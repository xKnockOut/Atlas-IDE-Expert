unit Shell.Composition.Refactorings.Editing;

// Internals-Rolle Shell: Refactorings am Text der Routine aus Atlas.Common.Lsp.Refactorings (herauslösen, case
// vervollständigen, with auflösen, …), Umschließung entfernen, uses nach dem Umbenennen einer Unit (#512) und nach
// dem Einfügen (#515).

interface

uses
  System.Generics.Collections,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Lsp.Commands,
  Shell.Composition.Refactorings.Services;

type
  TShellEditingRefactorings = class(TShellRefactoringPart)
  private
    function InterfaceUses(const AUnitName: string): TArray<string>;
    function Unwrap(const AArguments: TJSONArray): TJSONValue;
    function UnitRenamed(const AArguments: TJSONArray): TJSONValue;
    function PasteUses(const AArguments: TJSONArray): TJSONValue;
  public
    procedure Register(ACommands: TLspCommands); override;
    function Actions(const AUri: string; const ARange: TTextRange): TArray<TJSONObject>; override;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.Contract,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Lsp.CodeActions,
  Atlas.Common.Lsp.Refactorings,
  Atlas.Common.Lsp.Unwrap,
  Atlas.Common.Lsp.UnitRename,
  Atlas.Common.Lsp.SmartPaste,
  Shell.Texts;

/// <summary>Ist eins der Refactorings aus Atlas.Common.Lsp.Refactorings eingeschaltet?</summary>
function AnyEnabled(const ASettings: TRefactoringSettings): Boolean;
begin
  Result := ASettings.Extract or ASettings.CompleteCase or ASettings.ResolveWith or ASettings.CreateMethod;
  Result := Result or ASettings.InlineCode or ASettings.IfCase or ASettings.Conditions;
  Result := Result or ASettings.ConditionalExpression or ASettings.NestedRoutine;
end;

procedure TShellEditingRefactorings.Register(ACommands: TLspCommands);
begin
  ACommands.Register(TLspUnwrap.Command, Unwrap);
  ACommands.Register(TLspUnitRename.Command, UnitRenamed);
  ACommands.Register(TLspSmartPaste.Command, PasteUses);
end;

function TShellEditingRefactorings.Actions(const AUri: string; const ARange: TTextRange): TArray<TJSONObject>;
var
  mDocument: ITextDocument;
  mContext: TRefactoringContext;
  mAction: TCodeAction;
begin
  Result := nil;
  if not TryOpen(AUri, True, mDocument) then
  begin
    Exit;
  end;
  mContext := ContextFor(AUri);
  if not AnyEnabled(mContext.Settings) then
  begin
    Exit;
  end;
  for mAction in TLspRefactorings.Actions(TSyntaxTreeCache.Get(mDocument, nil).Tree, mDocument.Text, ARange,
    mContext) do
  begin
    Result := Result + [TLspCodeActions.ActionToJson(AUri, mAction)];
  end;
end;

function TShellEditingRefactorings.Unwrap(const AArguments: TJSONArray): TJSONValue;
var
  mUri: string;
  mDocument: ITextDocument;
  mResolver: TNameResolver;
  mIndentWidth: Integer;
  mAnswer: TJSONObject;
begin
  // Argumente: URI, Position, optional die Einrückungsbreite des Editors.
  Require(AArguments, ['uri', 'position']);
  mUri := AArguments.Items[0].Value;
  mIndentWidth := 0;
  if (AArguments.Count > 2) and (AArguments.Items[2] is TJSONNumber) then
  begin
    mIndentWidth := TJSONNumber(AArguments.Items[2]).AsInt;
  end;
  mDocument := Open(mUri);
  mResolver := NewResolver;
  try
    mAnswer := TLspUnwrap.Execute(mResolver, TSyntaxTreeCache.Get(mDocument, nil).Tree, mDocument.Text,
      TLspPositions.ReadPosition(AArguments.Items[1]), ContextFor(mUri), mIndentWidth);
  finally
    mResolver.Free;
  end;
  Log(Format('Umschließung entfernen: %d Konstrukte', [Count(mAnswer, 'candidates')]));
  Result := mAnswer;
end;

function TShellEditingRefactorings.UnitRenamed(const AArguments: TJSONArray): TJSONValue;
var
  mFiles: TArray<string>;
  mItem: TJSONValue;
  mAnswer: TJSONObject;
begin
  // Argumente: alte URI, neue URI, URIs der Dateien des Bereichs (#512).
  if (AArguments = nil) or (AArguments.Count < 3) or not (AArguments.Items[2] is TJSONArray) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, TShellTexts.Missing(['old', 'new', 'files']));
  end;
  if not Settings(AArguments.Items[1].Value).UnitRenameFollowUp then
  begin
    mAnswer := TJSONObject.Create;
    mAnswer.AddPair('enabled', TJSONBool.Create(False));
    Exit(mAnswer);
  end;
  mFiles := nil;
  for mItem in TJSONArray(AArguments.Items[2]) do
  begin
    mFiles := mFiles + [TDocumentUris.ToPath(mItem.Value)];
  end;
  mAnswer := TLspUnitRename.Execute(TDocumentUris.ToPath(AArguments.Items[0].Value),
    TDocumentUris.ToPath(AArguments.Items[1].Value), mFiles, Reader);
  Log(Format('Unit umbenannt: %d von %d Dateien betroffen', [Number(mAnswer, 'count'), Length(mFiles)]));
  Result := mAnswer;
end;

function TShellEditingRefactorings.InterfaceUses(const AUnitName: string): TArray<string>;
var
  mUnit: TUnitIndex;
begin
  Result := nil;
  EnsureUnit(AUnitName);
  if Index.FindUnit(AUnitName, mUnit) then
  begin
    Result := mUnit.InterfaceUses;
  end;
end;

function TShellEditingRefactorings.PasteUses(const AArguments: TJSONArray): TJSONValue;
var
  mUri: string;
  mDocument: ITextDocument;
  mContext: TUsesContext;
  mAnswer: TJSONObject;
begin
  // Argumente: URI, eingefügter Bereich, optional die gewählten Units (#515).
  Require(AArguments, ['uri', 'range']);
  mUri := AArguments.Items[0].Value;
  mDocument := Open(mUri);
  UsesContext(mUri, mContext);
  try
    mAnswer := TLspSmartPaste.Execute(AArguments, mUri, mDocument.Text, TSyntaxTreeCache.Get(mDocument, nil).Tree,
      mContext, InterfaceUses);
  except
    on E: EArgumentException do
      raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, E.Message);
  end;
  if mAnswer.GetValue('units') is TJSONArray then
  begin
    Log(Format('Einfügen: %d Units, %d mehrdeutig', [Count(mAnswer, 'units'), Count(mAnswer, 'choices')]));
  end
  else
  begin
    Log(Format('Einfügen: %d Units eingetragen', [Count(mAnswer, 'added')]));
  end;
  Result := mAnswer;
end;

end.
