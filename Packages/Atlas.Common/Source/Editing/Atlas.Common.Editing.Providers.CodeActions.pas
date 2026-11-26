unit Atlas.Common.Editing.Providers.CodeActions;

// IEditingCodeActions über TClassActions, TFreeFields, TCodeActions, TDocComments und TMemberOrder: rechnet die
// Stelle einer Anfrage in die Eingaben der Erzeuger um und liest die Einstellungen je Datei.

interface

uses
  Atlas.Common.CodeActions.Contract,
  Atlas.Common.Editing.Contract.CodeActions;

type
  TEditingCodeActionsProvider = class(TInterfacedObject, IEditingCodeActions)
  private
    FSettings: TEditingCodeActionSettings;
  public
    constructor Create(const ASettings: TEditingCodeActionSettings);
    function Structure(const ASite: TEditingCodeActionSite): TArray<TCodeAction>;
    function MissingBodies(const ASite: TEditingCodeActionSite; out AAction: TCodeAction): Boolean;
    function Statements(const ASite: TEditingCodeActionSite): TArray<TCodeAction>;
    function UsesActions(const ASite: TEditingCodeActionSite): TArray<TCodeAction>;
    function Declarations(const ASite: TEditingCodeActionSite): TArray<TCodeAction>;
    function OrganizeImports(const ASite: TEditingCodeActionSite; out AAction: TCodeAction): Boolean;
  end;

implementation

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeHandles,
  Atlas.Common.Pascal.InactiveRegions,
  Atlas.Common.Pascal.Destructors,
  Atlas.Common.Pascal.DocComments,
  Atlas.Common.Semantics.Contract,
  Atlas.Common.Editing.ClassActions,
  Atlas.Common.Editing.FreeFields,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.AssignmentSwap,
  Atlas.Common.Editing.MemberOrder,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TEditingCodeActionsText = (SortClassMembers);

const
  cTexts: array[TEditingCodeActionsText] of TAtlasText = (
    (De: 'Klassenmitglieder ordnen'; En: 'Sort class members'));

{$SCOPEDENUMS OFF}

{ TEditingCodeActionsProvider }

constructor TEditingCodeActionsProvider.Create(const ASettings: TEditingCodeActionSettings);
begin
  inherited Create;
  FSettings := ASettings;
end;

/// <summary>Umgebung der Klassen-Aktionen an ASite; ohne Einstellung nur mit der Datei.</summary>
function ClassContext(const ASettings: TEditingCodeActionSettings; const ASite: TEditingCodeActionSite): TClassActionContext;
var
  mEnvironment: TEditingClassEnvironment;
begin
  Result := TClassActionContext.Default;
  if Assigned(ASettings.ClassEnvironmentFor) then
  begin
    mEnvironment := ASettings.ClassEnvironmentFor(ASite.Uri);
    Result.Index := mEnvironment.Index;
    Result.Namespaces := mEnvironment.Namespaces;
    Result.DelphiVersion := mEnvironment.DelphiVersion;
    Result.Host := mEnvironment.Host;
  end;
  Result.Uri := ASite.Uri;
  Result.Style := ASite.Style;
end;

function TEditingCodeActionsProvider.Structure(const ASite: TEditingCodeActionSite): TArray<TCodeAction>;
var
  mTree: TSyntaxTree;
begin
  Result := nil;
  mTree := TSyntaxTreeHandles.TreeOf(ASite.Tree);
  // Klassen-Aktionen (#42): Getter/Setter/Feld, Interface-Methoden, Überschreiben.
  if ASite.Refactoring.ClassActions then
  begin
    Result := Result + TClassActions.Actions(ASite.Text, mTree, ASite.Range.StartPos.Line,
      ClassContext(FSettings, ASite));
  end;
  // Felder im Destruktor freigeben (#666). Die Aktion am Feld bringt die Regel mit, wenn sie läuft.
  if ASite.Refactoring.FreeFields then
  begin
    Result := Result + TFreeFields.Actions(mTree, ASite.Text, ASite.Index, ASite.Range.StartPos.Line,
      TPascalDestructors.StyleOf(ASite.Refactoring.FreeFieldsStyle), not ASite.RuleFreesField);
  end;
end;

