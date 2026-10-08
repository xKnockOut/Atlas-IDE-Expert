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
  BDLsp.Common.Dfm.FormInheritance,
  BDLsp.Common.Logging.Contract,
  BDLsp.Common.JsonRpc.Contract,
  BDLsp.Common.JsonRpc.Dispatcher,
  BDLsp.Common.JsonRpc.Connection,
  BDLsp.Common.JsonRpc.Watchdog,
  BDLsp.Common.Lsp.Lifecycle,
  BDLsp.Common.Lsp.TextDocumentSync,
  BDLsp.Common.Lsp.SyntaxDiagnostics,
  BDLsp.Common.Lsp.PullDiagnostics,
  BDLsp.Common.Lsp.DocumentSymbols,
  BDLsp.Common.Lsp.FoldingRanges,
  BDLsp.Common.Lsp.LinkedEditing,
  BDLsp.Common.Lsp.Formatting,
  BDLsp.Common.Lsp.SelectionRanges,
  BDLsp.Common.Lsp.Definition,
  BDLsp.Common.Lsp.Hover,
  BDLsp.Common.Lsp.WorkspaceSymbols,
  BDLsp.Common.Editing.Bookmarks,
  BDLsp.Common.Lsp.DocumentHighlights,
  BDLsp.Common.Lsp.CodeActions,
  BDLsp.Common.Lsp.DocumentLinks,
  BDLsp.Common.Lsp.Colors,
  BDLsp.Common.Lsp.Commands,
  BDLsp.Common.Lsp.References,
  BDLsp.Common.Lsp.Rename,
  BDLsp.Common.Lsp.FileOperations,
  BDLsp.Common.Lsp.Completion,
  BDLsp.Common.Pascal.LanguageFeatures,
  BDLsp.Common.Lsp.SignatureHelp,
  BDLsp.Common.Lsp.Hierarchies,
  BDLsp.Common.Lsp.Implementations,
  BDLsp.Common.Lsp.InlayHints,
  BDLsp.Common.Lsp.CodeLens,
  BDLsp.Common.Lsp.SemanticTokens,
  BDLsp.Common.Lsp.Status,
  BDLsp.Common.Lsp.QualifiedNames,
  BDLsp.Common.Lsp.StringLiteralCommands,
  BDLsp.Common.Editing.StringLiterals,
  BDLsp.Common.JsonRpc.Statistics,
  BDLsp.Common.Lsp.WatchedFiles,
  BDLsp.Common.Lsp.WorkspaceFolders,
  BDLsp.Common.Lsp.Configuration,
  BDLsp.Common.Documents.Contract,
  BDLsp.Common.Configuration.Contract,
  BDLsp.Common.Index.Contract,
  BDLsp.Common.Compiler.Contract,
  BDLsp.Common.Compiler.Results,
  BDLsp.Common.Lsp.WorkDoneProgress,
  Shell.CommandLine,
  BDLsp.Windows.Process.ParentWatcher,
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
    /// <summary>Lesezeichen "// @bookmark Name" für die Symbolsuche (#306).</summary>
    FBookmarks: TBookmarkStore;
    function CollectBookmarks: TArray<TBookmarkHit>;
    FDocumentHighlights: TLspDocumentHighlights;
    FReferences: TLspReferences;
    FRename: TLspRename;
    FFileOperations: TLspFileOperations;
    /// <summary>Nicht vertrauenswürdiger Arbeitsbereich (#186): kein Compiler-Lauf.</summary>
    FRestricted: Boolean;
    /// <summary>Prozessnummer des Editors aus der Befehlszeile (#283); 0 = keine.</summary>
    FClientProcessId: Cardinal;
    FParentWatcher: TParentWatcher;
    /// <summary>Überwacht den Editor-Prozess aus initialize oder der Befehlszeile.</summary>
    procedure WatchParent(const AInitializeParams: TJSONObject);
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
    /// <summary>Für delphi-lsp.json außerhalb aller Ordner: nur Fehlermeldungen.</summary>
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
    procedure AddWorkspace(const AFolder: TWorkspaceFolder);
    procedure RemoveWorkspace(const AFolder: TWorkspaceFolder);
    /// <summary>Innerster Ordner zur Datei oder nil. Aufrufer hält FWorkspacesLock.</summary>
    function WorkspaceOf(const AFileName: string): TShellWorkspace;
    function EnsureUnit(const AUnitName: string): Boolean;
    /// <summary>Text einer Quelldatei; geöffnete Dokumente haben Vorrang vor der Platte.</summary>
    function ReadSourceText(const AFileName: string; out AText: string): Boolean;
    /// <summary>Formulardatei mit der Kette ihrer Vorfahr-Formulare (#115). Der Aufrufer gibt sie frei.</summary>
    function NewFormInheritance(const AUri, AText: string): TFormInheritance;
    /// <summary>Projektdateien aller Ordner und geöffnete Dokumente, für Referenzen und Umbenennen.</summary>
    function ProjectSourceFiles: TArray<string>;
    /// <summary>.dproj und Hauptdateien (.dpr, .dpk) aller geladenen Projekte (#181).</summary>
    function ProjectDefinitionFiles: TArray<string>;
    /// <summary>Inhalt des Status-Befehls (#28).</summary>
    function CollectStatus: TServerStatus;
    function DefinesFor(const AUri: string; out ADefines: TArray<string>): Boolean;
    function DelphiVersionFor(const AUri: string): string;
    /// <summary>Schnellbefehle (#293): False = aus; ADisabled samt "uses" bei usesCommand = false.</summary>
    function SlashCommandsFor(const AUri: string; out ADisabled: TArray<string>): Boolean;
    function InlayHintSettingsFor(const AUri: string): TInlayHintSettings;
    function CompletionSettingsFor(const AUri: string): TCompletionSettings;
    /// <summary>"stringLiteral" für AUri; AMultiline nach Stil und Delphi-Version (#312).</summary>
    function StringLiteralFor(const AUri: string; out AMultiline: Boolean): TStringLiteralSettings;
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
    CompileCommand = 'betterdelphilsp.compile';
    SelectBuildCommand = 'betterdelphilsp.selectBuild';
    RebuildIndexCommand = 'betterdelphilsp.rebuildIndex';
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

