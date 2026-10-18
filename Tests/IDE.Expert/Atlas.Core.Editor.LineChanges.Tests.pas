unit Atlas.Core.Editor.LineChanges.Tests;

// Änderungsmarken und Zeilenhistorie (#507): Blöcke hinzugefügt, geändert
// und gelöscht, Marken je Zeile, nächste/vorige Änderung reihum,
// Zurücksetzen (auch am Ende des Puffers), Zuordnung zur Zeile auf der
// Platte für blame und „vor …“.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasLineChangesTests = class
  public
    [Test]
    procedure ComputesAddedModifiedDeleted;
    [Test]
    procedure MarksPerLine;
    [Test]
    procedure NextAndPreviousWrap;
    [Test]
    procedure RevertRestoresOldText;
    [Test]
    procedure RevertAtEndOfBuffer;
    [Test]
    procedure BlameLineFollowsUnsavedEdits;
    [Test]
    procedure AgeInUnits;
  end;

implementation

uses
  System.SysUtils,
  System.DateUtils,
  Atlas.Core.Editor.LineChanges;

function Apply(const ALines: TArray<string>; const AEdit: TAtlasLineEdit): string;
var
  Text: string;
  Index, Start, Stop: Integer;

  function Offset(ALine, ACharacter: Integer): Integer;
  var
    Line: Integer;
  begin
    Result := 0;
    for Line := 0 to ALine - 1 do
      Inc(Result, Length(ALines[Line]) + 1);
    Inc(Result, ACharacter);
  end;

begin
  Text := '';
  for Index := 0 to High(ALines) do
  begin
    if Index > 0 then
      Text := Text + #10;
    Text := Text + ALines[Index];
  end;
  Start := Offset(AEdit.StartLine, AEdit.StartCharacter);
  Stop := Offset(AEdit.EndLine, AEdit.EndCharacter);
  Result := Copy(Text, 1, Start) + AEdit.NewText + Copy(Text, Stop + 1, MaxInt);
end;

procedure TAtlasLineChangesTests.ComputesAddedModifiedDeleted;
var
  Changes: TAtlasLineChangeList;
begin
  Changes := TAtlasLineChanges.Compute(['a', 'b', 'c', 'd', 'e', 'f'], ['a', 'neu', 'b', 'C', 'd', 'f']);
  Assert.AreEqual(3, Integer(Length(Changes)));
  Assert.AreEqual(Ord(TAtlasLineChangeKind.Added), Ord(Changes[0].Kind));
  Assert.AreEqual(1, Changes[0].Line);
  Assert.AreEqual(1, Integer(Changes[0].Count));
  Assert.AreEqual(Ord(TAtlasLineChangeKind.Modified), Ord(Changes[1].Kind));
  Assert.AreEqual(3, Changes[1].Line);
  Assert.AreEqual('c', string.Join('|', Changes[1].OldLines));
  Assert.AreEqual(Ord(TAtlasLineChangeKind.Deleted), Ord(Changes[2].Kind));
  Assert.AreEqual(5, Changes[2].Line, 'vor f');
  Assert.AreEqual(0, Integer(Changes[2].Count));
  Assert.AreEqual('e', string.Join('|', Changes[2].OldLines));
  Assert.AreEqual(0, Integer(Length(TAtlasLineChanges.Compute(['a', 'b'], ['a', 'b']))));
end;

procedure TAtlasLineChangesTests.MarksPerLine;
var
  Changes: TAtlasLineChangeList;
  Index: Integer;
