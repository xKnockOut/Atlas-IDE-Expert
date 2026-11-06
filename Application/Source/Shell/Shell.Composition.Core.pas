unit Shell.Composition.Core;

// Kern der Komposition: Arbeitsbereiche, Einstellungen, atlas.json, Ordner, Regelkontext, Quellen, Direktiven und
// Vorgaben je Datei. Die Bereiche der Komposition bekommen den Kern statt einzelner Felder.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Logging.Contract,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Shell.Platform,
  Shell.Workspace,
  Shell.Composition.Workspaces,
  Shell.Composition.Settings,
  Shell.Composition.Configuration,
  Shell.Composition.Folders,
  Shell.Composition.RuleContext,
  Shell.Composition.Sources,
  Shell.Composition.Directives,
  Shell.Composition.FileOptions;

type
  /// <summary>Was der Kern von der Komposition braucht. Die Funktionen fragen erst beim Aufruf; was sie liefern,
  /// entsteht nach dem Kern.</summary>
  TShellCoreServices = record
    Logger: ILogger;
    Transport: IJsonRpcTransport;
    Documents: IDocumentStore;
    Index: TShellFoldersIndexFunc;
    UsesGraph: TShellRuleUsesGraphFunc;
    Queries: TShellRuleQueriesFunc;
    /// <summary>Gewähltes Projekt einer Projektgruppe (#648).</summary>
    SelectedProject: TShellRegistrySelectedFunc;
    /// <summary>Aktives Projekt der IDE.</summary>
    ActiveProject: TShellRegistryActiveFunc;
    IdeProject: TShellFoldersIdeProjectFunc;
    /// <summary>Typen der laufenden IDE (atlas/ideTypes).</summary>
    IdeTypes: TShellFoldersIdeTypesFunc;
    Selection: TShellFoldersSelectionFunc;
    Anonymizer: TShellFoldersAnonymizerFunc;
    ClientName: TShellFoldersTextFunc;
    ProjectLoaded: TProc;
    IndexStageDone: TProc<Boolean>;
    IndexEvent: TProc<string>;
    SettingsChanged: TProc<TServerSettings>;
    /// <summary>Beobachtete Dateien geändert; im Thread der Nachrichtenschleife verarbeiten.</summary>
    FilesChanged: TFileWatcherChanged;
  end;

  /// <summary>Hält die Arbeitsbereiche und alles, was je Datei aus ihnen folgt.</summary>
  TShellCore = class
  private
    FServices: TShellCoreServices;
    FWorkspaces: TShellWorkspaceRegistry;
    FSettings: TShellSettings;
    FConfiguration: TShellConfiguration;
    FFolders: TShellFolders;
    FRuleContext: TShellRuleContext;
    FSources: TShellSources;
    FDirectives: TShellDirectives;
    FFileOptions: TShellFileOptions;
    function RegistryServices: TShellWorkspaceRegistryServices;
    function ConfigurationServices: TShellConfigurationServices;
    function FoldersServices: TShellFoldersServices;
    function RuleContextServices: TShellRuleContextServices;
    function SourcesServices: TShellSourcesServices;
    /// <summary>Noch nicht gesehene Projektdateien von AWorkspace, mit excludeTests ohne Testunits.</summary>
    function FilesOf(AWorkspace: TShellWorkspace; ASeen: TDictionary<string, Boolean>): TArray<string>;
    /// <summary>Hat die Unit laut Index ein Test-Framework im uses?</summary>
    function IsIndexedTestUnit(const AFileName: string): Boolean;
  public
    constructor Create(const AServices: TShellCoreServices);
    /// <summary>Gibt Vorgaben, Regelkontext, Einstellungen, Arbeitsbereiche, Ordner und atlas.json frei; vorher
    /// FreeWorkspaces.</summary>
    destructor Destroy; override;
    /// <summary>atlas.json am Verteiler; Editor-Baum nur aus den aktiven Zweigen (#845) und mit den $I-Dateien der
    /// Suchpfade (#264, #860).</summary>
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>Beenden: Index-Threads aller Ordner anhalten.</summary>
    procedure StopIndexThreads;
    /// <summary>Beenden: gibt die Ordner frei, solange Index und Syntaxprüfung noch leben.</summary>
    procedure FreeWorkspaces;
    /// <summary>Text einer Datei; geöffnete Dokumente haben Vorrang vor der Platte.</summary>
    function ReadText(const AFileName: string; out AText: string): Boolean;
    /// <summary>Projektdateien aller Ordner und geöffnete Dateien außerhalb der Projekte.</summary>
    function ProjectFiles: TArray<string>;
    /// <summary>Dateien der Projektprüfung: ProjectFiles ohne Testunits, wenn excludeTests gilt.</summary>
    function CheckFiles: TArray<string>;
    property Workspaces: TShellWorkspaceRegistry read FWorkspaces;
    property Settings: TShellSettings read FSettings;
    property Configuration: TShellConfiguration read FConfiguration;
    property Folders: TShellFolders read FFolders;
    property RuleContext: TShellRuleContext read FRuleContext;
    property Sources: TShellSources read FSources;
    property Directives: TShellDirectives read FDirectives;
    property FileOptions: TShellFileOptions read FFileOptions;
  end;

