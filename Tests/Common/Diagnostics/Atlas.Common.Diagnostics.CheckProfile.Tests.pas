unit Atlas.Common.Diagnostics.CheckProfile.Tests;

// Tests für das Zeitprofil eines Prüflaufs (#1356): Sammeln je Unit und Regel,
// die langsamsten mit eindeutiger Reihenfolge bei Gleichstand, Summen, die
// Anbindung der Regel-Engine und der Bericht von --check --timings.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TCheckProfileTests = class
  public
    [Test]
    procedure SlowestUnitsComeFirstWithSums;
    [Test]
    procedure TiesAreSortedByName;
    [Test]
    procedure RepeatedUnitAddsUp;
    [Test]
    procedure RulesSumCallsAndTime;
    [Test]
    procedure BeginRunForgetsPreviousRun;
    [Test]
    procedure RunningProfileUsesElapsedTime;
    [Test]
    procedure EngineReportsRulesToAttachedProfiler;
    [Test]
    procedure WithoutProfilerEngineReportsNothing;
    [Test]
    procedure AnonymizedRenamesUnitsAndDropsPaths;
    [Test]
    procedure JsonAndMarkdownContainTables;
    [Test]
    procedure MarkdownEmptyBeforeFirstRun;
    [Test]
    procedure TimingsReportAsMarkdownAndJson;
    [Test]
    procedure TicksConvertWithoutOverflow;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.JSON,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Checker,
  Atlas.Common.Diagnostics.CheckProfile,
  Atlas.Tests.RuleAssert;

procedure TCheckProfileTests.SlowestUnitsComeFirstWithSums;
var
  mProfiler: TCheckProfiler;
  mProfile: TCheckRunProfile;
  mIndex: Integer;
begin
  mProfiler := TCheckProfiler.Create;
  try
    mProfiler.BeginRun(EncodeDate(2026, 10, 29));
    for mIndex := 1 to 12 do
      mProfiler.AddUnit(Format('C:\P\Unit%.2d.pas', [mIndex]), mIndex * 1000);
    mProfiler.FinishRun(80);
    mProfile := mProfiler.Snapshot(TCheckRunProfile.cTop);
    Assert.AreEqual(10, Integer(Length(mProfile.SlowUnits)));
    Assert.AreEqual('Unit12', mProfile.SlowUnits[0].Name);
    Assert.AreEqual('C:\P\Unit12.pas', mProfile.SlowUnits[0].FileName);
    Assert.AreEqual(12.0, mProfile.SlowUnits[0].Ms, 0.001);
    Assert.AreEqual('Unit03', mProfile.SlowUnits[9].Name);
    // Summe über alle Units, nicht nur die angezeigten: 1 + … + 12 ms.
    Assert.AreEqual(78.0, mProfile.UnitMs, 0.001);
    Assert.AreEqual(12, mProfile.Units);
    Assert.AreEqual<Int64>(80, mProfile.DurationMs);
    Assert.IsFalse(mProfile.Active);
  finally
    mProfiler.Free;
  end;
end;

procedure TCheckProfileTests.TiesAreSortedByName;
var
  mProfiler: TCheckProfiler;
  mProfile: TCheckRunProfile;
begin
  mProfiler := TCheckProfiler.Create;
  try
    mProfiler.BeginRun(Now);
    mProfiler.AddUnit('C:\P\Zeta.pas', 5000);
    mProfiler.AddUnit('C:\P\Alpha.pas', 5000);
    mProfiler.AddUnit('C:\Q\Alpha.pas', 5000);
    mProfiler.AddRule('z-regel', 2000);
    mProfiler.AddRule('a-regel', 2000);
    mProfile := mProfiler.Snapshot(TCheckRunProfile.cTop);
    Assert.AreEqual('C:\P\Alpha.pas', mProfile.SlowUnits[0].FileName);
    Assert.AreEqual('C:\Q\Alpha.pas', mProfile.SlowUnits[1].FileName);
    Assert.AreEqual('Zeta', mProfile.SlowUnits[2].Name);
    Assert.AreEqual('a-regel', mProfile.SlowRules[0].Id);
    Assert.AreEqual('z-regel', mProfile.SlowRules[1].Id);
  finally
    mProfiler.Free;
  end;