begin
  Changes := TAtlasLineChanges.Compute(['a', 'b', 'c', 'd'], ['a', 'x', 'y', 'c']);
  // b → x, y (geändert), d gelöscht am Ende.
  Assert.AreEqual(Ord(TAtlasLineMark.None), Ord(TAtlasLineChanges.MarkAt(Changes, 0, Index)));
  Assert.AreEqual(-1, Index);
  Assert.AreEqual(Ord(TAtlasLineMark.Modified), Ord(TAtlasLineChanges.MarkAt(Changes, 1, Index)));
  Assert.AreEqual(0, Index);
  Assert.AreEqual(Ord(TAtlasLineMark.Modified), Ord(TAtlasLineChanges.MarkAt(Changes, 2, Index)));
  Assert.AreEqual(Ord(TAtlasLineMark.None), Ord(TAtlasLineChanges.MarkAt(Changes, 3, Index)));
  Assert.AreEqual(1, TAtlasLineChanges.DeletedAt(Changes, 3, 4), 'Löschung am Ende an der letzten Zeile');
  Assert.AreEqual(-1, TAtlasLineChanges.DeletedAt(Changes, 2, 4));
  Assert.AreEqual(0, TAtlasLineChanges.ChangeAt(Changes, 2, 4));
  Assert.AreEqual(1, TAtlasLineChanges.ChangeAt(Changes, 3, 4));
  Changes := TAtlasLineChanges.Compute(['a', 'b'], ['a', 'b', 'neu']);
  Assert.AreEqual(Ord(TAtlasLineMark.Added), Ord(TAtlasLineChanges.MarkAt(Changes, 2, Index)));
end;

procedure TAtlasLineChangesTests.NextAndPreviousWrap;
var
  Changes: TAtlasLineChangeList;
  Target: Integer;
begin
  Changes := TAtlasLineChanges.Compute(['0', '1', '2', '3', '4', '5', '6'],
    ['0', 'x', 'y', '2', '3', '4', 'z', '6']);
  // Änderungen ab Zeile 1 (x, y statt 1) und Zeile 6 (z statt 5).
  Assert.IsTrue(TAtlasLineChanges.Next(Changes, 0, 8, True, Target));
  Assert.AreEqual(1, Target);
  Assert.IsTrue(TAtlasLineChanges.Next(Changes, 1, 8, True, Target));
  Assert.AreEqual(6, Target, 'aus dem Block heraus zum nächsten');
  Assert.IsTrue(TAtlasLineChanges.Next(Changes, 6, 8, True, Target));
  Assert.AreEqual(1, Target, 'reihum');
  Assert.IsTrue(TAtlasLineChanges.Next(Changes, 4, 8, False, Target));
  Assert.AreEqual(1, Target);
  Assert.IsTrue(TAtlasLineChanges.Next(Changes, 1, 8, False, Target));
  Assert.AreEqual(6, Target, 'rückwärts reihum');
  Assert.IsFalse(TAtlasLineChanges.Next(nil, 3, 8, True, Target));
end;

procedure TAtlasLineChangesTests.RevertRestoresOldText;
const
  Old: array[0..5] of string = ('a', 'b', 'c', 'd', 'e', 'f');
var
  OldLines, NewLines: TArray<string>;
  Changes: TAtlasLineChangeList;
  Change: TAtlasLineChange;
  Index: Integer;
