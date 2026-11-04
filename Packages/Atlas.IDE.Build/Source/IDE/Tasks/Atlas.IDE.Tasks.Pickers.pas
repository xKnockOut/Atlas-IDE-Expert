unit Atlas.IDE.Tasks.Pickers;

// Palettenfenster der Projektaufgaben (#900): „Aufgabe ausführen …“ (je
// Aufgabe Gruppe, Taste und letzter Lauf) und „Befunde je Aufgabe ein- oder
// ausblenden“. Der Läufer (Atlas.IDE.Tasks.Runner) reicht die Aufgaben und
// was bei einer Wahl geschieht hinein; nach seinem Abbau tut eine Wahl
// nichts (AAlive). Nur im Hauptthread.

interface

uses
  System.SysUtils,
  Atlas.Core.Tasks.Definitions,
  Atlas.IDE.Tasks.Projects;

type
  TAtlasIdeTaskPickers = class
  public
    /// <summary>Aufgabe wählen und starten; ALastText liefert den letzten Lauf je Name.</summary>
    class procedure ChooseTask(const ATasks: TAtlasTaskDefinitions; const ALastText: TFunc<string, string>;
      const ARun: TAtlasTaskRunByName; const AAlive: TFunc<Boolean>); static;
    /// <summary>Befunde einer Aufgabe ein- oder ausblenden; AHidden sagt, ob sie gerade ausgeblendet sind.</summary>
    class procedure ChooseFindings(const ATasks: TAtlasTaskDefinitions; const AHidden: TFunc<string, Boolean>;
      const AToggle: TProc<string>; const AAlive: TFunc<Boolean>); static;
  end;

implementation

uses
  System.Types,
  Vcl.Forms,
  Atlas.Core.Commands.Palette,
  Atlas.Core.Diagnostics.Guard,
  Atlas.UI.Build.Strings,
  Atlas.UI.Commands.Palette,
  Atlas.UI.Tasks.Texts,
  Atlas.IDE.Foundation.EditorStyle;

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

/// <summary>Wahl an APick weitergeben, solange der Läufer lebt (unter dem Schutz des Features).</summary>
function PickHandler(const AAlive: TFunc<Boolean>; const APick: TProc<string>): TProc<TAtlasCommand>;
begin
  Result :=
    procedure(ACommand: TAtlasCommand)
    var
      mId: string;
    begin
      if not AAlive() then
      begin
        Exit;
      end;
      mId := ACommand.Id;
      TAtlasGuard.Run(TAtlasFeature.Tasks,
        procedure
        begin
          APick(mId);
        end);
    end;
end;

procedure ShowPalette(const ACommands: TArray<TAtlasCommand>; const APrompt: string; const AAlive: TFunc<Boolean>;
  const APick: TProc<string>);
var
  mWindow: TAtlasPaletteWindow;
begin
  mWindow := TAtlasPaletteWindow.CreatePalette(Application, ACommands, nil, TAtlasIdeStyle.Colors);
  mWindow.KeepOrder := True;
  mWindow.Prompt := APrompt;
  mWindow.OnExecute := PickHandler(AAlive, APick);
  mWindow.ShowOver(PaletteArea);
end;

function RunPick(const ARun: TAtlasTaskRunByName): TProc<string>;
begin
  Result :=
    procedure(AName: string)
    var
      mReason: string;
    begin
      if not ARun(AName, mReason) and (mReason <> '') then
      begin
        TAtlasIdeTaskProjects.Say(mReason, True);
      end;
    end;
end;

{ TAtlasIdeTaskPickers }

class procedure TAtlasIdeTaskPickers.ChooseTask(const ATasks: TAtlasTaskDefinitions;
  const ALastText: TFunc<string, string>; const ARun: TAtlasTaskRunByName; const AAlive: TFunc<Boolean>);
var
  mCommands: TArray<TAtlasCommand>;
  mCommand: TAtlasCommand;
  mTask: TAtlasTaskDefinition;
begin
  mCommands := nil;
  for mTask in ATasks do
  begin
    mCommand := Default(TAtlasCommand);
    mCommand.Id := mTask.Name;
    mCommand.Caption := mTask.Name;
    mCommand.Path := TAtlasTaskTexts.GroupName(mTask.Group);
    mCommand.ShortCut := mTask.KeyText;
    mCommand.Description := TAtlasTaskTexts.Description(mTask, ALastText(mTask.Name));
    mCommands := mCommands + [mCommand];
  end;
  ShowPalette(mCommands, TAtlasBuildStrings.Text(TAtlasBuildTextId.TasksChoosePrompt), AAlive, RunPick(ARun));
end;

class procedure TAtlasIdeTaskPickers.ChooseFindings(const ATasks: TAtlasTaskDefinitions;
  const AHidden: TFunc<string, Boolean>; const AToggle: TProc<string>; const AAlive: TFunc<Boolean>);
var
  mCommands: TArray<TAtlasCommand>;
  mCommand: TAtlasCommand;
  mTask: TAtlasTaskDefinition;
begin
  mCommands := nil;
  for mTask in ATasks do
  begin
    mCommand := Default(TAtlasCommand);
    mCommand.Id := mTask.Name;
    if AHidden(mTask.Name) then
    begin
      mCommand.Caption := TAtlasBuildStrings.Fmt(TAtlasBuildTextId.TasksFindingsHidden, [mTask.Name]);
    end
    else
    begin
      mCommand.Caption := TAtlasBuildStrings.Fmt(TAtlasBuildTextId.TasksFindingsShown, [mTask.Name]);
    end;
    mCommand.Path := TAtlasTaskTexts.GroupName(mTask.Group);
    mCommands := mCommands + [mCommand];
  end;
  ShowPalette(mCommands, TAtlasBuildStrings.Text(TAtlasBuildTextId.TasksFindingsPrompt), AAlive, AToggle);
end;

end.