uses
  System.IOUtils,
  System.Math,
  System.StrUtils,
  BDLsp.Common.Product.Version,
  BDLsp.Common.Logging.Providers.Logger,
  BDLsp.Common.Logging.Providers.StreamSink,
  BDLsp.Common.JsonRpc.StreamTransport,
  BDLsp.Common.JsonRpc.TracingTransport,
  BDLsp.Common.Lsp.Adapters.LogMessageSink,
  BDLsp.Common.Documents.Providers.DocumentStore,
  BDLsp.Common.Documents.FileEncoding,
  BDLsp.Common.Documents.Uris,
  Shell.SlashHost,
  BDLsp.Common.Rules.Engine,
  BDLsp.Common.Rules.Builtin.General,
  BDLsp.Common.JsonRpc.Messages,
  BDLsp.Common.Lsp.FormEvents,
  BDLsp.Common.Lsp.FormFiles,
  BDLsp.Common.Dfm.FormModel,
  BDLsp.Common.Dfm.BinaryForm,
  BDLsp.Common.Dfm.FormFiles,
  BDLsp.Common.Dfm.ImagePreview,
  BDLsp.Common.Lsp.FormSymbols,
  BDLsp.Common.Editing.CodeActions,
  BDLsp.Common.Rules.Contract,
  BDLsp.Common.Index.SymbolIndex,
  BDLsp.Common.Editing.UsesActions,
  BDLsp.Common.Rules.Builtin,
  BDLsp.Common.Compiler.OutputParser,
  BDLsp.Windows.Compiler.Adapters.ProcessRunner,
  BDLsp.Windows.Console.StdStreams,
  BDLsp.Windows.Documents.PathCanonicalizer,
  BDLsp.Windows.Diagnostics.Adapters.DebugOutputSink,
  BDLsp.Windows.Diagnostics.StackTrace,
  BDLsp.Common.Logging.Providers.RotatingFileStream,
  BDLsp.Windows.Editing.SystemColors,
  BDLsp.Common.Projects.Contract;

function StringsToJson(const AValues: TArray<string>): TJSONArray;
var
  Value: string;
begin
  Result := TJSONArray.Create;
  for Value in AValues do
    Result.Add(Value);
end;

function CreateTraceStream(const AFileName, AFallbackTag: string): TStream;
var
  Directory: string;
