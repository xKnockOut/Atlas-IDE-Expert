unit Atlas.Common.Editing.CodeActions;

// Code-Aktionen ohne Protokollbezug (#42, #147):
//   - Korrekturen der Regeltreffer: Atlas.Common.Rules.CodeActions
//   - try/finally ergänzen: Atlas.Common.Pascal.TryFinally
//   - uses-Aktionen (#284): fehlende Unit ergänzen, ungenutzte entfernen,
//     ins implementation verschieben (Logik in Semantics.UsesActions)
//   - Zuweisungen umkehren (#313, Logik in Editing.AssignmentSwap)
//   - "Als String-Literal" und "Als Klartext kopieren" (#312, Logik in Editing.StringLiterals)

interface

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Editing.Contract,
  Atlas.Common.CodeActions.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.UsesEdits,
  Atlas.Common.Editing.AssignmentSwap;

type
  TCodeActions = class
  public
    /// <summary>uses aufräumen (doppelte entfernen, mit ASort sortieren); False ohne Änderung.</summary>
    class function OrganizeImports(const AText: string; ASort: Boolean; out AAction: TCodeAction;
      AByNamespace: Boolean): Boolean; overload; static;
    /// <summary>Wie oben mit AByNamespace = False.</summary>
    class function OrganizeImports(const AText: string; ASort: Boolean; out AAction: TCodeAction): Boolean;
      overload; static;
    /// <summary>uses aufräumen nach AOptions (auch nach Herkunft gegliedert, #2794); False ohne Änderung.</summary>
    class function OrganizeImports(const AText: string; const AOptions: TUsesRewrite;
      out AAction: TCodeAction): Boolean; overload; static;
    /// <summary>uses-Aktionen (#284): fehlende Unit zum Bezeichner an ARange.StartPos (Quick-Fix),
    /// interface-Units ins implementation verschieben (Rewrite), dazu für die Einträge an ARange (#621):
    /// „X entfernen“, „Alle ungenutzten uses entfernen“ (ab zwei) und „X ins implementation-uses verschieben“,
    /// mit Tag; inaktive Zweige aus AContext.Inactive zählen dabei nicht. Mit ARemoveUnused zusätzlich
    /// "ungenutzte uses entfernen" (source.removeUnusedImports).</summary>
    class function UsesActions(const AText: string; ATree: TSyntaxTree; const ARange: TTextRange;
      const AContext: TUsesContext; AEditing, ARemoveUnused: Boolean): TArray<TCodeAction>; static;
    /// <summary>"Zuweisungen umkehren" für die Zeilen von ARange (#313); False, wenn keine passt.</summary>
    class function SwapAssignments(const AText: string; const ARange: TTextRange; const AReadOnly: TReadOnlyCheck;
      out AAction: TCodeAction): Boolean; static;
    /// <summary>#312: Bei einer Markierung, die kein Literal ist, "Als String-Literal" (ganze Zeilen);
    /// auf einem Literal "Als Klartext kopieren" über CopyTextCommand. ATokens: die des Syntaxbaums zu AText.
    /// </summary>
    class function StringLiteralActions(const AText: string; const ATokens: TArray<TPascalToken>;
      const ARange: TTextRange; const ASettings: TStringLiteralSettings; AMultiline: Boolean): TArray<TCodeAction>;
      static;
  end;

implementation

uses
  Atlas.Common.Semantics.UsesActions,
  System.Math,
  System.StrUtils,
  System.RegularExpressions,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Pascal.StringLiterals,
  Atlas.Text.Lines,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TEditingCodeActionsText = (CleanUpUses, AddToUses,
    MoveToTheImplementationUses, RemoveAllUnusedUses, CopyAsPlainText, AsStringLiteral, RemoveUnusedUses, Remove,
    SwapAssignments);

const
  cTexts: array[TEditingCodeActionsText] of TAtlasText = (
    (De: 'uses aufräumen'; En: 'Clean up uses'),
    (De: 'uses %s ergänzen'; En: 'Add %s to uses'),
    (De: '%s ins implementation-uses verschieben'; En: 'Move %s to the implementation uses'),
    (De: 'Alle ungenutzten uses entfernen (%d)'; En: 'Remove all unused uses (%d)'),
    (De: 'Als Klartext kopieren'; En: 'Copy as plain text'),
    (De: 'Als String-Literal'; En: 'As string literal'),
    (De: 'Ungenutzte uses entfernen (%s)'; En: 'Remove unused uses (%s)'),
    (De: '%s entfernen'; En: 'Remove %s'),
    (De: 'Zuweisungen umkehren'; En: 'Swap assignments'));

