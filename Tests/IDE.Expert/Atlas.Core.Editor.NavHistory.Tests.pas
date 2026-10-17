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
  History: TAtlasNavHistory;
  Target, Next: TAtlasNavPlace;
begin
  History := TAtlasNavHistory.Create;
  try
    // Strg+Klick von A (Zeile 12) nach B (40), dann nach C (7).
    History.Jumped(At('A.pas', 12), At('B.pas', 40));
    History.Jumped(At('B.pas', 40), At('C.pas', 7));
    Assert.IsTrue(History.StepBack(At('C.pas', 7), Target));
    Assert.AreEqual('B.pas', Target.FileName);
    Assert.IsTrue(History.StepBack(Target, Next));
    Assert.AreEqual('A.pas', Next.FileName);
    Assert.AreEqual(12, Next.Line);
    Assert.IsFalse(History.StepBack(Next, Target));
    // Und wieder vor: B, dann C.
    Assert.IsTrue(History.StepForward(At('A.pas', 12), Target));
    Assert.AreEqual('B.pas', Target.FileName);
    Assert.IsTrue(History.StepForward(Target, Next));
    Assert.AreEqual('C.pas', Next.FileName);
    Assert.IsFalse(History.StepForward(Next, Target));
  finally
    History.Free;
  end;
end;

procedure TAtlasNavHistoryTests.NewJumpClearsForward;
var
  History: TAtlasNavHistory;
  Target: TAtlasNavPlace;
begin
  History := TAtlasNavHistory.Create;
  try
    History.Jumped(At('A.pas', 1), At('B.pas', 1));
    Assert.IsTrue(History.StepBack(At('B.pas', 1), Target));
    Assert.AreEqual(1, History.ForwardCount);
    History.Jumped(At('A.pas', 1), At('D.pas', 1));
    Assert.AreEqual(0, History.ForwardCount);
    Assert.AreEqual(1, History.BackCount);
    // Kein Sprung: nichts gemerkt.
    History.Jumped(At('D.pas', 1), At('D.pas', 5));
    Assert.AreEqual(1, History.BackCount);
    // Dieselbe Stelle zweimal: ein Eintrag.
    History.Jumped(At('D.pas', 1), At('E.pas', 1));
    History.Jumped(At('D.pas', 1), At('F.pas', 1));
    Assert.AreEqual(2, History.BackCount);
  finally
    History.Free;
  end;
end;

procedure TAtlasNavHistoryTests.EntriesFollowInsertedAndDeletedLines;
var
  History: TAtlasNavHistory;
  Target: TAtlasNavPlace;
begin
  History := TAtlasNavHistory.Create;
  try
    History.Jumped(At('A.pas', 50), At('B.pas', 1));
    History.Edited(At('A.pas', 60));
    // 5 Zeilen oberhalb eingefügt: dieselbe Codezeile ist jetzt 55.
    History.LinesChanged('a.pas', 10, 5);
    // Unterhalb geändert: bleibt.
    History.LinesChanged('A.pas', 70, 3);
    // Andere Datei: bleibt.
    History.LinesChanged('B.pas', 1, 100);
    Assert.IsTrue(History.StepBack(At('B.pas', 1), Target));
    Assert.AreEqual(55, Target.Line);
    Assert.IsTrue(History.LastEdit(At('B.pas', 1), Target));
    Assert.AreEqual(65, Target.Line);
    // Zeilen 60 bis 69 gelöscht (Anker 59, 10 Zeilen): der Eintrag in 65 rückt an die Stelle.
    History.LinesChanged('A.pas', 59, -10);
    Assert.IsTrue(History.LastEdit(At('B.pas', 1), Target));
    Assert.AreEqual(59, Target.Line);
  finally
    History.Free;
  end;
end;

procedure TAtlasNavHistoryTests.LastEditGoesBackThroughEdits;
var
  History: TAtlasNavHistory;
  Target, Next: TAtlasNavPlace;
begin
  History := TAtlasNavHistory.Create;
  try
    Assert.IsFalse(History.LastEdit(At('A.pas', 1), Target));
    History.Edited(At('A.pas', 10));
    History.Edited(At('B.pas', 20));
    History.Edited(At('C.pas', 30));
    // Steht schon an der jüngsten: die davor.
    Assert.IsTrue(History.LastEdit(At('C.pas', 30), Target));
    Assert.AreEqual('B.pas', Target.FileName);
    Assert.IsTrue(History.LastEdit(Target, Next));
    Assert.AreEqual('A.pas', Next.FileName);
    // Am Anfang bleibt es bei der ältesten.
    Assert.IsTrue(History.LastEdit(Next, Target));
    Assert.AreEqual('A.pas', Target.FileName);
    // Neue Änderung: wieder vorn.
    History.Edited(At('D.pas', 1));
    Assert.IsTrue(History.LastEdit(At('A.pas', 10), Target));
    Assert.AreEqual('D.pas', Target.FileName);
  finally
    History.Free;
  end;