begin
  Directory := TPath.GetDirectoryName(TPath.GetFullPath(AFileName));
  if Directory <> '' then
    ForceDirectories(Directory);
  // Rotiert bei Überlänge; ist die Datei gesperrt, wird eine eigene mit Prozessnummer angelegt (#283).
  Result := TRotatingFileStream.Create(AFileName, False, AFallbackTag);
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
  FCompileProgress := TLspWorkDoneProgress.Create(FTransport, 'bdlsp-compile');
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
  FFormatting.BlockKindsFor :=
    function(const AUri: string): TBlockKinds
    var
      Workspace: TShellWorkspace;
    begin
      TMonitor.Enter(FWorkspacesLock);
      try
        Workspace := WorkspaceOf(TDocumentUris.ToPath(AUri));
        if (Workspace = nil) and (FWorkspaces.Count = 1) then
          Workspace := FWorkspaces[0];
        if Workspace = nil then
          Result := TServerSettings.Default.CompleteBlocks
        else
          Result := Workspace.Configuration.Settings.CompleteBlocks;
      finally
        TMonitor.Exit(FWorkspacesLock);
      end;
    end;
  FFormatting.SlashCommandsFor := SlashCommandsFor;
  FFormatting.DelphiVersionFor := DelphiVersionFor;
  FFormatting.SlashHost := TShellSlashHost.Create(
    function(const AUri: string): TShellWorkspace
    begin
      TMonitor.Enter(FWorkspacesLock);
      try
        Result := WorkspaceOf(TDocumentUris.ToPath(AUri));
        if (Result = nil) and (FWorkspaces.Count = 1) then
          Result := FWorkspaces[0];
      finally
        TMonitor.Exit(FWorkspacesLock);
      end;
    end,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := ReadSourceText(AFileName, AText);
    end,
    function(const AUri: string): string
    var
      Workspace: TShellWorkspace;
      Settings: TServerSettings;
    begin
      TMonitor.Enter(FWorkspacesLock);
      try
        Workspace := WorkspaceOf(TDocumentUris.ToPath(AUri));
        if (Workspace = nil) and (FWorkspaces.Count = 1) then
          Workspace := FWorkspaces[0];
        if Workspace = nil then
          Exit('');
        Settings := Workspace.Configuration.Settings;
      finally
        TMonitor.Exit(FWorkspacesLock);
      end;
      // Eigene Vorlage der Schnellbefehle, sonst die der Regel file-header (#56).
      Result := Settings.SlashHeaderTemplate;
      if Result = '' then
        Result := TFileHeaderRule.Template(TRuleEngine.RuleOptions('file-header', Settings));
    end, FTransport, FLogger);
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
  FFormatting.Index := FIndex;
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
  // Bilder in Binärdaten (#271), sonst geerbte Formulare (#115): Wert im Vorfahr-Formular.
  FHover.FormHover :=
    function(const AUri, AText: string; const APosition: TTextPosition): string
    var
      Chain: TFormInheritance;
    begin
      Result := TDfmImagePreview.HoverAt(AText, APosition);
      if Result <> '' then
        Exit;
      Chain := NewFormInheritance(AUri, AText);
      try
        Result := Chain.HoverAt(APosition);
      finally
        Chain.Free;
      end;
      // Sonst Property, Klasse, Wert oder Ereignis über den Index (#308).
      if Result = '' then
        Result := TFormSymbols.Hover(AText, TDocumentUris.ToPath(AUri), APosition, FIndex,
          function(const AFileName: string; out AContent: string): Boolean
          begin
            Result := ReadSourceText(AFileName, AContent);
          end);
    end;
  FHover.Attach(FDispatcher);
  FWorkspaceSymbols := TLspWorkspaceSymbols.Create(FIndex);
  FBookmarks := TBookmarkStore.Create;
  FWorkspaceSymbols.BookmarksFor := CollectBookmarks;
  FWorkspaceSymbols.Attach(FDispatcher);
  FDocumentHighlights := TLspDocumentHighlights.Create(FDocuments, FIndex,
    function(const AUnitName: string): Boolean
    begin
      Result := EnsureUnit(AUnitName);
    end);
  FDocumentHighlights.SettingsFor :=
    function(const AUri: string): THighlightSettings
    var
      Workspace: TShellWorkspace;
    begin
      TMonitor.Enter(FWorkspacesLock);
      try
        Workspace := WorkspaceOf(TDocumentUris.ToPath(AUri));
        if (Workspace = nil) and (FWorkspaces.Count = 1) then
          Workspace := FWorkspaces[0];
        if Workspace <> nil then
          Result := Workspace.Configuration.Settings.Highlight
        else
          Result := THighlightSettings.Default;
      finally
        TMonitor.Exit(FWorkspacesLock);
      end;
    end;
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
  FFileOperations := TLspFileOperations.Create(
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := ReadSourceText(AFileName, AText);
    end,
    ProjectSourceFiles, ProjectDefinitionFiles,
    procedure(AMessage: TJSONObject)
    begin
      try
        FTransport.WriteMessage(AMessage);
      finally
        AMessage.Free;
      end;
    end);
  FFileOperations.Attach(FDispatcher);
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
  FCompletion.SlashCommandsFor := SlashCommandsFor;
  // Postfix-Vorlagen (#188): for var nur, wenn die Sprachversion Inline-Variablen kennt.
  FCompletion.PostfixFor :=
    function(const AUri: string): TPostfixOptions
    begin
      Result := TPostfixOptions.Default;
      Result.InlineVar := TLanguageFeatures.IsAvailable(TLanguageFeature.InlineVariable, DelphiVersionFor(AUri));
    end;
  // Ereignis-Handler in .dfm/.fmx (#111); die Unit liegt neben der Formulardatei.
  FCompletion.FormItems :=
    function(const AUri, AText: string; const APosition: TTextPosition; out AItems: TCompletionItems): Boolean
    var
      FormFile, UnitText: string;
    begin
      FormFile := TDocumentUris.ToPath(AUri);
      if not ReadSourceText(TFormFiles.UnitFile(FormFile), UnitText) then
        UnitText := '';
      Result := TFormEvents.Items(FormFile, AText, UnitText, APosition, FIndex,
        function(const AFileName: string; out AFileText: string): Boolean
        begin
          Result := ReadSourceText(AFileName, AFileText);
        end, AItems);
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
  FCodeActions.FormActions :=
    function(const AUri, AText: string; const ARange: TTextRange): TArray<TCodeAction>
    var
      Chain: TFormInheritance;
      Action: TCodeAction;
      Edit: TRuleEdit;
    begin
      Result := nil;
      // Binär gespeichert (#122): Umwandeln in Text.
      if TFormModel.IsBinary(AText) then
      begin
        Action := Default(TCodeAction);
        Action.Title := 'Formular in Text umwandeln';
        Action.Kind := QuickFixKind;
        Action.IsPreferred := True;
        Action.Command := TLspFormFiles.ConvertCommand;
        Action.CommandArguments := [AUri];
        Result := [Action];
        Exit;
      end;
      Chain := NewFormInheritance(AUri, AText);
      try
        Action := Default(TCodeAction);
        if Chain.ResetAt(ARange.StartPos, Edit, Action.Title) then
        begin
          Action.Kind := QuickFixKind;
          Action.Edits := [Edit];
          Result := [Action];
        end;
      finally
        Chain.Free;
      end;
    end;
  FCodeActions.StringLiteralFor := StringLiteralFor;
  FCodeActions.MemberOrderFor :=
    function(const AUri: string): TMemberOrderSettings
    var
      Workspace: TShellWorkspace;
    begin
      TMonitor.Enter(FWorkspacesLock);
      try
        Workspace := WorkspaceOf(TDocumentUris.ToPath(AUri));
        if (Workspace = nil) and (FWorkspaces.Count = 1) then
          Workspace := FWorkspaces[0];
        if Workspace = nil then
          Result := TMemberOrderSettings.Default
        else
          Result := Workspace.Configuration.Settings.MemberOrder;
      finally
        TMonitor.Exit(FWorkspacesLock);
      end;
    end;
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
  FCommands.Register(TLspFormFiles.ConvertCommand,
    function(const AArguments: TJSONArray): TJSONValue
    var
      Files: TArray<string>;
      FileName, Form, Backup, Extension: string;
      Converted, Backups: Integer;
    begin
      // Mit URI eine Datei, sonst alle Formulare neben den Projekt-Units.
      Files := nil;
      if (AArguments <> nil) and (AArguments.Count > 0) and (AArguments.Items[0] is TJSONString) then
        Files := [TDocumentUris.ToPath(AArguments.Items[0].Value)]
      else
        for FileName in ProjectSourceFiles do
          for Extension in TArray<string>.Create('.dfm', '.fmx') do
            if FileExists(ChangeFileExt(FileName, Extension)) then
              Files := Files + [ChangeFileExt(FileName, Extension)];
      Converted := 0;
      Backups := 0;
      for Form in Files do
        try
          if TDfmBinary.ConvertFile(Form, Backup) then
          begin
            Inc(Converted);
            if Backup <> '' then
              Inc(Backups);
          end;
        except
          on E: Exception do
            FLogger.Warning(Format('%s nicht umgewandelt: %s', [Form, E.Message]));
        end;
      FLogger.Info(Format('%d binäre Formulare in Text umgewandelt, %d Sicherungskopien (.bak)',
        [Converted, Backups]));
      Result := TJSONString.Create(Format('%d Formulare umgewandelt', [Converted]));
    end);
  FCommands.Register(TFormEvents.CreateCommand,
    function(const AArguments: TJSONArray): TJSONValue
    var
      Params, Request: TJSONObject;
    begin
      Params := TFormEvents.ApplyEditParams(AArguments,
        function(const AFileName: string; out AText: string): Boolean
        begin
          Result := ReadSourceText(AFileName, AText);
        end);
      if Params <> nil then
      begin
        // Die Antwort des Clients wertet der Dispatcher nicht aus; die id muss nur eindeutig sein.
        Request := TJsonRpcMessages.Notification(TLspFileOperations.ApplyEditMethod, Params);
        Request.AddPair('id', 'bdlsp-event-' + IntToStr(TThread.GetTickCount64));
        try
          FTransport.WriteMessage(Request);
        finally
          Request.Free;
        end;
      end;
      Result := TJSONNull.Create;
    end);
  FCommands.Register(TQualifiedNames.Command,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := TQualifiedNames.Execute(FDocuments, FIndex,
        function(const AUnitName: string): Boolean
        begin
          Result := EnsureUnit(AUnitName);
        end, FDefinition.Namespaces, AArguments);
    end);
  FCommands.Register(TStringLiteralCommands.PlainTextCommand,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := TStringLiteralCommands.ExecutePlainText(FDocuments, AArguments);
    end);
  FCommands.Register(TStringLiteralCommands.ToLiteralCommand,
    function(const AArguments: TJSONArray): TJSONValue
    var
      Settings: TStringLiteralSettings;
      Multiline: Boolean;
    begin
      Settings := TStringLiteralSettings.Default;
      Multiline := False;
      if (AArguments <> nil) and (AArguments.Count > 0) then
        Settings := StringLiteralFor(AArguments.Items[0].Value, Multiline);
      Result := TStringLiteralCommands.ExecuteToLiteral(FDocuments, Settings, Multiline, AArguments);
    end);
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
      Folder: TWorkspaceFolder;
    begin
      WatchParent(FLifecycle.InitializeParams);
      for Folder in TLspWorkspaceFolders.FromInitialize(FLifecycle.InitializeParams) do
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
  FBookmarks.Free;
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
  FFileOperations.Free;
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
    Format('bdlsp-index-%d', [FWorkspaceCounter]));
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
  GetMemoryManagerState(State);
  Result := Int64(State.TotalAllocatedMediumBlockSize) + Int64(State.TotalAllocatedLargeBlockSize);
  for I := Low(State.SmallBlockTypeStates) to High(State.SmallBlockTypeStates) do
    Inc(Result, Int64(State.SmallBlockTypeStates[I].AllocatedBlockCount) *
      State.SmallBlockTypeStates[I].UseableBlockSize);
