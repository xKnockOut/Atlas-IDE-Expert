unit Atlas.UI.VersionControl.SettingsBranch;

// Versionsverwaltung: Branches (#1288), SVN (#1290), Externals (#1291, #1292) und Git (#1289), seit #1905 im Modul.
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
  Atlas.UI.Strings;

{ TAtlasSettingsVcsBranchPart }

procedure TAtlasSettingsVcsBranchPart.Build;
begin
  // Unterpunkt „Branches“ (#1288, x-node vcs.branches): Dialog „Branch anlegen“ vor „Beginnen“.
  AddTitle(TAtlasTextId.SettingsVcsBranchTitle);
  Host.AddSwitch('vcs.branch.confirm', TAtlasStrings.Text(TAtlasTextId.SettingsVcsBranchConfirm));
  AddWrappedLabel(36, TAtlasStrings.Text(TAtlasTextId.SettingsVcsBranchHint)).Font.Color := clGrayText;
  // Gruppe „SVN“ (#1290): Vorgaben für Ort, Quelle, Danach und Nachricht im Dialog „Branch anlegen“.
  AddTitle(TAtlasTextId.SettingsVcsBranchSvnTitle);
  Host.AddText('vcs.branch.svn.location', TAtlasStrings.Text(TAtlasTextId.SettingsVcsBranchSvnLocation));
  AddWrappedLabel(36, TAtlasStrings.Text(TAtlasTextId.SettingsVcsBranchSvnLocationHint)).Font.Color := clGrayText;
  FVcsBranchSvnSource := AddChoice('vcs.branch.svn.source', TAtlasTextId.SettingsVcsBranchSvnSource,
    [TAtlasTextId.SettingsVcsBranchSvnSourceHead, TAtlasTextId.SettingsVcsBranchSvnSourceWorkingCopy],
    TArray<string>.Create('head', 'workingCopy'));
  FVcsBranchSvnSource.Width := 260;
  FVcsBranchSvnAfter := AddChoice('vcs.branch.svn.after', TAtlasTextId.SettingsVcsBranchSvnAfter,
    [TAtlasTextId.VcsBranchAfterSwitch, TAtlasTextId.VcsBranchAfterCheckout, TAtlasTextId.VcsBranchAfterNone],
    TArray<string>.Create('switch', 'checkout', 'none'));
  FVcsBranchSvnAfter.Width := 260;
  Host.AddText('vcs.branch.svn.checkoutFolder', TAtlasStrings.Text(TAtlasTextId.SettingsVcsBranchSvnFolder));
  Host.AddText('vcs.branch.svn.message', TAtlasStrings.Text(TAtlasTextId.SettingsVcsBranchSvnMessage));
  AddWrappedLabel(36, TAtlasStrings.Text(TAtlasTextId.SettingsVcsBranchSvnMessageHint)).Font.Color := clGrayText;
  AddVcsExternalsSection;
  AddVcsGitSection;
end;

procedure TAtlasSettingsVcsBranchPart.AddVcsExternalsSection;
var
  mPanel: TWinControl;
  mCaption: TLabel;
begin
  // Unterpunkt „Externals“ (#1291, x-node vcs.externals): Vorgaben je External im Dialog „Branch anlegen“.
  AddTitle(TAtlasTextId.SettingsVcsExternalsTitle);
  FVcsExternalsOnBranch := AddChoice('vcs.externals.onBranch', TAtlasTextId.SettingsVcsExternalsOnBranch,
    [TAtlasTextId.SettingsVcsExternalsOnBranchPin, TAtlasTextId.SettingsVcsExternalsOnBranchKeep,
    TAtlasTextId.SettingsVcsExternalsOnBranchAsk], TArray<string>.Create('pin', 'keep', 'ask'));
  FVcsExternalsOnBranch.Width := 260;
  FVcsExternalsSuggest := AddChoice('vcs.externals.suggestBranch', TAtlasTextId.SettingsVcsExternalsSuggest,
    [TAtlasTextId.SettingsVcsExternalsSuggestModified, TAtlasTextId.SettingsVcsExternalsSuggestNever,
    TAtlasTextId.SettingsVcsExternalsSuggestAlways], TArray<string>.Create('modified', 'never', 'always'));
  FVcsExternalsSuggest.Width := 260;
  mPanel := AddPanel(20, [cRulesKey]);
  mCaption := TLabel.Create(FPage);
  mCaption.Parent := mPanel;
  mCaption.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsVcsExternalsRules);
  mCaption.Left := 0;
  mCaption.Top := 3;
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
  AddWrappedLabel(36, TAtlasStrings.Text(TAtlasTextId.SettingsVcsExternalsRulesHint)).Font.Color := clGrayText;
  // Arbeitskopien der Gruppe und Aktualisieren (#1292).
  Host.AddSwitch('vcs.externals.show', TAtlasStrings.Text(TAtlasTextId.SettingsVcsExternalsShow));
  FVcsExternalsUpdate := AddChoice('vcs.externals.update', TAtlasTextId.SettingsVcsExternalsUpdate,
    [TAtlasTextId.SettingsVcsExternalsUpdateWith, TAtlasTextId.SettingsVcsExternalsUpdateWithout,
    TAtlasTextId.SettingsVcsExternalsUpdateAsk], TArray<string>.Create('with', 'without', 'ask'));
  FVcsExternalsUpdate.Width := 260;
end;

procedure TAtlasSettingsVcsBranchPart.AddVcsGitSection;
begin
  // Gruppe „Git“ (#1289): Vorgaben im Dialog und für „Beginnen“ ohne Dialog; Reihenfolge wie die Werte.
  AddTitle(TAtlasTextId.SettingsVcsBranchGitTitle);
  FVcsBranchGitBase := AddChoice('vcs.branch.git.base', TAtlasTextId.SettingsVcsBranchGitBase,
    [TAtlasTextId.SettingsVcsBranchGitBaseRemote, TAtlasTextId.SettingsVcsBranchGitBaseLocal,
    TAtlasTextId.SettingsVcsBranchGitBaseCurrent], TArray<string>.Create('remote', 'local', 'current'));
  FVcsBranchGitBase.Width := 320;
  FVcsBranchGitPush := AddChoice('vcs.branch.git.push', TAtlasTextId.SettingsVcsBranchGitPush,
    [TAtlasTextId.SettingsVcsBranchGitPushLater, TAtlasTextId.SettingsVcsBranchGitPushNow],
    TArray<string>.Create('later', 'now'));
  FVcsBranchGitPush.Width := 320;
  FVcsBranchGitUncommitted := AddChoice('vcs.branch.git.uncommitted', TAtlasTextId.SettingsVcsBranchGitUncommitted,
    [TAtlasTextId.SettingsVcsBranchGitCarry, TAtlasTextId.SettingsVcsBranchGitStash,
    TAtlasTextId.SettingsVcsBranchGitAsk], TArray<string>.Create('carry', 'stash', 'ask'));
  FVcsBranchGitUncommitted.Width := 320;
  Host.AddSwitch('vcs.branch.git.worktree', TAtlasStrings.Text(TAtlasTextId.SettingsVcsBranchGitWorktree));
  Host.AddText('vcs.branch.git.worktreeFolder', TAtlasStrings.Text(TAtlasTextId.SettingsVcsBranchGitWorktreeFolder));
  AddWrappedLabel(52, TAtlasStrings.Text(TAtlasTextId.SettingsVcsBranchGitHint)).Font.Color := clGrayText;
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
    FVcsExternalsRulesError.Caption := TAtlasStrings.Fmt(TAtlasTextId.SettingsVcsExternalsRulesInvalid, [mInvalid]);
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
