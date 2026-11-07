unit Shell.Composition.Refactorings.Fixes;

// Internals-Rolle Shell: Korrekturen als Code-Aktion: zu Compilermeldungen (Warnung abschalten, Korrekturen des
// Compilers, fehlende Unit) und am Code (Typ ausschreiben #453, Konstante statt Variable, in var-Block verschieben
// #644).

interface

uses
  System.Generics.Collections,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Lsp.Commands,
  Shell.Composition.Refactorings.Services;

type
  TShellFixRefactorings = class(TShellRefactoringPart)
  private
    function DisableWarningActions(const AUri: string; const ARange: TTextRange): TArray<TJSONObject>;
    function DisableWarning(const AArguments: TJSONArray): TJSONValue;
    function CompilerFixActions(const AUri: string; const ARange: TTextRange): TArray<TJSONObject>;
    function MissingUnitActions(const AUri: string; const ARange: TTextRange): TArray<TJSONObject>;
    function ExplicitTypeActions(const AUri: string; const APosition: TTextPosition): TArray<TJSONObject>;
    function SuggestConstActions(const AUri: string; const APosition: TTextPosition): TArray<TJSONObject>;
    function VarBlockActions(const AUri: string; const APosition: TTextPosition): TArray<TJSONObject>;
  public
    procedure Register(ACommands: TLspCommands); override;
    function Actions(const AUri: string; const ARange: TTextRange): TArray<TJSONObject>; override;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Compiler.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Pascal.LanguageFeatures,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Semantics.ResolvedSignatures,
  Atlas.Common.Editing.Contract,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.CompilerFixes,
  Atlas.Common.Editing.SuggestConst,
  Atlas.Common.Editing.VarBlock,
  Atlas.Common.Projects.MissingUnit,
  Atlas.Common.Lsp.CodeActions,
  Atlas.Common.Lsp.InlayHints,
  Atlas.Common.Lsp.DisableWarning,
  Atlas.Common.Lsp.CompilerFixes,
  Atlas.Common.Lsp.MissingUnit,
  Atlas.Common.Localization.Texts;

type
{$SCOPEDENUMS ON}
  TFixRefactoringText = (DisableWarning);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TFixRefactoringText] of TAtlasText = (
    (De: 'Warnung abschalten'; En: 'Disable warning'));

/// <summary>Typ einer Inline-Variablen ohne Typangabe für „In var-Block verschieben“ (#644): dieselbe Ermittlung
/// wie „Typ ausschreiben“ (#453), samt der uses, die ihn sichtbar machen.</summary>
function VarBlockTypes(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName,
  ALineBreak: string): TVarBlockTypeLookup;
begin
  Result :=
    function(ADecl: TSyntaxNode; out AType: string; out AEdits: TArray<TTextEdit>): Boolean
    var
      mFound: TInferredType;
      mAction: TCodeAction;
    begin
      AType := '';
      AEdits := nil;
      Result := False;
      for mFound in TLspInlayHints.Inferred(AResolver, ATree, AFileName, TTextRange.Create(ADecl.StartPos,
        ADecl.EndPos)) do
      begin
        if not mFound.ForIn and TLspInlayHints.ExplicitTypeAction(AResolver, ATree, AFileName, mFound.NameStart,
          ALineBreak, mAction) and (mAction.Edits <> nil) then
        begin
          // Erstes Edit ": Typ", die übrigen ergänzen uses.
          AType := Copy(mAction.Edits[0].NewText, 3, MaxInt);
          AEdits := Copy(mAction.Edits, 1, MaxInt);
          Exit(True);
        end;
      end;
    end;
end;

/// <summary>Einrichtung der Suche nach einer fehlenden Unit für die Datei AFileName.</summary>
function MissingUnitResolveFunc(const ASetup: TShellMissingUnitSetupFunc; const AFileName: string): TMissingUnitResolve;
begin
  Result :=
    function(const AUnitName: string; out AResult: TMissingUnitSetup): Boolean
    begin
      Result := ASetup(AFileName, AUnitName, AResult);
    end;
end;

