unit Argus.Core.Completion.Parentheses.Tests;

// Tests für Klammern beim Übernehmen (#430).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TArgusParenthesesTests = class
  public
    [Test]
    procedure WantsParenthesesOnlyForRoutinesWithParameters;
    [Test]
    procedure TypedCloseParenSkipsAutomaticOne;
    [Test]
    procedure TypedCloseParenAfterArguments;
    [Test]
    procedure FollowsEditsBeforeTheParen;
    [Test]
    procedure StopsWhenParenIsDeletedOrLineReplaced;
  end;

implementation

uses
  Argus.Core.Completion.Parentheses;

procedure TArgusParenthesesTests.WantsParenthesesOnlyForRoutinesWithParameters;
begin
  Assert.IsTrue(TArgusParentheses.Wanted(True, True, ';'));
  Assert.IsTrue(TArgusParentheses.Wanted(True, True, #0));
  Assert.IsFalse(TArgusParentheses.Wanted(True, False, ';'), 'Clear ohne Parameter: Delphi-Stil ohne Klammern');
  Assert.IsFalse(TArgusParentheses.Wanted(False, True, ';'), 'keine Routine');
  Assert.IsFalse(TArgusParentheses.Wanted(True, True, '('), 'schon eine Klammer');
end;

procedure TArgusParenthesesTests.TypedCloseParenSkipsAutomaticOne;
var
  Paren: TArgusAutoParen;
  RemoveAt: Integer;
begin
  // "  List.Add(|)": automatische ")" an Index 11.
  Paren := TArgusAutoParen.Start(5, 11, '  List.Add()');
  Paren.Update('  List.Add())', RemoveAt);
  Assert.AreEqual(12, RemoveAt);
  Assert.IsFalse(Paren.Active);
end;

procedure TArgusParenthesesTests.TypedCloseParenAfterArguments;
var
  Paren: TArgusAutoParen;
  RemoveAt: Integer;
  Line: string;
begin
  Paren := TArgusAutoParen.Start(5, 11, '  List.Add()');
  Line := '  List.Add()';
  // "X" tippen: Klammer wandert mit.
  Insert('X', Line, 12);
  Paren.Update(Line, RemoveAt);
  Assert.AreEqual(-1, RemoveAt);
  Assert.AreEqual(12, Paren.Close);
  // ")" hinter X: die automatische fällt weg.
  Insert(')', Line, 13);
  Paren.Update(Line, RemoveAt);
  Assert.AreEqual(13, RemoveAt);
end;

procedure TArgusParenthesesTests.FollowsEditsBeforeTheParen;
var
  Paren: TArgusAutoParen;
  RemoveAt: Integer;
begin
  Paren := TArgusAutoParen.Start(5, 11, '  List.Add()');
  // Einrückung vorn erweitert.
  Paren.Update('   List.Add()', RemoveAt);
  Assert.AreEqual(12, Paren.Close);
  Assert.IsTrue(Paren.Active);
  // Und wieder entfernt.
  Paren.Update('  List.Add()', RemoveAt);
  Assert.AreEqual(11, Paren.Close);
  Assert.AreEqual(-1, RemoveAt);
end;

procedure TArgusParenthesesTests.StopsWhenParenIsDeletedOrLineReplaced;
var
  Paren: TArgusAutoParen;
  RemoveAt: Integer;
begin
  Paren := TArgusAutoParen.Start(5, 11, '  List.Add()');
  Paren.Update('  List.Add(', RemoveAt);
  Assert.IsFalse(Paren.Active, 'automatische Klammer gelöscht');
  Paren := TArgusAutoParen.Start(5, 11, '  List.Add()');
  Paren.Update('  Other.Call(1, 2)', RemoveAt);
  Assert.IsFalse(Paren.Active, 'Zeile ersetzt');
  Assert.AreEqual(-1, RemoveAt);
end;

initialization
  TDUnitX.RegisterTestFixture(TArgusParenthesesTests);

end.
