unit Adapters.Lsp.SourceActions;

// Host-Adapter zwischen Editing und Lsp: textDocument/codeAction zeigt die Aktionen an Klasse, Anweisung, uses und
// Deklarationen (#42) über ILspSourceActions; erzeugt werden sie über IEditingCodeActions. Erzeugt nur in
// Shell.Composition.*; kennt nur die beiden Contracts.

interface

uses
  Atlas.Common.CodeActions.Contract,
  Atlas.Common.Lsp.Contract,
  Atlas.Common.Editing.Contract.CodeActions;

type
  /// <summary>ILspSourceActions über die API von Editing.</summary>
  TLspSourceActionsAdapter = class(TInterfacedObject, ILspSourceActions)
  private
    FActions: IEditingCodeActions;
  public
    constructor Create(const AActions: IEditingCodeActions);
    function Structure(const ASite: TLspCodeActionSite): TArray<TCodeAction>;
    function MissingBodies(const ASite: TLspCodeActionSite; out AAction: TCodeAction): Boolean;
    function Statements(const ASite: TLspCodeActionSite): TArray<TCodeAction>;
    function UsesActions(const ASite: TLspCodeActionSite): TArray<TCodeAction>;
    function Declarations(const ASite: TLspCodeActionSite): TArray<TCodeAction>;
    function OrganizeImports(const ASite: TLspCodeActionSite; out AAction: TCodeAction): Boolean;
    /// <summary>Adapter über AActions; nil ohne.</summary>
    class function Wrap(const AActions: IEditingCodeActions): ILspSourceActions; static;
  end;

implementation

/// <summary>Dieselbe Stelle in den Typen von Editing.</summary>
function SiteOf(const ASite: TLspCodeActionSite): TEditingCodeActionSite;
begin
  Result := Default(TEditingCodeActionSite);
  Result.Uri := ASite.Uri;
  Result.Text := ASite.Text;
  Result.Tree := ASite.Tree;
  Result.Range := ASite.Range;
  Result.Index := ASite.Index;
  Result.Style := ASite.Style;
  Result.Refactoring := ASite.Refactoring;
  Result.RuleFreesField := ASite.RuleFreesField;
  Result.WantsEditing := ASite.WantsEditing;
  Result.WantsRemoveUnused := ASite.WantsRemoveUnused;
end;

{ TLspSourceActionsAdapter }

constructor TLspSourceActionsAdapter.Create(const AActions: IEditingCodeActions);
begin
  inherited Create;
  FActions := AActions;
end;

function TLspSourceActionsAdapter.Structure(const ASite: TLspCodeActionSite): TArray<TCodeAction>;
begin
  Result := FActions.Structure(SiteOf(ASite));
end;

function TLspSourceActionsAdapter.MissingBodies(const ASite: TLspCodeActionSite; out AAction: TCodeAction): Boolean;
begin
  Result := FActions.MissingBodies(SiteOf(ASite), AAction);
end;

function TLspSourceActionsAdapter.Statements(const ASite: TLspCodeActionSite): TArray<TCodeAction>;
begin
  Result := FActions.Statements(SiteOf(ASite));
end;

function TLspSourceActionsAdapter.UsesActions(const ASite: TLspCodeActionSite): TArray<TCodeAction>;
begin
  Result := FActions.UsesActions(SiteOf(ASite));
end;

function TLspSourceActionsAdapter.Declarations(const ASite: TLspCodeActionSite): TArray<TCodeAction>;
begin
  Result := FActions.Declarations(SiteOf(ASite));
end;

function TLspSourceActionsAdapter.OrganizeImports(const ASite: TLspCodeActionSite; out AAction: TCodeAction): Boolean;
begin
  Result := FActions.OrganizeImports(SiteOf(ASite), AAction);
end;

class function TLspSourceActionsAdapter.Wrap(const AActions: IEditingCodeActions): ILspSourceActions;
begin
  Result := nil;
  if AActions <> nil then
  begin
    Result := TLspSourceActionsAdapter.Create(AActions);
  end;
end;

end.
