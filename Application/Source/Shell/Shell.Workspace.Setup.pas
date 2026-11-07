unit Shell.Workspace.Setup;

// Contract-Rolle Shell: Vorgaben eines Arbeitsbereichs, die der Aufrufer vor Load setzt (Projektgruppe #648,
// Index-Caches #1112, IDE-Projekte #396, Projektwahl #46, Prozessanmeldung #62), und seine Ereignisse.

interface

uses
  System.SysUtils,
  System.Classes,
  Atlas.Common.Logging.Contract,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Lsp.IdeProject,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Projects.Selection,
  Atlas.Common.Index.Scheduler,
  Atlas.Common.Index.Processes;

type
  /// <summary>Dienste, die ein Arbeitsbereich vom Server bekommt: Dokumente, Transport zum Client, Protokoll,
  /// der gemeinsame Symbolindex und das Fortschrittszeichen des Indexaufbaus.</summary>
  TShellWorkspaceServices = record
    Store: IDocumentStore;
    Transport: IJsonRpcTransport;
    Logger: ILogger;
    Index: ISymbolIndex;
    ProgressToken: string;
    class function Create(const AStore: IDocumentStore; const ATransport: IJsonRpcTransport; const ALogger: ILogger;
      const AIndex: ISymbolIndex; const AProgressToken: string): TShellWorkspaceServices; static;
  end;

  /// <summary>Vor Load zu setzen; danach nur noch lesen.</summary>
  TShellWorkspaceSetup = class
  private
    FProjectFile: string;
    FCacheRoot: string;
    FPriority: Integer;
    FScheduler: TIndexScheduler;
    FDeferred: Boolean;
    FActivated: Boolean;
    FLoopThreadId: TThreadID;
    FIdeProjects: TLspIdeProject;
    FIdeTypes: IRuleIdeTypes;
    FOrigin: string;
    FOnPackageFolders: TFunc<TArray<string>>;
    FOnGroupProjects: TFunc<TArray<string>>;
    FSelection: TProjectSelection;
    FProcessIdentity: TIndexProcessInfo;
  public
    constructor Create;
    /// <summary>Ordner aus OnPackageFolders; nil ohne Rückruf.</summary>
    function PackageFolders: TArray<string>;
    /// <summary>Was die IDE für AProjectFile meldet (#396); False ohne IDE-Projekte oder Eintrag.</summary>
    function IdeContext(const AProjectFile: string; out AContext: TIdeProjectContext): Boolean;
    /// <summary>Fest vorgegebene Projektdatei (Projektgruppe, #648); '' = im Ordner suchen.</summary>
    property ProjectFile: string read FProjectFile write FProjectFile;
    /// <summary>Ordner der Index-Caches (#1112, --index-cache); Vorgabe TIndexCacheDirectory.DefaultRoot.
    /// </summary>
    property CacheRoot: string read FCacheRoot write FCacheRoot;
    /// <summary>Reihenfolge im gemeinsamen Scheduler; auch die Nummer im Diagnoselog.</summary>
    property Priority: Integer read FPriority write FPriority;
    property Scheduler: TIndexScheduler read FScheduler write FScheduler;
    /// <summary>Aus der Projektgruppe: Mit index.projectGroup = false erst indizieren, wenn eine Datei des
    /// Projekts geöffnet wird (TShellWorkspace.Activate).</summary>
    property Deferred: Boolean read FDeferred write FDeferred;
    /// <summary>Eine Datei des zurückgestellten Projekts war offen.</summary>
    property Activated: Boolean read FActivated write FActivated;
    /// <summary>Thread der Nachrichtenschleife: Reload aus einem anderen Thread löst EInvalidOpException aus
    /// (Code-Review A-03). 0 = keine Prüfung, z. B. MCP, Linter, Tests.</summary>
    property LoopThreadId: TThreadID read FLoopThreadId write FLoopThreadId;
    /// <summary>Projektkontexte aus der IDE (#396): Was die IDE meldet, hat Vorrang vor der .dproj. nil ohne
    /// Plugin; gehört der Komposition.</summary>
    property IdeProjects: TLspIdeProject read FIdeProjects write FIdeProjects;
    /// <summary>Typen der laufenden IDE ohne Quelltext (atlas/ideTypes) für die Prüfregeln; nil ohne Plugin.
    /// </summary>
    property IdeTypes: IRuleIdeTypes read FIdeTypes write FIdeTypes;
    /// <summary>Eintrag des Clients, aus dem der Arbeitsbereich stammt (TWorkspaceFolder.Key); zum Entfernen.</summary>
    property Origin: string read FOrigin write FOrigin;
    /// <summary>Ordner, in denen requires-Packages als .dpk gesucht werden (#46), z. B. die Projekte der Gruppe.
    /// Danach folgen Projektordner, Such- und Bibliothekspfade.</summary>
    property OnPackageFolders: TFunc<TArray<string>> read FOnPackageFolders write FOnPackageFolders;
    /// <summary>Projektdateien (.dproj) der Gruppe: Was sie in einen Suchpfad übersetzen, gilt für
    /// uses-unit-not-found als vorhanden. nil = nur dieses Projekt.</summary>
    property OnGroupProjects: TFunc<TArray<string>> read FOnGroupProjects write FOnGroupProjects;
    /// <summary>Gemerkte Wahl über Neustarts (#46): selectBuild merkt sie dort, der erste Indexaufbau übernimmt
    /// sie. Gehört der Komposition, nil = nichts merken.</summary>
    property Selection: TProjectSelection read FSelection write FSelection;
    /// <summary>Prozessnummer, Art (LSP/MCP) und Client für die Anmeldung am Cache (#62).</summary>
    property ProcessIdentity: TIndexProcessInfo read FProcessIdentity write FProcessIdentity;
  end;

  /// <summary>Ereignisse eines Arbeitsbereichs; jedes darf fehlen.</summary>
  TShellWorkspaceEvents = class
  private
    FOnProjectLoaded: TProc;
    FOnIndexFinished: TProc;
    FOnProjectReady: TProc;
    FOnIndexEvent: TProc<string>;
    FOnNames: TProc<TArray<string>>;
    FOnSettingsChanged: TProc<TServerSettings>;
  public
    procedure ProjectLoaded;
    procedure IndexFinished;
    procedure ProjectReady;
    procedure IndexEvent(const AText: string);
    procedure Names(const ANames: TArray<string>);
    procedure SettingsChanged(const ASettings: TServerSettings);
    /// <summary>Nach dem Laden eines Projekts (Defines und Namespaces neu).</summary>
    property OnProjectLoaded: TProc read FOnProjectLoaded write FOnProjectLoaded;
    /// <summary>Nach einem vollständigen (nicht abgebrochenen) Indexaufbau; im Index-Thread.</summary>
    property OnIndexFinished: TProc read FOnIndexFinished write FOnIndexFinished;
    /// <summary>Projektstufe des Aufbaus fertig (Projektdateien und über uses erreichbare Units); im
    /// Index-Thread.</summary>
    property OnProjectReady: TProc read FOnProjectReady write FOnProjectReady;
    /// <summary>Zeile fürs Diagnoselog (#647), nur Zahlen und feste Wörter; im Index- oder
    /// Nachrichten-Thread.</summary>
    property OnIndexEvent: TProc<string> read FOnIndexEvent write FOnIndexEvent;
    /// <summary>Projekt- und Unit-Namen nach dem Lesen der .dproj, damit das Server-Log sie verbirgt (#647).</summary>
    property OnNames: TProc<TArray<string>> read FOnNames write FOnNames;
    /// <summary>Nach dem Lesen der Einstellungen, für serverweite Werte wie das Zeitlimit (#283).</summary>
    property OnSettingsChanged: TProc<TServerSettings> read FOnSettingsChanged write FOnSettingsChanged;
  end;

