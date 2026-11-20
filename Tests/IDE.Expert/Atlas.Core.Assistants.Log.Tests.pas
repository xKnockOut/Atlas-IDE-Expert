unit Atlas.Core.Assistants.Log.Tests;

// Tests für das Protokoll der Aufträge von KI-Assistenten (#2049): Annehmen nur eingeschaltet, Höchstzahl, Zählung
// für die Kopfzeile, Zurücknehmen und Unterschied aller Änderungen der Sitzung.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Assistants.Log;

type
  [TestFixture]
  [Category('Atlas.IDE.Assistants')]
  TAtlasAssistantsLogTests = class
  private
    FLog: TAtlasAssistantsLog;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure DisabledTakesNothing;
    [Test]
    procedure SwitchingOffClears;
    [Test]
    procedure MaxDropsTheOldest;
    [Test]
    procedure MaxIsClamped;
    [Test]
    procedure CountsByKind;
    [Test]
    procedure SinceIsTheFirstEntry;
    [Test]
    procedure RevertPlanRestoresTheOldBlock;
    [Test]
    procedure RevertPlanRefusesAfterOverlap;
    [Test]
    procedure RevertPlanRefusesTwice;
    [Test]
    procedure RevertPlanNeedsAnEdit;
    [Test]
    procedure SessionDiffSkipsReverted;
    [Test]
    procedure VersionCountsChanges;
  end;

implementation

uses
  System.SysUtils;

const
  cBefore = 'a'#10'b'#10'c'#10'd'#10'e'#10'f'#10'g'#10'h'#10;
  cAfter = 'a'#10'b'#10'c'#10'D'#10'e'#10'f'#10'g'#10'h'#10;

{ TAtlasAssistantsLogTests }

procedure TAtlasAssistantsLogTests.Setup;
begin
  FLog := TAtlasAssistantsLog.Create;
  FLog.Enabled := True;
end;

procedure TAtlasAssistantsLogTests.TearDown;
begin
  FreeAndNil(FLog);
end;

procedure TAtlasAssistantsLogTests.DisabledTakesNothing;
begin
  FLog.Enabled := False;
  Assert.AreEqual(0, FLog.Add(TAtlasAssistantsLog.PlainEntry(TAtlasAssistantsLogKind.Build, 'P.dproj', '', 'ok')));
  Assert.AreEqual(0, FLog.Count);
end;

procedure TAtlasAssistantsLogTests.SwitchingOffClears;
begin
  FLog.Add(TAtlasAssistantsLog.PlainEntry(TAtlasAssistantsLogKind.Build, 'P.dproj', '', 'ok'));
  FLog.Enabled := False;
  FLog.Enabled := True;
  Assert.AreEqual(0, FLog.Count);
end;

procedure TAtlasAssistantsLogTests.MaxDropsTheOldest;
var
  mIndex: Integer;
  mEntries: TArray<TAtlasAssistantsLogEntry>;
begin
  FLog.MaxEntries := TAtlasAssistantsLog.cMinMax;
  for mIndex := 1 to TAtlasAssistantsLog.cMinMax + 3 do
  begin
    FLog.Add(TAtlasAssistantsLog.PlainEntry(TAtlasAssistantsLogKind.Refused, 'A.pas', '', IntToStr(mIndex)));
  end;
  mEntries := FLog.Entries;
  Assert.AreEqual(TAtlasAssistantsLog.cMinMax, Integer(Length(mEntries)));
  Assert.AreEqual('4', mEntries[0].Detail);
end;

procedure TAtlasAssistantsLogTests.MaxIsClamped;
begin
  FLog.MaxEntries := 1;
  Assert.AreEqual(TAtlasAssistantsLog.cMinMax, FLog.MaxEntries);
  FLog.MaxEntries := 100000;
  Assert.AreEqual(TAtlasAssistantsLog.cMaxMax, FLog.MaxEntries);
end;

procedure TAtlasAssistantsLogTests.CountsByKind;
var
  mCounts: TAtlasAssistantsLogCounts;
begin
  FLog.Add(TAtlasAssistantsLog.EditEntry(TAtlasAssistantsLogKind.Edited, 'A.pas', 'x', cBefore, cAfter));
  FLog.Add(TAtlasAssistantsLog.EditEntry(TAtlasAssistantsLogKind.Edited, 'B.pas', 'x', cBefore, cAfter));
  FLog.Add(TAtlasAssistantsLog.PlainEntry(TAtlasAssistantsLogKind.Build, 'P.dproj', 'x', 'ok'));
  FLog.Add(TAtlasAssistantsLog.PlainEntry(TAtlasAssistantsLogKind.Refused, 'C.pas', 'x', 'nein'));
  FLog.Add(TAtlasAssistantsLog.EditEntry(TAtlasAssistantsLogKind.Held, 'D.pas', 'x', cBefore, cAfter));
  FLog.Add(TAtlasAssistantsLog.PlainEntry(TAtlasAssistantsLogKind.Question, '', 'x', 'Frage?'));
  mCounts := FLog.Counts;
  Assert.AreEqual(2, mCounts.Edits);
  Assert.AreEqual(1, mCounts.Builds);
  Assert.AreEqual(1, mCounts.Refused);
  Assert.AreEqual(1, mCounts.Held);
  Assert.AreEqual(1, mCounts.Questions);
