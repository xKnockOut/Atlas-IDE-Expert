unit Argus.Common.Lsp.CodeActions;

// textDocument/codeAction (#42): Korrekturen und Unterdrückungen zu
// Regeltreffern, try/finally um Create-Zuweisungen und fehlende
// Methodenrümpfe. Die Logik liegt in Argus.Common.Editing.CodeActions und
// Argus.Common.Editing.ClassCompletion; hier nur Protokoll und Regelaufruf.
//
// Für editor.codeActionsOnSave (#182) gibt es source.organizeImports (uses
// aufräumen, sortieren über "sortUses") und source.fixAll (alle als sicher
// markierten Korrekturen). Beide kommen nur, wenn der Client sie über
// context.only ausdrücklich anfragt. Ebenso source.removeUnusedImports (#284);
// "fehlende Unit ergänzen" und "ins implementation verschieben" kommen mit den
// übrigen Korrekturen, sobald UsesContextFor gesetzt ist.

interface

uses
  System.SysUtils,
  System.JSON,
  Argus.Common.JsonRpc.Contract,
  Argus.Common.JsonRpc.Dispatcher,
  Argus.Common.Documents.Contract,
  Argus.Common.Editing.CodeActions,
  Argus.Common.Editing.UsesActions,
  Argus.Common.Lsp.SyntaxDiagnostics;

