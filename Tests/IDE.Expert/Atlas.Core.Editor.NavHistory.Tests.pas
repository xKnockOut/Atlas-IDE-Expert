unit Atlas.Core.Editor.NavHistory.Tests;

// Tests für den Navigationsverlauf über Dateien hinweg (#504).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasNavHistoryTests = class
  public
    [Test]
    procedure JumpNeedsOtherFileOrMoreThanTenLines;
    [Test]
    procedure BackTwiceReturnsToFirstUnit;
    [Test]
    procedure NewJumpClearsForward;
    [Test]
    procedure EntriesFollowInsertedAndDeletedLines;
    [Test]
    procedure LastEditGoesBackThroughEdits;
    [Test]
    procedure NeighbouringEditsMerge;
    [Test]
    procedure KeepsAtMostHundredEntries;
    [Test]
    procedure ListAndJumpToEntry;
    [Test]
    procedure ExcerptIsTrimmedAndShortened;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Editor.NavHistory;

function At(const AFileName: string; ALine: Integer): TAtlasNavPlace;
begin
  Result := TAtlasNavPlace.Create(AFileName, ALine, 1);
end;

procedure TAtlasNavHistoryTests.JumpNeedsOtherFileOrMoreThanTenLines;
begin
  Assert.IsFalse(TAtlasNavHistory.IsJump(At('A.pas', 10), At('A.pas', 20)));
  Assert.IsTrue(TAtlasNavHistory.IsJump(At('A.pas', 10), At('A.pas', 21)));
  Assert.IsTrue(TAtlasNavHistory.IsJump(At('A.pas', 30), At('A.pas', 19)));
  Assert.IsTrue(TAtlasNavHistory.IsJump(At('A.pas', 10), At('B.pas', 10)));
  Assert.IsFalse(TAtlasNavHistory.IsJump(At('A.pas', 10), At('a.PAS', 12)));
  Assert.IsFalse(TAtlasNavHistory.IsJump(At('', 10), At('B.pas', 10)));
end;

procedure TAtlasNavHistoryTests.BackTwiceReturnsToFirstUnit;
var
  mHistory: TAtlasNavHistory;
  mTarget, mNext: TAtlasNavPlace;
begin
  mHistory := TAtlasNavHistory.Create;
  try
    // Strg+Klick von A (Zeile 12) nach B (40), dann nach C (7).
    mHistory.Jumped(At('A.pas', 12), At('B.pas', 40));
    mHistory.Jumped(At('B.pas', 40), At('C.pas', 7));
    Assert.IsTrue(mHistory.StepBack(At('C.pas', 7), mTarget));
    Assert.AreEqual('B.pas', mTarget.FileName);
    Assert.IsTrue(mHistory.StepBack(mTarget, mNext));
    Assert.AreEqual('A.pas', mNext.FileName);
    Assert.AreEqual(12, mNext.Line);
    Assert.IsFalse(mHistory.StepBack(mNext, mTarget));
    // Und wieder vor: B, dann C.
    Assert.IsTrue(mHistory.StepForward(At('A.pas', 12), mTarget));
    Assert.AreEqual('B.pas', mTarget.FileName);
    Assert.IsTrue(mHistory.StepForward(mTarget, mNext));
    Assert.AreEqual('C.pas', mNext.FileName);
    Assert.IsFalse(mHistory.StepForward(mNext, mTarget));
  finally
    mHistory.Free;
  end;
end;

procedure TAtlasNavHistoryTests.NewJumpClearsForward;
var
  mHistory: TAtlasNavHistory;
  mTarget: TAtlasNavPlace;
