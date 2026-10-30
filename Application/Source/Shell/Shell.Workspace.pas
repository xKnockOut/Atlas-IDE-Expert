unit Shell.Workspace;

// Host-Rolle Shell: ein Ordner des Arbeitsbereichs mit eigener
// atlas.json, eigenem Projekt und eigenem Indexaufbau. Alle Ordner
// schreiben in denselben Symbolindex, damit Navigation und Suche über
// Ordnergrenzen funktionieren.
// Projektgruppe (#648): Je Projekt der Gruppe ein Arbeitsbereich mit fest
// vorgegebener Projektdatei (ProjectFile); mehrere können denselben Ordner
// haben. Der gemeinsame Scheduler ordnet ihre Aufbauten.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Atlas.Common.Logging.Contract,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Lsp.Configuration,
  Atlas.Common.Lsp.IdeProject,
  Atlas.Common.Lsp.WorkDoneProgress,
  Atlas.Common.Projects.Contract,
  Atlas.Common.Projects.UnitResolver,
  Atlas.Common.Projects.PackageLocator,
  Atlas.Common.Projects.Selection,
  Atlas.Common.Projects.MissingUnit,
  Atlas.Common.Compiler.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.Service,
  Atlas.Common.Index.Builder,
  Atlas.Common.Index.Scheduler,
  Atlas.Common.Index.Processes,
  Atlas.Common.Index.Adapters.Processes,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Baseline,
  Atlas.Common.Rules.Checker,
  Atlas.Common.Rules.ProjectFiles,
  Atlas.Common.Lsp.Status,
  Shell.Compiler;

