unit Atlas.Common.Editing.CodeActions;

// Code-Aktionen ohne Protokollbezug (#42, #147):
//   - Korrekturen der Regeltreffer: Atlas.Common.Rules.CodeActions (A-11)
//   - "Regel für diese Zeile unterdrücken": eigene Kommentarzeile darüber,
//     bestehende "// lsp-ignore:"-Zeile darüber wird ergänzt
//   - "Regel für diese Datei unterdrücken": "// lsp-ignore-file:" in Zeile 1
//   - "try/finally ergänzen" nach "X := T.Create(...);" mit passendem X.Free;
//     bei "Result := T.Create(...)" stattdessen try/except, das Result nur im
//     Fehlerfall freigibt (das Objekt wird ja zurückgegeben). Die Entscheidung
//     trifft der Syntaxbaum: nur lokale Variablen (auch "var X := …"), keine
//     Felder und kein Self.F; der Aufruf darf über mehrere Zeilen gehen. Der
//     try-Block schließt die folgenden Anweisungen bis zum Blockende ein, bei
//     einer Auswahl bis zu deren Ende; steht dort schon "X.Free;", wandert es
//     ins finally. Einrückung nach dem Formatstil (#43).
//   - uses-Aktionen (#284): fehlende Unit ergänzen, ungenutzte entfernen,
//     ins implementation verschieben (Logik in Editing.UsesActions)
//   - Zuweisungen umkehren (#313, Logik in Editing.AssignmentSwap)
//   - "Als String-Literal" und "Als Klartext kopieren" (#312, Logik in Editing.StringLiterals)

interface

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Editing.UsesActions,
  Atlas.Common.Editing.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Editing.AssignmentSwap;

const
  cQuickFixKind = 'quickfix';
  cRewriteKind = 'refactor.rewrite';
  // Für editor.codeActionsOnSave (#182).
  cOrganizeImportsKind = 'source.organizeImports';
  cFixAllKind = 'source.fixAll';
  /// <summary>Ungenutzte uses entfernen (#284).</summary>
  cRemoveUnusedKind = 'source.removeUnusedImports';
  /// <summary>Client-Befehl, der das erste Argument in die Zwischenablage legt (#312).</summary>
  cCopyTextCommand = 'atlas.copyText';
  /// <summary>Client-Befehl, der den Cursor im Dokument der Aktion auf Zeile (erstes Argument) und Zeichen
  /// (zweites Argument, beide 0-basiert) setzt (#915).</summary>
  cGoToPositionCommand = 'atlas.goToPosition';
  /// <summary>Wie GoToPositionCommand; danach öffnet der Client den Parameter-Hint an der Stelle (#1007).</summary>
  cShowSignatureHelpCommand = 'atlas.showSignatureHelp';
  /// <summary>Client-Befehl, der die Unit-Beziehungen (#593) der Datei der Aktion zeigt, z. B. „Graph zeigen“ an
  /// einem Unit-Zyklus (#896).</summary>
  cShowUnitRelationsCommand = 'atlas.showUnitRelations';
  /// <summary>Kennungen der uses-Aktionen für den Hover des Plugins (#621), in data.tag.</summary>
  cUsesRemoveTag = 'uses.remove';
  cUsesRemoveAllTag = 'uses.removeAll';
  cUsesMoveTag = 'uses.move';
  /// <summary>Fehlende Methodenrümpfe (#42) und fehlende case-Zweige (#50); „Anweisung vervollständigen“ des
  /// Plugins sucht sie (#697).</summary>
  cClassBodiesTag = 'class.bodies';
  cCaseCompleteTag = 'case.complete';
  /// <summary>Schnellkorrektur eines Regeltreffers und „für diese Zeile/Datei unterdrücken“ (#909); das Fenster
  /// „Atlas-Prüfung“ und der Befund-Hover wählen damit die Aktion zum Treffer (Regel in diagnostics[0].code).
  /// </summary>
  cRuleFixTag = 'rule.fix';
  cRuleSuppressLineTag = 'rule.suppressLine';
  cRuleSuppressFileTag = 'rule.suppressFile';