end;

procedure TAtlasNavHistoryTests.NeighbouringEditsMerge;
var
  History: TAtlasNavHistory;
begin
  History := TAtlasNavHistory.Create;
  try
    History.Edited(At('A.pas', 10));
    History.Edited(At('A.pas', 11));
    History.Edited(At('A.pas', 13));
    Assert.AreEqual(1, History.EditCount);
    History.Edited(At('A.pas', 20));
    History.Edited(At('B.pas', 20));
    Assert.AreEqual(3, History.EditCount);
  finally
    History.Free;
  end;
end;

procedure TAtlasNavHistoryTests.KeepsAtMostHundredEntries;
var
  History: TAtlasNavHistory;
  Index: Integer;
  Target, Next: TAtlasNavPlace;
begin
  History := TAtlasNavHistory.Create;
  try
    for Index := 1 to 150 do
    begin
      History.Jumped(At(Format('U%d.pas', [Index]), 1), At(Format('U%d.pas', [Index + 1]), 1));
      History.Edited(At(Format('U%d.pas', [Index]), 1));
    end;
    Assert.AreEqual(TAtlasNavHistory.MaxEntries, History.BackCount);
    Assert.AreEqual(TAtlasNavHistory.MaxEntries, History.EditCount);
    // Der älteste verbliebene Eintrag ist U51.
    Target := At('U151.pas', 1);
    while History.StepBack(Target, Next) do
      Target := Next;
    Assert.AreEqual('U51.pas', Target.FileName);
  finally
    History.Free;
  end;
end;

procedure TAtlasNavHistoryTests.ListAndJumpToEntry;
var
  History: TAtlasNavHistory;
  Entries: TArray<TAtlasNavListEntry>;
  Target, Next: TAtlasNavPlace;
begin
  History := TAtlasNavHistory.Create;
  try
    History.Jumped(At('A.pas', 1), At('B.pas', 1));
    History.Jumped(At('B.pas', 1), At('C.pas', 1));
    History.Jumped(At('C.pas', 1), At('D.pas', 1));
    Assert.IsTrue(History.StepBack(At('D.pas', 1), Target));
    History.Edited(At('X.pas', 5));
    Entries := History.Entries;
    // Vor (D), Zurück jüngster zuerst (B, A), Änderung (X).
    Assert.AreEqual(4, Integer(Length(Entries)));
    Assert.AreEqual('D.pas', Entries[0].Place.FileName);
    Assert.AreEqual(Ord(TAtlasNavKind.Ahead), Ord(Entries[0].Kind));
    Assert.AreEqual('B.pas', Entries[1].Place.FileName);
    Assert.AreEqual('A.pas', Entries[2].Place.FileName);
    Assert.AreEqual(Ord(TAtlasNavKind.Edit), Ord(Entries[3].Kind));
    // Direkt zu A: C und B wandern auf den Vor-Stapel.
    Assert.IsTrue(History.Jump(Entries[2], At('C.pas', 1), Target));
    Assert.AreEqual('A.pas', Target.FileName);
    Assert.AreEqual(0, History.BackCount);
    Assert.AreEqual(3, History.ForwardCount);
    Assert.IsTrue(History.StepForward(Target, Next));
    Assert.AreEqual('B.pas', Next.FileName);
    // Zur Änderung: zählt als neuer Sprung.
    Entries := History.Entries;
    Assert.IsTrue(History.Jump(Entries[High(Entries)], At('B.pas', 1), Target));
    Assert.AreEqual('X.pas', Target.FileName);
    Assert.AreEqual(0, History.ForwardCount);
  finally
    History.Free;
  end;
end;

procedure TAtlasNavHistoryTests.ExcerptIsTrimmedAndShortened;
begin
  Assert.AreEqual('if A then B;', TAtlasNavHistory.Excerpt(#9'  if A then B;  '));
  Assert.AreEqual(TAtlasNavHistory.MaxExcerpt, Integer(Length(TAtlasNavHistory.Excerpt(StringOfChar('x', 200)))));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasNavHistoryTests);

end.
