unit Shell.Composition.Ide.Tests;

// Nachrichten aus der IDE: Compilermeldungen und Compile-Wechsel gehen an die Komposition, neue Präfixe prüfen
// neu, ein Projektkontext ohne passenden Arbeitsbereich lädt nichts.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.JsonRpc.Dispatcher,
  Shell.Composition.Workspaces,
  Shell.Composition.Ide;

type
  [TestFixture]
  TShellIdeTests = class
  private
    FRegistry: TShellWorkspaceRegistry;
    FIde: TShellIde;
    FDispatcher: TJsonRpcDispatcher;
    FMessages: Integer;
    FEvents: string;
    procedure Notify(const AMethod, AParams: string);
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>Meldungen aus dem Meldungsfenster kommen an; ohne Projekt wird kein Build abgelegt.</summary>
    [Test]
    procedure ForwardsMessages;
    /// <summary>Beginn und Ende eines Compiles melden den Wechsel.</summary>
    [Test]
    procedure ForwardsCompiling;
    /// <summary>Erst ein neuer Kontext, dann nur neue Präfixe: Das zweite prüft neu, ohne neu zu laden.</summary>
    [Test]
    procedure NamingChangeRefreshes;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Compiler.Contract,
  Atlas.Common.Logging.Providers.Logger,
  Atlas.Common.Compiler.IdeBuild,
  Atlas.Common.Lsp.IdeProject,
  Atlas.Common.JsonRpc.TestSupport;

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

{ TShellIdeTests }

procedure TShellIdeTests.Notify(const AMethod, AParams: string);
begin
  TJsonRpcTestSupport.Notify(FDispatcher, AMethod, AParams);
end;

procedure TShellIdeTests.Setup;
var
  mRegistry: TShellWorkspaceRegistryServices;
  mServices: TShellIdeServices;
begin
  mRegistry := Default(TShellWorkspaceRegistryServices);
  mRegistry.Logger := TLogger.Create;
  mRegistry.SelectedProject := NoSelection;
  mRegistry.ActiveProject := NoActive;
  mRegistry.ReadText := NoText;
  FRegistry := TShellWorkspaceRegistry.Create(mRegistry);
  FMessages := -1;
  FEvents := '';
  mServices := Default(TShellIdeServices);
  mServices.Logger := TLogger.Create;
  mServices.Workspaces := FRegistry;
  mServices.MessagesReceived :=
    procedure(const AMessages: TArray<TCompilerMessage>)
    begin
      FMessages := Length(AMessages);
    end;
  mServices.Compiling :=
    procedure(ARunning: Boolean)
    begin
      FEvents := FEvents + BoolToStr(ARunning, True) + ';';
    end;
  mServices.NamingChanged :=
    procedure
    begin
      FEvents := FEvents + 'naming;';
    end;
  FIde := TShellIde.Create(mServices);
  FDispatcher := TJsonRpcDispatcher.Create;
  FIde.Attach(FDispatcher);
end;

procedure TShellIdeTests.TearDown;
begin
  FreeAndNil(FDispatcher);
  FreeAndNil(FIde);
  FreeAndNil(FRegistry);
  FEvents := '';
end;

procedure TShellIdeTests.ForwardsMessages;
begin
  Notify(TIdeBuildTracker.cMessagesMethod, '{"messages":[{"file":"A.pas","line":3,"column":1,"severity":"error",' +
    '"code":"E2003","text":"x"}]}');
  Assert.AreEqual(1, FMessages);
end;

procedure TShellIdeTests.ForwardsCompiling;
begin
  Notify(TIdeBuildTracker.cStartedMethod, '{"group":true,"kind":"make"}');
  Notify(TIdeBuildTracker.cFinishedMethod, '{"group":true,"success":true}');
  Assert.AreEqual('True;False;', FEvents);
end;

procedure TShellIdeTests.NamingChangeRefreshes;
const
  cContext = '{"project":"C:\\P\\A.dproj","configuration":"Debug","platform":"Win32","active":true';
begin
  Notify(TLspIdeProject.cMethod, cContext + '}');
  Assert.AreEqual('', FEvents, 'neuer Kontext lädt neu, prüft nicht nur neu');
  Assert.AreEqual('C:\P\A.dproj', FIde.Project.ActiveProject);
  Notify(TLspIdeProject.cMethod, cContext + ',"naming":{"constant":"c"}}');
  Assert.AreEqual('naming;', FEvents);
end;

initialization
  TDUnitX.RegisterTestFixture(TShellIdeTests);

end.