begin
  mHistory := TAtlasNavHistory.Create;
  try
    mHistory.Jumped(At('A.pas', 1), At('B.pas', 1));
    Assert.IsTrue(mHistory.StepBack(At('B.pas', 1), mTarget));
    Assert.AreEqual(1, mHistory.ForwardCount);
    mHistory.Jumped(At('A.pas', 1), At('D.pas', 1));
    Assert.AreEqual(0, mHistory.ForwardCount);
    Assert.AreEqual(1, mHistory.BackCount);
    // Kein Sprung: nichts gemerkt.
    mHistory.Jumped(At('D.pas', 1), At('D.pas', 5));
    Assert.AreEqual(1, mHistory.BackCount);
    // Dieselbe Stelle zweimal: ein Eintrag.
    mHistory.Jumped(At('D.pas', 1), At('E.pas', 1));
    mHistory.Jumped(At('D.pas', 1), At('F.pas', 1));
    Assert.AreEqual(2, mHistory.BackCount);
  finally
    mHistory.Free;
  end;
end;

procedure TAtlasNavHistoryTests.EntriesFollowInsertedAndDeletedLines;
var
  mHistory: TAtlasNavHistory;
  mTarget: TAtlasNavPlace;
begin
  mHistory := TAtlasNavHistory.Create;
  try
    mHistory.Jumped(At('A.pas', 50), At('B.pas', 1));
    mHistory.Edited(At('A.pas', 60));
    // 5 Zeilen oberhalb eingefügt: dieselbe Codezeile ist jetzt 55.
    mHistory.LinesChanged('a.pas', 10, 5);
    // Unterhalb geändert: bleibt.
    mHistory.LinesChanged('A.pas', 70, 3);
    // Andere Datei: bleibt.
    mHistory.LinesChanged('B.pas', 1, 100);
    Assert.IsTrue(mHistory.StepBack(At('B.pas', 1), mTarget));
    Assert.AreEqual(55, mTarget.Line);
    Assert.IsTrue(mHistory.LastEdit(At('B.pas', 1), mTarget));
    Assert.AreEqual(65, mTarget.Line);
    // Zeilen 60 bis 69 gelöscht (Anker 59, 10 Zeilen): der Eintrag in 65 rückt an die Stelle.
    mHistory.LinesChanged('A.pas', 59, -10);
    Assert.IsTrue(mHistory.LastEdit(At('B.pas', 1), mTarget));
    Assert.AreEqual(59, mTarget.Line);
  finally
    mHistory.Free;
  end;
end;

procedure TAtlasNavHistoryTests.LastEditGoesBackThroughEdits;
var
  mHistory: TAtlasNavHistory;
  mTarget, mNext: TAtlasNavPlace;
begin
  mHistory := TAtlasNavHistory.Create;
  try
    Assert.IsFalse(mHistory.LastEdit(At('A.pas', 1), mTarget));
    mHistory.Edited(At('A.pas', 10));
    mHistory.Edited(At('B.pas', 20));
    mHistory.Edited(At('C.pas', 30));
    // Steht schon an der jüngsten: die davor.
    Assert.IsTrue(mHistory.LastEdit(At('C.pas', 30), mTarget));
    Assert.AreEqual('B.pas', mTarget.FileName);
    Assert.IsTrue(mHistory.LastEdit(mTarget, mNext));
    Assert.AreEqual('A.pas', mNext.FileName);
    // Am Anfang bleibt es bei der ältesten.
    Assert.IsTrue(mHistory.LastEdit(mNext, mTarget));
    Assert.AreEqual('A.pas', mTarget.FileName);
    // Neue Änderung: wieder vorn.
    mHistory.Edited(At('D.pas', 1));
    Assert.IsTrue(mHistory.LastEdit(At('A.pas', 10), mTarget));
    Assert.AreEqual('D.pas', mTarget.FileName);
  finally
    mHistory.Free;
  end;
end;

procedure TAtlasNavHistoryTests.NeighbouringEditsMerge;
var
  mHistory: TAtlasNavHistory;
begin
  mHistory := TAtlasNavHistory.Create;
  try
    mHistory.Edited(At('A.pas', 10));
    mHistory.Edited(At('A.pas', 11));
    mHistory.Edited(At('A.pas', 13));
    Assert.AreEqual(1, mHistory.EditCount);
    mHistory.Edited(At('A.pas', 20));
    mHistory.Edited(At('B.pas', 20));
    Assert.AreEqual(3, mHistory.EditCount);
  finally
    mHistory.Free;
  end;
