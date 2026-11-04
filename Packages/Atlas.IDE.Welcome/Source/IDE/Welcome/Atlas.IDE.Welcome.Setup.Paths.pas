unit Atlas.IDE.Welcome.Setup.Paths;

// Schritt 4 „Suchpfade und Defines prüfen“ des Bereichs „<Projekt> für Atlas
// einrichten“ (#759): im Hauptthread Projektkontext der aktiven Konfiguration
// (#396), Dateien und Makros je Projekt sammeln, im Hintergrund Pfade
// auflösen, .dproj und Dateien lesen und prüfen (Atlas.Core.Projects.PathCheck).
// Dazu die Projekte einer Gruppe und das Lesen von Dateien, das beim Entladen
// abbricht. Abgeteilt aus Atlas.IDE.Welcome.Setup (Atlas-Befunde).

interface

uses
  ToolsAPI,
  Atlas.Core.Projects.PathCheck;

type
  /// <summary>Ergebnis der Pfadprüfung eines Projekts (bei einer Gruppe eins je Projekt).</summary>
  TAtlasSetupPathRun = record
    Project: string;
    Check: TAtlasPathCheckResult;
    /// <summary>Grund, wenn die Prüfung dieses Projekts abbrach; '' sonst.</summary>
    Error: string;
  end;

  /// <summary>Was die Prüfung eines Projekts im Hintergrund braucht; im Hauptthread gesammelt.</summary>
  TAtlasSetupPathJob = record
    Project: string;
    Input: TAtlasPathCheckInput;
    /// <summary>Such- und Bibliothekspfade wie in den Optionen, mit $(…).</summary>
    SearchPaths: TArray<string>;
    LibraryPaths: TArray<string>;
    Macros: TAtlasPathMacros;
  end;

  TAtlasIdeSetupPaths = class
  public
    /// <summary>Text der Datei; False, wenn sie fehlt, nicht lesbar ist oder die IDE gerade entlädt.</summary>
    class function ReadText(const AFileName: string; out AText: string): Boolean; static;
    /// <summary>Offenes Projekt zur Projektdatei AFileName (.dproj); nil, wenn es nicht geöffnet ist.</summary>
    class function OpenProjectOf(const AFileName: string): IOTAProject; static;
    /// <summary>Projekte, deren Prüfung zu AProject gehört: bei einer .groupproj ihre Projekte, bei einem Projekt
    /// der geöffneten Gruppe mit mehreren Projekten alle Projekte der Gruppe; sonst leer.</summary>
    class function GroupOf(const AProject: string): TArray<string>; static;
    /// <summary>Optionen, Dateien und Makros eines geöffneten Projekts (nur im Hauptthread).</summary>
    class function JobOf(const AIde: IOTAProject): TAtlasSetupPathJob; static;
    /// <summary>Prüft ein Projekt; im Hintergrundthread.</summary>
    class function Run(const AJob: TAtlasSetupPathJob): TAtlasSetupPathRun; static;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.RegularExpressions,
  Atlas.Text.Defines,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.Shutdown,
  Atlas.Core.Projects.Contract,
  Atlas.Core.Files.TextFile,
  Atlas.Core.Welcome.Saved,
  Atlas.Core.Welcome.Setup,
  Atlas.IDE.Projects.Context,
  Atlas.IDE.Projects.Summaries;

/// <summary>Projekte einer geschlossenen Gruppe aus der .groupproj (nur vorhandene .dproj).</summary>
function ClosedGroup(const AGroup: string): TArray<string>;
var
  mText, mMember: string;
begin
  Result := nil;
  if not TAtlasIdeSetupPaths.ReadText(AGroup, mText) then
  begin
    Exit;
  end;
  for mMember in TAtlasWelcomeSaved.GroupProjects(AGroup, mText) do
  begin
    if SameText(ExtractFileExt(mMember), '.dproj') and FileExists(mMember) then
    begin
      Result := Result + [mMember];
    end;
  end;
end;

/// <summary>Hauptprojektgruppe der IDE; nil ohne.</summary>
function MainGroup: IOTAProjectGroup;
var
  mModules: IOTAModuleServices;
begin
  Result := nil;
  if Supports(BorlandIDEServices, IOTAModuleServices, mModules) then
  begin
    Result := mModules.MainProjectGroup;
  end;
end;

/// <summary>Projekte der geöffneten Gruppe mit mehreren Projekten, wenn AProject dazugehört; sonst leer.</summary>
function OpenGroup(const AProject: string): TArray<string>;
var
  mGroup: IOTAProjectGroup;
  mFileName: string;
  mIndex: Integer;
  mInside: Boolean;
