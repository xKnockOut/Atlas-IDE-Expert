unit Atlas.IDE.Tests.Projects;

// Testprojekte der Projektgruppe finden und bei mehreren wählen (#69, #585):
// Ein Projekt ist ein Testprojekt, wenn seine Hauptdatei DUnitX.TestFramework
// verwendet. Bei mehreren Kandidaten fragt Atlas einmal in einem
// Palettenfenster und merkt sich die Wahl für genau diese Kandidaten
// (Atlas.Core.Tests.ProjectChoice). Aus Atlas.IDE.Tests.Runner gelöst; der
// Läufer hält nur den Zustand der Läufe. Nur im Hauptthread verwenden.

interface

uses
  System.SysUtils,
  ToolsAPI;

type
  /// <summary>Das gefundene bzw. gewählte Testprojekt.</summary>
  TAtlasTestsProjectProc = reference to procedure(const AProject: IOTAProject);
  /// <summary>Zeile in der Meldungsansicht.</summary>
  TAtlasTestsSayProc = reference to procedure(const AText: string);

  TAtlasIdeTestProjects = class
  private
    class function ChoiceFile: string; static;
    /// <summary>Wahl AChosen aus AFiles merken und AThen mit dem Projekt rufen; ohne offenes Projekt eine Meldung.
    /// </summary>
    class procedure Apply(const AFiles: TArray<string>; AChosen: Integer; const ASay: TAtlasTestsSayProc;
      const AThen: TAtlasTestsProjectProc); static;
  public
    /// <summary>Zeilen einer Datei: offener Puffer, sonst die Platte.</summary>
    class function ReadLines(const AFileName: string; out ALines: TArray<string>): Boolean; static;
    class function IsTestProject(const AProject: IOTAProject): Boolean; static;
    /// <summary>Offenes Testprojekt, das AFileName ist oder enthält; nil ohne.</summary>
    class function ProjectByFile(const AFileName: string): IOTAProject; static;
    /// <summary>Testprojekte der Projektgruppe, die AFileName enthalten (AFileName '' = alle).</summary>
    class function TestProjects(const AFileName: string): TArray<IOTAProject>; static;
    /// <summary>Ein Kandidat bzw. gemerkte Wahl: gleich AThen; sonst fragen und merken. Nach dem Fragen nur,
    /// solange AAlive True liefert.</summary>
    class procedure Choose(const ACandidates: TArray<IOTAProject>; const AAlive: TFunc<Boolean>;
      const ASay: TAtlasTestsSayProc; const AThen: TAtlasTestsProjectProc); static;
  end;

implementation

uses
  System.IOUtils,
  System.Types,
  Vcl.Forms,
  Atlas.Core.Commands.Palette,
  Atlas.Core.Files.DataFile,
  Atlas.Core.Files.TextFile,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Tests.ProjectChoice,
  Atlas.Core.Tests.Run,
  Atlas.UI.Tests.Strings,
  Atlas.UI.Commands.Palette,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.Files,
  Atlas.Text.Lines;

/// <summary>Je Datei ein Eintrag der Palette; Id ist der Index.</summary>
function ProjectCommands(const AFiles: TArray<string>): TArray<TAtlasCommand>;
var
  mIndex: Integer;
  mCommand: TAtlasCommand;
begin
  Result := nil;
  for mIndex := 0 to High(AFiles) do
  begin
    mCommand := Default(TAtlasCommand);
    mCommand.Id := IntToStr(mIndex);
    mCommand.Caption := ChangeFileExt(ExtractFileName(AFiles[mIndex]), '');
    mCommand.Path := ExtractFileDir(AFiles[mIndex]);
    mCommand.Description := AFiles[mIndex];
    Result := Result + [mCommand];
  end;
end;

/// <summary>Fläche, über der die Palette erscheint: aktives Fenster, sonst Hauptfenster, sonst Arbeitsfläche.</summary>
function PaletteArea: TRect;
begin
  if Screen.ActiveForm <> nil then
  begin
    Result := Screen.ActiveForm.BoundsRect;
  end
  else if Application.MainForm <> nil then
  begin
    Result := Application.MainForm.BoundsRect;
  end
  else
  begin
    Result := Screen.WorkAreaRect;
  end;
end;

{ TAtlasIdeTestProjects }

class function TAtlasIdeTestProjects.ReadLines(const AFileName: string; out ALines: TArray<string>): Boolean;
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

class function TAtlasIdeTestProjects.IsTestProject(const AProject: IOTAProject): Boolean;
var
  mLines: TArray<string>;
begin
  Result := (AProject <> nil) and (AProject.FileName <> '') and
    ReadLines(ChangeFileExt(AProject.FileName, '.dpr'), mLines) and TAtlasTestRun.IsTestProgram(mLines);
end;