type
  /// <summary>Einstellung "sortUses" für AUri.</summary>
  TSortUsesProvider = reference to function(const AUri: string): Boolean;
  /// <summary>Index und Einstellungen für die uses-Aktionen; False ohne Index.</summary>
  TUsesContextProvider = reference to function(const AUri: string; out AContext: TUsesContext): Boolean;
  /// <summary>Aktionen in Formulardateien, z. B. binär gespeicherte in Text umwandeln (#122).</summary>
  TFormActionsFunc = reference to function(const AUri, AText: string; const ARange: TTextRange): TArray<TCodeAction>;

  TLspCodeActions = class
  public const
    Method = 'textDocument/codeAction';
  private
    FStore: IDocumentStore;
    FRuleProvider: TRuleContextProvider;
    FSortUsesFor: TSortUsesProvider;
    FSortUsesByNamespaceFor: TSortUsesProvider;
    FUsesContextFor: TUsesContextProvider;
    FFormActions: TFormActionsFunc;
    function HandleCodeAction(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
  public
    constructor Create(const AStore: IDocumentStore; const ARuleProvider: TRuleContextProvider);
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>Capability für initialize. Der Aufrufer übernimmt das Objekt.</summary>
    class function Capability: TJSONObject; static;
    /// <summary>Eine Aktion als LSP-CodeAction. Der Aufrufer übernimmt das Objekt.</summary>
    class function ActionToJson(const AUri: string; const AAction: TCodeAction): TJSONObject; static;
    /// <summary>Ohne Zuweisung werden uses nicht sortiert.</summary>
    property SortUsesFor: TSortUsesProvider read FSortUsesFor write FSortUsesFor;
    /// <summary>"sortUses": "namespace"; ohne Zuweisung rein alphabetisch.</summary>
    property SortUsesByNamespaceFor: TSortUsesProvider read FSortUsesByNamespaceFor write FSortUsesByNamespaceFor;
    /// <summary>Ohne Zuweisung keine uses-Aktionen (#284).</summary>
    property UsesContextFor: TUsesContextProvider read FUsesContextFor write FUsesContextFor;
    /// <summary>Aktionen in .dfm/.fmx; ohne Zuweisung keine.</summary>
    property FormActions: TFormActionsFunc read FFormActions write FFormActions;
  end;

implementation

uses
  Argus.Common.Lsp.Positions,
  Argus.Common.Rules.Contract,
  Argus.Common.Rules.Engine,
  Argus.Common.Pascal.SyntaxTree,
  Argus.Common.Pascal.TreeCache,
  Argus.Common.Editing.ClassCompletion,
  Argus.Common.Documents.Uris,
  Argus.Common.Dfm.Parser,
  Argus.Common.Index.Contract,
  Argus.Common.Editing.AssignmentSwap;

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
  Kinds.Add(OrganizeImportsKind);
  Kinds.Add(FixAllKind);
  Kinds.Add(RemoveUnusedKind);
  Result := TJSONObject.Create;
  Result.AddPair('codeActionKinds', Kinds);
end;

class function TLspCodeActions.ActionToJson(const AUri: string; const AAction: TCodeAction): TJSONObject;
var
  Edits: TJSONArray;
  Edit: TRuleEdit;
  Item, Changes, WorkspaceEdit, Diagnostic, Command: TJSONObject;
  Diagnostics, Arguments: TJSONArray;
  Argument: string;
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
  if AAction.Command <> '' then
  begin
    Command := TJSONObject.Create;
    Command.AddPair('title', AAction.Title);
    Command.AddPair('command', AAction.Command);
    Arguments := TJSONArray.Create;
    for Argument in AAction.CommandArguments do
      Arguments.Add(Argument);
    Command.AddPair('arguments', Arguments);
    Result.AddPair('command', Command);
  end;
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

/// <summary>Schreibzugriff über den Index prüfen (#313); ohne Index nil.</summary>
function ReadOnlyCheck(AHasRules: Boolean; const ARules: TRuleCheckContext; const AUri, AText: string): TReadOnlyCheck;
var
  Index: ISymbolIndex;
  FileName: string;
begin
  if not AHasRules or (ARules.Index = nil) then
    Exit(nil);
  Index := ARules.Index;
  FileName := TDocumentUris.ToPath(AUri);
  Result :=
    function(const AExpression: string): Boolean
    begin
      Result := TAssignmentSwap.ReadOnlyByIndex(Index, FileName, AText, AExpression);
    end;
end;

function TLspCodeActions.HandleCodeAction(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  Uri: string;
  RangeValue: TJSONValue;
  Range: TTextRange;
  Document: ITextDocument;
  Tree: TSyntaxTree;
  Shared: ISharedSyntaxTree;
  Rules: TRuleCheckContext;
  Context: TRuleContext;
  Findings: TArray<TRuleFinding>;
  Action, Completion: TCodeAction;
  HasRules, HasCompletion, WantsEditing, WantsOrganize, WantsFixAll, WantsRemoveUnused: Boolean;
  UsesContext: TUsesContext;
  UsesActions: TArray<TCodeAction>;
  Only: TArray<string>;
  OnlyValue: TJSONArray;
  Item: TJSONValue;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', Uri) and
    TJSONObject(AParams).TryGetValue<TJSONValue>('range', RangeValue)) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
      'Felder "textDocument.uri" und "range" fehlen in ' + Method);
  if not FStore.TryGet(Uri, Document) then
    Exit(TJSONArray.Create);
  Range := TLspPositions.ReadRange(RangeValue);
  if TDfmParser.IsFormFile(TDocumentUris.ToPath(Uri)) then
  begin
    Result := TJSONArray.Create;
    if Assigned(FFormActions) then
      for Action in FFormActions(Uri, Document.Text, Range) do
        TJSONArray(Result).AddElement(ActionToJson(Uri, Action));
    Exit;
  end;
  Only := nil;
  if TJSONObject(AParams).TryGetValue<TJSONArray>('context.only', OnlyValue) then
    for Item in OnlyValue do
      Only := Only + [Item.Value];
  WantsEditing := TCodeActions.KindRequested(QuickFixKind, Only) or TCodeActions.KindRequested(RewriteKind, Only);
  // source.* nur auf ausdrückliche Anfrage, nicht bei jeder Cursorbewegung.
  WantsOrganize := (Only <> nil) and TCodeActions.KindRequested(OrganizeImportsKind, Only);
  WantsFixAll := (Only <> nil) and TCodeActions.KindRequested(FixAllKind, Only);
  WantsRemoveUnused := (Only <> nil) and TCodeActions.KindRequested(RemoveUnusedKind, Only);
  Findings := nil;
  HasRules := False;
  Shared := TSyntaxTreeCache.Get(Document);
  Tree := Shared.Tree;
  ACancellation.ThrowIfCancellationRequested;
  if Assigned(FRuleProvider) and FRuleProvider(Uri, Rules) then
    HasRules := True;
  if HasRules and (Length(Rules.Rules) > 0) then
  begin
    Context := Default(TRuleContext);
    Context.RelativePath := Rules.RelativePath;
    Context.UnitName := ChangeFileExt(ExtractFileName(StringReplace(Rules.RelativePath, '/', '\', [rfReplaceAll])), '');
    Context.Text := Document.Text;
    Context.Tree := Tree;
    Context.Index := Rules.Index;
    Context.FormText := Rules.FormText;
    Findings := TRuleEngine.Run(Rules.Rules, Rules.Settings, Context);
  end;
  HasCompletion := WantsEditing and TClassCompletion.MissingBodies(Tree, Document.Text, Range.StartPos, Completion);
  UsesActions := nil;
  if (WantsEditing or WantsRemoveUnused) and Assigned(FUsesContextFor) and FUsesContextFor(Uri, UsesContext) then
    UsesActions := TCodeActions.UsesActions(Document.Text, Tree, Range, UsesContext, WantsEditing,
      WantsRemoveUnused);
  ACancellation.ThrowIfCancellationRequested;
  // Erst jetzt anlegen: Ein Abbruch oben soll kein Objekt zurücklassen.
  Result := TJSONArray.Create;
  if WantsEditing then
    for Action in TCodeActions.ForRange(Findings, Document.Text, Range) do
      TJSONArray(Result).AddElement(ActionToJson(Uri, Action));
  if HasCompletion then
    TJSONArray(Result).AddElement(ActionToJson(Uri, Completion));
  if WantsEditing and TCodeActions.SwapAssignments(Document.Text, Range, ReadOnlyCheck(HasRules, Rules, Uri,
    Document.Text), Action) then
    TJSONArray(Result).AddElement(ActionToJson(Uri, Action));
  for Action in UsesActions do
    TJSONArray(Result).AddElement(ActionToJson(Uri, Action));
  if WantsOrganize and TCodeActions.OrganizeImports(Document.Text, Assigned(FSortUsesFor) and FSortUsesFor(Uri),
    Action, Assigned(FSortUsesByNamespaceFor) and FSortUsesByNamespaceFor(Uri)) then
    TJSONArray(Result).AddElement(ActionToJson(Uri, Action));
  if WantsFixAll and TCodeActions.FixAll(Findings, Action) then
    TJSONArray(Result).AddElement(ActionToJson(Uri, Action));
end;

end.
