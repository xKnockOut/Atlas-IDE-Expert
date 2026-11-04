unit Atlas.IDE.Tasks.Projects;

// Projektaufgaben (#900): was der Läufer (Atlas.IDE.Tasks.Runner) über
// Projekte, Dateien und die IDE wissen muss:
// - Aufgaben eines Projekts aus atlas.json neben der .dproj und der globalen
//   %APPDATA%\Atlas\settings.json (Projekt vor global) und ein Stand der
//   beiden Dateien (SignatureOf), an dem der Läufer Änderungen merkt.
// - Projektdateien und Suchpfad für das Auflösen von Pfaden der Ausgabe,
//   Variablen ${…}, Speichern geänderter Dateien vor dem Lauf und Zeilen
//   einer Datei (Puffer vor Platte) für die Bereiche der Befunde.
// - Meldungen in der Meldungsansicht (Gruppe Atlas).
// - TAtlasIdeTaskNames merkt sich die Namen der Aufgaben je Projekt, bis sich
//   eine der Dateien ändert (Schnellaktion der Willkommensseite).
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Tasks.Definitions;

type
  /// <summary>Aufgabe AName starten; False mit Grund.</summary>
  TAtlasTaskRunByName = reference to function(const AName: string; out AReason: string): Boolean;

  TAtlasIdeTaskProjects = class
  public const
    /// <summary>Schlüssel der Läufe ohne Projekt (nur globale Aufgaben).</summary>
    NoProject = '(global)';
  public
    class function ActiveProject: string; static;
    /// <summary>tasks.json in %APPDATA%\Atlas (Verlauf).</summary>
    class function HistoryFile: string; static;
    /// <summary>AProject, '' als NoProject.</summary>
    class function KeyOf(const AProject: string): string; static;
    /// <summary>Stand von atlas.json des Projekts und der globalen Datei.</summary>
    class function SignatureOf(const AProject: string): string; static;
    /// <summary>Aufgaben des Projekts AProject (.dproj; '' = nur global).</summary>
    class function DefinitionsOf(const AProject: string; out AIssues: TArray<string>): TAtlasTaskDefinitions;
      static;
    /// <summary>Dateien des geladenen Projekts und sein Suchpfad (ohne Einträge mit Makros).</summary>
    class function ProjectFilesOf(const AProject: string; out ASearchPath: TArray<string>): TArray<string>; static;
    class function VariablesOf(const AProject: string): TAtlasTaskVariables; static;
    /// <summary>Geänderte Dateien speichern (ohne Projekte und Gruppen).</summary>
    class procedure SaveModified; static;
    /// <summary>Zeile in der Meldungsansicht (Gruppe Atlas); AShow holt die Ansicht nach vorn.</summary>
    class procedure Say(const AText: string; AShow: Boolean); static;
    /// <summary>Zeilen von AFileName aus dem Puffer, sonst von der Platte; False, wenn nicht lesbar.</summary>
    class function ReadLines(const AFileName: string; out ALines: TArray<string>): Boolean; static;
    /// <summary>Befunde aller Aufgaben aus dem Problemspeicher entfernen.</summary>
    class procedure ClearFindings; static;
  end;

  /// <summary>Namen der Aufgaben je Projekt, neu gelesen nur nach Änderung der Dateien.</summary>
  TAtlasIdeTaskNames = class
  private
    FSignatures: TDictionary<string, string>;
    FNames: TDictionary<string, TArray<string>>;
  public
    constructor Create;
    destructor Destroy; override;
    function NamesOf(const AProject: string): TArray<string>;
  end;

implementation

uses
  System.IOUtils,
  ToolsAPI,
  Atlas.Core.Files.TextFile,
  Atlas.Core.Projects.Contract,
  Atlas.Core.Settings.Layers,
  Atlas.Core.Tasks.Runs,
  Atlas.Text.Lines,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.Problems.Controller,
  Atlas.IDE.Projects.Context,
  Atlas.IDE.Settings.Project;

const
  cMessageGroup = 'Atlas';

function ProjectByFile(const AFileName: string): IOTAProject;
var
  mServices: IOTAModuleServices;
begin
  Result := nil;
  if (AFileName <> '') and Supports(BorlandIDEServices, IOTAModuleServices, mServices) then
  begin
    Supports(mServices.FindModule(AFileName), IOTAProject, Result);
  end;
end;

function Stamp(const AFileName: string): string;
var
  mAge: TDateTime;
