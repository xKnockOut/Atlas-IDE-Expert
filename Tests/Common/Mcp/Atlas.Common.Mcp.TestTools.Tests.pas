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
  RechnerTests: array[0..21] of string = (
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
  Index: Integer;
begin
  SetLength(Result, Length(RechnerTests));
  for Index := 0 to High(RechnerTests) do
    Result[Index] := RechnerTests[Index];
end;

function Reader: TMcpReadLines;
begin
  Result :=
    function(const AFileName: string; out ALines: TArray<string>): Boolean
    begin
      Result := AFileName.EndsWith('Rechner.Tests.pas');
      if Result then
        ALines := Lines
      else
        ALines := nil;
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
  Platform, Reason: string;
begin
  Assert.IsTrue(TMcpTestTools.ChoosePlatform('', '', ['Win64'], Platform, Reason));
  Assert.AreEqual('Win64', Platform, 'nur Win64 aktiviert: Win64, nicht Win32');
  Assert.IsTrue(TMcpTestTools.ChoosePlatform('', 'Win32', ['Win64'], Platform, Reason));
  Assert.AreEqual('Win64', Platform, 'Vorgabe der Datei nicht aktiviert');
  Assert.IsTrue(TMcpTestTools.ChoosePlatform('', 'Win64', ['Win32', 'Win64'], Platform, Reason));
  Assert.AreEqual('Win64', Platform, 'Vorgabe der Datei');
  Assert.IsTrue(TMcpTestTools.ChoosePlatform('', '', nil, Platform, Reason));
  Assert.AreEqual('Win32', Platform, 'alte Datei ohne Angaben');
end;

procedure TMcpTestToolsTests.RequestedPlatformMustBeEnabled;
var
  Platform, Reason: string;
begin
  Assert.IsFalse(TMcpTestTools.ChoosePlatform('Win32', 'Win64', ['Win64'], Platform, Reason));
  Assert.Contains(Reason, 'Win32');
  Assert.Contains(Reason, 'Win64');
  Assert.IsTrue(TMcpTestTools.ChoosePlatform('win64', '', ['Win64'], Platform, Reason));
  Assert.AreEqual('win64', Platform);
end;

procedure TMcpTestToolsTests.PicksSingleTestProject;
var
  Project, Reason: string;
  IsTest: TFunc<string, Boolean>;
begin
  IsTest :=
    function(AFileName: string): Boolean
    begin
      Result := AFileName.Contains('Tests');
    end;
  Assert.IsTrue(TMcpTestTools.PickProject(['C:\P\App.dproj', 'C:\P\App.Tests.dproj'], '', IsTest, Project,
    Reason));
  Assert.AreEqual('C:\P\App.Tests.dproj', Project);
  Assert.IsFalse(TMcpTestTools.PickProject(['C:\P\A.Tests.dproj', 'C:\P\B.Tests.dproj'], '', IsTest, Project,
    Reason));
  Assert.Contains(Reason, 'A.Tests.dproj');
  Assert.IsFalse(TMcpTestTools.PickProject(['C:\P\App.dproj'], '', IsTest, Project, Reason));
  Assert.Contains(Reason, 'DUnitX');
  Assert.IsTrue(TMcpTestTools.PickProject(['C:\P\App.dproj', 'C:\P\B.Tests.dproj'], 'app', IsTest, Project,
    Reason));
  Assert.AreEqual('C:\P\App.dproj', Project, 'genanntes Projekt ohne Endung');
  Assert.IsFalse(TMcpTestTools.PickProject(['C:\P\App.dproj'], 'Fehlt', IsTest, Project, Reason));
  Assert.Contains(Reason, 'Fehlt');
end;

procedure TMcpTestToolsTests.ExecutableFromExeOutput;
var
  Info: TProjectInfo;
begin
  Info := Default(TProjectInfo);
  Info.FileName := 'C:\Projekt\Rechner.Tests.dproj';
  Info.MainSource := 'C:\Projekt\Rechner.Tests.dpr';
  Info.Properties := [TPair<string, string>.Create('DCC_ExeOutput', '.\Win32\Debug'),
    TPair<string, string>.Create('DCC_ExeOutput', '.\Win64\Debug')];
  Assert.AreEqual('.\Win64\Debug', TMcpTestTools.PropertyOf(Info, 'dcc_exeoutput'), 'letzte Zuweisung');
  Assert.AreEqual('C:\Projekt\Win64\Debug\Rechner.Tests.exe', TMcpTestTools.ExecutableOf(Info));
  Info.Properties := nil;
  Assert.AreEqual('C:\Projekt\Rechner.Tests.exe', TMcpTestTools.ExecutableOf(Info), 'ohne Ausgabeordner');
end;

procedure TMcpTestToolsTests.TestsFromListOrText;
var
  Arguments: TJSONObject;
  List: TJSONArray;
  Tests: TArray<string>;
begin
  Arguments := TJSONObject.Create;
  try
    Assert.AreEqual(0, Length(TMcpTestTools.TestsOf(Arguments)), 'ohne Angabe alle');
    List := TJSONArray.Create;
    List.Add('U.TA.M');
    List.Add(' ');
    List.Add('U.TB');
    Arguments.AddPair('tests', List);
    Tests := TMcpTestTools.TestsOf(Arguments);
    Assert.AreEqual(2, Length(Tests));
    Assert.AreEqual('U.TB', Tests[1]);
  finally
    Arguments.Free;
  end;
  Arguments := TJSONObject.Create;
  try
    Arguments.AddPair('tests', 'U.TA.M, U.TB');
    Tests := TMcpTestTools.TestsOf(Arguments);
    Assert.AreEqual(2, Length(Tests));
    Assert.AreEqual('U.TA.M', Tests[0]);
    Assert.AreEqual('U.TB', Tests[1]);
  finally
    Arguments.Free;
  end;
  Assert.AreEqual(0, Length(TMcpTestTools.TestsOf(nil)));
end;

procedure TMcpTestToolsTests.LocatesMethodBody;
var
  Units: TArray<TProjectUnit>;
  FileName: string;
  Line: Integer;
  Missing: TTestCaseResult;
begin
  SetLength(Units, 1);
  Units[0].Name := 'Rechner.Tests';
  Units[0].FileName := 'C:\Projekt\Quellen\Rechner.Tests.pas';
  Assert.IsTrue(TMcpTestTools.Locate(FailedCase, Units, 'C:\Projekt', Reader, FileName, Line));
  Assert.AreEqual('C:\Projekt\Quellen\Rechner.Tests.pas', FileName);
  Assert.AreEqual(18, Line, 'Methodenkopf im implementation-Teil, 1-basiert');
  Assert.IsTrue(TMcpTestTools.Locate(FailedCase, nil, 'C:\Projekt', Reader, FileName, Line),
    'ohne Unit-Liste im Projektordner');
  Assert.AreEqual('C:\Projekt\Rechner.Tests.pas', FileName);
  Missing := FailedCase;
  Missing.UnitName := 'Andere.Tests';
  Assert.IsFalse(TMcpTestTools.Locate(Missing, nil, 'C:\Projekt', Reader, FileName, Line));
  Assert.AreEqual('', FileName);
end;

procedure TMcpTestToolsTests.ReportsFailuresWithFileAndLine;
var
  Run: TTestRunResult;
  Passed: TTestCaseResult;
  Json: TJSONObject;
  Failure: TJSONObject;
begin
  Run := Default(TTestRunResult);
  Run.Valid := True;
  Run.DurationMs := 1250;
  Passed := Default(TTestCaseResult);
  Passed.FullName := 'Rechner.Tests.TRechnerTests.Addiert';
  Passed.Outcome := TTestOutcome.Passed;
  Run.Cases := [Passed, FailedCase];
  Json := TJSONObject.ParseJSONValue(TMcpTestTools.Report(Target, ['Rechner.Tests.TRechnerTests'], Run, 1, nil, nil,
    Reader)) as TJSONObject;
  try
    Assert.AreEqual('failed', Json.GetValue('result').Value);
    Assert.AreEqual('Win64', Json.GetValue('platform').Value);
    Assert.AreEqual('2', Json.GetValue('total').Value);
    Assert.AreEqual('1', Json.GetValue('passed').Value);
    Assert.AreEqual('1250', Json.GetValue('durationMs').Value);
    Failure := TJSONArray(Json.GetValue('failures')).Items[0] as TJSONObject;
    Assert.AreEqual('Rechner.Tests.TRechnerTests.Summe.Gross', Failure.GetValue('test').Value);
    Assert.AreEqual('30', Failure.GetValue('expected').Value);
    Assert.AreEqual('31', Failure.GetValue('actual').Value);
    Assert.AreEqual('C:\Projekt\Rechner.Tests.pas', Failure.GetValue('file').Value);
    Assert.AreEqual('18', Failure.GetValue('line').Value);
  finally
    Json.Free;
  end;
  Run.Cases := [Passed];
  Json := TJSONObject.ParseJSONValue(TMcpTestTools.Report(Target, nil, Run, 0, nil, nil, Reader)) as TJSONObject;
  try
    Assert.AreEqual('passed', Json.GetValue('result').Value);
    Assert.IsNull(Json.GetValue('tests'), 'ohne Filter kein Feld tests');
  finally
    Json.Free;
  end;
end;

procedure TMcpTestToolsTests.ReportsMissingXmlReport;
var
  Run: TTestRunResult;
  Json: TJSONObject;
begin
  Run := TTestResults.Parse('');
  Json := TJSONObject.ParseJSONValue(TMcpTestTools.Report(Target, nil, Run, 3, ['Zugriffsverletzung'], nil, Reader))
    as TJSONObject;
  try
    Assert.AreEqual('noReport', Json.GetValue('result').Value);
    Assert.AreEqual('3', Json.GetValue('exitCode').Value);
    Assert.Contains(Json.GetValue('reason').Value, 'XML');
    Assert.AreEqual('Zugriffsverletzung', TJSONArray(Json.GetValue('output')).Items[0].Value);
    Assert.IsNull(Json.GetValue('failures'));
  finally
    Json.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TMcpTestToolsTests);

end.
