unit Shell.Composition.LeakSetup;

// Befehl atlas.server.leakSetup (#1880) der Komposition: Projekt zur URI aus
// den Arbeitsbereichen (Projektdatei, Hauptquelltext oder eine Datei des
// Projekts), dazu die Konfiguration Debug aus der .dproj (Symbole,
// Ausgabeordner), Such- und Bibliothekspfade des Arbeitsbereichs und PATH.
// Logik in Atlas.Common.Leaks.Setup und Atlas.Common.Lsp.LeakSetup.

interface

uses
  System.JSON,
  Atlas.Common.Logging.Contract,
  Atlas.Common.Lsp.Commands,
  Atlas.Common.Leaks.Setup,
  Shell.Composition.Workspaces;

type
  TShellLeakSetupReadText = reference to function(const AFileName: string; out AText: string): Boolean;

  /// <summary>Was der Befehl von der Komposition braucht.</summary>
  TShellLeakSetupServices = record
    Logger: ILogger;
    Workspaces: TShellWorkspaceRegistry;
    /// <summary>Geöffnete Dokumente vor der Platte.</summary>
    ReadText: TShellLeakSetupReadText;
  end;

  TShellLeakSetup = class
  public const
    cDebugConfiguration = 'Debug';
  public
    /// <summary>Meldet den Befehl an (nebenläufig: liest nur).</summary>
    class procedure Attach(ACommands: TLspCommands; const AServices: TShellLeakSetupServices); static;
    /// <summary>Eingabe für das Projekt hinter AUri; False mit AReason ohne geladenes Projekt.</summary>
    class function InputFor(const AServices: TShellLeakSetupServices; const AUri: string;
      out AInput: TLeakSetupInput; out AReason: string): Boolean; static;
    /// <summary>Ausgabeordner aus DCC_ExeOutput (relativ zur .dproj); '' = Projektordner.</summary>
    class function OutputFolderOf(const AProjectFile, AExeOutput: string): string; static;
    /// <summary>Ordner aus dem Text der Umgebungsvariablen PATH.</summary>
    class function PathFolders(const APath: string): TArray<string>; static;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Projects.Contract,
  Atlas.Common.Projects.DprojReader,
  Atlas.Common.Lsp.LeakSetup,
  Atlas.Common.Localization.Texts,
  Atlas.Text.LogMarks,
  Shell.Workspace;

{$SCOPEDENUMS ON}

type
  TShellLeakSetupText = (NoProject);

const
  cTexts: array[TShellLeakSetupText] of TAtlasText = (
    (De: 'Zu %s ist kein Projekt geladen'; En: 'No project is loaded for %s'));

{$SCOPEDENUMS OFF}

type
  /// <summary>Dateien für die Erkennung: Dokumente vor der Platte.</summary>
  TShellLeakSetupFiles = class(TInterfacedObject, ILeakSetupFiles)
  private
    FReadText: TShellLeakSetupReadText;
  public
    constructor Create(const AReadText: TShellLeakSetupReadText);
    function FileExists(const AFileName: string): Boolean;
    function ReadText(const AFileName: string; out AText: string): Boolean;
  end;

constructor TShellLeakSetupFiles.Create(const AReadText: TShellLeakSetupReadText);
begin
  inherited Create;
  FReadText := AReadText;
end;

function TShellLeakSetupFiles.FileExists(const AFileName: string): Boolean;
begin
  Result := System.SysUtils.FileExists(AFileName);
end;

function TShellLeakSetupFiles.ReadText(const AFileName: string; out AText: string): Boolean;
begin
  Result := FReadText(AFileName, AText);
end;

{ TShellLeakSetup }

class procedure TShellLeakSetup.Attach(ACommands: TLspCommands; const AServices: TShellLeakSetupServices);
var
  mServices: TShellLeakSetupServices;
begin
  mServices := AServices;
  ACommands.RegisterConcurrent(TLspLeakSetup.cCommand,
    function(const AArguments: TJSONArray): TJSONValue
    var
      mSetup: TLspLeakSetup;
    begin
      mSetup := TLspLeakSetup.Create(
        function(const AUri: string; out AInput: TLeakSetupInput; out AReason: string): Boolean
        begin
          Result := InputFor(mServices, AUri, AInput, AReason);
        end, TShellLeakSetupFiles.Create(mServices.ReadText));
      try
        Result := mSetup.Execute(AArguments);
      finally
        mSetup.Free;
      end;
    end);
end;

/// <summary>Arbeitsbereich mit der Projekt- oder Hauptdatei AFileName, sonst der zur Datei.</summary>
function WorkspaceFor(const AWorkspaces: TShellWorkspaceRegistry; const AFileName: string): TShellWorkspace;
var
  mWorkspace: TShellWorkspace;
  mProject: TProjectInfo;