begin
  Result := nil;
  mGroup := MainGroup;
  if (mGroup = nil) or (mGroup.ProjectCount < 2) then
  begin
    Exit;
  end;
  mInside := False;
  for mIndex := 0 to mGroup.ProjectCount - 1 do
  begin
    mFileName := mGroup.Projects[mIndex].FileName;
    // Nur gespeicherte .dproj (wie TAtlasIdeProjectContext.Read).
    if SameText(ExtractFileExt(mFileName), '.dproj') and FileExists(mFileName) then
    begin
      Result := Result + [mFileName];
      mInside := mInside or SameText(mFileName, AProject);
    end;
  end;
  if not mInside or (Length(Result) < 2) then
  begin
    Result := nil;
  end;
end;

/// <summary>Hauptdatei: .dpr bei Programmen und Bibliotheken, .dpk bei Packages; dahinter die Units des Projekts.
/// </summary>
function SourcesOf(const AIde: IOTAProject; const AProject: string): TArray<string>;
var
  mMain, mName: string;
  mIndex: Integer;
begin
  Result := nil;
  mMain := ChangeFileExt(AProject, '.dpr');
  if not FileExists(mMain) then
  begin
    mMain := ChangeFileExt(AProject, '.dpk');
  end;
  if FileExists(mMain) then
  begin
    Result := [mMain];
  end;
  for mIndex := 0 to AIde.GetModuleCount - 1 do
  begin
    mName := AIde.GetModule(mIndex).FileName;
    if SameText(ExtractFileExt(mName), '.pas') then
    begin
      Result := Result + [mName];
    end;
  end;
end;

/// <summary>Projekte der Gruppe (ihre Packages erfüllen requires, #759) und Build-Skripte (-dX) neben dem
/// Projekt, neben der Gruppe und in üblichen Unterordnern der Gruppe.</summary>
procedure AddGroup(var AInput: TAtlasPathCheckInput; const AProject: string);
var
  mGroup: IOTAProjectGroup;
  mGroupDir: string;
  mIndex: Integer;
begin
  mGroupDir := ExtractFileDir(AProject);
  mGroup := MainGroup;
  if mGroup <> nil then
  begin
    if mGroup.FileName <> '' then
    begin
      mGroupDir := ExtractFileDir(mGroup.FileName);
    end;
    for mIndex := 0 to mGroup.ProjectCount - 1 do
    begin
      if mGroup.Projects[mIndex] <> nil then
      begin
        AInput.GroupProjects := AInput.GroupProjects +
          [TAtlasIdeProjectSummaries.ProjectFileOf(mGroup.Projects[mIndex].FileName)];
      end;
    end;
  end;
  AInput.ScriptFolders := [ExtractFileDir(AProject), mGroupDir, TPath.Combine(mGroupDir, 'tools'),
    TPath.Combine(mGroupDir, 'scripts'), TPath.Combine(mGroupDir, 'build')];
end;

/// <summary>True, wenn AOutput einer der Ordner in ASearchPaths ist.</summary>
function InSearchPath(const AOutput: string; const ASearchPaths: TArray<string>): Boolean;
var
  mEach: string;
begin
  Result := False;
  if AOutput = '' then
  begin
    Exit;
  end;
  for mEach in ASearchPaths do
  begin
    if SameText(ExcludeTrailingPathDelimiter(mEach), ExcludeTrailingPathDelimiter(AOutput)) then
    begin
      Exit(True);
    end;
  end;
end;

/// <summary>Projekte der Gruppe, die in einen Ordner des Suchpfads übersetzen (DCC_DcuOutput).</summary>
function ProducersOf(const AInput: TAtlasPathCheckInput; const AProject: string;
  const AVariable: TAtlasPathVariable): TArray<string>;
var
  mMember, mOther, mOutput: string;
  mMatch: TMatch;
begin
  Result := nil;
  for mMember in AInput.GroupProjects do
  begin
    if SameText(mMember, AProject) or not TAtlasIdeSetupPaths.ReadText(mMember, mOther) then
    begin
      Continue;
    end;
    mMatch := TRegEx.Match(mOther, '<DCC_DcuOutput>([^<]*)</DCC_DcuOutput>', [roIgnoreCase]);
    if not mMatch.Success then
    begin
      Continue;
    end;
    mOutput := TAtlasPathCheck.ExpandPath(mMatch.Groups[1].Value, ExtractFileDir(mMember), AVariable);
    if InSearchPath(mOutput, AInput.SearchPaths) then
    begin
      Result := Result + [mMember];
    end;
  end;
end;

/// <summary>Dateinamen im Ordner AFolder; leer beim Entladen oder ohne Ordner.</summary>
function FilesIn(const AFolder: string): TArray<string>;
var
  mItem: string;
begin
  Result := nil;
  if TAtlasShutdown.Signalled or not TDirectory.Exists(AFolder) then
  begin
    Exit;
  end;
  try
    for mItem in TDirectory.GetFiles(AFolder) do
    begin
      Result := Result + [ExtractFileName(mItem)];
    end;
  except
    on Exception do
    begin
      Result := nil;
    end;
  end;
end;

