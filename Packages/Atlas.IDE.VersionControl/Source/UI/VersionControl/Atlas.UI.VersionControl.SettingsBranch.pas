unit Atlas.UI.VersionControl.SettingsBranch;

// Versionsverwaltung: Branches (#1288), SVN (#1290), Externals (#1291, #1292) und Git (#1289).
// Schalter, Texte und Auswahlen sind gebundene Felder der Seite (Werte wie im Schema); die Regeln für Externals
// (vcs.externals.rules) liest und schreibt der Teil selbst.

interface

uses
  Vcl.StdCtrls,
  Atlas.Core.Settings.Contract,
  Atlas.UI.Settings.ChoiceBox,
  Atlas.UI.VersionControl.SettingsPart;

type
  TAtlasSettingsVcsBranchPart = class(TAtlasVcsSettingsPart)
  public const
    cRulesKey = 'vcs.externals.rules';
  private
    FVcsBranchSvnSource: TAtlasChoiceBox;
    FVcsBranchSvnAfter: TAtlasChoiceBox;
    FVcsExternalsOnBranch: TAtlasChoiceBox;
    FVcsExternalsSuggest: TAtlasChoiceBox;
    FVcsExternalsRules: TMemo;
    FVcsExternalsRulesError: TLabel;
    FVcsExternalsUpdate: TAtlasChoiceBox;
    FVcsBranchGitBase: TAtlasChoiceBox;
    FVcsBranchGitPush: TAtlasChoiceBox;
    FVcsBranchGitUncommitted: TAtlasChoiceBox;
    procedure AddVcsExternalsSection;
    procedure AddVcsGitSection;
    procedure VcsExternalsRulesChange(Sender: TObject);
  public
    procedure Build; override;
    procedure Load(const AValues: IAtlasSettingsValues); override;
    procedure Save(const AValues: IAtlasSettingsValues); override;
    procedure Attached(APage: TAtlasVcsSettingsOwner); override;
    property VcsBranchSvnSource: TAtlasChoiceBox read FVcsBranchSvnSource;
    property VcsBranchSvnAfter: TAtlasChoiceBox read FVcsBranchSvnAfter;
    property VcsExternalsOnBranch: TAtlasChoiceBox read FVcsExternalsOnBranch;
    property VcsExternalsSuggest: TAtlasChoiceBox read FVcsExternalsSuggest;
    property VcsExternalsRules: TMemo read FVcsExternalsRules;
    property VcsExternalsRulesError: TLabel read FVcsExternalsRulesError;
    property VcsExternalsUpdate: TAtlasChoiceBox read FVcsExternalsUpdate;
    property VcsBranchGitBase: TAtlasChoiceBox read FVcsBranchGitBase;
    property VcsBranchGitPush: TAtlasChoiceBox read FVcsBranchGitPush;
    property VcsBranchGitUncommitted: TAtlasChoiceBox read FVcsBranchGitUncommitted;
  end;

implementation

uses
  Vcl.Controls,
  Vcl.Graphics,
  Atlas.Core.VersionControl.Contract,
  Atlas.Core.VersionControl.BranchPlan,
  Atlas.UI.Strings,
  Atlas.UI.VersionControl.Strings;

{ TAtlasSettingsVcsBranchPart }

procedure TAtlasSettingsVcsBranchPart.Build;
begin
  // Unterpunkt „Branches“ (#1288, x-node vcs.branches): Dialog „Branch anlegen“ vor „Beginnen“.
  AddTitle(TAtlasVcsTextId.SettingsVcsBranchTitle);
  Host.AddSwitch('vcs.branch.confirm', TAtlasVcsStrings.Text(TAtlasVcsTextId.SettingsVcsBranchConfirm));
  AddWrappedLabel(36, TAtlasVcsStrings.Text(TAtlasVcsTextId.SettingsVcsBranchHint)).Font.Color := clGrayText;
  // Gruppe „SVN“ (#1290): Vorgaben für Ort, Quelle, Danach und Nachricht im Dialog „Branch anlegen“.
  AddTitle(TAtlasVcsTextId.SettingsVcsBranchSvnTitle);
  Host.AddText('vcs.branch.svn.location', TAtlasVcsStrings.Text(TAtlasVcsTextId.SettingsVcsBranchSvnLocation));
  AddWrappedLabel(36, TAtlasVcsStrings.Text(TAtlasVcsTextId.SettingsVcsBranchSvnLocationHint)).Font.Color := clGrayText;
  FVcsBranchSvnSource := AddChoice('vcs.branch.svn.source', TAtlasVcsTextId.SettingsVcsBranchSvnSource,
    [TAtlasVcsTextId.SettingsVcsBranchSvnSourceHead, TAtlasVcsTextId.SettingsVcsBranchSvnSourceWorkingCopy],
    TArray<string>.Create('head', 'workingCopy'));
  FVcsBranchSvnSource.Width := FVcsBranchSvnSource.ScaleValue(260);
  FVcsBranchSvnAfter := AddChoice('vcs.branch.svn.after', TAtlasVcsTextId.SettingsVcsBranchSvnAfter,
    [TAtlasVcsTextId.VcsBranchAfterSwitch, TAtlasVcsTextId.VcsBranchAfterCheckout, TAtlasVcsTextId.VcsBranchAfterNone],
    TArray<string>.Create('switch', 'checkout', 'none'));
  FVcsBranchSvnAfter.Width := FVcsBranchSvnAfter.ScaleValue(260);
  Host.AddText('vcs.branch.svn.checkoutFolder', TAtlasVcsStrings.Text(TAtlasVcsTextId.SettingsVcsBranchSvnFolder));
  Host.AddText('vcs.branch.svn.message', TAtlasVcsStrings.Text(TAtlasVcsTextId.SettingsVcsBranchSvnMessage));
  AddWrappedLabel(36, TAtlasVcsStrings.Text(TAtlasVcsTextId.SettingsVcsBranchSvnMessageHint)).Font.Color := clGrayText;
  AddVcsExternalsSection;
  AddVcsGitSection;
