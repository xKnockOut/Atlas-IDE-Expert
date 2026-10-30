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
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.JSON,
  Atlas.Common.Lsp.Status,
  Atlas.Common.Lsp.StatusFile,
  Atlas.Common.Mcp.StatusTools;

const
  cNow: TDateTime = 46324.5;

function Own: TServerStatus;
begin
  Result := Default(TServerStatus);
  Result.Units := 7;
  Result.ProcessId := 77;
  Result.Version := '1.2.0';
  Result.State := TServerStatus.StateReady;
end;

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
  mStatus.State := TServerStatus.StateChecking;
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
    TDirectory.Delete(FRoot, True);
  FRoot := '';
end;

procedure TMcpStatusToolsTests.ShowsIdeServerStatus;
var
  mText: string;
begin
  mText := TMcpStatusTools.ServerStatus(FRoot, TPath.Combine(FRoot, 'App'), False, cNow, Own);
  Assert.IsTrue(mText.StartsWith('Quelle: Atlas-Server der IDE (Prozess 4711'), mText);
  Assert.IsTrue(mText.Contains('1234 Units'), mText);
  Assert.IsTrue(mText.Contains('prüft'), mText);
end;

procedure TMcpStatusToolsTests.ShowsIdeServerStatusAsJson;
var
  mValue: TJSONValue;
begin
  mValue := TJSONObject.ParseJSONValue(TMcpStatusTools.ServerStatus(FRoot, TPath.Combine(FRoot, 'App'), True, cNow,
    Own));
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
  mText := TMcpStatusTools.ServerStatus(FRoot, TPath.Combine(FRoot, 'Anderes'), False, cNow, Own);
  Assert.IsTrue(mText.StartsWith('Quelle: dieser MCP-Prozess'), mText);
  Assert.IsTrue(mText.Contains('7 Units'), mText);
end;

initialization
  TDUnitX.RegisterTestFixture(TMcpStatusToolsTests);

end.
