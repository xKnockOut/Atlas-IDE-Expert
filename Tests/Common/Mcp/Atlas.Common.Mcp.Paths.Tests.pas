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
  mGuard: TMcpPathGuard;
begin
  mGuard := TMcpPathGuard.Create('C:\Projekte\App\');
  try
    Assert.AreEqual('C:\Projekte\App\Source\Main.pas', mGuard.Resolve('Source\Main.pas'));
    Assert.AreEqual('C:\Projekte\App\Main.pas', mGuard.Resolve('c:/Projekte/App/Main.pas').Replace('c:', 'C:'));
    Assert.AreEqual('C:\Projekte\App\Main.pas', mGuard.Resolve('Source\..\Main.pas'));
  finally
    mGuard.Free;
  end;
end;

procedure TMcpPathGuardTests.RejectsOutsideAndDotDot;
var
  mGuard: TMcpPathGuard;
begin
  mGuard := TMcpPathGuard.Create('C:\Projekte\App');
  try
    Assert.WillRaise(procedure begin mGuard.Resolve('C:\Windows\win.ini'); end, EMcpToolError);
    Assert.WillRaise(procedure begin mGuard.Resolve('..\Anderes\Geheim.pas'); end, EMcpToolError);
    // Gleicher Anfang, anderer Ordner.
    Assert.WillRaise(procedure begin mGuard.Resolve('C:\Projekte\AppAlt\Main.pas'); end, EMcpToolError);
    Assert.WillRaise(procedure begin mGuard.Resolve(''); end, EMcpToolError);
  finally
    mGuard.Free;
  end;
end;

procedure TMcpPathGuardTests.AllowsLibraryPaths;
var
  mGuard: TMcpPathGuard;
begin
  mGuard := TMcpPathGuard.Create('C:\Projekte\App',
    function: TArray<string>
    begin
      Result := ['C:\Lib\Komponenten\', ''];
    end);
  try
    Assert.AreEqual('C:\Lib\Komponenten\Grid.pas', mGuard.Resolve('C:\Lib\Komponenten\Grid.pas'));
    Assert.WillRaise(procedure begin mGuard.Resolve('C:\Lib\Anderes.pas'); end, EMcpToolError);
  finally
    mGuard.Free;
  end;
end;

procedure TMcpPathGuardTests.UsesCanonicalizer;
var
  mGuard: TMcpPathGuard;
begin
  // Eine Junction C:\Projekte\App\Link zeigt nach C:\Fremd: nach dem Auflösen draußen.
  mGuard := TMcpPathGuard.Create('C:\Projekte\App', nil,
    function(APath: string): string
    begin
      Result := APath.Replace('C:\Projekte\App\Link', 'C:\Fremd');
    end);
  try
    Assert.WillRaise(procedure begin mGuard.Resolve('Link\Secret.pas'); end, EMcpToolError);
    Assert.AreEqual('C:\Projekte\App\Main.pas', mGuard.Resolve('Main.pas'));
  finally
    mGuard.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TMcpPathGuardTests);

end.