end;

procedure TAtlasSettingsVcsBranchPart.AddVcsExternalsSection;
var
  mPanel: TWinControl;
  mCaption: TLabel;
begin
  // Unterpunkt „Externals“ (#1291, x-node vcs.externals): Vorgaben je External im Dialog „Branch anlegen“.
  AddTitle(TAtlasVcsTextId.SettingsVcsExternalsTitle);
  FVcsExternalsOnBranch := AddChoice('vcs.externals.onBranch', TAtlasVcsTextId.SettingsVcsExternalsOnBranch,
    [TAtlasVcsTextId.SettingsVcsExternalsOnBranchPin, TAtlasVcsTextId.SettingsVcsExternalsOnBranchKeep,
    TAtlasVcsTextId.SettingsVcsExternalsOnBranchAsk], TArray<string>.Create('pin', 'keep', 'ask'));
  FVcsExternalsOnBranch.Width := FVcsExternalsOnBranch.ScaleValue(260);
  FVcsExternalsSuggest := AddChoice('vcs.externals.suggestBranch', TAtlasVcsTextId.SettingsVcsExternalsSuggest,
    [TAtlasVcsTextId.SettingsVcsExternalsSuggestModified, TAtlasVcsTextId.SettingsVcsExternalsSuggestNever,
    TAtlasVcsTextId.SettingsVcsExternalsSuggestAlways], TArray<string>.Create('modified', 'never', 'always'));
  FVcsExternalsSuggest.Width := FVcsExternalsSuggest.ScaleValue(260);
  mPanel := AddPanel(20, [cRulesKey]);
  mCaption := TLabel.Create(FPage);
  mCaption.Parent := mPanel;
  mCaption.Caption := TAtlasVcsStrings.Text(TAtlasVcsTextId.SettingsVcsExternalsRules);
  mCaption.Left := 0;
  mCaption.Top := mCaption.ScaleValue(3);
  mPanel := AddPanel(84, [cRulesKey]);
  FVcsExternalsRules := TMemo.Create(FPage);
  FVcsExternalsRules.Parent := mPanel;
  FVcsExternalsRules.SetBounds(0, 1, 466, 80);
  FVcsExternalsRules.Anchors := [akLeft, akTop, akRight];
  FVcsExternalsRules.ScrollBars := ssVertical;
  FVcsExternalsRules.WordWrap := False;
  FVcsExternalsRules.OnChange := VcsExternalsRulesChange;
  FVcsExternalsRulesError := AddWrappedLabel(20, '');
  FVcsExternalsRulesError.Font.Color := clRed;
  Attach(FVcsExternalsRulesError.Parent, mPanel);
  AddWrappedLabel(36, TAtlasVcsStrings.Text(TAtlasVcsTextId.SettingsVcsExternalsRulesHint)).Font.Color := clGrayText;
  // Arbeitskopien der Gruppe und Aktualisieren (#1292).
  Host.AddSwitch('vcs.externals.show', TAtlasVcsStrings.Text(TAtlasVcsTextId.SettingsVcsExternalsShow));
  FVcsExternalsUpdate := AddChoice('vcs.externals.update', TAtlasVcsTextId.SettingsVcsExternalsUpdate,
    [TAtlasVcsTextId.SettingsVcsExternalsUpdateWith, TAtlasVcsTextId.SettingsVcsExternalsUpdateWithout,
    TAtlasVcsTextId.SettingsVcsExternalsUpdateAsk], TArray<string>.Create('with', 'without', 'ask'));
  FVcsExternalsUpdate.Width := FVcsExternalsUpdate.ScaleValue(260);
end;