procedure TShellFixRefactorings.Register(ACommands: TLspCommands);
begin
  ACommands.Register(TLspDisableWarning.cApplyCommand, DisableWarning);
end;

function TShellFixRefactorings.Actions(const AUri: string; const ARange: TTextRange): TArray<TJSONObject>;
begin
  Result := ExplicitTypeActions(AUri, ARange.StartPos);
  Result := Result + CompilerFixActions(AUri, ARange);
  Result := Result + MissingUnitActions(AUri, ARange);
  Result := Result + DisableWarningActions(AUri, ARange);
  Result := Result + SuggestConstActions(AUri, ARange.StartPos);
  Result := Result + VarBlockActions(AUri, ARange.StartPos);
end;

function TShellFixRefactorings.DisableWarningActions(const AUri: string;
  const ARange: TTextRange): TArray<TJSONObject>;
var
  mOptions: TDisableWarningOptions;
  mMessages: TArray<TCompilerMessage>;
  mDocument: ITextDocument;
  mSettings: TRefactoringSettings;
begin
  Result := nil;
  mSettings := Settings(AUri);
  if not mSettings.DisableWarning or not Documents.TryGet(AUri, mDocument) then
  begin
    Exit;
  end;
  mMessages := Messages(TDocumentUris.ToPath(AUri));
  if mMessages = nil then
  begin
    Exit;
  end;
  mOptions := Default(TDisableWarningOptions);
  mOptions.Enabled := True;
  mOptions.AskReason := mSettings.DisableWarningReason;
  mOptions.Version := DelphiVersion(AUri);
  Result := TLspDisableWarning.Actions(mOptions, TSyntaxTreeCache.Get(mDocument, nil).Tree, AUri,
    ARange.StartPos.Line, ARange.EndPos.Line, mMessages);
end;

function TShellFixRefactorings.DisableWarning(const AArguments: TJSONArray): TJSONValue;
var
  mUri: string;
  mDocument: ITextDocument;
begin
  Require(AArguments, ['uri']);
  mUri := AArguments.Items[0].Value;
  mDocument := Open(mUri, Settings(mUri).DisableWarning,
    Disabled(cTexts[TFixRefactoringText.DisableWarning].Text, 'refactoring.disableWarning'));
  Result := TLspDisableWarning.Execute(AArguments, mDocument.Text, TSyntaxTreeCache.Get(mDocument, nil).Tree,
    DelphiVersion(mUri));
end;

function TShellFixRefactorings.CompilerFixActions(const AUri: string; const ARange: TTextRange): TArray<TJSONObject>;
var
  mMessages: TArray<TCompilerMessage>;
  mDocument: ITextDocument;
  mUses: TUsesContext;
  mContext: TCompilerFixContext;
  mRequest: TCompilerFixRequest;
begin
  Result := nil;
  if not Settings(AUri).CompilerFixes or not Documents.TryGet(AUri, mDocument) then
  begin
    Exit;
  end;
  mMessages := Messages(TDocumentUris.ToPath(AUri));
  if mMessages = nil then
  begin
    Exit;
  end;
  mContext := Default(TCompilerFixContext);
  if UsesContext(AUri, mUses) then
  begin
    mContext.Declaring := mUses.Declaring;
    mContext.Namespaces := mUses.Namespaces;
  end;
  mRequest.Text := mDocument.Text;
  mRequest.Tree := TSyntaxTreeCache.Get(mDocument, nil).Tree;
  mRequest.Uri := AUri;
  mRequest.Range := ARange;
  mRequest.Context := mContext;
  Result := TLspCompilerFixes.Actions(True, mRequest, mMessages);
end;

function TShellFixRefactorings.MissingUnitActions(const AUri: string; const ARange: TTextRange): TArray<TJSONObject>;
var
  mFileName: string;
  mMessages: TArray<TCompilerMessage>;
begin
  Result := nil;
  if not Settings(AUri).MissingUnit then
  begin
    Exit;
  end;
  mFileName := TDocumentUris.ToPath(AUri);
  mMessages := Messages(mFileName);
  if mMessages <> nil then
  begin
    Result := TLspMissingUnit.Actions(True, ARange.StartPos.Line, ARange.EndPos.Line, mMessages,
      MissingUnitResolveFunc(SetupProvider, mFileName));
  end;
