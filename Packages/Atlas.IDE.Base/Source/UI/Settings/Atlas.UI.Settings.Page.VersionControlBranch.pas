unit Atlas.UI.Settings.Page.VersionControlBranch;

// Versionsverwaltung: Branches (#1288), SVN (#1290), Git (#1289) und Externals.

interface

uses
  Vcl.StdCtrls,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Settings.ChoiceBox,
  Atlas.UI.Settings.Page.Host;

type
  /// <summary>Versionsverwaltung: Branches (#1288), SVN (#1290), Git (#1289) und Externals.</summary>
  TAtlasSettingsVcsBranchPart = class(TAtlasSettingsPagePart)
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
    procedure Save2(var ASettings: TAtlasPluginSettings);
    procedure AddVcsExternalsSection;
    procedure VcsExternalsRulesChange(Sender: TObject);
  public
    procedure Build;
    procedure Load(const ASettings: TAtlasPluginSettings); override;
    procedure Save(var ASettings: TAtlasPluginSettings); override;
    procedure BindMarks; override;
    property VcsBranchSvnSource: TAtlasChoiceBox read FVcsBranchSvnSource;
    property VcsBranchSvnAfter: TAtlasChoiceBox read FVcsBranchSvnAfter;
    /// <summary>Zum Testen: vcs.externals.* (#1291).</summary>
    property VcsExternalsOnBranch: TAtlasChoiceBox read FVcsExternalsOnBranch;
    property VcsExternalsSuggest: TAtlasChoiceBox read FVcsExternalsSuggest;
    property VcsExternalsRules: TMemo read FVcsExternalsRules;
    property VcsExternalsRulesError: TLabel read FVcsExternalsRulesError;
    property VcsExternalsUpdate: TAtlasChoiceBox read FVcsExternalsUpdate;
    /// <summary>Zum Testen: vcs.branch.git.* (#1289); Auswahl in der Reihenfolge der Werte im Schema.</summary>
    property VcsBranchGitBase: TAtlasChoiceBox read FVcsBranchGitBase;
    property VcsBranchGitPush: TAtlasChoiceBox read FVcsBranchGitPush;
    property VcsBranchGitUncommitted: TAtlasChoiceBox read FVcsBranchGitUncommitted;
  end;

implementation

uses
  System.Math,
  System.StrUtils,
  Vcl.Controls,
  Vcl.Graphics,
  Atlas.Core.VersionControl.Contract,
  Atlas.Core.VersionControl.BranchPlan,
  Atlas.UI.Strings;

const
  /// <summary>Werte von vcs.branch.git.base, .push und .uncommitted (#1289) in der Reihenfolge der Auswahl.
  /// </summary>
  cVcsGitBases: array[0..2] of string = ('remote', 'local', 'current');
  cVcsGitPushes: array[0..1] of string = ('later', 'now');
  cVcsGitUncommitted: array[0..2] of string = ('carry', 'stash', 'ask');

{ TAtlasSettingsVcsBranchPart }

