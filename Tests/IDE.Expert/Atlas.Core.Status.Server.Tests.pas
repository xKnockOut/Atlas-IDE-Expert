unit Atlas.Core.Status.Server.Tests;

// Inhalt des Fensters „Atlas-Server“ (#1356): Lesen der Antwort von
// atlas.server.status (neue und alte Server), langsamste Anfragen eindeutig
// sortiert, Balken gegen das Budget und sprachfreie Texte.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasServerSnapshotTests = class
  public
    [Test]
    procedure ReadsDiagnosticsOfNewServer;
    [Test]
    procedure OldServerKeepsOldValues;
    [Test]
    procedure InvalidAnswerIsNotValid;
    [Test]
    procedure RequestsSortedByMaximumThenMethod;
    [Test]
    procedure BarsUseBudgetOrTotal;
    [Test]
    procedure TextsAreLanguageFree;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Status.Server;

const
  cMb = 1024 * 1024;

function NewServerJson: string;
begin
  Result := '{"units":1234,"symbols":50000,"memoryBytes":524288000,"budgetBytes":419430400,' +
    '"workspaces":[],"requests":[{"method":"textDocument/hover","count":12,"averageMs":3.5,"maxMs":20,' +
    '"failed":0},{"method":"textDocument/completion","count":4,"averageMs":40,"maxMs":95.5,"failed":1}],' +
    '"process":{"pid":4711,"version":"1.2.0","started":"2026-10-29T12:00:00.000Z","uptimeMs":3900000,' +
    '"state":"checking"},' +
    '"memory":{"symbols":104857600,"usages":209715200,"libraryUnits":52428800,"treeCache":31457280,' +
    '"documents":1048576,"rest":124780544,"total":524288000,"budget":419430400,"overBudget":true},' +
    '"checkRun":{"serial":3,"active":false,"started":"2026-10-29T12:30:00.000Z","durationMs":8000,"units":120,' +
    '"unitMs":7900,"ruleMs":6000,"slowUnits":[{"name":"Haupt","file":"C:\\P\\Haupt.pas","ms":900.5},' +
    '{"name":"Ohne","ms":12}],"slowRules":[{"id":"unused-uses","ms":2500,"calls":120}]},' +
    '"queue":{"indexWaiting":1,"indexRunning":1,"checkWaiting":2,"checkRunning":0,"oldestWaitMs":3200},' +
    '"cacheHits":{"index":98,"trees":76,"treeCount":40},"markdown":"x"}';
end;

procedure TAtlasServerSnapshotTests.ReadsDiagnosticsOfNewServer;
var
  mSnapshot: TAtlasServerSnapshot;
begin
  mSnapshot := TAtlasServerSnapshot.Parse(NewServerJson);
  Assert.IsTrue(mSnapshot.Valid);
  Assert.IsTrue(mSnapshot.Known);
  Assert.AreEqual<Cardinal>(4711, mSnapshot.ProcessId);
  Assert.AreEqual('1.2.0', mSnapshot.Version);
  Assert.AreEqual<Int64>(3900000, mSnapshot.UptimeMs);
  Assert.IsTrue(mSnapshot.State = TAtlasServerState.Checking);
  Assert.AreEqual(1234, mSnapshot.Units);
  Assert.AreEqual<Int64>(200 * cMb, mSnapshot.Memory[TAtlasServerMemoryPart.Usages]);
  Assert.AreEqual<Int64>(30 * cMb, mSnapshot.Memory[TAtlasServerMemoryPart.TreeCache]);
  Assert.AreEqual<Int64>(500 * cMb, mSnapshot.MemoryTotal);
  Assert.AreEqual<Int64>(400 * cMb, mSnapshot.MemoryBudget);
  Assert.IsTrue(mSnapshot.OverBudget);
  Assert.AreEqual(3, mSnapshot.CheckSerial);
  Assert.IsFalse(mSnapshot.CheckActive);
  Assert.AreEqual<Int64>(8000, mSnapshot.CheckDurationMs);
  Assert.AreEqual(120, mSnapshot.CheckUnits);
  Assert.IsTrue(mSnapshot.CheckStarted > 0);
  Assert.AreEqual(2, Integer(Length(mSnapshot.SlowUnits)));
  Assert.AreEqual('Haupt', mSnapshot.SlowUnits[0].Name);
  Assert.AreEqual('C:\P\Haupt.pas', mSnapshot.SlowUnits[0].FileName);
  Assert.AreEqual(900.5, mSnapshot.SlowUnits[0].Ms, 0.001);
  Assert.AreEqual('', mSnapshot.SlowUnits[1].FileName, 'ohne Pfad');
  Assert.AreEqual(1, Integer(Length(mSnapshot.SlowRules)));
  Assert.AreEqual('unused-uses', mSnapshot.SlowRules[0].Id);
  Assert.AreEqual(120, mSnapshot.SlowRules[0].Calls);
  Assert.AreEqual(1, mSnapshot.IndexWaiting);
  Assert.AreEqual(1, mSnapshot.IndexRunning);
  Assert.AreEqual(2, mSnapshot.CheckWaiting);
  Assert.AreEqual<Int64>(3200, mSnapshot.OldestWaitMs);
  Assert.AreEqual(98, mSnapshot.IndexHitPercent);
  Assert.AreEqual(76, mSnapshot.TreeHitPercent);