type
  /// <summary>Edits in einer anderen Datei als dem Dokument der Aktion, z. B. der Formulardatei (#309).</summary>
  TFileTextEdits = record
    FileName: string;
    Edits: TArray<TTextEdit>;
  end;

  TCodeAction = record
    Title: string;
    Kind: string;
    /// <summary>Edits im Dokument der Aktion.</summary>
    Edits: TArray<TTextEdit>;
    /// <summary>Edits in weiteren Dateien (#309); nil = keine.</summary>
    FileEdits: TArray<TFileTextEdits>;
    IsPreferred: Boolean;
    /// <summary>Regelkennung des behobenen Treffers, sonst ''.</summary>
    RuleId: string;
    /// <summary>Bereich des behobenen Treffers, wenn RuleId gesetzt ist.</summary>
    DiagnosticRange: TTextRange;
    /// <summary>Befehl statt oder nach den Edits, z. B. für Dateiumwandlungen; '' ohne.</summary>
    Command: string;
    CommandArguments: TArray<string>;
    /// <summary>Kennung für Clients, die eine bestimmte Aktion suchen (UsesRemoveTag, #621); '' ohne.</summary>
    Tag: string;
    /// <summary>Text, den der Client vor dem Übernehmen als Vorschau zeigt (neue Signatur, #663); '' ohne.</summary>
    Preview: string;
    /// <summary>Grund, warum die Aktion hier nicht geht (Hinweis statt Aktion, #663); '' wenn sie geht.</summary>
    Disabled: string;
  end;

  TCodeActions = class
  public
    class function SuppressLine(const AText: string; ALine: Integer; const ARuleId: string): TTextEdit; static;
    class function SuppressFile(const AText, ARuleId: string): TTextEdit; static;
    /// <summary>try/finally nach einer Create-Zuweisung in ALine mit Standard-Formatstil; parst AText selbst.
    /// False, wenn nicht passend.</summary>
    class function TryFinally(const AText: string; ALine: Integer; out AAction: TCodeAction): Boolean; overload;
      static;
    /// <summary>try/finally nach der Create-Zuweisung, die in ARange.StartPos.Line beginnt. Reicht ARange über
    /// die Anweisung hinaus, endet der try-Block mit der Auswahl, sonst mit dem umgebenden Block. Einrückung
    /// nach AStyle. False, wenn nicht passend.</summary>
    class function TryFinally(const AText: string; ATree: TSyntaxTree; const ARange: TTextRange;
      const AStyle: TFormatStyle; out AAction: TCodeAction): Boolean; overload; static;
    /// <summary>uses aufräumen (doppelte entfernen, mit ASort sortieren); False ohne Änderung.</summary>
    class function OrganizeImports(const AText: string; ASort: Boolean; out AAction: TCodeAction;
      AByNamespace: Boolean): Boolean; overload; static;
    /// <summary>Wie oben mit AByNamespace = False.</summary>
    class function OrganizeImports(const AText: string; ASort: Boolean; out AAction: TCodeAction): Boolean;
      overload; static;
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
    /// <summary>True, wenn AKind unter einer der angefragten Arten liegt (LSP "only"); leeres AOnly = alle.</summary>
    class function KindRequested(const AKind: string; const AOnly: TArray<string>): Boolean; static;
  end;

implementation

uses
  System.Math,
  System.StrUtils,
  System.RegularExpressions,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Editing.GuardFree,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Editing.StringLiterals,
  Atlas.Text.Lines,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TEditingCodeActionsText = (AddTryExceptFreeResult, AddTryFinallyWithFree, CleanUpUses, AddToUses,
    MoveToTheImplementationUses, RemoveAllUnusedUses, CopyAsPlainText, AsStringLiteral, RemoveUnusedUses, Remove,
    SwapAssignments);

