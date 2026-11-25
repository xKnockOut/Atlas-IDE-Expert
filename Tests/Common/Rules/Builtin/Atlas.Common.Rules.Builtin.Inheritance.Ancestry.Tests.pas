unit Atlas.Common.Rules.Builtin.Inheritance.Ancestry.Tests;

// Gemeinsame Hilfen der Vererbungsregeln: ganze Zeilen für Korrekturen, die eine Anweisung oder einen Rumpf
// entfernen (WholeLineSpan).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TInheritanceHelperTests = class
  public
    [Test]
    procedure WholeLineSpanTakesLineWithBreak;
    [Test]
    procedure WholeLineSpanRejectsSharedLine;
    [Test]
    procedure WholeLineSpanWithDocComments;
    [Test]
    procedure WholeLineSpanWithBlankAfter;
  end;

implementation

uses
  Atlas.Common.Rules.Builtin.Inheritance.Ancestry;

{ TInheritanceHelperTests }

procedure TInheritanceHelperTests.WholeLineSpanTakesLineWithBreak;
var
  mSpan: TLineSpan;
begin
  // 'x := 1;' beginnt bei Offset 5 und endet vor dem Zeilenumbruch bei 12.
  Assert.IsTrue(WholeLineSpan('a'#13#10'  x := 1;'#13#10'b', 5, 12, False, False, mSpan));
  Assert.AreEqual(3, mSpan.Start, 'ab Zeilenanfang samt Einrückung');
  Assert.AreEqual(14, mSpan.Finish, 'samt CRLF');
end;

procedure TInheritanceHelperTests.WholeLineSpanRejectsSharedLine;
var
  mSpan: TLineSpan;
begin
  Assert.IsFalse(WholeLineSpan('a := 1; x := 2;', 8, 15, False, False, mSpan), 'davor steht Code');
  Assert.IsFalse(WholeLineSpan('x := 2; a := 1;', 0, 7, False, False, mSpan), 'dahinter steht Code');
end;

procedure TInheritanceHelperTests.WholeLineSpanWithDocComments;
var
  mSpan: TLineSpan;
begin
  Assert.IsTrue(WholeLineSpan('/// Doku'#13#10'procedure P;'#13#10, 10, 22, True, False, mSpan));
  Assert.AreEqual(0, mSpan.Start, '///-Zeile gehört dazu');
  Assert.IsTrue(WholeLineSpan('/// Doku'#13#10'procedure P;'#13#10, 10, 22, False, False, mSpan));
  Assert.AreEqual(10, mSpan.Start, 'ohne ADocComments bleibt sie stehen');
end;

procedure TInheritanceHelperTests.WholeLineSpanWithBlankAfter;
var
  mSpan: TLineSpan;
begin
  Assert.IsTrue(WholeLineSpan('procedure P;'#13#10#13#10'x', 0, 12, False, True, mSpan));
  Assert.AreEqual(16, mSpan.Finish, 'Leerzeile dahinter geht mit');
  Assert.IsTrue(WholeLineSpan('procedure P;'#13#10#13#10'x', 0, 12, False, False, mSpan));
  Assert.AreEqual(14, mSpan.Finish, 'ohne ABlankAfter nur die eigene Zeile');
  Assert.IsTrue(WholeLineSpan('procedure P;'#13#10'x', 0, 12, False, True, mSpan));
  Assert.AreEqual(14, mSpan.Finish, 'keine Leerzeile dahinter');
end;

initialization
  TDUnitX.RegisterTestFixture(TInheritanceHelperTests);

end.
