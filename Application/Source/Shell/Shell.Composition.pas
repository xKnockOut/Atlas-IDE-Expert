unit Shell.Composition;

// Host-Rolle Shell: Komposition des Servers von Hand (DI-Strategie ohne Container).
// Verbindet stdin/stdout, Transport, Dispatcher, Lebenszyklus, Dokumentverwaltung,
// Syntaxdiagnosen, Nachrichtenschleife, Logging, Zeitlimit für Anfragen und
// Absturzprotokoll mit Stacktrace. Jeder Ordner des Arbeitsbereichs hat
// eigene Konfiguration, eigenes Projekt und eigenen Indexaufbau
// (TShellWorkspace); der Symbolindex ist gemeinsam.

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.Generics.Collections,
  Argus.Common.Logging.Contract,
  Argus.Common.JsonRpc.Contract,
  Argus.Common.JsonRpc.Dispatcher,
  Argus.Common.JsonRpc.Connection,
  Argus.Common.JsonRpc.Watchdog,
  Argus.Common.Lsp.Lifecycle,
  Argus.Common.Lsp.TextDocumentSync,
  Argus.Common.Lsp.SyntaxDiagnostics,
  Argus.Common.Lsp.PullDiagnostics,
  Argus.Common.Lsp.DocumentSymbols,
  Argus.Common.Lsp.FoldingRanges,
  Argus.Common.Lsp.LinkedEditing,
  Argus.Common.Lsp.Formatting,
  Argus.Common.Lsp.SelectionRanges,
  Argus.Common.Lsp.Definition,
  Argus.Common.Lsp.Hover,
  Argus.Common.Lsp.WorkspaceSymbols,
  Argus.Common.Lsp.DocumentHighlights,
  Argus.Common.Lsp.CodeActions,
  Argus.Common.Lsp.DocumentLinks,
  Argus.Common.Lsp.Colors,
  Argus.Common.Lsp.Commands,
  Argus.Common.Lsp.References,
  Argus.Common.Lsp.Rename,
  Argus.Common.Lsp.Completion,
  Argus.Common.Lsp.SignatureHelp,
  Argus.Common.Lsp.Hierarchies,
  Argus.Common.Lsp.Implementations,
  Argus.Common.Lsp.InlayHints,
  Argus.Common.Lsp.CodeLens,
  Argus.Common.Lsp.SemanticTokens,
  Argus.Common.Lsp.Status,
  Argus.Common.JsonRpc.Statistics,
  Argus.Common.Lsp.WatchedFiles,
  Argus.Common.Lsp.WorkspaceFolders,
  Argus.Common.Lsp.Configuration,
  Argus.Common.Documents.Contract,
  Argus.Common.Configuration.Contract,
  Argus.Common.Index.Contract,
  Argus.Common.Compiler.Contract,
  Argus.Common.Compiler.Results,
  Argus.Common.Lsp.WorkDoneProgress,
  Shell.CommandLine,
  Argus.Windows.Process.ParentWatcher,
  Shell.Workspace;

type
  TServerComposition = class
  private
    FTransport: IJsonRpcTransport;
    FLogger: ILogger;
    FDispatcher: TJsonRpcDispatcher;
    FLifecycle: TLspLifecycle;
    FDocuments: IDocumentStore;
    FTextDocumentSync: TLspTextDocumentSync;
    FSyntaxDiagnostics: TLspSyntaxDiagnostics;
    FPullDiagnostics: TLspPullDiagnostics;
    FDocumentSymbols: TLspDocumentSymbols;
    FFoldingRanges: TLspFoldingRanges;
    FLinkedEditing: TLspLinkedEditing;
    FFormatting: TLspFormatting;
    FSelectionRanges: TLspSelectionRanges;
    FDefinition: TLspDefinition;
    FHover: TLspHover;
    FWorkspaceSymbols: TLspWorkspaceSymbols;
    FDocumentHighlights: TLspDocumentHighlights;
    FReferences: TLspReferences;
    FRename: TLspRename;
    /// <summary>Nicht vertrauenswürdiger Arbeitsbereich (#186): kein Compiler-Lauf.</summary>
    FRestricted: Boolean;
    /// <summary>Prozessnummer des Editors aus der Befehlszeile (#283); 0 = keine.</summary>
    FClientProcessId: Cardinal;
    FParentWatcher: TParentWatcher;
    FCompletion: TLspCompletion;
    FSignatureHelp: TLspSignatureHelp;
    FHierarchies: TLspHierarchies;
    FImplementations: TLspImplementations;
    FInlayHints: TLspInlayHints;
    FCodeLens: TLspCodeLens;
    FSemanticTokens: TLspSemanticTokens;
    FCodeActions: TLspCodeActions;
    FDocumentLinks: TLspDocumentLinks;
    FColors: TLspColors;
    FCommands: TLspCommands;
    FStatistics: IJsonRpcStatistics;
    FWatchedFiles: TLspWatchedFiles;
    FWorkspaceFolders: TLspWorkspaceFolders;
    /// <summary>Für argus.json außerhalb aller Ordner: nur Fehlermeldungen.</summary>
    FLooseConfiguration: TLspConfiguration;
    FConnection: TJsonRpcConnection;
    FIndex: ISymbolIndex;
    // Ordner des Arbeitsbereichs. Ändern nur im Thread der Nachrichtenschleife,
    // unter FWorkspacesLock, weil Anfrage-Threads lesen.
    FWorkspaces: TObjectList<TShellWorkspace>;
    FWorkspacesLock: TObject;
    FWorkspaceCounter: Integer;
    FEditorSettings: string;
    // Compiler-Anbindung (#40): höchstens ein Lauf zugleich, ein weiterer wird vorgemerkt.
    FCompilerResults: TCompilerResults;
    FCompilerProcess: ICompilerProcess;
    FCompileProgress: TLspWorkDoneProgress;
    FCompileLock: TObject;
    FCompileThread: TThread;
    FCompiling: Boolean;
    FHasPendingCompile: Boolean;
    FPendingCompile: TCompilerRequest;
    /// <summary>Grund, warum der Compiler nicht nutzbar ist; '' = nutzbar. Unter FCompileLock.
    /// Dann kompiliert der Server nach dem Speichern nicht mehr, bis das Projekt neu geladen wird.</summary>
    FCompilerUnavailable: string;
    /// <summary>Der Client hat keinen brauchbaren Ordner gemeldet (RAD Studio, #175):
    /// Ordner werden aus den geöffneten Dateien abgeleitet.</summary>
    FDeriveWorkspaces: Boolean;
    /// <summary>Überwacht den Editor-Prozess aus initialize oder der Befehlszeile.</summary>
    procedure WatchParent(const AInitializeParams: TJSONObject);
    procedure AddWorkspace(const AFolder: TWorkspaceFolder);
    /// <summary>Legt zur Datei den Ordner mit der nächsten Projektdatei an, falls sie in keinem Ordner liegt.</summary>
    procedure DeriveWorkspace(const AFileName: string);
    procedure RemoveWorkspace(const AFolder: TWorkspaceFolder);
    /// <summary>Innerster Ordner zur Datei oder nil. Aufrufer hält FWorkspacesLock.</summary>
    function WorkspaceOf(const AFileName: string): TShellWorkspace;
    function EnsureUnit(const AUnitName: string): Boolean;
    /// <summary>Text einer Quelldatei; geöffnete Dokumente haben Vorrang vor der Platte.</summary>
    function ReadSourceText(const AFileName: string; out AText: string): Boolean;
    /// <summary>Projektdateien aller Ordner und geöffnete Dokumente, für Referenzen und Umbenennen.</summary>
    function ProjectSourceFiles: TArray<string>;
    /// <summary>Inhalt des Status-Befehls (#28).</summary>
    function CollectStatus: TServerStatus;
    function DefinesFor(const AUri: string; out ADefines: TArray<string>): Boolean;
    function DelphiVersionFor(const AUri: string): string;
    function InlayHintSettingsFor(const AUri: string): TInlayHintSettings;
    function CompletionSettingsFor(const AUri: string): TCompletionSettings;
    function FormatStyleFor(const AUri: string): TFormatStyle;
    function RuleContextFor(const AUri: string; out AContext: TRuleCheckContext): Boolean;
    /// <summary>Namespaces aller Projekte an die Features weitergeben, Diagnosen neu prüfen.</summary>
    procedure ProjectLoaded;
    procedure HandleDocumentEvent(AKind: TDocumentEventKind; const ADocument: ITextDocument);
    /// <summary>Kompiliert das Projekt zu AFileName ('' = einziger Ordner) im Hintergrund.
    /// AManual: über den Befehl, auch wenn der Compiler zuletzt nicht nutzbar war.</summary>
    procedure StartCompile(const AFileName: string; AManual: Boolean);
    /// <summary>Merkt sich, dass der Compiler nicht nutzbar ist, und meldet das einmal.</summary>
    procedure CompilerUnavailable(const AReason: string);
    /// <summary>Hintergrund-Thread: führt ARequest und vorgemerkte Läufe aus.</summary>
    procedure CompileLoop(const ARequest: TCompilerRequest);
    procedure HandleDidChangeConfiguration(const AParams: TJSONValue);
    /// <summary>Dateiänderungen von außen: Projektdateien laden das Projekt neu, Quelltexte aktualisieren den Index.</summary>
    procedure HandleWatchedFiles(const AChanges: TArray<TFileChange>);
    class function BuildCapabilities: TJSONObject; static;
    /// <summary>Fehlerbeschreibung mit letzter Nachricht und Stacktrace für das Log.</summary>
    function DescribeFailure(const AError: Exception): string;
  public const
    CompileCommand = 'argus.server.compile';
    SelectBuildCommand = 'argus.server.selectBuild';
    RebuildIndexCommand = 'argus.server.rebuildIndex';
    /// <summary>Anfragen, die länger laufen, werden abgebrochen und gemeldet.</summary>
    RequestTimeoutMs = 10000;
  public
    constructor Create(const ATransport: IJsonRpcTransport; const ALogger: ILogger);
    destructor Destroy; override;
    /// <summary>Komposition mit stdin/stdout des Prozesses und Logging nach AOptions.</summary>
    class function CreateForStdio(const AOptions: TCommandLineOptions): TServerComposition; static;
    /// <summary>Verarbeitet Nachrichten bis exit oder Ende der Eingabe und liefert den Exit-Code.</summary>
    function Run: Integer;
    property Logger: ILogger read FLogger;
    /// <summary>Geöffnete Dokumente, für Features, die Dateien auswerten.</summary>
    property Documents: IDocumentStore read FDocuments;
    property Index: ISymbolIndex read FIndex;
  end;