end;

procedure TCheckProfileTests.RepeatedUnitAddsUp;
var
  mProfiler: TCheckProfiler;
  mProfile: TCheckRunProfile;
begin
  mProfiler := TCheckProfiler.Create;
  try
    mProfiler.BeginRun(Now);
    // Erster Versuch mit abgelaufener Frist, zweiter ohne: zusammen eine Unit.
    mProfiler.AddUnit('C:\P\Langsam.pas', 3000000);
    mProfiler.AddUnit('c:\p\langsam.pas', 1500000);
    mProfile := mProfiler.Snapshot(TCheckRunProfile.cTop);
    Assert.AreEqual(1, mProfile.Units);
    Assert.AreEqual(4500.0, mProfile.SlowUnits[0].Ms, 0.001);
  finally
    mProfiler.Free;
  end;
end;

procedure TCheckProfileTests.RulesSumCallsAndTime;
var
  mProfiler: TCheckProfiler;
  mProfile: TCheckRunProfile;
begin
  mProfiler := TCheckProfiler.Create;
  try
    mProfiler.BeginRun(Now);
    mProfiler.AddRule('empty-except', 400);
    mProfiler.AddRule('empty-except', 300);
    mProfiler.AddRule('hides-virtual', 2700000);
    mProfile := mProfiler.Snapshot(TCheckRunProfile.cTop);
    Assert.AreEqual('hides-virtual', mProfile.SlowRules[0].Id);
    Assert.AreEqual(1, mProfile.SlowRules[0].Calls);
    Assert.AreEqual('empty-except', mProfile.SlowRules[1].Id);
    Assert.AreEqual(2, mProfile.SlowRules[1].Calls);
    // Kurze Regeln verschwinden in der Summe nicht: 0,7 ms.
    Assert.AreEqual(0.7, mProfile.SlowRules[1].Ms, 0.001);
    Assert.AreEqual(2700.7, mProfile.RuleMs, 0.001);
  finally
    mProfiler.Free;
  end;
end;

procedure TCheckProfileTests.BeginRunForgetsPreviousRun;
var
  mProfiler: TCheckProfiler;
  mProfile: TCheckRunProfile;
begin
  mProfiler := TCheckProfiler.Create;
  try
    mProfiler.BeginRun(Now);
    mProfiler.AddUnit('C:\P\A.pas', 1000);
    mProfiler.AddRule('r', 1000);
    mProfiler.FinishRun(5);
    mProfiler.BeginRun(Now);
    mProfile := mProfiler.Snapshot(TCheckRunProfile.cTop);
    Assert.AreEqual(2, mProfile.Serial);
    Assert.IsTrue(mProfile.Active);
    Assert.AreEqual(0, Integer(Length(mProfile.SlowUnits)));
    Assert.AreEqual(0, Integer(Length(mProfile.SlowRules)));
  finally
    mProfiler.Free;
  end;
end;

procedure TCheckProfileTests.RunningProfileUsesElapsedTime;
var
  mProfiler: TCheckProfiler;
begin
  mProfiler := TCheckProfiler.Create;
  try
    mProfiler.BeginRun(Now);
    Assert.AreEqual<Int64>(1234, mProfiler.Snapshot(TCheckRunProfile.cTop, 1234).DurationMs);
    mProfiler.FinishRun(2000);
    // Fertig: die gemessene Dauer, nicht die übergebene.
    Assert.AreEqual<Int64>(2000, mProfiler.Snapshot(TCheckRunProfile.cTop, 1234).DurationMs);
  finally
    mProfiler.Free;
  end;
end;

procedure TCheckProfileTests.EngineReportsRulesToAttachedProfiler;
var
  mProfiler, mPrevious: TCheckProfiler;
  mRule: IRule;
  mProfile: TCheckRunProfile;
