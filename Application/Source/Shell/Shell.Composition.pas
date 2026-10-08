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
  System.JSON,
  System.Generics.Collections,
  BDLsp.Common.Logging.Contract,
  BDLsp.Common.JsonRpc.Contract,
  BDLsp.Common.JsonRpc.Dispatcher,
  BDLsp.Common.JsonRpc.Connection,
  BDLsp.Common.JsonRpc.Watchdog,
  BDLsp.Common.Lsp.Lifecycle,
  BDLsp.Common.Lsp.TextDocumentSync,
  BDLsp.Common.Lsp.SyntaxDiagnostics,
  BDLsp.Common.Lsp.DocumentSymbols,
  BDLsp.Common.Lsp.FoldingRanges,
  BDLsp.Common.Lsp.LinkedEditing,
  BDLsp.Common.Lsp.SelectionRanges,
  BDLsp.Common.Lsp.Definition,
  BDLsp.Common.Lsp.Hover,
  BDLsp.Common.Lsp.WorkspaceSymbols,
  BDLsp.Common.Lsp.DocumentHighlights,
  BDLsp.Common.Lsp.CodeActions,
  BDLsp.Common.Lsp.DocumentLinks,
  BDLsp.Common.Lsp.Colors,
  BDLsp.Common.Lsp.Commands,
  BDLsp.Common.Lsp.References,
  BDLsp.Common.Lsp.Rename,
  BDLsp.Common.Lsp.Completion,
  BDLsp.Common.Lsp.SignatureHelp,
  BDLsp.Common.Lsp.Hierarchies,
  BDLsp.Common.Lsp.Implementations,
  BDLsp.Common.Lsp.InlayHints,
  BDLsp.Common.Lsp.CodeLens,
  BDLsp.Common.Lsp.SemanticTokens,
  BDLsp.Common.Lsp.Status,
  BDLsp.Common.JsonRpc.Statistics,
  BDLsp.Common.Lsp.WatchedFiles,
  BDLsp.Common.Lsp.WorkspaceFolders,
  BDLsp.Common.Lsp.Configuration,
  BDLsp.Common.Documents.Contract,
  BDLsp.Common.Configuration.Contract,
  BDLsp.Common.Index.Contract,
  Shell.CommandLine,
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
    FDocumentSymbols: TLspDocumentSymbols;
    FFoldingRanges: TLspFoldingRanges;
    FLinkedEditing: TLspLinkedEditing;
    FSelectionRanges: TLspSelectionRanges;
    FDefinition: TLspDefinition;
    FHover: TLspHover;
    FWorkspaceSymbols: TLspWorkspaceSymbols;
    FDocumentHighlights: TLspDocumentHighlights;
    FReferences: TLspReferences;
    FRename: TLspRename;
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
    procedure AddWorkspace(const AFolder: TWorkspaceFolder);
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
    function RuleContextFor(const AUri: string; out AContext: TRuleCheckContext): Boolean;
    /// <summary>Namespaces aller Projekte an die Features weitergeben, Diagnosen neu prüfen.</summary>
    procedure ProjectLoaded;
    procedure HandleDocumentEvent(AKind: TDocumentEventKind; const ADocument: ITextDocument);
    procedure HandleDidChangeConfiguration(const AParams: TJSONValue);
    /// <summary>Dateiänderungen von außen: Projektdateien laden das Projekt neu, Quelltexte aktualisieren den Index.</summary>
    procedure HandleWatchedFiles(const AChanges: TArray<TFileChange>);
    class function BuildCapabilities: TJSONObject; static;
    /// <summary>Fehlerbeschreibung mit letzter Nachricht und Stacktrace für das Log.</summary>
    function DescribeFailure(const AError: Exception): string;
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
    property Logger: ILogger read FLogger;
    /// <summary>Geöffnete Dokumente, für Features, die Dateien auswerten.</summary>
    property Documents: IDocumentStore read FDocuments;
    property Index: ISymbolIndex read FIndex;
  end;

implementation

uses
  System.Classes,
  System.IOUtils,
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
  BDLsp.Common.Index.SymbolIndex,
  BDLsp.Common.Rules.Builtin,
  BDLsp.Windows.Console.StdStreams,
  BDLsp.Windows.Documents.PathCanonicalizer,
  BDLsp.Windows.Diagnostics.Adapters.DebugOutputSink,
  BDLsp.Windows.Diagnostics.StackTrace,
  BDLsp.Windows.Editing.SystemColors;

function CreateTraceStream(const AFileName: string): TStream;
var
  Directory: string;
begin
  Directory := TPath.GetDirectoryName(TPath.GetFullPath(AFileName));
  if Directory <> '' then
    ForceDirectories(Directory);
  Result := TFileStream.Create(AFileName, fmCreate or fmShareDenyWrite);
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
    end);
  FLifecycle.Attach(FDispatcher);
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
  FSyntaxDiagnostics.Attach;
  FDocumentSymbols := TLspDocumentSymbols.Create(FDocuments);
  FDocumentSymbols.Attach(FDispatcher);
  FFoldingRanges := TLspFoldingRanges.Create(FDocuments);
  FFoldingRanges.Attach(FDispatcher);
  FLinkedEditing := TLspLinkedEditing.Create(FDocuments);
  FLinkedEditing.Attach(FDispatcher);
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
  FSyntaxDiagnostics.VersionProvider := DelphiVersionFor;
  FSyntaxDiagnostics.RuleProvider := RuleContextFor;
  FIndex := TSymbolIndex.Create;
  FDefinition := TLspDefinition.Create(FDocuments, FIndex,
    function(const AUnitName: string): Boolean
    begin
      Result := EnsureUnit(AUnitName);
    end);
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
          Result := Workspace.SearchPaths;
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
  FConnection.Free;
  // Vor den Ordnern: der Hintergrund-Thread der Syntaxprüfung fragt ihre Symbole ab.
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
begin
  Result := Default(TServerStatus);
  Result.Units := FIndex.UnitCount;
  Result.Symbols := FIndex.SymbolCount;
  Result.MemoryBytes := AllocatedBytes;
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
      Result := Workspace.Configuration.Settings.DelphiVersion;
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
begin
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
      else if SameText(ExtractFileExt(Change.FileName), '.pas') or SameText(ExtractFileExt(Change.FileName), '.dpr') then
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
      LoggerImpl.AddSink(TStreamLogSink.CreateForFile(AOptions.LogFile), AOptions.LogLevel);
    except
      on E: Exception do
        Logger.Error(Format('Logdatei "%s" kann nicht geöffnet werden: %s', [AOptions.LogFile, E.Message]));
    end;

  // Ab hier erreichen versehentliche Ausgaben (Writeln, Bibliotheken) nur noch stderr.
  Transport := TJsonRpcStreamTransport.Create(TStdStreams.CreateInput, TStdStreams.ReserveOutputForProtocol, True);
  if AOptions.TraceFile <> '' then
    try
      Transport := TJsonRpcTracingTransport.Create(Transport, CreateTraceStream(AOptions.TraceFile), True);
    except
      on E: Exception do
        Logger.Error(Format('Mitschnitt "%s" kann nicht angelegt werden: %s', [AOptions.TraceFile, E.Message]));
    end;
  LoggerImpl.AddSink(TLspLogMessageSink.Create(Transport), AOptions.LogLevel);

  for Warning in AOptions.Warnings do
    Logger.Warning(Warning);

  Result := TServerComposition.Create(Transport, Logger);
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
