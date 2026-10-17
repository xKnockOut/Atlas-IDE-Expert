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
  Atlas.Core.Editor.LinkedEditing;

const
  Source =
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
  Range: TAtlasLinkedRange;
begin
  Result := '';
  for Range in ARanges do
  begin
    if Result <> '' then
      Result := Result + ' ';
    Result := Result + Format('%d:%d+%d', [Range.Line, Range.Character, Range.Length]);
  end;
end;

function Lines(const AText: string): TArray<string>;
begin
  Result := AText.Replace(#13#10, #10).Split([#10]);
end;

{ TAtlasLinkedEditingTests }

procedure TAtlasLinkedEditingTests.ReadsServerAnswer;
var
  Json: TJSONValue;
  Found: TAtlasLinkedRanges;
  Conflicts: TAtlasLinkedConflicts;
begin
  Json := TJSONObject.ParseJSONValue('{"ranges":[{"start":{"line":2,"character":2},"end":{"line":2,"character":8}},' +
    '{"start":{"line":4,"character":2},"end":{"line":4,"character":8}}],"wordPattern":"x",' +
    '"atlasConflicts":[{"name":"Anzahl","detail":"Parameter Anzahl"},{"name":"Lauf"}]}');
  try
    Assert.IsTrue(TAtlasLinkedEditing.FromJson(Json, Found, Conflicts));
  finally
    Json.Free;
  end;
  Assert.AreEqual('2:2+6 4:2+6', Describe(Found));
  Assert.AreEqual(2, Integer(Length(Conflicts)));
  Assert.AreEqual('Parameter Anzahl', Conflicts[0].Detail);
  // Ohne Beschreibung gilt der Name.
  Assert.AreEqual('Lauf', Conflicts[1].Detail);
  Found := nil;
  Conflicts := nil;
end;

procedure TAtlasLinkedEditingTests.RejectsMultilineAndEmptyAnswers;
var
  Json: TJSONValue;
  Found: TAtlasLinkedRanges;
  Conflicts: TAtlasLinkedConflicts;
begin
  Json := TJSONObject.ParseJSONValue('{"ranges":[{"start":{"line":2,"character":2},"end":{"line":3,"character":1}}]}');
  try
    Assert.IsFalse(TAtlasLinkedEditing.FromJson(Json, Found, Conflicts));
    Assert.AreEqual(0, Integer(Length(Found)));
  finally
    Json.Free;
  end;
  Json := TJSONNull.Create;
  try
    Assert.IsFalse(TAtlasLinkedEditing.FromJson(Json, Found, Conflicts));
  finally
    Json.Free;
  end;
  Assert.IsFalse(TAtlasLinkedEditing.FromJson(nil, Found, Conflicts));
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
  Assert.IsTrue(TAtlasLinkedEditing.Matches(Lines(Source), Ranges));
  Assert.AreEqual('Zeilen', TAtlasLinkedEditing.NameOf(Lines(Source), Ranges[2]));
  // Anders geschrieben zählt als derselbe Name.
  Assert.IsTrue(TAtlasLinkedEditing.Matches(Lines(Source.Replace('Zeilen + ', 'ZEILEN + ')),
    [TAtlasLinkedRange.Create(4, 2, 6), TAtlasLinkedRange.Create(4, 21, 6)]));
  // Text inzwischen geändert.
  Assert.IsFalse(TAtlasLinkedEditing.Matches(Lines(Source.Replace('  Zeilen: Integer', '  Zeile: Integer')), Ranges));
  Assert.IsFalse(TAtlasLinkedEditing.Matches(Lines('kurz'), Ranges));
  Assert.IsFalse(TAtlasLinkedEditing.Matches(Lines(Source), nil));
end;

procedure TAtlasLinkedEditingTests.TypesInsideAndAtBothEnds;
var
  Name: string;
  Offset: Integer;
begin
  Assert.IsTrue(TAtlasLinkedEditing.Key('Zeilen', 0, TAtlasLinkedKey.Insert, 'A', Name, Offset));
  Assert.AreEqual('AZeilen', Name);
  Assert.AreEqual(1, Offset);
  Assert.IsTrue(TAtlasLinkedEditing.Key('Zeilen', 6, TAtlasLinkedKey.Insert, 'Max', Name, Offset));
  Assert.AreEqual('ZeilenMax', Name);
  Assert.AreEqual(9, Offset);
  Assert.IsTrue(TAtlasLinkedEditing.Key('Zeilen', 3, TAtlasLinkedKey.Insert, '_', Name, Offset));
  Assert.AreEqual('Zei_len', Name);
  // Ziffern im Namen ja, am Anfang nicht.
  Assert.IsTrue(TAtlasLinkedEditing.Key('Zeilen', 6, TAtlasLinkedKey.Insert, '2', Name, Offset));
  Assert.AreEqual('Zeilen2', Name);
  Assert.IsFalse(TAtlasLinkedEditing.Key('Zeilen', 0, TAtlasLinkedKey.Insert, '2', Name, Offset));
  Assert.AreEqual('Zeilen', Name);
  // Unicode-Bezeichner.
  Assert.IsTrue(TAtlasLinkedEditing.Key('Gr', 2, TAtlasLinkedKey.Insert, #$00F6#$00DF'e', Name, Offset));
  Assert.AreEqual('Gr'#$00F6#$00DF'e', Name);
end;

procedure TAtlasLinkedEditingTests.DeletesDownToEmptyName;
var
  Name, Next: string;
  Offset, NextOffset: Integer;
begin
  Name := 'Ab';
  Offset := 2;
  Assert.IsTrue(TAtlasLinkedEditing.Key(Name, Offset, TAtlasLinkedKey.Backspace, '', Next, NextOffset));
  Assert.AreEqual('A', Next);
  Assert.IsTrue(TAtlasLinkedEditing.Key(Next, NextOffset, TAtlasLinkedKey.Backspace, '', Name, Offset));
  Assert.AreEqual('', Name);
  Assert.AreEqual(0, Offset);
  // Aus dem leeren Namen wieder einer.
  Assert.IsTrue(TAtlasLinkedEditing.Key(Name, Offset, TAtlasLinkedKey.Insert, 'N', Next, NextOffset));
  Assert.AreEqual('N', Next);
  Assert.IsTrue(TAtlasLinkedEditing.Key('Ab', 0, TAtlasLinkedKey.Delete, '', Name, Offset));
  Assert.AreEqual('b', Name);
  Assert.AreEqual(0, Offset);
  // Entf am Anfang, bis die erste Ziffer vorn stünde: dann Schluss.
  Assert.IsFalse(TAtlasLinkedEditing.Key('A1', 0, TAtlasLinkedKey.Delete, '', Name, Offset));
end;

procedure TAtlasLinkedEditingTests.StopsWhenLeavingTheName;
var
  Name: string;
  Offset: Integer;
begin
  Assert.IsFalse(TAtlasLinkedEditing.Key('Zeilen', 0, TAtlasLinkedKey.Backspace, '', Name, Offset));
  Assert.IsFalse(TAtlasLinkedEditing.Key('Zeilen', 6, TAtlasLinkedKey.Delete, '', Name, Offset));
  Assert.IsFalse(TAtlasLinkedEditing.Key('Zeilen', 3, TAtlasLinkedKey.Insert, ' ', Name, Offset));
  Assert.IsFalse(TAtlasLinkedEditing.Key('Zeilen', 6, TAtlasLinkedKey.Insert, '.', Name, Offset));
  Assert.IsFalse(TAtlasLinkedEditing.Key('Zeilen', 7, TAtlasLinkedKey.Insert, 'x', Name, Offset));
  Assert.IsFalse(TAtlasLinkedEditing.Key('Zeilen', 2, TAtlasLinkedKey.Insert, '', Name, Offset));
end;

procedure TAtlasLinkedEditingTests.RenamesAllRanges;
var
  Text: string;
  Found: TAtlasLinkedRanges;
begin
  Assert.IsTrue(TAtlasLinkedEditing.Rename(Source, Ranges, 'Anzahl2', Text, Found));
  Assert.AreEqual(Source.Replace('Zeilen', 'Anzahl2', [rfReplaceAll]), Text);
  Assert.AreEqual('2:2+7 4:2+7 4:22+7', Describe(Found));
  Assert.AreEqual('Anzahl2', TAtlasLinkedEditing.NameOf(Lines(Text), Found[2]));
end;

procedure TAtlasLinkedEditingTests.RenamesTwoRangesInOneLine;
var
  Text: string;
  Found: TAtlasLinkedRanges;
begin
  // Reihenfolge der Bereiche bleibt, auch wenn sie nicht in Textreihenfolge kommen.
  Assert.IsTrue(TAtlasLinkedEditing.Rename('a := a + a;', [TAtlasLinkedRange.Create(0, 9, 1),
    TAtlasLinkedRange.Create(0, 0, 1), TAtlasLinkedRange.Create(0, 5, 1)], 'Wert', Text, Found));
  Assert.AreEqual('Wert := Wert + Wert;', Text);
  Assert.AreEqual('0:15+4 0:0+4 0:8+4', Describe(Found));
end;

procedure TAtlasLinkedEditingTests.RenamesToEmptyAndBack;
var
  Text, Back: string;
  Found, Again: TAtlasLinkedRanges;
begin
  Assert.IsTrue(TAtlasLinkedEditing.Rename(Source, Ranges, '', Text, Found));
  Assert.AreEqual('2:2+0 4:2+0 4:15+0', Describe(Found));
  Assert.AreEqual(Source.Replace('Zeilen', '', [rfReplaceAll]), Text);
  Assert.IsTrue(TAtlasLinkedEditing.Rename(Text, Found, 'Zeilen', Back, Again));
  Assert.AreEqual(Source, Back);
  Assert.AreEqual(Describe(Ranges), Describe(Again));
end;

procedure TAtlasLinkedEditingTests.RejectsRangesOutsideText;
var
  Text: string;
  Found: TAtlasLinkedRanges;
begin
  Assert.IsFalse(TAtlasLinkedEditing.Rename(Source, [TAtlasLinkedRange.Create(9, 0, 2)], 'X', Text, Found));
  // Über das Zeilenende hinaus (das Zeilenende zählt nicht zum Namen).
  Assert.IsFalse(TAtlasLinkedEditing.Rename(Source, [TAtlasLinkedRange.Create(3, 3, 3)], 'X', Text, Found));
  Assert.AreEqual(Source, Text);
end;

procedure TAtlasLinkedEditingTests.FollowsChangesOfTheIde;
var
  Name: string;
  Range: TAtlasLinkedRange;
begin
  Range := TAtlasLinkedRange.Create(4, 2, 6);
  // Aus der Zwischenablage am Anfang eingefügt.
  Assert.IsTrue(TAtlasLinkedEditing.Follow('  Zeilen := 1;', '  MaxZeilen := 1;', Range, Name));
  Assert.AreEqual('MaxZeilen', Name);
  // Ganzen Namen ersetzt, auch kürzer.
  Assert.IsTrue(TAtlasLinkedEditing.Follow('  Zeilen := 1;', '  Z := 1;', Range, Name));
  Assert.AreEqual('Z', Name);
  Assert.IsTrue(TAtlasLinkedEditing.Follow('  Zeilen := 1;', '   := 1;', Range, Name));
  Assert.AreEqual('', Name);
  // Änderung außerhalb des Namens.
  Assert.IsFalse(TAtlasLinkedEditing.Follow('  Zeilen := 1;', '  Zeilen := 12;', Range, Name));
  Assert.IsFalse(TAtlasLinkedEditing.Follow('  Zeilen := 1;', ' Zeilen := 1;', Range, Name));
  Assert.IsFalse(TAtlasLinkedEditing.Follow('  Zeilen', '  Zeilen', TAtlasLinkedRange.Create(4, 2, 9), Name));
end;

procedure TAtlasLinkedEditingTests.ResizesAfterChangeOfTheIde;
var
  Text: string;
  Found, Again: TAtlasLinkedRanges;
begin
  // Die IDE hat das erste Vorkommen in Zeile 4 auf "Z" gekürzt; das zweite rückt nach.
  Found := TAtlasLinkedEditing.Resized(Ranges, 1, 1);
  Assert.AreEqual('2:2+6 4:2+1 4:16+6', Describe(Found));
  Assert.AreEqual(Describe(Ranges), Describe(TAtlasLinkedEditing.Resized(Ranges, 5, 1)));
  // Danach schreibt Rename den neuen Namen in die übrigen.
  Assert.IsTrue(TAtlasLinkedEditing.Rename(Source.Replace('  Zeilen := ', '  Z := '), Found, 'Z', Text, Again));
  Assert.AreEqual(Source.Replace('Zeilen', 'Z', [rfReplaceAll]), Text);
  Assert.AreEqual('2:2+1 4:2+1 4:16+1', Describe(Again));
end;

procedure TAtlasLinkedEditingTests.ReportsConflicts;
var
  Conflicts: TAtlasLinkedConflicts;
  Detail: string;
begin
  SetLength(Conflicts, 1);
  Conflicts[0].Name := 'Anzahl';
  Conflicts[0].Detail := 'Parameter Anzahl';
  Assert.IsTrue(TAtlasLinkedEditing.Problem('anzahl', 'Zeilen', Conflicts, Detail) = TAtlasLinkedProblem.Visible);
  Assert.AreEqual('Parameter Anzahl', Detail);
  Assert.IsTrue(TAtlasLinkedEditing.Problem('Begin', 'Zeilen', Conflicts, Detail) = TAtlasLinkedProblem.Reserved);
  Assert.IsTrue(TAtlasLinkedEditing.Problem('Zeilen2', 'Zeilen', Conflicts, Detail) = TAtlasLinkedProblem.None);
  // Der alte Name und der leere Name sind nie ein Konflikt.
  Assert.IsTrue(TAtlasLinkedEditing.Problem('ZEILEN', 'Zeilen', Conflicts, Detail) = TAtlasLinkedProblem.None);
  Assert.IsTrue(TAtlasLinkedEditing.Problem('', 'Zeilen', Conflicts, Detail) = TAtlasLinkedProblem.None);
  Assert.AreEqual('', Detail);
  Conflicts := nil;
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
