unit Atlas.Common.Lsp.Status;

// Inhalt des Status-Befehls "atlas.server.status" (#28): Index, Speicher,
// letzter Indexlauf je Ordner und Antwortzeiten je Methode. Als JSON für
// Werkzeuge und als Markdown zum Anzeigen. Seit #492 auch die Größe der
// Caches auf der Platte, die letzte Aktualisierung je Ordner und die Zahl der
// Units mit ausgelagerten Verwendungen (Einstellungsseite des Plugins); seit
// #261 der Weg zum Compiler und, wenn keiner nutzbar ist, Grund und Ausweg.
// Seit #1356 (Fenster „Atlas-Server“, --timings, MCP get_server_status)
// zusätzlich, rückwärtsverträglich unter neuen Schlüsseln: Prozess (pid,
// Version, Start, Zustand), Speicher je Bereich gegen das Budget, Zeitprofil
// des letzten Prüflaufs, Warteschlange von Index und Prüfung und die
// Trefferquoten von Index-Cache und Syntaxbaum-Cache.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Statistics,
  Atlas.Common.Diagnostics.CheckProfile;

type
  TWorkspaceStatus = record
    Name: string;
    /// <summary>Dauer des letzten Indexlaufs; -1 = noch keiner fertig.</summary>
    LastIndexMs: Int64;
    Parsed: Integer;
    FromCache: Integer;
    Missing: Integer;
    /// <summary>Letzte Änderung am Index dieses Ordners (Aufbau, Speichern, Tipp-Pause); 0 = noch keine.</summary>
    LastUpdate: TDateTime;
    /// <summary>Cache-Dateien des Ordners (Projekt, gemeinsame Bibliothek); '' ohne.</summary>
    CacheFile: string;
    LibraryCacheFile: string;
    /// <summary>Größe der Cache-Dateien in Byte (#492).</summary>
    CacheBytes: Int64;
    LibraryCacheBytes: Int64;
    /// <summary>Projektwahl (#46): .dproj, geladene Konfiguration und Plattform ('' ohne Projekt), per
    /// selectBuild gewählt (auch gemerkt), aktives Projekt der IDE, per selectProject ausgewählt.</summary>
    Project: string;
    Config: string;
    Platform: string;
    BuildChosen: Boolean;
    Active: Boolean;
    Selected: Boolean;
    /// <summary>" · Debug/Win64 (gewählt) · aktiv in der IDE · ausgewählt"; '' ohne Projekt.</summary>
    function ProjectText: string;
  end;

  /// <summary>Speicher je Bereich in Byte (#1356), geschätzt außer Total.</summary>
  TServerMemory = record
    /// <summary>Symbole und uses der Projekt-Units.</summary>
    Symbols: Int64;
    /// <summary>Verwendungen, soweit nicht ausgelagert.</summary>
    Usages: Int64;
    /// <summary>Symbole und uses der Bibliotheks-Units.</summary>
    LibraryUnits: Int64;
    /// <summary>Gemeinsame Syntaxbäume der geöffneten Dokumente (TreeCache).</summary>
    TreeCache: Int64;
    /// <summary>Text der geöffneten Dokumente.</summary>
    Documents: Int64;
    /// <summary>Belegter Speicher des Prozesses (Heap); -1 = unbekannt.</summary>
    Total: Int64;
    /// <summary>Budget des Index; 0 = unbegrenzt.</summary>
    Budget: Int64;
    /// <summary>Total ohne die geschätzten Bereiche; 0, wenn die Schätzung darüber liegt oder Total unbekannt ist.
    /// </summary>
    function Rest: Int64;
    /// <summary>Summe der geschätzten Bereiche ohne Rest.</summary>
    function Estimated: Int64;
    /// <summary>Index (Symbole, Verwendungen, Bibliothek) über dem Budget bzw. schon verkleinert.</summary>
    function OverBudget(ACompactUnits, AOffloadedUnits: Integer): Boolean;
  end;

  /// <summary>Warteschlange der Aufbauten und der Projektprüfung (#1356).</summary>
  TServerQueue = record
    IndexWaiting: Integer;
    IndexRunning: Integer;
    CheckWaiting: Integer;
    CheckRunning: Integer;
    /// <summary>Längste Wartezeit über beide Schlangen.</summary>
    OldestWaitMs: Int64;
  end;

  TServerStatus = record
  public const
    StateLoading = 'loading';
    StateReady = 'ready';
    StateChecking = 'checking';
  public
    Units: Integer;
    Symbols: Integer;
    /// <summary>Belegter Speicher in Byte; -1 = unbekannt.</summary>
    MemoryBytes: Int64;
    /// <summary>Geschätzter Bedarf des Symbolindex in Byte (#185).</summary>
    IndexBytes: Int64;
    /// <summary>Kompakt gehaltene Units.</summary>
    CompactUnits: Integer;
    /// <summary>Units mit ausgelagerten Verwendungen (#492).</summary>
    OffloadedUnits: Integer;
    /// <summary>Alle Index-Caches auf der Platte in Byte, auch anderer Projekte (#492).</summary>
    DiskBytes: Int64;
    /// <summary>Budget des Index in Byte; 0 = unbegrenzt.</summary>
    BudgetBytes: Int64;
    /// <summary>Text der geöffneten Dokumente in Byte.</summary>
    DocumentBytes: Int64;
    Workspaces: TArray<TWorkspaceStatus>;
    Requests: TArray<TMethodStatistics>;
    /// <summary>Zeile zum Compiler (#261), z. B. „Compiler: nicht verfügbar (Starter Edition)“; '' = keine.</summary>
    Compiler: string;
    /// <summary>Gewählter Weg: "dcc", "ide", "off"; '' = noch nicht geprüft.</summary>
    CompilerBackend: string;
    /// <summary>Grund und Ausweg, wenn kein Compiler nutzbar ist; sonst ''.</summary>
    CompilerReason: string;
    /// <summary>Prozess (#1356): Kennung, Version, Start (Ortszeit), Laufzeit und Zustand (StateLoading, StateReady,
    /// StateChecking); ProcessId 0 = nicht erhoben (ältere Aufrufer).</summary>
    ProcessId: Cardinal;
    Version: string;
    Started: TDateTime;
    UptimeMs: Int64;
    State: string;
    Memory: TServerMemory;
    CheckRun: TCheckRunProfile;
    Queue: TServerQueue;
    /// <summary>Units aus dem Index-Cache in Prozent der geladenen; -1 ohne Indexlauf.</summary>
    IndexCacheHitPercent: Integer;
    /// <summary>Zugriffe auf den Syntaxbaum-Cache ohne neuen Parse in Prozent; -1 ohne Zugriff.</summary>
    TreeCacheHitPercent: Integer;
    TreeCacheTrees: Integer;
    /// <summary>Units aus dem Cache in Prozent aller Units der Workspaces; -1 ohne Indexlauf.</summary>
    class function CacheHitPercent(const AWorkspaces: TArray<TWorkspaceStatus>): Integer; static;
    /// <summary>Text zum Zustand: „lädt“, „bereit“, „prüft“.</summary>
    function StateText: string;
    /// <summary>Der Aufrufer übernimmt das Objekt; enthält zusätzlich "markdown".</summary>
    function ToJson: TJSONObject;
    function ToMarkdown: string;
  private
    procedure AppendDiagnostics(ABuilder: TStringBuilder);
  end;