procedure TAtlasSettingsVcsBranchPart.Build;
begin
  // Unterpunkt „Branches“ (#1288, x-node vcs.branches): Dialog „Branch anlegen“ vor „Beginnen“; die Optionen aus
  // #1289 und #1290 kommen hier dazu.
  AddTitle(TAtlasTextId.SettingsVcsBranchTitle);
  BindCheck('VcsBranchConfirm', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsVcsBranchConfirm)));
  AddWrappedLabel(36, TAtlasStrings.Text(TAtlasTextId.SettingsVcsBranchHint)).Font.Color := clGrayText;
  // Gruppe „SVN“ (#1290): Vorgaben für Ort, Quelle, Danach und Nachricht im Dialog „Branch anlegen“; Reihenfolge der
  // Auswahl wie die Werte von vcs.branch.svn.source bzw. .after.
  AddTitle(TAtlasTextId.SettingsVcsBranchSvnTitle);
  BindText('VcsBranchSvnLocation', AddTextLine(TAtlasStrings.Text(TAtlasTextId.SettingsVcsBranchSvnLocation)));
  AddWrappedLabel(36, TAtlasStrings.Text(TAtlasTextId.SettingsVcsBranchSvnLocationHint)).Font.Color := clGrayText;
  FVcsBranchSvnSource := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsVcsBranchSvnSource),
    [TAtlasStrings.Text(TAtlasTextId.SettingsVcsBranchSvnSourceHead),
    TAtlasStrings.Text(TAtlasTextId.SettingsVcsBranchSvnSourceWorkingCopy)]);
  FVcsBranchSvnSource.Width := 260;
  FVcsBranchSvnAfter := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsVcsBranchSvnAfter),
    [TAtlasStrings.Text(TAtlasTextId.VcsBranchAfterSwitch), TAtlasStrings.Text(TAtlasTextId.VcsBranchAfterCheckout),
    TAtlasStrings.Text(TAtlasTextId.VcsBranchAfterNone)]);
  FVcsBranchSvnAfter.Width := 260;
  BindText('VcsBranchSvnCheckoutFolder', AddTextLine(TAtlasStrings.Text(TAtlasTextId.SettingsVcsBranchSvnFolder)));
  BindText('VcsBranchSvnMessage', AddTextLine(TAtlasStrings.Text(TAtlasTextId.SettingsVcsBranchSvnMessage)));
  AddWrappedLabel(36, TAtlasStrings.Text(TAtlasTextId.SettingsVcsBranchSvnMessageHint)).Font.Color := clGrayText;
  AddVcsExternalsSection;
end;

procedure TAtlasSettingsVcsBranchPart.AddVcsExternalsSection;
var
  mPanel: TWinControl;
  mCaption: TLabel;
