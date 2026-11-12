unit Atlas.Common.Lsp.Status;

// Inhalt des Status-Befehls "atlas.server.status" (#28): Index, Speicher,
// letzter Indexlauf je Ordner und Antwortzeiten je Methode. Als JSON für
// Werkzeuge und als Markdown zum Anzeigen. Dazu die Größe der
// Caches auf der Platte, die letzte Aktualisierung je Ordner und die Zahl der
// Units mit ausgelagerten Verwendungen (Einstellungsseite des Plugins, #492),
// der Weg zum Compiler und, wenn keiner nutzbar ist, Grund und Ausweg (#261).
// Für das Fenster „Atlas-Server“, --timings und MCP get_server_status (#1356)
// rückwärtsverträglich unter eigenen Schlüsseln: Prozess (pid,
// Version, Start, Zustand), Speicher je Bereich gegen das Budget, Zeitprofil
// des letzten Prüflaufs, Warteschlange von Index und Prüfung und die
// Trefferquoten von Index-Cache und Syntaxbaum-Cache.
// Mapped (#1478) liefert eine Kopie, in der jeder Name (Ordner, eigene
// Konfiguration, langsame Units) und jeder Pfad (Projekt, Caches) über eine
// Funktion läuft: für die Protokollzeile gekennzeichnet (TLogMarks), für den
// anonymen Status über den Anonymisierer des Servers.
// Je Ordner (#2142) das Token seiner $/progress-Meldungen und, solange er
// aufbaut, Prozent, Stufe und ob er auf sie wartet (Fenster „Atlas-Einrichtung“).

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
    /// <summary>Token der $/progress-Meldungen dieses Ordners ('' ohne, #2142).</summary>
    ProgressToken: string;
    /// <summary>Aufbau läuft (#2142): Prozent (-1 = unbekannt), Stufe ('projectFiles', 'searchPaths',
    /// 'library'; '' = unbekannt) und ob er auf sie wartet.</summary>
    Indexing: Boolean;
    IndexPercent: Integer;
    IndexStage: string;
    IndexWaiting: Boolean;
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
    cStateLoading = 'loading';
    cStateReady = 'ready';
    cStateChecking = 'checking';
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
  cStatusCommand = 'atlas.server.status';
  /// <summary>Alle Index-Caches löschen und die Ordner neu indizieren (#492).</summary>
  cClearIndexCommand = 'atlas.server.clearIndex';

implementation

uses
  System.Generics.Collections,
  System.DateUtils,
  Atlas.Text.Anonymize,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TStatusText = (Chosen, ActiveInTheIDE, Selected, Loading, Checking, IndexIsBeingBuilt, LastIndexRunMsRead,
    MethodCountMeanMsMax, ProcessVersionRunningFor, IndexBudget, BudgetExceededUsesAreSwapped,
    QueueIndexWaitingRunningCheck, SyntaxTreesInMemory, SyntaxTrees, CachesOnDisk, OfTheseOpenDocuments, CacheHits,
    UsesOfUnitsSwappedOut, Updated, MemoryMB, Symbols, Usages, LibraryUnits, OpenDocuments, Total, IndexUnitsSymbols,
    Memory, OfThisSymbolIndex, OfText, UnitsCompact, Ready);

const
  cTexts: array[TStatusText] of TAtlasText = (
    (De: ' (gewählt)'; En: ' (chosen)'),
    (De: ' · aktiv in der IDE'; En: ' · active in the IDE'),
    (De: ' · ausgewählt'; En: ' · selected'),
    (De: 'lädt'; En: 'loading'),
    (De: 'prüft'; En: 'checking'),
    (De: '- %s%s: Index wird aufgebaut'; En: '- %s%s: index is being built'),
    (De: '- %s%s: letzter Indexlauf %d ms (%d neu eingelesen, %d aus dem Cache, %d fehlen)';
     En: '- %s%s: last index run %d ms (%d read anew, %d from the cache, %d missing)'),
    (De: '| Methode | Anzahl | Mittel ms | Max ms | Fehler |'; En: '| Method | Count | Mean ms | Max ms | Errors |'),
    (De: '- Prozess %d, Version %s, läuft seit %d s, %s'; En: '- Process %d, version %s, running for %d s, %s'),
    (De: '| Budget des Index | '; En: '| Index budget | '),
    (De: 'Budget überschritten: Verwendungen werden ausgelagert.'; En: 'Budget exceeded: uses are swapped out.'),
    (De: '- Warteschlange: Index %d wartend, %d laufend; Prüfung %d wartend, %d laufend; älteste Wartezeit %d ms';
     En: '- Queue: index %d waiting, %d running; check %d waiting, %d running; oldest wait %d ms'),
    (De: ', Syntaxbäume %d %% (%d im Speicher)'; En: ', syntax trees %d %% (%d in memory)'),
    (De: ', Syntaxbäume –'; En: ', syntax trees –'),
    (De: '- Caches auf der Platte: '; En: '- Caches on disk: '),
    (De: '- davon geöffnete Dokumente: '; En: '- of these open documents: '),
    (De: '- Cache-Treffer: '; En: '- Cache hits: '),
    (De: ', Verwendungen von %d Units ausgelagert'; En: ', uses of %d units swapped out'),
    (De: ', aktualisiert '; En: ', updated '),
    (De: '| Speicher | MB |'; En: '| Memory | MB |'),
    (De: '| Symbole | '; En: '| Symbols | '),
    (De: '| Verwendungen | '; En: '| Usages | '),
    (De: '| Bibliotheks-Units | '; En: '| Library units | '),
    (De: '| Offene Dokumente | '; En: '| Open documents | '),
    (De: '| Gesamt | '; En: '| Total | '),
    (De: '- Index: %d Units, %d Symbole'; En: '- Index: %d units, %d symbols'),
    (De: '- Speicher: '; En: '- Memory: '),
    (De: '- davon Symbolindex: '; En: '- of this symbol index: '),
    (De: ' von '; En: ' of '),
    (De: ', %d Units kompakt'; En: ', %d units compact'),
    (De: 'bereit'; En: 'ready'));