{$SCOPEDENUMS OFF}

/// <summary>Offset des ersten Tokens ab APosition (für die Wahl des uses-Abschnitts).</summary>
function OffsetNear(const ATokens: TArray<TPascalToken>; const APosition: TTextPosition): Integer;
var
  mToken: TPascalToken;
begin
  Result := 0;
  for mToken in ATokens do
  begin
    Result := mToken.Offset;
    if (mToken.EndPos.Line > APosition.Line) or
      ((mToken.EndPos.Line = APosition.Line) and (mToken.EndPos.Character >= APosition.Character)) then
    begin
      Exit;
    end;
  end;
end;

{ TCodeActions }

class function TCodeActions.OrganizeImports(const AText: string; ASort: Boolean; out AAction: TCodeAction;
  AByNamespace: Boolean): Boolean;
var
  mOptions: TUsesRewrite;
begin
  mOptions := Default(TUsesRewrite);
  mOptions.Dedupe := True;
  mOptions.Sort := ASort;
  mOptions.ByNamespace := AByNamespace;
  Result := OrganizeImports(AText, mOptions, AAction);
end;

class function TCodeActions.OrganizeImports(const AText: string; const AOptions: TUsesRewrite;
  out AAction: TCodeAction): Boolean;
var
  mEdits: TArray<TTextEdit>;
begin
  AAction := Default(TCodeAction);
  Result := TPascalUsesEdits.Rewrite(TPascalLexer.Tokenize(AText), AText, AOptions, TTextLines.LineBreakOf(AText),
    mEdits);
  if Result then
  begin
    AAction.Title := cTexts[TEditingCodeActionsText.CleanUpUses].Text;
    AAction.Kind := cOrganizeImportsKind;
    AAction.Edits := mEdits;
  end;
end;

class function TCodeActions.OrganizeImports(const AText: string; ASort: Boolean; out AAction: TCodeAction): Boolean;
begin
  Result := OrganizeImports(AText, ASort, AAction, False);
end;

/// <summary>Überschneiden sich die Bereiche? Enden zählen mit, damit ein Cursor am Namen trifft.</summary>
function Touches(const A, B: TTextRange): Boolean;

  function Before(const AX, AY: TTextPosition): Boolean;
  begin
    Result := (AX.Line < AY.Line) or ((AX.Line = AY.Line) and (AX.Character < AY.Character));
  end;

begin
  Result := not (Before(A.EndPos, B.StartPos) or Before(B.EndPos, A.StartPos));
end;

function NewAction(const ATitle, AKind: string; const AEdits: TArray<TTextEdit>; const ATag: string): TCodeAction;
begin
  Result := Default(TCodeAction);
  Result.Title := ATitle;
  Result.Kind := AKind;
  Result.Edits := AEdits;
  Result.Tag := ATag;
end;

function MoveTitle(const AUnits: TArray<string>): string;
begin
  Result := cTexts[TEditingCodeActionsText.MoveToTheImplementationUses].Fmt([string.Join(', ', AUnits)]);
end;

/// <summary>Bereiche der ungenutzten Einträge.</summary>
function UnusedRanges(const AEntries: TArray<TUsesEntry>): TArray<TTextRange>;
var
  mEntry: TUsesEntry;
begin
  Result := nil;
  for mEntry in AEntries do
  begin
    if mEntry.State = TUsesEntryState.Unused then
    begin
      Result := Result + [mEntry.Range];
    end;
  end;
end;

