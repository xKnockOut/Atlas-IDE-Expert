unit Atlas.UI.Debug.ExceptionMessageRule.Tests;

// Dialog „Regel nach Meldungstext“ (#2549): Vorschlag des Musters, Art der
// Regel, Unit, ungültiger Ausdruck sperrt „Anlegen“.

interface

uses
  DUnitX.TestFramework,
  Atlas.UI.Strings;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasExceptionMessageRuleDialogTests = class
  private
    FLanguage: TAtlasLanguage;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure SuggestsPatternAndUnit;
    [Test]
    procedure RuleFromFields;
    [Test]
    procedure InvalidRegexBlocksCreate;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Debug.ExceptionRules,
  Atlas.UI.Debug.ExceptionMessageRule;

const
  cClass = 'EKonfigFehler';
  cMessage = 'Schlüssel unbekannt: ''Farbe'' in Zeile 12';
  cUnit = 'Kunden.Import';

function Input(AMode: TAtlasMessageRuleMode): TAtlasMessageRuleInput;
begin
  Result := TAtlasMessageRuleInput.Create(cClass, cMessage, cUnit, AMode);
end;

{ TAtlasExceptionMessageRuleDialogTests }

procedure TAtlasExceptionMessageRuleDialogTests.Setup;
begin
  FLanguage := TAtlasStrings.Language;
  TAtlasStrings.Language := TAtlasLanguage.German;
end;

procedure TAtlasExceptionMessageRuleDialogTests.TearDown;
begin
  TAtlasStrings.Language := FLanguage;
end;

procedure TAtlasExceptionMessageRuleDialogTests.SuggestsPatternAndUnit;
var
  mDialog: TAtlasExceptionMessageRuleDialog;
begin
  mDialog := TAtlasExceptionMessageRuleDialog.CreateFor(nil, Input(TAtlasMessageRuleMode.StopOnly));
  try
    Assert.AreEqual('Nur bei dieser Meldung anhalten', mDialog.Caption);
    mDialog.HandleNeeded;
    mDialog.Fill;
    Assert.AreEqual('Schlüssel unbekannt: * in Zeile *', mDialog.PatternEdit.Text);
    Assert.IsFalse(mDialog.RegexBox.Checked);
    Assert.AreEqual(Ord(TAtlasMessageRuleMode.StopOnly), mDialog.ModeBox.ItemIndex);
    Assert.AreEqual(2, mDialog.UnitBox.Items.Count, 'jede Unit und die eigene');
    Assert.AreEqual(0, mDialog.UnitBox.ItemIndex, 'zuerst jede Unit');
    Assert.AreEqual(cUnit, mDialog.UnitBox.Items[1]);
    Assert.IsTrue(mDialog.CreateButton.Enabled);
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasExceptionMessageRuleDialogTests.RuleFromFields;
var
  mDialog: TAtlasExceptionMessageRuleDialog;
  mRule: TAtlasExceptionRule;
begin
  mDialog := TAtlasExceptionMessageRuleDialog.CreateFor(nil, Input(TAtlasMessageRuleMode.StopOnly));
  try
    mDialog.HandleNeeded;
    mDialog.Fill;
    Assert.IsTrue(mDialog.TryRule(mRule));
    Assert.AreEqual(cClass, mRule.ExceptionClass);
    Assert.AreEqual(Ord(TAtlasMessageMatch.NotMatches), Ord(mRule.MessageMatch), 'nur bei solchen anhalten');
    Assert.AreEqual(Ord(TAtlasExceptionAction.Log), Ord(mRule.Action));
    Assert.AreEqual('', mRule.Location);
    mDialog.ModeBox.ItemIndex := Ord(TAtlasMessageRuleMode.Ignore);
    mDialog.UnitBox.ItemIndex := 1;
    mDialog.PatternEdit.Text := '  ^Schlüssel  ';
    mDialog.RegexBox.Checked := True;
    Assert.IsTrue(mDialog.TryRule(mRule));
    Assert.AreEqual(Ord(TAtlasMessageMatch.Matches), Ord(mRule.MessageMatch), 'ignorieren');
    Assert.AreEqual('^Schlüssel', mRule.Message, 'getrimmt');
    Assert.IsTrue(mRule.Regex);
    Assert.AreEqual(cUnit, mRule.Location);
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasExceptionMessageRuleDialogTests.InvalidRegexBlocksCreate;
var
  mDialog: TAtlasExceptionMessageRuleDialog;
  mRule: TAtlasExceptionRule;
begin
  mDialog := TAtlasExceptionMessageRuleDialog.CreateFor(nil, Input(TAtlasMessageRuleMode.Ignore));
  try
    Assert.AreEqual('Meldungen wie diese ignorieren', mDialog.Caption);
    mDialog.HandleNeeded;
    mDialog.Fill;
    mDialog.PatternEdit.Text := '(offen';
    mDialog.RegexBox.Checked := True;
    Assert.IsFalse(mDialog.CreateButton.Enabled);
    Assert.IsFalse(mDialog.TryRule(mRule));
    mDialog.RegexBox.Checked := False;
    Assert.IsTrue(mDialog.CreateButton.Enabled, 'als Text gültig');
    // Der Haken prüft neu (OnChange des Felds braucht ein Fenster).
    mDialog.PatternEdit.Text := ' ';
    mDialog.RegexBox.Checked := True;
    Assert.IsFalse(mDialog.CreateButton.Enabled, 'leer');
  finally
    mDialog.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasExceptionMessageRuleDialogTests);

end.