implementation

// Winapi.Windows zuerst, damit die System-Units bei gleichen Namen Vorrang haben.
uses
  Winapi.Windows,
  System.IOUtils,
  System.Math,
  System.StrUtils,
  Argus.Common.Product.Version,
  Argus.Common.Logging.Providers.Logger,
  Argus.Common.Logging.Providers.StreamSink,
  Argus.Common.JsonRpc.StreamTransport,
  Argus.Common.JsonRpc.TracingTransport,
  Argus.Common.Lsp.Adapters.LogMessageSink,
  Argus.Common.Documents.Providers.DocumentStore,
  Argus.Common.Documents.FileEncoding,
  Argus.Common.Documents.Uris,
  Argus.Common.Index.SymbolIndex,
  Argus.Common.Editing.UsesActions,
  Argus.Common.Rules.Builtin,
  Argus.Common.Compiler.OutputParser,
  Argus.Windows.Compiler.Adapters.ProcessRunner,
  Argus.Windows.Console.StdStreams,
  Argus.Windows.Documents.PathCanonicalizer,
  Argus.Windows.Diagnostics.Adapters.DebugOutputSink,
  Argus.Windows.Diagnostics.StackTrace,
  Argus.Common.Logging.Providers.RotatingFileStream,
  Argus.Windows.Editing.SystemColors,
  Argus.Common.Projects.Contract;

function StringsToJson(const AValues: TArray<string>): TJSONArray;
var
  Value: string;
begin
  Result := TJSONArray.Create;
  for Value in AValues do
    Result.Add(Value);
end;

// Mitschnitt anlegen. Rotiert bei Überlänge (#283). Hält ihn schon ein anderer
// Server (jede RAD-Studio-IDE startet einen eigenen), weicht er auf einen Namen
// mit AFallbackTag aus, statt ganz ohne Mitschnitt zu laufen. AActualName ist
// die tatsächlich benutzte Datei.
function CreateTraceStream(const AFileName, AFallbackTag: string; out AActualName: string): TStream;
var
  Directory: string;
  Stream: TRotatingFileStream;
begin
  Directory := TPath.GetDirectoryName(TPath.GetFullPath(AFileName));
  if Directory <> '' then
    ForceDirectories(Directory);
  Stream := TRotatingFileStream.Create(AFileName, False, AFallbackTag);
  AActualName := Stream.FileName;
  Result := Stream;
end;

{ TServerComposition }

