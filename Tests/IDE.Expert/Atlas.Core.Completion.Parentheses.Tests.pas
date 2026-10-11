unit Atlas.Core.Completion.Parentheses.Tests;

// Tests für Klammern beim Übernehmen (#430) und die Vorschau im Editor (#434).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasParenthesesTests = class
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

  [TestFixture]
  TAtlasPreviewTests = class
  public
    [Test]
    procedure ShowsRestOfName;
    [Test]
    procedure NothingWhenTextFollowsOrNoMatch;
  end;

implementation

uses
  Atlas.Core.Completion.Parentheses,
  Atlas.Core.Completion.Preview;

procedure TAtlasParenthesesTests.WantsParenthesesOnlyForRoutinesWithParameters;
begin
  Assert.IsTrue(TAtlasParentheses.Wanted(True, True, ';'));
  Assert.IsTrue(TAtlasParentheses.Wanted(True, True, #0));
  Assert.IsFalse(TAtlasParentheses.Wanted(True, False, ';'), 'Clear ohne Parameter: Delphi-Stil ohne Klammern');
  Assert.IsFalse(TAtlasParentheses.Wanted(False, True, ';'), 'keine Routine');
  Assert.IsFalse(TAtlasParentheses.Wanted(True, True, '('), 'schon eine Klammer');
end;

procedure TAtlasParenthesesTests.TypedCloseParenSkipsAutomaticOne;
var
  Paren: TAtlasAutoParen;
  RemoveAt: Integer;
begin
  // "  List.Add(|)": automatische ")" an Index 11.
  Paren := TAtlasAutoParen.Start(5, 11, '  List.Add()');
  Paren.Update('  List.Add())', RemoveAt);
  Assert.AreEqual(12, RemoveAt);
  Assert.IsFalse(Paren.Active);
end;

procedure TAtlasParenthesesTests.TypedCloseParenAfterArguments;
var
  Paren: TAtlasAutoParen;
  RemoveAt: Integer;
  Line: string;
begin
  Paren := TAtlasAutoParen.Start(5, 11, '  List.Add()');
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

procedure TAtlasParenthesesTests.FollowsEditsBeforeTheParen;
var
  Paren: TAtlasAutoParen;
  RemoveAt: Integer;
begin
  Paren := TAtlasAutoParen.Start(5, 11, '  List.Add()');
  // Einrückung vorn erweitert.
  Paren.Update('   List.Add()', RemoveAt);
  Assert.AreEqual(12, Paren.Close);
  Assert.IsTrue(Paren.Active);
  // Und wieder entfernt.
  Paren.Update('  List.Add()', RemoveAt);
  Assert.AreEqual(11, Paren.Close);
  Assert.AreEqual(-1, RemoveAt);
end;

procedure TAtlasParenthesesTests.StopsWhenParenIsDeletedOrLineReplaced;
var
  Paren: TAtlasAutoParen;
  RemoveAt: Integer;
begin
  Paren := TAtlasAutoParen.Start(5, 11, '  List.Add()');
  Paren.Update('  List.Add(', RemoveAt);
  Assert.IsFalse(Paren.Active, 'automatische Klammer gelöscht');
  Paren := TAtlasAutoParen.Start(5, 11, '  List.Add()');
  Paren.Update('  Other.Call(1, 2)', RemoveAt);
  Assert.IsFalse(Paren.Active, 'Zeile ersetzt');
  Assert.AreEqual(-1, RemoveAt);
end;

{ TAtlasPreviewTests }

procedure TAtlasPreviewTests.ShowsRestOfName;
begin
  Assert.AreEqual('Strings', TAtlasPreview.RestOf('AddStrings', 'Add', ''));
  Assert.AreEqual('Strings', TAtlasPreview.RestOf('AddStrings', 'add', '   '), 'Groß-/Kleinschreibung egal');
  Assert.AreEqual('BeginUpdate', TAtlasPreview.RestOf('BeginUpdate', '', ''));
end;

procedure TAtlasPreviewTests.NothingWhenTextFollowsOrNoMatch;
begin
  Assert.AreEqual('', TAtlasPreview.RestOf('AddStrings', 'Add', ');'), 'würde Text verdecken');
  Assert.AreEqual('', TAtlasPreview.RestOf('Count', 'Add', ''), 'passt nicht');
  Assert.AreEqual('', TAtlasPreview.RestOf('Add', 'Add', ''), 'schon vollständig');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasParenthesesTests);
  TDUnitX.RegisterTestFixture(TAtlasPreviewTests);

end.
