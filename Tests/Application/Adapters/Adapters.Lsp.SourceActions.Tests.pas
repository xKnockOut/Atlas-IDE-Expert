unit Adapters.Lsp.SourceActions.Tests;

// Tests für den Host-Adapter, der dem Sprachserver die Code-Aktionen aus Editing gibt.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspSourceActionsAdapterTests = class
  public
    [Test]
    procedure DelegatesToEditing;
    [Test]
    procedure WrapOfNilIsNil;
  end;

implementation

uses
  Atlas.Common.CodeActions.Contract,
  Atlas.Common.Lsp.Contract,
  Editing.Contract.CodeActions,
  Adapters.Lsp.SourceActions,
  Atlas.Common.Semantics.Contract;

type
  /// <summary>Jede Gruppe liefert eine Aktion mit ihrem Namen und der URI der Stelle.</summary>
  TNamedEditingActions = class(TInterfacedObject, IEditingCodeActions)
  private
    function Named(const AName: string; const ASite: TCodeActionSite): TCodeAction;
  public
    function Structure(const ASite: TCodeActionSite): TArray<TCodeAction>;
    function MissingBodies(const ASite: TCodeActionSite; out AAction: TCodeAction): Boolean;
    function Statements(const ASite: TCodeActionSite): TArray<TCodeAction>;
    function UsesActions(const ASite: TCodeActionSite): TArray<TCodeAction>;
    function Declarations(const ASite: TCodeActionSite): TArray<TCodeAction>;
    function OrganizeImports(const ASite: TCodeActionSite; out AAction: TCodeAction): Boolean;
  end;

function TNamedEditingActions.Named(const AName: string; const ASite: TCodeActionSite): TCodeAction;
begin
  Result := Default(TCodeAction);
  Result.Title := AName + '@' + ASite.Uri;
end;

function TNamedEditingActions.Structure(const ASite: TCodeActionSite): TArray<TCodeAction>;
begin
  SetLength(Result, 1);
  Result[0] := Named('Structure', ASite);
end;

function TNamedEditingActions.MissingBodies(const ASite: TCodeActionSite; out AAction: TCodeAction): Boolean;
begin
  AAction := Named('MissingBodies', ASite);
  Result := True;
end;

function TNamedEditingActions.Statements(const ASite: TCodeActionSite): TArray<TCodeAction>;
begin
  SetLength(Result, 1);
  Result[0] := Named('Statements', ASite);
end;

function TNamedEditingActions.UsesActions(const ASite: TCodeActionSite): TArray<TCodeAction>;
begin
  SetLength(Result, 1);
  Result[0] := Named('Uses', ASite);
end;

function TNamedEditingActions.Declarations(const ASite: TCodeActionSite): TArray<TCodeAction>;
begin
  SetLength(Result, 1);
  Result[0] := Named('Declarations', ASite);
end;

function TNamedEditingActions.OrganizeImports(const ASite: TCodeActionSite; out AAction: TCodeAction): Boolean;
begin
  AAction := Named('Organize', ASite);
  Result := False;
end;

{ TLspSourceActionsAdapterTests }

procedure TLspSourceActionsAdapterTests.DelegatesToEditing;
var
  mEditing: IEditingCodeActions;
  mLsp: ILspSourceActions;
  mSite: TCodeActionSite;
  mAction: TCodeAction;
begin
  mEditing := TNamedEditingActions.Create;
  mLsp := TLspSourceActionsAdapter.Wrap(mEditing);
  mSite := Default(TCodeActionSite);
  mSite.Uri := 'u';
  Assert.AreEqual('Structure@u', mLsp.Structure(mSite)[0].Title);
  Assert.AreEqual('Statements@u', mLsp.Statements(mSite)[0].Title);
  Assert.AreEqual('Uses@u', mLsp.UsesActions(mSite)[0].Title);
  Assert.AreEqual('Declarations@u', mLsp.Declarations(mSite)[0].Title);
  Assert.IsTrue(mLsp.MissingBodies(mSite, mAction));
  Assert.AreEqual('MissingBodies@u', mAction.Title);
  Assert.IsFalse(mLsp.OrganizeImports(mSite, mAction));
  Assert.AreEqual('Organize@u', mAction.Title);
  mSite := Default(TCodeActionSite);
  mAction := Default(TCodeAction);
end;

procedure TLspSourceActionsAdapterTests.WrapOfNilIsNil;
var
  mLsp: IInterface;
begin
  mLsp := TLspSourceActionsAdapter.Wrap(nil);
  Assert.IsNull(mLsp);
end;

initialization
  TDUnitX.RegisterTestFixture(TLspSourceActionsAdapterTests);

end.