class function TAtlasIdeTestProjects.ProjectByFile(const AFileName: string): IOTAProject;
var
  mServices: IOTAModuleServices;
  mGroup: IOTAProjectGroup;
  mIndex: Integer;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, IOTAModuleServices, mServices) then
  begin
    Exit;
  end;
  mGroup := mServices.MainProjectGroup;
  if mGroup = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to mGroup.ProjectCount - 1 do
  begin
    if (mGroup.Projects[mIndex] <> nil) and (SameText(mGroup.Projects[mIndex].FileName, AFileName) or
      (mGroup.Projects[mIndex].FindModuleInfo(AFileName) <> nil)) and IsTestProject(mGroup.Projects[mIndex]) then
    begin
      Exit(mGroup.Projects[mIndex]);
    end;
  end;
end;

class function TAtlasIdeTestProjects.TestProjects(const AFileName: string): TArray<IOTAProject>;
var
  mServices: IOTAModuleServices;
  mGroup: IOTAProjectGroup;
  mIndex: Integer;
  mProject: IOTAProject;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, IOTAModuleServices, mServices) then
  begin
    Exit;
  end;
  mGroup := mServices.MainProjectGroup;
  if mGroup = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to mGroup.ProjectCount - 1 do
  begin
    mProject := mGroup.Projects[mIndex];
    if (mProject = nil) or ((AFileName <> '') and not SameText(mProject.FileName, AFileName) and
      (mProject.FindModuleInfo(AFileName) = nil)) then
    begin
      Continue;
    end;
    if IsTestProject(mProject) then
    begin
      Result := Result + [mProject];
    end;
  end;
end;

class function TAtlasIdeTestProjects.ChoiceFile: string;
begin
  Result := TPath.Combine(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'),
    TAtlasTestProjectChoices.cFileName);
end;

class procedure TAtlasIdeTestProjects.Apply(const AFiles: TArray<string>; AChosen: Integer;
  const ASay: TAtlasTestsSayProc; const AThen: TAtlasTestsProjectProc);
var
  mProject: IOTAProject;
  mStored: TArray<TAtlasTestProjectChoice>;
begin
  // Das Projekt kann inzwischen geschlossen sein.
  mProject := ProjectByFile(AFiles[AChosen]);
  if mProject = nil then
  begin
    ASay(TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsNoProject));
    Exit;
  end;
  // Gesperrt gelesene Datei nicht mit dieser einen Wahl überschreiben (Bericht N3).
  if TAtlasDataFile.Writable(TAtlasTestProjectChoices.Load(ChoiceFile, mStored)) then
  begin
    TAtlasTestProjectChoices.Remember(mStored, AFiles, mProject.FileName);
    if not TAtlasTestProjectChoices.Save(ChoiceFile, mStored) then
    begin
      ASay(TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsChoiceSaveFailed));
    end;
  end
  else
  begin
    ASay(TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsChoiceSaveFailed));
  end;
  AThen(mProject);
end;

class procedure TAtlasIdeTestProjects.Choose(const ACandidates: TArray<IOTAProject>; const AAlive: TFunc<Boolean>;
  const ASay: TAtlasTestsSayProc; const AThen: TAtlasTestsProjectProc);
var
  mFiles: TArray<string>;
  mIndex: Integer;
  mWindow: TAtlasPaletteWindow;
  mAlive: TFunc<Boolean>;
  mSay: TAtlasTestsSayProc;
  mThen: TAtlasTestsProjectProc;
begin
  mFiles := nil;
  for mIndex := 0 to High(ACandidates) do
  begin
    mFiles := mFiles + [ACandidates[mIndex].FileName];
  end;
  mIndex := TAtlasTestProjectChoices.Pick(TAtlasTestProjectChoices.Load(ChoiceFile), mFiles);
  if mIndex >= 0 then
  begin
    AThen(ACandidates[mIndex]);
    Exit;
  end;
  // Einmal fragen; die Wahl gilt danach für genau diese Kandidaten.
  mAlive := AAlive;
  mSay := ASay;
  mThen := AThen;
  mWindow := TAtlasPaletteWindow.CreatePalette(Application, ProjectCommands(mFiles), nil, TAtlasIdeStyle.Colors);
  mWindow.KeepOrder := True;
  mWindow.Prompt := TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsChooseProject);
  mWindow.OnExecute :=
    procedure(ACommand: TAtlasCommand)
    var
      mChosen: Integer;
    begin
      mChosen := StrToIntDef(ACommand.Id, -1);
      if not mAlive() or (mChosen < 0) or (mChosen > High(mFiles)) then
      begin
        Exit;
      end;
      TAtlasGuard.Run(TAtlasFeature.Build,
        procedure
        begin
          Apply(mFiles, mChosen, mSay, mThen);
        end);
    end;
  mWindow.ShowOver(PaletteArea);
end;

end.