end;

function TServerComposition.NewFormInheritance(const AUri, AText: string): TFormInheritance;
var
  ReadText: TFunc<string, string>;
begin
  ReadText :=
    function(AFileName: string): string
    begin
      if not ReadSourceText(AFileName, Result) then
        Result := '';
    end;
  Result := TFormInheritance.Create(TDocumentUris.ToPath(AUri), AText, TFormInheritance.UnitAncestorOf(ReadText),
    TFormInheritance.IndexResolver(FIndex, ReadText));
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

function TServerComposition.CollectBookmarks: TArray<TBookmarkHit>;
var
  Files: TArray<string>;
  FileName: string;
  Document: ITextDocument;
  Stamp: Int64;
begin
  Files := ProjectSourceFiles;
  for FileName in Files do
  begin
    // Geöffnete Dateien nach Version (negativ), sonst nach Änderungszeit der Datei.
    if FDocuments.TryGet(TDocumentUris.FromPath(FileName), Document) then
      Stamp := -1 - Document.Version
    else if FileExists(FileName) then
      Stamp := Trunc(TFile.GetLastWriteTimeUtc(FileName) * MSecsPerDay)
    else
      Stamp := 0;
    FBookmarks.Update(FileName, Stamp, ReadSourceText);
  end;
  FBookmarks.Retain(Files);
  Result := FBookmarks.All;
