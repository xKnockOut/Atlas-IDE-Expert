unit Adapters.Lsp.SourceActions;

// Host-Adapter zwischen Editing und Lsp: textDocument/codeAction zeigt die Aktionen an Klasse, Anweisung, uses und
// Deklarationen (#42) über ILspSourceActions; erzeugt werden sie über IEditingCodeActions. Erzeugt nur in
// Shell.Composition.*; kennt nur die beiden Contracts und die gemeinsame Stelle
// TCodeActionSite (Semantics.Contract).

interface

uses
  Atlas.Common.CodeActions.Contract,
  Atlas.Common.Semantics.Contract,
  Lsp.Contract,
  Editing.Contract.CodeActions;

type
  /// <summary>ILspSourceActions über die API von Editing.</summary>
  TLspSourceActionsAdapter = class(TInterfacedObject, ILspSourceActions)
  private
    FActions: IEditingCodeActions;
  public
    constructor Create(const AActions: IEditingCodeActions);
    function Structure(const ASite: TCodeActionSite): TArray<TCodeAction>;
    function MissingBodies(const ASite: TCodeActionSite; out AAction: TCodeAction): Boolean;
    function Statements(const ASite: TCodeActionSite): TArray<TCodeAction>;
    function UsesActions(const ASite: TCodeActionSite): TArray<TCodeAction>;
    function Declarations(const ASite: TCodeActionSite): TArray<TCodeAction>;
    function OrganizeImports(const ASite: TCodeActionSite; out AAction: TCodeAction): Boolean;
    /// <summary>Adapter über AActions; nil ohne.</summary>
    class function Wrap(const AActions: IEditingCodeActions): ILspSourceActions; static;
  end;

implementation

{ TLspSourceActionsAdapter }

constructor TLspSourceActionsAdapter.Create(const AActions: IEditingCodeActions);
begin
  inherited Create;
  FActions := AActions;
end;

function TLspSourceActionsAdapter.Structure(const ASite: TCodeActionSite): TArray<TCodeAction>;
begin
  Result := FActions.Structure(ASite);
end;

function TLspSourceActionsAdapter.MissingBodies(const ASite: TCodeActionSite; out AAction: TCodeAction): Boolean;
begin
  Result := FActions.MissingBodies(ASite, AAction);
end;

function TLspSourceActionsAdapter.Statements(const ASite: TCodeActionSite): TArray<TCodeAction>;
begin
  Result := FActions.Statements(ASite);
end;

function TLspSourceActionsAdapter.UsesActions(const ASite: TCodeActionSite): TArray<TCodeAction>;
begin
  Result := FActions.UsesActions(ASite);
end;

function TLspSourceActionsAdapter.Declarations(const ASite: TCodeActionSite): TArray<TCodeAction>;
begin
  Result := FActions.Declarations(ASite);
end;

function TLspSourceActionsAdapter.OrganizeImports(const ASite: TCodeActionSite; out AAction: TCodeAction): Boolean;
begin
  Result := FActions.OrganizeImports(ASite, AAction);
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
