unit Shell.Composition.UnitSearch.Tests;

// Unit-Suche der Komposition: Anmelden der Befehle und die Liste der Units mit den Projekten aus den
// Arbeitsbereichen.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Compiler.Contract,
  Atlas.Common.Editing.Contract,
  Shell.Composition.Contract,
  Shell.Composition.UnitSearch;

type
  [TestFixture]
  TShellUnitSearchTests = class
  private
    FVisits: Integer;
    procedure VisitNone(const AVisit: TShellWorkspacesProc);
    function NoText(const AFileName: string; out AText: string): Boolean;
    function NoUses(const AUri: string; out AContext: TUsesContext): Boolean;
    function NewServices: TShellUnitSearchServices;
  public
    /// <summary>Units suchen, Vorschau und uses ergänzen sind angemeldet.</summary>
    [Test]
    procedure RegistersAllCommands;
    /// <summary>Die Liste der Units fragt die Arbeitsbereiche unter deren Sperre ab und antwortet mit JSON.</summary>
    [Test]
    procedure UnitsVisitWorkspaces;
  end;

implementation

uses
  System.JSON,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Lsp.Commands,
  Atlas.Common.Lsp.UnitSearch;

procedure TShellUnitSearchTests.VisitNone(const AVisit: TShellWorkspacesProc);
begin
  Inc(FVisits);
  AVisit(nil);
end;

function TShellUnitSearchTests.NoText(const AFileName: string; out AText: string): Boolean;
begin
  AText := '';
  Result := False;
end;

function TShellUnitSearchTests.NoUses(const AUri: string; out AContext: TUsesContext): Boolean;
begin
  AContext := Default(TUsesContext);
  Result := False;
end;

function TShellUnitSearchTests.NewServices: TShellUnitSearchServices;
begin
  Result := Default(TShellUnitSearchServices);
  Result.Index := TSymbolIndex.Create;
  Result.VisitWorkspaces := VisitNone;
  Result.ReadText := NoText;
  Result.UsesContextFor := NoUses;
  Result.Process :=
    function: ICompilerProcess
    begin
      Result := nil;
    end;
end;

procedure TShellUnitSearchTests.RegistersAllCommands;
var
  mSearch: TShellUnitSearch;
  mCommands: TLspCommands;
  mCapability: TJSONObject;
  mText: string;
  mName: string;
begin
  mSearch := TShellUnitSearch.Create(NewServices);
  mCommands := TLspCommands.Create;
  try
    mSearch.RegisterCommands(mCommands);
    mCapability := mCommands.Capability;
    try
      mText := mCapability.ToJSON;
    finally
      mCapability.Free;
    end;
    for mName in TArray<string>.Create(TUnitSearch.UnitsCommand, TUnitSearch.PreviewCommand,
      TUnitSearch.AddUsesCommand) do
    begin
      Assert.IsTrue(Pos('"' + mName + '"', mText) > 0, mName);
    end;
  finally
    mCommands.Free;
    mSearch.Free;
  end;
end;

procedure TShellUnitSearchTests.UnitsVisitWorkspaces;
var
  mSearch: TShellUnitSearch;
  mCommands: TLspCommands;
  mArguments: TJSONArray;
  mAnswer: TJSONValue;
begin
  FVisits := 0;
  mSearch := TShellUnitSearch.Create(NewServices);
  mCommands := TLspCommands.Create;
  mArguments := TJSONArray.Create;
  try
    mSearch.RegisterCommands(mCommands);
    mAnswer := mCommands.Execute(TUnitSearch.UnitsCommand, mArguments);
    try
      Assert.IsTrue(mAnswer is TJSONObject);
    finally
      mAnswer.Free;
    end;
  finally
    mArguments.Free;
    mCommands.Free;
    mSearch.Free;
  end;
  Assert.AreEqual(1, FVisits);
end;

initialization
  TDUnitX.RegisterTestFixture(TShellUnitSearchTests);

end.
