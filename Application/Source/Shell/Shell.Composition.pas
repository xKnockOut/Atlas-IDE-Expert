unit Shell.Composition;

// Host-Rolle Shell: Komposition des Servers von Hand (DI-Strategie ohne Container).
// Verbindet stdin/stdout, Transport, Dispatcher, Lebenszyklus, Dokumentverwaltung,
// Syntaxdiagnosen, Nachrichtenschleife, Logging, Zeitlimit für Anfragen und
// Absturzprotokoll mit Stacktrace, Absturzfällen und Sicherheitsnetz
// (Shell.CrashCases, #1355). Jeder Ordner des Arbeitsbereichs hat
// eigene Konfiguration, eigenes Projekt und eigenen Indexaufbau
// (TShellWorkspace); der Symbolindex ist gemeinsam.

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  Atlas.Common.Logging.Contract,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.Connection,
  Atlas.Common.JsonRpc.TracingTransport,
  Atlas.Common.Lsp.ApplyEdit,
  Atlas.Common.Lsp.TextDocumentSync,
  Atlas.Common.Lsp.WorkspaceCheck,
  Atlas.Common.Lsp.Hover,
  Atlas.Common.Lsp.TestUnits,
  Atlas.Common.Lsp.Completion,
  Atlas.Common.Pascal.Preprocessor,
  Atlas.Common.Pascal.FormatRoutines,
  Atlas.Common.Query.Contract,
  Atlas.Common.Architecture.UsesService,
  Atlas.Common.Editing.Contract,
  Shell.Composition.Status,
  Shell.Composition.Contract,
  Shell.Composition.Workspaces,
  Shell.Composition.FileChanges,
  Shell.Composition.CompileSetup,
  Shell.Composition.Stdio,
  Shell.Composition.Core,
  Shell.Composition.AnalysisArea,
  Shell.Composition.CodeArea,
  Shell.Composition.CommandArea,
  Shell.Composition.DiagnosticsArea,
  Shell.Composition.DocumentEvents,
  Shell.Composition.Protocol,
  Shell.Composition.Session,
  Shell.Composition.IdeArea,
  Shell.Composition.EditingArea,
  Shell.Composition.IndexArea,
  Shell.Composition.Capabilities,
  Shell.Composition.ServerCommands,
  Atlas.Common.Lsp.Status,
  Atlas.Common.Projects.Selection,
  Atlas.Common.Logging.Providers.RecentSink,
  Atlas.Common.Lsp.WatchedFiles,
  Atlas.Common.Lsp.IdeProject,
  Atlas.Common.Index.Adapters.CacheDirectory,
  Atlas.Common.Lsp.WorkspaceFolders,
  Atlas.Common.Lsp.Configuration,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Diagnostics.Anonymizer,
  Atlas.Common.Compiler.Contract,
  Atlas.Common.Compiler.Backend,
  Shell.CommandLine,
  Shell.Composition.Compile,
  Atlas.Common.Diagnostics.Contract,
  Shell.Platform,
  Shell.Workspace,
  Shell.CrashCases;