begin
  // Unterpunkt „Externals“ (#1291, x-node vcs.externals): Vorgaben je External im Dialog „Branch anlegen“;
  // Reihenfolge der Auswahl wie die Werte von vcs.externals.onBranch bzw. .suggestBranch.
  AddTitle(TAtlasTextId.SettingsVcsExternalsTitle);
  FVcsExternalsOnBranch := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsVcsExternalsOnBranch),
    [TAtlasStrings.Text(TAtlasTextId.SettingsVcsExternalsOnBranchPin),
    TAtlasStrings.Text(TAtlasTextId.SettingsVcsExternalsOnBranchKeep),
    TAtlasStrings.Text(TAtlasTextId.SettingsVcsExternalsOnBranchAsk)]);
  FVcsExternalsOnBranch.Width := 260;
  FVcsExternalsSuggest := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsVcsExternalsSuggest),
    [TAtlasStrings.Text(TAtlasTextId.SettingsVcsExternalsSuggestModified),
    TAtlasStrings.Text(TAtlasTextId.SettingsVcsExternalsSuggestNever),
    TAtlasStrings.Text(TAtlasTextId.SettingsVcsExternalsSuggestAlways)]);
  FVcsExternalsSuggest.Width := 260;
  mPanel := AddPanel(20);
  mCaption := TLabel.Create(FPage);
  mCaption.Parent := mPanel;
  mCaption.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsVcsExternalsRules);
  mCaption.Left := 0;
  mCaption.Top := 3;
  mPanel := AddPanel(84);
  FVcsExternalsRules := TMemo.Create(FPage);
  FVcsExternalsRules.Parent := mPanel;
  FVcsExternalsRules.SetBounds(0, 1, 466, 80);
  FVcsExternalsRules.Anchors := [akLeft, akTop, akRight];
  FVcsExternalsRules.ScrollBars := ssVertical;
  FVcsExternalsRules.WordWrap := False;
  FVcsExternalsRules.OnChange := VcsExternalsRulesChange;
  FVcsExternalsRulesError := AddWrappedLabel(20, '');
  FVcsExternalsRulesError.Font.Color := clRed;
  AddWrappedLabel(36, TAtlasStrings.Text(TAtlasTextId.SettingsVcsExternalsRulesHint)).Font.Color := clGrayText;
  // Arbeitskopien der Gruppe und Aktualisieren (#1292); Reihenfolge wie vcs.externals.update.
  BindCheck('VcsExternalsShow', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsVcsExternalsShow)));
  FVcsExternalsUpdate := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsVcsExternalsUpdate),
    [TAtlasStrings.Text(TAtlasTextId.SettingsVcsExternalsUpdateWith),
    TAtlasStrings.Text(TAtlasTextId.SettingsVcsExternalsUpdateWithout),
    TAtlasStrings.Text(TAtlasTextId.SettingsVcsExternalsUpdateAsk)]);
  FVcsExternalsUpdate.Width := 260;
  // Gruppe „Git“ (#1289): Vorgaben im Dialog und für „Beginnen“ ohne Dialog; Reihenfolge wie die Werte.
  AddTitle(TAtlasTextId.SettingsVcsBranchGitTitle);
  FVcsBranchGitBase := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsVcsBranchGitBase),
    [TAtlasStrings.Text(TAtlasTextId.SettingsVcsBranchGitBaseRemote),
    TAtlasStrings.Text(TAtlasTextId.SettingsVcsBranchGitBaseLocal),
    TAtlasStrings.Text(TAtlasTextId.SettingsVcsBranchGitBaseCurrent)]);
  FVcsBranchGitBase.Width := 320;
  FVcsBranchGitPush := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsVcsBranchGitPush),
    [TAtlasStrings.Text(TAtlasTextId.SettingsVcsBranchGitPushLater),
    TAtlasStrings.Text(TAtlasTextId.SettingsVcsBranchGitPushNow)]);
  FVcsBranchGitPush.Width := 320;
  FVcsBranchGitUncommitted := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsVcsBranchGitUncommitted),
    [TAtlasStrings.Text(TAtlasTextId.SettingsVcsBranchGitCarry),
    TAtlasStrings.Text(TAtlasTextId.SettingsVcsBranchGitStash),
    TAtlasStrings.Text(TAtlasTextId.SettingsVcsBranchGitAsk)]);
  FVcsBranchGitUncommitted.Width := 320;
  BindCheck('VcsBranchGitWorktree', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsVcsBranchGitWorktree)));
  BindText('VcsBranchGitWorktreeFolder',
    AddTextLine(TAtlasStrings.Text(TAtlasTextId.SettingsVcsBranchGitWorktreeFolder)));
  AddWrappedLabel(52, TAtlasStrings.Text(TAtlasTextId.SettingsVcsBranchGitHint)).Font.Color := clGrayText;
end;

procedure TAtlasSettingsVcsBranchPart.VcsExternalsRulesChange(Sender: TObject);
var
  mRules: TArray<TAtlasVcsExternalRule>;
  mInvalid: string;
begin
  // Ungültige Zeile: Hinweis; gespeichert bleiben dann die bisherigen Regeln (SaveTo).
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

procedure TAtlasSettingsVcsBranchPart.BindMarks;
begin
  FPage.Marks.Bind(FVcsBranchSvnSource, ['VcsBranchSvnSource']);
  FPage.Marks.Bind(FVcsBranchSvnAfter, ['VcsBranchSvnAfter']);
  FPage.Marks.Bind(FVcsExternalsOnBranch, ['VcsExternalsOnBranch']);
  FPage.Marks.Bind(FVcsExternalsSuggest, ['VcsExternalsSuggestBranch']);
  FPage.Marks.Bind(FVcsExternalsRules, ['VcsExternalsRules']);
  FPage.Marks.Bind(FVcsExternalsUpdate, ['VcsExternalsUpdate']);
  FPage.Marks.Bind(FVcsBranchGitBase, ['VcsBranchGitBase']);
  FPage.Marks.Bind(FVcsBranchGitPush, ['VcsBranchGitPush']);
  FPage.Marks.Bind(FVcsBranchGitUncommitted, ['VcsBranchGitUncommitted']);
end;

