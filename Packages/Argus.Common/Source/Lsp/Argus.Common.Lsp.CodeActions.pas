unit Argus.Common.Lsp.CodeActions;

// textDocument/codeAction (#42): Korrekturen und Unterdrückungen zu
// Regeltreffern, try/finally um Create-Zuweisungen und fehlende
// Methodenrümpfe. Die Logik liegt in Argus.Common.Editing.CodeActions und
// Argus.Common.Editing.ClassCompletion; hier nur Protokoll und Regelaufruf.

interface

uses
  System.SysUtils,
  System.JSON,
  Argus.Common.JsonRpc.Contract,
  Argus.Common.JsonRpc.Dispatcher,
  Argus.Common.Documents.Contract,
  Argus.Common.Editing.CodeActions,
  Argus.Common.Lsp.SyntaxDiagnostics;

type
  TLspCodeActions = class
  public const
    Method = 'textDocument/codeAction';
  private
    FStore: IDocumentStore;
    FRuleProvider: TRuleContextProvider;
    function HandleCodeAction(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
  public
    constructor Create(const AStore: IDocumentStore; const ARuleProvider: TRuleContextProvider);
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>Capability für initialize. Der Aufrufer übernimmt das Objekt.</summary>
    class function Capability: TJSONObject; static;
    /// <summary>Eine Aktion als LSP-CodeAction. Der Aufrufer übernimmt das Objekt.</summary>
    class function ActionToJson(const AUri: string; const AAction: TCodeAction): TJSONObject; static;
  end;

implementation

uses
  Argus.Common.Lsp.Positions,
  Argus.Common.Rules.Contract,
  Argus.Common.Rules.Engine,
  Argus.Common.Pascal.SyntaxTree,
  Argus.Common.Pascal.Parser,
  Argus.Common.Editing.ClassCompletion;

{ TLspCodeActions }

constructor TLspCodeActions.Create(const AStore: IDocumentStore; const ARuleProvider: TRuleContextProvider);
begin
  inherited Create;
  FStore := AStore;
  FRuleProvider := ARuleProvider;
end;

procedure TLspCodeActions.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterConcurrentRequest(Method, HandleCodeAction);
end;

class function TLspCodeActions.Capability: TJSONObject;
var
  Kinds: TJSONArray;
begin
  Kinds := TJSONArray.Create;
  Kinds.Add(QuickFixKind);
  Kinds.Add(RewriteKind);
  Result := TJSONObject.Create;
  Result.AddPair('codeActionKinds', Kinds);
end;

class function TLspCodeActions.ActionToJson(const AUri: string; const AAction: TCodeAction): TJSONObject;
var
  Edits: TJSONArray;
  Edit: TRuleEdit;
  Item, Changes, WorkspaceEdit, Diagnostic: TJSONObject;
  Diagnostics: TJSONArray;
begin
  Edits := TJSONArray.Create;
  for Edit in AAction.Edits do
  begin
    Item := TJSONObject.Create;
    Item.AddPair('range', TLspPositions.RangeToJson(Edit.Range));
    Item.AddPair('newText', Edit.NewText);
    Edits.AddElement(Item);
  end;
  Changes := TJSONObject.Create;
  Changes.AddPair(AUri, Edits);
  WorkspaceEdit := TJSONObject.Create;
  WorkspaceEdit.AddPair('changes', Changes);
  Result := TJSONObject.Create;
  Result.AddPair('title', AAction.Title);
  Result.AddPair('kind', AAction.Kind);
  if AAction.IsPreferred then
    Result.AddPair('isPreferred', TJSONBool.Create(True));
  if AAction.RuleId <> '' then
  begin
    Diagnostic := TJSONObject.Create;
    Diagnostic.AddPair('range', TLspPositions.RangeToJson(AAction.DiagnosticRange));
    Diagnostic.AddPair('code', AAction.RuleId);
    Diagnostic.AddPair('source', TLspSyntaxDiagnostics.Source);
    Diagnostic.AddPair('message', '');
    Diagnostics := TJSONArray.Create;
    Diagnostics.AddElement(Diagnostic);
    Result.AddPair('diagnostics', Diagnostics);
  end;
  Result.AddPair('edit', WorkspaceEdit);
end;

function TLspCodeActions.HandleCodeAction(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  Uri: string;
  RangeValue: TJSONValue;
  Range: TTextRange;
  Document: ITextDocument;
  Tree: TSyntaxTree;
  Rules: TRuleCheckContext;
  Context: TRuleContext;
  Findings: TArray<TRuleFinding>;
  Action, Completion: TCodeAction;
  HasCompletion: Boolean;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', Uri) and
    TJSONObject(AParams).TryGetValue<TJSONValue>('range', RangeValue)) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
      'Felder "textDocument.uri" und "range" fehlen in ' + Method);
  if not FStore.TryGet(Uri, Document) then
    Exit(TJSONArray.Create);
  Range := TLspPositions.ReadRange(RangeValue);
  Findings := nil;
  Tree := TPascalParser.Parse(Document.Text);
  try
    ACancellation.ThrowIfCancellationRequested;
    if Assigned(FRuleProvider) and FRuleProvider(Uri, Rules) and (Length(Rules.Rules) > 0) then
    begin
      Context := Default(TRuleContext);
      Context.RelativePath := Rules.RelativePath;
      Context.UnitName := ChangeFileExt(ExtractFileName(StringReplace(Rules.RelativePath, '/', '\', [rfReplaceAll])), '');
      Context.Text := Document.Text;
      Context.Tree := Tree;
      Findings := TRuleEngine.Run(Rules.Rules, Rules.Settings, Context);
    end;
    HasCompletion := TClassCompletion.MissingBodies(Tree, Document.Text, Range.StartPos, Completion);
  finally
    Tree.Free;
  end;
  // Erst jetzt anlegen: Ein Abbruch oben soll kein Objekt zurücklassen.
  Result := TJSONArray.Create;
  for Action in TCodeActions.ForRange(Findings, Document.Text, Range) do
    TJSONArray(Result).AddElement(ActionToJson(Uri, Action));
  if HasCompletion then
    TJSONArray(Result).AddElement(ActionToJson(Uri, Completion));
end;

end.