/// <summary>Eingabe der Prüfung mit aufgelösten Pfaden, Defines der .dproj und Erzeugern aus der Gruppe.</summary>
function InputOf(const AJob: TAtlasSetupPathJob): TAtlasPathCheckInput;
var
  mFolder, mDproj: string;
  mVariable: TAtlasPathVariable;
  mSkipped: TArray<string>;
begin
  Result := AJob.Input;
  mFolder := ExtractFileDir(AJob.Project);
  // Mit (): Variable liefert eine Funktion; ohne Klammern wäre es die Methode selbst.
  mVariable := AJob.Macros.Variable();
  // Pfade mit unbekanntem Makro fallen weg; ihre Makros machen die Funde unsicher.
  mSkipped := nil;
  Result.SearchPaths := TAtlasPathCheck.ExpandPaths(AJob.SearchPaths, mFolder, mVariable, mSkipped);
  Result.LibraryPaths := TAtlasPathCheck.ExpandPaths(AJob.LibraryPaths, mFolder, mVariable, mSkipped);
  Result.SkippedMacros := mSkipped;
  if TAtlasIdeSetupPaths.ReadText(AJob.Project, mDproj) then
  begin
    Result.ProjectDefines := TAtlasPathCheck.DprojDefines(mDproj);
  end;
  Result.ProducedBy := Result.ProducedBy + ProducersOf(Result, AJob.Project, mVariable);
end;

{ TAtlasIdeSetupPaths }

class function TAtlasIdeSetupPaths.ReadText(const AFileName: string; out AText: string): Boolean;
begin
  AText := '';
  // Abbruch beim Entladen: Die Prüfung liest dann nichts mehr.
  if TAtlasShutdown.Signalled or not FileExists(AFileName) then
  begin
    Exit(False);
  end;
  try
    AText := TAtlasTextFile.LoadText(AFileName);
    Result := True;
  except
    on Exception do
    begin
      Result := False;
    end;
  end;
end;

class function TAtlasIdeSetupPaths.OpenProjectOf(const AFileName: string): IOTAProject;
var
  mModules: IOTAModuleServices;
  mModule: IOTAModule;
begin
  Result := nil;
  if (AFileName = '') or not Supports(BorlandIDEServices, IOTAModuleServices, mModules) then
  begin
    Exit;
  end;
  mModule := mModules.FindModule(AFileName);
  if mModule <> nil then
  begin
    Supports(mModule, IOTAProject, Result);
  end;
end;

class function TAtlasIdeSetupPaths.GroupOf(const AProject: string): TArray<string>;
begin
  Result := nil;
  if AProject = '' then
  begin
    Exit;
  end;
  if TAtlasWelcomeSetup.IsGroup(AProject) then
  begin
    // Geschlossene Gruppe: Projekte aus der .groupproj.
    Result := ClosedGroup(AProject);
  end
  else
  begin
    Result := OpenGroup(AProject);
  end;
end;

class function TAtlasIdeSetupPaths.JobOf(const AIde: IOTAProject): TAtlasSetupPathJob;
var
  mContext: TAtlasProjectContext;
  mVersion: Double;
begin
  Result := Default(TAtlasSetupPathJob);
  Result.Project := TAtlasIdeProjectSummaries.ProjectFileOf(AIde.FileName);
  mContext := TAtlasIdeProjectContext.Read(AIde);
  Result.Input.Project := Result.Project;
  Result.Input.Sources := SourcesOf(AIde, Result.Project);
  Result.Input.Namespaces := mContext.Namespaces;
  AddGroup(Result.Input, Result.Project);
  mVersion := TTextDefines.CompilerVersionOfBds(StrToFloatDef(mContext.BdsVersion, 0, TFormatSettings.Invariant));
  Result.Input.ActiveDefines := mContext.Defines + TTextDefines.Predefined(mContext.Platform, mVersion);
  Result.SearchPaths := mContext.SearchPaths;
  Result.LibraryPaths := mContext.LibraryPaths;
  // Makros der IDE (Umgebungsvariablen der Optionen, BDS-Ordner, Projekt), danach der Prozess.
  if mContext.Project = '' then
  begin
    mContext.Project := Result.Project;
  end;
  Result.Macros := TAtlasIdeProjectContext.Macros(mContext);
end;

class function TAtlasIdeSetupPaths.Run(const AJob: TAtlasSetupPathJob): TAtlasSetupPathRun;
begin
  Result := Default(TAtlasSetupPathRun);
  Result.Project := AJob.Project;
  try
    Result.Check := TAtlasPathCheck.Run(InputOf(AJob),
      function(const AFileName: string; out AText: string): Boolean
      begin
        Result := ReadText(AFileName, AText);
      end,
      function(const AFolder: string): TArray<string>
      begin
        Result := FilesIn(AFolder);
      end);
  except
    on E: Exception do
    begin
      // Ins Protokoll nur die Klasse: Die Meldung kann Pfade enthalten.
      TAtlasGuard.Log('Einrichtung: Prüfung der Suchpfade abgebrochen (' + E.ClassName + ')');
      Result.Error := E.Message;
    end;
  end;
end;

end.
