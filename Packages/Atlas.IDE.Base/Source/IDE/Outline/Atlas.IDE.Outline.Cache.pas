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
// Fehler des Aufrufers: Der alte Stand bleibt, später neu versuchen. Die
// Ausnahme darf nicht bis in den Takt von Brotkrumen und mitlaufendem Kopf
// laufen, sonst zählte sie dort für die Absturzsicherung.
// Während einer Abfrage (Sitzung holen, Server starten, auf documentSymbol
// warten) kann der Manager alle Stände vergessen oder ein weiterer Takt
// einsteigen; Entfernen und Leeren hält TAtlasOutlineLoadGuard bis zum Ende
// der Abfrage zurück, damit der ladende Eintrag gültig bleibt.
// documentSymbol selbst läuft im Hintergrund (TAtlasBackgroundRequest),
// höchstens eine Anfrage zugleich; die Antwort gilt nur für den Eintrag und
// die Version, für die gefragt wurde. Der Hauptthread wartet nie auf die
// Antwort, sonst hinge jeder Reiterwechsel bis zur Zeitgrenze.
// Mit WithInterfaces holt derselbe Abruf danach atlas.server.interfaceMethods
// (#1785, Interface-Marke der Brotkrumen); ohne Antwort (älterer Server,
// Zeitgrenze) bleibt die Liste leer, die Gliederung gilt trotzdem. Wird die
// Marke eingeschaltet, fragt der nächste Takt einmal neu.
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  ToolsAPI,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Outline.Model,
  Atlas.Core.Outline.Interfaces;

type
{$SCOPEDENUMS ON}
  TAtlasOutlineStatus = (NoFile, NoServer, Waiting, Ready);
{$SCOPEDENUMS OFF}

  TAtlasOutlineSnapshot = record
    FileName: string;
    Nodes: TAtlasOutlineNodes;
    /// <summary>Text, zu dem die Knoten gehören.</summary>
    Text: string;
    /// <summary>Erfüllte Interface-Methoden (#1785); leer ohne WithInterfaces.</summary>
    Interfaces: TAtlasInterfaceMethods;
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
    /// <summary>Auch die erfüllten Interface-Methoden holen (#1785).</summary>
    class var WithInterfaces: Boolean;
  end;

implementation

uses
  Winapi.Windows,
  System.JSON,
  System.Generics.Collections,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Outline.LoadGuard,
  Atlas.Core.Lsp.BackgroundRequest,
  Atlas.Core.Lsp.Client,
  Atlas.IDE.Foundation.EditorSnapshot,
  Atlas.IDE.Foundation.CodeView;

const
  /// <summary>Tipppause, nach der neu gefragt wird.</summary>
  cPauseMs = 600;
  /// <summary>Ohne Server oder nach Zeitgrenze: so oft neu versuchen.</summary>
  cRetryMs = 2000;
  cRequestTimeoutMs = 5000;
  cInterfacesCommand = 'atlas.server.interfaceMethods';
  /// <summary>So viele Dateien bleiben gemerkt.</summary>
  cKeptFiles = 8;
  cPascalExtensions: array[0..4] of string = ('.pas', '.dpr', '.dpk', '.inc', '.pp');

type
  TEntry = class
  public
    FileName: string;
    Nodes: TAtlasOutlineNodes;
    Text: string;
    Interfaces: TAtlasInterfaceMethods;
    /// <summary>Der letzte Abruf hat die Interface-Methoden mitgeholt.</summary>
    WithInterfaces: Boolean;
    Version: Cardinal;
    Stamp: Cardinal;
    Loaded: Boolean;
    NoServer: Boolean;
    PendingVersion: Cardinal;
    PendingSince: UInt64;
    RetryAt: UInt64;
    Used: UInt64;
  end;

  /// <summary>Antwort eines Abrufs für den Eintrag Key in der Version Version; Ok ohne Zeitgrenze und Fehler.
  /// </summary>
  TLoadAnswer = record
    Key: string;
    Text: string;
    Version: Cardinal;
    Ok: Boolean;
    Nodes: TAtlasOutlineNodes;
    Interfaces: TAtlasInterfaceMethods;
    WithInterfaces: Boolean;
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
  mOldest: string;
  mPair: TPair<string, TEntry>;
  mTime: UInt64;