{$SCOPEDENUMS OFF}

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
    Result := Result + cTexts[TStatusText.Chosen].Text;
  end;
  if Active then
  begin
    Result := Result + cTexts[TStatusText.ActiveInTheIDE].Text;
  end;
  if Selected then
  begin
    Result := Result + cTexts[TStatusText.Selected].Text;
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
  if State = cStateLoading then
  begin
    Result := cTexts[TStatusText.Loading].Text;
  end
  else if State = cStateChecking then
  begin
    Result := cTexts[TStatusText.Checking].Text;
  end
  else
  begin
    Result := cTexts[TStatusText.Ready].Text;
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
      ABuilder.Append(cTexts[TStatusText.IndexIsBeingBuilt].Fmt([mWorkspace.Name, mWorkspace.ProjectText])).Append(#10);
      Continue;
    end;
    ABuilder.Append(cTexts[TStatusText.LastIndexRunMsRead].Fmt([mWorkspace.Name, mWorkspace.ProjectText,
      mWorkspace.LastIndexMs, mWorkspace.Parsed, mWorkspace.FromCache,
      mWorkspace.Missing]));
    if mWorkspace.LastUpdate <> 0 then
    begin
      ABuilder.Append(cTexts[TStatusText.Updated].Text).Append(FormatDateTime('dd.mm.yyyy hh":"nn":"ss',
        mWorkspace.LastUpdate));
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
  ABuilder.Append(#10).Append(cTexts[TStatusText.MethodCountMeanMsMax].Text).Append(#10);
  ABuilder.Append('|---|---:|---:|---:|---:|').Append(#10);
  for mRequest in ARequests do
  begin
    ABuilder.Append(Format('| %s | %d | %s | %d | %d |', [mRequest.Method, mRequest.Count,
      FormatFloat('0.0', mRequest.AverageMs, TFormatSettings.Invariant), mRequest.MaxMs, mRequest.Failed])).Append(#10);
  end;
end;

/// <summary>Token und laufender Aufbau eines Ordners (#2142); ohne Aufbau nur das Token.</summary>
procedure AddIndexing(AItem: TJSONObject; const AWorkspace: TWorkspaceStatus);
var
  mIndexing: TJSONObject;
begin
  if AWorkspace.ProgressToken <> '' then
  begin
    AItem.AddPair('progressToken', AWorkspace.ProgressToken);
  end;
  if not AWorkspace.Indexing then
  begin
    Exit;
  end;
  mIndexing := TJSONObject.Create;
  mIndexing.AddPair('percent', TJSONNumber.Create(AWorkspace.IndexPercent));
  if AWorkspace.IndexStage <> '' then
  begin
    mIndexing.AddPair('stage', AWorkspace.IndexStage);
  end;
  mIndexing.AddPair('waiting', TJSONBool.Create(AWorkspace.IndexWaiting));
  AItem.AddPair('indexing', mIndexing);
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
    AddIndexing(mItem, mWorkspace);
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
  ABuilder.Append(#10).Append(cTexts[TStatusText.ProcessVersionRunningFor].Fmt([ProcessId, Version, UptimeMs div 1000,
    StateText])).Append(#10);
  ABuilder.Append(#10).Append(cTexts[TStatusText.MemoryMB].Text).Append(#10);
  ABuilder.Append('|---|---:|').Append(#10);
  ABuilder.Append(cTexts[TStatusText.Symbols].Text).Append(MegaBytes(Memory.Symbols)).Append(' |').Append(#10);
  ABuilder.Append(cTexts[TStatusText.Usages].Text).Append(MegaBytes(Memory.Usages)).Append(' |').Append(#10);
  ABuilder.Append(cTexts[TStatusText.LibraryUnits].Text).Append(MegaBytes(Memory.LibraryUnits)).Append(' |')
    .Append(#10);
  ABuilder.Append('| Syntaxbaum-Cache | ').Append(MegaBytes(Memory.TreeCache)).Append(' |').Append(#10);
  ABuilder.Append(cTexts[TStatusText.OpenDocuments].Text).Append(MegaBytes(Memory.Documents)).Append(' |').Append(#10);
  ABuilder.Append('| Packages (.dcp) | ').Append(MegaBytes(Memory.Packages)).Append(' |').Append(#10);
  ABuilder.Append('| Rest | ').Append(MegaBytes(Memory.Rest)).Append(' |').Append(#10);
  if Memory.Total >= 0 then
  begin
    ABuilder.Append(cTexts[TStatusText.Total].Text).Append(MegaBytes(Memory.Total)).Append(' |').Append(#10);
  end;
  if Memory.Budget > 0 then
  begin
    ABuilder.Append(cTexts[TStatusText.IndexBudget].Text).Append(MegaBytes(Memory.Budget)).Append(' |').Append(#10);
  end;
  if Memory.OverBudget(CompactUnits, OffloadedUnits) then
  begin
    ABuilder.Append(#10).Append(cTexts[TStatusText.BudgetExceededUsesAreSwapped].Text).Append(#10);
  end;
  ABuilder.Append(#10).Append(cTexts[TStatusText.QueueIndexWaitingRunningCheck].Fmt([Queue.IndexWaiting,
    Queue.IndexRunning, Queue.CheckWaiting, Queue.CheckRunning,
    Queue.OldestWaitMs])).Append(#10);
  ABuilder.Append(cTexts[TStatusText.CacheHits].Text);
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
    ABuilder.Append(cTexts[TStatusText.SyntaxTreesInMemory].Fmt([TreeCacheHitPercent, TreeCacheTrees]));
  end
  else
  begin
    ABuilder.Append(cTexts[TStatusText.SyntaxTrees].Text);
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
  mBuilder: TStringBuilder;
begin
  mBuilder := TStringBuilder.Create;
  try
    mBuilder.Append('**Atlas**').Append(#10#10);
    mBuilder.Append(cTexts[TStatusText.IndexUnitsSymbols].Fmt([Units, Symbols])).Append(#10);
    if MemoryBytes >= 0 then
    begin
      mBuilder.Append(cTexts[TStatusText.Memory].Text).Append(MegaBytes(MemoryBytes)).Append(#10);
    end;
    mBuilder.Append(cTexts[TStatusText.OfThisSymbolIndex].Text).Append(MegaBytes(IndexBytes));
    if BudgetBytes > 0 then
    begin
      mBuilder.Append(cTexts[TStatusText.OfText].Text).Append(MegaBytes(BudgetBytes));
    end;
    if CompactUnits > 0 then
    begin
      mBuilder.Append(cTexts[TStatusText.UnitsCompact].Fmt([CompactUnits]));
    end;
    if OffloadedUnits > 0 then
    begin
      mBuilder.Append(cTexts[TStatusText.UsesOfUnitsSwappedOut].Fmt([OffloadedUnits]));
    end;
    mBuilder.Append(#10);
    mBuilder.Append(cTexts[TStatusText.CachesOnDisk].Text).Append(MegaBytes(DiskBytes)).Append(#10);
    mBuilder.Append(cTexts[TStatusText.OfTheseOpenDocuments].Text).Append(MegaBytes(DocumentBytes)).Append(#10);
    if Compiler <> '' then
    begin
      mBuilder.Append('- ').Append(Compiler).Append(#10);
      if CompilerReason <> '' then
      begin
        mBuilder.Append('  ').Append(CompilerReason).Append(#10);
      end;
    end;
    AppendWorkspaces(mBuilder, Workspaces);
    if ProcessId <> 0 then
    begin
      AppendDiagnostics(mBuilder);
    end;
    AppendRequests(mBuilder, Requests);
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

function TServerStatus.ToJson: TJSONObject;
var
  mItem: TJSONObject;
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
    mItem := TJSONObject.Create;
    mItem.AddPair('status', Compiler);
    mItem.AddPair('backend', CompilerBackend);
    mItem.AddPair('reason', CompilerReason);
    Result.AddPair('compiler', mItem);
  end;
  if ProcessId <> 0 then
  begin
    mItem := TJSONObject.Create;
    mItem.AddPair('pid', TJSONNumber.Create(ProcessId));
    mItem.AddPair('version', Version);
    mItem.AddPair('started', DateText(Started));
    mItem.AddPair('uptimeMs', TJSONNumber.Create(UptimeMs));
    mItem.AddPair('state', State);
    Result.AddPair('process', mItem);
    Result.AddPair('memory', MemoryJson(Memory, Memory.OverBudget(CompactUnits, OffloadedUnits)));
    Result.AddPair('checkRun', CheckRun.ToJson);
    Result.AddPair('queue', QueueJson(Queue));
    mItem := TJSONObject.Create;
    mItem.AddPair('index', TJSONNumber.Create(IndexCacheHitPercent));
    mItem.AddPair('trees', TJSONNumber.Create(TreeCacheHitPercent));
    mItem.AddPair('treeCount', TJSONNumber.Create(TreeCacheTrees));
    Result.AddPair('cacheHits', mItem);
  end;
  Result.AddPair('markdown', ToMarkdown);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.Status', cTexts);

end.
