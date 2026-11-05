unit Atlas.IDE.Outline.Cache;

// Gemeinsamer Stand der Gliederung je Datei für das Gliederungsfenster (#537)
// und die Brotkrumenleiste (#590): Refresh gleicht den Puffer der aktiven
// Ansicht mit dem Server ab und holt textDocument/documentSymbol, aber nur
// beim ersten Mal, nach einer Tipppause (neue Version aus
// TAtlasEditorSnapshots) oder nach einem Fehlschlag in Abständen. Caret-
// Bewegung löst nie eine Anfrage aus. Bleibt die Antwort leer, obwohl es
// vorher Knoten gab (Syntaxfehler), bleibt der letzte gültige Stand. Die
// letzten Dateien bleiben gemerkt, ein Wechsel zurück fragt nicht neu.
// Antwortet der Server nicht rechtzeitig (ELspClientError), ist das kein
// Fehler des Aufrufers: Der alte Stand bleibt, später neu versuchen. Früher
// lief die Ausnahme bis in den Takt von Brotkrumen und mitlaufendem Kopf und
// zählte dort für die Absturzsicherung.
// Während einer Abfrage (Sitzung holen, Server starten, auf documentSymbol
// warten) kann der Manager alle Stände vergessen oder ein weiterer Takt
// einsteigen; Entfernen und Leeren hält TAtlasOutlineLoadGuard bis zum Ende
// der Abfrage zurück, damit der ladende Eintrag gültig bleibt.
// documentSymbol selbst läuft im Hintergrund (TAtlasBackgroundRequest),
// höchstens eine Anfrage zugleich; die Antwort gilt nur für den Eintrag und
// die Version, für die gefragt wurde. Früher wartete der Hauptthread bis zu
// 2 s (2.0-stable: „keine Antwort vom Server“ bei jedem Reiterwechsel).
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  ToolsAPI,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Outline.Model;

type
{$SCOPEDENUMS ON}
  TAtlasOutlineStatus = (NoFile, NoServer, Waiting, Ready);
{$SCOPEDENUMS OFF}

  TAtlasOutlineSnapshot = record
    FileName: string;
    Nodes: TAtlasOutlineNodes;
    /// <summary>Text, zu dem die Knoten gehören.</summary>
    Text: string;
    /// <summary>Steigt bei jedem neuen Stand (über alle Dateien eindeutig).</summary>
    Stamp: Cardinal;
    Status: TAtlasOutlineStatus;
  end;

  TAtlasIdeOutlineCache = class
  public
    class procedure Install(const ASessionOf: TFunc<TLspSession>); static;
    class procedure Uninstall; static;
    /// <summary>Stand für AView; fragt den Server nur, wenn nötig (siehe oben).</summary>
    class function Refresh(const AView: IOTAEditView): TAtlasOutlineSnapshot; static;
    /// <summary>Gemerkten Stand der Datei vergessen (nächstes Refresh fragt sofort).</summary>
    class procedure Invalidate(const AFileName: string); static;
    /// <summary>Alle gemerkten Stände vergessen, z. B. nach einem Wechsel von Plattform oder Konfiguration:
    /// Der Server baut den Baum dann aus anderen {$IFDEF}-Zweigen (#845).</summary>
    class procedure InvalidateAll; static;
    /// <summary>Pascal-Quelltext (.pas, .dpr, .dpk, .inc, .pp)?</summary>
    class function IsPascal(const AFileName: string): Boolean; static;
  end;

implementation

uses
  Winapi.Windows,
  System.JSON,
  System.Generics.Collections,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Outline.LoadGuard,
  Atlas.Core.Lsp.BackgroundRequest,
  Atlas.IDE.Foundation.EditorSnapshot;

const
  /// <summary>Tipppause, nach der neu gefragt wird.</summary>
  PauseMs = 600;
  /// <summary>Ohne Server oder nach Zeitgrenze: so oft neu versuchen.</summary>
  RetryMs = 2000;
  RequestTimeoutMs = 5000;
  /// <summary>So viele Dateien bleiben gemerkt.</summary>
  KeptFiles = 8;
  PascalExtensions: array[0..4] of string = ('.pas', '.dpr', '.dpk', '.inc', '.pp');

type
  TEntry = class
  public
    FileName: string;
    Nodes: TAtlasOutlineNodes;
    Text: string;
    Version: Cardinal;
    Stamp: Cardinal;
    Loaded: Boolean;
    NoServer: Boolean;
    PendingVersion: Cardinal;
    PendingSince: UInt64;
    RetryAt: UInt64;
    Used: UInt64;
  end;

var
  SessionOf: TFunc<TLspSession>;
  Entries: TObjectDictionary<string, TEntry>;
  Guard: TAtlasOutlineLoadGuard;
  Request: TAtlasBackgroundRequest;
  LastStamp: Cardinal;

