unit Atlas.IDE.Debug.NoSourceFacts;

// Fenster „Kein Quelltext“ (#869): sammelt in der IDE die Tatsachen für
// TAtlasNoSource.Decide.
// - Ordner: gemerkte Ordner des Projekts (Quelltext suchen …), Suchpfad des
//   Projekts, Bibliothekspfad der IDE (mit $(…) wie die IDE), dazu
//   $(BDS)\source mit Unterordnern für die PAS der Bibliothek.
// - Modul im Windows-Ordner: <Modul>.dll bzw. .exe in System32/SysWOW64.
// - DCU aus der Bibliothek: unter $(BDSLIB).
// - Debug-DCUs: DCC_DebugDCUs der Konfiguration beim Start.
// - {$D-}: aus dem gefundenen Quelltext.
// Gemerkte Ordner je Projekt in %LOCALAPPDATA%\Atlas\debug-source-folders.json.
// Nur im Hauptthread verwenden.

interface

uses
  System.SysUtils,
  Atlas.Core.Debug.NoSource,
  Atlas.Core.Debug.DialogCompletion;

type
  TAtlasIdeNoSourceFacts = class
  public const
    cFolderFileName = 'debug-source-folders.json';
    cFoldersPerProject = 20;
  private class var
    FFolders: TAtlasExpressionHistory;
    FFoldersKept: Boolean;
    class function Folders: TArray<string>; static;
    class function LibraryFolder: string; static;
    class function IsSystemModule(const AModule: string): Boolean; static;
    class function FindLibrarySource(const AUnit: string): string; static;
  public
    class procedure Release; static;
    /// <summary>Tatsachen zur Kopfzeile AHeader des obersten Rahmens.</summary>
    class function Collect(const AHeader: string): TAtlasNoSourceFacts; static;
    /// <summary>Ordner AFolder für das aktuelle Projekt merken.</summary>
    class procedure RememberFolder(const AFolder: string); static;
  end;

implementation

uses
  System.IOUtils,
  System.Classes,
  ToolsAPI,
  Atlas.Core.Files.DataFile,
  Atlas.Core.Projects.Contract,
  Atlas.Core.Projects.PathCheck,
  Atlas.Core.Debug.Unavailable,
  Atlas.IDE.Projects.Context,
  Atlas.IDE.Debug.Session,
  Atlas.IDE.Debug.EvaluateStore;

const
  cFoldersWhat = 'debug source folders';
  cDebugDcusOption = 'DCC_DebugDCUs';
  /// <summary>Größe, bis zu der Atlas einen Quelltext nach {$D-} liest.</summary>
  cMaxSourceBytes = 4 * 1024 * 1024;
  cSystemFolders: array[0..1] of string = ('System32', 'SysWOW64');
  cModuleExtensions: array[0..2] of string = ('.dll', '.exe', '.drv');

function FolderFile: string;
begin
  Result := TPath.Combine(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'),
    TAtlasIdeNoSourceFacts.cFolderFileName);
end;

function FileExistsFunc: TFunc<string, Boolean>;
begin
  Result :=
    function(APath: string): Boolean
    begin
      Result := FileExists(APath);
    end;
end;

{ TAtlasIdeNoSourceFacts }

class procedure TAtlasIdeNoSourceFacts.Release;
begin
  FreeAndNil(FFolders);
  FFoldersKept := False;
end;

class function TAtlasIdeNoSourceFacts.Folders: TArray<string>;
var
  mProject: IOTAProject;
  mContext: TAtlasProjectContext;
  mMacros: TAtlasPathMacros;
  mVariable: TAtlasPathVariable;
  mSkipped: TArray<string>;
  mFolder: string;
begin
  if FFolders = nil then
  begin
    FFolders := TAtlasExpressionHistory.Create(cFoldersPerProject);
    FFoldersKept := not TAtlasDataFile.Writable(TAtlasDataFile.Load(FolderFile, cFoldersWhat,
      function(const AText: string): Boolean
      begin
        Result := FFolders.LoadFromText(AText);
      end));
  end;
  Result := FFolders.Items(TAtlasIdeEvaluateStore.CurrentProject);
  mProject := GetActiveProject;
  if mProject = nil then
  begin
    Exit;
  end;
  mContext := TAtlasIdeProjectContext.Read(mProject);
  if mContext.Project = '' then
  begin
    Exit;
  end;
  mMacros := TAtlasIdeProjectContext.Macros(mContext);
  mVariable := mMacros.Variable();
  mSkipped := nil;
  mFolder := ExtractFileDir(mContext.Project);
  Result := Result + [mFolder] + TAtlasPathCheck.ExpandPaths(mContext.SearchPaths, mFolder, mVariable, mSkipped) +
    TAtlasPathCheck.ExpandPaths(mContext.LibraryPaths, mFolder, mVariable, mSkipped);
