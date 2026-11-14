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
    /// <summary>#472: "(" hinter einem Bezeichner löst „Methode anlegen“ aus, hinter Schlüsselwörtern nicht.</summary>
    [Test]
    procedure CallOpenedAfterIdentifier;
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
  mParen: TAtlasAutoParen;
  mRemoveAt: Integer;
begin
  // "  List.Add(|)": automatische ")" an Index 11.
  mParen := TAtlasAutoParen.Start(5, 11, '  List.Add()');
  mParen.Update('  List.Add())', mRemoveAt);
  Assert.AreEqual(12, mRemoveAt);
  Assert.IsFalse(mParen.Active);
end;

procedure TAtlasParenthesesTests.TypedCloseParenAfterArguments;
var
  mParen: TAtlasAutoParen;
  mRemoveAt: Integer;
  mLine: string;
begin
  mParen := TAtlasAutoParen.Start(5, 11, '  List.Add()');
  mLine := '  List.Add()';
  // "X" tippen: Klammer wandert mit.
  Insert('X', mLine, 12);
  mParen.Update(mLine, mRemoveAt);
  Assert.AreEqual(-1, mRemoveAt);
  Assert.AreEqual(12, mParen.Close);
  // ")" hinter X: die automatische fällt weg.
  Insert(')', mLine, 13);
  mParen.Update(mLine, mRemoveAt);
  Assert.AreEqual(13, mRemoveAt);
end;

procedure TAtlasParenthesesTests.FollowsEditsBeforeTheParen;
var
  mParen: TAtlasAutoParen;
  mRemoveAt: Integer;
begin
  mParen := TAtlasAutoParen.Start(5, 11, '  List.Add()');
  // Einrückung vorn erweitert.
  mParen.Update('   List.Add()', mRemoveAt);
  Assert.AreEqual(12, mParen.Close);
  Assert.IsTrue(mParen.Active);
  // Und wieder entfernt.
  mParen.Update('  List.Add()', mRemoveAt);
  Assert.AreEqual(11, mParen.Close);
  Assert.AreEqual(-1, mRemoveAt);
end;

procedure TAtlasParenthesesTests.StopsWhenParenIsDeletedOrLineReplaced;
var
  mParen: TAtlasAutoParen;
  mRemoveAt: Integer;
begin
  mParen := TAtlasAutoParen.Start(5, 11, '  List.Add()');
  mParen.Update('  List.Add(', mRemoveAt);
  Assert.IsFalse(mParen.Active, 'automatische Klammer gelöscht');
  mParen := TAtlasAutoParen.Start(5, 11, '  List.Add()');
  mParen.Update('  Other.Call(1, 2)', mRemoveAt);
  Assert.IsFalse(mParen.Active, 'Zeile ersetzt');
  Assert.AreEqual(-1, mRemoveAt);
end;

{ TAtlasPreviewTests }

procedure TAtlasParenthesesTests.CallOpenedAfterIdentifier;
begin
  Assert.IsTrue(TAtlasParentheses.CallOpened('  Total := CalcDiscount(', 24));
  Assert.IsTrue(TAtlasParentheses.CallOpened('  Kunde.Speichern(', 18));
  // Cursor nicht direkt hinter "(", Leerzeichen davor, Schlüsselwort, Zahl, Kommentar und String.
  Assert.IsFalse(TAtlasParentheses.CallOpened('  Total := CalcDiscount(', 23));
  Assert.IsFalse(TAtlasParentheses.CallOpened('  Total := (', 12));
  Assert.IsFalse(TAtlasParentheses.CallOpened('  if (', 6));
  Assert.IsFalse(TAtlasParentheses.CallOpened('  X := 3(', 9));
  Assert.IsFalse(TAtlasParentheses.CallOpened('  // Rechne(', 12));
  Assert.IsFalse(TAtlasParentheses.CallOpened('  S := ''Rechne(', 15));
  Assert.IsFalse(TAtlasParentheses.CallOpened('(', 1));
end;

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