begin
  mRule := TCallbackRule.Create('profil-testregel',
    procedure
    begin
    end);
  mProfiler := TCheckProfiler.Create;
  try
    mProfiler.BeginRun(Now);
    mPrevious := TCheckProfiler.Attach(mProfiler);
    try
      TFileChecker.CheckText([mRule], TServerSettings.Default, 'A.pas', 'unit A; interface implementation end.');
      TFileChecker.CheckText([mRule], TServerSettings.Default, 'B.pas', 'unit B; interface implementation end.');
    finally
      TCheckProfiler.Attach(mPrevious);
    end;
    mProfile := mProfiler.Snapshot(TCheckRunProfile.cTop);
    Assert.AreEqual(1, Integer(Length(mProfile.SlowRules)));
    Assert.AreEqual('profil-testregel', mProfile.SlowRules[0].Id);
    Assert.AreEqual(2, mProfile.SlowRules[0].Calls);
  finally
    mProfiler.Free;
  end;
end;

procedure TCheckProfileTests.WithoutProfilerEngineReportsNothing;
var
  mProfiler: TCheckProfiler;
  mRule: IRule;
begin
  mRule := TCallbackRule.Create('profil-testregel',
    procedure
    begin
    end);
  mProfiler := TCheckProfiler.Create;
  try
    mProfiler.BeginRun(Now);
    // Nicht angehängt: Die Engine misst, meldet aber an niemanden.
    TFileChecker.CheckText([mRule], TServerSettings.Default, 'A.pas', 'unit A; interface implementation end.');
    Assert.AreEqual(0, Integer(Length(mProfiler.Snapshot(TCheckRunProfile.cTop).SlowRules)));
  finally
    mProfiler.Free;
  end;
end;

procedure TCheckProfileTests.AnonymizedRenamesUnitsAndDropsPaths;
var
  mProfiler: TCheckProfiler;
  mProfile: TCheckRunProfile;
  mJson: TJSONObject;
begin
  mProfiler := TCheckProfiler.Create;
  try
    mProfiler.BeginRun(Now);
    mProfiler.AddUnit('C:\Firma\Geheim.Kunden.pas', 1000);
    mProfile := mProfiler.Snapshot(TCheckRunProfile.cTop).Anonymized(
      function(const AName: string): string
      begin
        Result := 'name#1';
      end);
    Assert.AreEqual('name#1', mProfile.SlowUnits[0].Name);
    Assert.AreEqual('', mProfile.SlowUnits[0].FileName);
    mJson := mProfile.ToJson;
    try
      Assert.IsFalse(mJson.ToJSON.Contains('Geheim'), 'kein Name im JSON');
    finally
      mJson.Free;
    end;
  finally
    mProfiler.Free;
  end;
end;

procedure TCheckProfileTests.JsonAndMarkdownContainTables;
var
  mProfiler: TCheckProfiler;
  mProfile: TCheckRunProfile;
  mJson: TJSONObject;
  mUnits, mRules: TJSONArray;
  mMarkdown: string;
begin
  mProfiler := TCheckProfiler.Create;
  try
    mProfiler.BeginRun(EncodeDate(2026, 10, 29) + EncodeTime(12, 0, 0, 0));
    mProfiler.AddUnit('C:\P\Haupt.pas', 25000);
    mProfiler.AddRule('format-args', 1500);
    mProfiler.FinishRun(30);
    mProfile := mProfiler.Snapshot(TCheckRunProfile.cTop);
  finally
    mProfiler.Free;
  end;
  mJson := mProfile.ToJson;
  try
    Assert.AreEqual<Int64>(30, mJson.GetValue<Int64>('durationMs'));
    Assert.AreEqual(1, mJson.GetValue<Integer>('units'));
    mUnits := mJson.GetValue('slowUnits') as TJSONArray;
    mRules := mJson.GetValue('slowRules') as TJSONArray;
    Assert.AreEqual(1, mUnits.Count);
    Assert.AreEqual('Haupt', (mUnits.Items[0] as TJSONObject).GetValue('name').Value);
    Assert.AreEqual('C:\P\Haupt.pas', (mUnits.Items[0] as TJSONObject).GetValue('file').Value);
    Assert.AreEqual('format-args', (mRules.Items[0] as TJSONObject).GetValue('id').Value);
    Assert.AreEqual(1, (mRules.Items[0] as TJSONObject).GetValue<Integer>('calls'));
  finally
    mJson.Free;
  end;
  mMarkdown := mProfile.ToMarkdown;
  Assert.IsTrue(mMarkdown.Contains('Letzter Prüflauf: 1 Units in 30 ms'), mMarkdown);
  Assert.IsTrue(mMarkdown.Contains('| Haupt | 25.0 |'), mMarkdown);
  Assert.IsTrue(mMarkdown.Contains('| format-args | 1.5 | 1 |'), mMarkdown);
