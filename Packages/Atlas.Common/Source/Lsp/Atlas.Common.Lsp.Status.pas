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
// Seit #1478 liefert Mapped eine Kopie, in der jeder Name (Ordner, eigene
// Konfiguration, langsame Units) und jeder Pfad (Projekt, Caches) über eine
// Funktion läuft: für die Protokollzeile gekennzeichnet (TLogMarks), für den
// anonymen Status über den Anonymisierer des Servers.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Text.LogMarks,
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
    /// <summary>Kopie mit AMap auf Name, eigener Konfiguration (Name), Projekt und Caches (Pfad).</summary>
    function Mapped(const AMap: TLogMarkMap): TWorkspaceStatus;
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
    /// <summary>Inhalt der übersetzten Packages (.dcp), einmal je Prozess (TPackageCompiledFiles).</summary>
    Packages: Int64;
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
    /// <summary>Kopie, in der Namen und Pfade der Arbeitsbereiche und die Namen der langsamsten Units über AMap
    /// laufen (#1478).</summary>
    function Mapped(const AMap: TLogMarkMap): TServerStatus;
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
  System.DateUtils,
  Atlas.Text.Anonymize;

/// <summary>ISO 8601 in UTC; '' für 0.</summary>
function DateText(AValue: TDateTime): string;
begin
  if AValue = 0 then
  begin
    Result := '';
  end
  else
  begin
    Result := DateToISO8601(AValue, False);
  end;
end;

function MegaBytes(ABytes: Int64): string;
begin
  Result := FormatFloat('0.0', ABytes / (1024 * 1024), TFormatSettings.Invariant) + ' MB';
end;

{ TWorkspaceStatus }

/// <summary>AMap(AKind, AValue), leere Werte bleiben leer.</summary>
function MappedValue(const AMap: TLogMarkMap; AKind: TLogMarkKind; const AValue: string): string;
begin
  Result := AValue;
  if AValue <> '' then
  begin
    Result := AMap(AKind, AValue);
  end;
end;

function TWorkspaceStatus.Mapped(const AMap: TLogMarkMap): TWorkspaceStatus;
begin
  Result := Self;
  Result.Name := MappedValue(AMap, TLogMarkKind.Name, Name);
  Result.Project := MappedValue(AMap, TLogMarkKind.Path, Project);
  Result.CacheFile := MappedValue(AMap, TLogMarkKind.Path, CacheFile);
  Result.LibraryCacheFile := MappedValue(AMap, TLogMarkKind.Path, LibraryCacheFile);
  // Debug, Release und die Plattformen verraten nichts; eigene Konfigurationen tragen oft Kundennamen.
  if not TTextAnonymizer.IsKeyword(Config) then
  begin
    Result.Config := MappedValue(AMap, TLogMarkKind.Name, Config);
  end;
end;

function TServerStatus.Mapped(const AMap: TLogMarkMap): TServerStatus;
var
  mIndex: Integer;
  mMap: TLogMarkMap;
begin
  Result := Self;
  Result.Workspaces := Copy(Workspaces);
  for mIndex := 0 to High(Result.Workspaces) do
  begin
    Result.Workspaces[mIndex] := Workspaces[mIndex].Mapped(AMap);
  end;
  mMap := AMap;
  Result.CheckRun := CheckRun.Anonymized(
    function(const AName: string): string
    begin
      Result := MappedValue(mMap, TLogMarkKind.Name, AName);
    end);
end;

function TWorkspaceStatus.ProjectText: string;
begin
  Result := '';
  if Project = '' then
  begin
    Exit;
  end;
  if (Config <> '') or (Platform <> '') then
  begin
    Result := ' · ' + Config + '/' + Platform;
  end;
  if BuildChosen then
  begin
    Result := Result + ' (gewählt)';
  end;
  if Active then
  begin
    Result := Result + ' · aktiv in der IDE';
  end;
  if Selected then
  begin
    Result := Result + ' · ausgewählt';
  end;
end;

{ TServerMemory }