type
  TServerComposition = class
  private
    /// <summary>Logger, Transport, Mitschnitt (--trace), letzte Logzeilen (#108) und Anonymisierer (#647, #1356).
    /// Create setzt Logger und Transport; Mitschnitt, Logzeilen und Anonymisierer nur CreateForStdio, sonst nil.
    /// Der Mitschnitt liegt nicht besitzend in Transport.</summary>
    FChannel: TShellStdioChannel;
    /// <summary>Teilwurzel Protokoll: Verteiler, Statistik, letzte Nachrichten, Lebenszyklus, Absturzfälle.</summary>
    FProtocol: TShellProtocol;
    /// <summary>Teilwurzel Sitzung: Diagnoselog, Wächter des Editor-Prozesses, Client, Endgrund, Zeitlimit.</summary>
    FSession: TShellSession;
    /// <summary>--replay (#1355): Einstellungen aus dem Fall, keine eigenen Fälle.</summary>
    FReplay: Boolean;
    FDocuments: IDocumentStore;
    FTextDocumentSync: TLspTextDocumentSync;
    /// <summary>Teilwurzel Diagnosen: Syntaxprüfung, Pull-Diagnosen und Projektprüfung.</summary>
    FDiagnosticsArea: TShellDiagnosticsArea;
    /// <summary>Teilwurzel Code: Navigation, Refactorings, Vervollständigung, Code-Aktionen und Testunits.</summary>
    FCodeArea: TShellCodeArea;
    /// <summary>Teilwurzel Befehle: workspace/executeCommand mit allen Befehlen.</summary>
    FCommandArea: TShellCommandArea;
    /// <summary>Teilwurzel Analyse: Analysen, Übersichten, Baselines und betroffene Tests.</summary>
    FAnalysisArea: TShellAnalysisArea;
    /// <summary>Teilwurzel IDE: Nachrichten aus der IDE, Dateiänderungen und Projektwahl.</summary>
    FIdeArea: TShellIdeArea;
    /// <summary>Teilwurzel Bearbeiten: Gliederung, Formatieren, Erzeugen-Menü und Host der Schnellbefehle.</summary>
    FEditingArea: TShellEditingArea;
    /// <summary>Teilwurzel Index: Symbolindex, Uses-Graph, Ordner des Arbeitsbereichs und Ereignisse des Aufbaus.</summary>
    FIndexArea: TShellIndexArea;
    FConnection: TJsonRpcConnection;
    /// <summary>Arbeitsbereiche, Einstellungen, Ordner und was je Datei aus ihnen folgt.</summary>
    FCore: TShellCore;
    FCompilerProcess: ICompilerProcess;
    /// <summary>Compilerläufe (#40, #261): höchstens ein Lauf zugleich, ein weiterer wird vorgemerkt.</summary>
    FCompile: TShellCompileHost;
    /// <summary>Der Client hat keinen brauchbaren Ordner gemeldet (RAD Studio, #175):
    /// Ordner werden aus den geöffneten Dateien abgeleitet.</summary>
    FDeriveWorkspaces: Boolean;
    /// <summary>Teil von Create (S-02): Teilwurzel Protokoll mit Verteiler, Watchdog und Lebenszyklus.</summary>
    procedure WireProtocol;
    /// <summary>Schickt eine Benachrichtigung an den Client.</summary>
    procedure NotifyClient(const AMethod: string; AParams: TJSONObject);
    /// <summary>Teil von Create (S-02): Dokumentspeicher, Synchronisation, Syntax- und Pull-Diagnosen, Compilerergebnisse.</summary>
    procedure WireDocuments;
    /// <summary>Zeitlimit einer Anfrage aus den Einstellungen; vor der Sitzung die Vorgabe.</summary>
    function CurrentRequestTimeout: Cardinal;
    /// <summary>Teil von WireDocuments (#1355): Absturzfälle und Sicherheitsnetz mit Dokumenten, Einstellungen
    /// und Benachrichtigung an den Client.</summary>
    procedure WireCrashCases;
    /// <summary>Compilerläufe (#40, #261) mit Weg über dcc oder die eigene IDE (cc.ps1).</summary>
    procedure WireCompile;
    /// <summary>Teil von Create (S-02): Dokumentbezogene Funktionen ohne Index: Symbole, Faltung, Formatierung, Schnellbefehle.</summary>
    procedure WireEditing;
    /// <summary>Teil von Create (S-02): Arbeitsbereiche, Indexplanung und Konfiguration ohne Ordner; Pfade für die Syntaxprüfung.</summary>
    procedure WireWorkspaces;
    /// <summary>Teil von WireWorkspaces: Ereignisse des Dokumentspeichers (Shell.Composition.DocumentEvents).</summary>
    procedure WireDocumentEvents;
    /// <summary>Was der Kern von der Komposition braucht.</summary>
    function CoreServices: TShellCoreServices;
    /// <summary>Teil von CoreServices: Meldungen des Kerns an die Komposition.</summary>
    procedure CoreEvents(var AServices: TShellCoreServices);
    /// <summary>Teil von Create (S-02): Symbolindex und Diagnoselog.</summary>
    procedure WireIndex;
    /// <summary>Teil von WireIndex: Was die Teilwurzel Index von den anderen Teilen braucht.</summary>
    function IndexAreaServices: TShellIndexAreaServices;
    /// <summary>Teil von WireIndex: Teilwurzel Sitzung mit dem Diagnoselog am Verteiler.</summary>
    procedure WireSession;
    /// <summary>Teil von Create: Teilwurzel Code nach Kern und Index.</summary>
    procedure WireCode;
    /// <summary>Teil von Create (S-02): Signaturhilfe, Hierarchien, Implementierungen, Inlay-Hints, CodeLens, Metriken, TODOs, Baseline, Semantic Tokens.</summary>
    procedure WireAnalysis;
    /// <summary>Teil von Create (S-02): workspace/executeCommand: alle Befehle des Servers.</summary>
    procedure WireCommands;
    /// <summary>Teil von WireCommands: Status-Dienste, die nur die Komposition kennt.</summary>
    procedure CommandStatus(var AServices: TShellStatusServices);
    /// <summary>Teil von WireCommands: Server-Befehle, die nur die Komposition kennt.</summary>
    procedure CommandServer(var AServices: TShellServerCommandServices);
    /// <summary>Teil von Create (S-02): Anbindung an die IDE: Build-Meldungen und Projektkontext.</summary>
    procedure WireIde;
    /// <summary>Nach initialized: Client, Einstellungen, Beobachtung und erste Arbeitsbereiche.</summary>
    procedure ClientInitialized;
    /// <summary>Name, Fähigkeiten und Editor-Einstellungen des Clients aus initialize.</summary>
    procedure ApplyClientInfo(const AParams: TJSONObject);
    /// <summary>Text einer Quelldatei; geöffnete Dokumente haben Vorrang vor der Platte.</summary>
    function ReadSourceText(const AFileName: string; out AText: string): Boolean;
    /// <summary>Muster, Ordner und Testprogramm für Testunits zur Datei (#274, #189).</summary>
    function TestUnitContextFor(const AUri: string; out AContext: TTestUnitContext): Boolean;
    /// <summary>Index und usesKeep für /sortuses (#297) und die uses-Diagnosen (#621); False, solange die
    /// Code-Aktionen fehlen.</summary>
    function UsesContextFor(const AUri: string; out AContext: TUsesContext): Boolean;
    /// <summary>Beenden: gibt Features, Ordner und Index frei.</summary>
    procedure FreeFeatures;
  public const
    /// <summary>Anfragen, die länger laufen, werden abgebrochen und gemeldet.</summary>
    RequestTimeoutMs = 10000;
  public
    constructor Create(const ATransport: IJsonRpcTransport; const ALogger: ILogger);
    destructor Destroy; override;
    /// <summary>Komposition mit stdin/stdout des Prozesses und Logging nach AOptions.</summary>
    class function CreateForStdio(const AOptions: TCommandLineOptions): TServerComposition; static;
    /// <summary>Verarbeitet Nachrichten bis exit oder Ende der Eingabe und liefert den Exit-Code.</summary>
    function Run: Integer;
    /// <summary>Nachstellen eines Absturzfalls (--replay, #1355), vor Run: settings.json aus ASettingsFile ('' =
    /// keine) statt der des Benutzers; der Server sichert dabei keine Fälle und überspringt nichts.</summary>
    procedure PrepareReplay(const ASettingsFile: string);
    /// <summary>Absturzfälle und Sicherheitsnetz (#1355).</summary>
    function CrashCases: TShellCrashCases;
    /// <summary>Geöffnete Dokumente, für Features, die Dateien auswerten.</summary>
    property Documents: IDocumentStore read FDocuments;
    /// <summary>Gemeinsamer Symbolindex; nil vor WireIndex und nach dem Freigeben.</summary>
    function Index: ISymbolIndex;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Diagnostics.CheckProfile,
  Atlas.Common.Lsp.StatusFile,
  Atlas.Common.Lsp.Completion.Details,
  Atlas.Common.Lsp.Contract,
  Atlas.Common.JsonRpc.Messages;