constructor TServerComposition.Create(const ATransport: IJsonRpcTransport; const ALogger: ILogger);
begin
  inherited Create;
  FTransport := ATransport;
  FLogger := ALogger;
  FDispatcher := TJsonRpcDispatcher.Create;
  FStatistics := TJsonRpcStatistics.Create;
  FDispatcher.Statistics := FStatistics;
  FDispatcher.Watchdog := TJsonRpcWatchdog.Create(FDispatcher.PendingRequests, RequestTimeoutMs,
    procedure(const AMethod: string; ATimeoutMs: Cardinal)
    begin
      FLogger.Warning(Format('Anfrage %s nach %d ms abgebrochen (Zeitlimit)', [AMethod, ATimeoutMs]));
    end);
  FDispatcher.OnRequestFailed :=
    procedure(const AMethod: string; const AParams: TJSONValue; const AError: Exception)
    var
      Params: string;
    begin
      Params := '';
      if AParams <> nil then
        Params := AParams.ToJSON;
      if Length(Params) > 500 then
        Params := Copy(Params, 1, 500) + '…';
      FLogger.Error(Format('Anfrage %s fehlgeschlagen: %s: %s%sParameter: %s%s%s',
        [AMethod, AError.ClassName, AError.Message, sLineBreak, Params, sLineBreak, AError.StackTrace]));
    end;
  FLifecycle := TLspLifecycle.Create(TProductVersion.Name, TProductVersion.Version,
    function: TJSONObject
    begin
      Result := BuildCapabilities;
      // Pull-Diagnosen nur für Clients, die sie können; sonst bleibt es bei publishDiagnostics (#82).
      if TLspPullDiagnostics.ClientSupportsPull(FLifecycle.InitializeParams) then
      begin
        Result.AddPair('diagnosticProvider', TLspPullDiagnostics.Capability);
        FPullDiagnostics.RefreshSupport := TLspPullDiagnostics.ClientSupportsRefresh(FLifecycle.InitializeParams);
        FSyntaxDiagnostics.PullMode := True;
      end;
    end);
  FLifecycle.Attach(FDispatcher);
  // Ändert der Client ein Dokument, sind laufende Anfragen dazu überholt (#283).
  FDispatcher.PendingRequests.AddContentChangeMethod('textDocument/didChange');
  FDocuments := TDocumentStore.Create(
    function(const APath: string): string
    begin
      Result := TWindowsPathCanonicalizer.Canonicalize(APath);
    end);
  FTextDocumentSync := TLspTextDocumentSync.Create(FDocuments);
  FTextDocumentSync.Attach(FDispatcher);
  FSyntaxDiagnostics := TLspSyntaxDiagnostics.Create(FDocuments, FTransport);
  FSyntaxDiagnostics.OnError :=
    procedure(AError: Exception)
    begin
      FLogger.Error(Format('Fehler beim Prüfen der Syntax: %s: %s', [AError.ClassName, AError.Message]));
    end;
  FCompilerResults := TCompilerResults.Create;
  FCompilerProcess := TProcessRunner.Create;
  FCompileProgress := TLspWorkDoneProgress.Create(FTransport, 'argus-compile');
  FCompileLock := TObject.Create;
  FSyntaxDiagnostics.CompilerMessagesProvider :=
    function(const AFileName: string): TArray<TCompilerMessage>
    begin
      Result := FCompilerResults.MessagesFor(AFileName);
    end;
  FSyntaxDiagnostics.Attach;
  FPullDiagnostics := TLspPullDiagnostics.Create(FDocuments, FSyntaxDiagnostics, FTransport, ProjectSourceFiles,
    function(const AFileName: string; out AStamp: Int64): Boolean
    begin
      Result := TFile.Exists(AFileName);
      if Result then
        AStamp := Round(TFile.GetLastWriteTimeUtc(AFileName) * MSecsPerDay)
      else
        AStamp := 0;
    end,
    function(const AFileName: string; out AText: string): Boolean
    var
      FileFormat: TFileFormat;
    begin
      Result := TFile.Exists(AFileName);
      if Result then
        AText := TFileEncoding.LoadFromFile(AFileName, FileFormat)
      else
        AText := '';
    end);
  FPullDiagnostics.Attach(FDispatcher);
  FSyntaxDiagnostics.OnPullChanged := FPullDiagnostics.Changed;
  FDocumentSymbols := TLspDocumentSymbols.Create(FDocuments);
  FDocumentSymbols.Attach(FDispatcher);
  FFoldingRanges := TLspFoldingRanges.Create(FDocuments);
  FFoldingRanges.Attach(FDispatcher);
  FLinkedEditing := TLspLinkedEditing.Create(FDocuments);
  FLinkedEditing.Attach(FDispatcher);
  FFormatting := TLspFormatting.Create(FDocuments, FormatStyleFor,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := FileExists(AFileName);
      if Result then
        AText := TFile.ReadAllText(AFileName);
    end);
  FFormatting.UsesCommandFor :=
    function(const AUri: string): Boolean
    var
      Workspace: TShellWorkspace;
    begin
      TMonitor.Enter(FWorkspacesLock);
      try
        Workspace := WorkspaceOf(TDocumentUris.ToPath(AUri));
        if (Workspace = nil) and (FWorkspaces.Count = 1) then
          Workspace := FWorkspaces[0];
        Result := (Workspace = nil) or Workspace.Configuration.Settings.UsesCommand;
      finally
        TMonitor.Exit(FWorkspacesLock);
      end;
    end;
  FFormatting.Attach(FDispatcher);
  FSelectionRanges := TLspSelectionRanges.Create(FDocuments);
  FSelectionRanges.Attach(FDispatcher);
  FWorkspaces := TObjectList<TShellWorkspace>.Create(True);
  FWorkspacesLock := TObject.Create;
  FLooseConfiguration := TLspConfiguration.Create(FDocuments, FTransport,
    function(const AFileName: string; out AText: string): Boolean
    begin
      AText := '';
      Result := False;
    end);
  FDocuments.Subscribe(HandleDocumentEvent);
  FDispatcher.RegisterNotification(TLspConfiguration.DidChangeConfigurationMethod, HandleDidChangeConfiguration);
  FSyntaxDiagnostics.DefinesProvider := DefinesFor;
  FSyntaxDiagnostics.IncludePathsProvider :=
    function(const AUri: string): TArray<string>
    var
      Workspace: TShellWorkspace;
    begin
      Result := nil;
      TMonitor.Enter(FWorkspacesLock);
      try
        Workspace := WorkspaceOf(TDocumentUris.ToPath(AUri));
        if Workspace <> nil then
          Result := Workspace.IncludePaths;
      finally
        TMonitor.Exit(FWorkspacesLock);
      end;
    end;
  FSyntaxDiagnostics.VersionProvider := DelphiVersionFor;
  FSyntaxDiagnostics.RuleProvider := RuleContextFor;
  FIndex := TSymbolIndex.Create;
  FDefinition := TLspDefinition.Create(FDocuments, FIndex,
    function(const AUnitName: string): Boolean
    begin
      Result := EnsureUnit(AUnitName);
    end);
  FDefinition.ReadText :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := ReadSourceText(AFileName, AText);
    end;
  FDefinition.Attach(FDispatcher);
  FHover := TLspHover.Create(FDocuments, FIndex,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := ReadSourceText(AFileName, AText);
    end,
    function(const AUnitName: string): Boolean
    begin
      Result := EnsureUnit(AUnitName);
    end);
  FHover.VersionProvider := DelphiVersionFor;
  FHover.Attach(FDispatcher);
  FWorkspaceSymbols := TLspWorkspaceSymbols.Create(FIndex);
  FWorkspaceSymbols.Attach(FDispatcher);
  FDocumentHighlights := TLspDocumentHighlights.Create(FDocuments, FIndex,
    function(const AUnitName: string): Boolean
    begin
      Result := EnsureUnit(AUnitName);
    end);
  FDocumentHighlights.Attach(FDispatcher);
  FReferences := TLspReferences.Create(FDocuments, FIndex,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := ReadSourceText(AFileName, AText);
    end,
    ProjectSourceFiles,
    function(const AUnitName: string): Boolean
    begin
      Result := EnsureUnit(AUnitName);
    end);
  FReferences.Attach(FDispatcher);
  FRename := TLspRename.Create(FDocuments, FIndex,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := ReadSourceText(AFileName, AText);
    end,
    ProjectSourceFiles,
    function(const AUnitName: string): Boolean
    begin
      Result := EnsureUnit(AUnitName);
    end);
  FRename.Attach(FDispatcher);
  FCompletion := TLspCompletion.Create(FDocuments, FIndex,
    function(const AUnitName: string): Boolean
    begin
      Result := EnsureUnit(AUnitName);
    end);
  FCompletion.MatchingFor :=
    function(const AUri: string): TCompletionMatching
    begin
      Result := CompletionSettingsFor(AUri).Matching;
    end;
  FCompletion.Attach(FDispatcher);
  FSignatureHelp := TLspSignatureHelp.Create(FDocuments, FIndex,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := ReadSourceText(AFileName, AText);
    end,
    function(const AUnitName: string): Boolean
    begin
      Result := EnsureUnit(AUnitName);
    end);
  FSignatureHelp.Attach(FDispatcher);
  FHierarchies := TLspHierarchies.Create(FDocuments, FIndex,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := ReadSourceText(AFileName, AText);
    end,
    ProjectSourceFiles,
    function(const AUnitName: string): Boolean
    begin
      Result := EnsureUnit(AUnitName);
    end);
  FHierarchies.Attach(FDispatcher);
  FImplementations := TLspImplementations.Create(FDocuments, FIndex,
    function(const AUnitName: string): Boolean
    begin
      Result := EnsureUnit(AUnitName);
    end);
  FImplementations.Attach(FDispatcher);
  FInlayHints := TLspInlayHints.Create(FDocuments, FIndex,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := ReadSourceText(AFileName, AText);
    end,
    InlayHintSettingsFor,
    function(const AUnitName: string): Boolean
    begin
      Result := EnsureUnit(AUnitName);
    end);
  FInlayHints.Attach(FDispatcher);
  FCodeLens := TLspCodeLens.Create(FDocuments, FIndex,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := ReadSourceText(AFileName, AText);
    end,
    ProjectSourceFiles,
    function(const AUnitName: string): Boolean
    begin
      Result := EnsureUnit(AUnitName);
    end);
  FCodeLens.Attach(FDispatcher);
  FSemanticTokens := TLspSemanticTokens.Create(FDocuments, FIndex,
    function(const AUnitName: string): Boolean
    begin
      Result := EnsureUnit(AUnitName);
    end);
  FSemanticTokens.Attach(FDispatcher);
  FCodeActions := TLspCodeActions.Create(FDocuments, RuleContextFor);
  FCodeActions.SortUsesFor :=
    function(const AUri: string): Boolean
    var
      Workspace: TShellWorkspace;
    begin
      TMonitor.Enter(FWorkspacesLock);
      try
        Workspace := WorkspaceOf(TDocumentUris.ToPath(AUri));
        if (Workspace = nil) and (FWorkspaces.Count = 1) then
          Workspace := FWorkspaces[0];
        Result := (Workspace <> nil) and Workspace.Configuration.Settings.SortUses;
      finally
        TMonitor.Exit(FWorkspacesLock);
      end;
    end;
  FCodeActions.SortUsesByNamespaceFor :=
    function(const AUri: string): Boolean
    var
      Workspace: TShellWorkspace;
    begin
      TMonitor.Enter(FWorkspacesLock);
      try
        Workspace := WorkspaceOf(TDocumentUris.ToPath(AUri));
        if (Workspace = nil) and (FWorkspaces.Count = 1) then
          Workspace := FWorkspaces[0];
        Result := (Workspace <> nil) and Workspace.Configuration.Settings.SortUsesByNamespace;
      finally
        TMonitor.Exit(FWorkspacesLock);
      end;
    end;
  FCodeActions.UsesContextFor :=
    function(const AUri: string; out AContext: TUsesContext): Boolean
    var
      Workspace: TShellWorkspace;
    begin
      AContext := Default(TUsesContext);
      TMonitor.Enter(FWorkspacesLock);
      try
        Workspace := WorkspaceOf(TDocumentUris.ToPath(AUri));
        if (Workspace = nil) and (FWorkspaces.Count = 1) then
          Workspace := FWorkspaces[0];
        if Workspace <> nil then
        begin
          AContext.Keep := Workspace.Configuration.Settings.UsesKeep;
          AContext.Namespaces := Workspace.Namespaces;
        end;
      finally
        TMonitor.Exit(FWorkspacesLock);
      end;
      AContext.Info :=
        function(const AUnitName: string): TUsesUnitInfo
        var
          UnitIndex: TUnitIndex;
          Symbol: TIndexSymbol;
        begin
          Result := Default(TUsesUnitInfo);
          EnsureUnit(AUnitName);
          if not FIndex.FindUnit(AUnitName, UnitIndex) then
            Exit;
          Result.Known := True;
          Result.HasInitialization := UnitIndex.HasInitialization;
          for Symbol in UnitIndex.Symbols do
            if Symbol.InInterface then
              Result.Names := Result.Names + [Symbol.Name];
        end;
      AContext.Declaring :=
        function(const AName: string): TArray<string>
        var
          Location: TSymbolLocation;
        begin
          Result := nil;
          for Location in FIndex.FindSymbols(AName) do
            if Location.Symbol.InInterface and (Location.Symbol.Container = '') and
              (IndexText(Location.UnitName, Result) < 0) then
              Result := Result + [Location.UnitName];
        end;
      Result := True;
    end;
  FCodeActions.Attach(FDispatcher);
  FDocumentLinks := TLspDocumentLinks.Create(FDocuments,
    function(const AUri: string): TArray<string>
    var
      Workspace: TShellWorkspace;
    begin
      Result := nil;
      TMonitor.Enter(FWorkspacesLock);
      try
        Workspace := WorkspaceOf(TDocumentUris.ToPath(AUri));
        if Workspace <> nil then
          Result := Workspace.IncludePaths;
      finally
        TMonitor.Exit(FWorkspacesLock);
      end;
    end);
  FDocumentLinks.Attach(FDispatcher);
  FColors := TLspColors.Create(FDocuments, WindowsSystemColor);
  FColors.Attach(FDispatcher);
  FCommands := TLspCommands.Create;
  FCommands.Register(StatusCommand,
    function(const AArguments: TJSONArray): TJSONValue
    var
      Status: TServerStatus;
    begin
      Status := CollectStatus;
      FLogger.Info('Status:' + sLineBreak + Status.ToMarkdown);
      Result := Status.ToJson;
    end);
  FCommands.Register(CompileCommand,
    function(const AArguments: TJSONArray): TJSONValue
    var
      Uri: string;
    begin
      // Optional die URI einer Datei, deren Projekt kompiliert wird.
      Uri := '';
      if (AArguments <> nil) and (AArguments.Count > 0) and (AArguments.Items[0] is TJSONString) then
        Uri := AArguments.Items[0].Value;
      if Uri <> '' then
        StartCompile(TDocumentUris.ToPath(Uri), True)
      else
        StartCompile('', True);
      Result := TJSONNull.Create;
    end);
  FCommands.Register(RebuildIndexCommand,
    function(const AArguments: TJSONArray): TJSONValue
    var
      Workspace: TShellWorkspace;
      Targets: TArray<TShellWorkspace>;
    begin
      // Alle Ordner ohne Cache neu einlesen (#49), z. B. nach Änderungen außerhalb des Editors.
      TMonitor.Enter(FWorkspacesLock);
      try
        Targets := FWorkspaces.ToArray;
      finally
        TMonitor.Exit(FWorkspacesLock);
      end;
      for Workspace in Targets do
        Workspace.Rebuild;
      FLogger.Info(Format('Index wird für %d Ordner neu aufgebaut', [Length(Targets)]));
      Result := TJSONNull.Create;
    end);
  FCommands.Register(SelectBuildCommand,
    function(const AArguments: TJSONArray): TJSONValue
    var
      Options: TJSONObject;
      Config, Platform, Uri, Error: string;
      Workspace: TShellWorkspace;
      Targets: TArray<TShellWorkspace>;
      Project: TProjectInfo;
      Items: TJSONArray;
      Item: TJSONObject;
    begin
      // Argument: {"config": "Release", "platform": "Win64", "uri": "…"}; alle Felder optional.
      // Ohne Konfiguration und Plattform nur die aktuelle Auswahl je Projekt (#46).
      Config := '';
      Platform := '';
      Uri := '';
      if (AArguments <> nil) and (AArguments.Count > 0) and (AArguments.Items[0] is TJSONObject) then
      begin
        Options := TJSONObject(AArguments.Items[0]);
        Options.TryGetValue<string>('config', Config);
        Options.TryGetValue<string>('platform', Platform);
        Options.TryGetValue<string>('uri', Uri);
      end;
      Targets := nil;
      TMonitor.Enter(FWorkspacesLock);
      try
        if Uri <> '' then
        begin
          Workspace := WorkspaceOf(TDocumentUris.ToPath(Uri));
          if Workspace <> nil then
            Targets := [Workspace];
        end
        else
          Targets := FWorkspaces.ToArray;
      finally
        TMonitor.Exit(FWorkspacesLock);
      end;
      if (Config <> '') or (Platform <> '') then
        for Workspace in Targets do
          if Workspace.Project(Project) and not Workspace.SelectBuild(Config, Platform, Error) then
            raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, Error);
      Items := TJSONArray.Create;
      for Workspace in Targets do
        if Workspace.Project(Project) then
        begin
          Item := TJSONObject.Create;
          Item.AddPair('folder', Workspace.Name);
          Item.AddPair('project', Project.FileName);
          Item.AddPair('config', IfThen(Config <> '', Config, Project.Config));
          Item.AddPair('platform', IfThen(Platform <> '', Platform, Project.Platform));
          Item.AddPair('configs', StringsToJson(Project.Configs));
          Item.AddPair('platforms', StringsToJson(Project.Platforms));
          Items.AddElement(Item);
        end;
      Result := TJSONObject.Create(TJSONPair.Create('projects', Items));
    end);
  FCommands.Attach(FDispatcher);
  FWatchedFiles := TLspWatchedFiles.Create(FTransport);
  FWatchedFiles.OnChanged := HandleWatchedFiles;
  FWatchedFiles.Attach(FDispatcher);
  FWorkspaceFolders := TLspWorkspaceFolders.Create;
  FWorkspaceFolders.OnChanged :=
    procedure(const AAdded, ARemoved: TArray<TWorkspaceFolder>)
    var
      Folder: TWorkspaceFolder;
    begin
      for Folder in ARemoved do
        RemoveWorkspace(Folder);
      for Folder in AAdded do
        AddWorkspace(Folder);
    end;
  FWorkspaceFolders.Attach(FDispatcher);
  FLifecycle.OnInitialized :=
    procedure
    var
      Folders: TArray<TWorkspaceFolder>;
      Folder: TWorkspaceFolder;
    begin
      WatchParent(FLifecycle.InitializeParams);
      FHover.Markdown := TLspHover.ClientSupportsMarkdown(FLifecycle.InitializeParams);
      Folders := TLspWorkspaceFolders.FromInitialize(FLifecycle.InitializeParams);
      FDeriveWorkspaces := Length(Folders) = 0;
      if FDeriveWorkspaces then
        FLogger.Info('Kein Arbeitsbereichsordner gemeldet; Ordner werden aus den geöffneten Dateien abgeleitet');
      for Folder in Folders do
        AddWorkspace(Folder);
      FWatchedFiles.RegisterWatchers(FLifecycle.InitializeParams);
    end;
  FConnection := TJsonRpcConnection.Create(FTransport, FDispatcher);
  FConnection.OnError :=
    procedure(const AError: Exception)
    begin
      FLogger.Error('Fehler bei der Verarbeitung: ' + DescribeFailure(AError));
    end;
  FLifecycle.OnExit :=
    procedure
    begin
      FConnection.Stop;
    end;