begin
  SetLength(OldLines, Length(Old));
  for Index := 0 to High(Old) do
    OldLines[Index] := Old[Index];
  NewLines := ['a', 'neu', 'b', 'C', 'd', 'f'];
  Changes := TAtlasLineChanges.Compute(OldLines, NewLines);
  // Jeden Block einzeln zurücksetzen.
  Change := Changes[0];
  Assert.AreEqual('a'#10'b'#10'C'#10'd'#10'f', Apply(NewLines, TAtlasLineChanges.Revert(Change, NewLines, #10)),
    'hinzugefügt entfernt');
  Change := Changes[1];
  Assert.AreEqual('a'#10'neu'#10'b'#10'c'#10'd'#10'f', Apply(NewLines, TAtlasLineChanges.Revert(Change, NewLines, #10)),
    'geändert zurück');
  Change := Changes[2];
  Assert.AreEqual('a'#10'neu'#10'b'#10'C'#10'd'#10'e'#10'f',
    Apply(NewLines, TAtlasLineChanges.Revert(Change, NewLines, #10)), 'gelöscht wieder da');
end;

procedure TAtlasLineChangesTests.RevertAtEndOfBuffer;
var
  NewLines: TArray<string>;
  Changes: TAtlasLineChangeList;
begin
  NewLines := ['a', 'b', 'x'];
  Changes := TAtlasLineChanges.Compute(['a', 'b'], NewLines);
  Assert.AreEqual('a'#10'b', Apply(NewLines, TAtlasLineChanges.Revert(Changes[0], NewLines, #10)),
    'angehängte Zeile samt Umbruch');
  NewLines := ['a'];
  Changes := TAtlasLineChanges.Compute(['a', 'b', 'c'], NewLines);
  Assert.AreEqual('a'#10'b'#10'c', Apply(NewLines, TAtlasLineChanges.Revert(Changes[0], NewLines, #10)),
    'am Ende gelöscht');
  NewLines := ['a', 'B'];
  Changes := TAtlasLineChanges.Compute(['a', 'b'], NewLines);
  Assert.AreEqual('a'#10'b', Apply(NewLines, TAtlasLineChanges.Revert(Changes[0], NewLines, #10)),
    'letzte Zeile geändert');
end;

procedure TAtlasLineChangesTests.BlameLineFollowsUnsavedEdits;
var
  Disk, Buffer: TArray<string>;
begin
  Disk := ['a', 'b', 'c'];
  Buffer := ['neu', 'a', 'b', 'C'];
  Assert.AreEqual(-1, TAtlasLineChanges.BlameLine(Disk, Buffer, 0), 'ungespeichert neu');
  Assert.AreEqual(0, TAtlasLineChanges.BlameLine(Disk, Buffer, 1));
  Assert.AreEqual(1, TAtlasLineChanges.BlameLine(Disk, Buffer, 2));
  Assert.AreEqual(-1, TAtlasLineChanges.BlameLine(Disk, Buffer, 3), 'ungespeichert geändert');
  Assert.AreEqual(2, TAtlasLineChanges.BlameLine(Disk, Disk, 2), 'gleich');
end;

procedure TAtlasLineChangesTests.AgeInUnits;
var
  Now_: TDateTime;
  Age: TAtlasAge;
begin
  Now_ := EncodeDateTime(2026, 10, 17, 12, 0, 0, 0);
  Assert.AreEqual(Ord(TAtlasAgeUnit.JustNow), Ord(TAtlasLineChanges.Age(Now_, IncSecond(Now_, -20)).Unit_));
  Age := TAtlasLineChanges.Age(Now_, IncMinute(Now_, -5));
  Assert.AreEqual(Ord(TAtlasAgeUnit.Minutes), Ord(Age.Unit_));
  Assert.AreEqual(5, Integer(Age.Count));
  Age := TAtlasLineChanges.Age(Now_, IncHour(Now_, -3));
  Assert.AreEqual(Ord(TAtlasAgeUnit.Hours), Ord(Age.Unit_));
  Assert.AreEqual(3, Integer(Age.Count));
  Assert.AreEqual(Ord(TAtlasAgeUnit.Yesterday), Ord(TAtlasLineChanges.Age(Now_, IncHour(Now_, -30)).Unit_));
  Age := TAtlasLineChanges.Age(Now_, IncDay(Now_, -3));
  Assert.AreEqual(Ord(TAtlasAgeUnit.Days), Ord(Age.Unit_));
  Assert.AreEqual(3, Integer(Age.Count));
  Age := TAtlasLineChanges.Age(Now_, IncDay(Now_, -70));
  Assert.AreEqual(Ord(TAtlasAgeUnit.Months), Ord(Age.Unit_));
  Assert.AreEqual(2, Integer(Age.Count));
  Age := TAtlasLineChanges.Age(Now_, IncDay(Now_, -800));
  Assert.AreEqual(Ord(TAtlasAgeUnit.Years), Ord(Age.Unit_));
  Assert.AreEqual(2, Integer(Age.Count));
  Assert.AreEqual(Ord(TAtlasAgeUnit.JustNow), Ord(TAtlasLineChanges.Age(Now_, IncDay(Now_, 1)).Unit_),
    'Zukunft');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasLineChangesTests);

end.