begin
  if (AFileName <> '') and FileAge(AFileName, mAge) then
  begin
    Result := FloatToStr(mAge, TFormatSettings.Invariant);
  end
  else
  begin
    Result := '-';
  end;
end;

{ TAtlasIdeTaskProjects }

class function TAtlasIdeTaskProjects.ActiveProject: string;
begin
  Result := TAtlasProjectSettings.ActiveProject;
end;

class function TAtlasIdeTaskProjects.HistoryFile: string;
begin
  Result := TPath.Combine(TPath.Combine(GetEnvironmentVariable('APPDATA'), 'Atlas'), TAtlasTaskHistory.FileName);
end;

class function TAtlasIdeTaskProjects.KeyOf(const AProject: string): string;
begin
  Result := AProject;
  if Result = '' then
  begin
    Result := NoProject;
  end;
end;

class function TAtlasIdeTaskProjects.SignatureOf(const AProject: string): string;
var
  mProjectFile: string;
begin
  mProjectFile := '';
  if AProject <> '' then
  begin
    mProjectFile := TPath.Combine(ExtractFileDir(AProject), TAtlasSettingsFiles.ProjectName);
  end;
  Result := AnsiLowerCase(AProject) + '|' + Stamp(mProjectFile) + '|' + Stamp(TAtlasProjectSettings.GlobalFile);
end;

class function TAtlasIdeTaskProjects.DefinitionsOf(const AProject: string; out AIssues: TArray<string>):
  TAtlasTaskDefinitions;
var
  mHasBom: Boolean;
  mOwn, mGlobal: TAtlasTaskDefinitions;
begin
  AIssues := nil;
  mOwn := nil;
  if AProject <> '' then
  begin
    mOwn := TAtlasTasks.Parse(TAtlasProjectSettings.ReadText(TPath.Combine(ExtractFileDir(AProject),
      TAtlasSettingsFiles.ProjectName), mHasBom), False, AIssues);
  end;
  mGlobal := TAtlasTasks.Parse(TAtlasProjectSettings.ReadText(TAtlasProjectSettings.GlobalFile, mHasBom), True,
    AIssues);
  Result := TAtlasTasks.Merge(mOwn, mGlobal);
end;

/// <summary>Suchpfad mit Ordnern relativ zu AFolder; Makros wie $(BDS) setzt er nicht ein, solche Einträge bleiben
/// weg.</summary>
function SearchPathOf(const AEntries: TArray<string>; const AFolder: string): TArray<string>;
var
  mEntry: string;
begin
  Result := nil;
  for mEntry in AEntries do
  begin
    if (mEntry = '') or (Pos('$(', mEntry) > 0) then
    begin
      Continue;
    end;
    if TPath.IsPathRooted(mEntry) then
    begin
      Result := Result + [mEntry];
    end
    else
    begin
      Result := Result + [TPath.Combine(AFolder, mEntry)];
    end;
  end;
end;

class function TAtlasIdeTaskProjects.ProjectFilesOf(const AProject: string; out ASearchPath: TArray<string>):
  TArray<string>;
var
  mProject: IOTAProject;
  mIndex: Integer;
begin
  Result := nil;
  ASearchPath := nil;
  mProject := ProjectByFile(AProject);
  if mProject = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to mProject.GetModuleCount - 1 do
  begin
    if mProject.GetModule(mIndex).FileName <> '' then
    begin
      Result := Result + [mProject.GetModule(mIndex).FileName];
    end;
  end;
  ASearchPath := SearchPathOf(TAtlasIdeProjectContext.Read(mProject).SearchPaths, ExtractFileDir(AProject));
end;

class function TAtlasIdeTaskProjects.VariablesOf(const AProject: string): TAtlasTaskVariables;
var
  mServices: IOTAModuleServices;
  mEditors: IOTAEditorServices;
  mProject: IOTAProject;
begin
  Result := Default(TAtlasTaskVariables);
  Result.ProjectDir := ExtractFileDir(AProject);
  Result.GroupDir := Result.ProjectDir;
  if Supports(BorlandIDEServices, IOTAModuleServices, mServices) and (mServices.MainProjectGroup <> nil) and
    (mServices.MainProjectGroup.FileName <> '') then
  begin
    Result.GroupDir := ExtractFileDir(mServices.MainProjectGroup.FileName);
  end;
  if Supports(BorlandIDEServices, IOTAEditorServices, mEditors) and (mEditors.TopBuffer <> nil) then
  begin
    Result.FileName := mEditors.TopBuffer.FileName;
  end;
  mProject := ProjectByFile(AProject);
  if mProject <> nil then
  begin
    Result.Config := mProject.CurrentConfiguration;
    Result.Platform := mProject.CurrentPlatform;
  end;
  Result.Bds := GetEnvironmentVariable('BDS');