function Key(const AFileName: string): string;
begin
  Result := AnsiLowerCase(AFileName);
end;

procedure TrimEntries;
var
  Oldest: string;
  Pair: TPair<string, TEntry>;
  Time: UInt64;
begin
  while Entries.Count > KeptFiles do
  begin
    Oldest := '';
    Time := High(UInt64);
    for Pair in Entries do
    begin
      if Pair.Value.Used < Time then
      begin
        Time := Pair.Value.Used;
        Oldest := Pair.Key;
      end;
    end;
    Entries.Remove(Oldest);
  end;
end;

/// <summary>Antwort auf Load im Hauptthread: gilt nur, solange der Eintrag besteht und noch dieselbe Version hat.
/// </summary>
procedure Loaded(const AKey, AText: string; AVersion: Cardinal; AOk: Boolean; const ANodes: TAtlasOutlineNodes);
var
  mEntry: TEntry;
begin
  if (Entries = nil) or not Entries.TryGetValue(AKey, mEntry) or (mEntry.Version <> AVersion) then
  begin
    Exit;
  end;
  if not AOk then
  begin
    // Zeitgrenze oder Fehler: der alte Stand bleibt, später neu versuchen.
    mEntry.Loaded := False;
    mEntry.RetryAt := GetTickCount64 + RetryMs;
    Exit;
  end;
  mEntry.Loaded := True;
  // Syntaxfehler: Ohne Knoten bleibt der letzte gültige Stand.
  if (Length(ANodes) = 0) and (Length(mEntry.Nodes) > 0) then
  begin
    Exit;
  end;
  mEntry.Nodes := ANodes;
  mEntry.Text := AText;
  Inc(LastStamp);
  mEntry.Stamp := LastStamp;
end;

procedure Load(AEntry: TEntry; const ASnapshot: TAtlasEditorSnapshot);
var
  mSession: TLspSession;
  mFileName, mKey, mText: string;
  mVersion: Cardinal;
  mNodes: TAtlasOutlineNodes;
  mAnswered: Boolean;
begin
  AEntry.Version := ASnapshot.Version;
  AEntry.PendingVersion := ASnapshot.Version;
  // Bis die Antwort da ist (oder ausbleibt), nicht neu fragen.
  AEntry.Loaded := False;
  AEntry.RetryAt := GetTickCount64 + RetryMs;
  mSession := nil;
  // Kann den Server starten und die Projektkontexte abgleichen (InvalidateAll); der Wächter hält das zurück.
  if Assigned(SessionOf) then
  begin
    mSession := SessionOf();
  end;
  AEntry.NoServer := mSession = nil;
  if mSession = nil then
  begin
    Exit;
  end;
  // Im Hauptthread: Die Sitzung führt ihre Dokumentstände nicht threadsicher.
  mSession.Sync(AEntry.FileName, ASnapshot.Text);
  mFileName := AEntry.FileName;
  mKey := Key(mFileName);
  mText := ASnapshot.Text;
  mVersion := ASnapshot.Version;
  mNodes := nil;
  mAnswered := False;
  Request.Start(
    procedure
    var
      mResponse: TJSONValue;
    begin
      mResponse := mSession.DocumentSymbolTree(mFileName, RequestTimeoutMs);
      try
        mAnswered := mResponse <> nil;
        if mAnswered then
        begin
          mNodes := TAtlasOutline.FromJson(mResponse);
        end;
      finally
        mResponse.Free;
      end;
    end,
    procedure(AOk: Boolean; const AError: string)
    begin
      // Zeitgrenze, Fehlerantwort oder beendete Verbindung: wie keine Antwort.
      if AError <> '' then
      begin
        TAtlasGuard.Log('Gliederung: keine Antwort vom Server (' + TAtlasGuard.MessageText(AError) +
          '); alter Stand bleibt');
      end;
      Loaded(mKey, mText, mVersion, AOk and mAnswered, mNodes);
    end);
end;

/// <summary>Load unter dem Wächter; danach Vorgemerktes nachholen. Der Eintrag kann danach freigegeben sein.</summary>
procedure GuardedLoad(AEntry: TEntry; const ASnapshot: TAtlasEditorSnapshot);
var
  Clear: Boolean;
  Keys: TArray<string>;
  Pending: string;
begin
  Guard.Enter;
  try
    Load(AEntry, ASnapshot);
  finally
    if Guard.Leave(Clear, Keys) and (Entries <> nil) then
    begin
      if Clear then
      begin
        Entries.Clear;
      end
      else
      begin
        for Pending in Keys do
        begin
          Entries.Remove(Pending);
        end;
      end;
    end;
  end;
end;

{ TAtlasIdeOutlineCache }