end;

function TServerComposition.ProjectDefinitionFiles: TArray<string>;
var
  Workspace: TShellWorkspace;
  Info: TProjectInfo;
begin
  Result := nil;
  TMonitor.Enter(FWorkspacesLock);
  try
    for Workspace in FWorkspaces do
      if Workspace.Project(Info) then
      begin
        Result := Result + [Info.FileName];
        if Info.MainSource <> '' then
          Result := Result + [Info.MainSource];
      end;
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
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

function TServerComposition.SlashCommandsFor(const AUri: string; out ADisabled: TArray<string>): Boolean;
var
  Workspace: TShellWorkspace;
begin
  ADisabled := nil;
  TMonitor.Enter(FWorkspacesLock);
  try
    Workspace := WorkspaceOf(TDocumentUris.ToPath(AUri));
    if (Workspace = nil) and (FWorkspaces.Count = 1) then
      Workspace := FWorkspaces[0];
    if Workspace = nil then
      Exit(True);
    Result := Workspace.Configuration.Settings.SlashCommands;
    ADisabled := Workspace.Configuration.Settings.SlashCommandsDisabled;
    // usesCommand bleibt als Alias erhalten (#254).
    if not Workspace.Configuration.Settings.UsesCommand then
      ADisabled := ADisabled + ['uses'];
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
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

