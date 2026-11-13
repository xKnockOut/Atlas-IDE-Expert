unit Atlas.Core.Tests.Durations.Tests;

// Tests der Dauer an der Testlinse und der Liste der langsamsten Tests
// (#1772): Text der Marke, Grenze tests.slowMs, Sortierung und Grenze der
// Liste.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tests')]
  TAtlasTestDurationsTests = class
  public
    [Test]
    procedure SlowOnlyAboveLimit;
    [Test]
    procedure CaptionWithDurationAndSlow;
    [Test]
    procedure CaptionWithoutDurationUnchanged;
    [Test]
    procedure RowsSlowestFirstWithMarks;
  end;

implementation

uses
  Atlas.Text.TestResults,
  Atlas.Core.Tests.Durations;

function Texts: TAtlasTestDurationTexts;
begin
  Result := Default(TAtlasTestDurationTexts);
  Result.Duration := '%s · %s';
  Result.Slow := '%s · langsam';
  Result.DecimalSeparator := ',';
end;

function CaseOf(const AName: string; ADurationMs: Int64): TTestCaseResult;
begin
  Result := Default(TTestCaseResult);
  Result.FullName := AName;
  Result.UnitName := 'Demo.Tests';
  Result.DurationMs := ADurationMs;
  Result.Outcome := TTestOutcome.Passed;
end;

procedure TAtlasTestDurationsTests.SlowOnlyAboveLimit;
begin
  Assert.IsTrue(TAtlasTestDurations.IsSlow(800, 500), 'Sleep(800) bei 500 ms');
  Assert.IsFalse(TAtlasTestDurations.IsSlow(800, 1000), 'Sleep(800) bei 1000 ms');
  Assert.IsFalse(TAtlasTestDurations.IsSlow(500, 500), 'genau an der Grenze nicht');
  Assert.IsFalse(TAtlasTestDurations.IsSlow(5000, 0), 'ohne Grenze nie');
end;

procedure TAtlasTestDurationsTests.CaptionWithDurationAndSlow;
var
  mSlow: Boolean;
begin
  Assert.AreEqual('Test ausführen · bestanden · 12 ms',
    TAtlasTestDurations.Caption('Test ausführen · bestanden', 12, 12, 500, Texts, mSlow));
  Assert.IsFalse(mSlow);
  Assert.AreEqual('Tests der Klasse ausführen · bestanden · 1,2 s',
    TAtlasTestDurations.Caption('Tests der Klasse ausführen · bestanden', 1200, 400, 500, Texts, mSlow),
    'Klassenmarke: Summe, langsam nur über den langsamsten Test');
  Assert.IsFalse(mSlow);
  Assert.AreEqual('Test ausführen · bestanden · 800 ms · langsam',
    TAtlasTestDurations.Caption('Test ausführen · bestanden', 800, 800, 500, Texts, mSlow));
  Assert.IsTrue(mSlow);
end;

procedure TAtlasTestDurationsTests.CaptionWithoutDurationUnchanged;
var
  mSlow: Boolean;
begin
  Assert.AreEqual('Test ausführen', TAtlasTestDurations.Caption('Test ausführen', 0, 0, 500, Texts, mSlow));
  Assert.IsFalse(mSlow);
end;

procedure TAtlasTestDurationsTests.RowsSlowestFirstWithMarks;
var
  mRows: TArray<TAtlasTestSlowRow>;
begin
  mRows := TAtlasTestDurations.Rows([CaseOf('Demo.Tests.T.A', 20), CaseOf('Demo.Tests.T.B', 900),
    CaseOf('Demo.Tests.T.C', 0)], 500, ',');
  Assert.AreEqual(2, Integer(Length(mRows)), 'ohne Dauer nicht in der Liste');
  Assert.AreEqual('Demo.Tests.T.B', mRows[0].Test);
  Assert.AreEqual('900 ms', mRows[0].DurationText);
  Assert.IsTrue(mRows[0].Slow);
  Assert.AreEqual('Demo.Tests', mRows[0].UnitName);
  Assert.AreEqual('Demo.Tests.T.A', mRows[1].Test);
  Assert.IsFalse(mRows[1].Slow);
end;

end.
