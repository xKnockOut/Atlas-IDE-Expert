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
  mText: string;
  mIndex, mStart, mStop: Integer;

  function Offset(ALine, ACharacter: Integer): Integer;
  var
    mLine: Integer;
  begin
    Result := 0;
    for mLine := 0 to ALine - 1 do
    begin
      Inc(Result, Length(ALines[mLine]) + 1);
    end;
    Inc(Result, ACharacter);
  end;

begin
  mText := '';
  for mIndex := 0 to High(ALines) do
  begin
    if mIndex > 0 then
    begin
      mText := mText + #10;
    end;
    mText := mText + ALines[mIndex];
  end;
  mStart := Offset(AEdit.StartLine, AEdit.StartCharacter);
  mStop := Offset(AEdit.EndLine, AEdit.EndCharacter);
  Result := Copy(mText, 1, mStart) + AEdit.NewText + Copy(mText, mStop + 1, MaxInt);
end;

procedure TAtlasLineChangesTests.ComputesAddedModifiedDeleted;
var
  mChanges: TAtlasLineChangeList;
begin
  mChanges := TAtlasLineChanges.Compute(['a', 'b', 'c', 'd', 'e', 'f'], ['a', 'neu', 'b', 'C', 'd', 'f']);
  Assert.AreEqual(3, Integer(Length(mChanges)));
  Assert.AreEqual(Ord(TAtlasLineChangeKind.Added), Ord(mChanges[0].Kind));
  Assert.AreEqual(1, mChanges[0].Line);
  Assert.AreEqual(1, Integer(mChanges[0].Count));
  Assert.AreEqual(Ord(TAtlasLineChangeKind.Modified), Ord(mChanges[1].Kind));
  Assert.AreEqual(3, mChanges[1].Line);
  Assert.AreEqual('c', string.Join('|', mChanges[1].OldLines));
  Assert.AreEqual(Ord(TAtlasLineChangeKind.Deleted), Ord(mChanges[2].Kind));
  Assert.AreEqual(5, mChanges[2].Line, 'vor f');
  Assert.AreEqual(0, Integer(mChanges[2].Count));
  Assert.AreEqual('e', string.Join('|', mChanges[2].OldLines));
  Assert.AreEqual(0, Integer(Length(TAtlasLineChanges.Compute(['a', 'b'], ['a', 'b']))));
end;

procedure TAtlasLineChangesTests.MarksPerLine;
var
  mChanges: TAtlasLineChangeList;
  mIndex: Integer;
begin
  mChanges := TAtlasLineChanges.Compute(['a', 'b', 'c', 'd'], ['a', 'x', 'y', 'c']);
  // b → x, y (geändert), d gelöscht am Ende.
  Assert.AreEqual(Ord(TAtlasLineMark.None), Ord(TAtlasLineChanges.MarkAt(mChanges, 0, mIndex)));
  Assert.AreEqual(-1, mIndex);
  Assert.AreEqual(Ord(TAtlasLineMark.Modified), Ord(TAtlasLineChanges.MarkAt(mChanges, 1, mIndex)));
  Assert.AreEqual(0, mIndex);
  Assert.AreEqual(Ord(TAtlasLineMark.Modified), Ord(TAtlasLineChanges.MarkAt(mChanges, 2, mIndex)));
  Assert.AreEqual(Ord(TAtlasLineMark.None), Ord(TAtlasLineChanges.MarkAt(mChanges, 3, mIndex)));
  Assert.AreEqual(1, TAtlasLineChanges.DeletedAt(mChanges, 3, 4), 'Löschung am Ende an der letzten Zeile');
  Assert.AreEqual(-1, TAtlasLineChanges.DeletedAt(mChanges, 2, 4));
  Assert.AreEqual(0, TAtlasLineChanges.ChangeAt(mChanges, 2, 4));
  Assert.AreEqual(1, TAtlasLineChanges.ChangeAt(mChanges, 3, 4));
  mChanges := TAtlasLineChanges.Compute(['a', 'b'], ['a', 'b', 'neu']);
  Assert.AreEqual(Ord(TAtlasLineMark.Added), Ord(TAtlasLineChanges.MarkAt(mChanges, 2, mIndex)));
end;

procedure TAtlasLineChangesTests.NextAndPreviousWrap;
var
  mChanges: TAtlasLineChangeList;
  mTarget: Integer;
begin
  mChanges := TAtlasLineChanges.Compute(['0', '1', '2', '3', '4', '5', '6'],
    ['0', 'x', 'y', '2', '3', '4', 'z', '6']);
  // Änderungen ab Zeile 1 (x, y statt 1) und Zeile 6 (z statt 5).
  Assert.IsTrue(TAtlasLineChanges.Next(mChanges, 0, 8, True, mTarget));
  Assert.AreEqual(1, mTarget);
  Assert.IsTrue(TAtlasLineChanges.Next(mChanges, 1, 8, True, mTarget));
  Assert.AreEqual(6, mTarget, 'aus dem Block heraus zum nächsten');
  Assert.IsTrue(TAtlasLineChanges.Next(mChanges, 6, 8, True, mTarget));
  Assert.AreEqual(1, mTarget, 'reihum');
  Assert.IsTrue(TAtlasLineChanges.Next(mChanges, 4, 8, False, mTarget));
  Assert.AreEqual(1, mTarget);
  Assert.IsTrue(TAtlasLineChanges.Next(mChanges, 1, 8, False, mTarget));
  Assert.AreEqual(6, mTarget, 'rückwärts reihum');
  Assert.IsFalse(TAtlasLineChanges.Next(nil, 3, 8, True, mTarget));
end;

procedure TAtlasLineChangesTests.RevertRestoresOldText;
const
  cOld: array[0..5] of string = ('a', 'b', 'c', 'd', 'e', 'f');