function TServerComposition.StringLiteralFor(const AUri: string; out AMultiline: Boolean): TStringLiteralSettings;
var
  Workspace: TShellWorkspace;
begin
  TMonitor.Enter(FWorkspacesLock);
  try
    Workspace := WorkspaceOf(TDocumentUris.ToPath(AUri));
    if (Workspace = nil) and (FWorkspaces.Count = 1) then
      Workspace := FWorkspaces[0];
    if Workspace = nil then
      Result := TStringLiteralSettings.Default
    else
      Result := Workspace.Configuration.Settings.StringLiteral;
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
  AMultiline := TStringLiterals.UseMultiline(Result.Style, DelphiVersionFor(AUri));
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
  FileName, Folder: string;
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
  AContext.Index := FIndex;
  // Formulardatei neben der Unit für den Abgleich von Feldern und Objekten (#123).
  if SameText(ExtractFileExt(FileName), '.pas') and
    not ReadSourceText(ChangeFileExt(FileName, '.dfm'), AContext.FormText) and
    not ReadSourceText(ChangeFileExt(FileName, '.fmx'), AContext.FormText) then
    AContext.FormText := '';
  // Ressourcen neben der Unit, z. B. die .dcr mit den Palettensymbolen (#114).
  Folder := ExtractFilePath(FileName);
  AContext.ReadFile :=
    function(const AName: string; out AData: TBytes): Boolean
    begin
      Result := TFile.Exists(TPath.Combine(Folder, AName));
      if Result then
      try
        AData := TFile.ReadAllBytes(TPath.Combine(Folder, AName));
      except
        on EInOutError do
          Result := False;
        on EFileStreamError do
          Result := False;
      end;
    end;
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
  if not SameText(ExtractFileName(TDocumentUris.ToPath(ADocument.Uri)), ConfigurationFileName) then
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
      Transport := TJsonRpcTracingTransport.Create(Transport, CreateTraceStream(AOptions.TraceFile, IntToStr(TParentWatcher.CurrentProcessId)), True);
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
  Workspace: TJSONObject;
begin
  // Die Features tragen ihre Capabilities hier ein, sobald sie umgesetzt sind.
  Result := TJSONObject.Create;
  Result.AddPair('textDocumentSync', TLspTextDocumentSync.Capability);
  Result.AddPair('documentSymbolProvider', TJSONBool.Create(True));
  Result.AddPair('foldingRangeProvider', TJSONBool.Create(True));
  Result.AddPair('linkedEditingRangeProvider', TJSONBool.Create(True));
  Result.AddPair('documentFormattingProvider', TJSONBool.Create(True));
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
  Commands.Add(TQualifiedNames.Command);
  Commands.Add(TStringLiteralCommands.PlainTextCommand);
  Commands.Add(TStringLiteralCommands.ToLiteralCommand);
  Result.AddPair('executeCommandProvider', TJSONObject.Create(TJSONPair.Create('commands', Commands)));
  Workspace := TLspWorkspaceFolders.Capability;
  Workspace.AddPair('fileOperations', TLspFileOperations.Capability);
  Result.AddPair('workspace', Workspace);
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