end;

destructor TServerComposition.Destroy;
begin
  // Vor der Verbindung: der Wächter ruft FConnection.Stop.
  FParentWatcher.Free;
  FConnection.Free;
  // Laufenden Compilerlauf abwarten: Er meldet über die Syntaxprüfung.
  if FCompileThread <> nil then
  begin
    FCompileThread.WaitFor;
    FreeAndNil(FCompileThread);
  end;
  // Vor den Ordnern: der Hintergrund-Thread der Syntaxprüfung fragt ihre Symbole ab.
  FPullDiagnostics.Free;
  FSyntaxDiagnostics.Free;
  // Ordner vor dem Index: ihre Index-Threads laufen noch.
  FWorkspaces.Free;
  FWorkspacesLock.Free;
  FLooseConfiguration.Free;
  FWorkspaceFolders.Free;
  FIndex := nil;
  FDocumentSymbols.Free;
  FFoldingRanges.Free;
  FLinkedEditing.Free;
  FFormatting.Free;
  FSelectionRanges.Free;
  FDefinition.Free;
  FHover.Free;
  FWorkspaceSymbols.Free;
  FDocumentHighlights.Free;
  FReferences.Free;
  FSemanticTokens.Free;
  FCodeLens.Free;
  FInlayHints.Free;
  FImplementations.Free;
  FHierarchies.Free;
  FSignatureHelp.Free;
  FCompletion.Free;
  FRename.Free;
  FCodeActions.Free;
  FDocumentLinks.Free;
  FColors.Free;
  FCommands.Free;
  FCompileProgress.Free;
  FCompileLock.Free;
  FCompilerResults.Free;
  FCompilerProcess := nil;
  FWatchedFiles.Free;
  FTextDocumentSync.Free;
  FDocuments := nil;
  FLifecycle.Free;
  FDispatcher.Watchdog := nil;
  FDispatcher.Free;
  FTransport := nil;
  FLogger := nil;
  inherited;