type
  /// <summary>Sammelt die uses-Aktionen eines Dokuments (#284, #621).</summary>
  TUsesActionList = class
  private
    FText: string;
    FTokens: TArray<TPascalToken>;
    FRange: TTextRange;
    FContext: TUsesContext;
    FLineBreak: string;
    FMovable: TArray<string>;
    FActions: TArray<TCodeAction>;
    FResolution: TUsesResolution;
    FResolved: Boolean;
    procedure Add(const AAction: TCodeAction);
    /// <summary>Nutzung der uses-Einträge aus der Namensauflösung (#1925), einmal je Aktionsliste.</summary>
    function Resolution: TUsesResolution;
    procedure AddRemoveEntry(const AEntry: TUsesEntry; const AUnused: TArray<TTextRange>);
    procedure AddMoveEntry(const AEntry: TUsesEntry);
    /// <summary>Gibt der Aktion für alle verschiebbaren Units die Kennung UsesMoveTag.</summary>
    procedure TagMoveAll(const AUnitName: string);
  public
    /// <summary>ATokens: die des Syntaxbaums zu AText (große Units nicht je Code-Aktion neu zerlegen).</summary>
    constructor Create(const AText: string; const ATokens: TArray<TPascalToken>; const ARange: TTextRange;
      const AContext: TUsesContext);
    /// <summary>Fehlende Unit zum Bezeichner an ARange.StartPos (Quick-Fix).</summary>
    procedure AddMissing(ATree: TSyntaxTree);
    /// <summary>interface-Units ins implementation verschieben (Rewrite).</summary>
    procedure AddMoveAll;
    procedure AddRemoveUnused;
    /// <summary>Einzelne Einträge an ARange (#621), auch in Listen mit {$IFDEF}.</summary>
    procedure AddEntryActions;
    property Actions: TArray<TCodeAction> read FActions;
  end;

{ TUsesActionList }

constructor TUsesActionList.Create(const AText: string; const ATokens: TArray<TPascalToken>;
  const ARange: TTextRange; const AContext: TUsesContext);
begin
  inherited Create;
  FText := AText;
  FRange := ARange;
  FContext := AContext;
  FTokens := ATokens;
  FLineBreak := TTextLines.LineBreakOf(AText);
end;

procedure TUsesActionList.Add(const AAction: TCodeAction);
begin
  FActions := FActions + [AAction];
end;

function TUsesActionList.Resolution: TUsesResolution;
begin
  if not FResolved then
  begin
    FResolution := FContext.Resolution(FText, FContext.Inactive);
    FResolved := True;
  end;
  Result := FResolution;
end;

procedure TUsesActionList.AddRemoveEntry(const AEntry: TUsesEntry; const AUnused: TArray<TTextRange>);
var
  mEdit: TTextEdit;
  mAction: TCodeAction;
begin
  if TUsesActions.RemoveEntries(FText, [AEntry.Range], mEdit) then
  begin
    mAction := NewAction(cTexts[TEditingCodeActionsText.Remove].Fmt([AEntry.Name]), cQuickFixKind, [mEdit],
      cUsesRemoveTag);
    mAction.IsPreferred := True;
    Add(mAction);
  end;
  if (Length(AUnused) > 1) and TUsesActions.RemoveEntries(FText, AUnused, mEdit) then
  begin
    Add(NewAction(cTexts[TEditingCodeActionsText.RemoveAllUnusedUses].Fmt([Length(AUnused)]), cQuickFixKind, [mEdit],
      cUsesRemoveAllTag));
  end;
end;

procedure TUsesActionList.AddMoveEntry(const AEntry: TUsesEntry);
var
  mEdits: TArray<TTextEdit>;
begin
  // Allein verschiebbar: Die Aktion für alle oben hat schon denselben Titel und bekommt die Kennung.
  if (Length(FMovable) = 1) and SameText(FMovable[0], AEntry.Name) then
  begin
    TagMoveAll(AEntry.Name);
  end
  else if TUsesActions.MoveUnits(FTokens, FText, [AEntry.Name], FLineBreak, mEdits) then
  begin
    Add(NewAction(MoveTitle([AEntry.Name]), cRewriteKind, mEdits, cUsesMoveTag));
  end;
end;

procedure TUsesActionList.TagMoveAll(const AUnitName: string);
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(FActions) do
  begin
    if (FActions[mIndex].Kind = cRewriteKind) and SameText(FActions[mIndex].Title, MoveTitle([AUnitName])) then
    begin
      FActions[mIndex].Tag := cUsesMoveTag;
    end;
  end;
end;

procedure TUsesActionList.AddMissing(ATree: TSyntaxTree);
var
  mUnitName: string;
  mEdit: TTextEdit;
