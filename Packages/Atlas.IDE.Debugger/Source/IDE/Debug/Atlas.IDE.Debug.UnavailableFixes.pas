unit Atlas.IDE.Debug.UnavailableFixes;

// Korrekturen zu „kein Zugriff auf Wert“ (#840) in der IDE, jede erst nach
// einer Vorschau mit Bestätigung. TAtlasIdeDebugUnavailable wählt die Korrektur
// zur letzten Erklärung und reicht deren Tatsachen herein:
//   - ApplyEdit: Einfügungen des Servers über TAtlasIdeWorkspaceEdit.
//   - PrepareRestart: Konfiguration mit Debug-Informationen wählen („Debug“
//     zuerst); Zurücksetzen (Reset) und Start (Run) über die Aktionen der IDE.
//   - UseDebugDcus: DCC_DebugDCUs in der Konfiguration des Starts auf true.
//   - ShowDirective: springt zur Direktive des Schalters.
// Nur im Hauptthread verwenden.

interface

uses
  System.SysUtils,
  System.Classes,
  ToolsAPI,
  Atlas.Core.Debug.Unavailable;

type
  TAtlasIdeDebugUnavailableFixes = class
  public const
    /// <summary>Konfiguration, die „Mit Debug neu starten“ zuerst wählt.</summary>
    cDebugConfiguration = 'Debug';
    cDebugDcusOption = 'DCC_DebugDCUs';
    cDebugInfoOption = 'DCC_DebugInformation';
  private
    class function Confirm(const AText: string): Boolean; static;
    class function HasDebugInfo(const AProject: IOTAProject; const AName: string): Boolean; static;
    /// <summary>„Debug“ mit Debug-Informationen, sonst die erste mit (ohne „Base“); '' ohne.</summary>
    class function ChooseConfiguration(const AProject: IOTAProject): string; static;
    class function ExecuteAction(const AName: string; AShortCut: TShortCut): Boolean; static;
  public
    /// <summary>Text der Korrektur im Tooltip.</summary>
    class function FixText(AFix: TAtlasUnavailableFix): string; static;
    /// <summary>Einfügung für AFix (Routine oder Unit) aus AFacts nach Vorschau anwenden.</summary>
    class procedure ApplyEdit(AFix: TAtlasUnavailableFix; const AFacts: TAtlasUnavailableFacts;
      const ASay: TProc<string>); static;
    /// <summary>Konfiguration wählen, bestätigen lassen und umstellen; False, wenn nichts zu starten ist.</summary>
    class function PrepareRestart(const ASay: TProc<string>): Boolean; static;
    /// <summary>„Start“ der IDE auslösen; ohne Aktion eine Meldung.</summary>
    class procedure Run(const ASay: TProc<string>); static;
    /// <summary>„Programm zurücksetzen“ auslösen; False ohne Aktion (mit Meldung).</summary>
    class function Reset(const ASay: TProc<string>): Boolean; static;
    /// <summary>DCC_DebugDCUs in AConfiguration ('' = aktuelle) nach Bestätigung einschalten.</summary>
    class procedure UseDebugDcus(const AConfiguration: string; const ASay: TProc<string>); static;
    class procedure ShowDirective(const ASwitch: TAtlasUnavailableSwitch); static;
  end;

implementation

uses
  System.Actions,
  System.UITypes,
  Winapi.Windows,
  Vcl.ActnList,
  Vcl.Dialogs,
  Vcl.Menus,
  Atlas.Core.Editor.WorkspacePlan,
  Atlas.Core.Lsp.WorkspaceEdits,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Editor.WorkspaceEdit,
  Atlas.IDE.Projects.Context,
  Atlas.UI.Strings,
  Atlas.UI.Debug.Strings;

const
  cResetAction = 'RunProgramResetCommand';
  cRunAction = 'RunRunCommand';

procedure Say(const ASay: TProc<string>; const AText: string);
begin
  if Assigned(ASay) then
  begin
    ASay(AText);
  end;
end;

/// <summary>Aktion mit Namen AName, sonst die mit dem Tastenkürzel AShortCut; nil ohne.</summary>
function FindAction(const AServices: INTAServices; const AName: string; AShortCut: TShortCut): TContainedAction;
var
  mIndex: Integer;
  mAction: TContainedAction;