end;

procedure TServerComposition.AddWorkspace(const AFolder: TWorkspaceFolder);
var
  Workspace: TShellWorkspace;
begin
  Inc(FWorkspaceCounter);
  Workspace := TShellWorkspace.Create(AFolder.Path, AFolder.Name, FDocuments, FTransport, FLogger, FIndex,
    Format('argus-index-%d', [FWorkspaceCounter]));
  Workspace.OnProjectLoaded := ProjectLoaded;
  // Das Zeitlimit gilt serverweit; bei mehreren Ordnern das zuletzt gelesene.
  Workspace.OnSettingsChanged :=
    procedure(ASettings: TServerSettings)
    begin
      FDispatcher.Watchdog.SetTimeout(ASettings.RequestTimeoutMs);
    end;
  Workspace.Configuration.SetEditorSettings(FEditorSettings);
  TMonitor.Enter(FWorkspacesLock);
  try
    FWorkspaces.Add(Workspace);
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
  FLogger.Info('Arbeitsbereichsordner: ' + AFolder.Path);
  Workspace.Load;
end;

procedure TServerComposition.RemoveWorkspace(const AFolder: TWorkspaceFolder);
var
  Index: Integer;
  Workspace: TShellWorkspace;
  UnitIndex: TUnitIndex;
begin
  Workspace := nil;
  TMonitor.Enter(FWorkspacesLock);
  try
    for Index := FWorkspaces.Count - 1 downto 0 do
      if SameText(ExcludeTrailingPathDelimiter(FWorkspaces[Index].Root), ExcludeTrailingPathDelimiter(AFolder.Path)) then
      begin
        Workspace := FWorkspaces.Extract(FWorkspaces[Index]);
        Break;
      end;
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
  if Workspace = nil then
    Exit;
  FLogger.Info('Arbeitsbereichsordner entfernt: ' + AFolder.Path);
  Workspace.Stop;
  // Projektdateien des Ordners verlassen den Index; geteilte Bibliotheks-Units bleiben.
  for UnitIndex in FIndex.Units do
    if TLspWorkspaceFolders.FolderOf([TWorkspaceFolder.Create(Workspace.Root, '')], UnitIndex.FileName) = 0 then
      FIndex.RemoveFile(UnitIndex.FileName);
  Workspace.Free;
  ProjectLoaded;
end;

function HasProjectFile(const AFolder: string): Boolean;
begin
  try
    Result := (Length(TDirectory.GetFiles(AFolder, '*.dproj')) > 0) or
      (Length(TDirectory.GetFiles(AFolder, '*.groupproj')) > 0);
  except
    // Ungültige oder nicht lesbare Ordner zählen als ohne Projekt.
    on Exception do
      Result := False;
  end;
end;

procedure TServerComposition.DeriveWorkspace(const AFileName: string);
var
  Known: Boolean;
  Folder: string;
begin
  TMonitor.Enter(FWorkspacesLock);
  try
    Known := WorkspaceOf(AFileName) <> nil;
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
  if Known then
    Exit;
  Folder := TLspWorkspaceFolders.ProjectFolderFor(AFileName, HasProjectFile);
  if Folder <> '' then
    AddWorkspace(TWorkspaceFolder.Create(Folder, ExtractFileName(Folder)));
end;

function TServerComposition.WorkspaceOf(const AFileName: string): TShellWorkspace;
var
  Folders: TArray<TWorkspaceFolder>;
  Workspace: TShellWorkspace;
  Index: Integer;
begin
  Folders := nil;
  for Workspace in FWorkspaces do
    Folders := Folders + [TWorkspaceFolder.Create(Workspace.Root, Workspace.Name)];
  Index := TLspWorkspaceFolders.FolderOf(Folders, AFileName);
  if Index < 0 then
    Result := nil
  else
    Result := FWorkspaces[Index];
end;

function TServerComposition.EnsureUnit(const AUnitName: string): Boolean;
var
  Workspace: TShellWorkspace;
begin
  // Anfrage-Threads: jeder Ordner versucht es mit seinen Suchpfaden.
  TMonitor.Enter(FWorkspacesLock);
  try
    for Workspace in FWorkspaces do
      if Workspace.EnsureUnit(AUnitName) then
        Exit(True);
    Result := False;
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
end;

function TServerComposition.DefinesFor(const AUri: string; out ADefines: TArray<string>): Boolean;
var
  Workspace: TShellWorkspace;
begin
  ADefines := nil;
  TMonitor.Enter(FWorkspacesLock);
  try
    Workspace := WorkspaceOf(TDocumentUris.ToPath(AUri));
    // Dateien außerhalb aller Ordner: wie der einzige Ordner, sonst nicht abblenden.
    if (Workspace = nil) and (FWorkspaces.Count = 1) then
      Workspace := FWorkspaces[0];
    Result := (Workspace <> nil) and Workspace.Defines(ADefines);
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
end;