type
  /// <summary>Hält einen TPackageLocator (#1220); der Locator wird mit dem letzten Halter frei.</summary>
  IPackageLocatorHold = interface
    ['{5B6F7C1E-2A9D-4E83-9F04-3C1D8A7B6E21}']
    function Locator: TPackageLocator;
  end;

  TPackageLocatorHold = class(TInterfacedObject, IPackageLocatorHold)
  private
    FLocator: TPackageLocator;
  public
    /// <summary>Übernimmt ALocator.</summary>
    constructor Create(ALocator: TPackageLocator);
    destructor Destroy; override;
    function Locator: TPackageLocator;
  end;

  TShellWorkspace = class
  private
    FRoot: string;
    FName: string;
    FLogger: ILogger;
    FTransport: IJsonRpcTransport;
    FIndex: ISymbolIndex;
    /// <summary>Hinweis auf gemischte Kodierungen schon im Editor gezeigt (#121); einmal je Sitzung.</summary>
    FEncodingsShown: Boolean;
    FConfiguration: TLspConfiguration;
    FIndexService: TIndexService;
    FProgress: TLspWorkDoneProgress;
    FUnitResolver: TUnitResolver;
    /// <summary>Frühere Resolver: Der alte Builder bedient EnsureUnit, bis der neue veröffentlicht ist,
    /// und ruft sie dabei noch auf. Freigabe erst mit dem Arbeitsbereich.</summary>
    FRetiredResolvers: TObjectList<TUnitResolver>;
    /// <summary>Packages aus requires (#46), je Indexaufbau neu; unter FLock. Frühere bleiben bis zur Freigabe des
    /// Arbeitsbereichs, weil Prüfungen in Anfrage-Threads sie noch halten können.</summary>
    FPackageLocator: TPackageLocator;
    // Der Locator lebt, solange ihn ein Halter hat (#1220): Arbeitsbereich und die Unit-Suche, die Prüfungen in
    // Anfrage-Threads noch über die Freigabe des Arbeitsbereichs hinaus benutzen können.
    FPackageLocatorHold: IPackageLocatorHold;
    FRetiredLocators: TList<IPackageLocatorHold>;
    /// <summary>Unit-Suche wie beim Compiler für uses-unit-not-found (#1016), je Indexaufbau neu; unter FLock.
    /// </summary>
    FUnitLookup: IRuleUnitLookup;
    FOnPackageFolders: TFunc<TArray<string>>;
    FOnGroupProjects: TFunc<TArray<string>>;
    /// <summary>Gemerkte Wahl über Neustarts (#46); gehört der Komposition, nil = nichts merken.</summary>
    FSelection: TProjectSelection;
    /// <summary>Gemerkte Konfiguration und Plattform schon übernommen; danach gilt nur noch selectBuild.</summary>
    FBuildRestored: Boolean;
    /// <summary>Anmeldung am eigenen Index-Cache für „Prozesse am Projekt“ (#62); unter FLock.</summary>
    FProcessEntry: TIndexProcessEntry;
    FProcessIdentity: TIndexProcessInfo;
    FSignature: string;
    // Schützt Defines und Namespaces, die Anfrage-Threads lesen.
    FLock: TObject;
    FDefines: TArray<string>;
    FHasDefines: Boolean;
    FNamespaces: TArray<string>;
    FSearchPaths: TArray<string>;
    FProjectFiles: TArray<string>;
    /// <summary>Alle Units der Suchpfade im Index (#648), unter FLock.</summary>
    FSearchFiles: TArray<string>;
    /// <summary>Projektdateien und Suchpfad-Units in Großschreibung, für ContainsFile; unter FLock.</summary>
    FOwnFiles: TDictionary<string, Boolean>;
    /// <summary>Fest vorgegebene Projektdatei (Projektgruppe, #648); '' = im Ordner suchen.</summary>
    FFixedProject: string;
    /// <summary>Ordner der Index-Caches (#1112, --index-cache); Vorgabe TIndexCacheDirectory.DefaultRoot.
    /// </summary>
    FCacheRoot: string;
    FPriority: Integer;
    FScheduler: TIndexScheduler;
    /// <summary>Aus der Projektgruppe: Mit index.projectGroup = false erst indizieren, wenn eine Datei des
    /// Projekts geöffnet wird (Activate).</summary>
    FDeferred: Boolean;
    FActivated: Boolean;
    /// <summary>Thread der Nachrichtenschleife; Reload nur dort (Code-Review A-03). 0 = keine Prüfung.</summary>
    FLoopThreadId: TThreadID;
    FOrigin: string;
    // Für den Compileraufruf (#40), unter FLock.
    FProject: TProjectInfo;
    FHasProject: Boolean;
    FBdsRoot: string;
    FDelphiVersion: string;
    /// <summary>Beim nächsten Indexaufbau den Cache verwerfen (#49).</summary>
    FDiscardCache: Boolean;
    FCompilerLibraryPaths: TArray<string>;
    // Per Befehl gewählte Konfiguration und Plattform (#46), unter FLock; '' = Einstellung.
    FBuildConfig: string;
    FBuildPlatform: string;
    // Bedingte Symbole aus den Projektoptionen der IDE (#615), auch ungespeichert; nur mit FHasBuildDefines.
    FBuildDefines: TArray<string>;
    FHasBuildDefines: Boolean;
    FOnProjectLoaded: TProc;
    /// <summary>Projektkontexte aus der IDE (#396); nil ohne Plugin. Gehört der Komposition.</summary>
    FIdeProjects: TLspIdeProject;
    FOnIndexFinished: TProc;
    FOnProjectReady: TProc;
    FOnIndexEvent: TProc<string>;
    FOnNames: TProc<TArray<string>>;
    /// <summary>Ein Aufbau läuft und hat die Projektstufe noch nicht hinter sich.</summary>
    FProjectPending: Boolean;
    /// <summary>Der letzte Aufbau hat entschieden, ohne Projekt zu indizieren (keine oder fehlende Projektdatei,
    /// index.projectGroup aus und noch nicht aktiviert); dann wartet keine Prüfung auf ein Projekt (#1220).</summary>
    FWithoutProject: Boolean;
    FOnSettingsChanged: TProc<TServerSettings>;
    FBaseline: IRuleBaseline;
    FLastIndexMs: Int64;
    FLastIndex: TIndexBuildResult;
    /// <summary>Letzte Änderung am Index (Aufbau, Speichern, Tipp-Pause, #492); unter FLock.</summary>
    FLastUpdate: TDateTime;
    /// <summary>Cache-Dateien des laufenden Aufbaus (#492); unter FLock.</summary>
    FCacheFile: string;
    FLibraryCacheFile: string;
    /// <summary>Sperre des eigenen Index-Caches (#184); nil, wenn eine andere Instanz ihn hält.</summary>
    FCacheLock: TStream;
    FCacheLockFile: string;
    FBaselineTime: TDateTime;
    /// <summary>Sperrt ACacheFile, gibt eine alte Sperre frei; False = nur lesen. Vermerkt Herkunft (AOrigin)
    /// und Benutzung und räumt den Cache-Ordner nach ASettings auf (#905); dabei bleiben ACacheFile und
    /// ALibraryCacheFile stehen (#616).</summary>
    function LockCache(const ACacheFile, ALibraryCacheFile, AOrigin: string;
      const ASettings: TServerSettings): Boolean;
    /// <summary>Löscht Projekt- und Bibliotheks-Cache; läuft als TIndexRequest.Prepare im Index-Thread.</summary>
    function DiscardCacheFiles(const ACacheFile, ALibraryCacheFile: string): TProc;
    /// <summary>Weist auf gemischte Kodierungen der Projektdateien hin (Index-Thread).</summary>
    procedure ReportEncodings;
    procedure Touch;
    procedure IndexEvent(const AText: string);
    procedure StartIndex(const ASettings: TServerSettings);
    function FindProjectFile(const ASettings: TServerSettings): string;
    function GetNamespaces: TArray<string>;
    function GetIncludePaths: TArray<string>;
    function GetProjectFiles: TArray<string>;
    function GetPackageLocator: TPackageLocator;
    /// <summary>Meldet den eigenen Prozess am Cache an bzw. um (#62) und hält Zustand und Ereignis fest.</summary>
    procedure ReportProcess(const ACacheFile, AState: string; AWriter: Boolean; const AEvent: string); overload;
    /// <summary>Nur ein Ereignis am angemeldeten Cache; ohne Anmeldung nichts.</summary>
    procedure ReportProcess(const AState: string; AWriter: Boolean; const AEvent: string); overload;
    /// <summary>Hält dieser Arbeitsbereich die Sperre seines Caches (laut Anmeldung, #62)?</summary>
    function WritesCache: Boolean;
    /// <summary>Übernimmt einmal die gemerkte Konfiguration und Plattform von AProjectFile (#46).</summary>
    procedure RestoreBuild(const AProjectFile: string);
    /// <summary>True, wenn eine Wahl verworfen wurde, die AProject nicht kennt.</summary>
    function DropUnknownBuild(const AProject: TProjectInfo): Boolean;
    /// <summary>Packages (#46): contains der .dpk gehört zum Projekt, auch ohne DCCReference; die Units der
    /// requires-Packages mit Quelltext kommen zu den Suchpfad-Units.</summary>
    procedure AddPackageFiles(const AProject: TProjectInfo; ALocator: TPackageLocator; var AFiles,
      ASearchFiles: TArray<string>);
  public
    constructor Create(const ARoot, AName: string; const AStore: IDocumentStore; const ATransport: IJsonRpcTransport;
      const ALogger: ILogger; const AIndex: ISymbolIndex; const AProgressToken: string);
    destructor Destroy; override;
    /// <summary>Liest atlas.json des Ordners und startet den Indexaufbau.</summary>
    procedure Load; overload;
    /// <summary>Wie Load, mit der globalen settings.json AGlobalSettings; der Index startet nur einmal.</summary>
    procedure Load(const AGlobalSettings: string); overload;
    /// <summary>Lädt das Projekt neu, auch wenn sich die Einstellungen nicht geändert haben.</summary>
    procedure Reload;
    /// <summary>Baut den Index ohne Cache neu auf (Befehl „Index neu aufbauen“, #49).</summary>
    procedure Rebuild;
    /// <summary>Hält den Indexaufbau an.</summary>
    procedure Stop;
    /// <summary>Hält den Aufbau an und gibt die Sperre des eigenen Caches frei, damit „Index löschen“ (#492)
    /// ihn entfernen kann; Rebuild sperrt ihn wieder.</summary>
    procedure ReleaseCache;
    function EnsureUnit(const AUnitName: string): Boolean;
    function ApplyChanges(const AChanges: TArray<TFileChange>): Integer;
    function ApplyText(const AFileName, AText: string): Boolean;
    /// <summary>Symbole des Projekts für das Abblenden; False ohne Projekt. Threadsicher.</summary>
    function Defines(out ADefines: TArray<string>): Boolean;
    /// <summary>Symbole und Include-Dateien des Projekts für die Regelprüfung von AFileName (#860); ohne
    /// Projekt die Vordefinitionen, $I dann nur im Ordner der Datei. Threadsicher.</summary>
    function CheckSource(const AFileName: string): TCheckSource;
    /// <summary>Arbeitsbereich zu einer Datei (S-02): AFound, sonst bei genau einem Arbeitsbereich dieser,
    /// sonst nil. Eine Regel für alle Einstellungs- und Pfadabfragen des Servers.</summary>
    class function Choose(AFound: TShellWorkspace; const AAll: TList<TShellWorkspace>): TShellWorkspace; static;
    /// <summary>
    /// atlas-baseline.json des Ordners (#97), neu gelesen, sobald sich die
    /// Datei ändert; nil ohne oder bei ungültiger Datei. Threadsicher.
    /// </summary>
    function Baseline: IRuleBaseline;
    /// <summary>Compilerlauf für das Projekt (#40, #261): Aufruf von dcc32/dcc64, Projekt, Plattform,
    /// Installation und compiler-Einstellungen. Ob dcc da und nutzbar ist, prüft der Aufrufer
    /// (TShellCompilerEditions). False mit Grund in AError ohne Projekt, Installation oder unterstützte
    /// Plattform. Threadsicher.</summary>
    function CompileJob(out AJob: TShellCompileJob; out AError: string): Boolean;
    /// <summary>Wechselt Konfiguration und/oder Plattform ('' = unverändert) und lädt das Projekt neu (#46).
    /// False mit Grund in AError ohne Projekt oder bei unbekannten Werten. Threadsicher.</summary>
    function SelectBuild(const AConfig, APlatform: string; out AError: string): Boolean; overload;
    /// <summary>Wie oben; mit AHasDefines ersetzen ADefines die Symbole (DCC_Define) der .dproj,
    /// etwa ungespeicherte Projektoptionen der IDE (#615).</summary>
    function SelectBuild(const AConfig, APlatform: string; const ADefines: TArray<string>; AHasDefines: Boolean;
      out AError: string): Boolean; overload;
    /// <summary>Geladenes Projekt; False ohne Projekt. Threadsicher.</summary>
    function Project(out AProject: TProjectInfo): Boolean;
    /// <summary>Für das Projekt gewählte Delphi-Version (z. B. "23.0", #47); '' ohne Installation. Threadsicher.</summary>
    function DelphiVersion: string;
    /// <summary>Ordner der Delphi-Installation ($(BDS)); '' ohne Installation. Threadsicher.</summary>
    function BdsRoot: string;
    /// <summary>Bibliothekspfade der Installation für das Projekt, aufgelöst; nil ohne Installation. Threadsicher.
    /// </summary>
    function LibraryPaths: TArray<string>;
    /// <summary>Suche nach einer Unit, die der Compiler nicht fand (#550): aktives Projekt, alle
    /// Konfigurationen und Plattformen der .dproj, Bibliothekspfade und Ordnerzugriff. Gruppe und Index
    /// ergänzt der Aufrufer. False ohne Projekt. Threadsicher.</summary>
    function MissingUnitSetup(out ASetup: TMissingUnitSetup): Boolean;
    /// <summary>Fortschritt des laufenden Indexaufbaus in Prozent; -1, wenn keiner läuft (#647).</summary>
    function IndexLoading: Integer;
    /// <summary>Letzter Indexlauf für den Status-Befehl (#28). Threadsicher.</summary>
    function IndexStatus: TWorkspaceStatus;
    property Root: string read FRoot;
    property Name: string read FName;
    property Configuration: TLspConfiguration read FConfiguration;
    /// <summary>Unit-Namespaces des Projekts. Threadsicher.</summary>
    property Namespaces: TArray<string> read GetNamespaces;
    /// <summary>Suchpfade für Include-Dateien (#264): Projekt-Suchpfade, dann Bibliothekspfade. Threadsicher.</summary>
    property IncludePaths: TArray<string> read GetIncludePaths;
    /// <summary>Quelltexte des Projekts (Hauptdatei, Units). Threadsicher.</summary>
    property ProjectFiles: TArray<string> read GetProjectFiles;
    /// <summary>Nach dem Laden eines Projekts (Defines und Namespaces neu).</summary>
    property OnProjectLoaded: TProc read FOnProjectLoaded write FOnProjectLoaded;
    /// <summary>Nach einem vollständigen (nicht abgebrochenen) Indexaufbau; im Index-Thread.</summary>
    property OnIndexFinished: TProc read FOnIndexFinished write FOnIndexFinished;
    /// <summary>Projektstufe des Aufbaus fertig (Projektdateien und über uses erreichbare Units); im Index-Thread.</summary>
    property OnProjectReady: TProc read FOnProjectReady write FOnProjectReady;
    /// <summary>Zeile fürs Diagnoselog (#647), nur Zahlen und feste Wörter; im Index- oder Nachrichten-Thread.</summary>
    property OnIndexEvent: TProc<string> read FOnIndexEvent write FOnIndexEvent;
    /// <summary>Projekt- und Unit-Namen nach dem Lesen der .dproj, damit das Server-Log sie verbirgt (#647).</summary>
    property OnNames: TProc<TArray<string>> read FOnNames write FOnNames;
    /// <summary>True, solange ein Aufbau die Projektstufe noch nicht hinter sich hat. Threadsicher.</summary>
    property ProjectPending: Boolean read FProjectPending;
    /// <summary>Nach dem Lesen der Einstellungen, für serverweite Werte wie das Zeitlimit (#283).</summary>
    property OnSettingsChanged: TProc<TServerSettings> read FOnSettingsChanged write FOnSettingsChanged;
    /// <summary>True, wenn AFileName zum Projekt gehört (DCCReference, Hauptdatei oder Suchpfad-Unit). Threadsicher.</summary>
    function ContainsFile(const AFileName: string): Boolean;
    /// <summary>Projekt aus der Gruppe, das mit index.projectGroup = false noch wartet: jetzt indizieren.</summary>
    procedure Activate;
    /// <summary>Vor Load setzen (#648): feste Projektdatei, Reihenfolge, gemeinsamer Scheduler und ob das
    /// Projekt nur aus der Gruppe stammt.</summary>
    property ProjectFile: string read FFixedProject write FFixedProject;
    /// <summary>Vor Load setzen (#1112): Ordner der Index-Caches; Vorgabe TIndexCacheDirectory.DefaultRoot.
    /// </summary>
    property CacheRoot: string read FCacheRoot write FCacheRoot;
    property Priority: Integer read FPriority write FPriority;
    property Scheduler: TIndexScheduler read FScheduler write FScheduler;
    property Deferred: Boolean read FDeferred write FDeferred;
    /// <summary>Thread der Nachrichtenschleife: Reload aus einem anderen Thread löst EInvalidOpException aus
    /// (Code-Review A-03). 0 = keine Prüfung, z. B. MCP, Linter, Tests.</summary>
    property LoopThreadId: TThreadID read FLoopThreadId write FLoopThreadId;
    /// <summary>Vor Load setzen (#396): Was die IDE für das Projekt meldet, hat Vorrang vor der .dproj.</summary>
    property IdeProjects: TLspIdeProject read FIdeProjects write FIdeProjects;
    /// <summary>Eintrag des Clients, aus dem der Arbeitsbereich stammt (TWorkspaceFolder.Key); zum Entfernen.</summary>
    property Origin: string read FOrigin write FOrigin;
    /// <summary>Ordner, in denen requires-Packages als .dpk gesucht werden (#46), z. B. die Projekte der Gruppe;
    /// vor Load setzen. Danach folgen Projektordner, Such- und Bibliothekspfade.</summary>
    property OnPackageFolders: TFunc<TArray<string>> read FOnPackageFolders write FOnPackageFolders;
    /// <summary>Projektdateien (.dproj) der Gruppe: Was sie in einen Suchpfad übersetzen, gilt für
    /// uses-unit-not-found als vorhanden; vor Load setzen. nil = nur dieses Projekt.</summary>
    property OnGroupProjects: TFunc<TArray<string>> read FOnGroupProjects write FOnGroupProjects;
    /// <summary>Packages des zuletzt geladenen Projekts (#46); nil vor dem ersten Laden. Bleibt bis zur Freigabe
    /// des Arbeitsbereichs gültig. Threadsicher.</summary>
    property PackageLocator: TPackageLocator read GetPackageLocator;
    /// <summary>Unit-Suche des zuletzt geladenen Projekts (#1016); nil vor dem ersten Laden. Threadsicher.</summary>
    function UnitLookup: IRuleUnitLookup;
    /// <summary>Dienste des Projekts für die Prüfregeln (#1112): Symbolindex, Nachladen von Units dieses
    /// Arbeitsbereichs, Namespaces, Unit-Suche, Packages und die Namenskonvention aus dem Projektkontext der IDE.
    /// Ein Weg für LSP-Server, MCP und Linter; projektweite Dienste (ProjectFiles, Nachladen über alle
    /// Arbeitsbereiche) ergänzt, wer mehrere Arbeitsbereiche hält. Threadsicher.</summary>
    function RuleServices: TRuleServices;
    /// <summary>Anwendungsart, Projektname und automatisch erzeugte Formulare für AFileName aus AProject
    /// (#926, #943, #956, #1055); sonst nur der Dateiname. Liest die .dpr über AReadText.</summary>
    class function RuleProjectOf(const AProject: TProjectInfo; const AFileName: string;
      const AReadText: TRuleProjectReadText): TCheckProject; overload; static;
    /// <summary>RuleProjectOf über alle Projekte, die AFileName enthalten (#1112), das bevorzugte zuerst;
    /// zusammengeführt mit MergeRuleProjects.</summary>
    class function RuleProjectOf(const AProjects: TArray<TProjectInfo>; const AFileName: string;
      const AReadText: TRuleProjectReadText): TCheckProject; overload; static;
    /// <summary>Projektkontext einer Datei aus mehreren Projekten (#1112): Das erste Projekt, das die Datei
    /// enthält, liefert Name, Formulare und .dpr. Widersprechen sich die Anwendungsarten (eine Unit im
    /// Konsolen-Testprogramm und im IDE-Package), bleibt die Art Unknown: Art-abhängige Regeln dürfen nicht
    /// für ein Projekt melden, was im anderen richtig ist.</summary>
    class function MergeRuleProjects(const AProjects: TArray<TCheckProject>;
      const AFileName: string): TCheckProject; static;
    /// <summary>Projekt dieses Arbeitsbereichs für projektweite Regeln (#1102) mit Datei und Quelltexten, dazu
    /// der Hauptquelltext; False ohne geladenes Projekt. Threadsicher, liest keine Dateien; Art, Test-Projekt und
    /// Formulare ergänzt TRuleProjectFiles.ProjectOf außerhalb von Sperren.</summary>
    function RuleProject(out AProject: TRuleProject; out AMainSource: string): Boolean;
    /// <summary>Projekt geladen und Index fertig (#1102, #1112)? Sonst der Grund in AReason. Ein Arbeitsbereich,
    /// dessen Projekt noch lädt, kann Verwendungen enthalten, die keiner kennt. Ein Arbeitsbereich ohne Projekt ist
    /// bereit, sobald der Aufbau das festgestellt hat (#1220). Threadsicher.</summary>
    function RuleReady(out AReason: string): Boolean;
    /// <summary>Leert die prozessweiten Ordnerlisten der .pas-/.dcu-Dateien. Für Tests: Je Testordner bliebe sonst
    /// ein Eintrag bis Programmende.</summary>
    class procedure ClearSharedListings; static;
    /// <summary>Vor Load setzen (#46): selectBuild merkt die Wahl dort, der erste Indexaufbau übernimmt sie.</summary>
    property Selection: TProjectSelection read FSelection write FSelection;
    /// <summary>Feste Projektdatei oder die des geladenen Projekts; '' ohne Projekt. Threadsicher.</summary>
    function ProjectFileName: string;
    /// <summary>Vor Load setzen (#62): Prozessnummer, Art (LSP/MCP) und Client für die Anmeldung am Cache.
    /// </summary>
    property ProcessIdentity: TIndexProcessInfo read FProcessIdentity write FProcessIdentity;
    /// <summary>Eigener Index-Cache und die daran angemeldeten Prozesse (#62); False ohne Cache. Threadsicher.
    /// </summary>
    function Processes(out ACacheFile: string; out AProcesses: TArray<TIndexProcessInfo>): Boolean;
  end;

