unit Shell.Composition.TestSupport;

// Gemeinsame Hilfen der Tests der Zusammensetzung des Servers (Shell.Composition.*.Tests): alle Teile verdrahten,
// Lecksuche ohne Projekte einrichten, Kern und Verteiler im TearDown freigeben.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Shell.Composition.Core,
  Shell.Composition.Parts,
  Shell.Composition.Workspaces,
  Shell.Composition.LeakSetup;

type
  TShellTest = record
  public
    /// <summary>Verdrahtet alle Teile wie der Start des Servers.</summary>
    class procedure WireAll(AParts: TShellParts); static;
    /// <summary>
    ///   Dienste der Lecksuche über eine neue Projektverwaltung ARegistry ohne gewähltes oder aktives Projekt und
    ///   ohne lesbare Dateien. Der Test gibt ARegistry frei.
    /// </summary>
    class function LeakServices(out ARegistry: TShellWorkspaceRegistry): TShellLeakSetupServices; static;
    /// <summary>Gibt Verteiler, Dokumentenlager und Kern samt Arbeitsbereichen frei und leert die Felder.</summary>
    class procedure FreeCore(var ACore: TShellCore; var ADispatcher: TJsonRpcDispatcher;
      var ADocuments: IDocumentStore); static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Logging.Providers.Logger,
  Shell.Composition.ProtocolWiring,
  Shell.Composition.FeatureWiring,
  Shell.Composition.CoreWiring,
  Shell.Composition.CommandWiring;

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

{ TShellTest }

class procedure TShellTest.WireAll(AParts: TShellParts);
begin
  TShellProtocolWiring.Protocol(AParts);
  TShellProtocolWiring.Documents(AParts);
  TShellFeatureWiring.Editing(AParts);
  TShellCoreWiring.Workspaces(AParts);
  TShellCoreWiring.Index(AParts);
  TShellFeatureWiring.Code(AParts);
  TShellFeatureWiring.Analysis(AParts);
  TShellCommandWiring.Commands(AParts);
  TShellFeatureWiring.Ide(AParts);
end;

class function TShellTest.LeakServices(out ARegistry: TShellWorkspaceRegistry): TShellLeakSetupServices;
var
  mRegistry: TShellWorkspaceRegistryServices;
begin
  mRegistry := Default(TShellWorkspaceRegistryServices);
  mRegistry.Logger := TLogger.Create;
  mRegistry.SelectedProject := NoSelection;
  mRegistry.ActiveProject := NoActive;
  mRegistry.ReadText := NoText;
  ARegistry := TShellWorkspaceRegistry.Create(mRegistry);
  Result := Default(TShellLeakSetupServices);
  Result.Logger := mRegistry.Logger;
  Result.Workspaces := ARegistry;
  Result.ReadText := NoText;
end;

class procedure TShellTest.FreeCore(var ACore: TShellCore; var ADispatcher: TJsonRpcDispatcher;
  var ADocuments: IDocumentStore);
begin
  FreeAndNil(ADispatcher);
  ADocuments := nil;
  ACore.FreeWorkspaces;
  FreeAndNil(ACore);
end;

end.