function AllocatedBytes: Int64;
var
  State: TMemoryManagerState;
  I: Integer;
begin
  {$WARN SYMBOL_PLATFORM OFF}
  GetMemoryManagerState(State);
  {$WARN SYMBOL_PLATFORM ON}
  Result := Int64(State.TotalAllocatedMediumBlockSize) + Int64(State.TotalAllocatedLargeBlockSize);
  for I := Low(State.SmallBlockTypeStates) to High(State.SmallBlockTypeStates) do
    Inc(Result, Int64(State.SmallBlockTypeStates[I].AllocatedBlockCount) *
      State.SmallBlockTypeStates[I].UseableBlockSize);
end;

function TServerComposition.ReadSourceText(const AFileName: string; out AText: string): Boolean;
var
  Document: ITextDocument;
  FileFormat: TFileFormat;
begin
  if FDocuments.TryGet(TDocumentUris.FromPath(AFileName), Document) then
  begin
    AText := Document.Text;
    Exit(True);
  end;
  Result := FileExists(AFileName);
  if Result then
    AText := TFileEncoding.LoadFromFile(AFileName, FileFormat)
  else
    AText := '';
end;

function TServerComposition.ProjectSourceFiles: TArray<string>;
var
  Workspace: TShellWorkspace;
  Document: ITextDocument;
  FileName: string;
begin
  Result := nil;
  TMonitor.Enter(FWorkspacesLock);
  try
    for Workspace in FWorkspaces do
      for FileName in Workspace.ProjectFiles do
        Result := Result + [FileName];
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
  // Geöffnete Dateien außerhalb des Projekts zählen mit.
  for Document in FDocuments.Documents do
    Result := Result + [TDocumentUris.ToPath(Document.Uri)];
end;

function TServerComposition.CollectStatus: TServerStatus;
var
  Workspace: TShellWorkspace;
  Document: ITextDocument;
begin
  Result := Default(TServerStatus);
  Result.Units := FIndex.UnitCount;
  Result.Symbols := FIndex.SymbolCount;
  Result.MemoryBytes := AllocatedBytes;
  Result.IndexBytes := FIndex.MemoryBytes;
  Result.CompactUnits := FIndex.CompactCount;
  Result.BudgetBytes := FIndex.Budget;
  for Document in FDocuments.Documents do
    Result.DocumentBytes := Result.DocumentBytes + Length(Document.Text) * SizeOf(Char);
  TMonitor.Enter(FWorkspacesLock);
  try
    for Workspace in FWorkspaces do
      Result.Workspaces := Result.Workspaces + [Workspace.IndexStatus];
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
  Result.Requests := FStatistics.Snapshot;
end;

function TServerComposition.DelphiVersionFor(const AUri: string): string;
var
  Workspace: TShellWorkspace;
begin
  TMonitor.Enter(FWorkspacesLock);
  try
    Workspace := WorkspaceOf(TDocumentUris.ToPath(AUri));
    if (Workspace = nil) and (FWorkspaces.Count = 1) then
      Workspace := FWorkspaces[0];
    if Workspace = nil then
      Result := ''
    else
    begin
      // Tatsächlich gewählte Installation (#47), sonst die konfigurierte Version.
      Result := Workspace.DelphiVersion;
      if Result = '' then
        Result := Workspace.Configuration.Settings.DelphiVersion;
    end;
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
end;

function TServerComposition.CompletionSettingsFor(const AUri: string): TCompletionSettings;
var
  Workspace: TShellWorkspace;
begin
  TMonitor.Enter(FWorkspacesLock);
  try
    Workspace := WorkspaceOf(TDocumentUris.ToPath(AUri));
    if (Workspace = nil) and (FWorkspaces.Count = 1) then
      Workspace := FWorkspaces[0];
    if Workspace = nil then
      Result := TCompletionSettings.Default
    else
      Result := Workspace.Configuration.Settings.Completion;
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
end;

function TServerComposition.InlayHintSettingsFor(const AUri: string): TInlayHintSettings;
var
  Workspace: TShellWorkspace;
begin
  TMonitor.Enter(FWorkspacesLock);
  try
    Workspace := WorkspaceOf(TDocumentUris.ToPath(AUri));
    if (Workspace = nil) and (FWorkspaces.Count = 1) then
      Workspace := FWorkspaces[0];
    if Workspace = nil then
      Result := TInlayHintSettings.Default
    else
      Result := Workspace.Configuration.Settings.InlayHints;
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
end;

function TServerComposition.FormatStyleFor(const AUri: string): TFormatStyle;
var
  Workspace: TShellWorkspace;
begin
  TMonitor.Enter(FWorkspacesLock);
  try
    Workspace := WorkspaceOf(TDocumentUris.ToPath(AUri));
    if (Workspace = nil) and (FWorkspaces.Count = 1) then
      Workspace := FWorkspaces[0];
    if Workspace = nil then
      Result := TFormatStyle.Default
    else
      Result := Workspace.Configuration.Settings.Formatting;
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
end;

function TServerComposition.RuleContextFor(const AUri: string; out AContext: TRuleCheckContext): Boolean;
var
  Workspace: TShellWorkspace;
  FileName: string;
begin
  AContext := Default(TRuleCheckContext);
  FileName := TDocumentUris.ToPath(AUri);
  TMonitor.Enter(FWorkspacesLock);
  try
    Workspace := WorkspaceOf(FileName);
    if Workspace = nil then
      AContext.Settings := TServerSettings.Default
    else
    begin
      AContext.Settings := Workspace.Configuration.Settings;
      AContext.RelativePath := ExtractRelativePath(IncludeTrailingPathDelimiter(Workspace.Root), FileName);
      AContext.Baseline := Workspace.Baseline;
    end;
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
  // Neue Instanzen je Prüfung: Regeln dürfen so Zustand halten, ohne Threads zu teilen.
  AContext.Rules := BuiltinRules;
  Result := True;
end;

procedure TServerComposition.ProjectLoaded;
var
  Workspace: TShellWorkspace;
  Namespaces: TArray<string>;
  Namespace: string;
begin
  // Neues Projekt oder neue Installation: Der Compiler bekommt eine neue Chance (#40).
  if FCompileLock <> nil then
  begin
    TMonitor.Enter(FCompileLock);
    try
      FCompilerUnavailable := '';
    finally
      TMonitor.Exit(FCompileLock);
    end;
  end;
  // Die Features kennen eine Liste: die Namespaces aller Projekte ohne Doppelte.
  Namespaces := nil;
  TMonitor.Enter(FWorkspacesLock);
  try
    for Workspace in FWorkspaces do
      for Namespace in Workspace.Namespaces do
        if IndexText(Namespace, Namespaces) < 0 then
          Namespaces := Namespaces + [Namespace];
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
  FDefinition.Namespaces := Namespaces;
  FHover.Namespaces := Namespaces;
  FDocumentHighlights.Namespaces := Namespaces;
  FReferences.Namespaces := Namespaces;
  FRename.Namespaces := Namespaces;
  FCompletion.Namespaces := Namespaces;
  FSignatureHelp.Namespaces := Namespaces;
  FHierarchies.Namespaces := Namespaces;
  FImplementations.Namespaces := Namespaces;
  FInlayHints.Namespaces := Namespaces;
  FCodeLens.Namespaces := Namespaces;
  FSemanticTokens.Namespaces := Namespaces;
  FSyntaxDiagnostics.Refresh;
end;

procedure TServerComposition.HandleDocumentEvent(AKind: TDocumentEventKind; const ADocument: ITextDocument);
var
  Workspace: TShellWorkspace;
  OnSave: Boolean;
