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
  System.Generics.Collections, // Inline-Funktionen von TJSONArray (H2443)
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Uris,
  Lsp.Commands,
  Lsp.LeakCandidates,
  Shell.Composition.LeakCandidates,
  Shell.Composition.TestSupport;

{ TShellLeakCandidatesTests }

procedure TShellLeakCandidatesTests.Setup;
begin
  FServices := TShellTest.LeakServices(FRegistry);
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
