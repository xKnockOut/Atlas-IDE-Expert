unit Atlas.Common.Mcp.StatusTools.Tests;

// Tests für get_server_status (#1356): Status des Servers der IDE aus der
// Statusdatei, sonst der des MCP-Prozesses, als Markdown oder JSON.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMcpStatusToolsTests = class
  private
    FRoot: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ShowsIdeServerStatus;
    [Test]
    procedure ShowsIdeServerStatusAsJson;
    [Test]
    procedure FallsBackToOwnStatus;
    [Test]
    procedure AppendsSessionStatistics;
    [Test]
    procedure AddsStatisticsToJson;
    [Test]
    procedure StatisticsResourceSaysWhenOff;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.JSON,
  Atlas.Common.Lsp.Status,
  Atlas.Common.Lsp.StatusFile,
  Atlas.Common.Mcp.Statistics,
  Atlas.Common.Mcp.StatusTools;

const
  cNow: TDateTime = 46324.5;

function Own: TServerStatus;
begin
  Result := Default(TServerStatus);
  Result.Units := 7;
  Result.ProcessId := 77;
  Result.Version := '1.2.0';
  Result.State := TServerStatus.cStateReady;
end;

{ TMcpStatusToolsTests }

procedure TMcpStatusToolsTests.Setup;
var
  mStatus: TServerStatus;
  mJson: TJSONObject;
begin
  FRoot := TPath.Combine(TPath.GetTempPath, 'Atlas-StatusTools-' + IntToStr(Random(MaxInt)));
  mStatus := Default(TServerStatus);
  mStatus.Units := 1234;
  mStatus.ProcessId := 4711;
  mStatus.Version := '1.2.0';
  mStatus.State := TServerStatus.cStateChecking;
  mJson := mStatus.ToJson;
  try
    TServerStatusFile.Write(FRoot, 4711, [TPath.Combine(FRoot, 'App')], mJson, cNow);
  finally
    mJson.Free;
  end;
end;

procedure TMcpStatusToolsTests.TearDown;
begin
  if TDirectory.Exists(FRoot) then
  begin
    TDirectory.Delete(FRoot, True);
  end;
  FRoot := '';
end;

procedure TMcpStatusToolsTests.ShowsIdeServerStatus;
var
  mText: string;
begin
  mText := TMcpStatusTools.ServerStatus(FRoot, TPath.Combine(FRoot, 'App'), False, cNow, Own, nil);
  Assert.IsTrue(mText.StartsWith('Quelle: Atlas-Server der IDE (Prozess 4711'), mText);
  Assert.IsTrue(mText.Contains('1234 Units'), mText);
  Assert.IsTrue(mText.Contains('prüft'), mText);
end;

procedure TMcpStatusToolsTests.ShowsIdeServerStatusAsJson;
var
  mValue: TJSONValue;
begin
  mValue := TJSONObject.ParseJSONValue(TMcpStatusTools.ServerStatus(FRoot, TPath.Combine(FRoot, 'App'), True, cNow,
    Own, nil));
  try
    Assert.IsTrue(mValue is TJSONObject);
    Assert.AreEqual(1234, TJSONObject(mValue).GetValue<Integer>('units'));
    Assert.IsTrue(TJSONObject(mValue).GetValue('source').Value.Contains('4711'));
    Assert.IsNull(TJSONObject(mValue).GetValue('markdown'), 'ohne Markdown im JSON');
  finally
    mValue.Free;
  end;
end;

procedure TMcpStatusToolsTests.FallsBackToOwnStatus;
var
  mText: string;
begin
  mText := TMcpStatusTools.ServerStatus(FRoot, TPath.Combine(FRoot, 'Anderes'), False, cNow, Own, nil);
  Assert.IsTrue(mText.StartsWith('Quelle: dieser MCP-Prozess'), mText);
  Assert.IsTrue(mText.Contains('7 Units'), mText);
end;

function CalledStatistics: TMcpStatistics;
var
  mCall: TMcpCall;
begin
  Result := TMcpStatistics.Create('C:\App', cNow);
  Result.SetClient('Assistent A');
  mCall := Default(TMcpCall);
  mCall.Name := 'find_symbol';
  mCall.ElapsedMs := 40;
  mCall.Bytes := 2048;
  Result.Add(mCall, cNow);
end;

procedure TMcpStatusToolsTests.AppendsSessionStatistics;
var
  mStatistics: TMcpStatistics;
  mText: string;
begin
  mStatistics := CalledStatistics;
  try
    mText := TMcpStatusTools.ServerStatus(FRoot, TPath.Combine(FRoot, 'App'), False, cNow, Own, mStatistics);
  finally
    mStatistics.Free;
  end;
  Assert.IsTrue(mText.StartsWith('Quelle: Atlas-Server der IDE'), mText);
  Assert.IsTrue(mText.Contains('Assistent A'), mText);
  Assert.IsTrue(mText.Contains('| find_symbol | 1 | 0 | 40 ms | 40 ms | 2,0 KB | 2,0 KB |'), mText);
end;

procedure TMcpStatusToolsTests.AddsStatisticsToJson;
var
  mStatistics: TMcpStatistics;
  mValue: TJSONValue;
begin
  mStatistics := CalledStatistics;
  try
    mValue := TJSONObject.ParseJSONValue(TMcpStatusTools.ServerStatus(FRoot, TPath.Combine(FRoot, 'App'), True,
      cNow, Own, mStatistics));
  finally
    mStatistics.Free;
  end;
  try
    Assert.IsTrue(mValue is TJSONObject);
    Assert.AreEqual('Assistent A', TJSONObject(mValue).GetValue<string>('mcp.client'));
    Assert.AreEqual(1234, TJSONObject(mValue).GetValue<Integer>('units'), 'Status bleibt');
  finally
    mValue.Free;
  end;
end;

procedure TMcpStatusToolsTests.StatisticsResourceSaysWhenOff;
begin
  Assert.IsTrue(TMcpStatusTools.StatisticsText(nil, TPath.Combine(FRoot, 'mcp-stats.jsonl'), cNow).Contains(
    'mcp.statistics'));
end;

initialization
  TDUnitX.RegisterTestFixture(TMcpStatusToolsTests);

end.
