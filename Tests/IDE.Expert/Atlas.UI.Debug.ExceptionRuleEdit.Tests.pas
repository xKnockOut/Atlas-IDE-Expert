unit Atlas.UI.Debug.ExceptionRuleEdit.Tests;

// Dialog „Exception-Regel“ (#838): Vorbelegung aus der Regel, Regel aus den
// Feldern, ohne Klasse oder mit ungültigem Ausdruck kein „Übernehmen“.

interface

uses
  DUnitX.TestFramework,
  Atlas.UI.Strings;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasExceptionRuleEditDialogTests = class
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
    procedure RuleFromFields;
    [Test]
    procedure ClassAndPatternRequired;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Debug.ExceptionRules,
  Atlas.UI.Debug.ExceptionRuleEdit;

function PlaceRule: TAtlasExceptionRule;
begin
  Result := TAtlasExceptionRule.Create('EConvertError', '', TAtlasMessageMatch.Matches,
    TAtlasExceptionAction.Continue);
  Result.Location := 'Bericht.Druck.*';
end;

{ TAtlasExceptionRuleEditDialogTests }

procedure TAtlasExceptionRuleEditDialogTests.Setup;
begin
  FLanguage := TAtlasStrings.Language;
  TAtlasStrings.Language := TAtlasLanguage.German;
end;

procedure TAtlasExceptionRuleEditDialogTests.TearDown;
begin
  TAtlasStrings.Language := FLanguage;
end;

procedure TAtlasExceptionRuleEditDialogTests.FillsFromRule;
var
  mDialog: TAtlasExceptionRuleEditDialog;
begin
  mDialog := TAtlasExceptionRuleEditDialog.CreateFor(nil, PlaceRule, False);
  try
    Assert.AreEqual('Exception-Regel bearbeiten', mDialog.Caption);
    mDialog.HandleNeeded;
    mDialog.Fill;
    Assert.AreEqual('EConvertError', mDialog.ClassEdit.Text);
    Assert.AreEqual('Bericht.Druck.*', mDialog.PlaceEdit.Text);
    Assert.AreEqual('', mDialog.MessageEdit.Text);
    Assert.AreEqual(3, mDialog.ActionBox.Items.Count);
    Assert.AreEqual(Ord(TAtlasExceptionAction.Continue), mDialog.ActionBox.ItemIndex);
    Assert.AreEqual('Weiterlaufen', mDialog.ActionBox.Text);
    Assert.IsTrue(mDialog.EnabledBox.Checked);
    Assert.IsTrue(mDialog.SaveButton.Enabled);
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasExceptionRuleEditDialogTests.RuleFromFields;
var
  mDialog: TAtlasExceptionRuleEditDialog;
  mRule, mStart: TAtlasExceptionRule;
begin
  mStart := PlaceRule;
  mStart.Origin := TAtlasExceptionRuleOrigin.Project;
  mDialog := TAtlasExceptionRuleEditDialog.CreateFor(nil, mStart, True);
  try
    Assert.AreEqual('Exception-Regel anlegen', mDialog.Caption);
    mDialog.HandleNeeded;
    mDialog.Fill;
    mDialog.ClassEdit.Text := ' EAbort ';
    mDialog.PlaceEdit.Text := '';
    mDialog.MessageEdit.Text := ' Abbruch ';
    mDialog.MatchBox.ItemIndex := Ord(TAtlasMessageMatch.NotMatches);
    mDialog.ActionBox.ItemIndex := Ord(TAtlasExceptionAction.Stop);
    mDialog.EnabledBox.Checked := False;
    Assert.IsTrue(mDialog.TryRule(mRule));
    Assert.AreEqual('EAbort', mRule.ExceptionClass);
    Assert.AreEqual('', mRule.Location, 'überall');
    Assert.AreEqual('Abbruch', mRule.Message);
    Assert.IsFalse(mRule.Regex);
    Assert.AreEqual(Ord(TAtlasMessageMatch.NotMatches), Ord(mRule.MessageMatch));
    Assert.AreEqual(Ord(TAtlasExceptionAction.Stop), Ord(mRule.Action));
    Assert.IsFalse(mRule.Enabled);
    Assert.AreEqual(Ord(TAtlasExceptionRuleOrigin.Project), Ord(mRule.Origin), 'Herkunft bleibt');
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasExceptionRuleEditDialogTests.ClassAndPatternRequired;
var
  mDialog: TAtlasExceptionRuleEditDialog;
  mRule: TAtlasExceptionRule;
begin
  mDialog := TAtlasExceptionRuleEditDialog.CreateFor(nil, PlaceRule, True);
  try
    mDialog.HandleNeeded;
    mDialog.Fill;
    // Der Haken prüft neu (OnChange der Felder braucht ein Fenster).
    mDialog.MessageEdit.Text := '(offen';
    mDialog.RegexBox.Checked := True;
    Assert.IsFalse(mDialog.SaveButton.Enabled, 'ungültiger Ausdruck');
    Assert.IsFalse(mDialog.TryRule(mRule));
    mDialog.MessageEdit.Text := '';
    mDialog.ClassEdit.Text := '';
    mDialog.RegexBox.Checked := False;
    Assert.IsFalse(mDialog.SaveButton.Enabled, 'ohne Klasse');
    Assert.IsFalse(mDialog.TryRule(mRule));
  finally
    mDialog.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasExceptionRuleEditDialogTests);

end.
