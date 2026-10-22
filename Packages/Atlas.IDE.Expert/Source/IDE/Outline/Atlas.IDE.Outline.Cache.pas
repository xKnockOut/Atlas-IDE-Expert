unit Atlas.IDE.Outline.Cache;

// Gemeinsamer Stand der Gliederung je Datei für das Gliederungsfenster (#537)
// und die Brotkrumenleiste (#590): Refresh gleicht den Puffer der aktiven
// Ansicht mit dem Server ab und holt textDocument/documentSymbol, aber nur
// beim ersten Mal, nach einer Tipppause (neue Version aus
// TAtlasEditorSnapshots) oder nach einem Fehlschlag in Abständen. Caret-
// Bewegung löst nie eine Anfrage aus. Bleibt die Antwort leer, obwohl es
// vorher Knoten gab (Syntaxfehler), bleibt der letzte gültige Stand. Die
// letzten Dateien bleiben gemerkt, ein Wechsel zurück fragt nicht neu.
// Während einer Abfrage (Sitzung holen, Server starten, auf documentSymbol
// warten) kann der Manager alle Stände vergessen oder ein weiterer Takt
// einsteigen; Entfernen und Leeren hält TAtlasOutlineLoadGuard bis zum Ende
// der Abfrage zurück, damit der ladende Eintrag gültig bleibt.
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
  Atlas.Core.Outline.LoadGuard,
  Atlas.IDE.Foundation.EditorSnapshot;

const
  /// <summary>Tipppause, nach der neu gefragt wird.</summary>
  PauseMs = 600;
  /// <summary>Ohne Server oder nach Zeitgrenze: so oft neu versuchen.</summary>
  RetryMs = 2000;
  RequestTimeoutMs = 2000;
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
      if Pair.Value.Used < Time then
      begin
        Time := Pair.Value.Used;
        Oldest := Pair.Key;
      end;
    Entries.Remove(Oldest);
  end;
end;

procedure Load(AEntry: TEntry; const ASnapshot: TAtlasEditorSnapshot);
var
  Session: TLspSession;
  Response: TJSONValue;
  Nodes: TAtlasOutlineNodes;
begin
  AEntry.Version := ASnapshot.Version;
  AEntry.PendingVersion := ASnapshot.Version;
  Session := nil;
  // Kann den Server starten und die Projektkontexte abgleichen (InvalidateAll); der Wächter hält das zurück.
  if Assigned(SessionOf) then
    Session := SessionOf();
  AEntry.NoServer := Session = nil;
  if Session = nil then
  begin
    AEntry.Loaded := False;
    AEntry.RetryAt := GetTickCount64 + RetryMs;
    Exit;
  end;
  Session.Sync(AEntry.FileName, ASnapshot.Text);
  Response := Session.DocumentSymbolTree(AEntry.FileName, RequestTimeoutMs);
  try
    if Response = nil then
    begin
      // Zeitgrenze oder Fehler: der alte Stand bleibt, später neu versuchen.
      AEntry.Loaded := False;
      AEntry.RetryAt := GetTickCount64 + RetryMs;
      Exit;
    end;
    AEntry.Loaded := True;
    Nodes := TAtlasOutline.FromJson(Response);
  finally
    Response.Free;
  end;
  // Syntaxfehler: Ohne Knoten bleibt der letzte gültige Stand.
  if (Length(Nodes) = 0) and (Length(AEntry.Nodes) > 0) then
    Exit;
  AEntry.Nodes := Nodes;
  AEntry.Text := ASnapshot.Text;
  Inc(LastStamp);
  AEntry.Stamp := LastStamp;
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
      if Clear then
        Entries.Clear
      else
        for Pending in Keys do
          Entries.Remove(Pending);
  end;
end;

{ TAtlasIdeOutlineCache }

class procedure TAtlasIdeOutlineCache.Install(const ASessionOf: TFunc<TLspSession>);
begin
  SessionOf := ASessionOf;
  if Entries = nil then
    Entries := TObjectDictionary<string, TEntry>.Create([doOwnsValues]);
  if Guard = nil then
    Guard := TAtlasOutlineLoadGuard.Create;
end;

class procedure TAtlasIdeOutlineCache.Uninstall;
begin
  SessionOf := nil;
  FreeAndNil(Entries);
  FreeAndNil(Guard);
end;

class function TAtlasIdeOutlineCache.IsPascal(const AFileName: string): Boolean;
var
  Extension: string;
begin
  for Extension in PascalExtensions do
    if SameText(ExtractFileExt(AFileName), Extension) then
      Exit(True);
  Result := False;
end;

class procedure TAtlasIdeOutlineCache.Invalidate(const AFileName: string);
begin
  if (Entries <> nil) and Guard.Remove(Key(AFileName)) then
    Entries.Remove(Key(AFileName));
end;

class procedure TAtlasIdeOutlineCache.InvalidateAll;
begin
  if (Entries <> nil) and Guard.ClearAll then
    Entries.Clear;
end;

class function TAtlasIdeOutlineCache.Refresh(const AView: IOTAEditView): TAtlasOutlineSnapshot;
var
  Entry: TEntry;
  Snapshot: TAtlasEditorSnapshot;
  FileName: string;
  Moment: UInt64;
begin
  Result := Default(TAtlasOutlineSnapshot);
  Result.Status := TAtlasOutlineStatus.NoFile;
  if (Entries = nil) or (AView = nil) or (AView.Buffer = nil) then
    Exit;
  FileName := AView.Buffer.FileName;
  if not IsPascal(FileName) then
    Exit;
  Result.FileName := FileName;
  Result.Status := TAtlasOutlineStatus.Waiting;
  Snapshot := TAtlasEditorSnapshots.Get(AView);
  Moment := GetTickCount64;
  // Ein Takt mitten in einer Abfrage (Nachrichten beim Warten): nur zeigen, was schon da ist.
  if Guard.Busy then
  begin
    if not Entries.TryGetValue(Key(FileName), Entry) then
      Exit;
  end
  else if not Entries.TryGetValue(Key(FileName), Entry) then
  begin
    Entry := TEntry.Create;
    Entry.FileName := FileName;
    Entries.Add(Key(FileName), Entry);
    Entry.Used := Moment;
    TrimEntries;
    GuardedLoad(Entry, Snapshot);
  end
  else if Snapshot.Version <> Entry.Version then
  begin
    // Erst nach einer Tipppause neu fragen.
    if Snapshot.Version <> Entry.PendingVersion then
    begin
      Entry.PendingVersion := Snapshot.Version;
      Entry.PendingSince := Moment;
    end
    else if Moment - Entry.PendingSince >= PauseMs then
      GuardedLoad(Entry, Snapshot);
  end
  else if not Entry.Loaded and (Moment >= Entry.RetryAt) then
    GuardedLoad(Entry, Snapshot);
  // Nach dem Laden neu nachschlagen: Vorgemerktes Leeren kann den Eintrag freigegeben haben.
  if (Entries = nil) or not Entries.TryGetValue(Key(FileName), Entry) then
    Exit;
  Entry.Used := Moment;
  Result.Nodes := Entry.Nodes;
  Result.Text := Entry.Text;
  Result.Stamp := Entry.Stamp;
  if Entry.NoServer and (Length(Entry.Nodes) = 0) then
    Result.Status := TAtlasOutlineStatus.NoServer
  else if Entry.Stamp = 0 then
    Result.Status := TAtlasOutlineStatus.Waiting
  else
    Result.Status := TAtlasOutlineStatus.Ready;
end;

end.