class procedure TAtlasIdeOutlineCache.Install(const ASessionOf: TFunc<TLspSession>);
begin
  SessionOf := ASessionOf;
  if Entries = nil then
  begin
    Entries := TObjectDictionary<string, TEntry>.Create([doOwnsValues]);
  end;
  if Guard = nil then
  begin
    Guard := TAtlasOutlineLoadGuard.Create;
  end;
  if Request = nil then
  begin
    Request := TAtlasBackgroundRequest.Create(TAtlasFeature.Outline);
  end;
end;

class procedure TAtlasIdeOutlineCache.Uninstall;
begin
  SessionOf := nil;
  // Laufende Anfrage abwarten; ihre Antwort verfällt.
  FreeAndNil(Request);
  FreeAndNil(Entries);
  FreeAndNil(Guard);
end;

class function TAtlasIdeOutlineCache.IsPascal(const AFileName: string): Boolean;
var
  Extension: string;
begin
  for Extension in PascalExtensions do
  begin
    if SameText(ExtractFileExt(AFileName), Extension) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class procedure TAtlasIdeOutlineCache.Invalidate(const AFileName: string);
begin
  if (Entries <> nil) and Guard.Remove(Key(AFileName)) then
  begin
    Entries.Remove(Key(AFileName));
  end;
end;

class procedure TAtlasIdeOutlineCache.InvalidateAll;
begin
  if (Entries <> nil) and Guard.ClearAll then
  begin
    Entries.Clear;
  end;
end;

/// <summary>Eintrag von AFileName zum Stand ASnapshot laden, wenn nötig: neu, nach einer Tipppause oder nach
/// einem Fehlschlag. Ein Takt mitten in einer Abfrage (Nachrichten beim Warten) lädt nichts.</summary>
procedure UpdateEntry(const AFileName: string; const ASnapshot: TAtlasEditorSnapshot; AMoment: UInt64);
var
  Entry: TEntry;
begin
  if Guard.Busy or Request.Busy then
  begin
    Exit;
  end;
  if not Entries.TryGetValue(Key(AFileName), Entry) then
  begin
    Entry := TEntry.Create;
    Entry.FileName := AFileName;
    Entries.Add(Key(AFileName), Entry);
    Entry.Used := AMoment;
    TrimEntries;
    GuardedLoad(Entry, ASnapshot);
  end
  else if ASnapshot.Version = Entry.Version then
  begin
    if not Entry.Loaded and (AMoment >= Entry.RetryAt) then
    begin
      GuardedLoad(Entry, ASnapshot);
    end;
  end
  // Erst nach einer Tipppause neu fragen.
  else if ASnapshot.Version <> Entry.PendingVersion then
  begin
    Entry.PendingVersion := ASnapshot.Version;
    Entry.PendingSince := AMoment;
  end
  else if AMoment - Entry.PendingSince >= PauseMs then
  begin
    GuardedLoad(Entry, ASnapshot);
  end;
end;

/// <summary>Stand des Eintrags AEntry in AResult.</summary>
procedure FillSnapshot(AEntry: TEntry; var AResult: TAtlasOutlineSnapshot);
begin
  AResult.Nodes := AEntry.Nodes;
  AResult.Text := AEntry.Text;
  AResult.Stamp := AEntry.Stamp;
  if AEntry.NoServer and (Length(AEntry.Nodes) = 0) then
  begin
    AResult.Status := TAtlasOutlineStatus.NoServer;
  end
  else if AEntry.Stamp = 0 then
  begin
    AResult.Status := TAtlasOutlineStatus.Waiting;
  end
  else
  begin
    AResult.Status := TAtlasOutlineStatus.Ready;
  end;
end;

class function TAtlasIdeOutlineCache.Refresh(const AView: IOTAEditView): TAtlasOutlineSnapshot;
var
  Entry: TEntry;
  FileName: string;
  Moment: UInt64;
begin
  Result := Default(TAtlasOutlineSnapshot);
  Result.Status := TAtlasOutlineStatus.NoFile;
  if (Entries = nil) or (AView = nil) or (AView.Buffer = nil) or not IsPascal(AView.Buffer.FileName) then
  begin
    Exit;
  end;
  FileName := AView.Buffer.FileName;
  Result.FileName := FileName;
  Result.Status := TAtlasOutlineStatus.Waiting;
  Moment := GetTickCount64;
  UpdateEntry(FileName, TAtlasEditorSnapshots.Get(AView), Moment);
  // Nach dem Laden neu nachschlagen: Vorgemerktes Leeren kann den Eintrag freigegeben haben.
  if (Entries = nil) or not Entries.TryGetValue(Key(FileName), Entry) then
  begin
    Exit;
  end;
  Entry.Used := Moment;
  FillSnapshot(Entry, Result);
end;

end.