end;

class function TAtlasIdeNoSourceFacts.LibraryFolder: string;
var
  mServices: IOTAServices;
begin
  Result := '';
  if Supports(BorlandIDEServices, IOTAServices, mServices) then
  begin
    Result := TPath.Combine(mServices.GetRootDirectory, 'lib');
  end;
end;

class function TAtlasIdeNoSourceFacts.IsSystemModule(const AModule: string): Boolean;
var
  mWindows, mFolder, mExt: string;
begin
  Result := False;
  if AModule = '' then
  begin
    Exit;
  end;
  mWindows := GetEnvironmentVariable('SystemRoot');
  if mWindows = '' then
  begin
    Exit;
  end;
  for mFolder in cSystemFolders do
  begin
    for mExt in cModuleExtensions do
    begin
      if FileExists(TPath.Combine(TPath.Combine(mWindows, mFolder), AModule + mExt)) then
      begin
        Exit(True);
      end;
    end;
  end;
end;

class function TAtlasIdeNoSourceFacts.FindLibrarySource(const AUnit: string): string;
var
  mServices: IOTAServices;
  mFiles: TArray<string>;
begin
  Result := '';
  if (AUnit = '') or not Supports(BorlandIDEServices, IOTAServices, mServices) then
  begin
    Exit;
  end;
  try
    mFiles := TDirectory.GetFiles(TPath.Combine(mServices.GetRootDirectory, 'source'), AUnit + '.pas',
      TSearchOption.soAllDirectories);
  except
    // Ordner fehlt oder ist nicht lesbar: ohne Quelltext der Bibliothek.
    on Exception do
      mFiles := nil;
  end;
  if Length(mFiles) > 0 then
  begin
    Result := mFiles[0];
  end;
end;

/// <summary>Schaltet der Quelltext AFileName die Debug-Informationen ab?</summary>
function SourceDebugInfoOff(const AFileName: string): Boolean;
var
  mText: string;
begin
  Result := False;
  try
    if TFile.GetSize(AFileName) <= cMaxSourceBytes then
    begin
      mText := TFile.ReadAllText(AFileName, TEncoding.UTF8);
      Result := TAtlasNoSource.DebugInfoOff(mText);
    end;
  except
    // Nicht lesbar: kein Befund.
    on Exception do
      Result := False;
  end;
end;

class function TAtlasIdeNoSourceFacts.Collect(const AHeader: string): TAtlasNoSourceFacts;
var
  mPlace: TAtlasNoSourcePlace;
  mLibrary: string;
begin
  Result := Default(TAtlasNoSourceFacts);
  mPlace := TAtlasNoSourcePlace.Parse(AHeader);
  Result.Place := mPlace;
  Result.SystemModule := IsSystemModule(mPlace.Module);
  if Result.SystemModule then
  begin
    Exit;
  end;
  TAtlasNoSource.Locate(mPlace, Folders, FileExistsFunc, Result);
  mLibrary := LibraryFolder;
  Result.LibraryUnit := (Result.DcuPath <> '') and (mLibrary <> '') and
    TAtlasNoSource.IsUnder(Result.DcuPath, [mLibrary]);
  if Result.LibraryUnit and (Result.PasPath = '') then
  begin
    Result.PasPath := FindLibrarySource(Result.UnitName);
  end;
  Result.DebugDcus := TAtlasDebugUnavailable.OptionOn(TAtlasIdeDebugSession.LaunchValue(cDebugDcusOption), False);
  if Result.PasPath <> '' then
  begin
    Result.DebugInfoOff := SourceDebugInfoOff(Result.PasPath);
  end;
end;

class procedure TAtlasIdeNoSourceFacts.RememberFolder(const AFolder: string);
begin
  Folders;
  if not FFolders.Add(TAtlasIdeEvaluateStore.CurrentProject, ExcludeTrailingPathDelimiter(AFolder)) or
    FFoldersKept then
  begin
    Exit;
  end;
  try
    TAtlasDataFile.Write(FolderFile, FFolders.ToText);
  except
    on E: Exception do
      TAtlasDataFile.ReportNotWritten(cFoldersWhat, E);
  end;
end;

end.