const
  cTexts: array[TEditingCodeActionsText] of TAtlasText = (
    (De: 'try/except ergänzen (Result bei Fehler freigeben)'; En: 'Add try/except (free Result on error)'),
    (De: 'try/finally mit %s.Free ergänzen'; En: 'Add try/finally with %s.Free'),
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


/// <summary>Anweisung, die ein try-Block einschließen kann.</summary>
function IsStatement(AKind: TSyntaxKind): Boolean;
begin
  Result := AKind in [TSyntaxKind.Block, TSyntaxKind.AsmBlock, TSyntaxKind.AssignStatement,
    TSyntaxKind.CallStatement, TSyntaxKind.IfStatement, TSyntaxKind.CaseStatement, TSyntaxKind.ForStatement,
    TSyntaxKind.ForInStatement, TSyntaxKind.WhileStatement, TSyntaxKind.RepeatStatement, TSyntaxKind.WithStatement,
    TSyntaxKind.TryStatement, TSyntaxKind.RaiseStatement, TSyntaxKind.GotoStatement, TSyntaxKind.LabeledStatement,
    TSyntaxKind.InlineVar, TSyntaxKind.InlineConst, TSyntaxKind.EmptyStatement];
end;

/// <summary>Knoten mit einer Folge von Anweisungen, in der try/finally Platz hat.</summary>
function IsStatementList(AKind: TSyntaxKind): Boolean;
begin
  Result := AKind in [TSyntaxKind.Block, TSyntaxKind.TryStatement, TSyntaxKind.FinallyBlock,
    TSyntaxKind.ExceptBlock, TSyntaxKind.RepeatStatement, TSyntaxKind.CaseElse];
end;

/// <summary>Zuweisung oder Inline-Variable, die in Zeile ALine beginnt und direkt in einer Anweisungsfolge
/// steht.</summary>
function CreateStatementAt(ATree: TSyntaxTree; ALine: Integer): TSyntaxNode;
var
  mFound: TSyntaxNode;
begin
  mFound := nil;
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      if (mFound <> nil) or (ANode.StartPos.Line > ALine) or (ANode.EndPos.Line < ALine) then
      begin
        Exit(False);
      end;
      if (ANode.StartPos.Line = ALine) and (ANode.Kind in [TSyntaxKind.AssignStatement, TSyntaxKind.InlineVar]) and
        (ANode.Parent <> nil) and IsStatementList(ANode.Parent.Kind) then
      begin
        mFound := ANode;
        Exit(False);
      end;
      Result := True;
    end);
  Result := mFound;
end;

function IndexInParent(ANode: TSyntaxNode): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to ANode.Parent.ChildCount - 1 do
  begin
    if ANode.Parent[mIndex] = ANode then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

/// <summary>Leerraum und Zeilenumbrüche zu je einem Leerzeichen zusammengefasst.</summary>
function CollapseSpace(const AText: string): string;
var
  mIndex: Integer;
  mSpace: Boolean;