const
  StatusCommand = 'atlas.server.status';
  /// <summary>Alle Index-Caches löschen und die Ordner neu indizieren (#492).</summary>
  ClearIndexCommand = 'atlas.server.clearIndex';

implementation

uses
  System.Generics.Collections,
  System.DateUtils;

/// <summary>ISO 8601 in UTC; '' für 0.</summary>
function DateText(AValue: TDateTime): string;
begin
  if AValue = 0 then
    Result := ''
  else
    Result := DateToISO8601(AValue, False);
end;

function MegaBytes(ABytes: Int64): string;
begin
  Result := FormatFloat('0.0', ABytes / (1024 * 1024), TFormatSettings.Invariant) + ' MB';
end;

{ TWorkspaceStatus }

function TWorkspaceStatus.ProjectText: string;
begin
  Result := '';
  if Project = '' then
    Exit;
  if (Config <> '') or (Platform <> '') then
    Result := ' · ' + Config + '/' + Platform;
  if BuildChosen then
    Result := Result + ' (gewählt)';
  if Active then
    Result := Result + ' · aktiv in der IDE';
  if Selected then
    Result := Result + ' · ausgewählt';
end;

{ TServerMemory }

function TServerMemory.Estimated: Int64;
begin
  Result := Symbols + Usages + LibraryUnits + TreeCache + Documents;
