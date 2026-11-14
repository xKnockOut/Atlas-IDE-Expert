unit Atlas.Common.Mcp.TestTools.Tests;

// Tests des MCP-Werkzeugs run_tests ohne Prozess (#69): Wahl der Plattform
// (Projekt nur für Win64 läuft als Win64), des Testprojekts und der Test-EXE,
// Filter "tests", Fundstelle eines fehlgeschlagenen Tests und Bericht.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMcpTestToolsTests = class
  public
    [Test]
    procedure PlatformFromProjectNotWin32;
    [Test]
    procedure RequestedPlatformMustBeEnabled;
    [Test]
    procedure PicksSingleTestProject;
    [Test]
    procedure ExecutableFromExeOutput;
    [Test]
    procedure TestsFromListOrText;
    [Test]
    procedure LocatesMethodBody;
    [Test]
    procedure ReportsFailuresWithFileAndLine;
    [Test]
    procedure ReportsMissingXmlReport;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.JSON,
  Atlas.Common.Projects.Contract,
  Atlas.Common.Mcp.TestTools,
  Atlas.Text.TestResults;

const
  cRechnerTests: array[0..21] of string = (
    'unit Rechner.Tests;',
    'interface',
    'uses DUnitX.TestFramework;',
    'type',
    '  [TestFixture]',
    '  TRechnerTests = class',
    '  public',
    '    [Test]',
    '    procedure Addiert;',
    '    [TestCase(''Gross'', ''10,20,30'')]',
    '    procedure Summe(A, B, C: Integer);',
    '  end;',
    'implementation',
    'procedure TRechnerTests.Addiert;',
    'begin',
    'end;',
    '',
    'procedure TRechnerTests.Summe(A, B, C: Integer);',
    'begin',
    '  Assert.AreEqual(C, A + B);',
    'end;',
    'end.');

function Lines: TArray<string>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(cRechnerTests));
  for mIndex := 0 to High(cRechnerTests) do
  begin
    Result[mIndex] := cRechnerTests[mIndex];
  end;
end;

function Reader: TMcpReadLines;
begin
  Result :=
    function(const AFileName: string; out ALines: TArray<string>): Boolean
    begin
      Result := AFileName.EndsWith('Rechner.Tests.pas');
      if Result then
      begin
        ALines := Lines;
      end
      else
      begin
        ALines := nil;
      end;
    end;
end;

function FailedCase: TTestCaseResult;
begin
  Result := Default(TTestCaseResult);
  Result.FullName := 'Rechner.Tests.TRechnerTests.Summe.Gross';
  Result.UnitName := 'Rechner.Tests';
  Result.Fixture := 'TRechnerTests';
  Result.Method := 'Summe';
  Result.CaseName := 'Gross';
  Result.Outcome := TTestOutcome.Failed;
  Result.Message := 'Expected 30 but got 31';
  Result.Expected := '30';
  Result.Actual := '31';
  Result.HasValues := True;
end;

function Target: TMcpTestTarget;
begin
  Result := Default(TMcpTestTarget);
  Result.Project := 'C:\Projekt\Rechner.Tests.dproj';
  Result.Configuration := 'Debug';
  Result.Platform := 'Win64';
  Result.Executable := 'C:\Projekt\Win64\Debug\Rechner.Tests.exe';
end;

{ TMcpTestToolsTests }

procedure TMcpTestToolsTests.PlatformFromProjectNotWin32;
var
  mPlatform, mReason: string;
begin
  Assert.IsTrue(TMcpTestTools.ChoosePlatform('', '', ['Win64'], mPlatform, mReason));
  Assert.AreEqual('Win64', mPlatform, 'nur Win64 aktiviert: Win64, nicht Win32');
  Assert.IsTrue(TMcpTestTools.ChoosePlatform('', 'Win32', ['Win64'], mPlatform, mReason));
  Assert.AreEqual('Win64', mPlatform, 'Vorgabe der Datei nicht aktiviert');
  Assert.IsTrue(TMcpTestTools.ChoosePlatform('', 'Win64', ['Win32', 'Win64'], mPlatform, mReason));
  Assert.AreEqual('Win64', mPlatform, 'Vorgabe der Datei');
  Assert.IsTrue(TMcpTestTools.ChoosePlatform('', '', nil, mPlatform, mReason));
  Assert.AreEqual('Win32', mPlatform, 'alte Datei ohne Angaben');
end;

procedure TMcpTestToolsTests.RequestedPlatformMustBeEnabled;
var
  mPlatform, mReason: string;