begin
  while Entries.Count > cKeptFiles do
  begin
    mOldest := '';
    mTime := High(UInt64);
    for mPair in Entries do
    begin
      if mPair.Value.Used < mTime then
      begin
        mTime := mPair.Value.Used;
        mOldest := mPair.Key;
      end;
    end;
    Entries.Remove(mOldest);
  end;
end;

/// <summary>Antwort auf Load im Hauptthread: gilt nur, solange der Eintrag besteht und noch dieselbe Version hat.
/// </summary>
procedure Loaded(const AAnswer: TLoadAnswer);
var
  mEntry: TEntry;
begin
  if (Entries = nil) or not Entries.TryGetValue(AAnswer.Key, mEntry) or (mEntry.Version <> AAnswer.Version) then
  begin
    Exit;
  end;
  if not AAnswer.Ok then
  begin
    // Zeitgrenze oder Fehler: der alte Stand bleibt, später neu versuchen.
    mEntry.Loaded := False;
    mEntry.RetryAt := GetTickCount64 + cRetryMs;
    Exit;
  end;
  mEntry.Loaded := True;
  // Auch beim Syntaxfehler gemerkt: sonst fragte jeder Takt erneut nach den Interface-Methoden.
  mEntry.WithInterfaces := AAnswer.WithInterfaces;
  // Syntaxfehler: Ohne Knoten bleibt der letzte gültige Stand.
  if (Length(AAnswer.Nodes) = 0) and (Length(mEntry.Nodes) > 0) then
  begin
    Exit;
  end;
  mEntry.Nodes := AAnswer.Nodes;
  mEntry.Text := AAnswer.Text;
  mEntry.Interfaces := AAnswer.Interfaces;
  Inc(LastStamp);
  mEntry.Stamp := LastStamp;
end;

/// <summary>Erfüllte Interface-Methoden der Datei (#1785), im Hintergrund; leer ohne Antwort.</summary>
function FetchInterfaces(ASession: TLspSession; const AFileName: string): TAtlasInterfaceMethods;
var
  mArguments: TJSONArray;
  mArgumentsJson: string;
  mResponse: TJSONValue;
begin
  Result := nil;
  mArguments := TJSONArray.Create;
  try
    mArguments.Add(TLspSession.PathToUri(AFileName));
    mArgumentsJson := mArguments.ToJSON;
  finally
    mArguments.Free;
  end;
  try
    mResponse := ASession.RunCommand(cInterfacesCommand, mArgumentsJson, cRequestTimeoutMs);
  except
    // Älterer Server ohne den Befehl oder Zeitgrenze: ohne Marke weiter.
    on ELspClientError do
      Exit;
  end;
  try
    Result := TAtlasOutlineInterfaces.FromJson(mResponse);
  finally
    mResponse.Free;
  end;
end;

procedure Load(AEntry: TEntry; const ASnapshot: TAtlasEditorSnapshot);
var
  mSession: TLspSession;
  mFileName: string;
  mAnswer: TLoadAnswer;
begin
  AEntry.Version := ASnapshot.Version;
  AEntry.PendingVersion := ASnapshot.Version;
  // Bis die Antwort da ist (oder ausbleibt), nicht neu fragen.
  AEntry.Loaded := False;
  AEntry.RetryAt := GetTickCount64 + cRetryMs;
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
  mAnswer := Default(TLoadAnswer);
  mAnswer.Key := Key(mFileName);
  mAnswer.Text := ASnapshot.Text;
  mAnswer.Version := ASnapshot.Version;
  mAnswer.WithInterfaces := TAtlasIdeOutlineCache.WithInterfaces;
  Request.Start(
    procedure
    var
      mResponse: TJSONValue;
    begin
      mResponse := mSession.DocumentSymbolTree(mFileName, cRequestTimeoutMs);
      try
        mAnswer.Ok := mResponse <> nil;
        if mAnswer.Ok then
        begin
          mAnswer.Nodes := TAtlasOutline.FromJson(mResponse);
        end;
      finally
        mResponse.Free;
      end;
      if mAnswer.Ok and mAnswer.WithInterfaces then
      begin
        mAnswer.Interfaces := FetchInterfaces(mSession, mFileName);
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
      mAnswer.Ok := AOk and mAnswer.Ok;
      Loaded(mAnswer);
    end);