begin
  Result := nil;
  for mIndex := 0 to AServices.ActionList.ActionCount - 1 do
  begin
    if SameText(AServices.ActionList.Actions[mIndex].Name, AName) then
    begin
      Result := AServices.ActionList.Actions[mIndex];
    end;
  end;
  // Ersatz: die Aktion mit dem Tastenkürzel der IDE.
  for mIndex := 0 to AServices.ActionList.ActionCount - 1 do
  begin
    mAction := AServices.ActionList.Actions[mIndex];
    if (Result = nil) and (mAction is TCustomAction) and (TCustomAction(mAction).ShortCut = AShortCut) then
    begin
      Result := mAction;
    end;
  end;
end;

{ TAtlasIdeDebugUnavailableFixes }

class function TAtlasIdeDebugUnavailableFixes.FixText(AFix: TAtlasUnavailableFix): string;
const
  cIds: array[TAtlasUnavailableFix] of TAtlasDebugTextId = (TAtlasDebugTextId.DebugUnavailableFixRestart,
    TAtlasDebugTextId.DebugUnavailableFixRoutine, TAtlasDebugTextId.DebugUnavailableFixUnit,
    TAtlasDebugTextId.DebugUnavailableFixDcus, TAtlasDebugTextId.DebugUnavailableFixDirective);
begin
  Result := TAtlasDebugStrings.Text(cIds[AFix]);
end;

class function TAtlasIdeDebugUnavailableFixes.Confirm(const AText: string): Boolean;
begin
  Result := MessageDlg(AText, TMsgDlgType.mtConfirmation, [TMsgDlgBtn.mbOK, TMsgDlgBtn.mbCancel], 0) = mrOk;
end;

class procedure TAtlasIdeDebugUnavailableFixes.ApplyEdit(AFix: TAtlasUnavailableFix;
  const AFacts: TAtlasUnavailableFacts; const ASay: TProc<string>);
var
  mEdit: TLspWorkspaceEdit;
  mOutcome: TAtlasWorkspaceEditResult;
  mTarget: string;
begin
  if AFix = TAtlasUnavailableFix.RoutineOptimization then
  begin
    mEdit := AFacts.RoutineEdit;
  end
  else
  begin
    mEdit := AFacts.UnitEdit;
  end;
  if mEdit.IsEmpty then
  begin
    Exit;
  end;
  mTarget := ExtractFileName(mEdit.Files[0].FileName);
  // Vorschau: die eingefügten Zeilen; erst nach Bestätigung ändern.
  if not Confirm(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DebugUnavailableConfirmEdit, [mTarget,
    sLineBreak + sLineBreak, string.Join(sLineBreak, TAtlasDebugUnavailable.PreviewLines(mEdit)),
    sLineBreak + sLineBreak])) then
  begin
    Exit;
  end;
  mOutcome := TAtlasIdeWorkspaceEdit.Apply(mEdit,
    TAtlasUnopenedPolicies.FromSetting(TAtlasIdeSettings.Current.OpenForEdits), FixText(AFix));
  if mOutcome.Error <> '' then
  begin
    Say(ASay, TAtlasStrings.Fmt(TAtlasTextId.EditFailed, [mOutcome.Error]));
  end
  else
  begin
    Say(ASay, TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DebugUnavailableEditDone, [FixText(AFix), mTarget]));
  end;
end;

class function TAtlasIdeDebugUnavailableFixes.HasDebugInfo(const AProject: IOTAProject;
  const AName: string): Boolean;
begin
  Result := TAtlasDebugUnavailable.OptionOn(
    TAtlasIdeProjectContext.ConfigurationValue(AProject, AName, '', cDebugInfoOption), True);
end;

class function TAtlasIdeDebugUnavailableFixes.ChooseConfiguration(const AProject: IOTAProject): string;
var
  mName: string;
  mConfigurations: TArray<string>;