end;

procedure TCheckProfileTests.MarkdownEmptyBeforeFirstRun;
begin
  Assert.AreEqual('', Default(TCheckRunProfile).ToMarkdown);
end;

procedure TCheckProfileTests.TimingsReportAsMarkdownAndJson;
var
  mTimings: TCheckTimings;
  mProfiler: TCheckProfiler;
  mJson: TJSONObject;
  mMarkdown: string;
begin
  mTimings := Default(TCheckTimings);
  mTimings.IndexMs := 1200;
  mTimings.IndexUnits := 340;
  mTimings.ProjectBytes := 2 * 1024 * 1024;
  mTimings.TotalBytes := 64 * 1024 * 1024;
  mProfiler := TCheckProfiler.Create;
  try
    mProfiler.BeginRun(Now);
    mProfiler.AddUnit('C:\P\A.pas', 1000);
    mProfiler.FinishRun(3);
    mTimings.Profile := mProfiler.Snapshot(TCheckRunProfile.cTop);
  finally
    mProfiler.Free;
  end;
  mMarkdown := mTimings.ToMarkdown;
  Assert.IsTrue(mMarkdown.Contains('Symbolindex: 340 Units in 1200 ms'), mMarkdown);
  Assert.IsTrue(mMarkdown.Contains('| Symbole | 2.0 |'), mMarkdown);
  Assert.IsTrue(mMarkdown.Contains('| Gesamt (Heap) | 64.0 |'), mMarkdown);
  Assert.IsTrue(mMarkdown.Contains('Langsamste Units'), mMarkdown);
  mJson := mTimings.ToJson;
  try
    Assert.AreEqual<Int64>(1200, (mJson.GetValue('index') as TJSONObject).GetValue<Int64>('ms'));
    Assert.AreEqual<Int64>(2 * 1024 * 1024, (mJson.GetValue('memory') as TJSONObject).GetValue<Int64>('symbols'));
    Assert.IsTrue(mJson.GetValue('checkRun') is TJSONObject);
  finally
    mJson.Free;
  end;
  Assert.IsTrue(TCheckTimings.IsJsonFile('profil.JSON'));
  Assert.IsFalse(TCheckTimings.IsJsonFile('profil.md'));
  Assert.IsFalse(TCheckTimings.IsJsonFile(''));
  mTimings.IndexMs := -1;
  Assert.IsTrue(mTimings.ToMarkdown.Contains('keiner (--no-index)'));
end;

procedure TCheckProfileTests.TicksConvertWithoutOverflow;
begin
  Assert.AreEqual<Int64>(1500, TCheckProfiler.TicksToMicroseconds(15000, 10000000));
  // Zehn Tage in Ticks zu 100 ns: Ticks * 1000000 liefe über.
  Assert.AreEqual<Int64>(Int64(10) * 86400 * 1000000,
    TCheckProfiler.TicksToMicroseconds(Int64(10) * 86400 * 10000000, 10000000));
  Assert.AreEqual<Int64>(0, TCheckProfiler.TicksToMicroseconds(5, 0));
end;

initialization
  TDUnitX.RegisterTestFixture(TCheckProfileTests);

end.
