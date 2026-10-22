unit Atlas.Core.Outline.NavigationOption.Tests;

// Option „Navigationssymbolleiste anzeigen“ der IDE (Bericht M3): Name unter
// den Optionsnamen finden, ähnliche Namen fürs Protokoll, Wert lesen und in
// derselben Art zurückschreiben.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasNavigationOptionTests = class
  public
    [Test]
    procedure FindsTheOptionAndPrefersShow;
    [Test]
    procedure FindsNothingWithoutNavigationBar;
    [Test]
    procedure CandidatesForTheLog;
    [Test]
    procedure ReadsBooleanNumberAndText;
    [Test]
    procedure WritesInTheSameKind;
  end;

implementation

uses
  System.Variants,
  Atlas.Core.Outline.NavigationOption;

procedure TAtlasNavigationOptionTests.FindsTheOptionAndPrefersShow;
begin
  Assert.AreEqual('ShowNavigationToolbar', TAtlasNavigationOption.Find(['AutoIndent', 'NavigationToolbarHeight',
    'ShowNavigationToolbar', 'RightMargin']), 'mit Show vor dem ersten Treffer');
  Assert.AreEqual('NavBar', TAtlasNavigationOption.Find(['AutoIndent', 'NavBar', 'NavigationBarColor']),
    'ohne Show der erste Treffer');
  Assert.AreEqual('Visible Navigation Bar', TAtlasNavigationOption.Find(['Visible Navigation Bar']),
    'Groß-/Kleinschreibung und Leerzeichen egal');
end;

procedure TAtlasNavigationOptionTests.FindsNothingWithoutNavigationBar;
begin
  Assert.AreEqual('', TAtlasNavigationOption.Find(['AutoIndent', 'ShowToolbar', 'NavigateBack']));
  Assert.AreEqual('', TAtlasNavigationOption.Find(nil));
end;

procedure TAtlasNavigationOptionTests.CandidatesForTheLog;
var
  Names: TArray<string>;
begin
  Names := TAtlasNavigationOption.Candidates(['AutoIndent', 'ShowToolbar', 'NavigateBack', 'RightMargin']);
  Assert.AreEqual(2, Integer(Length(Names)));
  Assert.AreEqual('ShowToolbar', Names[0]);
  Assert.AreEqual('NavigateBack', Names[1]);
  Assert.AreEqual(0, Integer(Length(TAtlasNavigationOption.Candidates(['AutoIndent']))));
end;

procedure TAtlasNavigationOptionTests.ReadsBooleanNumberAndText;
begin
  Assert.IsTrue(TAtlasNavigationOption.IsOn(True));
  Assert.IsFalse(TAtlasNavigationOption.IsOn(False));
  Assert.IsTrue(TAtlasNavigationOption.IsOn(1));
  Assert.IsFalse(TAtlasNavigationOption.IsOn(0));
  Assert.IsTrue(TAtlasNavigationOption.IsOn('True'));
  Assert.IsFalse(TAtlasNavigationOption.IsOn('false'));
  Assert.IsFalse(TAtlasNavigationOption.IsOn('0'));
  Assert.IsTrue(TAtlasNavigationOption.IsOn(Null), 'ohne Wert gilt die Vorgabe der IDE');
  Assert.IsTrue(TAtlasNavigationOption.IsOn(Unassigned), 'ohne Wert gilt die Vorgabe der IDE');
end;

procedure TAtlasNavigationOptionTests.WritesInTheSameKind;
var
  Value: Variant;
begin
  Value := TAtlasNavigationOption.Encode(True, False);
  Assert.IsTrue(VarIsType(Value, varBoolean), 'Boolean bleibt Boolean');
  Assert.IsFalse(Boolean(Value));
  Value := TAtlasNavigationOption.Encode(1, False);
  Assert.IsFalse(VarIsType(Value, varBoolean), 'Zahl bleibt Zahl');
  Assert.AreEqual(0, Integer(Value));
  Value := TAtlasNavigationOption.Encode('True', False);
  Assert.IsTrue(VarIsStr(Value), 'Text bleibt Text');
  Assert.AreEqual('False', VarToStr(Value));
  Value := TAtlasNavigationOption.Encode(Unassigned, True);
  Assert.IsTrue(VarIsType(Value, varBoolean), 'ohne Wert als Boolean');
  Assert.IsTrue(Boolean(Value));
end;

end.