function TEditingCodeActionsProvider.MissingBodies(const ASite: TEditingCodeActionSite; out AAction: TCodeAction): Boolean;
begin
  // Fehlende Rümpfe mit classCompletion.* (#1834) über den Host der Klassen-Aktionen.
  Result := TClassActions.MissingBodies(ASite.Text, TSyntaxTreeHandles.TreeOf(ASite.Tree), ASite.Range.StartPos,
    ClassContext(FSettings, ASite), AAction);
end;

function TEditingCodeActionsProvider.Statements(const ASite: TEditingCodeActionSite): TArray<TCodeAction>;
var
  mAction: TCodeAction;
  mSettings: TStringLiteralSettings;
  mMultiline: Boolean;
begin
  Result := nil;
  if TCodeActions.SwapAssignments(ASite.Text, ASite.Range,
    TAssignmentSwap.ReadOnlyCheckOf(ASite.Index, TDocumentUris.ToPath(ASite.Uri), ASite.Text), mAction) then
  begin
    Result := Result + [mAction];
  end;
  mMultiline := False;
  if Assigned(FSettings.StringLiteralFor) then
  begin
    mSettings := FSettings.StringLiteralFor(ASite.Uri, mMultiline);
  end
  else
  begin
    mSettings := TStringLiteralSettings.Default;
  end;
  Result := Result + TCodeActions.StringLiteralActions(ASite.Text, TSyntaxTreeHandles.TreeOf(ASite.Tree).Tokens,
    ASite.Range, mSettings, mMultiline);
end;

function TEditingCodeActionsProvider.UsesActions(const ASite: TEditingCodeActionSite): TArray<TCodeAction>;
var
  mUsesContext: TUsesContext;
  mDefines: TArray<string>;
begin
  Result := nil;
  if not ((ASite.WantsEditing or ASite.WantsRemoveUnused) and Assigned(FSettings.UsesContextFor) and
    FSettings.UsesContextFor(ASite.Uri, mUsesContext)) then
  begin
    Exit;
  end;
  mUsesContext.Inactive := nil;
  if ASite.WantsEditing and Assigned(FSettings.DefinesFor) and FSettings.DefinesFor(ASite.Uri, mDefines) then
  begin
    mUsesContext.Inactive := TInactiveRegions.Ranges(ASite.Text, mDefines);
  end;
  Result := TCodeActions.UsesActions(ASite.Text, TSyntaxTreeHandles.TreeOf(ASite.Tree), ASite.Range, mUsesContext,
    ASite.WantsEditing, ASite.WantsRemoveUnused);
end;

function TEditingCodeActionsProvider.Declarations(const ASite: TEditingCodeActionSite): TArray<TCodeAction>;
var
  mTree: TSyntaxTree;
  mSettings: TMemberOrderSettings;
  mEdit: TTextEdit;
  mAction: TCodeAction;
begin
  Result := nil;
  mTree := TSyntaxTreeHandles.TreeOf(ASite.Tree);
  // Dokumentationskommentar erzeugen bzw. an die Signatur anpassen (#88); abschaltbar.
  if not Assigned(FSettings.DocCommentsFor) or FSettings.DocCommentsFor(ASite.Uri) then
  begin
    Result := Result + TDocComments.Actions(ASite.Text, mTree, ASite.Range.StartPos.Line);
  end;
  // Klassenmitglieder ordnen (#89).
  if Assigned(FSettings.MemberOrderFor) then
  begin
    mSettings := FSettings.MemberOrderFor(ASite.Uri);
  end
  else
  begin
    mSettings := TMemberOrderSettings.Default;
  end;
  if TMemberOrder.Sort(ASite.Text, mTree, ASite.Range.StartPos.Line, mSettings, mEdit) then
  begin
    mAction := Default(TCodeAction);
    mAction.Title := cTexts[TEditingCodeActionsText.SortClassMembers].Text;
    mAction.Kind := cRewriteKind;
    mAction.Edits := [mEdit];
    Result := Result + [mAction];
  end;
end;

function TEditingCodeActionsProvider.OrganizeImports(const ASite: TEditingCodeActionSite;
  out AAction: TCodeAction): Boolean;
var
  mOrder: TUsesRewrite;
begin
  mOrder := Default(TUsesRewrite);
  if Assigned(FSettings.UsesOrderFor) then
  begin
    mOrder := FSettings.UsesOrderFor(ASite.Uri);
  end;
  mOrder.Dedupe := True;
  Result := TCodeActions.OrganizeImports(ASite.Text, mOrder, AAction);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Editing.Providers.CodeActions', cTexts);

end.