end;

procedure TAtlasNavHistoryTests.KeepsAtMostHundredEntries;
var
  mHistory: TAtlasNavHistory;
  mIndex: Integer;
  mTarget, mNext: TAtlasNavPlace;
begin
  mHistory := TAtlasNavHistory.Create;
  try
    for mIndex := 1 to 150 do
    begin
      mHistory.Jumped(At(Format('U%d.pas', [mIndex]), 1), At(Format('U%d.pas', [mIndex + 1]), 1));
      mHistory.Edited(At(Format('U%d.pas', [mIndex]), 1));
    end;
    Assert.AreEqual(TAtlasNavHistory.cMaxEntries, mHistory.BackCount);
    Assert.AreEqual(TAtlasNavHistory.cMaxEntries, mHistory.EditCount);
    // Der älteste verbliebene Eintrag ist U51.
    mTarget := At('U151.pas', 1);
    while mHistory.StepBack(mTarget, mNext) do
    begin
      mTarget := mNext;
    end;
    Assert.AreEqual('U51.pas', mTarget.FileName);
  finally
    mHistory.Free;
  end;
end;

procedure TAtlasNavHistoryTests.ListAndJumpToEntry;
var
  mHistory: TAtlasNavHistory;
  mEntries: TArray<TAtlasNavListEntry>;
  mTarget, mNext: TAtlasNavPlace;
begin
  mHistory := TAtlasNavHistory.Create;
  try
    mHistory.Jumped(At('A.pas', 1), At('B.pas', 1));
    mHistory.Jumped(At('B.pas', 1), At('C.pas', 1));
    mHistory.Jumped(At('C.pas', 1), At('D.pas', 1));
    Assert.IsTrue(mHistory.StepBack(At('D.pas', 1), mTarget));
    mHistory.Edited(At('X.pas', 5));
    mEntries := mHistory.Entries;
    // Vor (D), Zurück jüngster zuerst (B, A), Änderung (X).
    Assert.AreEqual(4, Integer(Length(mEntries)));
    Assert.AreEqual('D.pas', mEntries[0].Place.FileName);
    Assert.AreEqual(Ord(TAtlasNavKind.Ahead), Ord(mEntries[0].Kind));
    Assert.AreEqual('B.pas', mEntries[1].Place.FileName);
    Assert.AreEqual('A.pas', mEntries[2].Place.FileName);
    Assert.AreEqual(Ord(TAtlasNavKind.Edit), Ord(mEntries[3].Kind));
    // Direkt zu A: C und B wandern auf den Vor-Stapel.
    Assert.IsTrue(mHistory.Jump(mEntries[2], At('C.pas', 1), mTarget));
    Assert.AreEqual('A.pas', mTarget.FileName);
    Assert.AreEqual(0, mHistory.BackCount);
    Assert.AreEqual(3, mHistory.ForwardCount);
    Assert.IsTrue(mHistory.StepForward(mTarget, mNext));
    Assert.AreEqual('B.pas', mNext.FileName);
    // Zur Änderung: zählt als neuer Sprung.
    mEntries := mHistory.Entries;
    Assert.IsTrue(mHistory.Jump(mEntries[High(mEntries)], At('B.pas', 1), mTarget));
    Assert.AreEqual('X.pas', mTarget.FileName);
    Assert.AreEqual(0, mHistory.ForwardCount);
  finally
    mHistory.Free;
  end;
end;

procedure TAtlasNavHistoryTests.ExcerptIsTrimmedAndShortened;
begin
  Assert.AreEqual('if A then B;', TAtlasNavHistory.Excerpt(#9'  if A then B;  '));
  Assert.AreEqual(TAtlasNavHistory.cMaxExcerpt, Integer(Length(TAtlasNavHistory.Excerpt(StringOfChar('x', 200)))));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasNavHistoryTests);

end.
