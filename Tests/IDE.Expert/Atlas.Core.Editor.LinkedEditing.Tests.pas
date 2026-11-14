unit Atlas.Core.Editor.LinkedEditing.Tests;

// Tests für „Bezeichner live mitziehen“ (#658): Antwort des Servers lesen,
// Tasten im Namen (auch Einfügen am Anfang und Löschen bis zur Länge 0),
// Abgleich auf alle Bereiche samt Verschiebung in derselben Zeile, fremde
// Änderungen am Namen, Konflikte mit reservierten Wörtern und sichtbaren
// Namen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasLinkedEditingTests = class
  public
    [Test]
    procedure ReadsServerAnswer;
    [Test]
    procedure RejectsMultilineAndEmptyAnswers;
    [Test]
    procedure FindsRangeAtCaret;
    [Test]
    procedure MatchesOnlyCurrentText;
    [Test]
    procedure TypesInsideAndAtBothEnds;
    [Test]
    procedure DeletesDownToEmptyName;
    [Test]
    procedure StopsWhenLeavingTheName;
    [Test]
    procedure RenamesAllRanges;
    [Test]
    procedure RenamesTwoRangesInOneLine;
    [Test]
    procedure RenamesToEmptyAndBack;
    [Test]
    procedure RejectsRangesOutsideText;
    [Test]
    procedure FollowsChangesOfTheIde;
    [Test]
    procedure ResizesAfterChangeOfTheIde;
    [Test]
    procedure ReportsConflicts;
    [Test]
    procedure KnowsReservedWords;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Core.Editor.LinkedEditing;

const
  cSource =
    'procedure Lauf(Anzahl: Integer);'#13#10 + // 0
    'var'#13#10 +                              // 1
    '  Zeilen: Integer;'#13#10 +               // 2
    'begin'#13#10 +                            // 3
    '  Zeilen := Anzahl + Zeilen;'#13#10 +     // 4
    'end;';                                    // 5

function Ranges: TAtlasLinkedRanges;
begin
  Result := [TAtlasLinkedRange.Create(2, 2, 6), TAtlasLinkedRange.Create(4, 2, 6), TAtlasLinkedRange.Create(4, 21, 6)];
end;

function Describe(const ARanges: TAtlasLinkedRanges): string;
var
  mRange: TAtlasLinkedRange;
begin
  Result := '';
  for mRange in ARanges do
  begin
    if Result <> '' then
    begin
      Result := Result + ' ';
    end;
    Result := Result + Format('%d:%d+%d', [mRange.Line, mRange.Character, mRange.Length]);
  end;
end;