begin
  if not Assigned(FContext.Declaring) then
  begin
    Exit;
  end;
  for mUnitName in TUsesActions.MissingUnits(FTokens, ATree, FRange.StartPos, FContext.Declaring,
    FContext.Namespaces) do
  begin
    if TPascalUsesEdits.AddUnit(FTokens, OffsetNear(FTokens, FRange.StartPos), mUnitName, FLineBreak, mEdit) then
    begin
      Add(NewAction(cTexts[TEditingCodeActionsText.AddToUses].Fmt([mUnitName]), cQuickFixKind, [mEdit], ''));
    end;
  end;
end;

procedure TUsesActionList.AddMoveAll;
var
  mEdits: TArray<TTextEdit>;
begin
  FMovable := TUsesActions.MovableUnits(FTokens, FContext.Info, Resolution);
  if TUsesActions.MoveUnits(FTokens, FText, FMovable, FLineBreak, mEdits) then
  begin
    Add(NewAction(MoveTitle(FMovable), cRewriteKind, mEdits, ''));
  end;
end;

procedure TUsesActionList.AddRemoveUnused;
var
  mUnits: TArray<string>;
  mEdits: TArray<TTextEdit>;
begin
  mUnits := TUsesActions.UnusedUnits(FTokens, FContext.Info, FContext.Keep, Resolution);
  if TUsesActions.RemoveUnits(FTokens, FText, mUnits, FLineBreak, mEdits) then
  begin
    Add(NewAction(cTexts[TEditingCodeActionsText.RemoveUnusedUses].Fmt([string.Join(', ', mUnits)]), cRemoveUnusedKind,
      mEdits, ''));
  end;
end;

procedure TUsesActionList.AddEntryActions;
var
  mEntries: TArray<TUsesEntry>;
  mEntry: TUsesEntry;
  mUnused: TArray<TTextRange>;
begin
  mEntries := TUsesActions.Entries(FTokens, FContext.Inactive, FContext.Info, FContext.Keep, Resolution);
  mUnused := UnusedRanges(mEntries);
  for mEntry in mEntries do
  begin
    if not Touches(mEntry.Range, FRange) then
    begin
      Continue;
    end;
    if mEntry.State = TUsesEntryState.Unused then
    begin
      AddRemoveEntry(mEntry, mUnused);
    end
    else if mEntry.State = TUsesEntryState.OnlyImplementation then
    begin
      AddMoveEntry(mEntry);
    end;
  end;
end;

class function TCodeActions.UsesActions(const AText: string; ATree: TSyntaxTree; const ARange: TTextRange;
  const AContext: TUsesContext; AEditing, ARemoveUnused: Boolean): TArray<TCodeAction>;
var
  mList: TUsesActionList;
begin
  Result := nil;
  if not Assigned(AContext.Info) then
  begin
    Exit;
  end;
  if ATree <> nil then
  begin
    mList := TUsesActionList.Create(AText, ATree.Tokens, ARange, AContext);
  end
  else
  begin
    mList := TUsesActionList.Create(AText, TPascalLexer.Tokenize(AText), ARange, AContext);
  end;
  try
    if AEditing then
    begin
      mList.AddMissing(ATree);
      mList.AddMoveAll;
    end;
    if ARemoveUnused then
    begin
      mList.AddRemoveUnused;
    end;
    if AEditing then
    begin
      mList.AddEntryActions;
    end;
    Result := mList.Actions;
  finally
    mList.Free;
  end;
end;

class function TCodeActions.SwapAssignments(const AText: string; const ARange: TTextRange;
  const AReadOnly: TReadOnlyCheck; out AAction: TCodeAction): Boolean;
begin
  AAction := Default(TCodeAction);
  Result := TAssignmentSwap.Swap(AText, ARange, AReadOnly, AAction.Edits);
  if Result then
  begin
    AAction.Title := cTexts[TEditingCodeActionsText.SwapAssignments].Text;
    AAction.Kind := cRewriteKind;
  end;
end;

/// <summary>"Als Klartext kopieren" für ein Literal an APosition; False, wenn dort keins steht.</summary>
function CopyPlainAction(const AText: string; const ATokens: TArray<TPascalToken>; const APosition: TTextPosition;
  out AAction: TCodeAction): Boolean;
var
  mLiteral: TTextRange;
  mPlain: string;
