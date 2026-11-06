unit Shell.Composition.Directives;

// Internals-Rolle Shell: Direktiven je Datei aus dem Projekt ihres Arbeitsbereichs. Bedingte Symbole für das
// Abblenden inaktiver Zweige (#615, #845), Include-Pfade (#264), Kontext für Hover und Vervollständigung in
// Direktiven (#102), Herkunft der Compilerschalter und Plattform und Konfiguration des Builds.

interface

uses
  Atlas.Common.Projects.Contract,
  Atlas.Common.Pascal.Preprocessor,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Architecture.UsesLocator,
  Atlas.Common.Lsp.SyntaxDiagnostics,
  Atlas.Common.Lsp.ConditionalSymbols,
  Atlas.Common.Lsp.CompilerSwitches,
  Shell.Composition.Workspaces,
  Shell.Composition.Settings;

type
  /// <summary>Direktiven der Dateien aus den Projekten der Arbeitsbereiche.</summary>
  TShellDirectives = class
  private
    FWorkspaces: TShellWorkspaceRegistry;
    FSettings: TShellSettings;
    /// <summary>Bedingte Symbole des Projekts der Datei; ohne Zuordnung die des ersten (aktiven) Projekts.
    /// </summary>
    function DefinesFor(const AUri: string; out ADefines: TArray<string>): Boolean;
    function DefinesOfFile(const AFileName: string): TArray<string>;
    /// <summary>Include-Pfade des Projekts; ohne Projekt sucht der Resolver im Ordner der Datei.</summary>
    function IncludeResolverFor(const AUri: string): TIncludeResolver;
    /// <summary>Include-Pfade, Projekt und Erfolg des Projekts zur Datei unter der Sperre.</summary>
    function ProjectOf(const AFileName: string; out AIncludePaths: TArray<string>; out AProject: TProjectInfo): Boolean;
    function ConditionalContextFor(const AUri: string): TConditionalContext;
    function CompilerSwitchContextFor(const AUri: string): TCompilerSwitchContext;
    function BuildTargetFor(const AUri: string; out APlatform, AConfig: string): Boolean;
  public
    constructor Create(AWorkspaces: TShellWorkspaceRegistry; ASettings: TShellSettings);
    /// <summary>Symbole für Abblenden, Code-Aktionen und Baselines.</summary>
    function Defines: TDefinesProvider;
    function TreeDefines: TTreeDefinesProvider;
    function TreeIncludes: TTreeIncludeProvider;
    /// <summary>Symbole einer Datei auf der Platte für die uses-Suche.</summary>
    function UsesDefines: TUsesDefinesFunc;
    function IncludeResolver(const AUri: string): TIncludeResolver;
    /// <summary>Hover und Vervollständigung in Direktiven (#102): Symbole mit Herkunft aus der .dproj,
    /// Compiler-Vorgaben, Include-Pfade und der Schalter "directives".</summary>
    function ConditionalContext: TConditionalContextFunc;
    /// <summary>Compilerschalter mit Herkunft aus Projekt bzw. Vorgabe.</summary>
    function CompilerSwitchContext: TCompilerSwitchContextFunc;
    /// <summary>Plattform und Konfiguration des Projekts der Datei.</summary>
    function BuildTarget: TBuildTargetProvider;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.IncludeFiles,
  Atlas.Common.Pascal.CompilerSwitches,
  Atlas.Common.Documents.Uris,
  Shell.Workspace;

/// <summary>Bedingte Symbole aus ADefines ohne Vorgaben des Compilers und ohne Schalterstände.</summary>
function OwnDefines(const ADefines, APredefined: TArray<string>): TArray<string>;
var
  mDefine: string;
begin
  Result := nil;
  for mDefine in ADefines do
  begin
    if (IndexText(mDefine, APredefined) < 0) and not TPascalPreprocessor.IsSwitchEntry(mDefine) then
    begin
      Result := Result + [mDefine];
    end;
  end;
end;

constructor TShellDirectives.Create(AWorkspaces: TShellWorkspaceRegistry; ASettings: TShellSettings);
begin
  inherited Create;
  FWorkspaces := AWorkspaces;
  FSettings := ASettings;
end;

function TShellDirectives.Defines: TDefinesProvider;
begin
  Result := DefinesFor;
end;

function TShellDirectives.TreeDefines: TTreeDefinesProvider;
begin
  Result := DefinesFor;
end;

function TShellDirectives.TreeIncludes: TTreeIncludeProvider;
begin
  Result := IncludeResolverFor;
end;

function TShellDirectives.UsesDefines: TUsesDefinesFunc;
begin
  Result := DefinesOfFile;
end;

function TShellDirectives.IncludeResolver(const AUri: string): TIncludeResolver;
begin
  Result := IncludeResolverFor(AUri);
end;

function TShellDirectives.ConditionalContext: TConditionalContextFunc;
begin
  Result := ConditionalContextFor;
end;

function TShellDirectives.CompilerSwitchContext: TCompilerSwitchContextFunc;
begin
  Result := CompilerSwitchContextFor;
end;

function TShellDirectives.BuildTarget: TBuildTargetProvider;
begin
  Result := BuildTargetFor;
end;

function TShellDirectives.DefinesFor(const AUri: string; out ADefines: TArray<string>): Boolean;
var
  mWorkspace: TShellWorkspace;
