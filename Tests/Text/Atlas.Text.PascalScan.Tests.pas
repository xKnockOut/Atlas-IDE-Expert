unit Atlas.Text.PascalScan.Tests;

// Tests der Suche außerhalb von Kommentaren und Zeichenketten: jede Art
// Kommentar, Anweisung und Zeichenkette mit und ohne Abschluss, Wortgrenzen
// (qualifizierte Namen, &-Bezeichner, Unicode), und dass jede Suche auch bei
// offenen Kommentaren endet.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TPascalScanTests = class
  public
    [Test]
    procedure SkipsEveryKindOfComment;
    [Test]
    procedure SkipsStrings;
    [Test]
    procedure WithoutNoiseStaysPut;
    [Test]
    procedure OpenNoiseReachesEnd;
    [Test]
    procedure ParenStarParenIsOpen;
    [Test]
    procedure IsClosedFindsEveryOpenKind;
    [Test]
    procedure FindWordSkipsNoise;
    [Test]
    procedure FindWordWholeWordsOnly;
    [Test]
    procedure FindAfterOpenCommentEnds;
    [Test]
    procedure FindCharSkipsNoise;
  end;

implementation

uses
  Atlas.Text.PascalScan;

const
  cBreak = #13#10;

{ TPascalScanTests }

procedure TPascalScanTests.SkipsEveryKindOfComment;
begin
  Assert.AreEqual(5, TPascalScan.SkipNoise('{ab}x', 1));
  Assert.AreEqual(7, TPascalScan.SkipNoise('(*ab*)x', 1));
  Assert.AreEqual(6, TPascalScan.SkipNoise('{$R+}x', 1));
  Assert.AreEqual(8, TPascalScan.SkipNoise('(*$I-*)x', 1));
  Assert.AreEqual(5, TPascalScan.SkipNoise('//ab' + cBreak + 'x', 1));
  Assert.AreEqual(4, TPascalScan.SkipNoise('x{}y', 2));
end;

procedure TPascalScanTests.SkipsStrings;
var
  mMulti: string;
