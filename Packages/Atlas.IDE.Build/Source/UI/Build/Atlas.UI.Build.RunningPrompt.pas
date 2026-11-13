unit Atlas.UI.Build.RunningPrompt;

// Rückfrage „AtlasDemo.exe läuft noch. Beenden und bauen?“ vor dem Build (#551)
// mit Ja / Nein / Immer. „Immer“ beendet und stellt build.stopRunningProgram auf
// always (das erledigt der Aufrufer). Escape und Schließen gelten als Nein.

interface

{$SCOPEDENUMS ON}

type
  TAtlasRunningPromptChoice = (Keep, Stop, Always);

  TAtlasRunningPrompt = class
  public
    /// <summary>Fragt, ob AProgram (gefunden als AProcesses) beendet werden soll.</summary>
    class function Ask(const AProgram, AProcesses: string): TAtlasRunningPromptChoice; static;
  end;

implementation

uses
  Vcl.Dialogs,
  Atlas.UI.Build.Strings;

class function TAtlasRunningPrompt.Ask(const AProgram, AProcesses: string): TAtlasRunningPromptChoice;
const
  cAnswerStop = 100;
  cAnswerKeep = 101;
  cAnswerAlways = 102;
var
  mDialog: TTaskDialog;
  mButton: TTaskDialogBaseButtonItem;
begin
  Result := TAtlasRunningPromptChoice.Keep;
  mDialog := TTaskDialog.Create(nil);
  try
    mDialog.Caption := 'Atlas';
    mDialog.Title := TAtlasBuildStrings.Fmt(TAtlasBuildTextId.RunningProgramTitle, [AProgram]);
    mDialog.Text := TAtlasBuildStrings.Fmt(TAtlasBuildTextId.RunningProgramText, [AProcesses]);
    mDialog.MainIcon := tdiWarning;
    mDialog.Flags := [tfAllowDialogCancellation];
    mButton := mDialog.Buttons.Add;
    mButton.Caption := TAtlasBuildStrings.Text(TAtlasBuildTextId.RunningProgramStop);
    mButton.ModalResult := cAnswerStop;
    mButton.Default := True;
    mButton := mDialog.Buttons.Add;
    mButton.Caption := TAtlasBuildStrings.Text(TAtlasBuildTextId.RunningProgramKeep);
    mButton.ModalResult := cAnswerKeep;
    mButton := mDialog.Buttons.Add;
    mButton.Caption := TAtlasBuildStrings.Text(TAtlasBuildTextId.RunningProgramAlways);
    mButton.ModalResult := cAnswerAlways;
    if not mDialog.Execute then
    begin
      Exit;
    end;
    case mDialog.ModalResult of
      cAnswerStop:
        Result := TAtlasRunningPromptChoice.Stop;
      cAnswerAlways:
        Result := TAtlasRunningPromptChoice.Always;
    end;
  finally
    mDialog.Free;
  end;
end;

end.