begin
  ADefines := nil;
  System.TMonitor.Enter(FWorkspaces.Lock);
  try
    mWorkspace := FWorkspaces.WorkspaceOf(TDocumentUris.ToPath(AUri));
    Result := (mWorkspace <> nil) and mWorkspace.State.Defines(ADefines);
    // Datei keinem Projekt zugeordnet oder dessen Projekt noch nicht geladen (Projektgruppe): wie das
    // aktive Projekt, das die IDE zuerst meldet. Sonst blieben inaktive Zweige dort ungedimmt (#615).
    if not Result and (FWorkspaces.Items.Count > 0) then
    begin
      Result := FWorkspaces.Items[0].State.Defines(ADefines);
    end;
  finally
    System.TMonitor.Exit(FWorkspaces.Lock);
  end;
end;

function TShellDirectives.DefinesOfFile(const AFileName: string): TArray<string>;
begin
  if not DefinesFor(TDocumentUris.FromPath(AFileName), Result) then
  begin
    Result := nil;
  end;
end;

function TShellDirectives.ProjectOf(const AFileName: string; out AIncludePaths: TArray<string>;
  out AProject: TProjectInfo): Boolean;
var
  mWorkspace: TShellWorkspace;
begin
  AIncludePaths := nil;
  Result := False;
  System.TMonitor.Enter(FWorkspaces.Lock);
  try
    mWorkspace := FWorkspaces.Pick(AFileName);
    if mWorkspace <> nil then
    begin
      AIncludePaths := mWorkspace.State.IncludePaths;
      Result := mWorkspace.State.Project(AProject);
    end;
  finally
    System.TMonitor.Exit(FWorkspaces.Lock);
  end;
  if not Result then
  begin
    AProject := Default(TProjectInfo);
  end;
end;

function TShellDirectives.IncludeResolverFor(const AUri: string): TIncludeResolver;
var
  mIncludePaths: TArray<string>;
  mProject: TProjectInfo;
begin
  ProjectOf(TDocumentUris.ToPath(AUri), mIncludePaths, mProject);
  Result := TIncludeFiles.Resolver(mIncludePaths);
end;

function TShellDirectives.ConditionalContextFor(const AUri: string): TConditionalContext;
var
  mSettings: TDirectiveSettings;
  mProject: TProjectInfo;
  mDefines, mPredefined, mIncludePaths: TArray<string>;
begin
  mSettings := FSettings.SettingsFor(AUri).Directives;
  Result := TConditionalContext.Default;
  Result.CompletionEnabled := mSettings.Completion;
  Result.HoverEnabled := mSettings.Hover;
  Result.FileName := TDocumentUris.ToPath(AUri);
  if not (mSettings.Completion or mSettings.Hover) then
  begin
    Exit;
  end;
  ProjectOf(Result.FileName, mIncludePaths, mProject);
  Result.ResolveInclude := TIncludeFiles.Resolver(mIncludePaths);
  // Dieselben Symbole wie beim Abblenden inaktiver Zweige.
  Result.HasDefines := DefinesFor(AUri, mDefines);
  if not Result.HasDefines then
  begin
    Exit;
  end;
  Result.Defines := mDefines;
  mPredefined := TPascalPreprocessor.PredefinedSymbols(mProject.Platform,
    TPascalPreprocessor.CompilerVersionFromDefines(mDefines));
  Result.Config := mProject.Config;
  Result.Platform := mProject.Platform;
  Result.Sources := TConditionalSymbols.SourcesOf(OwnDefines(mDefines, mPredefined), mProject.DefineOrigins,
    mPredefined, mProject.Platform);
end;

function TShellDirectives.CompilerSwitchContextFor(const AUri: string): TCompilerSwitchContext;
var
  mProject: TProjectInfo;
  mDefines, mPredefined, mIncludePaths: TArray<string>;
  mSource: TSymbolSource;
  mKind: TSwitchOriginKind;
begin
  Result := Default(TCompilerSwitchContext);
  Result.FileName := TDocumentUris.ToPath(AUri);
  Result.HasProject := ProjectOf(Result.FileName, mIncludePaths, mProject);
  Result.ResolveInclude := TIncludeFiles.Resolver(mIncludePaths);
  Result.Configuration := mProject.Config;
  Result.Platform := mProject.Platform;
  Result.Input.Properties := mProject.Properties;
  // Dieselben Symbole und Schalterstände wie beim Abblenden inaktiver Zweige.
  if not DefinesFor(AUri, mDefines) then
  begin
    Exit;
  end;
  Result.Input.Defines := mDefines;
  mPredefined := TPascalPreprocessor.PredefinedSymbols(mProject.Platform,
    TPascalPreprocessor.CompilerVersionFromDefines(mDefines));
  for mSource in TConditionalSymbols.SourcesOf(OwnDefines(mDefines, mPredefined), mProject.DefineOrigins,
    mPredefined, mProject.Platform) do
  begin
    mKind := TSwitchOriginKind.Project;
    if IndexText(mSource.Name, mPredefined) >= 0 then
    begin
      mKind := TSwitchOriginKind.Default;
    end;
    Result.Input.DefineOrigins := Result.Input.DefineOrigins +
      [TSwitchDefineOrigin.Create(mSource.Name, TSwitchOrigin.Make(mKind, mSource.Origin))];
  end;
end;

function TShellDirectives.BuildTargetFor(const AUri: string; out APlatform, AConfig: string): Boolean;
var
  mIncludePaths: TArray<string>;
  mProject: TProjectInfo;
begin
  Result := ProjectOf(TDocumentUris.ToPath(AUri), mIncludePaths, mProject);
  APlatform := mProject.Platform;
  AConfig := mProject.Config;
end;

end.
