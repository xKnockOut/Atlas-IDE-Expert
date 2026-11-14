unit Atlas.Common.Rules.Builtin.Testing.LeakMonitor.Tests;

// Tests der Regel dunitx-leak-monitor (#1774): Testprogramm ohne Leckmonitor mit Korrektur (FastMM4, bei FastMM5
// dessen Monitor), still mit Monitor (auch einem eigenen, den eine Unit des Projekts anmeldet), in Units
// und in Programmen ohne DUnitX; der Monitor Default zählt nicht.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDUnitXLeakMonitorTests = class
  public
    [Test]
    procedure ProgramWithoutMonitor;
    [Test]
    procedure FastMM5GetsItsMonitor;
    [Test]
    procedure DefaultMonitorCountsAsNone;
    [Test]
    procedure SilentWithMonitor;
    [Test]
    procedure SilentWithOwnMonitorInProject;
    [Test]
    procedure SilentOutsideTestPrograms;
    [Test]
    procedure RuleIsRegistered;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Rules.Builtin.Testing.LeakMonitor,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Tests.RuleAssert;

/// <summary>Testprogramm mit AUses als uses-Liste.</summary>
function TestProgram(const AUses: string): string;
begin
  Result := 'program FallTests;'#10'uses'#10 + AUses + ';'#10'begin'#10'  TDUnitX.RunRegisteredTests;'#10'end.';
end;

function Findings(const AText, AFileName: string): TArray<TRuleFinding>;
var
  mRule: IRule;
begin
  mRule := TDUnitXLeakMonitorRule.Create;
  Result := TRuleAssert.Findings(mRule, AText, '', AFileName);
end;

/// <summary>Text nach der Korrektur des einzigen Befunds; '' ohne Befund oder Korrektur.</summary>
function Fixed(const AUses: string): string;
var
  mFound: TArray<TRuleFinding>;
begin
  Result := '';
  mFound := Findings(TestProgram(AUses), 'FallTests.dpr');
  if (Length(mFound) = 1) and (Length(mFound[0].Fixes) > 0) then
  begin
    Result := TChangeSignature.ApplyEdits(TestProgram(AUses), mFound[0].Fixes[0].Edits);
  end;
end;

{ TDUnitXLeakMonitorTests }

procedure TDUnitXLeakMonitorTests.ProgramWithoutMonitor;
var
  mFound: TArray<TRuleFinding>;
  mText: string;
begin
  mFound := Findings(TestProgram('  DUnitX.TestFramework,'#10'  Fall.Tests'), 'FallTests.dpr');
  Assert.AreEqual(1, Integer(Length(mFound)));
  // Gemeldet am Eintrag DUnitX.TestFramework (Zeile 2 ab 0).
  Assert.AreEqual(2, mFound[0].Range.StartPos.Line);
  Assert.IsTrue(ContainsStr(mFound[0].Message, 'DUnitX.MemoryLeakMonitor.FastMM4'), mFound[0].Message);
  mText := Fixed('  DUnitX.TestFramework,'#10'  Fall.Tests');
  Assert.IsTrue(ContainsStr(mText, 'DUnitX.MemoryLeakMonitor.FastMM4'), mText);
  Assert.IsTrue(ContainsStr(mText, 'Fall.Tests'), mText);
  // Nach der Korrektur schweigt die Regel.
  Assert.AreEqual(0, Integer(Length(Findings(mText, 'FallTests.dpr'))));
end;

procedure TDUnitXLeakMonitorTests.FastMM5GetsItsMonitor;
var
  mText: string;
begin
  mText := Fixed('  FastMM5,'#10'  DUnitX.TestFramework');
  Assert.IsTrue(ContainsStr(mText, 'DUnitX.MemoryLeakMonitor.FastMM5'), mText);
  Assert.IsFalse(ContainsStr(mText, 'DUnitX.MemoryLeakMonitor.FastMM4'), mText);
  Assert.AreEqual('DUnitX.MemoryLeakMonitor.FastMM4', TDUnitXLeakMonitorRule.MonitorFor(['FastMM4']));
  Assert.AreEqual('DUnitX.MemoryLeakMonitor.FastMM5', TDUnitXLeakMonitorRule.MonitorFor(['fastmm5']));
end;

procedure TDUnitXLeakMonitorTests.DefaultMonitorCountsAsNone;
begin
  Assert.AreEqual(1, Integer(Length(Findings(TestProgram('  DUnitX.TestFramework,'#10 +
    '  DUnitX.MemoryLeakMonitor.Default'), 'FallTests.dpr'))));
end;

procedure TDUnitXLeakMonitorTests.SilentWithOwnMonitorInProject;
var
  mRule: IRule;
  mIndex: ISymbolIndex;
begin
  // Eigener Monitor (Atlas.Tests.LeakMonitor): eine Unit des Projekts meldet IMemoryLeakMonitor an.
  mRule := TDUnitXLeakMonitorRule.Create;
  mIndex := TSymbolIndex.Create;
  Assert.AreEqual(1, Integer(Length(TRuleAssert.IndexFindings(mRule, TestProgram('  DUnitX.TestFramework'), mIndex, '',
    'FallTests.dpr'))), 'ohne eigenen Monitor');
  mIndex.AddUnit(TIndexExtractor.ExtractText('unit Monitor;'#10'interface'#10'implementation'#10'procedure Anmelden;' +
    #10'begin'#10'  TDUnitXIoC.DefaultContainer.RegisterType<IMemoryLeakMonitor>(Erzeugen);'#10'end;'#10'end.',
    'Monitor.pas', nil, nil, True));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.IndexFindings(mRule, TestProgram('  DUnitX.TestFramework'), mIndex, '',
    'FallTests.dpr'))), 'eigener Monitor im Projekt');
end;

procedure TDUnitXLeakMonitorTests.SilentWithMonitor;
begin
  Assert.AreEqual(0, Integer(Length(Findings(TestProgram('  DUnitX.MemoryLeakMonitor.FastMM4,'#10 +
    '  DUnitX.TestFramework'), 'FallTests.dpr'))));
  Assert.AreEqual(0, Integer(Length(Findings(TestProgram('  FastMM5,'#10'  DUnitX.TestFramework,'#10 +
    '  DUnitX.MemoryLeakMonitor.FastMM5'), 'FallTests.dpr'))));
end;

procedure TDUnitXLeakMonitorTests.SilentOutsideTestPrograms;
begin
  // Programm ohne DUnitX.
  Assert.AreEqual(0, Integer(Length(Findings(TestProgram('  System.SysUtils'), 'Fall.dpr'))));
  // Testunit: Der Monitor gehört ins Programm, nicht in die Unit.
  Assert.AreEqual(0, Integer(Length(Findings('unit Fall.Tests;'#10'interface'#10'uses'#10 +
    '  DUnitX.TestFramework;'#10'implementation'#10'end.', 'Fall.Tests.pas'))));
end;

procedure TDUnitXLeakMonitorTests.RuleIsRegistered;
var
  mRule: IRule;
  mFound: Integer;
begin
  mFound := 0;
  for mRule in BuiltinRules do
  begin
    if mRule.Descriptor.Id = cDUnitXLeakMonitorRuleId then
    begin
      Inc(mFound);
    end;
  end;
  Assert.AreEqual(1, mFound);
end;

end.