procedure TAtlasSettingsVcsBranchPart.AddVcsGitSection;
begin
  // Gruppe „Git“ (#1289): Vorgaben im Dialog und für „Beginnen“ ohne Dialog; Reihenfolge wie die Werte.
  AddTitle(TAtlasVcsTextId.SettingsVcsBranchGitTitle);
  FVcsBranchGitBase := AddChoice('vcs.branch.git.base', TAtlasVcsTextId.SettingsVcsBranchGitBase,
    [TAtlasVcsTextId.SettingsVcsBranchGitBaseRemote, TAtlasVcsTextId.SettingsVcsBranchGitBaseLocal,
    TAtlasVcsTextId.SettingsVcsBranchGitBaseCurrent], TArray<string>.Create('remote', 'local', 'current'));
  FVcsBranchGitBase.Width := FVcsBranchGitBase.ScaleValue(320);
  FVcsBranchGitPush := AddChoice('vcs.branch.git.push', TAtlasVcsTextId.SettingsVcsBranchGitPush,
    [TAtlasVcsTextId.SettingsVcsBranchGitPushLater, TAtlasVcsTextId.SettingsVcsBranchGitPushNow],
    TArray<string>.Create('later', 'now'));
  FVcsBranchGitPush.Width := FVcsBranchGitPush.ScaleValue(320);
  FVcsBranchGitUncommitted := AddChoice('vcs.branch.git.uncommitted', TAtlasVcsTextId.SettingsVcsBranchGitUncommitted,
    [TAtlasVcsTextId.SettingsVcsBranchGitCarry, TAtlasVcsTextId.SettingsVcsBranchGitStash,
    TAtlasVcsTextId.SettingsVcsBranchGitAsk], TArray<string>.Create('carry', 'stash', 'ask'));
  FVcsBranchGitUncommitted.Width := FVcsBranchGitUncommitted.ScaleValue(320);
  Host.AddSwitch('vcs.branch.git.worktree', TAtlasVcsStrings.Text(TAtlasVcsTextId.SettingsVcsBranchGitWorktree));
  Host.AddText('vcs.branch.git.worktreeFolder', TAtlasVcsStrings.Text(TAtlasVcsTextId.SettingsVcsBranchGitWorktreeFolder));
  AddWrappedLabel(52, TAtlasVcsStrings.Text(TAtlasVcsTextId.SettingsVcsBranchGitHint)).Font.Color := clGrayText;
end;

procedure TAtlasSettingsVcsBranchPart.VcsExternalsRulesChange(Sender: TObject);
var
  mRules: TArray<TAtlasVcsExternalRule>;
  mInvalid: string;
begin
  if FVcsExternalsRulesError = nil then
  begin
    Exit;
  end;
  // Ungültige Zeile: Hinweis; gespeichert bleiben dann die bisherigen Regeln (Save).
  if TAtlasVcsExternalRules.RulesOfText(FVcsExternalsRules.Text, mRules, mInvalid) then
  begin
    FVcsExternalsRulesError.Caption := '';
  end
  else
  begin
    FVcsExternalsRulesError.Caption := TAtlasVcsStrings.Fmt(TAtlasVcsTextId.SettingsVcsExternalsRulesInvalid, [mInvalid]);
  end;
  FPage.RefreshMarks;
end;

procedure TAtlasSettingsVcsBranchPart.Load(const AValues: IAtlasSettingsValues);
begin
  if FVcsExternalsRules = nil then
  begin
    Exit;
  end;
  FVcsExternalsRules.Text :=
    TAtlasVcsExternalRules.RulesText(TAtlasVcsExternalRules.RulesOf(AValues.ReadString(cRulesKey)));
end;

procedure TAtlasSettingsVcsBranchPart.Save(const AValues: IAtlasSettingsValues);
var
  mRules: TArray<TAtlasVcsExternalRule>;
  mInvalid: string;
begin
  // Mit ungültiger Zeile bleiben die bisherigen Regeln (Hinweis unter dem Feld).
  if (FVcsExternalsRules <> nil) and TAtlasVcsExternalRules.RulesOfText(FVcsExternalsRules.Text, mRules,
    mInvalid) then
  begin
    AValues.WriteString(cRulesKey, TAtlasVcsExternalRules.RulesJson(mRules));
  end;
end;

procedure TAtlasSettingsVcsBranchPart.Attached(APage: TAtlasVcsSettingsOwner);
begin
  inherited Attached(APage);
  if APage = nil then
  begin
    FVcsBranchSvnSource := nil;
    FVcsBranchSvnAfter := nil;
    FVcsExternalsOnBranch := nil;
    FVcsExternalsSuggest := nil;
    FVcsExternalsRules := nil;
    FVcsExternalsRulesError := nil;
    FVcsExternalsUpdate := nil;
    FVcsBranchGitBase := nil;
    FVcsBranchGitPush := nil;
    FVcsBranchGitUncommitted := nil;
  end;
end;

end.