begin
  if FDeriveWorkspaces and (AKind = TDocumentEventKind.Opened) and StartsText('file:', ADocument.Uri) then
    DeriveWorkspace(TDocumentUris.ToPath(ADocument.Uri));
  // Nach dem Speichern einer Quelldatei kompilieren (#40), abschaltbar über compiler.onSave.
  if (AKind = TDocumentEventKind.Saved) and MatchText(ExtractFileExt(TDocumentUris.ToPath(ADocument.Uri)),
    ['.pas', '.dpr', '.dpk', '.inc']) then
  begin
    TMonitor.Enter(FWorkspacesLock);
    try
      Workspace := WorkspaceOf(TDocumentUris.ToPath(ADocument.Uri));
      OnSave := (Workspace <> nil) and Workspace.Configuration.Settings.Compiler.OnSave;
    finally
      TMonitor.Exit(FWorkspacesLock);
    end;
    if OnSave then
      StartCompile(TDocumentUris.ToPath(ADocument.Uri), False);
    Exit;
  end;
  if not IsConfigurationFileName(ExtractFileName(TDocumentUris.ToPath(ADocument.Uri))) then
    Exit;
  TMonitor.Enter(FWorkspacesLock);
  try
    Workspace := WorkspaceOf(TDocumentUris.ToPath(ADocument.Uri));
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
  // Nur der Thread der Nachrichtenschleife entfernt Ordner; Workspace bleibt gültig.
  if Workspace <> nil then
    Workspace.Configuration.DocumentEvent(AKind, ADocument)
  else
    FLooseConfiguration.DocumentEvent(AKind, ADocument);
end;

procedure TServerComposition.CompilerUnavailable(const AReason: string);
var
  First: Boolean;
begin
  TMonitor.Enter(FCompileLock);
  try
    First := FCompilerUnavailable <> AReason;
    FCompilerUnavailable := AReason;
  finally
    TMonitor.Exit(FCompileLock);
  end;
  if First then
    FLogger.Warning('Kompilieren nicht möglich: ' + AReason +
      '. Nach dem Speichern wird bis zum nächsten Laden des Projekts nicht mehr kompiliert; ' +
      'der Befehl "Projekt kompilieren" versucht es erneut.');
end;

procedure TServerComposition.StartCompile(const AFileName: string; AManual: Boolean);
var
  Workspace: TShellWorkspace;
  Request: TCompilerRequest;
  Error: string;
  Unavailable: Boolean;
begin
  // Workspace Trust (#186): Ein Compiler-Lauf kann Build-Events des Projekts ausführen.
  if FRestricted then
  begin
    if AManual then
      FLogger.Warning('Kompilieren ist in einem nicht vertrauenswürdigen Arbeitsbereich abgeschaltet');
    Exit;
  end;
  TMonitor.Enter(FCompileLock);
  try
    Unavailable := FCompilerUnavailable <> '';
  finally
    TMonitor.Exit(FCompileLock);
  end;
  if Unavailable and not AManual then
    Exit;
  TMonitor.Enter(FWorkspacesLock);
  try
    Workspace := nil;
    if AFileName <> '' then
      Workspace := WorkspaceOf(AFileName);
    if (Workspace = nil) and (FWorkspaces.Count = 1) then
      Workspace := FWorkspaces[0];
    if Workspace = nil then
      Error := 'Kein Ordner mit Projekt geöffnet'
    else if Workspace.CompilerRequest(Request, Error) then
      Error := '';
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
  if Error <> '' then
  begin
    CompilerUnavailable(Error);
    Exit;
  end;
  TMonitor.Enter(FCompileLock);
  try
    if FCompiling then
    begin
      // Der laufende Lauf startet danach den neuesten Stand.
      FPendingCompile := Request;
      FHasPendingCompile := True;
      Exit;
    end;
    FCompiling := True;
  finally
    TMonitor.Exit(FCompileLock);
  end;
  if FCompileThread <> nil then
  begin
    FCompileThread.WaitFor;
    FreeAndNil(FCompileThread);
  end;
  FCompileThread := TThread.CreateAnonymousThread(
    procedure
    begin
      CompileLoop(Request);
    end);
  FCompileThread.FreeOnTerminate := False;
  FCompileThread.Start;
end;

procedure TServerComposition.CompileLoop(const ARequest: TCompilerRequest);
var
  Request: TCompilerRequest;
  Lines: TList<string>;
  Messages: TArray<TCompilerMessage>;
  Item: TCompilerMessage;
  Counts: array[TCompilerSeverity] of Integer;
  Code, Index: Integer;
  Summary, Output: string;
begin
  Request := ARequest;
  repeat
    Lines := TList<string>.Create;
    try
      FCompileProgress.Start('Projekt kompilieren');
      try
        Code := FCompilerProcess.Run(Request,
          procedure(const ALine: string)
          begin
            Lines.Add(ALine);
          end);
        Messages := TCompilerOutputParser.Parse(Lines.ToArray, Request.WorkingDir);
        if (Code <> 0) and (Length(Messages) = 0) then
        begin
          // Abbruch ohne eine einzige Meldung: Der Compiler selbst ist nicht nutzbar,
          // z. B. ohne Lizenz für die Kommandozeile. Bisherige Meldungen bleiben stehen.
          Output := '';
          for Index := 0 to Min(Lines.Count, 3) - 1 do
            if Trim(Lines[Index]) <> '' then
              Output := Output + ' ' + Trim(Lines[Index]);
          CompilerUnavailable(Format('%s endet mit Exit-Code %d ohne Meldungen:%s',
            [Request.Executable, Code, Output]));
          FCompileProgress.Finish('Compiler nicht nutzbar');
        end
        else
        begin
          TMonitor.Enter(FCompileLock);
          try
            FCompilerUnavailable := '';
          finally
            TMonitor.Exit(FCompileLock);
          end;
          FillChar(Counts, SizeOf(Counts), 0);
          for Item in Messages do
          begin
            Inc(Counts[Item.Severity]);
            if Item.FileName = '' then
              FLogger.Warning(Format('Compiler: %s %s', [Item.Code, Item.Text]));
          end;
          FSyntaxDiagnostics.RefreshFiles(FCompilerResults.Replace(Messages));
          Summary := Format('%d Fehler, %d Warnungen, %d Hinweise',
            [Counts[TCompilerSeverity.Error] + Counts[TCompilerSeverity.Fatal], Counts[TCompilerSeverity.Warning],
            Counts[TCompilerSeverity.Hint]]);
          FLogger.Info(Format('Kompiliert mit %s (Exit-Code %d): %s', [Request.Executable, Code, Summary]));
          FCompileProgress.Finish(Summary);
        end;
      except
        on E: Exception do
        begin
          CompilerUnavailable(E.Message);
          FCompileProgress.Finish('Fehlgeschlagen');
        end;
      end;
    finally
      Lines.Free;
    end;
    TMonitor.Enter(FCompileLock);
    try
      if not FHasPendingCompile then
      begin
        FCompiling := False;
        Break;
      end;
      Request := FPendingCompile;
      FHasPendingCompile := False;
    finally
      TMonitor.Exit(FCompileLock);
    end;
  until False;
end;

procedure TServerComposition.HandleDidChangeConfiguration(const AParams: TJSONValue);
var
  Workspace: TShellWorkspace;
begin
  FEditorSettings := TLspConfiguration.EditorSettingsFromParams(AParams);
  for Workspace in FWorkspaces.ToArray do
    Workspace.Configuration.SetEditorSettings(FEditorSettings);
end;

procedure TServerComposition.HandleWatchedFiles(const AChanges: TArray<TFileChange>);
var
  Change: TFileChange;
  Sources: TArray<TFileChange>;
  Workspace: TShellWorkspace;
  Reload: TList<TShellWorkspace>;
  Updated: Integer;