end;

/// <summary>Load unter dem Wächter; danach Vorgemerktes nachholen. Der Eintrag kann danach freigegeben sein.</summary>
procedure GuardedLoad(AEntry: TEntry; const ASnapshot: TAtlasEditorSnapshot);
var
  mClear: Boolean;
  mKeys: TArray<string>;
  mPending: string;
begin
  Guard.Enter;
  try
    Load(AEntry, ASnapshot);
  finally
    if Guard.Leave(mClear, mKeys) and (Entries <> nil) then
    begin
      if mClear then
      begin
        Entries.Clear;
      end
      else
      begin
        for mPending in mKeys do
        begin
          Entries.Remove(mPending);
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
  mExtension: string;
begin
  for mExtension in cPascalExtensions do
  begin
    if SameText(ExtractFileExt(AFileName), mExtension) then
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
  mEntry: TEntry;
begin
  if Guard.Busy or Request.Busy then
  begin
    Exit;
  end;
  if not Entries.TryGetValue(Key(AFileName), mEntry) then
  begin
    mEntry := TEntry.Create;
    mEntry.FileName := AFileName;
    Entries.Add(Key(AFileName), mEntry);
    mEntry.Used := AMoment;
    TrimEntries;
    GuardedLoad(mEntry, ASnapshot);
  end
  else if ASnapshot.Version = mEntry.Version then
  begin
    // Marke eingeschaltet (#1785): einmal mit Interface-Methoden neu fragen.
    if (not mEntry.Loaded and (AMoment >= mEntry.RetryAt)) or
      (mEntry.Loaded and TAtlasIdeOutlineCache.WithInterfaces and not mEntry.WithInterfaces) then
    begin
      GuardedLoad(mEntry, ASnapshot);
    end;
  end
  // Erst nach einer Tipppause neu fragen.
  else if ASnapshot.Version <> mEntry.PendingVersion then
  begin
    mEntry.PendingVersion := ASnapshot.Version;
    mEntry.PendingSince := AMoment;
  end
  else if AMoment - mEntry.PendingSince >= cPauseMs then
  begin
    GuardedLoad(mEntry, ASnapshot);
  end;
end;

/// <summary>Stand des Eintrags AEntry in AResult.</summary>
procedure FillSnapshot(AEntry: TEntry; var AResult: TAtlasOutlineSnapshot);
begin
  AResult.Nodes := AEntry.Nodes;
  AResult.Text := AEntry.Text;
  AResult.Interfaces := AEntry.Interfaces;
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
  mEntry: TEntry;
  mFileName: string;
  mMoment: UInt64;
begin
  Result := Default(TAtlasOutlineSnapshot);
  Result.Status := TAtlasOutlineStatus.NoFile;
  if (Entries = nil) or (AView = nil) or (AView.Buffer = nil) or not IsPascal(AView.Buffer.FileName) then
  begin
    Exit;
  end;
  mFileName := AView.Buffer.FileName;
  Result.FileName := mFileName;
  Result.Status := TAtlasOutlineStatus.Waiting;
  mMoment := GetTickCount64;
  // Im Designer und auf der Willkommensseite nicht neu laden: Der Code ist nicht zu sehen; es gilt der letzte Stand.
  if TAtlasIdeCodeView.InFront then
  begin
    UpdateEntry(mFileName, TAtlasEditorSnapshots.Get(AView), mMoment);
  end;
  // Nach dem Laden neu nachschlagen: Vorgemerktes Leeren kann den Eintrag freigegeben haben.
  if (Entries = nil) or not Entries.TryGetValue(Key(mFileName), mEntry) then
  begin
    Exit;
  end;
  mEntry.Used := mMoment;
  FillSnapshot(mEntry, Result);
end;

end.