function Lines(const AText: string): TArray<string>;
begin
  Result := AText.Replace(#13#10, #10).Split([#10]);
end;

{ TAtlasLinkedEditingTests }

procedure TAtlasLinkedEditingTests.ReadsServerAnswer;
var
  mJson: TJSONValue;
  mFound: TAtlasLinkedRanges;
  mConflicts: TAtlasLinkedConflicts;
begin
  mJson := TJSONObject.ParseJSONValue('{"ranges":[{"start":{"line":2,"character":2},"end":{"line":2,"character":8}},' +
    '{"start":{"line":4,"character":2},"end":{"line":4,"character":8}}],"wordPattern":"x",' +
    '"atlasConflicts":[{"name":"Anzahl","detail":"Parameter Anzahl"},{"name":"Lauf"}]}');
  try
    Assert.IsTrue(TAtlasLinkedEditing.FromJson(mJson, mFound, mConflicts));
  finally
    mJson.Free;
  end;
  Assert.AreEqual('2:2+6 4:2+6', Describe(mFound));
  Assert.AreEqual(2, Integer(Length(mConflicts)));
  Assert.AreEqual('Parameter Anzahl', mConflicts[0].Detail);
  // Ohne Beschreibung gilt der Name.
  Assert.AreEqual('Lauf', mConflicts[1].Detail);
  mFound := nil;
  mConflicts := nil;
end;

procedure TAtlasLinkedEditingTests.RejectsMultilineAndEmptyAnswers;
var
  mJson: TJSONValue;
  mFound: TAtlasLinkedRanges;
  mConflicts: TAtlasLinkedConflicts;
begin
  mJson := TJSONObject.ParseJSONValue('{"ranges":[{"start":{"line":2,"character":2},"end":{"line":3,"character":1}}]}');
  try
    Assert.IsFalse(TAtlasLinkedEditing.FromJson(mJson, mFound, mConflicts));
    Assert.AreEqual(0, Integer(Length(mFound)));
  finally
    mJson.Free;
  end;
  mJson := TJSONNull.Create;
  try
    Assert.IsFalse(TAtlasLinkedEditing.FromJson(mJson, mFound, mConflicts));
  finally
    mJson.Free;
  end;
  Assert.IsFalse(TAtlasLinkedEditing.FromJson(nil, mFound, mConflicts));
end;

procedure TAtlasLinkedEditingTests.FindsRangeAtCaret;
begin
  Assert.AreEqual(1, TAtlasLinkedEditing.IndexAt(Ranges, 4, 2));
  // Beide Ränder zählen: direkt vor und direkt hinter dem Namen.
  Assert.AreEqual(1, TAtlasLinkedEditing.IndexAt(Ranges, 4, 8));
  Assert.AreEqual(2, TAtlasLinkedEditing.IndexAt(Ranges, 4, 27));
  Assert.AreEqual(-1, TAtlasLinkedEditing.IndexAt(Ranges, 4, 12));
  Assert.AreEqual(-1, TAtlasLinkedEditing.IndexAt(Ranges, 3, 2));
end;

procedure TAtlasLinkedEditingTests.MatchesOnlyCurrentText;
begin
  Assert.IsTrue(TAtlasLinkedEditing.Matches(Lines(cSource), Ranges));
  Assert.AreEqual('Zeilen', TAtlasLinkedEditing.NameOf(Lines(cSource), Ranges[2]));
  // Anders geschrieben zählt als derselbe Name.
  Assert.IsTrue(TAtlasLinkedEditing.Matches(Lines(cSource.Replace('Zeilen + ', 'ZEILEN + ')),
    [TAtlasLinkedRange.Create(4, 2, 6), TAtlasLinkedRange.Create(4, 21, 6)]));
  // Text inzwischen geändert.
  Assert.IsFalse(TAtlasLinkedEditing.Matches(Lines(cSource.Replace('  Zeilen: Integer', '  Zeile: Integer')), Ranges));
  Assert.IsFalse(TAtlasLinkedEditing.Matches(Lines('kurz'), Ranges));
  Assert.IsFalse(TAtlasLinkedEditing.Matches(Lines(cSource), nil));
end;

procedure TAtlasLinkedEditingTests.TypesInsideAndAtBothEnds;
var
  mName: string;
  mOffset: Integer;
begin
  Assert.IsTrue(TAtlasLinkedEditing.Key('Zeilen', 0, TAtlasLinkedKey.Insert, 'A', mName, mOffset));
  Assert.AreEqual('AZeilen', mName);
  Assert.AreEqual(1, mOffset);
  Assert.IsTrue(TAtlasLinkedEditing.Key('Zeilen', 6, TAtlasLinkedKey.Insert, 'Max', mName, mOffset));
  Assert.AreEqual('ZeilenMax', mName);
  Assert.AreEqual(9, mOffset);
  Assert.IsTrue(TAtlasLinkedEditing.Key('Zeilen', 3, TAtlasLinkedKey.Insert, '_', mName, mOffset));
  Assert.AreEqual('Zei_len', mName);
  // Ziffern im Namen ja, am Anfang nicht.
  Assert.IsTrue(TAtlasLinkedEditing.Key('Zeilen', 6, TAtlasLinkedKey.Insert, '2', mName, mOffset));
  Assert.AreEqual('Zeilen2', mName);
  Assert.IsFalse(TAtlasLinkedEditing.Key('Zeilen', 0, TAtlasLinkedKey.Insert, '2', mName, mOffset));
  Assert.AreEqual('Zeilen', mName);
  // Unicode-Bezeichner.
  Assert.IsTrue(TAtlasLinkedEditing.Key('Gr', 2, TAtlasLinkedKey.Insert, #$00F6#$00DF'e', mName, mOffset));
  Assert.AreEqual('Gr'#$00F6#$00DF'e', mName);
end;

procedure TAtlasLinkedEditingTests.DeletesDownToEmptyName;
var
  mName, mNext: string;
  mOffset, mNextOffset: Integer;
begin
  mName := 'Ab';
  mOffset := 2;
  Assert.IsTrue(TAtlasLinkedEditing.Key(mName, mOffset, TAtlasLinkedKey.Backspace, '', mNext, mNextOffset));
  Assert.AreEqual('A', mNext);
  Assert.IsTrue(TAtlasLinkedEditing.Key(mNext, mNextOffset, TAtlasLinkedKey.Backspace, '', mName, mOffset));
  Assert.AreEqual('', mName);
  Assert.AreEqual(0, mOffset);
  // Aus dem leeren Namen wieder einer.
  Assert.IsTrue(TAtlasLinkedEditing.Key(mName, mOffset, TAtlasLinkedKey.Insert, 'N', mNext, mNextOffset));
  Assert.AreEqual('N', mNext);
  Assert.IsTrue(TAtlasLinkedEditing.Key('Ab', 0, TAtlasLinkedKey.Delete, '', mName, mOffset));
  Assert.AreEqual('b', mName);
  Assert.AreEqual(0, mOffset);
  // Entf am Anfang, bis die erste Ziffer vorn stünde: dann Schluss.
  Assert.IsFalse(TAtlasLinkedEditing.Key('A1', 0, TAtlasLinkedKey.Delete, '', mName, mOffset));
end;

procedure TAtlasLinkedEditingTests.StopsWhenLeavingTheName;
var
  mName: string;
  mOffset: Integer;
begin
  Assert.IsFalse(TAtlasLinkedEditing.Key('Zeilen', 0, TAtlasLinkedKey.Backspace, '', mName, mOffset));
  Assert.IsFalse(TAtlasLinkedEditing.Key('Zeilen', 6, TAtlasLinkedKey.Delete, '', mName, mOffset));
  Assert.IsFalse(TAtlasLinkedEditing.Key('Zeilen', 3, TAtlasLinkedKey.Insert, ' ', mName, mOffset));
  Assert.IsFalse(TAtlasLinkedEditing.Key('Zeilen', 6, TAtlasLinkedKey.Insert, '.', mName, mOffset));
  Assert.IsFalse(TAtlasLinkedEditing.Key('Zeilen', 7, TAtlasLinkedKey.Insert, 'x', mName, mOffset));
  Assert.IsFalse(TAtlasLinkedEditing.Key('Zeilen', 2, TAtlasLinkedKey.Insert, '', mName, mOffset));
end;

procedure TAtlasLinkedEditingTests.RenamesAllRanges;
var
  mText: string;
  mFound: TAtlasLinkedRanges;
begin
  Assert.IsTrue(TAtlasLinkedEditing.Rename(cSource, Ranges, 'Anzahl2', mText, mFound));
  Assert.AreEqual(cSource.Replace('Zeilen', 'Anzahl2', [rfReplaceAll]), mText);
  Assert.AreEqual('2:2+7 4:2+7 4:22+7', Describe(mFound));
  Assert.AreEqual('Anzahl2', TAtlasLinkedEditing.NameOf(Lines(mText), mFound[2]));
end;

procedure TAtlasLinkedEditingTests.RenamesTwoRangesInOneLine;
var
  mText: string;
  mFound: TAtlasLinkedRanges;
begin
  // Reihenfolge der Bereiche bleibt, auch wenn sie nicht in Textreihenfolge kommen.
  Assert.IsTrue(TAtlasLinkedEditing.Rename('a := a + a;', [TAtlasLinkedRange.Create(0, 9, 1),
    TAtlasLinkedRange.Create(0, 0, 1), TAtlasLinkedRange.Create(0, 5, 1)], 'Wert', mText, mFound));
  Assert.AreEqual('Wert := Wert + Wert;', mText);
  Assert.AreEqual('0:15+4 0:0+4 0:8+4', Describe(mFound));
end;

procedure TAtlasLinkedEditingTests.RenamesToEmptyAndBack;
var
  mText, mBack: string;
  mFound, mAgain: TAtlasLinkedRanges;
begin
  Assert.IsTrue(TAtlasLinkedEditing.Rename(cSource, Ranges, '', mText, mFound));
  Assert.AreEqual('2:2+0 4:2+0 4:15+0', Describe(mFound));
  Assert.AreEqual(cSource.Replace('Zeilen', '', [rfReplaceAll]), mText);
  Assert.IsTrue(TAtlasLinkedEditing.Rename(mText, mFound, 'Zeilen', mBack, mAgain));
  Assert.AreEqual(cSource, mBack);
  Assert.AreEqual(Describe(Ranges), Describe(mAgain));
end;

procedure TAtlasLinkedEditingTests.RejectsRangesOutsideText;
var
  mText: string;
  mFound: TAtlasLinkedRanges;
begin
  Assert.IsFalse(TAtlasLinkedEditing.Rename(cSource, [TAtlasLinkedRange.Create(9, 0, 2)], 'X', mText, mFound));
  // Über das Zeilenende hinaus (das Zeilenende zählt nicht zum Namen).
  Assert.IsFalse(TAtlasLinkedEditing.Rename(cSource, [TAtlasLinkedRange.Create(3, 3, 3)], 'X', mText, mFound));
  Assert.AreEqual(cSource, mText);
end;

procedure TAtlasLinkedEditingTests.FollowsChangesOfTheIde;
var
  mName: string;
  mRange: TAtlasLinkedRange;
begin
  mRange := TAtlasLinkedRange.Create(4, 2, 6);
  // Aus der Zwischenablage am Anfang eingefügt.
  Assert.IsTrue(TAtlasLinkedEditing.Follow('  Zeilen := 1;', '  MaxZeilen := 1;', mRange, mName));
  Assert.AreEqual('MaxZeilen', mName);
  // Ganzen Namen ersetzt, auch kürzer.
  Assert.IsTrue(TAtlasLinkedEditing.Follow('  Zeilen := 1;', '  Z := 1;', mRange, mName));
  Assert.AreEqual('Z', mName);
  Assert.IsTrue(TAtlasLinkedEditing.Follow('  Zeilen := 1;', '   := 1;', mRange, mName));
  Assert.AreEqual('', mName);
  // Änderung außerhalb des Namens.
  Assert.IsFalse(TAtlasLinkedEditing.Follow('  Zeilen := 1;', '  Zeilen := 12;', mRange, mName));
  Assert.IsFalse(TAtlasLinkedEditing.Follow('  Zeilen := 1;', ' Zeilen := 1;', mRange, mName));
  Assert.IsFalse(TAtlasLinkedEditing.Follow('  Zeilen', '  Zeilen', TAtlasLinkedRange.Create(4, 2, 9), mName));
end;

procedure TAtlasLinkedEditingTests.ResizesAfterChangeOfTheIde;
var
  mText: string;
  mFound, mAgain: TAtlasLinkedRanges;
begin
  // Die IDE hat das erste Vorkommen in Zeile 4 auf "Z" gekürzt; das zweite rückt nach.
  mFound := TAtlasLinkedEditing.Resized(Ranges, 1, 1);
  Assert.AreEqual('2:2+6 4:2+1 4:16+6', Describe(mFound));
  Assert.AreEqual(Describe(Ranges), Describe(TAtlasLinkedEditing.Resized(Ranges, 5, 1)));
  // Danach schreibt Rename den neuen Namen in die übrigen.
  Assert.IsTrue(TAtlasLinkedEditing.Rename(cSource.Replace('  Zeilen := ', '  Z := '), mFound, 'Z', mText, mAgain));
  Assert.AreEqual(cSource.Replace('Zeilen', 'Z', [rfReplaceAll]), mText);
  Assert.AreEqual('2:2+1 4:2+1 4:16+1', Describe(mAgain));
end;

procedure TAtlasLinkedEditingTests.ReportsConflicts;
var
  mConflicts: TAtlasLinkedConflicts;
  mDetail: string;
begin
  SetLength(mConflicts, 1);
  mConflicts[0].Name := 'Anzahl';
  mConflicts[0].Detail := 'Parameter Anzahl';
  Assert.AreEqual<TAtlasLinkedProblem>(TAtlasLinkedProblem.Visible,
    TAtlasLinkedEditing.Problem('anzahl', 'Zeilen', mConflicts, mDetail));
  Assert.AreEqual('Parameter Anzahl', mDetail);
  Assert.AreEqual<TAtlasLinkedProblem>(TAtlasLinkedProblem.Reserved,
    TAtlasLinkedEditing.Problem('Begin', 'Zeilen', mConflicts, mDetail));
  Assert.AreEqual<TAtlasLinkedProblem>(TAtlasLinkedProblem.None,
    TAtlasLinkedEditing.Problem('Zeilen2', 'Zeilen', mConflicts, mDetail));
  // Der alte Name und der leere Name sind nie ein Konflikt.
  Assert.AreEqual<TAtlasLinkedProblem>(TAtlasLinkedProblem.None,
    TAtlasLinkedEditing.Problem('ZEILEN', 'Zeilen', mConflicts, mDetail));
  Assert.AreEqual<TAtlasLinkedProblem>(TAtlasLinkedProblem.None,
    TAtlasLinkedEditing.Problem('', 'Zeilen', mConflicts, mDetail));
  Assert.AreEqual('', mDetail);
  mConflicts := nil;
end;

procedure TAtlasLinkedEditingTests.KnowsReservedWords;
begin
  Assert.IsTrue(TAtlasLinkedEditing.IsReserved('begin'));
  Assert.IsTrue(TAtlasLinkedEditing.IsReserved('RESOURCESTRING'));
  Assert.IsTrue(TAtlasLinkedEditing.IsReserved('out'));
  Assert.IsFalse(TAtlasLinkedEditing.IsReserved('Result'));
  Assert.IsFalse(TAtlasLinkedEditing.IsReserved('Zeilen'));
  Assert.IsTrue(TAtlasLinkedEditing.IsName(''));
  Assert.IsTrue(TAtlasLinkedEditing.IsName('_a1'));
  Assert.IsFalse(TAtlasLinkedEditing.IsName('1a'));
  Assert.IsFalse(TAtlasLinkedEditing.IsName('a b'));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasLinkedEditingTests);

end.