implementation

uses
  Atlas.Common.Documents.Uris,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Query.Contract,
  Atlas.Common.Architecture.UsesService,
  Shell.Bootstrap;

constructor TShellCore.Create(const AServices: TShellCoreServices);
begin
  inherited Create;
  FServices := AServices;
  FWorkspaces := TShellWorkspaceRegistry.Create(RegistryServices);
  FSettings := TShellSettings.Create(FWorkspaces,
    function(const AUri: string): string
    begin
      Result := FFileOptions.LanguageLevelFor(AUri);
    end);
  FConfiguration := TShellConfiguration.Create(ConfigurationServices);
  FFolders := TShellFolders.Create(FoldersServices);
  FRuleContext := TShellRuleContext.Create(RuleContextServices);
  FSources := TShellSources.Create(SourcesServices);
  FDirectives := TShellDirectives.Create(FWorkspaces, FSettings);
  FFileOptions := TShellFileOptions.Create(FWorkspaces, FSettings);
end;

destructor TShellCore.Destroy;
begin
  FreeAndNil(FFileOptions);
  FreeAndNil(FDirectives);
  FreeAndNil(FSources);
  FreeAndNil(FRuleContext);
  FreeAndNil(FSettings);
  FreeAndNil(FWorkspaces);
  // Nach den Ordnern: Ihre Index-Threads sind beendet und abgemeldet.
  FreeAndNil(FFolders);
  FreeAndNil(FConfiguration);
  FServices := Default(TShellCoreServices);
  inherited Destroy;
end;

procedure TShellCore.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  FConfiguration.Attach(ADispatcher);
  // Editor-Baum nur aus den aktiven Zweigen des Projekts (#845).
  TSyntaxTreeCache.SetDefinesProvider(FDirectives.TreeDefines());
  // $I-Dateien im Editor-Baum, in Syntaxprüfung und Abblenden (#264, #860): Suchpfade des Projekts.
  TSyntaxTreeCache.SetIncludeProvider(FDirectives.TreeIncludes());
end;

procedure TShellCore.StopIndexThreads;
var
  mWorkspace: TShellWorkspace;
begin
  for mWorkspace in FWorkspaces.Items do
  begin
    mWorkspace.Stop;
  end;
end;

procedure TShellCore.FreeWorkspaces;
begin
  FWorkspaces.FreeWorkspaces;
end;

function TShellCore.RegistryServices: TShellWorkspaceRegistryServices;
begin
  Result := Default(TShellWorkspaceRegistryServices);
  Result.Logger := FServices.Logger;
  Result.SelectedProject := FServices.SelectedProject;
  Result.ActiveProject := FServices.ActiveProject;
  Result.ReadText := ReadText;
end;

function TShellCore.ConfigurationServices: TShellConfigurationServices;
begin
  Result := Default(TShellConfigurationServices);
  Result.Logger := FServices.Logger;
  Result.Workspaces := FWorkspaces;
  Result.Settings := FSettings;
  Result.Documents := FServices.Documents;
  Result.Transport := FServices.Transport;
  Result.FilesChanged := FServices.FilesChanged;
end;

function TShellCore.FoldersServices: TShellFoldersServices;
begin
  Result := Default(TShellFoldersServices);
  Result.Logger := FServices.Logger;
  Result.Transport := FServices.Transport;
  Result.Documents := FServices.Documents;
  Result.Workspaces := FWorkspaces;
  Result.Settings := FSettings;
  Result.Configuration := FConfiguration;
  Result.Index := FServices.Index;
  Result.IdeProject := FServices.IdeProject;
  Result.IdeTypes := FServices.IdeTypes;
  Result.Selection := FServices.Selection;
  Result.Anonymizer := FServices.Anonymizer;
  Result.ClientName := FServices.ClientName;
  Result.ReadText := ReadText;
  Result.ProjectLoaded := FServices.ProjectLoaded;
  Result.IndexStageDone := FServices.IndexStageDone;
  Result.IndexEvent := FServices.IndexEvent;
  Result.SettingsChanged := FServices.SettingsChanged;
end;

