unit Shell.Composition.CompileSetup.Tests;

// Compile-Host der Komposition: ohne Ordner kein Auftrag, PowerShell für cc.ps1 immer benannt.

interface

uses
  DUnitX.TestFramework,
  Shell.Composition.Workspaces,
  Shell.Composition.CompileSetup;

type
  [TestFixture]
  TShellCompileSetupTests = class
  private
    FRegistry: TShellWorkspaceRegistry;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>Ohne Ordner kein Auftrag; der Grund steht in AError.</summary>
    [Test]
    procedure NoFolderNoJob;
    /// <summary>Ohne pwsh und powershell im PATH bleibt ein Programmname, nie leer (#261).</summary>
    [Test]
    procedure PowerShellNamed;
    /// <summary>Der Host entsteht ohne laufenden Compiler und lässt sich freigeben.</summary>
    [Test]
    procedure HostWithoutCompiler;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Logging.Providers.Logger,
  Shell.Compiler,
  Shell.Composition.Compile;

function NoText(const AFileName: string; out AText: string): Boolean;
begin
  AText := '';
  Result := False;
end;

function NoSelection(const AOrigin: string): string;
begin
  Result := '';
end;

function NoActive: string;
begin
  Result := '';
end;

procedure TShellCompileSetupTests.Setup;
var
  mRegistry: TShellWorkspaceRegistryServices;
begin
  mRegistry := Default(TShellWorkspaceRegistryServices);
  mRegistry.Logger := TLogger.Create;
  mRegistry.SelectedProject := NoSelection;
  mRegistry.ActiveProject := NoActive;
  mRegistry.ReadText := NoText;
  FRegistry := TShellWorkspaceRegistry.Create(mRegistry);
end;

procedure TShellCompileSetupTests.TearDown;
begin
  FreeAndNil(FRegistry);
end;

procedure TShellCompileSetupTests.NoFolderNoJob;
var
  mJob: TShellCompileJob;
  mError: string;
begin
  Assert.IsFalse(TShellCompileSetup.JobFor(FRegistry, '', mJob, mError));
  Assert.AreEqual('Kein Ordner mit Projekt geöffnet', mError);
  Assert.IsFalse(TShellCompileSetup.JobFor(FRegistry, '/tmp/Projekt/A.pas', mJob, mError));
  Assert.AreEqual('Kein Ordner mit Projekt geöffnet', mError);
end;

procedure TShellCompileSetupTests.PowerShellNamed;
begin
  Assert.AreNotEqual('', TShellCompileSetup.PowerShellProgram);
end;

procedure TShellCompileSetupTests.HostWithoutCompiler;
var
  mServices: TShellCompileSetupServices;
  mHost: TShellCompileHost;
begin
  mServices := Default(TShellCompileSetupServices);
  mServices.Logger := TLogger.Create;
  mServices.Workspaces :=
    function: TShellWorkspaceRegistry
    begin
      Result := FRegistry;
    end;
  mHost := TShellCompileSetup.NewHost(mServices);
  try
    Assert.IsNotNull(mHost);
    Assert.IsFalse(mHost.Restricted);
  finally
    mHost.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TShellCompileSetupTests);

end.