begin
  Result := '';
  mSpace := False;
  for mIndex := 1 to Length(AText) do
  begin
    if CharInSet(AText[mIndex], [' ', #9, #10, #13]) then
    begin
      mSpace := True;
    end
    else
    begin
      if mSpace and (Result <> '') then
      begin
        Result := Result + ' ';
      end;
      mSpace := False;
      Result := Result + AText[mIndex];
    end;
  end;
end;

function SourceOf(const AText: string; ANode: TSyntaxNode): string;
begin
  Result := Copy(AText, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
end;

/// <summary>Steht ANode allein auf seinen Zeilen: davor nur Leerraum, danach höchstens ";" und ein
/// //-Kommentar?</summary>
function OwnsLines(const ALines: TArray<string>; ANode: TSyntaxNode): Boolean;
var
  mAfter: string;
begin
  Result := False;
  if (ANode.StartPos.Line > High(ALines)) or (ANode.EndPos.Line > High(ALines)) then
  begin
    Exit;
  end;
  if Trim(Copy(ALines[ANode.StartPos.Line], 1, ANode.StartPos.Character)) <> '' then
  begin
    Exit;
  end;
  mAfter := Trim(Copy(ALines[ANode.EndPos.Line], ANode.EndPos.Character + 1, MaxInt));
  if StartsStr(';', mAfter) then
  begin
    mAfter := Trim(Copy(mAfter, 2, MaxInt));
  end;
  Result := (mAfter = '') or StartsStr('//', mAfter);
end;

/// <summary>Gibt die Anweisung AVariable frei (X.Free, X.DisposeOf, FreeAndNil(X))?</summary>
function IsRelease(const ASource, AVariable: string): Boolean;
var
  mEscaped: string;
begin
  mEscaped := TRegEx.Escape(AVariable);
  Result := TRegEx.IsMatch(ASource, '^\s*(' + mEscaped + '\s*\.\s*(Free|DisposeOf)|FreeAndNil\s*\(\s*' + mEscaped +
    '\s*\))\s*;?\s*$', [roIgnoreCase]);
end;

/// <summary>Freigegeben, zurückgegeben, zugewiesen oder an eine Liste übergeben: Dann gehört das Objekt nicht
/// in ein finally.</summary>
function EscapesOrFrees(const ASource, AVariable: string): Boolean;
var
  mEscaped: string;
begin
  mEscaped := TRegEx.Escape(AVariable);
  Result := TRegEx.IsMatch(ASource, '\b' + mEscaped + '\s*\.\s*(Free|DisposeOf|Destroy)\b', [roIgnoreCase]) or
    TRegEx.IsMatch(ASource, '\bFreeAndNil\s*\(\s*' + mEscaped + '\s*\)', [roIgnoreCase]) or
    TRegEx.IsMatch(ASource, ':=\s*' + mEscaped + '\s*[;)]', [roIgnoreCase]) or
    TRegEx.IsMatch(ASource, '\bExit\s*\(\s*' + mEscaped + '\s*\)', [roIgnoreCase]) or
    TRegEx.IsMatch(ASource, '\.\s*(Add|Insert|Push|Enqueue|AddObject|AddPair|AddOrSetValue)\s*\(([^;]*[^\w.])?' +
      mEscaped + '\s*[,)]', [roIgnoreCase]);
end;

function IndentUnit(const AStyle: TFormatStyle): string;
begin
  if AStyle.UseTabs then
  begin
    Exit(#9);
  end;
  if AStyle.IndentSize > 0 then
  begin
    Result := StringOfChar(' ', AStyle.IndentSize);
  end
  else
  begin
    Result := '  ';
  end;
end;

{ TCodeActions }

class function TCodeActions.SuppressLine(const AText: string; ALine: Integer; const ARuleId: string): TTextEdit;
var
  mLines: TArray<string>;
  mAbove, mLine: string;
begin
  mLines := TTextLines.SplitLines(AText);
  if (ALine > 0) and (ALine <= High(mLines)) then
  begin
    mAbove := mLines[ALine - 1];
    if StartsText('// lsp-ignore:', TrimLeft(mAbove)) then
    begin
      Exit(TTextEdit.Create(TTextRange.Create(ALine - 1, Length(mAbove), ALine - 1, Length(mAbove)), ', ' + ARuleId));
    end;
  end;
  if (ALine >= 0) and (ALine <= High(mLines)) then
  begin
    mLine := mLines[ALine];
  end
  else
  begin
    mLine := '';
  end;
  Result := TTextEdit.Create(TTextRange.Create(ALine, 0, ALine, 0),
    TTextLines.IndentOf(mLine) + '// lsp-ignore: ' + ARuleId + TTextLines.LineBreakOf(AText));
end;

class function TCodeActions.SuppressFile(const AText, ARuleId: string): TTextEdit;
begin
  Result := TTextEdit.Create(TTextRange.Create(0, 0, 0, 0),
    '// lsp-ignore-file: ' + ARuleId + TTextLines.LineBreakOf(AText));
end;

class function TCodeActions.TryFinally(const AText: string; ALine: Integer; out AAction: TCodeAction): Boolean;
var
  mTree: TSyntaxTree;
begin
  mTree := TSyntaxTreeCache.Parse(AText);
  try
    Result := TryFinally(AText, mTree, TTextRange.Create(ALine, 0, ALine, 0), TFormatStyle.Default, AAction);
  finally
    mTree.Free;
  end;
end;

const
  // Leerraum ist zusammengefasst; leere Alternativen halten jede Gruppe belegt.
  cCreatePattern = '^(var |)(\w+) ?(:|)([^:=]*):= ?([A-Za-z_][\w.]*)(<[^;()]*>|) ?\. ?Create\w* ?(\(.*\)|) ?;?$';

type
  /// <summary>Plant "try/finally ergänzen" für eine Create-Zuweisung: Anweisung, eingeschlossener Teil und
  /// Freigabe.</summary>
  TTryFinallyPlan = class
  private
    FText: string;
    FTree: TSyntaxTree;
    FLines: TArray<string>;
    FStatement: TSyntaxNode;
    FParent: TSyntaxNode;
    FLast: TSyntaxNode;
    FReleaseNode: TSyntaxNode;
    FFirst: Integer;
    FTarget: string;
    FDeclaredType: string;
    FCreateArguments: string;
    FIsResult: Boolean;
    /// <summary>Zuweisung oder Inline-Variable in der ersten Zeile von ARange, allein auf ihren Zeilen, mit
    /// einfachem Namen als Ziel.</summary>
    function FindStatement(const ARange: TTextRange): Boolean;
    /// <summary>Liest Ziel, Typ und Argumente des Create-Aufrufs; False, wenn das Objekt nicht hierher gehört.
    /// </summary>
    function ReadCreate: Boolean;
    function FindDeclaredType: Boolean;
    /// <summary>Folgende Anweisungen bis zum Blockende bzw. bis zum Ende der Auswahl.</summary>
    function FindBlock(const ARange: TTextRange): Boolean;
    function SelectionEnd(const ARange: TTextRange): Integer;
    function LastEnclosed(ASelectionEnd: Integer): TSyntaxNode;
    /// <summary>Eine Freigabe als letzte Anweisung wandert ins finally; jede andere Freigabe oder Weitergabe
    /// verbietet die Aktion, auch hinter dem eingeschlossenen Teil.</summary>
    function CheckRelease: Boolean;
    /// <summary>Quelltext der folgenden Anweisungen ohne die Freigabe, je mit ";".</summary>
    function RestSource: string;
    function BodyEnd: Integer;
    function Body(const AStep, ALineBreak: string): string;
    function ReleaseText: string;
  public
    constructor Create(const AText: string; ATree: TSyntaxTree);
    /// <summary>True, wenn die Aktion zur Anweisung in ARange.StartPos.Line passt.</summary>
    function Applies(const ARange: TTextRange): Boolean;
    function Action(const AStyle: TFormatStyle): TCodeAction;
  end;

/// <summary>Ziel ist ein einfacher Name: Self.F und F[I] sind keine Zuweisung an eine lokale Variable.</summary>
function HasSimpleTarget(AStatement: TSyntaxNode): Boolean;
begin
  Result := (AStatement.Kind <> TSyntaxKind.AssignStatement) or
    ((AStatement.ChildCount >= 2) and (AStatement[0].Kind = TSyntaxKind.Identifier));
end;

constructor TTryFinallyPlan.Create(const AText: string; ATree: TSyntaxTree);
begin
  inherited Create;
  FText := AText;
  FTree := ATree;
  FLines := TTextLines.SplitLines(AText);
end;

function TTryFinallyPlan.FindStatement(const ARange: TTextRange): Boolean;
begin
  Result := (FTree <> nil) and (FTree.Root <> nil) and (ARange.StartPos.Line >= 0) and
    (ARange.StartPos.Line <= High(FLines));
  if Result then
  begin
    FStatement := CreateStatementAt(FTree, ARange.StartPos.Line);
    Result := (FStatement <> nil) and OwnsLines(FLines, FStatement) and HasSimpleTarget(FStatement);
  end;
end;

function TTryFinallyPlan.FindDeclaredType: Boolean;
begin
  // Feld, globale Variable oder Parameter: Wem das Objekt gehört, sieht man hier nicht.
  Result := (FStatement.Kind = TSyntaxKind.InlineVar) or FIsResult or
    TGuardFree.LocalVariableType(FTree, FText, FTarget, FStatement.StartPos.Line, FDeclaredType);
end;

function TTryFinallyPlan.ReadCreate: Boolean;
var
  mMatch: TMatch;
begin
  // Leerraum und Zeilenumbrüche zusammenfassen: Der Aufruf darf über mehrere Zeilen gehen.
  mMatch := TRegEx.Match(CollapseSpace(SourceOf(FText, FStatement)), cCreatePattern, [roIgnoreCase]);
  Result := mMatch.Success;
  if Result then
  begin
    FTarget := mMatch.Groups[2].Value;
    FCreateArguments := mMatch.Groups[7].Value;
    // Typ einer Inline-Variablen; bei Zuweisungen leer.
    FDeclaredType := Trim(mMatch.Groups[4].Value);
    FIsResult := SameText(FTarget, 'Result');
    // Interfaces zählen Referenzen; ein Owner gibt frei.
    Result := not SameText(FTarget, 'Self') and FindDeclaredType and
      not TRegEx.IsMatch(FDeclaredType, '^I[A-Z]') and
      not TRegEx.IsMatch(FCreateArguments, '^\( ?(Self|Application|Owner|AOwner) ?[,)]', [roIgnoreCase]);
  end;
end;

function TTryFinallyPlan.SelectionEnd(const ARange: TTextRange): Integer;
begin
  Result := ARange.EndPos.Line;
  if (Result > ARange.StartPos.Line) and (ARange.EndPos.Character = 0) then
  begin
    Dec(Result);
  end;
  if Result <= FStatement.EndPos.Line then
  begin
    Result := MaxInt;
  end;
end;

function TTryFinallyPlan.LastEnclosed(ASelectionEnd: Integer): TSyntaxNode;
var
  mIndex: Integer;
begin
  Result := nil;
  mIndex := FFirst;
  while (mIndex < FParent.ChildCount) and IsStatement(FParent[mIndex].Kind) and
    (FParent[mIndex].StartPos.Line <= ASelectionEnd) do
  begin
    if FParent[mIndex].Kind <> TSyntaxKind.EmptyStatement then
    begin
      Result := FParent[mIndex];
    end;
    Inc(mIndex);
  end;
end;

function TTryFinallyPlan.FindBlock(const ARange: TTextRange): Boolean;
begin
  FParent := FStatement.Parent;
  FFirst := IndexInParent(FStatement) + 1;
  // Schon geschützt.
  Result := (FFirst >= FParent.ChildCount) or (FParent[FFirst].Kind <> TSyntaxKind.TryStatement);
  if Result then
  begin
    FLast := LastEnclosed(SelectionEnd(ARange));
    Result := (FLast <> nil) and OwnsLines(FLines, FLast) and
      (FParent[FFirst].StartPos.Line > FStatement.EndPos.Line);
  end;
end;

function TTryFinallyPlan.RestSource: string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := FFirst to FParent.ChildCount - 1 do
  begin
    if FParent[mIndex] <> FReleaseNode then
    begin
      Result := Result + SourceOf(FText, FParent[mIndex]) + ';' + #10;
    end;
  end;
end;

function TTryFinallyPlan.CheckRelease: Boolean;
begin
  FReleaseNode := nil;
  if not FIsResult and IsRelease(SourceOf(FText, FLast), FTarget) then
  begin
    FReleaseNode := FLast;
  end;
  Result := FIsResult or not EscapesOrFrees(RestSource, FTarget);
  // Nur die Freigabe: Der try-Block bliebe leer.
  Result := Result and (FReleaseNode <> FParent[FFirst]);
end;

function TTryFinallyPlan.Applies(const ARange: TTextRange): Boolean;
begin
  Result := FindStatement(ARange) and ReadCreate and FindBlock(ARange) and CheckRelease;
end;

function TTryFinallyPlan.BodyEnd: Integer;
begin
  Result := FLast.EndPos.Line;
  if FReleaseNode <> nil then
  begin
    Result := FReleaseNode.StartPos.Line - 1;
  end;
  while (Result > FStatement.EndPos.Line) and (Trim(FLines[Result]) = '') do
  begin
    Dec(Result);
  end;
end;

function TTryFinallyPlan.Body(const AStep, ALineBreak: string): string;
var
  mLine: Integer;
begin
  Result := '';
  for mLine := FStatement.EndPos.Line + 1 to BodyEnd do
  begin
    if Trim(FLines[mLine]) <> '' then
    begin
      Result := Result + AStep + FLines[mLine];
    end;
    Result := Result + ALineBreak;
  end;
end;

function TTryFinallyPlan.ReleaseText: string;
begin
  if FReleaseNode <> nil then
  begin
    Result := Trim(SourceOf(FText, FReleaseNode)) + ';';
  end
  else
  begin
    Result := FTarget + '.Free;';
  end;
end;

function TTryFinallyPlan.Action(const AStyle: TFormatStyle): TCodeAction;
var
  mIndent, mStep, mLineBreak, mBody: string;
begin
  Result := Default(TCodeAction);
  mIndent := TTextLines.IndentOf(FLines[FStatement.StartPos.Line]);
  mStep := IndentUnit(AStyle);
  mLineBreak := TTextLines.LineBreakOf(FText);
  mBody := Body(mStep, mLineBreak);
  Result.Kind := cRewriteKind;
  if FIsResult then
  begin
    Result.Title := cTexts[TEditingCodeActionsText.AddTryExceptFreeResult].Text;
    mBody := mBody + mIndent + 'except' + mLineBreak + mIndent + mStep + 'Result.Free;' + mLineBreak + mIndent +
      mStep + 'raise;';
  end
  else
  begin
    Result.Title := cTexts[TEditingCodeActionsText.AddTryFinallyWithFree].Fmt([FTarget]);
    mBody := mBody + mIndent + 'finally' + mLineBreak + mIndent + mStep + ReleaseText;
  end;
  Result.Edits := [TTextEdit.Create(TTextRange.Create(FStatement.EndPos.Line,
    Length(FLines[FStatement.EndPos.Line]), FLast.EndPos.Line, Length(FLines[FLast.EndPos.Line])),
    mLineBreak + mIndent + 'try' + mLineBreak + mBody + mLineBreak + mIndent + 'end;')];
end;

class function TCodeActions.TryFinally(const AText: string; ATree: TSyntaxTree; const ARange: TTextRange;
  const AStyle: TFormatStyle; out AAction: TCodeAction): Boolean;
var
  mPlan: TTryFinallyPlan;
begin
  AAction := Default(TCodeAction);
  mPlan := TTryFinallyPlan.Create(AText, ATree);
  try
    Result := mPlan.Applies(ARange);
    if Result then
    begin
      AAction := mPlan.Action(AStyle);
    end;
  finally
    mPlan.Free;
  end;
end;

class function TCodeActions.OrganizeImports(const AText: string; ASort: Boolean; out AAction: TCodeAction): Boolean;
begin
  Result := OrganizeImports(AText, ASort, AAction, False);
end;

class function TCodeActions.OrganizeImports(const AText: string; ASort: Boolean; out AAction: TCodeAction;
  AByNamespace: Boolean): Boolean;
var
  mEdits: TArray<TTextEdit>;
begin
  AAction := Default(TCodeAction);
  Result := TUsesClauses.Organize(TPascalLexer.Tokenize(AText), AText, ASort, TTextLines.LineBreakOf(AText),
    mEdits, AByNamespace);
  if Result then
  begin
    AAction.Title := cTexts[TEditingCodeActionsText.CleanUpUses].Text;
    AAction.Kind := cOrganizeImportsKind;
    AAction.Edits := mEdits;
  end;
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
    procedure Add(const AAction: TCodeAction);
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
    if TUsesClauses.AddUnit(FTokens, OffsetNear(FTokens, FRange.StartPos), mUnitName, FLineBreak, mEdit) then
    begin
      Add(NewAction(cTexts[TEditingCodeActionsText.AddToUses].Fmt([mUnitName]), cQuickFixKind, [mEdit], ''));
    end;
  end;
end;

procedure TUsesActionList.AddMoveAll;
var
  mEdits: TArray<TTextEdit>;
begin
  FMovable := TUsesActions.MovableUnits(FTokens, FContext.Info);
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
  mUnits := TUsesActions.UnusedUnits(FTokens, FContext.Info, FContext.Keep);
  if TUsesActions.RemoveUnits(FTokens, FText, mUnits, FLineBreak, mEdits) then
  begin
    Add(NewAction(cTexts[TEditingCodeActionsText.RemoveUnusedUses].Fmt([string.Join(', ', mUnits)]), cRemoveUnusedKind,
      mEdits, ''));
  end;
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

procedure TUsesActionList.AddEntryActions;
var
  mEntries: TArray<TUsesEntry>;
  mEntry: TUsesEntry;
  mUnused: TArray<TTextRange>;
begin
  mEntries := TUsesActions.Entries(FTokens, FContext.Inactive, FContext.Info, FContext.Keep);
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

class function TCodeActions.KindRequested(const AKind: string; const AOnly: TArray<string>): Boolean;
var
  mOnly: string;
begin
  Result := AOnly = nil;
  // "source" umfasst "source.fixAll", aber nicht "sourceX".
  for mOnly in AOnly do
  begin
    if SameText(AKind, mOnly) or StartsText(mOnly + '.', AKind) then
    begin
      Result := True;
    end;
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