implementation

uses
  System.IOUtils,
  System.JSON,
  System.StrUtils,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.JsonRpc.Messages,
  Atlas.Common.Compiler.CommandLine,
  Atlas.Common.Projects.Paths,
  Atlas.Common.Projects.DprojReader,
  Atlas.Common.Projects.PackageReader,
  Atlas.Common.Projects.UnitLookup,
  Atlas.Common.Projects.DelphiVersions,
  Atlas.Common.Index.ProjectFiles,
  Atlas.Common.Pascal.IncludeFiles,
  Atlas.Common.Index.Adapters.DiskFileSystem,
  Atlas.Common.Index.Adapters.CacheDirectory,
  Atlas.Common.Index.CacheHousekeeping,
  Atlas.Common.Rules.Builtin.RtlTypePatterns,
  Atlas.Common.Rules.Builtin.FormFields,
  Atlas.Common.Rules.WarnSwitches,
  Atlas.Common.Diagnostics.ShutdownLeaks,
  Shell.Platform,
  Shell.Bootstrap;

/// <summary>Neu eingelesene Units nach Grund und belegter Speicher, fürs Diagnoselog (Rückmeldung 22.10.2026).</summary>
function MissText(const AResult: TIndexBuildResult): string;
begin
  Result := Format(' new %d changed %d includes %d usages %d compact %d damaged %d mem %d MB',
    [AResult.Misses[TIndexCacheMiss.NoEntry], AResult.Misses[TIndexCacheMiss.Changed],
     AResult.Misses[TIndexCacheMiss.Includes], AResult.Misses[TIndexCacheMiss.Usages],
     AResult.Misses[TIndexCacheMiss.Compact], AResult.Misses[TIndexCacheMiss.Damaged],
     TShutdownLeaks.AllocatedBytes div (1024 * 1024)]);
end;

type
  /// <summary>.pas-Dateien (für uses-unit-not-found auch .dcu, #1016) je Ordner, geteilt von allen Projekten
  /// des Servers. Neu gelesen, wenn sich der Ordner geändert hat (Datei hinzugefügt oder entfernt).</summary>
  TSharedUnitListings = class
  private type
    TListing = record
      Stamp: TDateTime;
      Files: TArray<string>;
    end;
  private
    class var FLock: TObject;
    class var FListings: TDictionary<string, TListing>;
  public
    class constructor Create;
    class destructor Destroy;
    class function List(AFolder: string): TArray<string>; static;
    /// <summary>.pas- und .dcu-Dateien des Ordners.</summary>
    class function ListUnitFiles(AFolder: string): TArray<string>; static;
    class function Listed(const AFolder, APattern: string): TArray<string>; static;
    class procedure Clear; static;
  end;

class constructor TSharedUnitListings.Create;
begin
  FLock := TObject.Create;
  FListings := TDictionary<string, TListing>.Create;
end;

class destructor TSharedUnitListings.Destroy;
begin
  FListings.Free;
  FLock.Free;
end;

class procedure TSharedUnitListings.Clear;
begin
  TMonitor.Enter(FLock);
  try
    FListings.Clear;
  finally
    TMonitor.Exit(FLock);
  end;
end;

class procedure TShellWorkspace.ClearSharedListings;
begin
  TSharedUnitListings.Clear;
end;

class function TSharedUnitListings.List(AFolder: string): TArray<string>;
begin
  Result := Listed(AFolder, '*.pas');
end;

class function TSharedUnitListings.ListUnitFiles(AFolder: string): TArray<string>;
begin
  Result := Listed(AFolder, '*.pas') + Listed(AFolder, '*.dcu');
end;

class function TSharedUnitListings.Listed(const AFolder, APattern: string): TArray<string>;
var
  Key: string;
  Listing: TListing;
  Stamp: TDateTime;
begin
  Result := nil;
  try
    if not TDirectory.Exists(AFolder) then
      Exit;
    Stamp := TDirectory.GetLastWriteTime(AFolder);
    Key := AnsiLowerCase(ExcludeTrailingPathDelimiter(AFolder)) + '|' + APattern;
    TMonitor.Enter(FLock);
    try
      if FListings.TryGetValue(Key, Listing) and (Listing.Stamp = Stamp) then
        Exit(Listing.Files);
    finally
      TMonitor.Exit(FLock);
    end;
    Listing.Stamp := Stamp;
    Listing.Files := TDirectory.GetFiles(AFolder, APattern);
    TMonitor.Enter(FLock);
    try
      FListings.AddOrSetValue(Key, Listing);
    finally
      TMonitor.Exit(FLock);
    end;
    Result := Listing.Files;
  except
    // Nicht lesbare Ordner (Rechte, Netzlaufwerk) tragen nichts bei.
    on Exception do
      Result := nil;
  end;
end;

/// <summary>Unit-Suche wie beim Compiler (#1016) über die geteilten Ordnerlisten. Ohne Installation (und ohne
/// Bibliothekspfade aus der IDE) gilt keine Unit als sicher fehlend.</summary>
{ TPackageLocatorHold }

constructor TPackageLocatorHold.Create(ALocator: TPackageLocator);
begin
  inherited Create;
  FLocator := ALocator;
end;

destructor TPackageLocatorHold.Destroy;
begin
  FLocator.Free;
  inherited Destroy;
end;

function TPackageLocatorHold.Locator: TPackageLocator;
begin
  Result := FLocator;
end;

/// <summary>DCU-Ausgabe und Units der anderen Projekte der Gruppe (uses-unit-not-found, 3a): mit derselben
/// Plattform und Konfiguration gelesen. Nicht lesbare Projekte fehlen nur.</summary>
function GroupOutputsFor(const AOwnFile: string; const AFiles: TArray<string>; const AOptions: TDprojOptions;
  const ALogger: ILogger): TArray<TUnitLookupGroupOutput>;
var
  mFile: string;
  mSeen: TArray<string>;
  mProject: TProjectInfo;
  mOutput: TUnitLookupGroupOutput;
  mUnit: TProjectUnit;
begin
  Result := nil;
  mSeen := nil;
  for mFile in AFiles do
  begin
    if SameText(mFile, AOwnFile) or (IndexText(mFile, mSeen) >= 0) then
      Continue;
    mSeen := mSeen + [mFile];
    try
      mProject := TDprojReader.Load(mFile, AOptions);
    except
      on E: Exception do
      begin
        ALogger.Debug(Format('Gruppenprojekt %s für die Unit-Suche nicht lesbar: %s', [mFile, E.Message]));
        Continue;
      end;
    end;
    mOutput := Default(TUnitLookupGroupOutput);
    mOutput.DcuFolder := TUnitLookup.DcuOutputOf(mProject);
    for mUnit in mProject.Units do
      mOutput.Units := mOutput.Units + [mUnit.Name];
    if mOutput.DcuFolder <> '' then
      Result := Result + [mOutput];
  end;
end;
type
  /// <summary>Projekte der Gruppe für die Unit-Suche (uses-unit-not-found): bei jeder Anfrage die aktuelle Liste,
  /// gelesen werden die .dproj nur, wenn sie sich geändert hat. Die IDE meldet die Projekte einzeln und nach dem
  /// ersten an.</summary>
  TGroupOutputCache = class
  private
    FLock: TObject;
    FKey: string;
    // Zuletzt nach der Projektliste gefragt (TThread.GetTickCount64); 0 = nie.
    FCheckedAt: UInt64;
    FOutputs: TArray<TUnitLookupGroupOutput>;
    FFiles: TFunc<TArray<string>>;
    FOwnFile: string;
    FOptions: TDprojOptions;
    FLogger: ILogger;
  public
    constructor Create(const AFiles: TFunc<TArray<string>>; const AOwnFile: string; const AOptions: TDprojOptions;
      const ALogger: ILogger);
    destructor Destroy; override;
    function Current: TArray<TUnitLookupGroupOutput>;
  end;

  IGroupOutputCacheHold = interface
    ['{6B1F4E2A-93C7-4D5B-A8E1-2F7C9D0B3A64}']
    function Cache: TGroupOutputCache;
  end;

  TGroupOutputCacheHold = class(TInterfacedObject, IGroupOutputCacheHold)
  private
    FCache: TGroupOutputCache;
  public
    constructor Create(ACache: TGroupOutputCache);
    destructor Destroy; override;
    function Cache: TGroupOutputCache;
  end;

constructor TGroupOutputCache.Create(const AFiles: TFunc<TArray<string>>; const AOwnFile: string;
  const AOptions: TDprojOptions; const ALogger: ILogger);
begin
  inherited Create;
  FLock := TObject.Create;
  FFiles := AFiles;
  FOwnFile := AOwnFile;
  FOptions := AOptions;
  FLogger := ALogger;
end;

destructor TGroupOutputCache.Destroy;
begin
  FLock.Free;
  inherited;
end;

function TGroupOutputCache.Current: TArray<TUnitLookupGroupOutput>;
const
  // Die Liste fragt die Komposition unter ihrer Sperre ab: nicht bei jeder fehlenden Unit.
  cRecheckMs = 2000;
var
  mFiles: TArray<string>;
  mKey: string;
begin
  System.TMonitor.Enter(FLock);
  try
    if (FCheckedAt <> 0) and (TThread.GetTickCount64 - FCheckedAt < cRecheckMs) then
      Exit(FOutputs);
  finally
    System.TMonitor.Exit(FLock);
  end;
  mFiles := FFiles();
  mKey := AnsiUpperCase(string.Join(';', mFiles));
  System.TMonitor.Enter(FLock);
  try
    if mKey <> FKey then
    begin
      FOutputs := GroupOutputsFor(FOwnFile, mFiles, FOptions, FLogger);
      FKey := mKey;
    end;
    FCheckedAt := TThread.GetTickCount64;
    Result := FOutputs;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

constructor TGroupOutputCacheHold.Create(ACache: TGroupOutputCache);
begin
  inherited Create;
  FCache := ACache;
end;

destructor TGroupOutputCacheHold.Destroy;
begin
  FCache.Free;
  inherited;
end;

function TGroupOutputCacheHold.Cache: TGroupOutputCache;
begin
  Result := FCache;
end;

/// <summary>Rückruf für TUnitLookupSetup.GroupOutputsOf; fängt nur den Halter ein.</summary>
function GroupOutputsOfHold(const AHold: IGroupOutputCacheHold): TFunc<TArray<TUnitLookupGroupOutput>>;
begin
  Result :=
    function: TArray<TUnitLookupGroupOutput>
    begin
      Result := AHold.Cache.Current;
    end;
end;
function UnitLookupFor(const AProject: TProjectInfo; const AInstallation: ILibraryPathProvider;
  const ALibraryPaths: TArray<string>; const AHold: IPackageLocatorHold; const AIndex: ISymbolIndex;
  const AGroupOutputsOf: TFunc<TArray<TUnitLookupGroupOutput>>): IRuleUnitLookup;
var
  Setup: TUnitLookupSetup;
  Text: string;
  SourceFormat: TFileFormat;
  Entry: TPackageEntry;
