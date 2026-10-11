unit Atlas.Common.Mcp.Paths.Tests;

// Tests für die Pfadregeln der MCP-Werkzeuge (#99).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMcpPathGuardTests = class
  public
    [Test]
    procedure RelativeAndAbsoluteInsideRoot;
    [Test]
    procedure RejectsOutsideAndDotDot;
    [Test]
    procedure AllowsLibraryPaths;
    [Test]
    procedure UsesCanonicalizer;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Mcp.Server,
  Atlas.Common.Mcp.Paths;

procedure TMcpPathGuardTests.RelativeAndAbsoluteInsideRoot;
var
  Guard: TMcpPathGuard;
begin
  Guard := TMcpPathGuard.Create('C:\Projekte\App\');
  try
    Assert.AreEqual('C:\Projekte\App\Source\Main.pas', Guard.Resolve('Source\Main.pas'));
    Assert.AreEqual('C:\Projekte\App\Main.pas', Guard.Resolve('c:/Projekte/App/Main.pas').Replace('c:', 'C:'));
    Assert.AreEqual('C:\Projekte\App\Main.pas', Guard.Resolve('Source\..\Main.pas'));
  finally
    Guard.Free;
  end;
end;

procedure TMcpPathGuardTests.RejectsOutsideAndDotDot;
var
  Guard: TMcpPathGuard;
begin
  Guard := TMcpPathGuard.Create('C:\Projekte\App');
  try
    Assert.WillRaise(procedure begin Guard.Resolve('C:\Windows\win.ini'); end, EMcpToolError);
    Assert.WillRaise(procedure begin Guard.Resolve('..\Anderes\Geheim.pas'); end, EMcpToolError);
    // Gleicher Anfang, anderer Ordner.
    Assert.WillRaise(procedure begin Guard.Resolve('C:\Projekte\AppAlt\Main.pas'); end, EMcpToolError);
    Assert.WillRaise(procedure begin Guard.Resolve(''); end, EMcpToolError);
  finally
    Guard.Free;
  end;
end;

procedure TMcpPathGuardTests.AllowsLibraryPaths;
var
  Guard: TMcpPathGuard;
begin
  Guard := TMcpPathGuard.Create('C:\Projekte\App',
    function: TArray<string>
    begin
      Result := ['C:\Lib\Komponenten\', ''];
    end);
  try
    Assert.AreEqual('C:\Lib\Komponenten\Grid.pas', Guard.Resolve('C:\Lib\Komponenten\Grid.pas'));
    Assert.WillRaise(procedure begin Guard.Resolve('C:\Lib\Anderes.pas'); end, EMcpToolError);
  finally
    Guard.Free;
  end;
end;

procedure TMcpPathGuardTests.UsesCanonicalizer;
var
  Guard: TMcpPathGuard;
begin
  // Eine Junction C:\Projekte\App\Link zeigt nach C:\Fremd: nach dem Auflösen draußen.
  Guard := TMcpPathGuard.Create('C:\Projekte\App', nil,
    function(APath: string): string
    begin
      Result := APath.Replace('C:\Projekte\App\Link', 'C:\Fremd');
    end);
  try
    Assert.WillRaise(procedure begin Guard.Resolve('Link\Secret.pas'); end, EMcpToolError);
    Assert.AreEqual('C:\Projekte\App\Main.pas', Guard.Resolve('Main.pas'));
  finally
    Guard.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TMcpPathGuardTests);

end.