procedure TAtlasSettingsVcsBranchPart.Load(const ASettings: TAtlasPluginSettings);
begin
  FVcsBranchSvnSource.Choice := Ord(AtlasVcsSvnSourceOf(ASettings.VcsBranchSvnSource));
  FVcsBranchSvnAfter.Choice := Ord(AtlasVcsSvnAfterOf(ASettings.VcsBranchSvnAfter));
  FVcsExternalsOnBranch.Choice := Max(0, IndexText(ASettings.VcsExternalsOnBranch, ['pin', 'keep', 'ask']));
  FVcsExternalsSuggest.Choice := Max(0, IndexText(ASettings.VcsExternalsSuggestBranch,
    ['modified', 'never', 'always']));
  FVcsExternalsRules.Text :=
    TAtlasVcsExternalRules.RulesText(TAtlasVcsExternalRules.RulesOf(ASettings.VcsExternalsRules));
  FVcsExternalsUpdate.Choice := Ord(AtlasVcsExternalsUpdateOf(ASettings.VcsExternalsUpdate));
  FVcsBranchGitBase.Choice := Max(0, IndexText(ASettings.VcsBranchGitBase, cVcsGitBases));
  FVcsBranchGitPush.Choice := Max(0, IndexText(ASettings.VcsBranchGitPush, cVcsGitPushes));
  FVcsBranchGitUncommitted.Choice := Max(0, IndexText(ASettings.VcsBranchGitUncommitted, cVcsGitUncommitted));
end;

procedure TAtlasSettingsVcsBranchPart.Save(var ASettings: TAtlasPluginSettings);
var
  mRules: TArray<TAtlasVcsExternalRule>;
  mInvalid: string;
begin
  if FVcsBranchSvnSource.Choice = Ord(TAtlasVcsSvnSource.WorkingCopy) then
  begin
    ASettings.VcsBranchSvnSource := 'workingCopy';
  end
  else
  begin
    ASettings.VcsBranchSvnSource := 'head';
  end;
  case FVcsBranchSvnAfter.Choice of
    Ord(TAtlasVcsSvnAfter.Checkout):
      ASettings.VcsBranchSvnAfter := 'checkout';
    Ord(TAtlasVcsSvnAfter.None):
      ASettings.VcsBranchSvnAfter := 'none';
  else
    ASettings.VcsBranchSvnAfter := 'switch';
  end;
  case FVcsExternalsOnBranch.Choice of
    1:
      ASettings.VcsExternalsOnBranch := 'keep';
    2:
      ASettings.VcsExternalsOnBranch := 'ask';
  else
    ASettings.VcsExternalsOnBranch := 'pin';
  end;
  case FVcsExternalsSuggest.Choice of
    1:
      ASettings.VcsExternalsSuggestBranch := 'never';
    2:
      ASettings.VcsExternalsSuggestBranch := 'always';
  else
    ASettings.VcsExternalsSuggestBranch := 'modified';
  end;
  // Mit ungültiger Zeile bleiben die bisherigen Regeln (Hinweis unter dem Feld).
  if TAtlasVcsExternalRules.RulesOfText(FVcsExternalsRules.Text, mRules, mInvalid) then
  begin
    ASettings.VcsExternalsRules := TAtlasVcsExternalRules.RulesJson(mRules);
  end;
  case FVcsExternalsUpdate.Choice of
    1:
      ASettings.VcsExternalsUpdate := 'without';
    2:
      ASettings.VcsExternalsUpdate := 'ask';
  else
    ASettings.VcsExternalsUpdate := 'with';
  end;
  Save2(ASettings);
end;

procedure TAtlasSettingsVcsBranchPart.Save2(var ASettings: TAtlasPluginSettings);
begin
  ASettings.VcsBranchGitBase := cVcsGitBases[EnsureRange(FVcsBranchGitBase.Choice, 0, High(cVcsGitBases))];
  ASettings.VcsBranchGitPush := cVcsGitPushes[EnsureRange(FVcsBranchGitPush.Choice, 0, High(cVcsGitPushes))];
  ASettings.VcsBranchGitUncommitted := cVcsGitUncommitted[EnsureRange(FVcsBranchGitUncommitted.Choice, 0,
    High(cVcsGitUncommitted))];
end;

end.
