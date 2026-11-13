unit Shell.Composition.LeakCandidates.Tests;

// Befehl atlas.server.leakCandidates der Komposition (#1875): angemeldet und
// nebenläufig, ohne geladenes Projekt ein Fehler mit dem Dateinamen.

interface

uses
  DUnitX.TestFramework,
  Shell.Composition.Workspaces,
  Shell.Composition.LeakSetup;

type
  [TestFixture]
  TShellLeakCandidatesTests = class
  private
    FRegistry: TShellWorkspaceRegistry;
    FServices: TShellLeakSetupServices;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>Der Befehl ist angemeldet und läuft nebenläufig.</summary>
    [Test]
    procedure AttachRegistersConcurrent;
    /// <summary>Ohne Arbeitsbereich: Fehler mit dem Dateinamen.</summary>
    [Test]
    procedure NoProjectRaisesWithFileName;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Lsp.Commands,
  Atlas.Common.Lsp.LeakCandidates,
  Atlas.Common.Logging.Providers.Logger,
  Shell.Composition.LeakCandidates;

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

procedure TShellLeakCandidatesTests.Setup;
var
  mRegistry: TShellWorkspaceRegistryServices;
begin
  mRegistry := Default(TShellWorkspaceRegistryServices);
  mRegistry.Logger := TLogger.Create;
  mRegistry.SelectedProject := NoSelection;
  mRegistry.ActiveProject := NoActive;
  mRegistry.ReadText := NoText;
  FRegistry := TShellWorkspaceRegistry.Create(mRegistry);
  FServices := Default(TShellLeakSetupServices);
  FServices.Logger := mRegistry.Logger;
  FServices.Workspaces := FRegistry;
  FServices.ReadText := NoText;
end;

procedure TShellLeakCandidatesTests.TearDown;
begin
  FServices := Default(TShellLeakSetupServices);
  FreeAndNil(FRegistry);
end;

procedure TShellLeakCandidatesTests.AttachRegistersConcurrent;
var
  mCommands: TLspCommands;
begin
  mCommands := TLspCommands.Create;
  try
    TShellLeakCandidates.Attach(mCommands, FServices);
    Assert.IsTrue(mCommands.IsConcurrentCommand(TLspLeakCandidates.cCommand));
  finally
    mCommands.Free;
  end;
end;

procedure TShellLeakCandidatesTests.NoProjectRaisesWithFileName;
var
  mCommands: TLspCommands;
  mArguments: TJSONArray;
  mMessage: string;
begin
  mMessage := '';
  mCommands := TLspCommands.Create;
  mArguments := TJSONArray.Create;
  try
    TShellLeakCandidates.Attach(mCommands, FServices);
    mArguments.Add(TDocumentUris.FromPath(StringReplace('C:\P\App.dproj', '\', PathDelim, [rfReplaceAll])));
    try
      mCommands.Execute(TLspLeakCandidates.cCommand, mArguments).Free;
    except
      on E: EJsonRpcError do
      begin
        mMessage := E.Message;
      end;
    end;
  finally
    mArguments.Free;
    mCommands.Free;
  end;
  Assert.IsTrue(Pos('App.dproj', mMessage) > 0, mMessage);
end;

initialization
  TDUnitX.RegisterTestFixture(TShellLeakCandidatesTests);

end.