begin
  Setup := Default(TUnitLookupSetup);
  Setup.Project := AProject;
  Setup.LibraryPaths := ALibraryPaths;
  Setup.LibraryKnown := Length(ALibraryPaths) > 0;
  Setup.GroupOutputsOf := AGroupOutputsOf;
  if AInstallation <> nil then
    Setup.BrowsingPaths := AInstallation.BrowsingPaths(AProject.Platform);
  // requires der .dpk: deren Units findet der Compiler über die .dcp.
  if SameText(ExtractFileExt(AProject.MainSource), '.dpk') then
  try
    Text := TFileEncoding.LoadFromFile(AProject.MainSource, SourceFormat);
    for Entry in TPackageReader.Read(Text).Requires do
      Setup.RequiredPackages := Setup.RequiredPackages + [Entry.Name];
  except
    // Nicht lesbar: ohne requires, dann bleibt die Suche bei Packages unsicher.
    on Exception do
      Setup.RequiredPackages := ['?'];
  end;
  Setup.ListFiles := TSharedUnitListings.ListUnitFiles;
  Setup.ListFolders :=
    function(AFolder: string): TArray<string>
    begin
      Result := nil;
      try
        if TDirectory.Exists(AFolder) then
          Result := TDirectory.GetDirectories(AFolder);
      except
        on Exception do
          Result := nil;
      end;
    end;
  Setup.FileExists :=
    function(AFileName: string): Boolean
    begin
      Result := FileExists(AFileName);
    end;
  Setup.ReadText :=
    function(const AFileName: string; out AText: string): Boolean
    var
      TextFormat: TFileFormat;
    begin
      Result := FileExists(AFileName);
      AText := '';
      if Result then
      try
        AText := TFileEncoding.LoadFromFile(AFileName, TextFormat);
      except
        on Exception do
          Result := False;
      end;
    end;
  // Die anonymen Methoden fangen den Halter ein, nicht den rohen Locator (#1220): Er bleibt, solange sie leben.
  if AHold <> nil then
  begin
    Setup.PackageProvides :=
      function(const APackage, AUnitName: string): TRulePackageAnswer
      var
        Contains: Boolean;
      begin
        if not AHold.Locator.Provides(APackage, AUnitName, Contains) then
          Result := TRulePackageAnswer.Unknown
        else if Contains then
          Result := TRulePackageAnswer.Yes
        else
          Result := TRulePackageAnswer.No;
      end;
    Setup.PackageExists :=
      function(APackage: string): Boolean
      var
        Contains: Boolean;
      begin
        Result := AHold.Locator.Provides(APackage, APackage, Contains);
      end;
    // dcc sieht auch die Units der Packages, die ein requires-Package verlangt (Atlas.Windows → Atlas.Common →
    // Atlas.Text).
    Setup.PackageRequires :=
      function(APackage: string): TArray<string>
      begin
        Result := AHold.Locator.Requires(APackage);
      end;
  end;
  if AIndex <> nil then
  begin
    Setup.IndexKnows :=
      function(AName: string): Boolean
      var
        Found: TUnitIndex;
      begin
        Result := AIndex.FindUnit(AName, Found);
      end;
    Setup.IndexUnits :=
      function: TArray<string>
      var
        Item: TUnitIndex;
      begin
        Result := nil;
        for Item in AIndex.Units do
          Result := Result + [Item.UnitName];
      end;
  end;
  Result := TUnitLookup.Create(Setup);
end;

const
  /// <summary>So lange wartet ein lesender Prozess höchstens auf den Cache des schreibenden (#62).</summary>
  CacheWaitMs = 120000;

{ TShellWorkspace }

constructor TShellWorkspace.Create(const ARoot, AName: string; const AStore: IDocumentStore;
  const ATransport: IJsonRpcTransport; const ALogger: ILogger; const AIndex: ISymbolIndex;
  const AProgressToken: string);
begin
  inherited Create;
  FRoot := ARoot;
  FName := AName;
  FLogger := ALogger;
  FTransport := ATransport;
  FIndex := AIndex;
  FLock := TObject.Create;
  FOwnFiles := TDictionary<string, Boolean>.Create;
  FRetiredResolvers := TObjectList<TUnitResolver>.Create(True);
  FRetiredLocators := TList<IPackageLocatorHold>.Create;
  FLastIndexMs := -1;
  FCacheRoot := TIndexCacheDirectory.DefaultRoot;
  FConfiguration := TLspConfiguration.Create(AStore, ATransport,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := TShellBootstrap.ReadSourceText(AFileName, AText);
    end);
  FConfiguration.OnChanged :=
    procedure(const ASettings: TServerSettings)
    begin
      FLogger.Info(Format('Einstellungen für %s: Delphi %s, Projekt %s, %d Regeleinstellungen, %d Ausschlüsse',
        [FName, ASettings.DelphiVersion, ASettings.Project, Length(ASettings.Rules), Length(ASettings.Exclude)]));
      // Vorgabe-Kodierung (#121) gilt für alle Lese- und Schreibpfade unter diesem Ordner.
      if FRoot <> '' then
        TFileEncodingDefaults.SetFolder(FRoot, ASettings.DefaultEncoding);
      // Der Index ist gemeinsam; bei mehreren Ordnern gilt das zuletzt gelesene Budget.
      FIndex.SetBudget(Int64(ASettings.MemoryBudgetMb) * 1024 * 1024);
      if Assigned(FOnSettingsChanged) then
        FOnSettingsChanged(ASettings);
      StartIndex(ASettings);
    end;
  FIndexService := TIndexService.Create(FIndex, TDiskIndexFileSystem.Create);
  FProgress := TLspWorkDoneProgress.Create(ATransport, AProgressToken);
  FIndexService.OnProgress := FProgress.AsIndexProgress();
  FIndexService.OnProjectReady :=
    procedure(const AResult: TIndexBuildResult; AElapsedMs: Int64)
    begin
      FProjectPending := False;
      IndexEvent(Format('index project#%d projectStage %d ms parsed %d cached %d missing %d',
        [FPriority, AElapsedMs, AResult.Parsed, AResult.FromCache, AResult.Missing]) + MissText(AResult));
      if Assigned(FOnProjectReady) then
        FOnProjectReady();
    end;
  FIndexService.OnFinished :=
    procedure(const AResult: TIndexBuildResult; AElapsedMs: Int64)
    begin
      // Abgebrochen (Neustart): Der neue Aufbau hat FProjectPending schon wieder gesetzt.
      if not AResult.Cancelled then
        FProjectPending := False;
      IndexEvent(Format('index project#%d done %d ms parsed %d cached %d missing %d units %d resolve %d ms parse %d ms%s',
        [FPriority, AElapsedMs, AResult.Parsed, AResult.FromCache, AResult.Missing, FIndex.UnitCount,
         AResult.ResolveMs, AResult.ParseMs, IfThen(AResult.Cancelled, ' cancelled', '')]) + MissText(AResult));
      if not AResult.Cancelled then
      begin
        TMonitor.Enter(FLock);
        try
          FLastIndexMs := AElapsedMs;
          FLastIndex := AResult;
          FLastUpdate := Now;
        finally
          TMonitor.Exit(FLock);
        end;
      end;
      FLogger.Info(Format('Symbolindex für %s fertig in %d ms: %d Units, %d Symbole (%d neu eingelesen, %d aus dem Cache, %d fehlen)%s',
        [FName, AElapsedMs, FIndex.UnitCount, FIndex.SymbolCount, AResult.Parsed, AResult.FromCache, AResult.Missing,
         IfThen(AResult.Cancelled, ', abgebrochen', '')]));
      if not AResult.Cancelled then
      begin
        // Prozesse am Projekt (#62): Der Schreiber hat gespeichert, ein Leser den Stand übernommen.
        if WritesCache then
          ReportProcess(TIndexProcessInfo.StateReady, True, Format('Index gespeichert (%d Units)',
            [AResult.Parsed + AResult.FromCache]))
        else
          ReportProcess(TIndexProcessInfo.StateReady, False, Format('Stand übernommen (%d Units aus dem Cache)',
            [AResult.FromCache]));
        ReportEncodings;
        if Assigned(FOnIndexFinished) then
          FOnIndexFinished();
      end;
    end;
  FIndexService.OnCacheWritten :=
    procedure(ALibrary: Boolean; AUnits: Integer; ABytes, AElapsedMs: Int64)
    begin
      // Wie oft und wie groß geschrieben wird (Rückmeldung 22.10.2026); ohne Pfad.
      IndexEvent(Format('index project#%d cacheWrite %s units %d %d KB %d ms mem %d MB',
        [FPriority, IfThen(ALibrary, 'library', 'project'), AUnits, ABytes div 1024, AElapsedMs,
         TShutdownLeaks.AllocatedBytes div (1024 * 1024)]));
    end;
  FIndexService.OnCacheRejected :=
    procedure(const AFileName, AReason: string)
    var
      Kind: string;
    begin
      // Still neu aufbauen (#492): nur ins Log, keine Meldung an den Benutzer. Ohne Pfad: Das Log bleibt
      // anonym (der Cache liegt im Benutzerprofil). Welcher Cache und warum, steht auch im Diagnose-Log: Ohne
      // Grund war nicht zu sehen, warum ein Rechner bei jedem Start alles neu aufbaut (29.10.2026). Die Gründe
      // von TIndexCache.ReadEntries enthalten keinen Pfad.
      Kind := 'project';
      if Pos(PathDelim + TIndexCacheDirectory.LibraryFolder + PathDelim, AFileName) > 0 then
        Kind := 'library';
      FLogger.Info(Format('Index-Cache verworfen (%s); wird neu aufgebaut', [AReason]));
      IndexEvent(Format('index project#%d cache rejected %s reason %s', [FPriority, Kind, AReason]));
      ReportProcess(TIndexProcessInfo.StateBuilding, WritesCache, Format('Cache verworfen (%s)', [AReason]));
    end;
  FIndexService.OnCacheNotWritten :=
    procedure(const AFileName, AReason: string)
    var
      Kind: string;
    begin
      // Bericht N1: früher still. Der nächste Aufbau liest die fehlenden Units neu; ohne Pfad ins Log.
      Kind := 'Projekt';
      if Pos(PathDelim + TIndexCacheDirectory.LibraryFolder + PathDelim, AFileName) > 0 then
        Kind := 'Bibliothek';
      FLogger.Warning(Format('Index-Cache (%s) nicht geschrieben: %s', [Kind, AReason]));
      IndexEvent('index cache not written ' + Kind);
    end;
  FIndexService.OnError :=
    procedure(const AError: Exception)
    begin
      // Sonst bliebe workspace/diagnostic bis zum nächsten Reload bei indexLoading (Code-Review A-04).
      // StartIndex hält den alten Lauf an, bevor es FProjectPending setzt: Das hier trifft nur den eigenen.
      FProjectPending := False;
      FLogger.Error(Format('Fehler beim Aufbau des Symbolindex für %s: %s: %s', [FName, AError.ClassName, AError.Message]));
      IndexEvent(Format('index project#%d failed %s', [FPriority, AError.ClassName]));
      try
        // Ohne aktiven Fortschritt ein No-op.
        FProgress.Finish('Fehlgeschlagen');
      except
        // Transport schon geschlossen: Das Log genügt.
      end;
      // Teilweise aufgebauter Index: Syntaxprüfung und Pull-Diagnosen sollen ihn trotzdem nutzen.
      if Assigned(FOnIndexFinished) then
        FOnIndexFinished();
    end;
end;

destructor TShellWorkspace.Destroy;
begin
  if FRoot <> '' then
    TFileEncodingDefaults.RemoveFolder(FRoot);
  FIndexService.Free;
  FCacheLock.Free;
  FProgress.Free;
  FUnitResolver.Free;
  FRetiredResolvers.Free;
  FPackageLocator := nil;
  FPackageLocatorHold := nil;
  FRetiredLocators.Free;
  FProcessEntry.Free;
  FConfiguration.Free;
  FOwnFiles.Free;
  FLock.Free;
  FIndex := nil;
  FLogger := nil;
  inherited;
end;

procedure TShellWorkspace.IndexEvent(const AText: string);
begin
  if Assigned(FOnIndexEvent) then
    FOnIndexEvent(AText);
end;

class function TShellWorkspace.Choose(AFound: TShellWorkspace; const AAll: TList<TShellWorkspace>): TShellWorkspace;
begin
  Result := AFound;
  if (Result = nil) and (AAll <> nil) and (AAll.Count = 1) then
    Result := AAll[0];
end;

procedure TShellWorkspace.Load;
begin
  FConfiguration.LoadWorkspace(FRoot);
end;