end;

function TServerMemory.Rest: Int64;
begin
  Result := 0;
  if Total > Estimated then
    Result := Total - Estimated;
end;

function TServerMemory.OverBudget(ACompactUnits, AOffloadedUnits: Integer): Boolean;
begin
  Result := (Budget > 0) and ((Symbols + Usages + LibraryUnits > Budget) or (ACompactUnits > 0) or
    (AOffloadedUnits > 0));
end;

{ TServerStatus }

class function TServerStatus.CacheHitPercent(const AWorkspaces: TArray<TWorkspaceStatus>): Integer;
var
  mWorkspace: TWorkspaceStatus;
  mLoaded, mCached: Int64;
begin
  mLoaded := 0;
  mCached := 0;
  for mWorkspace in AWorkspaces do
    if mWorkspace.LastIndexMs >= 0 then
    begin
      Inc(mLoaded, mWorkspace.Parsed + mWorkspace.FromCache);
      Inc(mCached, mWorkspace.FromCache);
    end;
  if mLoaded = 0 then
    Exit(-1);
  Result := Round(mCached * 100 / mLoaded);
end;

function TServerStatus.StateText: string;
begin
  if State = StateLoading then
    Result := 'lädt'
  else if State = StateChecking then
    Result := 'prüft'
  else
    Result := 'bereit';
end;

procedure TServerStatus.AppendDiagnostics(ABuilder: TStringBuilder);
var
  mProfile: string;