{ TServerComposition }

constructor TServerComposition.Create(const ATransport: IJsonRpcTransport; const ALogger: ILogger);
begin
  inherited Create;
  FChannel.Transport := ATransport;
  FChannel.Logger := ALogger;
  WireProtocol;
  WireDocuments;
  WireEditing;
  WireWorkspaces;
  WireIndex;
  WireCode;
  WireAnalysis;
  WireCommands;
  WireIde;
  FProtocol.Lifecycle.OnInitialized := ClientInitialized;
  FConnection := TJsonRpcConnection.Create(FChannel.Transport, FProtocol.Dispatcher);
  FConnection.OnError :=
    procedure(const AError: Exception)
    begin
      FChannel.Logger.Error('Fehler bei der Verarbeitung: ' + FSession.DescribeFailure(AError));
    end;
  FProtocol.Lifecycle.OnExit :=
    procedure
    begin
      FSession.EndReason := TDiagnosticEndReason.Clean;
      FConnection.Stop;
    end;
end;

procedure TServerComposition.WireProtocol;
var
  mServices: TShellProtocolServices;
begin
  mServices.Logger := FChannel.Logger;
  mServices.TimeoutMs := RequestTimeoutMs;
  mServices.Capabilities :=
    function: TJSONObject
    begin
      Result := TShellCapabilities.Build;
      // Pull-Diagnosen nur für Clients, die sie können; sonst bleibt es bei publishDiagnostics (#82).
      FDiagnosticsArea.ApplyClientCapabilities(FProtocol.Lifecycle.InitializeParams, Result);
    end;
  FProtocol := TShellProtocol.Create(mServices);
end;

procedure TServerComposition.NotifyClient(const AMethod: string; AParams: TJSONObject);
var
  mNotification: TJSONObject;
begin
  mNotification := TJsonRpcMessages.Notification(AMethod, AParams);
  try
    FChannel.Transport.WriteMessage(mNotification);
  finally
    mNotification.Free;
  end;
end;

function TServerComposition.CurrentRequestTimeout: Cardinal;
begin
  Result := RequestTimeoutMs;
  if FSession <> nil then
  begin
    Result := FSession.RequestTimeout;
  end;
end;

procedure TServerComposition.WireCrashCases;
begin
  FProtocol.CreateCrashCases(FDocuments,
    function(const AUri: string): TArray<string>
    var
      mWorkspace: TShellWorkspace;
    begin
      Result := nil;
      if (FCore <> nil) and (FCore.Configuration.GlobalSettingsFile <> '') then
      begin
        Result := Result + [FCore.Configuration.GlobalSettingsFile];
      end;
      if not StartsText('file:', AUri) or (FCore = nil) then
      begin
        Exit;
      end;
      System.TMonitor.Enter(FCore.Workspaces.Lock);
      try
        mWorkspace := FCore.Workspaces.WorkspaceOf(TDocumentUris.ToPath(AUri));
        if mWorkspace <> nil then
        begin
          Result := Result + [ExistingOrLegacyFile(mWorkspace.Root, ConfigurationFileName,
            LegacyConfigurationFileName)];
        end;
      finally
        System.TMonitor.Exit(FCore.Workspaces.Lock);
      end;
    end,
    NotifyClient);
end;

procedure TServerComposition.PrepareReplay(const ASettingsFile: string);
begin
  FReplay := True;
  FCore.Configuration.UseReplaySettings(ASettingsFile);
  FProtocol.CrashCases.Enabled := False;
  FProtocol.CrashCases.SkipEnabled := False;
end;

procedure TServerComposition.WireCompile;
var
  mServices: TShellCompileSetupServices;