procedure TShellWorkspace.Load(const AGlobalSettings: string);
begin
  FConfiguration.LoadWorkspace(FRoot, AGlobalSettings);
end;

procedure TShellWorkspace.Reload;
begin
  // StartIndex ändert Zustand ohne Sperre: Andere Threads stellen Reload über TJsonRpcConnection.Queue
  // in die Schleife (A-03).
  if (FLoopThreadId <> 0) and (TThread.Current.ThreadID <> FLoopThreadId) then
    raise EInvalidOpException.Create('Reload nur im Thread der Nachrichtenschleife');
  FSignature := '';
  StartIndex(FConfiguration.Settings);
end;

procedure TShellWorkspace.Rebuild;
begin
  FDiscardCache := True;
  Reload;
end;

procedure TShellWorkspace.Stop;
begin
  FIndexService.Stop;
end;

procedure TShellWorkspace.ReleaseCache;
begin
  FIndexService.Stop;
  FreeAndNil(FCacheLock);
  FCacheLockFile := '';
  ReportProcess(TIndexProcessInfo.StateReady, False, 'Sperre freigegeben (Index löschen)');
end;

procedure TShellWorkspace.ReportProcess(const ACacheFile, AState: string; AWriter: Boolean; const AEvent: string);
var
  Identity: TIndexProcessInfo;
begin
  TMonitor.Enter(FLock);
  try
    if (FProcessEntry = nil) or not SameText(FProcessEntry.CacheFile, ACacheFile) then
    begin
      FreeAndNil(FProcessEntry);
      Identity := FProcessIdentity;
      Identity.Workspace := FName;
      if Identity.Kind = '' then
        Identity.Kind := TIndexProcessInfo.KindLsp;
      FProcessEntry := TIndexProcessEntry.Create(ACacheFile, Identity);
    end;
    FProcessEntry.Update(AState, AWriter, AEvent);
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TShellWorkspace.ReportProcess(const AState: string; AWriter: Boolean; const AEvent: string);
begin
  TMonitor.Enter(FLock);
  try
    if FProcessEntry <> nil then
      FProcessEntry.Update(AState, AWriter, AEvent);
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TShellWorkspace.WritesCache: Boolean;
begin
  TMonitor.Enter(FLock);
  try
    Result := (FProcessEntry <> nil) and FProcessEntry.Info.Writer;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TShellWorkspace.Processes(out ACacheFile: string; out AProcesses: TArray<TIndexProcessInfo>): Boolean;
begin
  TMonitor.Enter(FLock);
  try
    ACacheFile := FCacheFile;
  finally
    TMonitor.Exit(FLock);
  end;
  AProcesses := nil;
  Result := ACacheFile <> '';
  if Result then
    AProcesses := TIndexProcesses.List(ACacheFile);
end;

procedure TShellWorkspace.Touch;
begin
  TMonitor.Enter(FLock);
  try
    FLastUpdate := Now;
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TShellWorkspace.Activate;
begin
  if not FDeferred or FActivated then
    Exit;
  FActivated := True;
  // Mit index.projectGroup = true ist der Arbeitsbereich schon indiziert.
  if Configuration.Settings.IndexProjectGroup then
    Exit;
  FLogger.Info(Format('%s: Datei des Projekts geöffnet, Index wird aufgebaut', [FName]));
  Reload;
end;

function TShellWorkspace.ContainsFile(const AFileName: string): Boolean;
begin
  TMonitor.Enter(FLock);
  try
    Result := FOwnFiles.ContainsKey(AnsiUpperCase(AFileName));
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TShellWorkspace.EnsureUnit(const AUnitName: string): Boolean;
begin
  Result := FIndexService.EnsureUnit(AUnitName);
end;

function TShellWorkspace.ApplyText(const AFileName, AText: string): Boolean;
begin
  Result := FIndexService.ApplyText(AFileName, AText);
  if Result then
    Touch;
end;

function TShellWorkspace.ApplyChanges(const AChanges: TArray<TFileChange>): Integer;
begin
  Result := FIndexService.ApplyChanges(AChanges);
  if Result > 0 then
    Touch;
end;

function TShellWorkspace.CheckSource(const AFileName: string): TCheckSource;
var
  Symbols: TArray<string>;
begin
  if not Defines(Symbols) then
    Symbols := nil;
  Result := TCheckSource.Create(AFileName, Symbols, TIncludeFiles.Resolver(IncludePaths));
end;

function TShellWorkspace.Defines(out ADefines: TArray<string>): Boolean;
begin
  TMonitor.Enter(FLock);
  try
    ADefines := FDefines;
    Result := FHasDefines;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TShellWorkspace.LockCache(const ACacheFile, ALibraryCacheFile, AOrigin: string;
  const ASettings: TServerSettings): Boolean;
var
  Removed: Integer;
  Keep: TArray<string>;
begin
  if SameText(ACacheFile, FCacheLockFile) and (FCacheLock <> nil) then
  begin
    ReportProcess(ACacheFile, TIndexProcessInfo.StateBuilding, True, 'Index wird aktualisiert');
    Exit(True);
  end;
  FreeAndNil(FCacheLock);
  FCacheLockFile := ACacheFile;
  FCacheLock := TIndexCacheDirectory.TryLock(ACacheFile);
  Result := FCacheLock <> nil;
  // Für „Prozesse am Projekt“ (#62): wer schreibt, wer nur liest.
  if Result then
    ReportProcess(ACacheFile, TIndexProcessInfo.StateBuilding, True, 'Cache-Sperre erhalten, Index wird aufgebaut')
  else
    ReportProcess(ACacheFile, TIndexProcessInfo.StateReading, False, 'Sperre belegt, lade Cache nur lesend');
  // Der gemeinsame Bibliotheks-Cache ist nicht gesperrt; ohne ihn hier zu nennen, löschte das Aufräumen
  // ihn bei jedem Start, sobald der Ordner über der Höchstgröße lag (#616: "0 aus dem Cache").
  Keep := TArray<string>.Create(ACacheFile, ALibraryCacheFile);
  try
    // Herkunft und Benutzung vermerken (#905): Danach erkennt jede Instanz verwaiste und ungenutzte Caches.
    if Result then
      TIndexCacheDirectory.WriteOrigin(ACacheFile, AOrigin);
    TIndexCacheDirectory.TouchUse(ACacheFile);
    TIndexCacheDirectory.TouchUse(ALibraryCacheFile);
    // Im Log nur Anzahlen, keine Pfade (anonymes Server-Log).
    if ASettings.IndexRemoveOrphans then
    begin
      Removed := TIndexCacheDirectory.RemoveOrphans(FCacheRoot, Keep);
      if Removed > 0 then
        FLogger.Info(Format('%d verwaiste Index-Caches gelöscht (Projekt nicht mehr vorhanden)', [Removed]));
    end;
    Removed := TIndexCacheDirectory.RemoveUnused(FCacheRoot, ASettings.IndexCacheMaxAgeDays,
      Keep);
    if Removed > 0 then
      FLogger.Info(Format('%d Index-Caches gelöscht (länger als %d Tage nicht benutzt)',
        [Removed, ASettings.IndexCacheMaxAgeDays]));
    Removed := TIndexCacheDirectory.Cleanup(FCacheRoot,
      TIndexCacheHousekeeping.MaxBytesOf(ASettings.IndexCacheMaxMb), Keep);
    if Removed > 0 then
    begin
      FLogger.Info(Format('%d alte Index-Caches gelöscht (Höchstgröße %d MB)', [Removed, ASettings.IndexCacheMaxMb]));
      // Auch ins Diagnose-Log: Ohne --log stand es nirgends, und gelöschte Caches anderer Projektgruppen sahen
      // aus wie ein Cache, der nicht greift (29.10.2026).
      IndexEvent(Format('index project#%d cacheCleanup removed %d limit %d MB', [FPriority, Removed,
        ASettings.IndexCacheMaxMb]));
    end;
  except
    on E: Exception do
      FLogger.Warning(Format('Aufräumen des Cache-Ordners fehlgeschlagen: %s', [E.Message]));
  end;
end;

function TShellWorkspace.DiscardCacheFiles(const ACacheFile, ALibraryCacheFile: string): TProc;
var
  Logger: ILogger;
  CacheFile, LibraryCacheFile: string;
begin
  Logger := FLogger;
  CacheFile := ACacheFile;
  LibraryCacheFile := ALibraryCacheFile;
  Result :=
    procedure
    begin
      if not TFile.Exists(CacheFile) then
        Exit;
      try
        TFile.Delete(CacheFile);
        if TFile.Exists(LibraryCacheFile) then
          TFile.Delete(LibraryCacheFile);
        Logger.Info('Index-Cache verworfen: ' + ExtractFileName(CacheFile));
      except
        on E: Exception do
          Logger.Warning(Format('Index-Cache %s nicht löschbar: %s', [ExtractFileName(CacheFile), E.ClassName]));
      end;
    end;
end;

function TShellWorkspace.SelectBuild(const AConfig, APlatform: string; out AError: string): Boolean;
begin
  Result := SelectBuild(AConfig, APlatform, nil, False, AError);
end;

function TShellWorkspace.SelectBuild(const AConfig, APlatform: string; const ADefines: TArray<string>;
  AHasDefines: Boolean; out AError: string): Boolean;
var
  Define: string;
  Defines: TArray<string>;
begin
  Defines := nil;
  for Define in ADefines do
    if (Trim(Define) <> '') and (IndexText(Trim(Define), Defines) < 0) then
      Defines := Defines + [UpperCase(Trim(Define))];
  TMonitor.Enter(FLock);
  try
    if not FHasProject then
      AError := Format('Für %s ist kein Projekt geladen.', [FName])
    else
      AError := TDprojReader.CheckTarget(FProject, AConfig, APlatform);
    Result := AError = '';
    if Result then
    begin
      if AConfig <> '' then
        FBuildConfig := AConfig;
      if APlatform <> '' then
        FBuildPlatform := APlatform;
      if AHasDefines then
      begin
        FBuildDefines := Defines;
        FHasBuildDefines := True;
      end;
    end;
  finally
    TMonitor.Exit(FLock);
  end;
  if Result then
  begin
    FLogger.Info(Format('%s: Konfiguration %s, Plattform %s gewählt', [FName, AConfig, APlatform]));
    // Über Neustarts merken (#46); die Symbole der IDE kommen nach dem Start neu.
    if (FSelection <> nil) and ((AConfig <> '') or (APlatform <> '')) then
      FSelection.SetBuild(ProjectFileName, AConfig, APlatform);
    if AHasDefines then
      FLogger.Info(Format('%s: %d Symbole aus den Projektoptionen der IDE', [FName, Length(Defines)]));
    Reload;
  end;
end;

function TShellWorkspace.DelphiVersion: string;
begin
  TMonitor.Enter(FLock);
  try
    Result := FDelphiVersion;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TShellWorkspace.BdsRoot: string;
begin
  TMonitor.Enter(FLock);
  try
    Result := FBdsRoot;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TShellWorkspace.LibraryPaths: TArray<string>;
begin
  TMonitor.Enter(FLock);
  try
    Result := FCompilerLibraryPaths;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TShellWorkspace.MissingUnitSetup(out ASetup: TMissingUnitSetup): Boolean;
var
  Project: TProjectInfo;
  Version: string;
  Installation: ILibraryPathProvider;
  Options: TDprojOptions;
  Config, Platform: string;
  Loaded: TProjectInfo;
  Target: TMissingUnitTarget;
