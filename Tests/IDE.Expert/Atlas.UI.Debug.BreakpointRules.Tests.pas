unit Atlas.UI.Debug.BreakpointRules.Tests;

// Dialog „Haltepunkt-Regeln“ (#864): Titel, Vorbelegung aus der Regel,
// Regel aus den Feldern (Auslöser, einmal, Trefferbedingung, Thread-Filter).

interface

uses
  DUnitX.TestFramework,
  Atlas.UI.Strings;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasBreakpointRuleDialogTests = class
  private
    FLanguage: TAtlasLanguage;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure FillsFromRule;
    [Test]
    procedure ChosenRuleFromFields;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Debug.BreakpointRules,
  Atlas.UI.Debug.BreakpointRules;

function Rule: TAtlasBreakpointRule;
begin
  Result := Default(TAtlasBreakpointRule);
  Result.FileName := 'C:\Src\Kunden.pas';
  Result.Line := 41;
end;

function Triggers: TAtlasRuleTriggers;
begin
  Result := [TAtlasRuleTrigger.Create('C:\Src\Haupt.pas', 9), TAtlasRuleTrigger.Create('C:\Src\Import.pas', 19)];
end;

{ TAtlasBreakpointRuleDialogTests }

procedure TAtlasBreakpointRuleDialogTests.Setup;
begin
  FLanguage := TAtlasStrings.Language;
  TAtlasStrings.Language := TAtlasLanguage.German;
end;

procedure TAtlasBreakpointRuleDialogTests.TearDown;
begin
  TAtlasStrings.Language := FLanguage;
end;

procedure TAtlasBreakpointRuleDialogTests.FillsFromRule;
var
  mRule: TAtlasBreakpointRule;
  mDialog: TAtlasBreakpointRuleDialog;
begin
  mRule := Rule;
  mRule.Depend := TAtlasDependMode.Once;
  mRule.TriggerFile := 'C:\Src\Import.pas';
  mRule.TriggerLine := 19;
  mRule.Hit := TAtlasHitMode.EveryNth;
  mRule.HitCount := 5;
  mDialog := TAtlasBreakpointRuleDialog.CreateDialog(nil, mRule, Triggers);
  try
    Assert.AreEqual('Haltepunkt-Regeln: Kunden.pas:42', mDialog.Caption);
    mDialog.HandleNeeded;
    mDialog.Fill;
    Assert.AreEqual(3, mDialog.TriggerBox.Items.Count);
    Assert.AreEqual('Import.pas:20', mDialog.TriggerBox.Text);
    Assert.AreEqual(1, mDialog.DependBox.ItemIndex);
    Assert.AreEqual(Ord(TAtlasHitMode.EveryNth), mDialog.HitBox.ItemIndex);
    Assert.AreEqual('5', mDialog.HitCountEdit.Text);
    Assert.IsFalse(mDialog.ThreadTextEdit.Enabled);
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasBreakpointRuleDialogTests.ChosenRuleFromFields;
var
  mDialog: TAtlasBreakpointRuleDialog;
  mChosen: TAtlasBreakpointRule;
begin
  mDialog := TAtlasBreakpointRuleDialog.CreateDialog(nil, Rule, Triggers);
  try
    mDialog.HandleNeeded;
    mDialog.Fill;
    Assert.AreEqual(0, mDialog.TriggerBox.ItemIndex, 'Ohne Regel: sofort aktiv');
    mDialog.TriggerBox.ItemIndex := 1;
    mDialog.HitBox.ItemIndex := Ord(TAtlasHitMode.AtLeast);
    mDialog.HitCountEdit.Text := '3';
    mDialog.ThreadBox.ItemIndex := Ord(TAtlasThreadFilter.NameContains);
    mDialog.ThreadTextEdit.Text := ' Import ';
    mChosen := mDialog.ChosenRule;
    Assert.AreEqual('C:\Src\Haupt.pas', mChosen.TriggerFile);
    Assert.AreEqual(9, mChosen.TriggerLine);
    Assert.AreEqual(Ord(TAtlasDependMode.UntilEnd), Ord(mChosen.Depend));
    Assert.AreEqual(Ord(TAtlasHitMode.AtLeast), Ord(mChosen.Hit));
    Assert.AreEqual(3, mChosen.HitCount);
    Assert.AreEqual('Import', mChosen.ThreadText);
    Assert.AreEqual(41, mChosen.Line);
  finally
    mDialog.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasBreakpointRuleDialogTests);

end.