begin
  FCompilerProcess := TProcessRunner.Create;
  mServices := Default(TShellCompileSetupServices);
  mServices.Logger := FChannel.Logger;
  mServices.Transport := FChannel.Transport;
  mServices.Process := FCompilerProcess;
  mServices.Workspaces :=
    function: TShellWorkspaceRegistry
    begin
      Result := FCore.Workspaces;
    end;
  mServices.Publish :=
    procedure(const AFiles: TArray<string>)
    begin
      FDiagnosticsArea.Syntax.RefreshFiles(AFiles);
    end;
  FCompile := TShellCompileSetup.NewHost(mServices);
end;

/// <summary>Kanonischer Pfad für den Dokumentspeicher.</summary>
function CanonicalPath(const APath: string): string;
begin
  Result := TShellPlatform.CanonicalizePath(APath);
end;

procedure TServerComposition.WireDocuments;
var
  mServices: TShellDiagnosticsAreaServices;
begin
  FDocuments := TDocumentStore.Create(CanonicalPath);
  FTextDocumentSync := TLspTextDocumentSync.Create(FDocuments);
  FTextDocumentSync.Attach(FProtocol.Dispatcher);
  WireCrashCases;
  WireCompile;
  mServices := Default(TShellDiagnosticsAreaServices);
  mServices.Logger := FChannel.Logger;
  mServices.Transport := FChannel.Transport;
  mServices.Dispatcher := FProtocol.Dispatcher;
  mServices.Documents := FDocuments;
  // Closures: Kern und Index entstehen erst nach den Diagnosen (WireWorkspaces, WireIndex).
  mServices.Core :=
    function: TShellCore
    begin
      Result := FCore;
    end;
  mServices.Index :=
    function: ISymbolIndex
    begin
      Result := Index;
    end;
  mServices.CompilerMessages :=
    function(const AFileName: string): TArray<TCompilerMessage>
    begin
      Result := FCompile.Results.MessagesFor(AFileName);
    end;
  mServices.UsesContext := UsesContextFor;
  // Das Diagnoselog entsteht erst mit der Sitzung; bis dahin heißt jede Datei 'unit' (#1094).
  mServices.FileLabel :=
    function(const AFileName: string): string
    begin
      Result := 'unit';
      if FSession <> nil then
      begin
        Result := FSession.FileLabel(AFileName);
      end;
    end;
  mServices.RequestTimeout := CurrentRequestTimeout;
  FDiagnosticsArea := TShellDiagnosticsArea.Create(mServices);
end;

function TServerComposition.Index: ISymbolIndex;
begin
  Result := nil;
  if FIndexArea <> nil then
  begin
    Result := FIndexArea.Index;
  end;
end;

function TServerComposition.CrashCases: TShellCrashCases;
begin
  Result := FProtocol.CrashCases;
end;

procedure TServerComposition.WireEditing;
var
  mServices: TShellEditingAreaServices;
begin
  mServices := Default(TShellEditingAreaServices);
  // Closure: Der Kern entsteht erst nach dem Bearbeiten (WireWorkspaces).
  mServices.Core :=
    function: TShellCore
    begin
      Result := FCore;
    end;
  mServices.Editing.Documents := FDocuments;
  mServices.Editing.ReadText := ReadSourceText;
  mServices.Slash.Transport := FChannel.Transport;
  mServices.Slash.Logger := FChannel.Logger;
  mServices.Slash.Dispatcher := FProtocol.Dispatcher;
  mServices.Slash.ReadText := ReadSourceText;
  // Die .dproj geht über das Plugin in die IDE, wenn der Client applyEdit kann (#397).
  mServices.Slash.ClientAppliesEdits :=
    function: Boolean
    begin
      Result := TLspApplyEdit.ClientSupports(FProtocol.Lifecycle.InitializeParams);
    end;
  // Neu laden nur im Thread der Nachrichtenschleife (Code-Review A-03); FConnection liest die Closure
  // erst beim Aufruf.
  mServices.Slash.RunInLoop :=
    procedure(const AWork: TProc)
    begin
      if (FConnection = nil) or not FConnection.Queue(AWork) then
      begin
        FChannel.Logger.Warning('Schnellbefehl: Projekt nicht neu geladen, die Verbindung ist beendet');
      end;
    end;
  mServices.Slash.TestUnitContextFor := TestUnitContextFor;
  mServices.Slash.UsesContextFor := UsesContextFor;
  FEditingArea := TShellEditingArea.Create(mServices);
end;

procedure TServerComposition.WireWorkspaces;
begin
  FCore := TShellCore.Create(CoreServices);
  WireDocumentEvents;
  FCore.Attach(FProtocol.Dispatcher);
end;

procedure TServerComposition.WireDocumentEvents;
var
  mServices: TShellDocumentEventServices;
begin
  mServices := Default(TShellDocumentEventServices);
  mServices.Core :=
    function: TShellCore
    begin
      Result := FCore;
    end;
  mServices.CrashCases :=
    function: TShellCrashCases
    begin
      Result := FProtocol.CrashCases;
    end;
  mServices.Compile :=
    function: TShellCompileHost
    begin
      Result := FCompile;
    end;
  // Die Dateiänderungen entstehen erst in WireIde.
  mServices.FileChanges :=
    function: TShellFileChanges
    begin
      Result := nil;
      if FIdeArea <> nil then
      begin
        Result := FIdeArea.FileChanges;
      end;
    end;
  mServices.DeriveWorkspaces :=
    function: Boolean
    begin
      Result := FDeriveWorkspaces;
    end;
  TShellDocumentEvents.Attach(FDocuments, mServices);