end;

function TShellFixRefactorings.ExplicitTypeActions(const AUri: string;
  const APosition: TTextPosition): TArray<TJSONObject>;
var
  mDocument: ITextDocument;
  mResolver: TNameResolver;
  mAction: TCodeAction;
begin
  Result := nil;
  if not TryOpen(AUri, Settings(AUri).ExplicitType, mDocument) then
  begin
    Exit;
  end;
  mResolver := NewResolver;
  try
    if TLspInlayHints.ExplicitTypeAction(mResolver, TSyntaxTreeCache.Get(mDocument, nil).Tree,
      TDocumentUris.ToPath(AUri), APosition, LineBreakOf(mDocument.Text), mAction) then
    begin
      Result := [TLspCodeActions.ActionToJson(AUri, mAction)];
    end;
  finally
    mResolver.Free;
  end;
end;

function TShellFixRefactorings.SuggestConstActions(const AUri: string;
  const APosition: TTextPosition): TArray<TJSONObject>;
var
  mDocument: ITextDocument;
  mShared: ISharedSyntaxTree;
  mResolver: TNameResolver;
  mAction: TCodeAction;
  mFileName: string;
begin
  Result := nil;
  if not TryOpen(AUri, Settings(AUri).SuggestConst and TLanguageFeatures.IsAvailable(TLanguageFeature.InlineVariable,
    LanguageLevel(AUri)), mDocument) then
  begin
    Exit;
  end;
  mShared := TSyntaxTreeCache.Get(mDocument, nil);
  mFileName := TDocumentUris.ToPath(AUri);
  // Dieselbe Übergabeart von Argumenten wie die Unterstreichung im Plugin (atlas.server.reassigned).
  mResolver := NewResolver;
  try
    mResolver.PinTree(mShared.Tree, mFileName);
    try
      if TSuggestConst.Action(mDocument.Text, mShared.Tree, APosition, TResolvedSignatures.Lookup(mResolver,
        mShared.Tree, mFileName), mAction) then
      begin
        Result := [TLspCodeActions.ActionToJson(AUri, mAction)];
      end;
    finally
      mResolver.UnpinTree;
    end;
  finally
    mResolver.Free;
  end;
end;

function TShellFixRefactorings.VarBlockActions(const AUri: string;
  const APosition: TTextPosition): TArray<TJSONObject>;
var
  mDocument: ITextDocument;
  mShared: ISharedSyntaxTree;
  mResolver: TNameResolver;
  mSettings: TRefactoringSettings;
  mOptions: TVarBlockOptions;
  mAction: TCodeAction;
  mFileName: string;
begin
  Result := nil;
  mSettings := Settings(AUri);
  if not TryOpen(AUri, mSettings.VarBlock, mDocument) then
  begin
    Exit;
  end;
  mShared := TSyntaxTreeCache.Get(mDocument, nil);
  mFileName := TDocumentUris.ToPath(AUri);
  mResolver := NewResolver;
  try
    mResolver.PinTree(mShared.Tree, mFileName);
    try
      mOptions := TVarBlockOptions.Default;
      mOptions.InlineVariables := TLanguageFeatures.IsAvailable(TLanguageFeature.InlineVariable, LanguageLevel(AUri));
      mOptions.Merge := mSettings.VarBlockMerge;
      mOptions.Sort := TVarBlock.SortOf(mSettings.VarBlockSort);
      mOptions.Style := FormatStyle(AUri);
      mOptions.Lookup := TResolvedSignatures.Lookup(mResolver, mShared.Tree, mFileName);
      mOptions.Types := VarBlockTypes(mResolver, mShared.Tree, mFileName, LineBreakOf(mDocument.Text));
      for mAction in TVarBlock.Actions(mDocument.Text, mShared.Tree, APosition, mOptions) do
      begin
        Result := Result + [TLspCodeActions.ActionToJson(AUri, mAction)];
      end;
    finally
      mResolver.UnpinTree;
    end;
  finally
    mResolver.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Shell.Composition.Refactorings.Fixes', cTexts);

end.