end;

procedure TAtlasAssistantsLogTests.SinceIsTheFirstEntry;
var
  mEntry: TAtlasAssistantsLogEntry;
begin
  Assert.AreEqual(Double(0), Double(FLog.Since));
  mEntry := TAtlasAssistantsLog.PlainEntry(TAtlasAssistantsLogKind.Build, 'P.dproj', '', 'ok');
  mEntry.Time := EncodeDate(2026, 11, 20);
  FLog.Add(mEntry);
  mEntry.Time := EncodeDate(2026, 11, 21);
  FLog.Add(mEntry);
  Assert.AreEqual(Double(EncodeDate(2026, 11, 20)), Double(FLog.Since));
  FLog.Clear;
  Assert.AreEqual(Double(0), Double(FLog.Since));
end;

procedure TAtlasAssistantsLogTests.RevertPlanRestoresTheOldBlock;
var
  mId: Integer;
  mText: string;
begin
  mId := FLog.Add(TAtlasAssistantsLog.EditEntry(TAtlasAssistantsLogKind.Edited, 'A.pas', '', cBefore, cAfter));
  Assert.AreEqual<TAtlasLogRevertBlock>(TAtlasLogRevertBlock.None, FLog.RevertPlan(mId, '0'#10 + cAfter + 'i'#10,
    mText));
  Assert.AreEqual('0'#10 + cBefore + 'i'#10, mText);
end;

procedure TAtlasAssistantsLogTests.RevertPlanRefusesAfterOverlap;
var
  mId: Integer;
  mText: string;
begin
  mId := FLog.Add(TAtlasAssistantsLog.EditEntry(TAtlasAssistantsLogKind.Edited, 'A.pas', '', cBefore, cAfter));
  Assert.AreEqual<TAtlasLogRevertBlock>(TAtlasLogRevertBlock.ChangedSince,
    FLog.RevertPlan(mId, 'a'#10'b'#10'c'#10'X'#10'e'#10'f'#10'g'#10'h'#10, mText));
end;

procedure TAtlasAssistantsLogTests.RevertPlanRefusesTwice;
var
  mId: Integer;
  mText: string;
begin
  mId := FLog.Add(TAtlasAssistantsLog.EditEntry(TAtlasAssistantsLogKind.Edited, 'A.pas', '', cBefore, cAfter));
  FLog.MarkReverted(mId);
  Assert.AreEqual<TAtlasLogRevertBlock>(TAtlasLogRevertBlock.AlreadyReverted, FLog.RevertPlan(mId, cAfter, mText));
end;

procedure TAtlasAssistantsLogTests.RevertPlanNeedsAnEdit;
var
  mId: Integer;
  mText: string;
begin
  mId := FLog.Add(TAtlasAssistantsLog.EditEntry(TAtlasAssistantsLogKind.Held, 'A.pas', '', cBefore, cAfter));
  Assert.AreEqual<TAtlasLogRevertBlock>(TAtlasLogRevertBlock.NoChange, FLog.RevertPlan(mId, cAfter, mText));
  Assert.AreEqual<TAtlasLogRevertBlock>(TAtlasLogRevertBlock.NoChange, FLog.RevertPlan(4711, cAfter, mText));
end;

procedure TAtlasAssistantsLogTests.SessionDiffSkipsReverted;
var
  mId: Integer;
  mLines: TArray<string>;
begin
  FLog.Add(TAtlasAssistantsLog.EditEntry(TAtlasAssistantsLogKind.Edited, 'A.pas', '', cBefore, cAfter));
  mId := FLog.Add(TAtlasAssistantsLog.EditEntry(TAtlasAssistantsLogKind.Edited, 'B.pas', '', cBefore, cAfter));
  FLog.MarkReverted(mId);
  mLines := FLog.SessionDiffLines;
  Assert.AreEqual(3, Integer(Length(mLines)));
  Assert.AreEqual('=== A.pas · 4–4', mLines[0]);
  Assert.AreEqual('- d', mLines[1]);
  Assert.AreEqual('+ D', mLines[2]);
end;

procedure TAtlasAssistantsLogTests.VersionCountsChanges;
var
  mVersion: Integer;
  mId: Integer;
begin
  mVersion := FLog.Version;
  mId := FLog.Add(TAtlasAssistantsLog.EditEntry(TAtlasAssistantsLogKind.Edited, 'A.pas', '', cBefore, cAfter));
  Assert.IsTrue(FLog.Version > mVersion);
  mVersion := FLog.Version;
  FLog.MarkReverted(mId);
  Assert.IsTrue(FLog.Version > mVersion);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasAssistantsLogTests);

end.