begin
  Assert.IsFalse(TMcpTestTools.ChoosePlatform('Win32', 'Win64', ['Win64'], mPlatform, mReason));
  Assert.Contains(mReason, 'Win32');
  Assert.Contains(mReason, 'Win64');
  Assert.IsTrue(TMcpTestTools.ChoosePlatform('win64', '', ['Win64'], mPlatform, mReason));
  Assert.AreEqual('win64', mPlatform);
end;

procedure TMcpTestToolsTests.PicksSingleTestProject;
var
  mProject, mReason: string;
  mIsTest: TFunc<string, Boolean>;
begin
  mIsTest :=
    function(AFileName: string): Boolean
    begin
      Result := AFileName.Contains('Tests');
    end;
  Assert.IsTrue(TMcpTestTools.PickProject(['C:\P\App.dproj', 'C:\P\App.Tests.dproj'], '', mIsTest, mProject,
    mReason));
  Assert.AreEqual('C:\P\App.Tests.dproj', mProject);
  Assert.IsFalse(TMcpTestTools.PickProject(['C:\P\A.Tests.dproj', 'C:\P\B.Tests.dproj'], '', mIsTest, mProject,
    mReason));
  Assert.Contains(mReason, 'A.Tests.dproj');
  Assert.IsFalse(TMcpTestTools.PickProject(['C:\P\App.dproj'], '', mIsTest, mProject, mReason));
  Assert.Contains(mReason, 'DUnitX');
  Assert.IsTrue(TMcpTestTools.PickProject(['C:\P\App.dproj', 'C:\P\B.Tests.dproj'], 'app', mIsTest, mProject,
    mReason));
  Assert.AreEqual('C:\P\App.dproj', mProject, 'genanntes Projekt ohne Endung');
  Assert.IsFalse(TMcpTestTools.PickProject(['C:\P\App.dproj'], 'Fehlt', mIsTest, mProject, mReason));
  Assert.Contains(mReason, 'Fehlt');
end;

procedure TMcpTestToolsTests.ExecutableFromExeOutput;
var
  mInfo: TProjectInfo;
begin
  mInfo := Default(TProjectInfo);
  mInfo.FileName := 'C:\Projekt\Rechner.Tests.dproj';
  mInfo.MainSource := 'C:\Projekt\Rechner.Tests.dpr';
  mInfo.Properties := [TPair<string, string>.Create('DCC_ExeOutput', '.\Win32\Debug'),
    TPair<string, string>.Create('DCC_ExeOutput', '.\Win64\Debug')];
  Assert.AreEqual('.\Win64\Debug', TMcpTestTools.PropertyOf(mInfo, 'dcc_exeoutput'), 'letzte Zuweisung');
  Assert.AreEqual('C:\Projekt\Win64\Debug\Rechner.Tests.exe', TMcpTestTools.ExecutableOf(mInfo));
  mInfo.Properties := nil;
  Assert.AreEqual('C:\Projekt\Rechner.Tests.exe', TMcpTestTools.ExecutableOf(mInfo), 'ohne Ausgabeordner');
end;

procedure TMcpTestToolsTests.TestsFromListOrText;
var
  mArguments: TJSONObject;
  mList: TJSONArray;
  mTests: TArray<string>;
begin
  mArguments := TJSONObject.Create;
  try
    Assert.AreEqual(0, Integer(Length(TMcpTestTools.TestsOf(mArguments))), 'ohne Angabe alle');
    mList := TJSONArray.Create;
    mList.Add('U.TA.M');
    mList.Add(' ');
    mList.Add('U.TB');
    mArguments.AddPair('tests', mList);
    mTests := TMcpTestTools.TestsOf(mArguments);
    Assert.AreEqual(2, Integer(Length(mTests)));
    Assert.AreEqual('U.TB', mTests[1]);
  finally
    mArguments.Free;
  end;
  mArguments := TJSONObject.Create;
  try
    mArguments.AddPair('tests', 'U.TA.M, U.TB');
    mTests := TMcpTestTools.TestsOf(mArguments);
    Assert.AreEqual(2, Integer(Length(mTests)));
    Assert.AreEqual('U.TA.M', mTests[0]);
    Assert.AreEqual('U.TB', mTests[1]);
  finally
    mArguments.Free;
  end;
  Assert.AreEqual(0, Integer(Length(TMcpTestTools.TestsOf(nil))));
end;

procedure TMcpTestToolsTests.LocatesMethodBody;
var
  mUnits: TArray<TProjectUnit>;
  mFileName: string;
  mLine: Integer;
  mMissing: TTestCaseResult;