end;

function TServerComposition.CoreServices: TShellCoreServices;
begin
  Result := Default(TShellCoreServices);
  Result.Logger := FChannel.Logger;
  Result.Transport := FChannel.Transport;
  Result.Documents := FDocuments;
  Result.Index :=
    function: ISymbolIndex
    begin
      Result := Index;
    end;
  Result.UsesGraph :=
    function: TUsesGraphService
    begin
      // Der Kern fragt erst nach WireIndex und ist beim Beenden vor dem Index fort.
      Result := FIndexArea.UsesGraph;
    end;
  Result.Queries :=
    function: ICodeQueries
    begin
      Result := FAnalysisArea.Overviews.Queries;
    end;
  Result.SelectedProject :=
    function(const AOrigin: string): string
    begin
      Result := FIdeArea.Selection.Project(AOrigin);
    end;
  Result.ActiveProject :=
    function: string
    begin
      Result := FIdeArea.Ide.Project.ActiveProject;
    end;
  Result.IdeProject :=
    function: TLspIdeProject
    begin
      Result := FIdeArea.Ide.Project;
    end;
  Result.Selection :=
    function: TProjectSelection
    begin
      Result := FIdeArea.Selection;
    end;
  Result.Anonymizer :=
    function: ILogAnonymizer
    begin
      Result := FChannel.Anonymizer;
    end;
  Result.ClientName :=
    function: string
    begin
      Result := '';
      if FSession <> nil then
      begin
        Result := FSession.ClientName;
      end;
    end;
  CoreEvents(Result);
end;

procedure TServerComposition.CoreEvents(var AServices: TShellCoreServices);
begin
  AServices.ProjectLoaded :=
    procedure
    begin
      FIndexArea.ProjectLoaded;
    end;
  AServices.IndexStageDone :=
    procedure(AProjectStage: Boolean)
    begin
      FIndexArea.IndexStageDone(AProjectStage);
    end;
  AServices.IndexEvent :=
    procedure(AText: string)
    begin
      // Absicherung: Beim Beenden ist das Diagnoselog schon fort (Code-Review A-05).
      if FSession <> nil then
      begin
        FSession.Diagnostics.Log.LogEvent(AText);
      end;
    end;
  AServices.SettingsChanged :=
    procedure(ASettings: TServerSettings)
    begin
      FProtocol.Dispatcher.Watchdog.SetTimeout(ASettings.RequestTimeoutMs);
      FSession.ApplySettings(ASettings);
      // server.crashCases und server.crashSkip (#1355) gelten serverweit; beim Nachstellen bleiben beide aus.
      if not FReplay then
      begin
        FProtocol.CrashCases.Enabled := ASettings.ServerCrashCases;
        FProtocol.CrashCases.SkipEnabled := ASettings.ServerCrashSkip;
      end;
    end;
  // Im Thread der Nachrichtenschleife verarbeiten wie eine Meldung des Clients.
  AServices.FilesChanged :=
    procedure(const AFiles: TArray<string>)
    begin
      FConnection.Post(TLspWatchedFiles.Notification(AFiles));
    end;
end;

procedure TServerComposition.WireIndex;
begin
  FIndexArea := TShellIndexArea.Create(IndexAreaServices);
  FEditingArea.Editing.UseIndex(FIndexArea.Index);
  WireSession;
end;

function TServerComposition.IndexAreaServices: TShellIndexAreaServices;
begin
  Result := Default(TShellIndexAreaServices);
  Result.Dispatcher := FProtocol.Dispatcher;
  Result.Core :=
    function: TShellCore
    begin
      Result := FCore;
    end;
  Result.Diagnostics :=
    function: TShellDiagnosticsArea
    begin
      Result := FDiagnosticsArea;
    end;
  // Closure: CreateForStdio setzt den Anonymisierer erst nach Create.
  Result.Anonymizer :=
    function: ILogAnonymizer
    begin
      Result := FChannel.Anonymizer;
    end;
  Result.ProjectStarted :=
    procedure
    begin
      if FCompile <> nil then
      begin
        FCompile.Reset;
      end;
    end;
  Result.NamespacesChanged :=
    procedure(const ANamespaces: TArray<string>)
    begin
      FCodeArea.Navigation.SetNamespaces(ANamespaces);
      FCodeArea.Completion.Completion.Hooks.Namespaces := ANamespaces;
      FAnalysisArea.Analysis.SetNamespaces(ANamespaces);
    end;
  Result.LibraryRootsChanged :=
    procedure(const ARoots: TArray<string>)
    begin
      FSession.Diagnostics.SetLibraryRoots(ARoots);
    end;
  Result.Queue :=
    function(const AWork: TProc): Boolean
    begin
      Result := (FConnection <> nil) and FConnection.Queue(AWork);
    end;
end;

procedure TServerComposition.WireSession;
var
  mServices: TShellSessionServices;
begin
  mServices.Logger := FChannel.Logger;
  mServices.Documents := FDocuments;
  mServices.Index := Index;
  mServices.Dispatcher := FProtocol.Dispatcher;
  mServices.IndexLoading :=
    function: Integer
    begin
      Result := FCore.Workspaces.IndexLoading;
    end;
  mServices.Stop :=
    procedure
    begin
      FConnection.Stop;
    end;
  FSession := TShellSession.Create(mServices, RequestTimeoutMs);