begin
  Assert.AreEqual(5, TPascalScan.SkipNoise('''ab''x', 1));
  // '' in einer Zeichenkette: zwei Zeichenketten hintereinander.
  Assert.AreEqual(3, TPascalScan.SkipNoise('''''x''', 1));
  mMulti := 'x := ''''''' + cBreak + '  a } b' + cBreak + '  ''''''' + ';';
  Assert.AreEqual(Integer(Length(mMulti)), TPascalScan.SkipNoise(mMulti, 6));
end;

procedure TPascalScanTests.WithoutNoiseStaysPut;
begin
  Assert.AreEqual(1, TPascalScan.SkipNoise('abc', 1));
  Assert.AreEqual(2, TPascalScan.SkipNoise('a(b', 2));
  Assert.AreEqual(2, TPascalScan.SkipNoise('a/b', 2));
  Assert.AreEqual(4, TPascalScan.SkipNoise('abc', 4));
end;

procedure TPascalScanTests.OpenNoiseReachesEnd;
begin
  Assert.AreEqual(5, TPascalScan.SkipNoise('{abc', 1));
  Assert.AreEqual(6, TPascalScan.SkipNoise('(*abc', 1));
  Assert.AreEqual(4, TPascalScan.SkipNoise('//a', 1));
  // Eine Zeichenkette endet spätestens am Zeilenende.
  Assert.AreEqual(4, TPascalScan.SkipNoise('''ab' + cBreak + 'c''', 1));
end;

procedure TPascalScanTests.ParenStarParenIsOpen;
begin
  Assert.AreEqual(4, TPascalScan.SkipNoise('(*)', 1));
  Assert.IsFalse(TPascalScan.IsClosed('program X; (*) uses A;'));
  Assert.AreEqual(5, TPascalScan.SkipNoise('(**)', 1));
end;

procedure TPascalScanTests.IsClosedFindsEveryOpenKind;
begin
  Assert.IsTrue(TPascalScan.IsClosed(''));
  Assert.IsTrue(TPascalScan.IsClosed('program X; { a } (* b *) // c' + cBreak + 'begin Writeln(''d''); end.'));
  Assert.IsTrue(TPascalScan.IsClosed('a // offen bis Zeilenende'));
  Assert.IsFalse(TPascalScan.IsClosed('program X; { a'));
  Assert.IsFalse(TPascalScan.IsClosed('program X; (* a'));
  Assert.IsFalse(TPascalScan.IsClosed('program X; ''a' + cBreak + 'b'';'));
  Assert.IsFalse(TPascalScan.IsClosed('x := ''''''' + cBreak + 'a'));
  Assert.AreEqual(0, TPascalScan.FirstOpen('a { b } c'));
  Assert.AreEqual(9, TPascalScan.FirstOpen('a { b } (* c'));
  Assert.AreEqual(3, TPascalScan.FirstOpen('a ''b' + cBreak + '{ c'));
end;

procedure TPascalScanTests.FindWordSkipsNoise;
const
  cText = '{ uses } (* uses *) // uses' + cBreak + '''uses'' uses A;';
begin
  Assert.AreEqual(Integer(Pos(''' uses', cText) + 2), TPascalScan.FindWord(cText, 'uses', 1));
  Assert.AreEqual(Integer(Pos(''' uses', cText) + 2), TPascalScan.FindWord(cText, 'USES', 1));
  Assert.AreEqual(0, TPascalScan.FindWord(cText, 'uses', Pos(''' uses', cText) + 3));
end;

procedure TPascalScanTests.FindWordWholeWordsOnly;
begin
  Assert.AreEqual(0, TPascalScan.FindWord('Units, X.uses, &uses', 'uses', 1));
  Assert.AreEqual(0, TPascalScan.FindWord('usesA', 'uses', 1));
  Assert.AreEqual(0, TPascalScan.FindWord('Grünuses', 'uses', 1));
  Assert.AreEqual(1, TPascalScan.FindWord('uses;', 'uses', 1));
  Assert.AreEqual(3, TPascalScan.FindWord('A in ''a.pas''', 'in', 1));
  Assert.AreEqual(6, TPascalScan.FindWord('Ünit in', 'in', 1));
end;

procedure TPascalScanTests.FindAfterOpenCommentEnds;
const
  cText = 'program X;' + cBreak + '(* uses A;' + cBreak + 'begin end.';
begin
  // Ohne Abschluss reicht der Kommentar bis zum Ende; die Suche endet und springt nie zurück vor AFrom.
  Assert.AreEqual(0, TPascalScan.FindWord(cText, 'uses', 1));
  Assert.AreEqual(0, TPascalScan.FindWord(cText, 'begin', 1));
  Assert.AreEqual(0, TPascalScan.FindChar(cText, ';', 11));
  Assert.AreEqual(10, TPascalScan.FindChar(cText, ';', 1));
  Assert.AreEqual(0, TPascalScan.FindWord('a (*) uses', 'uses', 1));
  Assert.AreEqual(0, TPascalScan.FindWord('a { uses', 'uses', 1));
  Assert.AreEqual(0, TPascalScan.FindChar('a ''x;', ';', 1));
end;

procedure TPascalScanTests.FindCharSkipsNoise;
const
  cText = 'uses { ; } A (* ; *), B in ''b;.pas'' // ;' + cBreak + ';';
begin
  Assert.AreEqual(Integer(Length(cText)), TPascalScan.FindChar(cText, ';', 1));
  Assert.AreEqual(Integer(Pos(',', cText)), TPascalScan.FindChar(cText, ',', 1));
  Assert.AreEqual(0, TPascalScan.FindChar('abc', ';', 1));
  Assert.AreEqual(0, TPascalScan.FindChar('', ';', 1));
  Assert.AreEqual(1, TPascalScan.FindChar(';', ';', 0));
end;

end.
