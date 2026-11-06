unit Shell.Composition.TestUnits.Tests;

// Testunits der Komposition: ohne Arbeitsbereich kein Umfeld und keine Code-Aktionen, Befehl angemeldet.

interface

uses
  DUnitX.TestFramework,
  Shell.Workspace,
  Shell.Composition.Contract,
  Shell.Composition.TestUnits;

type
  [TestFixture]
  TShellTestUnitsTests = class
  private
    FPicked: string;
    procedure VisitNone(const AVisit: TShellWorkspacesProc);
    function PickNone(const AFileName: string): TShellWorkspace;
    function NoText(const AFileName: string; out AText: string): Boolean;
    function NewServices: TShellTestUnitServices;
  public
    [TearDown]
    procedure TearDown;
    /// <summary>Ohne Arbeitsbereich gibt es kein Umfeld; gefragt wird mit dem Pfad der Datei.</summary>
    [Test]
    procedure NoContextWithoutWorkspace;
    /// <summary>Der Befehl atlas.server.testUnit ist angemeldet, ohne Ordner gibt es keine Code-Aktionen.</summary>
    [Test]
    procedure RegistersCommandWithoutActions;
  end;

implementation

uses
  System.JSON,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Lsp.Commands,
  Atlas.Common.Lsp.TestUnits;

procedure TShellTestUnitsTests.TearDown;
begin
  FPicked := '';
end;

procedure TShellTestUnitsTests.VisitNone(const AVisit: TShellWorkspacesProc);
begin
  AVisit(nil);
end;

function TShellTestUnitsTests.PickNone(const AFileName: string): TShellWorkspace;
begin
  FPicked := AFileName;
  Result := nil;
end;

function TShellTestUnitsTests.NoText(const AFileName: string; out AText: string): Boolean;
begin
  AText := '';
  Result := False;
end;

function TShellTestUnitsTests.NewServices: TShellTestUnitServices;
begin
  Result := Default(TShellTestUnitServices);
  Result.Documents := TDocumentStore.Create;
  Result.Index := TSymbolIndex.Create;
  Result.ReadText := NoText;
  Result.VisitWorkspaces := VisitNone;
  Result.PickWorkspace := PickNone;
end;

procedure TShellTestUnitsTests.NoContextWithoutWorkspace;
var
  mTestUnits: TShellTestUnits;
  mContext: TTestUnitContext;
begin
  mTestUnits := TShellTestUnits.Create(NewServices);
  try
    Assert.IsFalse(mTestUnits.ContextFor('file:///tmp/A.pas', mContext));
    Assert.AreEqual(TDocumentUris.ToPath('file:///tmp/A.pas'), FPicked);
    Assert.AreEqual('', mContext.Root);
  finally
    mTestUnits.Free;
  end;
end;

procedure TShellTestUnitsTests.RegistersCommandWithoutActions;
var
  mTestUnits: TShellTestUnits;
  mCommands: TLspCommands;
  mCapability: TJSONObject;
  mText: string;
begin
  mTestUnits := TShellTestUnits.Create(NewServices);
  mCommands := TLspCommands.Create;
  try
    mTestUnits.RegisterCommand(mCommands);
    mCapability := mCommands.Capability;
    try
      mText := mCapability.ToJSON;
    finally
      mCapability.Free;
    end;
    Assert.IsTrue(Pos('"' + TLspTestUnits.cCommand + '"', mText) > 0);
    Assert.AreEqual(0, Integer(Length(mTestUnits.Actions('file:///tmp/A.pas', 0))));
  finally
    mCommands.Free;
    mTestUnits.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TShellTestUnitsTests);

end.
