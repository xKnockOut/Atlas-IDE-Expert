unit Atlas.Common.Lsp.CodeActions;

// textDocument/codeAction (#42): Korrekturen und Unterdrückungen zu
// Regeltreffern, try/finally um Create-Zuweisungen und fehlende
// Methodenrümpfe. Die Logik liegt in Atlas.Common.Editing.CodeActions und
// Atlas.Common.Editing.ClassCompletion; hier nur Protokoll und Regelaufruf.
//
// Für editor.codeActionsOnSave (#182) gibt es source.organizeImports (uses
// aufräumen, sortieren über "sortUses") und source.fixAll (alle als sicher
// markierten Korrekturen). Beide kommen nur, wenn der Client sie über
// context.only ausdrücklich anfragt. Ebenso source.removeUnusedImports (#284);
// "fehlende Unit ergänzen" und "ins implementation verschieben" kommen mit den
// übrigen Korrekturen, sobald UsesContextFor gesetzt ist. Weitere Aktionen
// mit Dateioperationen (Testunit anlegen, #274) kommen über ExtraActions.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Rules.CodeActions,
  Atlas.Common.Editing.UsesActions,
  Atlas.Common.Editing.Contract,
  Atlas.Common.Editing.ClassActions,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Lsp.SyntaxDiagnostics;