var
  mOldLines, mNewLines: TArray<string>;
  mChanges: TAtlasLineChangeList;
  mChange: TAtlasLineChange;
  mIndex: Integer;
begin
  SetLength(mOldLines, Length(cOld));
  for mIndex := 0 to High(cOld) do
  begin
    mOldLines[mIndex] := cOld[mIndex];
  end;
  mNewLines := ['a', 'neu', 'b', 'C', 'd', 'f'];
  mChanges := TAtlasLineChanges.Compute(mOldLines, mNewLines);
  // Jeden Block einzeln zurücksetzen.
  mChange := mChanges[0];
  Assert.AreEqual('a'#10'b'#10'C'#10'd'#10'f', Apply(mNewLines, TAtlasLineChanges.Revert(mChange, mNewLines, #10)),
    'hinzugefügt entfernt');
  mChange := mChanges[1];
  Assert.AreEqual('a'#10'neu'#10'b'#10'c'#10'd'#10'f', Apply(mNewLines, TAtlasLineChanges.Revert(mChange, mNewLines, #10)),
    'geändert zurück');
  mChange := mChanges[2];
  Assert.AreEqual('a'#10'neu'#10'b'#10'C'#10'd'#10'e'#10'f',
    Apply(mNewLines, TAtlasLineChanges.Revert(mChange, mNewLines, #10)), 'gelöscht wieder da');
end;

procedure TAtlasLineChangesTests.RevertAtEndOfBuffer;
var
  mNewLines: TArray<string>;
  mChanges: TAtlasLineChangeList;
begin
  mNewLines := ['a', 'b', 'x'];
  mChanges := TAtlasLineChanges.Compute(['a', 'b'], mNewLines);
  Assert.AreEqual('a'#10'b', Apply(mNewLines, TAtlasLineChanges.Revert(mChanges[0], mNewLines, #10)),
    'angehängte Zeile samt Umbruch');
  mNewLines := ['a'];
  mChanges := TAtlasLineChanges.Compute(['a', 'b', 'c'], mNewLines);
  Assert.AreEqual('a'#10'b'#10'c', Apply(mNewLines, TAtlasLineChanges.Revert(mChanges[0], mNewLines, #10)),
    'am Ende gelöscht');
  mNewLines := ['a', 'B'];
  mChanges := TAtlasLineChanges.Compute(['a', 'b'], mNewLines);
  Assert.AreEqual('a'#10'b', Apply(mNewLines, TAtlasLineChanges.Revert(mChanges[0], mNewLines, #10)),
    'letzte Zeile geändert');
end;

procedure TAtlasLineChangesTests.BlameLineFollowsUnsavedEdits;
var
  mDisk, mBuffer: TArray<string>;
begin
  mDisk := ['a', 'b', 'c'];
  mBuffer := ['neu', 'a', 'b', 'C'];
  Assert.AreEqual(-1, TAtlasLineChanges.BlameLine(mDisk, mBuffer, 0), 'ungespeichert neu');
  Assert.AreEqual(0, TAtlasLineChanges.BlameLine(mDisk, mBuffer, 1));
  Assert.AreEqual(1, TAtlasLineChanges.BlameLine(mDisk, mBuffer, 2));
  Assert.AreEqual(-1, TAtlasLineChanges.BlameLine(mDisk, mBuffer, 3), 'ungespeichert geändert');
  Assert.AreEqual(2, TAtlasLineChanges.BlameLine(mDisk, mDisk, 2), 'gleich');
end;

procedure TAtlasLineChangesTests.AgeInUnits;
var
  mNow_: TDateTime;
  mAge: TAtlasAge;
begin
  mNow_ := EncodeDateTime(2026, 10, 17, 12, 0, 0, 0);
  Assert.AreEqual(Ord(TAtlasAgeUnit.JustNow), Ord(TAtlasLineChanges.Age(mNow_, IncSecond(mNow_, -20)).Unit_));
  mAge := TAtlasLineChanges.Age(mNow_, IncMinute(mNow_, -5));
  Assert.AreEqual(Ord(TAtlasAgeUnit.Minutes), Ord(mAge.Unit_));
  Assert.AreEqual(5, Integer(mAge.Count));
  mAge := TAtlasLineChanges.Age(mNow_, IncHour(mNow_, -3));
  Assert.AreEqual(Ord(TAtlasAgeUnit.Hours), Ord(mAge.Unit_));
  Assert.AreEqual(3, Integer(mAge.Count));
  Assert.AreEqual(Ord(TAtlasAgeUnit.Yesterday), Ord(TAtlasLineChanges.Age(mNow_, IncHour(mNow_, -30)).Unit_));
  mAge := TAtlasLineChanges.Age(mNow_, IncDay(mNow_, -3));
  Assert.AreEqual(Ord(TAtlasAgeUnit.Days), Ord(mAge.Unit_));
  Assert.AreEqual(3, Integer(mAge.Count));
  mAge := TAtlasLineChanges.Age(mNow_, IncDay(mNow_, -70));
  Assert.AreEqual(Ord(TAtlasAgeUnit.Months), Ord(mAge.Unit_));
  Assert.AreEqual(2, Integer(mAge.Count));
  mAge := TAtlasLineChanges.Age(mNow_, IncDay(mNow_, -800));
  Assert.AreEqual(Ord(TAtlasAgeUnit.Years), Ord(mAge.Unit_));
  Assert.AreEqual(2, Integer(mAge.Count));
  Assert.AreEqual(Ord(TAtlasAgeUnit.JustNow), Ord(TAtlasLineChanges.Age(mNow_, IncDay(mNow_, 1)).Unit_),
    'Zukunft');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasLineChangesTests);

end.