end;

procedure TAtlasServerSnapshotTests.OldServerKeepsOldValues;
var
  mSnapshot: TAtlasServerSnapshot;
begin
  mSnapshot := TAtlasServerSnapshot.Parse('{"units":7,"memoryBytes":1048576,"budgetBytes":0,"requests":[]}');
  Assert.IsTrue(mSnapshot.Valid);
  Assert.IsFalse(mSnapshot.Known, 'ohne process');
  Assert.AreEqual(7, mSnapshot.Units);
  Assert.AreEqual<Int64>(cMb, mSnapshot.MemoryTotal);
  Assert.AreEqual(-1, mSnapshot.IndexHitPercent);
  Assert.AreEqual(0, mSnapshot.CheckSerial);
  Assert.IsTrue(mSnapshot.State = TAtlasServerState.Unknown);
end;

procedure TAtlasServerSnapshotTests.InvalidAnswerIsNotValid;
begin
  Assert.IsFalse(TAtlasServerSnapshot.Parse('').Valid);
  Assert.IsFalse(TAtlasServerSnapshot.Parse('kaputt').Valid);
  Assert.IsFalse(TAtlasServerSnapshot.Parse('[1,2]').Valid);
  Assert.AreEqual(-1, TAtlasServerSnapshot.Parse('').Units);
end;

procedure TAtlasServerSnapshotTests.RequestsSortedByMaximumThenMethod;
var
  mSnapshot: TAtlasServerSnapshot;
  mJson: string;
  mIndex: Integer;
begin
  mSnapshot := TAtlasServerSnapshot.Parse(NewServerJson);
  Assert.AreEqual(2, Integer(Length(mSnapshot.Requests)));
  Assert.AreEqual('textDocument/completion', mSnapshot.Requests[0].Method);
  Assert.AreEqual(1, mSnapshot.Requests[0].Failed);
  // Gleichstand im Maximum: nach Methode; mehr als zehn: die langsamsten zehn.
  mJson := '{"requests":[';
  for mIndex := 1 to 12 do
  begin
    if mIndex > 1 then
      mJson := mJson + ',';
    mJson := mJson + Format('{"method":"m%.2d","count":1,"averageMs":1,"maxMs":%d}', [mIndex, 100 - mIndex]);
  end;
  mJson := mJson + ',{"method":"a99","count":1,"averageMs":1,"maxMs":99}]}';
  mSnapshot := TAtlasServerSnapshot.Parse(mJson);
  Assert.AreEqual(TAtlasServerSnapshot.cRequestRows, Integer(Length(mSnapshot.Requests)));
  Assert.AreEqual('a99', mSnapshot.Requests[0].Method);
  Assert.AreEqual('m01', mSnapshot.Requests[1].Method);
  Assert.AreEqual('m09', mSnapshot.Requests[9].Method);
end;

procedure TAtlasServerSnapshotTests.BarsUseBudgetOrTotal;
var
  mSnapshot: TAtlasServerSnapshot;
begin
  mSnapshot := TAtlasServerSnapshot.Parse(NewServerJson);
  // Über dem Budget: Maßstab ist der Prozessspeicher (500 MB).
  Assert.AreEqual<Int64>(500 * cMb, mSnapshot.Scale);
  Assert.AreEqual(0.4, mSnapshot.Fraction(TAtlasServerMemoryPart.Usages), 0.0001);
  Assert.AreEqual(1.0, mSnapshot.TotalFraction, 0.0001);
  mSnapshot := Default(TAtlasServerSnapshot);
  mSnapshot.MemoryBudget := 400 * cMb;
  mSnapshot.MemoryTotal := 100 * cMb;
  mSnapshot.Memory[TAtlasServerMemoryPart.Symbols] := 40 * cMb;
  Assert.AreEqual(0.1, mSnapshot.Fraction(TAtlasServerMemoryPart.Symbols), 0.0001, 'gegen das Budget');
  Assert.AreEqual(0.25, mSnapshot.TotalFraction, 0.0001);
  Assert.AreEqual(0.0, Default(TAtlasServerSnapshot).Fraction(TAtlasServerMemoryPart.Rest), 0.0001, 'ohne Zahlen');
end;

procedure TAtlasServerSnapshotTests.TextsAreLanguageFree;
var
  mFormat: TFormatSettings;
begin
  mFormat := TFormatSettings.Invariant;
  Assert.AreEqual('45 s', TAtlasServerTexts.Duration(45999));
  Assert.AreEqual('12 min', TAtlasServerTexts.Duration(12 * 60000 + 5000));
  Assert.AreEqual('1 h 05 min', TAtlasServerTexts.Duration(3900000));
  Assert.AreEqual('50 h', TAtlasServerTexts.Duration(Int64(50) * 3600000));
  Assert.AreEqual('0 s', TAtlasServerTexts.Duration(-5));
  Assert.AreEqual('1.5 MB', TAtlasServerTexts.Megabytes(cMb + cMb div 2, mFormat));
  Assert.AreEqual('12', TAtlasServerTexts.Milliseconds(12.4, mFormat));
  Assert.AreEqual('3.5', TAtlasServerTexts.Milliseconds(3.46, mFormat));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasServerSnapshotTests);

end.