type
  /// <summary>Einstellung "sortUses" für AUri.</summary>
  TSortUsesProvider = reference to function(const AUri: string): Boolean;
  /// <summary>Einstellung "completeBlocks.docComment" für AUri (#88).</summary>
  TDocCommentsProvider = reference to function(const AUri: string): Boolean;
  /// <summary>Einstellungen "stringLiteral" für AUri und ob ein mehrzeiliger String entsteht (#312).</summary>
  TStringLiteralProvider = reference to function(const AUri: string;
    out AMultiline: Boolean): TStringLiteralSettings;

  /// <summary>Index und Einstellungen für die uses-Aktionen; False ohne Index. Dieselbe Art wie bei den
  /// Diagnosen, die ungenutzte uses melden (#621).</summary>
  TUsesContextProvider = Atlas.Common.Lsp.SyntaxDiagnostics.TUsesContextProvider;
  /// <summary>Aktionen in Formulardateien, z. B. binär gespeicherte in Text umwandeln (#122).</summary>
  TFormActionsFunc = reference to function(const AUri, AText: string; const ARange: TTextRange): TArray<TCodeAction>;

  /// <summary>Einstellungen "memberOrder" für AUri (#89).</summary>
  TMemberOrderProvider = reference to function(const AUri: string): TMemberOrderSettings;
  /// <summary>Formatstil für AUri (#43), etwa für die Einrückung von try/finally (#42).</summary>
  TCodeActionStyleProvider = reference to function(const AUri: string): TFormatStyle;
  /// <summary>Einstellungen "refactoring" für AUri, etwa tryFinally und classActions (#42).</summary>
  TCodeActionRefactoringProvider = reference to function(const AUri: string): TRefactoringSettings;
  /// <summary>Index, Namespaces und Version für die Klassen-Aktionen (#42).</summary>
  TClassActionContextProvider = reference to function(const AUri: string): TClassActionContext;

  /// <summary>Weitere Aktionen als fertige LSP-CodeActions, etwa mit Dateioperationen (#274). Der
  /// Aufrufer übernimmt die Objekte.</summary>
  TExtraActionsFunc = reference to function(const AUri: string; const ARange: TTextRange): TArray<TJSONObject>;

  TLspCodeActions = class
  public const
    Method = 'textDocument/codeAction';
    /// <summary>So lange wartet die Glühbirne auf einen laufenden Lauf der Prüfregeln am selben Text (#1761).
    /// </summary>
    RuleWaitMs = 1500;
  private
    FStore: IDocumentStore;
    FRuleProvider: TRuleContextProvider;
    FSortUsesFor: TSortUsesProvider;
    FSortUsesByNamespaceFor: TSortUsesProvider;
    FUsesContextFor: TUsesContextProvider;
    FFormActions: TFormActionsFunc;
    FStringLiteralFor: TStringLiteralProvider;
    FMemberOrderFor: TMemberOrderProvider;
    FDocCommentsFor: TDocCommentsProvider;
    FFormatStyleFor: TCodeActionStyleProvider;
    FRefactoringFor: TCodeActionRefactoringProvider;
    FClassActionContextFor: TClassActionContextProvider;
    FExtraActions: TExtraActionsFunc;
    FDefinesFor: TDefinesProvider;
    function FormFileActions(const AUri, AText: string; const ARange: TTextRange): TJSONArray;
    function HandleCodeAction(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
  public
    constructor Create(const AStore: IDocumentStore; const ARuleProvider: TRuleContextProvider);
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>Capability für initialize. Der Aufrufer übernimmt das Objekt.</summary>
    class function Capability: TJSONObject; static;
    /// <summary>Eine Aktion als LSP-CodeAction. Der Aufrufer übernimmt das Objekt.</summary>
    class function ActionToJson(const AUri: string; const AAction: TCodeAction): TJSONObject; static;
    /// <summary>WorkspaceEdit {"changes": {AUri: [...]}} für Befehle, die Änderungen liefern (#668). Der Aufrufer
    /// übernimmt das Objekt.</summary>
    class function WorkspaceEditJson(const AUri: string; const AEdits: TArray<TTextEdit>): TJSONObject; static;
    /// <summary>Ohne Zuweisung werden uses nicht sortiert.</summary>
    property SortUsesFor: TSortUsesProvider read FSortUsesFor write FSortUsesFor;
    /// <summary>"sortUses": "namespace"; ohne Zuweisung rein alphabetisch.</summary>
    property SortUsesByNamespaceFor: TSortUsesProvider read FSortUsesByNamespaceFor write FSortUsesByNamespaceFor;
    /// <summary>Ohne Zuweisung keine uses-Aktionen (#284).</summary>
    property UsesContextFor: TUsesContextProvider read FUsesContextFor write FUsesContextFor;
    /// <summary>Ohne Zuweisung gelten die Vorgaben mit Verkettung.</summary>
    property StringLiteralFor: TStringLiteralProvider read FStringLiteralFor write FStringLiteralFor;
    /// <summary>Ohne Zuweisung gelten die Vorgaben von "memberOrder".</summary>
    property MemberOrderFor: TMemberOrderProvider read FMemberOrderFor write FMemberOrderFor;
    /// <summary>Ohne Zuweisung gibt es die Aktionen zum Dokumentationskommentar (#88).</summary>
    property DocCommentsFor: TDocCommentsProvider read FDocCommentsFor write FDocCommentsFor;
    /// <summary>Ohne Zuweisung gilt der Standard-Formatstil.</summary>
    property FormatStyleFor: TCodeActionStyleProvider read FFormatStyleFor write FFormatStyleFor;
    /// <summary>Ohne Zuweisung gelten die Vorgaben (try/finally und Klassen-Aktionen an).</summary>
    property RefactoringFor: TCodeActionRefactoringProvider read FRefactoringFor write FRefactoringFor;
    /// <summary>Ohne Zuweisung laufen die Klassen-Aktionen ohne Index, nur mit der Datei.</summary>
    property ClassActionContextFor: TClassActionContextProvider read FClassActionContextFor
      write FClassActionContextFor;
    /// <summary>Aktionen in .dfm/.fmx; ohne Zuweisung keine.</summary>
    property FormActions: TFormActionsFunc read FFormActions write FFormActions;
    /// <summary>Weitere Aktionen in Units (Testunit anlegen und wechseln, #274/#189); ohne Zuweisung keine.</summary>
    property ExtraActions: TExtraActionsFunc read FExtraActions write FExtraActions;
    /// <summary>Symbole des Projekts für die uses-Einträge in {$IFDEF}-Zweigen (#621); ohne Zuweisung zählen alle
    /// Zweige.</summary>
    property DefinesFor: TDefinesProvider read FDefinesFor write FDefinesFor;
  end;

implementation

uses
  System.Generics.Collections,
  System.Diagnostics,
  Atlas.Common.JsonRpc.PendingRequests,
  Atlas.Common.JsonRpc.CurrentRequest,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Checker,
  Atlas.Common.Rules.Prompt,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Editing.ClassCompletion,
  Atlas.Common.Editing.DocComments,
  Atlas.Common.Editing.MemberOrder,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Dfm.Parser,
  Atlas.Common.Index.Contract,
  Atlas.Common.Editing.AssignmentSwap,
  Atlas.Common.Editing.Extract,
  Atlas.Common.Editing.FreeFields,
  Atlas.Common.Lsp.InactiveRegions,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TLspCodeActionsText = (FieldsTextDocumentUriAndRange, CopyFindingAsPrompt, SortClassMembers);

const
  cTexts: array[TLspCodeActionsText] of TAtlasText = (
    (De: 'Felder "textDocument.uri" und "range" fehlen in '; En: 'Fields "textDocument.uri" and "range" missing in '),
    (De: 'Befund %s als Prompt kopieren'; En: 'Copy finding %s as prompt'),
    (De: 'Klassenmitglieder ordnen'; En: 'Sort class members'));

{$SCOPEDENUMS OFF}

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
  Kinds.Add(ExtractKind);
  Kinds.Add(OrganizeImportsKind);
  Kinds.Add(FixAllKind);
  Kinds.Add(RemoveUnusedKind);
  Result := TJSONObject.Create;
  Result.AddPair('codeActionKinds', Kinds);
end;

function EditsToJson(const AEdits: TArray<TTextEdit>): TJSONArray;
var
  Edit: TTextEdit;
  Item: TJSONObject;
begin
  Result := TJSONArray.Create;
  for Edit in AEdits do
  begin
    Item := TJSONObject.Create;
    Item.AddPair('range', TLspPositions.RangeToJson(Edit.Range));
    Item.AddPair('newText', Edit.NewText);
    Result.AddElement(Item);
  end;
end;

class function TLspCodeActions.WorkspaceEditJson(const AUri: string; const AEdits: TArray<TTextEdit>): TJSONObject;
var
  Changes: TJSONObject;
begin
  Changes := TJSONObject.Create;
  Changes.AddPair(AUri, EditsToJson(AEdits));
  Result := TJSONObject.Create;
  Result.AddPair('changes', Changes);
end;

function CommandJson(const AAction: TCodeAction): TJSONObject;
var
  mArguments: TJSONArray;
  mArgument: string;
begin
  Result := TJSONObject.Create;
  Result.AddPair('title', AAction.Title);
  Result.AddPair('command', AAction.Command);
  mArguments := TJSONArray.Create;
  for mArgument in AAction.CommandArguments do
  begin
    mArguments.Add(mArgument);
  end;
  Result.AddPair('arguments', mArguments);
end;

/// <summary>Kennung für Clients, die eine bestimmte Aktion suchen (#621), Vorschau vor dem Übernehmen (#663).
/// </summary>
function DataJson(const AAction: TCodeAction): TJSONObject;
begin
  Result := TJSONObject.Create;
  if AAction.Tag <> '' then
  begin
    Result.AddPair('tag', AAction.Tag);
  end;
  if AAction.Preview <> '' then
  begin
    Result.AddPair('preview', AAction.Preview);
  end;
end;

function DiagnosticsJson(const AAction: TCodeAction): TJSONArray;
var
  mDiagnostic: TJSONObject;
begin
  mDiagnostic := TJSONObject.Create;
  mDiagnostic.AddPair('range', TLspPositions.RangeToJson(AAction.DiagnosticRange));
  mDiagnostic.AddPair('code', AAction.RuleId);
  mDiagnostic.AddPair('source', TLspSyntaxDiagnostics.Source);
  mDiagnostic.AddPair('message', '');
  Result := TJSONArray.Create;
  Result.AddElement(mDiagnostic);
end;

function ChangesJson(const AUri: string; const AAction: TCodeAction): TJSONObject;
var
  mFileEdits: TFileTextEdits;
begin
  Result := TJSONObject.Create;
  // Nur Edits in anderen Dateien (Formulardatei, #309): das Dokument bleibt unverändert.
  if (AAction.Edits <> nil) or (AAction.FileEdits = nil) then
  begin
    Result.AddPair(AUri, EditsToJson(AAction.Edits));
  end;
  for mFileEdits in AAction.FileEdits do
  begin
    Result.AddPair(TDocumentUris.FromPath(mFileEdits.FileName), EditsToJson(mFileEdits.Edits));
  end;
end;

class function TLspCodeActions.ActionToJson(const AUri: string; const AAction: TCodeAction): TJSONObject;
var
  mWorkspaceEdit: TJSONObject;
begin
  mWorkspaceEdit := TJSONObject.Create;
  mWorkspaceEdit.AddPair('changes', ChangesJson(AUri, AAction));
  Result := TJSONObject.Create;
  Result.AddPair('title', AAction.Title);
  Result.AddPair('kind', AAction.Kind);
  if AAction.Command <> '' then
  begin
    Result.AddPair('command', CommandJson(AAction));
  end;
  if AAction.IsPreferred then
  begin
    Result.AddPair('isPreferred', TJSONBool.Create(True));
  end;
  if (AAction.Tag <> '') or (AAction.Preview <> '') then
  begin
    Result.AddPair('data', DataJson(AAction));
  end;
  // Hinweis statt Aktion (LSP 3.16 disabled).
  if AAction.Disabled <> '' then
  begin
    Result.AddPair('disabled', TJSONObject.Create(TJSONPair.Create('reason', AAction.Disabled)));
  end;
  if AAction.RuleId <> '' then
  begin
    Result.AddPair('diagnostics', DiagnosticsJson(AAction));
  end;
  Result.AddPair('edit', mWorkspaceEdit);
end;

/// <summary>Schreibzugriff über den Index prüfen (#313); ohne Index nil.</summary>
function ReadOnlyCheck(AHasRules: Boolean; const ARules: TRuleCheckContext; const AUri, AText: string): TReadOnlyCheck;
var
  Index: ISymbolIndex;
  FileName: string;
begin
  if not AHasRules or (ARules.Services.Index = nil) then
  begin
    Exit(nil);
  end;
  Index := ARules.Services.Index;
  FileName := TDocumentUris.ToPath(AUri);
  Result :=
    function(const AExpression: string): Boolean
    begin
      Result := TAssignmentSwap.ReadOnlyByIndex(Index, FileName, AText, AExpression);
    end;
end;

type
  /// <summary>Sammelt die Aktionen einer Anfrage in einer Unit.</summary>
  TCodeActionBuilder = class
  private
    FOwner: TLspCodeActions;
    FUri: string;
    FRange: TTextRange;
    FText: string;
    FTree: TSyntaxTree;
    FHasRules: Boolean;
    FRules: TRuleCheckContext;
    FFindings: TArray<TRuleFinding>;
    FWantsEditing: Boolean;
    FWantsOrganize: Boolean;
    FWantsFixAll: Boolean;
    FWantsRemoveUnused: Boolean;
    FResult: TJSONArray;
    /// <summary>Abbruchsignal der Anfrage; beendet nur das Warten auf einen laufenden Lauf.</summary>
    FCancellation: IJsonRpcCancellationToken;
    procedure ReadWanted(const AOnly: TArray<string>);
    /// <summary>Treffer der Prüfregeln: aus dem Memo bei gleichem Text, sonst selbst gerechnet und abgelegt.
    /// </summary>
    function RuleFindings: TArray<TRuleFinding>;
    procedure CollectFindings;
    function UsesActions: TArray<TCodeAction>;
    function Style: TFormatStyle;
    function Refactoring: TRefactoringSettings;
    procedure Add(const AAction: TCodeAction); overload;
    procedure Add(const AActions: TArray<TCodeAction>); overload;
    procedure AddRuleActions(const ARefactoring: TRefactoringSettings; const AStyle: TFormatStyle);
    procedure AddClassActions(const AStyle: TFormatStyle);
    function RuleOffersFreeField: Boolean;
    procedure AddFreeFieldActions(const ARefactoring: TRefactoringSettings);
    procedure AddPromptActions;
    procedure AddStringLiteralActions;
    procedure AddDocCommentActions;
    procedure AddMemberOrderAction;
    procedure AddSourceActions;
    procedure AddExtraActions;
    /// <summary>Aktionen an der Stelle, die der Client bei jeder Cursorbewegung anfragt: Regeln, Klasse, Felder,
    /// Prompt.</summary>
    procedure AddEditingActions;
  public
    constructor Create(AOwner: TLspCodeActions; const AUri: string; const ARange: TTextRange; const AText: string;
      ATree: TSyntaxTree);
    /// <summary>Alle Aktionen; ACancellation wird geprüft, bevor das Ergebnis entsteht. Der Aufrufer übernimmt es.
    /// </summary>
    function Build(const AOnly: TArray<string>; const ACancellation: IJsonRpcCancellationToken): TJSONArray;
  end;

constructor TCodeActionBuilder.Create(AOwner: TLspCodeActions; const AUri: string; const ARange: TTextRange;
  const AText: string; ATree: TSyntaxTree);
begin
  inherited Create;
  FOwner := AOwner;
  FUri := AUri;
  FRange := ARange;
  FText := AText;
  FTree := ATree;
end;

procedure TCodeActionBuilder.ReadWanted(const AOnly: TArray<string>);
begin
  FWantsEditing := TCodeActions.KindRequested(QuickFixKind, AOnly) or TCodeActions.KindRequested(RewriteKind, AOnly)
    or TCodeActions.KindRequested(ExtractKind, AOnly);
  // source.* nur auf ausdrückliche Anfrage, nicht bei jeder Cursorbewegung.
  FWantsOrganize := (AOnly <> nil) and TCodeActions.KindRequested(OrganizeImportsKind, AOnly);
  FWantsFixAll := (AOnly <> nil) and TCodeActions.KindRequested(FixAllKind, AOnly);
  FWantsRemoveUnused := (AOnly <> nil) and TCodeActions.KindRequested(RemoveUnusedKind, AOnly);
end;

/// <summary>Warten auf einen fremden Lauf endet nach RuleWaitMs oder mit dem Signal von ACancellation.</summary>
function WaitCancelled(const ACancellation: IJsonRpcCancellationToken): TRuleCancelled;
var
  mClock: TStopwatch;
begin
  mClock := TStopwatch.StartNew;
  Result :=
    function: Boolean
    begin
      Result := (mClock.ElapsedMilliseconds >= TLspCodeActions.RuleWaitMs) or
        ((ACancellation <> nil) and ACancellation.IsCancellationRequested);
    end;
end;

function TCodeActionBuilder.RuleFindings: TArray<TRuleFinding>;
var
  mPastTimeout: IJsonRpcCancellationToken;
  mPrevious: Pointer;
begin
  // Die Treffer der Diagnose am selben Text wiederverwenden (2.0-stable): Die Glühbirne fragt bei jeder
  // Cursorbewegung, und ein eigener Lauf aller Regeln stand hinter dem Prüflauf an. Läuft die Diagnose
  // gerade, wartet die Glühbirne höchstens RuleWaitMs auf sie, statt daneben noch einmal zu rechnen (#1761);
  // danach zeigt sie die übrigen Aktionen ohne die der Regeln, statt ins Zeitlimit zu laufen. Rechnet sie selbst,
  // läuft der Lauf über das Zeitlimit hinaus zu Ende und legt ab; auch tiefe Aufrufe (EnsureUnit) brechen dann nicht
  // ab.
  mPastTimeout := TJsonRpcPastTimeout.Create(FCancellation);
  mPrevious := TJsonRpcCurrentRequest.Enter(mPastTimeout);
  try
    try
      Result := TLspSyntaxDiagnostics.SharedRuleFindings(FText, FTree, FRules, WaitCancelled(FCancellation));
    except
      on ERuleCheckCancelled do
      begin
        if FCancellation <> nil then
        begin
          FCancellation.ThrowIfCancellationRequested;
        end;
        Result := nil;
      end;
    end;
  finally
    TJsonRpcCurrentRequest.Leave(mPrevious);
  end;
end;

procedure TCodeActionBuilder.CollectFindings;
begin
  FHasRules := Assigned(FOwner.FRuleProvider) and FOwner.FRuleProvider(FUri, FRules);
  // Syntaxfehler mit der Korrektur des Parsers (#1022), auch ohne Prüfregeln; Schweregrad und Abschalten wie
  // in den Diagnosen. Die Regeltreffer im selben Regelkontext wie in den Diagnosen (#1112).
  if FHasRules then
  begin
    FFindings := TFileChecker.SyntaxFindings(FTree.Diagnostics, FRules.Settings) + RuleFindings;
  end
  else
  begin
    FFindings := TFileChecker.SyntaxFindings(FTree.Diagnostics, Default(TServerSettings));
  end;
end;

function TCodeActionBuilder.UsesActions: TArray<TCodeAction>;
var
  mUsesContext: TUsesContext;
  mDefines: TArray<string>;
begin
  Result := nil;
  if not ((FWantsEditing or FWantsRemoveUnused) and Assigned(FOwner.FUsesContextFor) and
    FOwner.FUsesContextFor(FUri, mUsesContext)) then
  begin
    Exit;
  end;
  mUsesContext.Inactive := nil;
  if FWantsEditing and Assigned(FOwner.FDefinesFor) and FOwner.FDefinesFor(FUri, mDefines) then
  begin
    mUsesContext.Inactive := TLspInactiveRegions.Ranges(FText, mDefines);
  end;
  Result := TCodeActions.UsesActions(FText, FTree, FRange, mUsesContext, FWantsEditing, FWantsRemoveUnused);
end;

function TCodeActionBuilder.Style: TFormatStyle;
begin
  if Assigned(FOwner.FFormatStyleFor) then
  begin
    Result := FOwner.FFormatStyleFor(FUri);
  end
  else
  begin
    Result := TFormatStyle.Default;
  end;
end;

function TCodeActionBuilder.Refactoring: TRefactoringSettings;
begin
  if Assigned(FOwner.FRefactoringFor) then
  begin
    Result := FOwner.FRefactoringFor(FUri);
  end
  else
  begin
    Result := TRefactoringSettings.Default;
  end;
end;

procedure TCodeActionBuilder.Add(const AAction: TCodeAction);
begin
  FResult.AddElement(TLspCodeActions.ActionToJson(FUri, AAction));
end;

procedure TCodeActionBuilder.Add(const AActions: TArray<TCodeAction>);
var
  mAction: TCodeAction;
begin
  for mAction in AActions do
  begin
    Add(mAction);
  end;
end;

procedure TCodeActionBuilder.AddRuleActions(const ARefactoring: TRefactoringSettings; const AStyle: TFormatStyle);
begin
  if ARefactoring.TryFinally then
  begin
    Add(TRuleCodeActions.ForRange(FFindings, FText, FTree, FRange, AStyle));
  end
  else
  begin
    Add(TRuleCodeActions.ForFindings(FFindings, FText, FRange));
  end;
end;

procedure TCodeActionBuilder.AddClassActions(const AStyle: TFormatStyle);
var
  mContext: TClassActionContext;
begin
  if Assigned(FOwner.FClassActionContextFor) then
  begin
    mContext := FOwner.FClassActionContextFor(FUri);
  end
  else
  begin
    mContext := TClassActionContext.Default;
    mContext.Uri := FUri;
  end;
  mContext.Style := AStyle;
  Add(TClassActions.Actions(FText, FTree, FRange.StartPos.Line, mContext));
end;

function TCodeActionBuilder.RuleOffersFreeField: Boolean;
var
  mFinding: TRuleFinding;
begin
  Result := False;
  for mFinding in FFindings do
  begin
    if (mFinding.RuleId = 'field-not-freed') and (mFinding.Range.StartPos.Line = FRange.StartPos.Line) then
    begin
      Exit(True);
    end;
  end;
end;

procedure TCodeActionBuilder.AddFreeFieldActions(const ARefactoring: TRefactoringSettings);
var
  mFieldIndex: ISymbolIndex;
begin
  mFieldIndex := nil;
  if FHasRules then
  begin
    mFieldIndex := FRules.Services.Index;
  end;
  // Die Aktion am Feld bringt die Regel mit, wenn sie läuft.
  Add(TFreeFields.Actions(FTree, FText, mFieldIndex, FRange.StartPos.Line,
    TFreeFields.StyleOf(ARefactoring.FreeFieldsStyle), not RuleOffersFreeField));
end;

procedure TCodeActionBuilder.AddPromptActions;
var
  mFinding: TRuleFinding;
  mAction: TCodeAction;
begin
  for mFinding in FFindings do
  begin
    if (mFinding.Range.StartPos.Line <= FRange.EndPos.Line) and
      (mFinding.Range.EndPos.Line >= FRange.StartPos.Line) then
    begin
      mAction := Default(TCodeAction);
      mAction.Title := cTexts[TLspCodeActionsText.CopyFindingAsPrompt].Fmt([mFinding.RuleId]);
      mAction.Kind := QuickFixKind;
      mAction.Command := CopyTextCommand;
      mAction.CommandArguments := [TFindingPrompt.Markdown(mFinding, TDocumentUris.ToPath(FUri), FText,
        TFindingPrompt.SharedCatalog)];
      Add(mAction);
    end;
  end;
end;

procedure TCodeActionBuilder.AddStringLiteralActions;
var
  mSettings: TStringLiteralSettings;
  mMultiline: Boolean;
begin
  mMultiline := False;
  if Assigned(FOwner.FStringLiteralFor) then
  begin
    mSettings := FOwner.FStringLiteralFor(FUri, mMultiline);
  end
  else
  begin
    mSettings := TStringLiteralSettings.Default;
  end;
  Add(TCodeActions.StringLiteralActions(FText, FRange, mSettings, mMultiline));
end;

procedure TCodeActionBuilder.AddDocCommentActions;
begin
  // Abschaltbar.
  if not Assigned(FOwner.FDocCommentsFor) or FOwner.FDocCommentsFor(FUri) then
  begin
    Add(TDocComments.Actions(FText, FTree, FRange.StartPos.Line));
  end;
end;

procedure TCodeActionBuilder.AddMemberOrderAction;
var
  mSettings: TMemberOrderSettings;
  mEdit: TRuleEdit;
  mAction: TCodeAction;
begin
  if Assigned(FOwner.FMemberOrderFor) then
  begin
    mSettings := FOwner.FMemberOrderFor(FUri);
  end
  else
  begin
    mSettings := TMemberOrderSettings.Default;
  end;
  if TMemberOrder.Sort(FText, FTree, FRange.StartPos.Line, mSettings, mEdit) then
  begin
    mAction := Default(TCodeAction);
    mAction.Title := cTexts[TLspCodeActionsText.SortClassMembers].Text;
    mAction.Kind := RewriteKind;
    mAction.Edits := [mEdit];
    Add(mAction);
  end;
end;

procedure TCodeActionBuilder.AddSourceActions;
var
  mAction: TCodeAction;
begin
  if FWantsOrganize and TCodeActions.OrganizeImports(FText, Assigned(FOwner.FSortUsesFor) and
    FOwner.FSortUsesFor(FUri), mAction, Assigned(FOwner.FSortUsesByNamespaceFor) and
    FOwner.FSortUsesByNamespaceFor(FUri)) then
  begin
    Add(mAction);
  end;
  if FWantsFixAll and TRuleCodeActions.FixAll(FFindings, mAction) then
  begin
    Add(mAction);
  end;
end;

procedure TCodeActionBuilder.AddExtraActions;
var
  mExtra: TJSONObject;
begin
  if Assigned(FOwner.FExtraActions) then
  begin
    for mExtra in FOwner.FExtraActions(FUri, FRange) do
    begin
      FResult.AddElement(mExtra);
    end;
  end;
end;

procedure TCodeActionBuilder.AddEditingActions;
var
  mStyle: TFormatStyle;
  mRefactoring: TRefactoringSettings;
begin
  mStyle := Style;
  mRefactoring := Refactoring;
  AddRuleActions(mRefactoring, mStyle);
  // Klassen-Aktionen (#42): Getter/Setter/Feld, Interface-Methoden, Überschreiben.
  if mRefactoring.ClassActions then
  begin
    AddClassActions(mStyle);
  end;
  // Felder im Destruktor freigeben (#666).
  if mRefactoring.FreeFields then
  begin
    AddFreeFieldActions(mRefactoring);
  end;
  // Befund als Prompt kopieren (#158): den Text kopiert der Client (Befehl atlas.copyText).
  AddPromptActions;
end;

function TCodeActionBuilder.Build(const AOnly: TArray<string>;
  const ACancellation: IJsonRpcCancellationToken): TJSONArray;
var
  mCompletion, mAction: TCodeAction;
  mHasCompletion: Boolean;
  mUsesActions: TArray<TCodeAction>;
begin
  ReadWanted(AOnly);
  FCancellation := ACancellation;
  ACancellation.ThrowIfCancellationRequested;
  CollectFindings;
  mHasCompletion := FWantsEditing and TClassCompletion.MissingBodies(FTree, FText, FRange.StartPos, mCompletion);
  mUsesActions := UsesActions;
  ACancellation.ThrowIfCancellationRequested;
  // Erst jetzt anlegen: Ein Abbruch oben soll kein Objekt zurücklassen.
  FResult := TJSONArray.Create;
  try
    if FWantsEditing then
    begin
      AddEditingActions;
    end;
    if mHasCompletion then
    begin
      Add(mCompletion);
    end;
    if FWantsEditing and TCodeActions.SwapAssignments(FText, FRange, ReadOnlyCheck(FHasRules, FRules, FUri, FText),
      mAction) then
    begin
      Add(mAction);
    end;
    if FWantsEditing then
    begin
      AddStringLiteralActions;
    end;
    Add(mUsesActions);
    // Dokumentationskommentar erzeugen bzw. an die Signatur anpassen (#88) und Klassenmitglieder ordnen (#89).
    if FWantsEditing then
    begin
      AddDocCommentActions;
      AddMemberOrderAction;
    end;
    AddSourceActions;
    if FWantsEditing then
    begin
      AddExtraActions;
    end;
  except
    FreeAndNil(FResult);
    raise;
  end;
  Result := FResult;
end;

function OnlyKinds(AParams: TJSONObject): TArray<string>;
var
  mOnly: TJSONArray;
  mItem: TJSONValue;
begin
  Result := nil;
  if AParams.TryGetValue<TJSONArray>('context.only', mOnly) then
  begin
    for mItem in mOnly do
    begin
      Result := Result + [mItem.Value];
    end;
  end;
end;

function TLspCodeActions.FormFileActions(const AUri, AText: string; const ARange: TTextRange): TJSONArray;
var
  mAction: TCodeAction;
begin
  Result := TJSONArray.Create;
  if Assigned(FFormActions) then
  begin
    for mAction in FFormActions(AUri, AText, ARange) do
    begin
      Result.AddElement(ActionToJson(AUri, mAction));
    end;
  end;
end;

function TLspCodeActions.HandleCodeAction(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  mUri: string;
  mRangeValue: TJSONValue;
  mRange: TTextRange;
  mDocument: ITextDocument;
  mShared: ISharedSyntaxTree;
  mBuilder: TCodeActionBuilder;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', mUri) and
    TJSONObject(AParams).TryGetValue<TJSONValue>('range', mRangeValue)) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
      cTexts[TLspCodeActionsText.FieldsTextDocumentUriAndRange].Text + Method);
  end;
  if not FStore.TryGet(mUri, mDocument) then
  begin
    Exit(TJSONArray.Create);
  end;
  mRange := TLspPositions.ReadRange(mRangeValue);
  if TDfmParser.IsFormFile(TDocumentUris.ToPath(mUri)) then
  begin
    Exit(FormFileActions(mUri, mDocument.Text, mRange));
  end;
  mShared := TSyntaxTreeCache.Get(mDocument);
  mBuilder := TCodeActionBuilder.Create(Self, mUri, mRange, mDocument.Text, mShared.Tree);
  try
    Result := mBuilder.Build(OnlyKinds(TJSONObject(AParams)), ACancellation);
  finally
    mBuilder.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.CodeActions', cTexts);

end.