begin
  Sources := nil;
  Reload := TList<TShellWorkspace>.Create;
  try
    for Change in AChanges do
      if TLspWatchedFiles.IsProjectFile(Change.FileName) then
      begin
        TMonitor.Enter(FWorkspacesLock);
        try
          Workspace := WorkspaceOf(Change.FileName);
        finally
          TMonitor.Exit(FWorkspacesLock);
        end;
        if (Workspace <> nil) and not Reload.Contains(Workspace) then
          Reload.Add(Workspace);
      end
      // .inc (#264): der Index liest die einbindenden Units neu ein.
      else if MatchText(ExtractFileExt(Change.FileName), ['.pas', '.dpr', '.inc']) then
        Sources := Sources + [Change];
    // Neu aufbauen: Suchpfade, Defines oder Units können sich geändert haben.
    for Workspace in Reload do
    begin
      FLogger.Info(Format('Projektdatei in %s geändert, Symbolindex wird neu aufgebaut', [Workspace.Root]));
      Workspace.Reload;
    end;
  finally
    Reload.Free;
  end;
  if Length(Sources) = 0 then
    Exit;
  // Jeder Ordner aktualisiert die Units, die sein Aufbau kennt.
  Updated := 0;
  for Workspace in FWorkspaces.ToArray do
    Inc(Updated, Workspace.ApplyChanges(Sources));
  FLogger.Debug(Format('%d Dateiänderungen von außen, %d Units im Index aktualisiert', [Length(Sources), Updated]));
end;

class function TServerComposition.CreateForStdio(const AOptions: TCommandLineOptions): TServerComposition;
var
  LoggerImpl: TLogger;
  Logger: ILogger;
  Transport: IJsonRpcTransport;
  Warning: string;
  TraceName: string;
begin
  // Stacktraces für das Absturzprotokoll (Exception.StackTrace).
  TStackTrace.Install;
  LoggerImpl := TLogger.Create;
  Logger := LoggerImpl;
  LoggerImpl.AddSink(TDebugOutputLogSink.Create, TLogLevel.Debug);
  // stderr zeigt VS Code ebenfalls im Ausgabefenster; dort nur Fehler, um
  // Doppelungen mit window/logMessage zu vermeiden.
  LoggerImpl.AddSink(TStreamLogSink.Create(TStdStreams.CreateError, True), TLogLevel.Error);
  if AOptions.LogFile <> '' then
    try
      LoggerImpl.AddSink(TStreamLogSink.CreateForFile(AOptions.LogFile, IntToStr(TParentWatcher.CurrentProcessId)),
        AOptions.LogLevel);
    except
      on E: Exception do
        Logger.Error(Format('Logdatei "%s" kann nicht geöffnet werden: %s', [AOptions.LogFile, E.Message]));
    end;

  // Ab hier erreichen versehentliche Ausgaben (Writeln, Bibliotheken) nur noch stderr.
  Transport := TJsonRpcStreamTransport.Create(TStdStreams.CreateInput, TStdStreams.ReserveOutputForProtocol, True);
  if AOptions.TraceFile <> '' then
    try
      Transport := TJsonRpcTracingTransport.Create(Transport,
        CreateTraceStream(AOptions.TraceFile, IntToStr(TParentWatcher.CurrentProcessId), TraceName), True);
      if not SameText(TraceName, AOptions.TraceFile) then
        Logger.Info(Format('Mitschnitt "%s" ist belegt, schreibe nach "%s"', [AOptions.TraceFile, TraceName]));
    except
      on E: Exception do
        Logger.Error(Format('Mitschnitt "%s" kann nicht angelegt werden: %s', [AOptions.TraceFile, E.Message]));
    end;
  LoggerImpl.AddSink(TLspLogMessageSink.Create(Transport), AOptions.LogLevel);

  for Warning in AOptions.Warnings do
    Logger.Warning(Warning);

  Result := TServerComposition.Create(Transport, Logger);
  Result.FRestricted := AOptions.Restricted;
  Result.FClientProcessId := AOptions.ClientProcessId;
  if AOptions.Restricted then
    Logger.Info('Eingeschränkter Modus (Arbeitsbereich nicht vertrauenswürdig): der Compiler wird nicht gestartet');
end;

procedure TServerComposition.WatchParent(const AInitializeParams: TJSONObject);
var
  ProcessId: Cardinal;
  Value: TJSONValue;
begin
  ProcessId := FClientProcessId;
  if AInitializeParams <> nil then
  begin
    Value := AInitializeParams.GetValue('processId');
    if Value is TJSONNumber then
      ProcessId := Cardinal(TJSONNumber(Value).AsInt64);
  end;
  if (ProcessId = 0) or (FParentWatcher <> nil) then
    Exit;
  FParentWatcher := TParentWatcher.Create(ProcessId,
    procedure
    begin
      FLogger.Warning(Format('Editor-Prozess %d ist beendet; der Server beendet sich', [ProcessId]));
      FConnection.Stop;
    end);
end;

function TServerComposition.DescribeFailure(const AError: Exception): string;
begin
  Result := Format('%s: %s%sLetzte Nachricht: %s', [AError.ClassName, AError.Message, sLineBreak,
    FDispatcher.LastMessage]);
  if AError.StackTrace <> '' then
    Result := Result + sLineBreak + AError.StackTrace;
end;

class function TServerComposition.BuildCapabilities: TJSONObject;
var
  Commands: TJSONArray;
begin
  // Die Features tragen ihre Capabilities hier ein, sobald sie umgesetzt sind.
  Result := TJSONObject.Create;
  Result.AddPair('textDocumentSync', TLspTextDocumentSync.Capability);
  Result.AddPair('documentSymbolProvider', TJSONBool.Create(True));
  Result.AddPair('foldingRangeProvider', TJSONBool.Create(True));
  Result.AddPair('linkedEditingRangeProvider', TJSONBool.Create(True));
  Result.AddPair('documentFormattingProvider', TJSONBool.Create(True));
  // Nur für den Schnellbefehl /uses (#254); Blockabschluss (#179) übernimmt die IDE.
  Result.AddPair('documentOnTypeFormattingProvider', TLspFormatting.OnTypeCapability);
  Result.AddPair('documentRangeFormattingProvider', TJSONBool.Create(True));
  Result.AddPair('selectionRangeProvider', TJSONBool.Create(True));
  Result.AddPair('definitionProvider', TJSONBool.Create(True));
  Result.AddPair('declarationProvider', TJSONBool.Create(True));
  Result.AddPair('typeDefinitionProvider', TJSONBool.Create(True));
  Result.AddPair('hoverProvider', TJSONBool.Create(True));
  Result.AddPair('workspaceSymbolProvider', TJSONBool.Create(True));
  Result.AddPair('documentHighlightProvider', TJSONBool.Create(True));
  Result.AddPair('referencesProvider', TJSONBool.Create(True));
  Result.AddPair('renameProvider', TLspRename.Capability);
  Result.AddPair('completionProvider', TLspCompletion.Capability);
  Result.AddPair('signatureHelpProvider', TLspSignatureHelp.Capability);
  Result.AddPair('typeHierarchyProvider', TJSONBool.Create(True));
  Result.AddPair('callHierarchyProvider', TJSONBool.Create(True));
  Result.AddPair('implementationProvider', TJSONBool.Create(True));
  Result.AddPair('inlayHintProvider', TJSONBool.Create(True));
  Result.AddPair('codeLensProvider', TLspCodeLens.Capability);
  Result.AddPair('semanticTokensProvider', TLspSemanticTokens.Capability);
  Result.AddPair('codeActionProvider', TLspCodeActions.Capability);
  Result.AddPair('documentLinkProvider', TLspDocumentLinks.Capability);
  Result.AddPair('colorProvider', TJSONBool.Create(True));
  Commands := TJSONArray.Create;
  Commands.Add(StatusCommand);
  Commands.Add(CompileCommand);
  Commands.Add(SelectBuildCommand);
  Commands.Add(RebuildIndexCommand);
  Result.AddPair('executeCommandProvider', TJSONObject.Create(TJSONPair.Create('commands', Commands)));
  Result.AddPair('workspace', TLspWorkspaceFolders.Capability);
end;

function TServerComposition.Run: Integer;
begin
  FLogger.Info(Format('%s %s gestartet', [TProductVersion.Name, TProductVersion.Version]));
  try
    FConnection.Run;
    Result := FLifecycle.ExitCode;
  except
    on E: Exception do
    begin
      FLogger.Error('Server abgebrochen: ' + DescribeFailure(E));
      Result := 1;
    end;
  end;
  FLogger.Info(Format('Beendet mit Exit-Code %d', [Result]));
end;

end.