begin
  ABuilder.Append(#10).Append(Format('- Prozess %d, Version %s, läuft seit %d s, %s',
    [ProcessId, Version, UptimeMs div 1000, StateText])).Append(#10);
  ABuilder.Append(#10).Append('| Speicher | MB |').Append(#10);
  ABuilder.Append('|---|---:|').Append(#10);
  ABuilder.Append('| Symbole | ').Append(MegaBytes(Memory.Symbols)).Append(' |').Append(#10);
  ABuilder.Append('| Verwendungen | ').Append(MegaBytes(Memory.Usages)).Append(' |').Append(#10);
  ABuilder.Append('| Bibliotheks-Units | ').Append(MegaBytes(Memory.LibraryUnits)).Append(' |').Append(#10);
  ABuilder.Append('| Syntaxbaum-Cache | ').Append(MegaBytes(Memory.TreeCache)).Append(' |').Append(#10);
  ABuilder.Append('| Offene Dokumente | ').Append(MegaBytes(Memory.Documents)).Append(' |').Append(#10);
  ABuilder.Append('| Rest | ').Append(MegaBytes(Memory.Rest)).Append(' |').Append(#10);
  if Memory.Total >= 0 then
    ABuilder.Append('| Gesamt | ').Append(MegaBytes(Memory.Total)).Append(' |').Append(#10);
  if Memory.Budget > 0 then
    ABuilder.Append('| Budget des Index | ').Append(MegaBytes(Memory.Budget)).Append(' |').Append(#10);
  if Memory.OverBudget(CompactUnits, OffloadedUnits) then
    ABuilder.Append(#10).Append('Budget überschritten: Verwendungen werden ausgelagert.').Append(#10);
  ABuilder.Append(#10).Append(Format('- Warteschlange: Index %d wartend, %d laufend; Prüfung %d wartend, %d laufend; ' +
    'älteste Wartezeit %d ms', [Queue.IndexWaiting, Queue.IndexRunning, Queue.CheckWaiting, Queue.CheckRunning,
    Queue.OldestWaitMs])).Append(#10);
  ABuilder.Append('- Cache-Treffer: ');
  if IndexCacheHitPercent >= 0 then
    ABuilder.Append(Format('Index %d %%', [IndexCacheHitPercent]))
  else
    ABuilder.Append('Index –');
  if TreeCacheHitPercent >= 0 then
    ABuilder.Append(Format(', Syntaxbäume %d %% (%d im Speicher)', [TreeCacheHitPercent, TreeCacheTrees]))
  else
    ABuilder.Append(', Syntaxbäume –');
  ABuilder.Append(#10);
  mProfile := CheckRun.ToMarkdown;
  if mProfile <> '' then
    ABuilder.Append(#10).Append(mProfile);
end;

function TServerStatus.ToMarkdown: string;
var
  Builder: TStringBuilder;
  Workspace: TWorkspaceStatus;
  Request: TMethodStatistics;
begin
  Builder := TStringBuilder.Create;
  try
    Builder.Append('**Atlas**').Append(#10#10);
    Builder.Append(Format('- Index: %d Units, %d Symbole', [Units, Symbols])).Append(#10);
    if MemoryBytes >= 0 then
      Builder.Append('- Speicher: ').Append(MegaBytes(MemoryBytes)).Append(#10);
    Builder.Append('- davon Symbolindex: ').Append(MegaBytes(IndexBytes));
    if BudgetBytes > 0 then
      Builder.Append(' von ').Append(MegaBytes(BudgetBytes));
    if CompactUnits > 0 then
      Builder.Append(Format(', %d Units kompakt', [CompactUnits]));
    if OffloadedUnits > 0 then
      Builder.Append(Format(', Verwendungen von %d Units ausgelagert', [OffloadedUnits]));
    Builder.Append(#10);
    Builder.Append('- Caches auf der Platte: ').Append(MegaBytes(DiskBytes)).Append(#10);
    Builder.Append('- davon geöffnete Dokumente: ').Append(MegaBytes(DocumentBytes)).Append(#10);
    if Compiler <> '' then
    begin
      Builder.Append('- ').Append(Compiler).Append(#10);
      if CompilerReason <> '' then
        Builder.Append('  ').Append(CompilerReason).Append(#10);
    end;
    for Workspace in Workspaces do
      if Workspace.LastIndexMs < 0 then
        Builder.Append(Format('- %s%s: Index wird aufgebaut', [Workspace.Name, Workspace.ProjectText])).Append(#10)
      else
      begin
        Builder.Append(Format('- %s%s: letzter Indexlauf %d ms (%d neu eingelesen, %d aus dem Cache, %d fehlen)',
          [Workspace.Name, Workspace.ProjectText, Workspace.LastIndexMs, Workspace.Parsed, Workspace.FromCache,
          Workspace.Missing]));
        if Workspace.LastUpdate <> 0 then
          Builder.Append(', aktualisiert ').Append(FormatDateTime('dd.mm.yyyy hh":"nn":"ss', Workspace.LastUpdate));
        Builder.Append(', Cache ').Append(MegaBytes(Workspace.CacheBytes + Workspace.LibraryCacheBytes));
        Builder.Append(#10);
      end;
    if ProcessId <> 0 then
      AppendDiagnostics(Builder);
    if Length(Requests) > 0 then
    begin
      Builder.Append(#10).Append('| Methode | Anzahl | Mittel ms | Max ms | Fehler |').Append(#10);
      Builder.Append('|---|---:|---:|---:|---:|').Append(#10);
      for Request in Requests do
        Builder.Append(Format('| %s | %d | %s | %d | %d |', [Request.Method, Request.Count,
          FormatFloat('0.0', Request.AverageMs, TFormatSettings.Invariant), Request.MaxMs, Request.Failed])).Append(#10);
    end;
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

function TServerStatus.ToJson: TJSONObject;
var
  Items: TJSONArray;
  Item: TJSONObject;
  Workspace: TWorkspaceStatus;
  Request: TMethodStatistics;
begin
  Result := TJSONObject.Create;
  Result.AddPair('units', TJSONNumber.Create(Units));
  Result.AddPair('symbols', TJSONNumber.Create(Symbols));
  Result.AddPair('memoryBytes', TJSONNumber.Create(MemoryBytes));
  Result.AddPair('indexBytes', TJSONNumber.Create(IndexBytes));
  Result.AddPair('compactUnits', TJSONNumber.Create(CompactUnits));
  Result.AddPair('offloadedUnits', TJSONNumber.Create(OffloadedUnits));
  Result.AddPair('diskBytes', TJSONNumber.Create(DiskBytes));
  Result.AddPair('budgetBytes', TJSONNumber.Create(BudgetBytes));
  Result.AddPair('documentBytes', TJSONNumber.Create(DocumentBytes));
  Items := TJSONArray.Create;
  for Workspace in Workspaces do
  begin
    Item := TJSONObject.Create;
    Item.AddPair('name', Workspace.Name);
    Item.AddPair('lastIndexMs', TJSONNumber.Create(Workspace.LastIndexMs));
    Item.AddPair('parsed', TJSONNumber.Create(Workspace.Parsed));
    Item.AddPair('fromCache', TJSONNumber.Create(Workspace.FromCache));
    Item.AddPair('missing', TJSONNumber.Create(Workspace.Missing));
    Item.AddPair('lastUpdate', DateText(Workspace.LastUpdate));
    Item.AddPair('cacheBytes', TJSONNumber.Create(Workspace.CacheBytes));
    Item.AddPair('libraryCacheBytes', TJSONNumber.Create(Workspace.LibraryCacheBytes));
    if Workspace.Project <> '' then
    begin
      Item.AddPair('project', Workspace.Project);
      Item.AddPair('config', Workspace.Config);
      Item.AddPair('platform', Workspace.Platform);
      Item.AddPair('buildChosen', TJSONBool.Create(Workspace.BuildChosen));
      Item.AddPair('active', TJSONBool.Create(Workspace.Active));
      Item.AddPair('selected', TJSONBool.Create(Workspace.Selected));
    end;
    Items.AddElement(Item);
  end;
  Result.AddPair('workspaces', Items);
  Items := TJSONArray.Create;
  for Request in Requests do
  begin
    Item := TJSONObject.Create;
    Item.AddPair('method', Request.Method);
    Item.AddPair('count', TJSONNumber.Create(Request.Count));
    Item.AddPair('averageMs', TJSONNumber.Create(Request.AverageMs));
    Item.AddPair('maxMs', TJSONNumber.Create(Request.MaxMs));
    Item.AddPair('failed', TJSONNumber.Create(Request.Failed));
    Items.AddElement(Item);
  end;
  Result.AddPair('requests', Items);
  if Compiler <> '' then
  begin
    Item := TJSONObject.Create;
    Item.AddPair('status', Compiler);
    Item.AddPair('backend', CompilerBackend);
    Item.AddPair('reason', CompilerReason);
    Result.AddPair('compiler', Item);
  end;
  if ProcessId <> 0 then
  begin
    Item := TJSONObject.Create;
    Item.AddPair('pid', TJSONNumber.Create(ProcessId));
    Item.AddPair('version', Version);
    Item.AddPair('started', DateText(Started));
    Item.AddPair('uptimeMs', TJSONNumber.Create(UptimeMs));
    Item.AddPair('state', State);
    Result.AddPair('process', Item);
    Item := TJSONObject.Create;
    Item.AddPair('symbols', TJSONNumber.Create(Memory.Symbols));
    Item.AddPair('usages', TJSONNumber.Create(Memory.Usages));
    Item.AddPair('libraryUnits', TJSONNumber.Create(Memory.LibraryUnits));
    Item.AddPair('treeCache', TJSONNumber.Create(Memory.TreeCache));
    Item.AddPair('documents', TJSONNumber.Create(Memory.Documents));
    Item.AddPair('rest', TJSONNumber.Create(Memory.Rest));
    Item.AddPair('total', TJSONNumber.Create(Memory.Total));
    Item.AddPair('budget', TJSONNumber.Create(Memory.Budget));
    Item.AddPair('overBudget', TJSONBool.Create(Memory.OverBudget(CompactUnits, OffloadedUnits)));
    Result.AddPair('memory', Item);
    Result.AddPair('checkRun', CheckRun.ToJson);
    Item := TJSONObject.Create;
    Item.AddPair('indexWaiting', TJSONNumber.Create(Queue.IndexWaiting));
    Item.AddPair('indexRunning', TJSONNumber.Create(Queue.IndexRunning));
    Item.AddPair('checkWaiting', TJSONNumber.Create(Queue.CheckWaiting));
    Item.AddPair('checkRunning', TJSONNumber.Create(Queue.CheckRunning));
    Item.AddPair('oldestWaitMs', TJSONNumber.Create(Queue.OldestWaitMs));
    Result.AddPair('queue', Item);
    Item := TJSONObject.Create;
    Item.AddPair('index', TJSONNumber.Create(IndexCacheHitPercent));
    Item.AddPair('trees', TJSONNumber.Create(TreeCacheHitPercent));
    Item.AddPair('treeCount', TJSONNumber.Create(TreeCacheTrees));
    Result.AddPair('cacheHits', Item);
  end;
  Result.AddPair('markdown', ToMarkdown);
end;

end.