begin
  Result := '';
  mConfigurations := TAtlasIdeProjectContext.Configurations(AProject);
  for mName in mConfigurations do
  begin
    if SameText(mName, cDebugConfiguration) and HasDebugInfo(AProject, mName) then
    begin
      Result := mName;
    end;
  end;
  for mName in mConfigurations do
  begin
    if (Result = '') and not SameText(mName, 'Base') and HasDebugInfo(AProject, mName) then
    begin
      Result := mName;
    end;
  end;
end;

class function TAtlasIdeDebugUnavailableFixes.PrepareRestart(const ASay: TProc<string>): Boolean;
var
  mProject: IOTAProject;
  mChosen, mPrevious: string;
begin
  Result := False;
  mProject := GetActiveProject;
  if mProject = nil then
  begin
    Exit;
  end;
  mChosen := ChooseConfiguration(mProject);
  if mChosen = '' then
  begin
    Say(ASay, TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugUnavailableNoDebugConfiguration));
    Exit;
  end;
  mPrevious := mProject.CurrentConfiguration;
  if not Confirm(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DebugUnavailableConfirmRestart, [mChosen, mPrevious,
    sLineBreak + sLineBreak])) then
  begin
    Exit;
  end;
  if not SameText(mPrevious, mChosen) then
  begin
    mProject.CurrentConfiguration := mChosen;
  end;
  Result := True;
end;

class procedure TAtlasIdeDebugUnavailableFixes.Run(const ASay: TProc<string>);
begin
  if not ExecuteAction(cRunAction, ShortCut(VK_F9, [])) then
  begin
    Say(ASay, TAtlasStrings.Text(TAtlasTextId.StartProfilesNoRunAction));
  end;
end;

class function TAtlasIdeDebugUnavailableFixes.Reset(const ASay: TProc<string>): Boolean;
begin
  Result := ExecuteAction(cResetAction, ShortCut(VK_F2, [ssCtrl]));
  if not Result then
  begin
    Say(ASay, TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugUnavailableNoResetAction));
  end;
end;

class procedure TAtlasIdeDebugUnavailableFixes.UseDebugDcus(const AConfiguration: string;
  const ASay: TProc<string>);
var
  mProject: IOTAProject;
  mBuild: IOTABuildConfiguration;
  mConfiguration, mPrevious: string;
begin
  mProject := GetActiveProject;
  if mProject = nil then
  begin
    Exit;
  end;
  mConfiguration := AConfiguration;
  if mConfiguration = '' then
  begin
    mConfiguration := mProject.CurrentConfiguration;
  end;
  mBuild := TAtlasIdeProjectContext.BuildConfiguration(mProject, mConfiguration);
  if mBuild = nil then
  begin
    Exit;
  end;
  mPrevious := Trim(mBuild.GetValue(cDebugDcusOption, True));
  if mPrevious = '' then
  begin
    mPrevious := 'false';
  end;
  if not Confirm(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DebugUnavailableConfirmDcus, [mConfiguration,
    ExtractFileName(mProject.FileName), mPrevious, sLineBreak + sLineBreak])) then
  begin
    Exit;
  end;
  mBuild.SetValue(cDebugDcusOption, 'true');
  Say(ASay, TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DebugUnavailableDcusDone, [mConfiguration, mPrevious]));
end;

class procedure TAtlasIdeDebugUnavailableFixes.ShowDirective(const ASwitch: TAtlasUnavailableSwitch);
begin
  if ASwitch.IsDirective then
  begin
    TAtlasIdeNavigation.GoToLocation(ASwitch.FileName, ASwitch.Line, 0);
  end;
end;

class function TAtlasIdeDebugUnavailableFixes.ExecuteAction(const AName: string; AShortCut: TShortCut): Boolean;
var
  mServices: INTAServices;
  mFound: TContainedAction;
begin
  Result := False;
  if not Supports(BorlandIDEServices, INTAServices, mServices) or (mServices.ActionList = nil) then
  begin
    Exit;
  end;
  mFound := FindAction(mServices, AName, AShortCut);
  if mFound = nil then
  begin
    Exit;
  end;
  mFound.Update;
  if (mFound is TCustomAction) and not TCustomAction(mFound).Enabled then
  begin
    Exit;
  end;
  mFound.Execute;
  Result := True;
end;

end.