end;

procedure TServerComposition.WireCode;
var
  mServices: TShellCodeAreaServices;
begin
  mServices := Default(TShellCodeAreaServices);
  mServices.Logger := FChannel.Logger;
  mServices.Dispatcher := FProtocol.Dispatcher;
  mServices.Documents := FDocuments;
  mServices.Index := Index;
  mServices.Editing := FEditingArea.Editing;
  mServices.RuleIdsFor :=
    function(const AUri, AText: string; ALine: Integer; out AIds: TArray<string>): Boolean
    begin
      Result := FEditingArea.Slash.RuleIdsAt(AUri, AText, ALine, AIds);
    end;
  mServices.MessagesFor :=
    function(const AFileName: string): TArray<TCompilerMessage>
    begin
      Result := FCompile.Results.MessagesFor(AFileName);
    end;
  // Closure: Die Teilwurzel IDE entsteht erst in WireIde.
  mServices.IdeProjectFor :=
    function(const AProjectFile: string; out AContext: TIdeProjectContext): Boolean
    begin
      Result := FIdeArea.Ide.Project.Find(AProjectFile, AContext);
    end;
  mServices.VisitWorkspaces :=
    procedure(const AVisit: TShellWorkspacesProc)
    begin
      FCore.Workspaces.Visit(AVisit);
    end;
  mServices.Notify := NotifyClient;
  mServices.Log :=
    procedure(const AText: string)
    begin
      FChannel.Logger.Debug(AText);
    end;
  FCodeArea := TShellCodeArea.Create(FCore, mServices);
end;

procedure TServerComposition.WireAnalysis;
var
  mServices: TShellAnalysisAreaServices;
begin
  mServices := Default(TShellAnalysisAreaServices);
  mServices.Logger := FChannel.Logger;
  mServices.Dispatcher := FProtocol.Dispatcher;
  mServices.Documents := FDocuments;
  mServices.Index := Index;
  // Closure: Die Teilwurzel IDE entsteht erst in WireIde.
  mServices.FormatRoutinesFor :=
    function(const AUri: string): TArray<TFormatRoutine>
    begin
      Result := FIdeArea.FormatRoutinesFor(AUri);
    end;
  mServices.UsesContextFor := UsesContextFor;
  mServices.RefreshLater :=
    procedure
    begin
      FDiagnosticsArea.Syntax.RefreshLater;
    end;
  mServices.TestUnitContext := TestUnitContextFor;
  mServices.RequestTimeout := CurrentRequestTimeout;
  FAnalysisArea := TShellAnalysisArea.Create(FCore, mServices);
end;

procedure TServerComposition.WireCommands;
var
  mServices: TShellCommandAreaServices;
begin
  mServices := Default(TShellCommandAreaServices);
  mServices.Logger := FChannel.Logger;
  mServices.Dispatcher := FProtocol.Dispatcher;
  CommandStatus(mServices.Status);
  CommandServer(mServices.Server);
  mServices.Editor.Documents := FDocuments;
  mServices.Editor.Index := Index;
  mServices.Editor.ResourceStringWrite := FEditingArea.Slash.ResourceStringWrite;
  mServices.UnitSearch.Index := Index;
  mServices.UnitSearch.UsesContextFor := UsesContextFor;
  mServices.UnitSearch.Process :=
    function: ICompilerProcess
    begin
      Result := FCompilerProcess;
    end;
  FCommandArea := TShellCommandArea.Create(FCore, FCodeArea, FAnalysisArea, FEditingArea.Editing, mServices);
end;

procedure TServerComposition.CommandStatus(var AServices: TShellStatusServices);
begin
  AServices.Index := Index;
  AServices.Documents := FDocuments;
  AServices.Statistics := FProtocol.Statistics;
  AServices.ActiveProject :=
    function: string
    begin
      Result := FIdeArea.Ide.Project.ActiveProject;
    end;
  // Protokoll, Mitschnitt und Anonymisierung setzt CreateForStdio erst nach Create.
  AServices.RecentLog :=
    function: IRecentLogLines
    begin
      Result := FChannel.RecentLog;
    end;
  AServices.Tracing :=
    function: TJsonRpcTracingTransport
    begin
      Result := FChannel.Tracing;
    end;
  AServices.Anonymizer :=
    function: ILogAnonymizer
    begin
      Result := FChannel.Anonymizer;
    end;
  AServices.CompilerStatus :=
    procedure(var AStatus: TServerStatus)
    begin
      FCompile.StatusOf(AStatus);
    end;
  AServices.CheckStatus :=
    procedure(var AStatus: TServerStatus; out AQueue: TWorkspaceCheckQueue)
    begin
      AQueue := Default(TWorkspaceCheckQueue);
      if (FDiagnosticsArea <> nil) and (FDiagnosticsArea.Pull <> nil) then
      begin
        AStatus.CheckRun := FDiagnosticsArea.Pull.Check.Profile(TCheckRunProfile.cTop);
        AQueue := FDiagnosticsArea.Pull.Check.Queue;
      end;
    end;
end;