begin
  AAction := Default(TCodeAction);
  Result := TStringLiterals.LiteralAt(ATokens, APosition, mLiteral) and
    TStringLiterals.PlainText(TStringLiterals.TextOf(AText, mLiteral), mPlain);
  if Result then
  begin
    AAction.Title := cTexts[TEditingCodeActionsText.CopyAsPlainText].Text;
    AAction.Kind := cRewriteKind;
    AAction.Command := cCopyTextCommand;
    AAction.CommandArguments := [mPlain];
  end;
end;

/// <summary>Ganze Zeilen der Auswahl ARange; False ohne Auswahl oder außerhalb des Texts.</summary>
function SelectedLines(const ARange: TTextRange; const ALines: TArray<string>; out AFirst, ALast: Integer): Boolean;
begin
  AFirst := ARange.StartPos.Line;
  ALast := Min(ARange.EndPos.Line, High(ALines));
  if (ARange.EndPos.Line > AFirst) and (ARange.EndPos.Character = 0) then
  begin
    ALast := Min(ARange.EndPos.Line - 1, High(ALines));
  end;
  Result := ((ARange.StartPos.Line <> ARange.EndPos.Line) or (ARange.StartPos.Character <> ARange.EndPos.Character))
    and (AFirst >= 0) and (AFirst <= ALast);
end;

/// <summary>Kleinste Einrückung der nicht leeren Zeilen AFirst bis ALast; MaxInt, wenn alle leer sind.</summary>
function CommonIndent(const ALines: TArray<string>; AFirst, ALast: Integer): Integer;
var
  mLine: Integer;
begin
  Result := MaxInt;
  for mLine := AFirst to ALast do
  begin
    if Trim(ALines[mLine]) <> '' then
    begin
      Result := Min(Result, Length(TTextLines.IndentOf(ALines[mLine])));
    end;
  end;
end;

/// <summary>Zeilen AFirst bis ALast ohne die ersten AIndent Zeichen, mit #10 verbunden.</summary>
function Dedented(const ALines: TArray<string>; AFirst, ALast, AIndent: Integer): string;
var
  mLine: Integer;
begin
  Result := '';
  for mLine := AFirst to ALast do
  begin
    if mLine > AFirst then
    begin
      Result := Result + #10;
    end;
    Result := Result + Copy(ALines[mLine], AIndent + 1, MaxInt);
  end;
end;

class function TCodeActions.StringLiteralActions(const AText: string; const ATokens: TArray<TPascalToken>;
  const ARange: TTextRange; const ASettings: TStringLiteralSettings; AMultiline: Boolean): TArray<TCodeAction>;
var
  mLines: TArray<string>;
  mAction: TCodeAction;
  mFirst, mLast, mCommon: Integer;
begin
  Result := nil;
  if CopyPlainAction(AText, ATokens, ARange.StartPos, mAction) then
  begin
    Result := [mAction];
    Exit;
  end;
  // Ohne Auswahl gibt es nichts umzuwandeln: den Text dann nicht in Zeilen teilen.
  if (ARange.StartPos.Line = ARange.EndPos.Line) and (ARange.StartPos.Character = ARange.EndPos.Character) then
  begin
    Exit;
  end;
  mLines := TTextLines.SplitLines(AText);
  if not SelectedLines(ARange, mLines, mFirst, mLast) then
  begin
    Exit;
  end;
  // Gemeinsame Einrückung entfernen; die erste Zeile gibt die Einrückung des Literals vor.
  mCommon := CommonIndent(mLines, mFirst, mLast);
  if mCommon = MaxInt then
  begin
    Exit;
  end;
  mAction := Default(TCodeAction);
  mAction.Title := cTexts[TEditingCodeActionsText.AsStringLiteral].Text;
  mAction.Kind := cRewriteKind;
  mAction.Edits := [TTextEdit.Create(TTextRange.Create(mFirst, 0, mLast, Length(mLines[mLast])),
    TStringLiterals.ToLiteral(Dedented(mLines, mFirst, mLast, mCommon), TTextLines.IndentOf(mLines[mFirst]), True,
    AMultiline, ASettings, TTextLines.LineBreakOf(AText)))];
  Result := [mAction];
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Editing.CodeActions', cTexts);

end.