begin
  ASetup := Default(TMissingUnitSetup);
  TMonitor.Enter(FLock);
  try
    Result := FHasProject;
    Project := FProject;
    Version := FDelphiVersion;
    ASetup.ActiveLibraryPaths := FCompilerLibraryPaths;
  finally
    TMonitor.Exit(FLock);
  end;
  if not Result then
    Exit;
  ASetup.Project := Project;
  ASetup.Namespaces := Project.Namespaces;
  Installation := nil;
  if Version <> '' then
  try
    Installation := TDelphiInstallation.Create(Version);
  except
    // Installation nicht lesbar: ohne Bibliothek und ohne $(BDS) in den Suchpfaden.
    on EProjectError do
      Installation := nil;
  end;
  Options := Default(TDprojOptions);
  Options.FileExists :=
    function(AFileName: string): Boolean
    begin
      Result := FileExists(AFileName);
    end;
  if Installation <> nil then
    Options.Variables := Installation.Variables;
  // Jede Konfiguration mit jeder Plattform, wie der Compiler sie sähe.
  for Config in Project.Configs do
    for Platform in Project.Platforms do
    begin
      Options.Config := Config;
      Options.Platform := Platform;
      try
        Loaded := TDprojReader.Load(Project.FileName, Options);
      except
        on EProjectError do
          Continue;
      end;
      Target.Config := Config;
      Target.Platform := Platform;
      Target.SearchPaths := Loaded.SearchPaths;
      ASetup.Targets := ASetup.Targets + [Target];
    end;
  if Installation <> nil then
  begin
    ASetup.Platforms := TMissingUnitSearch.KnownPlatforms;
    ASetup.LibraryPaths :=
      function(APlatform: string): TArray<string>
      begin
        try
          Result := Installation.LibraryPaths(APlatform);
        except
          // Plattform nicht installiert.
          on EProjectError do
            Result := nil;
        end;
      end;
  end;
  ASetup.ListFiles := TSharedUnitListings.ListUnitFiles;
  ASetup.ListFolders :=
    function(AFolder: string): TArray<string>
    begin
      Result := nil;
      try
        if TDirectory.Exists(AFolder) then
          Result := TDirectory.GetDirectories(AFolder);
      except
        on Exception do
          Result := nil;
      end;
    end;
end;

function TShellWorkspace.IndexLoading: Integer;
begin
  if FProgress.Active then
    Result := FProgress.Percent
  else
    Result := -1;
end;

function TShellWorkspace.Project(out AProject: TProjectInfo): Boolean;
begin
  TMonitor.Enter(FLock);
  try
    Result := FHasProject;
    if Result then
      AProject := FProject
    else
      AProject := Default(TProjectInfo);
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TShellWorkspace.IndexStatus: TWorkspaceStatus;
begin
  TMonitor.Enter(FLock);
  try
    Result.Name := FName;
    Result.LastIndexMs := FLastIndexMs;
    Result.Parsed := FLastIndex.Parsed;
    Result.FromCache := FLastIndex.FromCache;
    Result.Missing := FLastIndex.Missing;
    Result.LastUpdate := FLastUpdate;
    Result.CacheFile := FCacheFile;
    Result.LibraryCacheFile := FLibraryCacheFile;
    // Projektwahl (#46); aktiv und ausgewählt ergänzt die Komposition.
    Result.Project := FFixedProject;
    if FHasProject then
    begin
      Result.Project := FProject.FileName;
      Result.Config := FProject.Config;
      Result.Platform := FProject.Platform;
    end;
    Result.BuildChosen := (FBuildConfig <> '') or (FBuildPlatform <> '');
  finally
    TMonitor.Exit(FLock);
  end;
  Result.CacheBytes := TIndexCacheDirectory.SizeOf([Result.CacheFile]);
  Result.LibraryCacheBytes := TIndexCacheDirectory.SizeOf([Result.LibraryCacheFile]);
end;

function TShellWorkspace.Baseline: IRuleBaseline;
var
  FileName: string;
  FileTime: TDateTime;
  FileFormat: TFileFormat;
begin
  FileName := ExistingOrLegacyFile(FRoot, BaselineFileName, LegacyBaselineFileName);
  TMonitor.Enter(FLock);
  try
    if not TFile.Exists(FileName) then
    begin
      FBaseline := nil;
      FBaselineTime := 0;
      Exit(nil);
    end;
    FileTime := TFile.GetLastWriteTime(FileName);
    if FileTime <> FBaselineTime then
    begin
      FBaselineTime := FileTime;
      try
        FBaseline := TRuleBaseline.FromJson(TFileEncoding.LoadFromFile(FileName, FileFormat));
        FLogger.Info(Format('Baseline für %s geladen: %d bekannte Treffer', [FName, FBaseline.Count]));
      except
        on E: Exception do
        begin
          FBaseline := nil;
          FLogger.Error(Format('Baseline %s nicht lesbar: %s', [FileName, E.Message]));
        end;
      end;
    end;
    Result := FBaseline;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TShellWorkspace.CompileJob(out AJob: TShellCompileJob; out AError: string): Boolean;
var
  Project: TProjectInfo;
  HasProject: Boolean;
  BdsRoot, Version, OutputDir: string;
  LibraryPaths: TArray<string>;
begin
  AJob := Default(TShellCompileJob);
  AJob.Settings := FConfiguration.Settings.Compiler;
  AError := '';
  TMonitor.Enter(FLock);
  try
    Project := FProject;
    HasProject := FHasProject;
    BdsRoot := FBdsRoot;
    Version := FDelphiVersion;
    LibraryPaths := FCompilerLibraryPaths;
  finally
    TMonitor.Exit(FLock);
  end;
  if not HasProject then
  begin
    AError := 'Kein Projekt geladen';
    Exit(False);
  end;
  if BdsRoot = '' then
  begin
    AError := 'Delphi-Installation nicht gefunden';
    Exit(False);
  end;
  // Eigener Ausgabeordner je Projekt, Plattform und Konfiguration; der Build des Entwicklers bleibt unberührt.
  OutputDir := TPath.Combine(TPath.GetTempPath, Format('Atlas\dcc-%.8x\%s-%s',
    [Cardinal(LowerCase(Project.FileName).GetHashCode), Project.Platform, Project.Config]));
  try
    AJob.Request := TCompilerCommandLine.Build(Project, LibraryPaths, BdsRoot, OutputDir);
    AJob.Project := Project.FileName;
    AJob.Platform := Project.Platform;
    AJob.BdsRoot := BdsRoot;
    AJob.Version := Version;
    // Ob dcc32/dcc64 da ist (Starter Edition, #261), prüft TShellCompilerEditions; der Ausgabeordner
    // entsteht erst, wenn dcc wirklich läuft.
    AJob.OutputDir := OutputDir;
    Result := True;
  except
    on E: ECompilerError do
    begin
      AError := E.Message;
      Result := False;
    end;
  end;
end;

function TShellWorkspace.GetProjectFiles: TArray<string>;
begin
  TMonitor.Enter(FLock);
  try
    Result := FProjectFiles;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TShellWorkspace.ProjectFileName: string;
begin
  TMonitor.Enter(FLock);
  try
    Result := FFixedProject;
    if (Result = '') and FHasProject then
      Result := FProject.FileName;
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TShellWorkspace.RestoreBuild(const AProjectFile: string);
var
  Choice: TProjectBuildChoice;
begin
  if (FSelection = nil) or not FSelection.Build(AProjectFile, Choice) then
  begin
    FBuildRestored := True;
    Exit;
  end;
  TMonitor.Enter(FLock);
  try
    if FBuildRestored then
      Exit;
    FBuildRestored := True;
    if FBuildConfig = '' then
      FBuildConfig := Choice.Config;
    if FBuildPlatform = '' then
      FBuildPlatform := Choice.Platform;
  finally
    TMonitor.Exit(FLock);
  end;
  FLogger.Info(Format('%s: gemerkte Wahl übernommen (Konfiguration %s, Plattform %s)',
    [FName, Choice.Config, Choice.Platform]));
end;

function TShellWorkspace.DropUnknownBuild(const AProject: TProjectInfo): Boolean;
var
  Error: string;
begin
  Error := '';
  TMonitor.Enter(FLock);
  try
    Result := (FBuildConfig <> '') or (FBuildPlatform <> '');
    if Result then
      Error := TDprojReader.CheckTarget(AProject, FBuildConfig, FBuildPlatform);
    Result := Result and (Error <> '');
    if Result then
    begin
      FBuildConfig := '';
      FBuildPlatform := '';
    end;
  finally
    TMonitor.Exit(FLock);
  end;
  if Result then
  begin
    FLogger.Warning(Format('%s: gewählte Konfiguration oder Plattform gibt es nicht mehr (%s); es gelten die Vorgaben',
      [FName, Error]));
    if FSelection <> nil then
      FSelection.SetBuild(AProject.FileName, '', '');
  end;
end;

function TShellWorkspace.UnitLookup: IRuleUnitLookup;
begin
  TMonitor.Enter(FLock);
  try
    Result := FUnitLookup;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TShellWorkspace.RuleServices: TRuleServices;
var
  Hold: IPackageLocatorHold;
  Context: TIdeProjectContext;
  Info: TProjectInfo;
  Pair: TPair<string, string>;
  Entry: string;
begin
  Result := Default(TRuleServices);
  Result.Index := FIndex;
  Result.EnsureUnit :=
    function(const AUnitName: string): Boolean
    begin
      Result := EnsureUnit(AUnitName);
    end;
  Result.Namespaces := Namespaces;
  // Unit-Suche wie beim Compiler für uses-unit-not-found (#1016).
  Result.Units := UnitLookup;
  // requires-Packages für implicit-package-import (#46); der Halter hält den Locator, solange die Prüfung ihn
  // braucht, auch über einen Projektwechsel hinaus (#1220). Nicht gefundene Packages sind unbekannt, damit die Regel
  // still bleibt statt falsch zu melden.
  TMonitor.Enter(FLock);
  try
    Hold := FPackageLocatorHold;
  finally
    TMonitor.Exit(FLock);
  end;
  if Hold <> nil then
    Result.PackageProvides :=
      function(const APackage, AUnitName: string): TRulePackageAnswer
      var
        Contains: Boolean;
      begin
        if not Hold.Locator.Provides(APackage, AUnitName, Contains) then
          Result := TRulePackageAnswer.Unknown
        else if Contains then
          Result := TRulePackageAnswer.Yes
        else
          Result := TRulePackageAnswer.No;
      end;
  // Präfixe der Projektdatei .atlas für naming-prefix und die Korrektur von shadowed-name (#1111).
  if (FIdeProjects <> nil) and (ProjectFileName <> '') and FIdeProjects.Find(ProjectFileName, Context) then
    Result.Naming := Context.RuleNaming;
  // Warnungen der .dproj (DCC_SYMBOL_PLATFORM, DCC_UNSAFE_CODE …) für die Regeln der Gruppe Compiler vorab (#1378).
  if Project(Info) then
    for Pair in Info.Properties do
    begin
      Entry := TRuleWarnSwitches.ProjectEntry(Pair.Key, Pair.Value);
      if Entry <> '' then
        Result.ProjectWarnings := Result.ProjectWarnings + [Entry];
    end;
end;

class function TShellWorkspace.RuleProjectOf(const AProject: TProjectInfo; const AFileName: string;
  const AReadText: TRuleProjectReadText): TCheckProject;
var
  Member: Boolean;
  ProjectUnit: TProjectUnit;
  Pair: TPair<string, string>;
  ConsoleTarget, MainText: string;
begin
  Result := Default(TCheckProject);
  Result.FileName := AFileName;
  // Anwendungsart für writeln-in-gui-app (#926) und queue-nil-in-package (#943), nur für Dateien des Projekts.
  if AProject.MainSource = '' then
    Exit;
  Member := SameText(AProject.MainSource, AFileName);
  for ProjectUnit in AProject.Units do
    if SameText(ProjectUnit.FileName, AFileName) then
      Member := True;
  ConsoleTarget := '';
  for Pair in AProject.Properties do
    if SameText(Pair.Key, 'DCC_ConsoleTarget') then
      ConsoleTarget := Pair.Value;
  if Member and AReadText(AProject.MainSource, MainText) then
  begin
    Result.Application := TWritelnInGuiAppRule.ApplicationKind(ConsoleTarget, MainText);
    Result.Name := ChangeFileExt(ExtractFileName(AProject.MainSource), '');
    // Reihenfolge von Application.CreateForm für form-access-before-create (#956).
    Result.AutoCreateForms := TFormAccessBeforeCreateRule.AutoCreatedForms(MainText);
    // .dpr für die Korrektur von form-autocreate-and-manual (#1055).
    Result.ProjectMainSource := AProject.MainSource;
  end;
end;

class function TShellWorkspace.RuleProjectOf(const AProjects: TArray<TProjectInfo>; const AFileName: string;
  const AReadText: TRuleProjectReadText): TCheckProject;