function TShellCore.RuleContextServices: TShellRuleContextServices;
begin
  Result := Default(TShellRuleContextServices);
  Result.Logger := FServices.Logger;
  Result.Workspaces := FWorkspaces;
  Result.Settings := FSettings;
  Result.Index :=
    function: ISymbolIndex
    begin
      Result := FServices.Index();
    end;
  Result.UsesGraph := FServices.UsesGraph;
  Result.Queries := FServices.Queries;
  Result.EnsureUnit := FFolders.EnsureUnitFunc();
  Result.ReadText := ReadText;
end;

function TShellCore.SourcesServices: TShellSourcesServices;
begin
  Result := Default(TShellSourcesServices);
  Result.Workspaces := FWorkspaces;
  Result.Settings := FSettings;
  Result.Index :=
    function: ISymbolIndex
    begin
      Result := FServices.Index();
    end;
  Result.EnsureUnit := FFolders.EnsureUnitFunc();
  Result.ReadText := ReadText;
  Result.ActiveProject :=
    function: string
    begin
      Result := FServices.ActiveProject();
    end;
end;

function TShellCore.ReadText(const AFileName: string; out AText: string): Boolean;
var
  mDocument: ITextDocument;
begin
  // Geöffnete Dokumente haben Vorrang vor der Datei auf der Platte.
  if FServices.Documents.TryGet(TDocumentUris.FromPath(AFileName), mDocument) then
  begin
    AText := mDocument.Text;
    Exit(True);
  end;
  Result := TShellBootstrap.ReadSourceText(AFileName, AText);
end;

function TShellCore.ProjectFiles: TArray<string>;
var
  mWorkspace: TShellWorkspace;
  mDocument: ITextDocument;
  mFileName: string;
begin
  Result := nil;
  System.TMonitor.Enter(FWorkspaces.Lock);
  try
    for mWorkspace in FWorkspaces.Items do
    begin
      for mFileName in mWorkspace.State.ProjectFiles do
      begin
        Result := Result + [mFileName];
      end;
    end;
  finally
    System.TMonitor.Exit(FWorkspaces.Lock);
  end;
  // Geöffnete Dateien außerhalb des Projekts zählen mit.
  for mDocument in FServices.Documents.Documents do
  begin
    Result := Result + [TDocumentUris.ToPath(mDocument.Uri)];
  end;
end;

function TShellCore.CheckFiles: TArray<string>;
var
  mWorkspace: TShellWorkspace;
  mDocument: ITextDocument;
  mSeen: TDictionary<string, Boolean>;
begin
  // Wie ProjectSourceFiles, aber mit excludeTests ohne Testunits: Sonst stehen sie in der Warteschlange der
  // Projektprüfung, werden gezählt und eingelesen und erst in der Regel-Engine übersprungen. Ob eine Unit eine
  // Testunit ist, sagt ihr uses im Index; nicht indizierte Dateien bleiben drin (die Engine entscheidet dann).
  Result := nil;
  mSeen := TDictionary<string, Boolean>.Create;
  try
    System.TMonitor.Enter(FWorkspaces.Lock);
    try
      for mWorkspace in FWorkspaces.Items do
      begin
        Result := Result + FilesOf(mWorkspace, mSeen);
      end;
    finally
      System.TMonitor.Exit(FWorkspaces.Lock);
    end;
  finally
    mSeen.Free;
  end;
  // Geöffnete Dateien außerhalb des Projekts zählen mit; geöffnete Testunits prüft der Editor ohnehin.
  for mDocument in FServices.Documents.Documents do
  begin
    Result := Result + [TDocumentUris.ToPath(mDocument.Uri)];
  end;
end;

function TShellCore.FilesOf(AWorkspace: TShellWorkspace;
  ASeen: TDictionary<string, Boolean>): TArray<string>;
var
  mFileName: string;
begin
  Result := nil;
  for mFileName in AWorkspace.State.ProjectFiles do
  begin
    if ASeen.ContainsKey(AnsiLowerCase(mFileName)) then
    begin
      Continue;
    end;
    ASeen.Add(AnsiLowerCase(mFileName), True);
    if not (AWorkspace.Configuration.Settings.ExcludeTests and IsIndexedTestUnit(mFileName)) then
    begin
      Result := Result + [mFileName];
    end;
  end;
end;

function TShellCore.IsIndexedTestUnit(const AFileName: string): Boolean;
var
  mIndexed: TUnitIndex;
  mIndex: ISymbolIndex;
begin
  mIndex := FServices.Index();
  Result := (mIndex <> nil) and mIndex.FindFile(AFileName, mIndexed) and
    TUsesClauses.UsesTestFramework(mIndexed.InterfaceUses + mIndexed.ImplementationUses);
end;

end.