implementation

uses
  Atlas.Common.Index.Adapters.CacheDirectory;

{ TShellWorkspaceServices }

class function TShellWorkspaceServices.Create(const AStore: IDocumentStore; const ATransport: IJsonRpcTransport;
  const ALogger: ILogger; const AIndex: ISymbolIndex; const AProgressToken: string): TShellWorkspaceServices;
begin
  Result.Store := AStore;
  Result.Transport := ATransport;
  Result.Logger := ALogger;
  Result.Index := AIndex;
  Result.ProgressToken := AProgressToken;
end;

{ TShellWorkspaceSetup }

constructor TShellWorkspaceSetup.Create;
begin
  inherited Create;
  FCacheRoot := TIndexCacheDirectory.DefaultRoot;
end;

function TShellWorkspaceSetup.PackageFolders: TArray<string>;
begin
  Result := nil;
  if Assigned(FOnPackageFolders) then
  begin
    Result := FOnPackageFolders();
  end;
end;

function TShellWorkspaceSetup.IdeContext(const AProjectFile: string; out AContext: TIdeProjectContext): Boolean;
begin
  AContext := Default(TIdeProjectContext);
  Result := (FIdeProjects <> nil) and (AProjectFile <> '') and FIdeProjects.Find(AProjectFile, AContext);
end;

{ TShellWorkspaceEvents }

procedure TShellWorkspaceEvents.ProjectLoaded;
begin
  if Assigned(FOnProjectLoaded) then
  begin
    FOnProjectLoaded();
  end;
end;

procedure TShellWorkspaceEvents.IndexFinished;
begin
  if Assigned(FOnIndexFinished) then
  begin
    FOnIndexFinished();
  end;
end;

procedure TShellWorkspaceEvents.ProjectReady;
begin
  if Assigned(FOnProjectReady) then
  begin
    FOnProjectReady();
  end;
end;

procedure TShellWorkspaceEvents.IndexEvent(const AText: string);
begin
  if Assigned(FOnIndexEvent) then
  begin
    FOnIndexEvent(AText);
  end;
end;

procedure TShellWorkspaceEvents.Names(const ANames: TArray<string>);
begin
  if Assigned(FOnNames) then
  begin
    FOnNames(ANames);
  end;
end;

procedure TShellWorkspaceEvents.SettingsChanged(const ASettings: TServerSettings);
begin
  if Assigned(FOnSettingsChanged) then
  begin
    FOnSettingsChanged(ASettings);
  end;
end;

end.