begin
  SetLength(mUnits, 1);
  mUnits[0].Name := 'Rechner.Tests';
  mUnits[0].FileName := 'C:\Projekt\Quellen\Rechner.Tests.pas';
  Assert.IsTrue(TMcpTestTools.Locate(FailedCase, mUnits, 'C:\Projekt', Reader(), mFileName, mLine));
  Assert.AreEqual('C:\Projekt\Quellen\Rechner.Tests.pas', mFileName);
  Assert.AreEqual(18, mLine, 'Methodenkopf im implementation-Teil, 1-basiert');
  Assert.IsTrue(TMcpTestTools.Locate(FailedCase, nil, 'C:\Projekt', Reader(), mFileName, mLine),
    'ohne Unit-Liste im Projektordner');
  Assert.AreEqual('C:\Projekt\Rechner.Tests.pas', mFileName);
  mMissing := FailedCase;
  mMissing.UnitName := 'Andere.Tests';
  Assert.IsFalse(TMcpTestTools.Locate(mMissing, nil, 'C:\Projekt', Reader(), mFileName, mLine));
  Assert.AreEqual('', mFileName);
end;

procedure TMcpTestToolsTests.ReportsFailuresWithFileAndLine;
var
  mRun: TTestRunResult;
  mPassed: TTestCaseResult;
  mJson: TJSONObject;
  mFailure: TJSONObject;
begin
  mRun := Default(TTestRunResult);
  mRun.Valid := True;
  mRun.DurationMs := 1250;
  mPassed := Default(TTestCaseResult);
  mPassed.FullName := 'Rechner.Tests.TRechnerTests.Addiert';
  mPassed.Outcome := TTestOutcome.Passed;
  mRun.Cases := [mPassed, FailedCase];
  mJson := TJSONObject.ParseJSONValue(TMcpTestTools.Report(Target, ['Rechner.Tests.TRechnerTests'], mRun,
    TMcpTestProcess.Make(1, nil), nil, Reader())) as TJSONObject;
  try
    Assert.AreEqual('failed', mJson.GetValue('result').Value);
    Assert.AreEqual('Win64', mJson.GetValue('platform').Value);
    Assert.AreEqual('2', mJson.GetValue('total').Value);
    Assert.AreEqual('1', mJson.GetValue('passed').Value);
    Assert.AreEqual('1250', mJson.GetValue('durationMs').Value);
    mFailure := TJSONArray(mJson.GetValue('failures')).Items[0] as TJSONObject;
    Assert.AreEqual('Rechner.Tests.TRechnerTests.Summe.Gross', mFailure.GetValue('test').Value);
    Assert.AreEqual('30', mFailure.GetValue('expected').Value);
    Assert.AreEqual('31', mFailure.GetValue('actual').Value);
    Assert.AreEqual('C:\Projekt\Rechner.Tests.pas', mFailure.GetValue('file').Value);
    Assert.AreEqual('18', mFailure.GetValue('line').Value);
  finally
    mJson.Free;
  end;
  mRun.Cases := [mPassed];
  mJson := TJSONObject.ParseJSONValue(TMcpTestTools.Report(Target, nil, mRun, TMcpTestProcess.Make(0, nil), nil,
    Reader())) as TJSONObject;
  try
    Assert.AreEqual('passed', mJson.GetValue('result').Value);
    Assert.IsNull(mJson.GetValue('tests'), 'ohne Filter kein Feld tests');
  finally
    mJson.Free;
  end;
end;

procedure TMcpTestToolsTests.ReportsMissingXmlReport;
var
  mRun: TTestRunResult;
  mJson: TJSONObject;
begin
  mRun := TTestResults.Parse('');
  mJson := TJSONObject.ParseJSONValue(TMcpTestTools.Report(Target, nil, mRun,
    TMcpTestProcess.Make(3, TArray<string>.Create('Zugriffsverletzung')), nil, Reader()))
    as TJSONObject;
  try
    Assert.AreEqual('noReport', mJson.GetValue('result').Value);
    Assert.AreEqual('3', mJson.GetValue('exitCode').Value);
    Assert.Contains(mJson.GetValue('reason').Value, 'XML');
    Assert.AreEqual('Zugriffsverletzung', TJSONArray(mJson.GetValue('output')).Items[0].Value);
    Assert.IsNull(mJson.GetValue('failures'));
  finally
    mJson.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TMcpTestToolsTests);

end.
