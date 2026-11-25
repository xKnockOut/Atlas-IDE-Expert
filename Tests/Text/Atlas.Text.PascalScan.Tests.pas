unit Atlas.Text.PascalScan.Tests;

// Tests der Suche außerhalb von Kommentaren und Zeichenketten: jede Art
// Kommentar, Anweisung und Zeichenkette mit und ohne Abschluss, Wortgrenzen
// (qualifizierte Namen, &-Bezeichner, Unicode), und dass jede Suche auch bei
// offenen Kommentaren endet. Ein Vergleich zweier Textlängen prüft, dass die
// Arbeit bei vielen Zeichenketten linear mit der Länge wächst; er vergleicht
// nur die Größenordnung, keine feste Zeit, und hält so auch auf langsamen
// Rechnern.

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
    [Test]
    procedure StringEndsAtQuoteOrLineEnd;
    [Test]
    procedure SearchGoesOnAfterOpenString;
    [Test]
    [Category('Benchmark')]
    procedure ManyStringsStayLinear;
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  System.Diagnostics,
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

procedure TPascalScanTests.StringEndsAtQuoteOrLineEnd;
begin
  // Das nächste Hochkomma schließt, wenn es vor dem Zeilenende steht; eins in einer späteren Zeile nicht.
  Assert.AreEqual(6, TPascalScan.SkipNoise('''abc''' + cBreak + 'x''', 1));
  Assert.AreEqual(5, TPascalScan.SkipNoise('''abc' + cBreak + 'x''', 1));
  Assert.AreEqual(5, TPascalScan.SkipNoise('''abc' + #10 + 'x''', 1));
  Assert.AreEqual(3, TPascalScan.SkipNoise('''a', 1));
  Assert.AreEqual(2, TPascalScan.SkipNoise('''', 1));
  Assert.AreEqual(3, TPascalScan.SkipNoise('''''', 1));
  // ''' mitten in der Zeile ist keine mehrzeilige Zeichenkette.
  Assert.AreEqual(3, TPascalScan.SkipNoise(''''''' x''', 1));
end;

procedure TPascalScanTests.SearchGoesOnAfterOpenString;
const
  cText = 'a ''x;' + cBreak + 'b;';
begin
  // Eine einzeilige Zeichenkette ohne Abschluss endet am Zeilenende; gesucht wird in der nächsten Zeile weiter.
  Assert.AreEqual(Integer(Length(cText)), TPascalScan.FindChar(cText, ';', 1));
  Assert.AreEqual(Integer(Pos('b;', cText)), TPascalScan.FindWord(cText, 'B', 1));
  Assert.AreEqual(3, TPascalScan.FirstOpen(cText));
end;

/// <summary>Wie eine große .dpr: AEntries Einträge "Unit in 'Pfad'".</summary>
function DprWithStrings(AEntries: Integer): string;
var
  mBuilder: TStringBuilder;
  mIndex: Integer;
begin
  mBuilder := TStringBuilder.Create;
  try
    mBuilder.Append('program P;' + cBreak + 'uses' + cBreak);
    for mIndex := 1 to AEntries do
    begin
      mBuilder.Append('  Unit' + IntToStr(mIndex) + ' in ''Quelle\Ordner\Unit' + IntToStr(mIndex) + '.pas'',' +
        cBreak);
    end;
    mBuilder.Append('  Letzte;' + cBreak + 'begin' + cBreak + 'end.');
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

/// <summary>Alle "in" in AText suchen; Zahl der Treffer.</summary>
function CountIn(const AText: string): Integer;
var
  mFound: Integer;
begin
  Result := 0;
  mFound := TPascalScan.FindWord(AText, 'in', 1);
  while mFound > 0 do
  begin
    Inc(Result);
    mFound := TPascalScan.FindWord(AText, 'in', mFound + 1);
  end;
end;

/// <summary>Kürzeste von drei Suchen über AText in Ticks (eine Unterbrechung des Rechners zählt nicht).</summary>
function BestTicks(const AText: string): Int64;
var
  mRound: Integer;
  mWatch: TStopwatch;
begin
  Result := High(Int64);
  for mRound := 1 to 3 do
  begin
    mWatch := TStopwatch.StartNew;
    CountIn(AText);
    mWatch.Stop;
    Result := Min(Result, mWatch.ElapsedTicks);
  end;
end;

procedure TPascalScanTests.ManyStringsStayLinear;
const
  cSmall = 2000;
  cFactor = 8;
var
  mSmall, mLarge: string;
  mSmallTicks, mLargeTicks: Int64;
begin
  // Jede Zeichenkette kostet nur ihre eigene Länge. Kopierte die Suche je Zeichenkette den Text von vorn, wüchse
  // die Arbeit mit dem Quadrat der Länge: achtfacher Text, 64-fache Zeit statt achtfacher.
  mSmall := DprWithStrings(cSmall);
  mLarge := DprWithStrings(cSmall * cFactor);
  Assert.AreEqual(0, TPascalScan.FirstOpen(mLarge));
  Assert.AreEqual(cSmall * cFactor, CountIn(mLarge));
  Assert.AreEqual(Integer(Pos('begin', mLarge)), TPascalScan.FindWord(mLarge, 'begin', 1));
  mSmallTicks := Max(BestTicks(mSmall), 1);
  mLargeTicks := BestTicks(mLarge);
  Assert.IsTrue(mLargeTicks < 3 * cFactor * mSmallTicks, Format('%d statt höchstens %d Ticks (Kurz: %d)',
    [mLargeTicks, 3 * cFactor * mSmallTicks, mSmallTicks]));
  mSmall := '';
  mLarge := '';
end;

end.