procedure TServerComposition.CommandServer(var AServices: TShellServerCommandServices);
begin
  AServices.Compile :=
    function(const AFileName: string; out AChoice: TCompilerBackendChoice): Boolean
    begin
      Result := FCompile.Start(AFileName, True, AChoice);
    end;
  AServices.ActiveProject :=
    function: string
    begin
      Result := FIdeArea.Ide.Project.ActiveProject;
    end;
  AServices.SetProject :=
    procedure(const AScope, AProject: string)
    begin
      FIdeArea.Selection.SetProject(AScope, AProject);
    end;
  AServices.RetryCrashCase :=
    function(const AUri: string): Integer
    begin
      Result := FProtocol.CrashCases.Retry(AUri);
    end;
  AServices.Recheck :=
    procedure
    begin
      FDiagnosticsArea.Pull.Changed;
    end;
end;
procedure TServerComposition.WireIde;
var
  mServices: TShellIdeAreaServices;
begin
  mServices.Logger := FChannel.Logger;
  mServices.Transport := FChannel.Transport;
  mServices.Dispatcher := FProtocol.Dispatcher;
  // Beim Beenden sind Diagnosen und Compile-Host vor der Teilwurzel IDE fort.
  mServices.Diagnostics :=
    function: TShellDiagnosticsArea
    begin
      Result := FDiagnosticsArea;
    end;
  mServices.Compile :=
    function: TShellCompileHost
    begin
      Result := FCompile;
    end;
  FIdeArea := TShellIdeArea.Create(FCore, mServices);
end;

procedure TServerComposition.ClientInitialized;
var
  mFolders: TArray<TWorkspaceFolder>;
  mFolder: TWorkspaceFolder;
begin
  FSession.WatchParent(FProtocol.Lifecycle.InitializeParams);
  ApplyClientInfo(FProtocol.Lifecycle.InitializeParams);
  mFolders := TLspWorkspaceFolders.FromInitialize(FProtocol.Lifecycle.InitializeParams);
  // Vor dem ersten Laden, damit die Projekte nicht zweimal indiziert werden (#396).
  FIdeArea.Ide.Project.LoadInitialize(FProtocol.Lifecycle.InitializeParams);
  // Meldet der Client nur Projektdateien (IDE-Plugin, #648), bekommen Dateien außerhalb dieser
  // Projekte weiter einen abgeleiteten Arbeitsbereich.
  FDeriveWorkspaces := True;
  for mFolder in mFolders do
  begin
    if mFolder.ProjectFile = '' then
    begin
      FDeriveWorkspaces := False;
    end;
  end;
  if Length(mFolders) = 0 then
  begin
    FChannel.Logger.Info('Kein Arbeitsbereichsordner gemeldet; Ordner werden aus den geöffneten Dateien abgeleitet');
  end;
  FCore.Configuration.Start;
  for mFolder in mFolders do
  begin
    FCore.Folders.Add(mFolder);
  end;
  FCore.Configuration.UpdateWatchedFiles;
  FIdeArea.FileChanges.RegisterWatchers(FProtocol.Lifecycle.InitializeParams);
end;

procedure TServerComposition.ApplyClientInfo(const AParams: TJSONObject);
begin
  if AParams <> nil then
  begin
    // Name des Clients für die Anmeldung am Index-Cache (#62); vor dem Anlegen der Arbeitsbereiche.
    FSession.ClientName := AParams.GetValue<string>('clientInfo.name', '');
    // Absturzfälle nennen den Client (#1355).
    FProtocol.CrashCases.Client := Trim(FSession.ClientName + ' ' + AParams.GetValue<string>('clientInfo.version', ''));
  end;
  // Sprache des Clients (#1458) vor SetEditorSettings, das die Sprache der Texte wählt.
  FCore.Settings.SetClientLocale(TLspClientLocale.FromInitialize(AParams));
  // Der neue Client erfährt, was nach Abstürzen übersprungen wird.
  FProtocol.CrashCases.Announce;
  // Editor-Ebene: initializationOptions.settings.atlas wie bei didChangeConfiguration, schon vor dem
  // ersten Indexaufbau; sie zählt wie global (TConfigurationScopes). Das IDE-Plugin schickt keine
  // Einstellungen mehr: Es schreibt settings.json, die der Server selbst liest und beobachtet.
  if AParams <> nil then
  begin
    FCore.Settings.SetEditorSettings(TLspConfiguration.EditorSettingsFromParams(AParams.GetValue('initializationOptions')));
  end
  else
  begin
    // Ohne Parameter bleibt die Editor-Ebene leer; die Einstellungen ohne Arbeitsbereich gelten trotzdem neu.
    FCore.Settings.SetEditorSettings(FCore.Settings.EditorSettings);
  end;
  FCodeArea.Navigation.Hover.Markdown := TLspHover.ClientSupportsMarkdown(AParams);
  // Code-Vorlagen mit Platzhaltern nur an Clients mit snippetSupport (#51).
  FCodeArea.Completion.Completion.Hooks.SnippetSupport := TLspCompletion.ClientSupportsSnippets(AParams);
  FCodeArea.Completion.Completion.Hooks.DocumentationMarkdown := TCompletionDetails.ClientPrefersMarkdown(AParams);
end;

destructor TServerComposition.Destroy;
var
  Unfinished: Boolean;