var
  Projects: TArray<TCheckProject>;
  Project: TProjectInfo;
begin
  Projects := nil;
  for Project in AProjects do
    Projects := Projects + [RuleProjectOf(Project, AFileName, AReadText)];
  Result := MergeRuleProjects(Projects, AFileName);
end;

class function TShellWorkspace.MergeRuleProjects(const AProjects: TArray<TCheckProject>;
  const AFileName: string): TCheckProject;
var
  Project: TCheckProject;
  Found: Boolean;
begin
  Result := Default(TCheckProject);
  Result.FileName := AFileName;
  Found := False;
  for Project in AProjects do
  begin
    // Ohne .dpr gehört die Datei nicht zu diesem Projekt (RuleProjectOf).
    if Project.ProjectMainSource = '' then
      Continue;
    if not Found then
    begin
      Result := Project;
      Result.FileName := AFileName;
      Found := True;
    end
    else if Project.Application <> Result.Application then
      Result.Application := TRuleApplicationKind.Unknown;
  end;
end;

function TShellWorkspace.RuleProject(out AProject: TRuleProject; out AMainSource: string): Boolean;
var
  Info: TProjectInfo;
begin
  AProject := Default(TRuleProject);
  AMainSource := '';
  Result := Project(Info);
  if not Result then
    Exit;
  AProject.FileName := ProjectFileName;
  AProject.Sources := ProjectFiles;
  AMainSource := Info.MainSource;
end;

function TShellWorkspace.RuleReady(out AReason: string): Boolean;
var
  Info: TProjectInfo;
begin
  AReason := '';
  if ProjectPending or not (Project(Info) or FWithoutProject) then
  begin
    AReason := 'Projekte werden geladen';
    Exit(False);
  end;
  if IndexLoading >= 0 then
  begin
    AReason := 'Index wird aufgebaut';
    Exit(False);
  end;
  Result := True;
end;

function TShellWorkspace.GetPackageLocator: TPackageLocator;
begin
  TMonitor.Enter(FLock);
  try
    Result := FPackageLocator;
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TShellWorkspace.AddPackageFiles(const AProject: TProjectInfo; ALocator: TPackageLocator; var AFiles,
  ASearchFiles: TArray<string>);
var
  Text, FileName: string;
  Source: TPackageSource;
  Known: TDictionary<string, Boolean>;
  Added, Required: Integer;
begin
  if not SameText(ExtractFileExt(AProject.MainSource), '.dpk') or
    not TShellBootstrap.ReadSourceText(AProject.MainSource, Text) then
    Exit;
  Source := TPackageReader.Read(Text);
  if not Source.IsPackage then
    Exit;
  Known := TDictionary<string, Boolean>.Create;
  try
    for FileName in AFiles + ASearchFiles do
      Known.AddOrSetValue(AnsiUpperCase(FileName), True);
    Added := 0;
    for FileName in TPackageLocator.ContainedFiles(AProject.MainSource, Source) do
      if not Known.ContainsKey(AnsiUpperCase(FileName)) and FileExists(FileName) then
      begin
        Known.Add(AnsiUpperCase(FileName), True);
        AFiles := AFiles + [FileName];
        Inc(Added);
      end;
    Required := 0;
    for FileName in ALocator.RequiredFiles(Source) do
      if not Known.ContainsKey(AnsiUpperCase(FileName)) and FileExists(FileName) then
      begin
        Known.Add(AnsiUpperCase(FileName), True);
        ASearchFiles := ASearchFiles + [FileName];
        Inc(Required);
      end;
  finally
    Known.Free;
  end;
  if (Added > 0) or (Required > 0) then
    FLogger.Info(Format('%s: Package mit %d Units aus contains ohne DCCReference und %d aus requires-Packages',
      [FName, Added, Required]));
end;

function TShellWorkspace.GetIncludePaths: TArray<string>;
begin
  TMonitor.Enter(FLock);
  try
    Result := FSearchPaths + FCompilerLibraryPaths;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TShellWorkspace.GetNamespaces: TArray<string>;
begin
  TMonitor.Enter(FLock);
  try
    Result := FNamespaces;
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TShellWorkspace.ReportEncodings;
var
  Files: TArray<string>;
  Seen: TDictionary<string, Boolean>;
  FileName, Include: string;
  Survey: TEncodingSurvey;
  UnitIndex: TUnitIndex;
  Text: string;
  Params: TJSONObject;
  Notification: TJSONObject;

  procedure AddFile(const AFileName: string);
  begin
    if Seen.ContainsKey(AnsiUpperCase(AFileName)) or not FileExists(AFileName) then
      Exit;
    Seen.Add(AnsiUpperCase(AFileName), True);
    // Über TFileEncoding: teilt Löschen, damit das Plugin die Unit währenddessen ersetzen kann (Bericht M5).
    Survey.Add(TFileEncoding.ReadAllBytes(AFileName));
  end;

begin
  TMonitor.Enter(FLock);
  try
    Files := FProjectFiles;
  finally
    TMonitor.Exit(FLock);
  end;
  Survey := Default(TEncodingSurvey);
  Survey.AnsiCodePage := TFileEncodingDefaults.CodePageFor(TPath.Combine(FRoot, 'x.pas'));
  // Units, ihre Formulare und Include-Dateien (#121); binäre Formulare zählt die Erhebung nicht.
  Seen := TDictionary<string, Boolean>.Create;
  try
    for FileName in Files do
    begin
      AddFile(FileName);
      AddFile(ChangeFileExt(FileName, '.dfm'));
      AddFile(ChangeFileExt(FileName, '.fmx'));
      if FIndex.FindFile(FileName, UnitIndex) then
        for Include in UnitIndex.Includes do
          AddFile(Include);
    end;
  finally
    Seen.Free;
  end;
  if not Survey.IsMixed then
  begin
    FLogger.Debug(Format('Kodierungen im Projekt %s: %s', [FName, Survey.Describe]));
    Exit;
  end;
  Text := Format('Gemischte Kodierungen im Projekt %s: %s. Beim Schreiben behält jede Datei ihre Kodierung.',
    [FName, Survey.Describe]);
  FLogger.Warning(Text);
  // Das Protokoll sieht im Editor kaum jemand: einmal als Meldung zeigen.
  if FEncodingsShown or (FTransport = nil) then
    Exit;
  FEncodingsShown := True;
  Params := TJSONObject.Create;
  Params.AddPair('type', TJSONNumber.Create(2));
  Params.AddPair('message', Text);
  Notification := TJsonRpcMessages.Notification('window/showMessage', Params);
  try
    FTransport.WriteMessage(Notification);
  finally
    Notification.Free;
  end;
end;

function TShellWorkspace.FindProjectFile(const ASettings: TServerSettings): string;
var
  Candidates: TArray<string>;
begin
  Result := '';
  // Aus der Projektgruppe (#648): Die Datei ist vorgegeben, auch wenn mehrere im Ordner liegen.
  if FFixedProject <> '' then
  begin
    if FileExists(FFixedProject) then
      Result := FFixedProject
    else
      FLogger.Warning('Projektdatei nicht gefunden: ' + FFixedProject);
    Exit;
  end;
  if ASettings.Project <> '' then
  begin
    if TProjectPaths.IsAbsolute(ASettings.Project) then
      Result := ASettings.Project
    else if FRoot <> '' then
      Result := TProjectPaths.Combine(FRoot, ASettings.Project);
    if not FileExists(Result) then
    begin
      FLogger.Warning('Projektdatei nicht gefunden: ' + Result);
      Result := '';
    end;
    Exit;
  end;
  // Ohne Angabe: die einzige .dproj im Ordner.
  if (FRoot = '') or not TDirectory.Exists(FRoot) then
    Exit;
  Candidates := TDirectory.GetFiles(FRoot, '*.dproj');
  if Length(Candidates) = 1 then
    Result := Candidates[0]
  else if Length(Candidates) > 1 then
    FLogger.Info(Format('%d Projektdateien in %s; "project" in %s wählt eine aus',
      [Length(Candidates), FRoot, ConfigurationFileName]));
end;

procedure TShellWorkspace.StartIndex(const ASettings: TServerSettings);
var
  mProjectFile, Signature, State, CacheFile, CacheOrigin: string;
  Installation: ILibraryPathProvider;
  Options: TDprojOptions;
  Project: TProjectInfo;
  LibraryPaths: TArray<string>;
  Request: TIndexRequest;
  Resolver: TUnitResolver;
  FileExistsFunc: TFunc<string, Boolean>;
  ProjectVersion, Version: string;
  mInstalled: TArray<string>;
  ConfiguredMissing: Boolean;
  ListUnits: TIndexListUnits;
  Excluded: TIndexExcluded;
  Exclude, Files, SearchFiles, LibraryFiles: TArray<string>;
  FileName: string;
  Context: TIdeProjectContext;
  HasContext: Boolean;
  CompilerLibraryPaths: TArray<string>;
  Names: TArray<string>;
  ProjectUnit: TProjectUnit;
  PackageFolders: TArray<string>;
  GroupOutputsOf: TFunc<TArray<TUnitLookupGroupOutput>>;
  Locator: TPackageLocator;
  Hold: IPackageLocatorHold;
  Lookup: IRuleUnitLookup;
