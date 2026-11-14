unit Shell.Mcp.ServerSetup.Tests;

// Einrichtung des MCP-Servers: abgeschaltete Werkzeuge aus mcp.disabledTools und abgeschalteten Funktionen (#227).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMcpServerSetupTests = class
  public
    [Test]
    procedure DefaultsDisableNoTool;
    [Test]
    procedure DisabledFeaturesDisableTheirTools;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Shell.Mcp.ServerSetup;

{ TMcpServerSetupTests }

procedure TMcpServerSetupTests.DefaultsDisableNoTool;
begin
  Assert.AreEqual(0, Integer(Length(DisabledTools(TServerSettings.Default))));
end;

procedure TMcpServerSetupTests.DisabledFeaturesDisableTheirTools;
var
  mSettings: TServerSettings;
begin
  mSettings := TServerSettings.Default;
  mSettings.McpDisabledTools := TArray<string>.Create('format_code');
  mSettings.ArchitectureEnabled := False;
  mSettings.HotspotsEnabled := False;
  mSettings.Navigation.SymbolPath := False;
  mSettings.Tests.Affected := False;
  mSettings.QueryEnabled := False;
  Assert.AreEqual('format_code,get_architecture,get_hotspots,find_path,get_affected_tests,query_code',
    string.Join(',', DisabledTools(mSettings)));
end;

end.