begin
  TPascalPreprocessor.SetDeclaredProvider(nil);
  // Zuerst: Eine laufende Übernahme greift auf die Ordner zu.
  if FIdeArea <> nil then
  begin
    FIdeArea.FileChanges.StopRefresh;
  end;
  // Vor der Verbindung: Beide Wächter rufen FConnection.
  if FCore <> nil then
  begin
    FCore.Configuration.StopWatching;
  end;
  if FSession <> nil then
  begin
    FSession.StopWatchingParent;
  end;
  // Code-Review A-06: Liefen beim Ende noch Handler, die ihr Abbruchsignal nicht prüfen, nutzen sie
  // Features und Ordner weiter.
  Unfinished := (FConnection <> nil) and FConnection.UnfinishedWork;
  FreeAndNil(FConnection);
  if FProtocol <> nil then
  begin
    FProtocol.Dispatcher.Watchdog := nil;
  end;
  // Compiler und Index-Threads anhalten, solange Diagnoselog und Syntaxprüfung noch leben (Code-Review A-05):
  // Ein abgebrochener Aufbau meldet sich über OnIndexEvent im Diagnoselog, ein Compilerlauf über die
  // Syntaxprüfung.
  if FCompile <> nil then
  begin
    FCompile.Stop;
  end;
  if FCore <> nil then
  begin
    FCore.StopIndexThreads;
  end;
  // Der Baum-Cache ist global; ohne Projekte gelten wieder die Vordefinitionen (#845).
  TSyntaxTreeCache.SetDefinesProvider(nil);
  TSyntaxTreeCache.SetIncludeProvider(nil);
  // Erst jetzt meldet sich niemand mehr beim Diagnoselog.
  if FProtocol <> nil then
  begin
    FProtocol.Dispatcher.Observer := nil;
  end;
  FreeAndNil(FSession);
  if Unfinished then
  begin
    // Der Prozess endet gleich: Speicher stehen lassen, statt ihn unter einem laufenden Handler freizugeben.
    FChannel.Logger.Warning('Beim Beenden liefen noch Anfragen; ihre Objekte werden nicht freigegeben');
  end
  else
  begin
    FreeFeatures;
  end;
  if FChannel.Tracing <> nil then
  begin
    FChannel.Tracing.OnFailed := nil;
  end;
  // Statusdatei für get_server_status (#1356) gehört nur dem laufenden Server.
  TServerStatusFile.Delete(TIndexCacheDirectory.DefaultRoot, TShellPlatform.CurrentProcessId);
  FChannel := Default(TShellStdioChannel);
  inherited;
end;

procedure TServerComposition.FreeFeatures;
begin
  // Vor den Ordnern: der Hintergrund-Thread der Syntaxprüfung fragt ihre Symbole ab.
  FDiagnosticsArea.FreeChecks;
  // Ordner vor dem Index: ihre Index-Threads laufen noch.
  FCore.FreeWorkspaces;
  // Nach den Ordnern: Ihre Index-Threads melden Projektstufe und Ende.
  FreeAndNil(FDiagnosticsArea);
  FreeAndNil(FCore);
  FreeAndNil(FIndexArea);
  // Danach die Features in umgekehrter Reihenfolge ihrer Gruppen; Protokoll und Absturzfälle zuletzt.
  FreeAndNil(FAnalysisArea);
  FreeAndNil(FCodeArea);
  FreeAndNil(FCommandArea);
  // Nach allen Nutzern des Hosts der Schnellbefehle: Er ruft dessen Methoden.
  FreeAndNil(FEditingArea);
  FreeAndNil(FCompile);
  FCompilerProcess := nil;
  FreeAndNil(FIdeArea);
  FreeAndNil(FTextDocumentSync);
  FDocuments := nil;
  // Nach der Verbindung und dem Watchdog: Niemand meldet mehr einen Absturz.
  FreeAndNil(FProtocol);
end;

function TServerComposition.ReadSourceText(const AFileName: string; out AText: string): Boolean;
begin
  Result := FCore.ReadText(AFileName, AText);
end;

function TServerComposition.TestUnitContextFor(const AUri: string; out AContext: TTestUnitContext): Boolean;
begin
  AContext := Default(TTestUnitContext);
  Result := (FCodeArea <> nil) and FCodeArea.TestUnits.ContextFor(AUri, AContext);
end;

function TServerComposition.UsesContextFor(const AUri: string; out AContext: TUsesContext): Boolean;
begin
  AContext := Default(TUsesContext);
  Result := (FCodeArea <> nil) and FCodeArea.UsesContextFor(AUri, AContext);
end;

class function TServerComposition.CreateForStdio(const AOptions: TCommandLineOptions): TServerComposition;
var
  mChannel: TShellStdioChannel;
  mLogger: ILogger;
begin
  mChannel := TShellStdio.Open(AOptions);
  mLogger := mChannel.Logger;
  Result := TServerComposition.Create(mChannel.Transport, mLogger);
  Result.FChannel.Tracing := mChannel.Tracing;
  Result.FChannel.RecentLog := mChannel.RecentLog;
  Result.FChannel.Anonymizer := mChannel.Anonymizer;
  Result.FCompile.Restricted := AOptions.Restricted;
  Result.FSession.ClientProcessId := AOptions.ClientProcessId;
  if AOptions.Restricted then
  begin
    mLogger.Info('Eingeschränkter Modus (Arbeitsbereich nicht vertrauenswürdig): der Compiler wird nicht gestartet');
  end;
end;

function TServerComposition.Run: Integer;
begin
  Result := FSession.Run(FConnection, FProtocol.Lifecycle);
end;

end.