function TServerMemory.Estimated: Int64;
begin
  Result := Symbols + Usages + LibraryUnits + TreeCache + Documents + Packages;
end;

function TServerMemory.Rest: Int64;
begin
  Result := 0;
  if Total > Estimated then
  begin
    Result := Total - Estimated;
  end;
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
  begin
    if mWorkspace.LastIndexMs >= 0 then
    begin
      Inc(mLoaded, mWorkspace.Parsed + mWorkspace.FromCache);
      Inc(mCached, mWorkspace.FromCache);
    end;
  end;
  if mLoaded = 0 then
  begin
    Exit(-1);
  end;
  Result := Round(mCached * 100 / mLoaded);
end;

function TServerStatus.StateText: string;
begin
  if State = StateLoading then
  begin
    Result := 'lädt';
  end
  else if State = StateChecking then
  begin
    Result := 'prüft';
  end
  else
  begin
    Result := 'bereit';
  end;
end;

/// <summary>Zeile je Arbeitsbereich für TServerStatus.ToMarkdown.</summary>
procedure AppendWorkspaces(ABuilder: TStringBuilder; const AWorkspaces: TArray<TWorkspaceStatus>);
var
  mWorkspace: TWorkspaceStatus;
begin
  for mWorkspace in AWorkspaces do
  begin
    if mWorkspace.LastIndexMs < 0 then
    begin
      ABuilder.Append(Format('- %s%s: Index wird aufgebaut', [mWorkspace.Name, mWorkspace.ProjectText])).Append(#10);
      Continue;
    end;
    ABuilder.Append(Format('- %s%s: letzter Indexlauf %d ms (%d neu eingelesen, %d aus dem Cache, %d fehlen)',
      [mWorkspace.Name, mWorkspace.ProjectText, mWorkspace.LastIndexMs, mWorkspace.Parsed, mWorkspace.FromCache,
      mWorkspace.Missing]));
    if mWorkspace.LastUpdate <> 0 then
    begin
      ABuilder.Append(', aktualisiert ').Append(FormatDateTime('dd.mm.yyyy hh":"nn":"ss', mWorkspace.LastUpdate));
    end;
    ABuilder.Append(', Cache ').Append(MegaBytes(mWorkspace.CacheBytes + mWorkspace.LibraryCacheBytes));
    ABuilder.Append(#10);
  end;
end;

/// <summary>Tabelle der Anfragen für TServerStatus.ToMarkdown; nichts ohne Anfragen.</summary>
procedure AppendRequests(ABuilder: TStringBuilder; const ARequests: TArray<TMethodStatistics>);
var
  mRequest: TMethodStatistics;
begin
  if Length(ARequests) = 0 then
  begin
    Exit;
  end;
  ABuilder.Append(#10).Append('| Methode | Anzahl | Mittel ms | Max ms | Fehler |').Append(#10);
  ABuilder.Append('|---|---:|---:|---:|---:|').Append(#10);
  for mRequest in ARequests do
  begin
    ABuilder.Append(Format('| %s | %d | %s | %d | %d |', [mRequest.Method, mRequest.Count,
      FormatFloat('0.0', mRequest.AverageMs, TFormatSettings.Invariant), mRequest.MaxMs, mRequest.Failed])).Append(#10);
  end;
end;

function WorkspacesJson(const AWorkspaces: TArray<TWorkspaceStatus>): TJSONArray;
var
  mWorkspace: TWorkspaceStatus;
  mItem: TJSONObject;
begin
  Result := TJSONArray.Create;
  for mWorkspace in AWorkspaces do
  begin
    mItem := TJSONObject.Create;
    mItem.AddPair('name', mWorkspace.Name);
    mItem.AddPair('lastIndexMs', TJSONNumber.Create(mWorkspace.LastIndexMs));
    mItem.AddPair('parsed', TJSONNumber.Create(mWorkspace.Parsed));
    mItem.AddPair('fromCache', TJSONNumber.Create(mWorkspace.FromCache));
    mItem.AddPair('missing', TJSONNumber.Create(mWorkspace.Missing));
    mItem.AddPair('lastUpdate', DateText(mWorkspace.LastUpdate));
    mItem.AddPair('cacheBytes', TJSONNumber.Create(mWorkspace.CacheBytes));
    mItem.AddPair('libraryCacheBytes', TJSONNumber.Create(mWorkspace.LibraryCacheBytes));
    if mWorkspace.Project <> '' then
    begin
      mItem.AddPair('project', mWorkspace.Project);
      mItem.AddPair('config', mWorkspace.Config);
      mItem.AddPair('platform', mWorkspace.Platform);
      mItem.AddPair('buildChosen', TJSONBool.Create(mWorkspace.BuildChosen));
      mItem.AddPair('active', TJSONBool.Create(mWorkspace.Active));
      mItem.AddPair('selected', TJSONBool.Create(mWorkspace.Selected));
    end;
    Result.AddElement(mItem);
  end;
end;

function RequestsJson(const ARequests: TArray<TMethodStatistics>): TJSONArray;
var
  mRequest: TMethodStatistics;
  mItem: TJSONObject;
begin
  Result := TJSONArray.Create;
  for mRequest in ARequests do
  begin
    mItem := TJSONObject.Create;
    mItem.AddPair('method', mRequest.Method);
    mItem.AddPair('count', TJSONNumber.Create(mRequest.Count));
    mItem.AddPair('averageMs', TJSONNumber.Create(mRequest.AverageMs));
    mItem.AddPair('maxMs', TJSONNumber.Create(mRequest.MaxMs));
    mItem.AddPair('failed', TJSONNumber.Create(mRequest.Failed));
    Result.AddElement(mItem);
  end;
end;

/// <summary>Aufschlüsselung des Speichers; AOverBudget wie TServerMemory.OverBudget.</summary>
function MemoryJson(const AMemory: TServerMemory; AOverBudget: Boolean): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('symbols', TJSONNumber.Create(AMemory.Symbols));
  Result.AddPair('usages', TJSONNumber.Create(AMemory.Usages));
  Result.AddPair('libraryUnits', TJSONNumber.Create(AMemory.LibraryUnits));
  Result.AddPair('treeCache', TJSONNumber.Create(AMemory.TreeCache));
  Result.AddPair('documents', TJSONNumber.Create(AMemory.Documents));
  Result.AddPair('packages', TJSONNumber.Create(AMemory.Packages));
  Result.AddPair('rest', TJSONNumber.Create(AMemory.Rest));
  Result.AddPair('total', TJSONNumber.Create(AMemory.Total));
  Result.AddPair('budget', TJSONNumber.Create(AMemory.Budget));
  Result.AddPair('overBudget', TJSONBool.Create(AOverBudget));
end;

function QueueJson(const AQueue: TServerQueue): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('indexWaiting', TJSONNumber.Create(AQueue.IndexWaiting));
  Result.AddPair('indexRunning', TJSONNumber.Create(AQueue.IndexRunning));
  Result.AddPair('checkWaiting', TJSONNumber.Create(AQueue.CheckWaiting));
  Result.AddPair('checkRunning', TJSONNumber.Create(AQueue.CheckRunning));
  Result.AddPair('oldestWaitMs', TJSONNumber.Create(AQueue.OldestWaitMs));
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
  ABuilder.Append('| Packages (.dcp) | ').Append(MegaBytes(Memory.Packages)).Append(' |').Append(#10);
  ABuilder.Append('| Rest | ').Append(MegaBytes(Memory.Rest)).Append(' |').Append(#10);
  if Memory.Total >= 0 then
  begin
    ABuilder.Append('| Gesamt | ').Append(MegaBytes(Memory.Total)).Append(' |').Append(#10);
  end;
  if Memory.Budget > 0 then
  begin
    ABuilder.Append('| Budget des Index | ').Append(MegaBytes(Memory.Budget)).Append(' |').Append(#10);
  end;
  if Memory.OverBudget(CompactUnits, OffloadedUnits) then
  begin
    ABuilder.Append(#10).Append('Budget überschritten: Verwendungen werden ausgelagert.').Append(#10);
  end;
  ABuilder.Append(#10).Append(Format('- Warteschlange: Index %d wartend, %d laufend; Prüfung %d wartend, %d laufend; ' +
    'älteste Wartezeit %d ms', [Queue.IndexWaiting, Queue.IndexRunning, Queue.CheckWaiting, Queue.CheckRunning,
    Queue.OldestWaitMs])).Append(#10);
  ABuilder.Append('- Cache-Treffer: ');
  if IndexCacheHitPercent >= 0 then
  begin
    ABuilder.Append(Format('Index %d %%', [IndexCacheHitPercent]));
  end
  else
  begin
    ABuilder.Append('Index –');
  end;
  if TreeCacheHitPercent >= 0 then
  begin
    ABuilder.Append(Format(', Syntaxbäume %d %% (%d im Speicher)', [TreeCacheHitPercent, TreeCacheTrees]));
  end
  else
  begin
    ABuilder.Append(', Syntaxbäume –');
  end;
  ABuilder.Append(#10);
  mProfile := CheckRun.ToMarkdown;
  if mProfile <> '' then
  begin
    ABuilder.Append(#10).Append(mProfile);
  end;
end;

function TServerStatus.ToMarkdown: string;
var
  Builder: TStringBuilder;
begin
  Builder := TStringBuilder.Create;
  try
    Builder.Append('**Atlas**').Append(#10#10);
    Builder.Append(Format('- Index: %d Units, %d Symbole', [Units, Symbols])).Append(#10);
    if MemoryBytes >= 0 then
    begin
      Builder.Append('- Speicher: ').Append(MegaBytes(MemoryBytes)).Append(#10);
    end;
    Builder.Append('- davon Symbolindex: ').Append(MegaBytes(IndexBytes));
    if BudgetBytes > 0 then
    begin
      Builder.Append(' von ').Append(MegaBytes(BudgetBytes));
    end;
    if CompactUnits > 0 then
    begin
      Builder.Append(Format(', %d Units kompakt', [CompactUnits]));
    end;
    if OffloadedUnits > 0 then
    begin
      Builder.Append(Format(', Verwendungen von %d Units ausgelagert', [OffloadedUnits]));
    end;
    Builder.Append(#10);
    Builder.Append('- Caches auf der Platte: ').Append(MegaBytes(DiskBytes)).Append(#10);
    Builder.Append('- davon geöffnete Dokumente: ').Append(MegaBytes(DocumentBytes)).Append(#10);
    if Compiler <> '' then
    begin
      Builder.Append('- ').Append(Compiler).Append(#10);
      if CompilerReason <> '' then
      begin
        Builder.Append('  ').Append(CompilerReason).Append(#10);
      end;
    end;
    AppendWorkspaces(Builder, Workspaces);
    if ProcessId <> 0 then
    begin
      AppendDiagnostics(Builder);
    end;
    AppendRequests(Builder, Requests);
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

function TServerStatus.ToJson: TJSONObject;
var
  Item: TJSONObject;
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
  Result.AddPair('workspaces', WorkspacesJson(Workspaces));
  Result.AddPair('requests', RequestsJson(Requests));
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
    Result.AddPair('memory', MemoryJson(Memory, Memory.OverBudget(CompactUnits, OffloadedUnits)));
    Result.AddPair('checkRun', CheckRun.ToJson);
    Result.AddPair('queue', QueueJson(Queue));
    Item := TJSONObject.Create;
    Item.AddPair('index', TJSONNumber.Create(IndexCacheHitPercent));
    Item.AddPair('trees', TJSONNumber.Create(TreeCacheHitPercent));
    Item.AddPair('treeCount', TJSONNumber.Create(TreeCacheTrees));
    Result.AddPair('cacheHits', Item);
  end;
  Result.AddPair('markdown', ToMarkdown);
end;

end.