begin
  for mWorkspace in AWorkspaces.Items do
  begin
    if mWorkspace.State.Project(mProject) and (SameFileName(mProject.FileName, AFileName) or
      SameFileName(mProject.MainSource, AFileName)) then
    begin
      Exit(mWorkspace);
    end;
  end;
  Result := AWorkspaces.Pick(AFileName);
end;

/// <summary>Projekt und Suchordner unter der Sperre der Arbeitsbereiche.</summary>
function LoadedProject(const AServices: TShellLeakSetupServices; const AFileName: string;
  out AProject: TProjectInfo; out AFolders: TArray<string>): Boolean;
var
  mWorkspace: TShellWorkspace;
begin
  AProject := Default(TProjectInfo);
  AFolders := nil;
  System.TMonitor.Enter(AServices.Workspaces.Lock);
  try
    mWorkspace := WorkspaceFor(AServices.Workspaces, AFileName);
    Result := (mWorkspace <> nil) and mWorkspace.State.Project(AProject) and (AProject.MainSource <> '');
    if Result then
    begin
      AFolders := mWorkspace.State.IncludePaths;
    end;
  finally
    System.TMonitor.Exit(AServices.Workspaces.Lock);
  end;
end;

function PropertyOf(const AProject: TProjectInfo; const AName: string): string;
var
  mPair: TPair<string, string>;
begin
  Result := '';
  for mPair in AProject.Properties do
  begin
    if SameText(mPair.Key, AName) then
    begin
      Result := mPair.Value;
    end;
  end;
end;

/// <summary>Symbole und Ausgabeordner der Konfiguration Debug; ohne lesbare .dproj leer.</summary>
procedure ReadDebugConfiguration(const AServices: TShellLeakSetupServices; const AProject: TProjectInfo;
  var AInput: TLeakSetupInput);
var
  mOptions: TDprojOptions;
  mDebug: TProjectInfo;
begin
  mOptions := Default(TDprojOptions);
  mOptions.Config := TShellLeakSetup.cDebugConfiguration;
  mOptions.Platform := AProject.Platform;
  try
    mDebug := TDprojReader.Load(AProject.FileName, mOptions);
    AInput.DebugDefines := mDebug.Defines;
    AInput.OutputFolder := TShellLeakSetup.OutputFolderOf(AProject.FileName, PropertyOf(mDebug, 'DCC_ExeOutput'));
  except
    on E: Exception do
    begin
      AServices.Logger.Debug('Leak setup: Debug configuration not readable: ' + TLogMarks.Text(E.Message));
    end;
  end;
end;

class function TShellLeakSetup.InputFor(const AServices: TShellLeakSetupServices; const AUri: string;
  out AInput: TLeakSetupInput; out AReason: string): Boolean;
var
  mProject: TProjectInfo;
  mFolders: TArray<string>;
begin
  AInput := Default(TLeakSetupInput);
  AReason := '';
  Result := LoadedProject(AServices, TDocumentUris.ToPath(AUri), mProject, mFolders);
  if not Result then
  begin
    AReason := cTexts[TShellLeakSetupText.NoProject].Fmt([ExtractFileName(TDocumentUris.ToPath(AUri))]);
    Exit;
  end;
  AInput.ProjectFile := mProject.FileName;
  AInput.MainSource := mProject.MainSource;
  if not AServices.ReadText(mProject.MainSource, AInput.MainText) then
  begin
    AInput.MainText := '';
  end;
  AInput.Platform := mProject.Platform;
  AInput.SearchFolders := mFolders;
  AInput.PathFolders := PathFolders(GetEnvironmentVariable('PATH'));
  ReadDebugConfiguration(AServices, mProject, AInput);
end;

class function TShellLeakSetup.OutputFolderOf(const AProjectFile, AExeOutput: string): string;
var
  mFolder: string;
begin
  mFolder := ExcludeTrailingPathDelimiter(StringReplace(AExeOutput, '\', PathDelim, [rfReplaceAll]));
  if (mFolder = '') or (mFolder = '.') then
  begin
    Result := ExtractFileDir(AProjectFile);
  end
  else if (ExtractFileDrive(mFolder) <> '') or mFolder.StartsWith(PathDelim) then
  begin
    Result := mFolder;
  end
  else
  begin
    Result := ExcludeTrailingPathDelimiter(ExpandFileName(IncludeTrailingPathDelimiter(ExtractFileDir(AProjectFile)) +
      mFolder));
  end;
end;

class function TShellLeakSetup.PathFolders(const APath: string): TArray<string>;
var
  mFolder: string;
begin
  Result := nil;
  for mFolder in APath.Split([PathSep]) do
  begin
    if Trim(mFolder) <> '' then
    begin
      Result := Result + [Trim(mFolder)];
    end;
  end;
end;

end.