begin
  // Mit index.projectGroup = false nur das Projekt der geöffneten Datei (#648).
  if FDeferred and not FActivated and not ASettings.IndexProjectGroup then
  begin
    FLogger.Info(Format('%s: index.projectGroup ist aus; indiziert wird, sobald eine Datei des Projekts offen ist',
      [FName]));
    FWithoutProject := True;
    Exit;
  end;
  mProjectFile := FindProjectFile(ASettings);
  // Ohne Projekt indiziert dieser Arbeitsbereich nichts; Prüfungen sollen dann nicht auf ihn warten. Sonst liefen
  // die indexabhängigen Regeln in einem Ordner ohne Projekt nie (#1220).
  FWithoutProject := mProjectFile = '';
  if FWithoutProject then
    Exit;
  // In der IDE bestimmt die IDE Konfiguration, Plattform, Optionen und Delphi-Version (#396).
  Context := Default(TIdeProjectContext);
  HasContext := (FIdeProjects <> nil) and FIdeProjects.Find(mProjectFile, Context);
  // Konfiguration vor ProjectVersion der .dproj vor neuester Installation (#47).
  try
    ProjectVersion := TDelphiVersions.ProjectVersionOf(TFileEncoding.LoadText(mProjectFile));
  except
    on Exception do
      ProjectVersion := '';
  end;
  mInstalled := TDelphiInstallation.Versions;
  try
    if HasContext and (Context.BdsVersion <> '') and (IndexText(Context.BdsVersion, mInstalled) >= 0) then
      Version := Context.BdsVersion
    else
    begin
      // Ohne Installation die erwartete Version: Sie liefert nur die Symbole (#1321).
      Version := TDelphiVersions.Choose(ASettings.DelphiVersion, ProjectVersion, mInstalled, ConfiguredMissing);
      // Die Warnung steht auch an "delphiVersion" in atlas.json (#47).
      if ConfiguredMissing then
        FLogger.Warning(Format('%s: delphiVersion %s ist nicht installiert; automatisch gewählt: %s',
          [FName, ASettings.DelphiVersion, Version]));
    end;
    if TDelphiVersions.IsInstalled(Version, mInstalled) then
    begin
      Installation := TDelphiInstallation.Create(Version);
      FLogger.Info(Format('%s: %s (BDS %s, ProjectVersion %s)',
        [FName, TDelphiVersions.ProductName(Version), Version, ProjectVersion]));
    end
    else
    begin
      Installation := nil;
      FLogger.Info(Format('%s: kein Delphi installiert; Symbole wie %s (BDS %s, ProjectVersion %s), ' +
        'ohne Bibliothekspfade', [FName, TDelphiVersions.ProductName(Version), Version, ProjectVersion]));
    end;
  except
    // Version bleibt: CompilerVersion und VERxxx hängen nicht an den Pfaden der Installation (#1321).
    on E: EProjectError do
    begin
      FLogger.Warning('Delphi-Installation nicht gefunden: ' + E.Message);
      Installation := nil;
    end;
  end;
  FileExistsFunc :=
    function(AFileName: string): Boolean
    begin
      Result := FileExists(AFileName);
    end;
  RestoreBuild(mProjectFile);
  Options := Default(TDprojOptions);
  Options.Config := ASettings.Config;
  Options.Platform := ASettings.Platform;
  TMonitor.Enter(FLock);
  try
    if FBuildConfig <> '' then
      Options.Config := FBuildConfig;
    if FBuildPlatform <> '' then
      Options.Platform := FBuildPlatform;
  finally
    TMonitor.Exit(FLock);
  end;
  if HasContext and (Context.Configuration <> '') then
    Options.Config := Context.Configuration;
  if HasContext and (Context.Platform <> '') then
    Options.Platform := Context.Platform;
  Options.FileExists := FileExistsFunc;
  if Installation <> nil then
    Options.Variables := Installation.Variables;
  try
    Project := TDprojReader.Load(mProjectFile, Options);
    // Gemerkte Wahl (#46), die es im Projekt nicht mehr gibt: mit den Vorgaben weiter.
    if DropUnknownBuild(Project) then
    begin
      Options.Config := ASettings.Config;
      Options.Platform := ASettings.Platform;
      if HasContext and (Context.Configuration <> '') then
        Options.Config := Context.Configuration;
      if HasContext and (Context.Platform <> '') then
        Options.Platform := Context.Platform;
      Project := TDprojReader.Load(mProjectFile, Options);
    end;
  except
    on E: EProjectError do
    begin
      FLogger.Error(Format('Projekt %s nicht lesbar: %s', [mProjectFile, E.Message]));
      Exit;
    end;
  end;
  CompilerLibraryPaths := nil;
  if Installation <> nil then
    CompilerLibraryPaths := Installation.LibraryPaths(Project.Platform);
  if HasContext then
  begin
    if Installation <> nil then
    begin
      Context.ApplyTo(Project, Installation.Variables);
      if Length(Context.LibraryPaths) > 0 then
        CompilerLibraryPaths := Context.ExpandedLibraryPaths(Project, Installation.Variables);
    end
    else
    begin
      Context.ApplyTo(Project, nil);
      if Length(Context.LibraryPaths) > 0 then
        CompilerLibraryPaths := Context.ExpandedLibraryPaths(Project, nil);
    end;
    FLogger.Info(Format('%s: Projektkontext aus der IDE (%s, %s, %d Symbole, %d Suchpfade)',
      [FName, Project.Config, Project.Platform, Length(Project.Defines), Length(Project.SearchPaths)]));
  end;
  // Symbole aus den Projektoptionen der IDE gelten vor denen der Datei (#615).
  TMonitor.Enter(FLock);
  try
    if FHasBuildDefines then
      Project.Defines := FBuildDefines;
  finally
    TMonitor.Exit(FLock);
  end;
  if Assigned(FOnNames) then
  begin
    Names := [ChangeFileExt(ExtractFileName(Project.FileName), ''),
      ChangeFileExt(ExtractFileName(Project.MainSource), '')];
    for ProjectUnit in Project.Units do
      Names := Names + [ProjectUnit.Name];
    FOnNames(Names);
  end;
  TMonitor.Enter(FLock);
  try
    FProject := Project;
    FHasProject := True;
    if Installation <> nil then
    begin
      FDelphiVersion := Version;
      FBdsRoot := TCompilerCommandLine.BdsRoot(Installation.Variables);
      FCompilerLibraryPaths := CompilerLibraryPaths;
    end
    else
    begin
      FDelphiVersion := '';
      FBdsRoot := '';
      FCompilerLibraryPaths := nil;
    end;
  finally
    TMonitor.Exit(FLock);
  end;
  Signature := TIndexProjectFiles.Signature(Project, Version);
  if Installation <> nil then
    LibraryPaths := CompilerLibraryPaths + Installation.BrowsingPaths(Project.Platform)
  else
    LibraryPaths := nil;
  // Alle Units der Such- und Bibliothekspfade (#648), nicht nur die über uses erreichbaren.
  ListUnits :=
    function(const AFolder: string): TArray<string>
    begin
      Result := nil;
      try
        if TDirectory.Exists(AFolder) then
          Result := TDirectory.GetFiles(AFolder, '*.pas');
      except
        // Nicht lesbare Ordner (Rechte, Netzlaufwerk) tragen nichts bei.
        on Exception do
          Result := nil;
      end;
    end;
  Exclude := ASettings.IndexExclude;
  Excluded :=
    function(const AFileName: string): Boolean
    var
      Pattern: string;
    begin
      for Pattern in Exclude do
        if MatchesGlob(Pattern, AFileName) then
          Exit(True);
      Result := False;
    end;
  Files := TIndexProjectFiles.Files(Project);
  SearchFiles := nil;
  if ASettings.IndexSearchPaths then
    SearchFiles := TIndexProjectFiles.PathFiles(Project.SearchPaths, ListUnits, Excluded, Files);
  LibraryFiles := nil;
  if ASettings.IndexLibraryPaths then
    LibraryFiles := TIndexProjectFiles.PathFiles(LibraryPaths, ListUnits, Excluded, Files + SearchFiles);
  // requires-Packages (#46): Quelle .dpk in den Ordnern der Gruppe, im Projektordner und in den Suchpfaden,
  // übersetzt .dcp in den Bibliothekspfaden.
  PackageFolders := nil;
  if Assigned(FOnPackageFolders) then
    PackageFolders := FOnPackageFolders();
  Locator := TPackageLocator.Create(PackageFolders + [ExtractFileDir(mProjectFile)] + Project.SearchPaths +
    CompilerLibraryPaths);
  Hold := TPackageLocatorHold.Create(Locator);
  TMonitor.Enter(FLock);
  try
    if FPackageLocatorHold <> nil then
      FRetiredLocators.Add(FPackageLocatorHold);
    FPackageLocatorHold := Hold;
    FPackageLocator := Locator;
  finally
    TMonitor.Exit(FLock);
  end;
  GroupOutputsOf := nil;
  if Assigned(FOnGroupProjects) then
    GroupOutputsOf := GroupOutputsOfHold(TGroupOutputCacheHold.Create(TGroupOutputCache.Create(FOnGroupProjects,
      mProjectFile, Options, FLogger)));
  Lookup := UnitLookupFor(Project, Installation, CompilerLibraryPaths, Hold, FIndex, GroupOutputsOf);
  TMonitor.Enter(FLock);
  try
    FUnitLookup := Lookup;
  finally
    TMonitor.Exit(FLock);
  end;
  AddPackageFiles(Project, Locator, Files, SearchFiles);
  // Neu indexieren, wenn sich Schlüssel oder Unit-Listen ändern; der Cache hängt nur am Schlüssel.
  State := Signature + '#' + AnsiUpperCase(String.Join(';', Files)) + '#' +
    AnsiUpperCase(String.Join(';', SearchFiles)) + '#' + AnsiUpperCase(String.Join(';', LibraryFiles));
  if State = FSignature then
    Exit;
  FSignature := State;
  // Kein Stop hier (#874): Start bricht den laufenden Aufbau ab, ohne in der Nachrichtenschleife auf ihn zu
  // warten; der neue Aufbau beginnt erst nach dessen Ende.
  Resolver := TUnitResolver.Create(Project, LibraryPaths, FileExistsFunc);
  // Ordner einmal auflisten, über alle Projekte geteilt (CPU beim Start).
  Resolver.ListUnits := TSharedUnitListings.List;
  // Nicht freigeben: Anfragen können den alten Builder noch nutzen (EnsureUnit ohne Sperre, #647).
  if FUnitResolver <> nil then
    FRetiredResolvers.Add(FUnitResolver);
  FUnitResolver := Resolver;
  Request.Files := Files;
  Request.SearchFiles := SearchFiles;
  Request.LibraryFiles := LibraryFiles;
  Request.Priority := FPriority;
  FIndexService.Scheduler := FScheduler;
  Request.Defines := TIndexProjectFiles.Defines(Project, Version);
  // RTL, VCL und FMX einmal je Compiler und Plattform, unabhängig von Projekt und Konfiguration (#647).
  // Nur der Ordner der Installation: Eigener Code im Bibliothekspfad wird oft mit dem Projekt übersetzt.
  if Installation <> nil then
  begin
    Request.LibraryRoots := [TCompilerCommandLine.BdsRoot(Installation.Variables)];
    Request.LibraryDefines := TIndexProjectFiles.LibraryDefines(Project, Version);
  end;
  // $I-Dateien wie beim Compiler: Projekt-Suchpfade, dann Bibliothekspfade (#264).
  if Installation <> nil then
    Request.IncludePaths := Project.SearchPaths + CompilerLibraryPaths
  else
    Request.IncludePaths := Project.SearchPaths;
  Request.ResolveUnit :=
    function(const AUnitName: string): string
    begin
      Result := Resolver.Resolve(AUnitName);
    end;
  // Ablage je IDE-Version und Projekt (#492): %LOCALAPPDATA%\Atlas\Index\<Version>\<Projekt-Hash>.
  CacheFile := TIndexCacheDirectory.FileFor(FCacheRoot, Version, Signature);
  Request.CacheFile := CacheFile;
  // RTL/VCL/FMX einmal je Compilerversion und Plattform, geteilt mit allen Projekten (#492, #647).
  Request.LibraryCacheFile := TIndexCacheDirectory.LibraryFileFor(FCacheRoot, Version,
    TIndexProjectFiles.LibrarySignature(Project, Version));
  Request.Usages := ASettings.IndexUsages;
  // Herkunft für das Aufräumen (#905): die Projektdatei, ohne sie der Arbeitsordner.
  CacheOrigin := Project.FileName;
  if CacheOrigin = '' then
    CacheOrigin := FRoot;
  Request.ReadOnlyCache := not LockCache(CacheFile, Request.LibraryCacheFile, CacheOrigin, ASettings);
  if Request.ReadOnlyCache then
  begin
    FLogger.Info(Format('Cache %s wird von einer anderen Instanz geschrieben und hier nur gelesen', [CacheFile]));
    // Auf deren Stand warten statt alles doppelt zu lesen (#62), begrenzt.
    Request.CacheBusy :=
      function: Boolean
      begin
        Result := TIndexCacheDirectory.IsLocked(CacheFile);
      end;
    Request.CacheWaitMs := CacheWaitMs;
  end;
  if FDiscardCache then
  begin
    FDiscardCache := False;
    // Im Index-Thread nach dem Ende des alten Aufbaus löschen: Sonst schriebe er den Cache danach wieder.
    if not Request.ReadOnlyCache then
      Request.Prepare := DiscardCacheFiles(CacheFile, Request.LibraryCacheFile);
  end;
  TMonitor.Enter(FLock);
  try
    // Dieselben Symbole bestimmen, welche {$IFDEF}-Zweige der Editor abblendet.
    FDefines := Request.Defines;
    FHasDefines := True;
    FNamespaces := Project.Namespaces;
    FSearchPaths := Project.SearchPaths;
    FProjectFiles := Request.Files;
    FSearchFiles := Request.SearchFiles;
    FCacheFile := Request.CacheFile;
    FLibraryCacheFile := Request.LibraryCacheFile;
    FOwnFiles.Clear;
    for FileName in Request.Files + Request.SearchFiles do
      FOwnFiles.AddOrSetValue(AnsiUpperCase(FileName), True);
  finally
    TMonitor.Exit(FLock);
  end;
  FLogger.Info(Format('Symbolindex für %s (%s, %s): %d Projektdateien, %d Units der Suchpfade, %d der Bibliothek, Cache %s',
    [mProjectFile, Project.Config, Project.Platform, Length(Request.Files), Length(Request.SearchFiles),
     Length(Request.LibraryFiles), CacheFile]));
  IndexEvent(Format('index project#%d start files %d search %d library %d cache %s',
    [FPriority, Length(Request.Files), Length(Request.SearchFiles), Length(Request.LibraryFiles),
     IfThen(Request.ReadOnlyCache, 'readOnly', 'write')]));
  FProjectPending := True;
  FIndexService.Start(Request);
  if Assigned(FOnProjectLoaded) then
    FOnProjectLoaded();
end;

end.