end;

/// <summary>Modul mit einem geänderten Editor speichern.</summary>
procedure SaveIfModified(const AModule: IOTAModule);
var
  mEditor: Integer;
begin
  for mEditor := 0 to AModule.ModuleFileCount - 1 do
  begin
    if (AModule.ModuleFileEditors[mEditor] <> nil) and AModule.ModuleFileEditors[mEditor].Modified then
    begin
      AModule.Save(False, True);
      Exit;
    end;
  end;
end;

class procedure TAtlasIdeTaskProjects.SaveModified;
var
  mServices: IOTAModuleServices;
  mModule: IOTAModule;
  mIndex: Integer;
begin
  if not Supports(BorlandIDEServices, IOTAModuleServices, mServices) then
  begin
    Exit;
  end;
  for mIndex := 0 to mServices.ModuleCount - 1 do
  begin
    mModule := mServices.Modules[mIndex];
    // Projekte und Gruppen nicht: Ihr Speichern fragt nach Namen bzw. ändert die .dproj.
    if (mModule <> nil) and not Supports(mModule, IOTAProject) and not Supports(mModule, IOTAProjectGroup) then
    begin
      SaveIfModified(mModule);
    end;
  end;
end;

class procedure TAtlasIdeTaskProjects.Say(const AText: string; AShow: Boolean);
var
  mMessages: IOTAMessageServices;
  mGroup: IOTAMessageGroup;
begin
  if not Supports(BorlandIDEServices, IOTAMessageServices, mMessages) then
  begin
    Exit;
  end;
  mGroup := mMessages.GetGroup(cMessageGroup);
  if mGroup = nil then
  begin
    mGroup := mMessages.AddMessageGroup(cMessageGroup);
  end;
  mMessages.AddTitleMessage(AText, mGroup);
  if AShow then
  begin
    mMessages.ShowMessageView(mGroup);
  end;
end;

class function TAtlasIdeTaskProjects.ReadLines(const AFileName: string; out ALines: TArray<string>): Boolean;
var
  mBuffer: IOTAEditBuffer;
  mText: string;
begin
  ALines := nil;
  mBuffer := TAtlasIdeFiles.BufferOf(AFileName);
  if mBuffer <> nil then
  begin
    mText := TAtlasEditorBuffer.Text(mBuffer);
  end
  else
  begin
    if not FileExists(AFileName) then
    begin
      Exit(False);
    end;
    try
      mText := TAtlasTextFile.Load(AFileName).Text;
    except
      on Exception do
        Exit(False);
    end;
  end;
  ALines := TTextLines.SplitLines(mText);
  Result := True;
end;

class procedure TAtlasIdeTaskProjects.ClearFindings;
begin
  if TAtlasProblemsController.Current <> nil then
  begin
    TAtlasProblemsController.Current.ClearTasks;
  end;
end;

{ TAtlasIdeTaskNames }

constructor TAtlasIdeTaskNames.Create;
begin
  inherited Create;
  FSignatures := TDictionary<string, string>.Create;
  FNames := TDictionary<string, TArray<string>>.Create;
end;

destructor TAtlasIdeTaskNames.Destroy;
begin
  FreeAndNil(FNames);
  FreeAndNil(FSignatures);
  inherited Destroy;
end;

function TAtlasIdeTaskNames.NamesOf(const AProject: string): TArray<string>;
var
  mKey, mSignature, mKnown: string;
  mIssues: TArray<string>;
  mTask: TAtlasTaskDefinition;
begin
  mKey := AnsiLowerCase(AProject);
  mSignature := TAtlasIdeTaskProjects.SignatureOf(AProject);
  if FSignatures.TryGetValue(mKey, mKnown) and (mKnown = mSignature) and FNames.TryGetValue(mKey, Result) then
  begin
    Exit;
  end;
  Result := nil;
  for mTask in TAtlasIdeTaskProjects.DefinitionsOf(AProject, mIssues) do
  begin
    Result := Result + [mTask.Name];
  end;
  FSignatures.AddOrSetValue(mKey, mSignature);
  FNames.AddOrSetValue(mKey, Result);
end;

end.
