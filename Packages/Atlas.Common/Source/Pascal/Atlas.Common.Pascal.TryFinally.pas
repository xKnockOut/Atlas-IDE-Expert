unit Atlas.Common.Pascal.TryFinally;

// "try/finally ergänzen" nach "X := T.Create(...);" mit passendem X.Free (#42);
// bei "Result := T.Create(...)" stattdessen try/except, das Result nur im
// Fehlerfall freigibt (das Objekt wird ja zurückgegeben). Die Entscheidung
// trifft der Syntaxbaum: nur lokale Variablen (auch "var X := …"), keine
// Felder und kein Self.F; der Aufruf darf über mehrere Zeilen gehen. Der
// try-Block schließt die folgenden Anweisungen bis zum Blockende ein, bei
// einer Auswahl bis zu deren Ende; steht dort schon "X.Free;", wandert es
// ins finally. Einrückung nach dem Formatstil (#43).

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.CodeActions.Contract;

type
  TPascalTryFinally = class
  public
    /// <summary>try/finally nach einer Create-Zuweisung in ALine mit Standard-Formatstil; parst AText selbst.
    /// False, wenn nicht passend.</summary>
    class function Offer(const AText: string; ALine: Integer; out AAction: TCodeAction): Boolean; overload;
      static;
    /// <summary>try/finally nach der Create-Zuweisung, die in ARange.StartPos.Line beginnt. Reicht ARange über
    /// die Anweisung hinaus, endet der try-Block mit der Auswahl, sonst mit dem umgebenden Block. Einrückung
    /// nach AStyle. False, wenn nicht passend.</summary>
    class function Offer(const AText: string; ATree: TSyntaxTree; const ARange: TTextRange;
      const AStyle: TFormatStyle; out AAction: TCodeAction): Boolean; overload; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.RegularExpressions,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Pascal.GuardFree,
  Atlas.Text.Lines,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TPascalTryFinallyText = (AddTryExceptFreeResult, AddTryFinallyWithFree);

const
  cTexts: array[TPascalTryFinallyText] of TAtlasText = (
    (De: 'try/except ergänzen (Result bei Fehler freigeben)'; En: 'Add try/except (free Result on error)'),
    (De: 'try/finally mit %s.Free ergänzen'; En: 'Add try/finally with %s.Free'));

{$SCOPEDENUMS OFF}

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

{ TTryFinallyPlan }

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

function TTryFinallyPlan.ReadCreate: Boolean;
var
  mMatch: TMatch;
begin
  // Leerraum und Zeilenumbrüche zusammenfassen: Der Aufruf darf über mehrere Zeilen gehen.
  mMatch := TRegEx.Match(TTextLines.CollapseSpace(SourceOf(FText, FStatement)), cCreatePattern, [roIgnoreCase]);
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

function TTryFinallyPlan.FindDeclaredType: Boolean;
begin
  // Feld, globale Variable oder Parameter: Wem das Objekt gehört, sieht man hier nicht.
  Result := (FStatement.Kind = TSyntaxKind.InlineVar) or FIsResult or
    TGuardFree.LocalVariableType(FTree, FText, FTarget, FStatement.StartPos.Line, FDeclaredType);
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

function TTryFinallyPlan.Applies(const ARange: TTextRange): Boolean;
begin
  Result := FindStatement(ARange) and ReadCreate and FindBlock(ARange) and CheckRelease;
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
    Result.Title := cTexts[TPascalTryFinallyText.AddTryExceptFreeResult].Text;
    mBody := mBody + mIndent + 'except' + mLineBreak + mIndent + mStep + 'Result.Free;' + mLineBreak + mIndent +
      mStep + 'raise;';
  end
  else
  begin
    Result.Title := cTexts[TPascalTryFinallyText.AddTryFinallyWithFree].Fmt([FTarget]);
    mBody := mBody + mIndent + 'finally' + mLineBreak + mIndent + mStep + ReleaseText;
  end;
  Result.Edits := [TTextEdit.Create(TTextRange.Create(FStatement.EndPos.Line,
    Length(FLines[FStatement.EndPos.Line]), FLast.EndPos.Line, Length(FLines[FLast.EndPos.Line])),
    mLineBreak + mIndent + 'try' + mLineBreak + mBody + mLineBreak + mIndent + 'end;')];
end;

class function TPascalTryFinally.Offer(const AText: string; ATree: TSyntaxTree; const ARange: TTextRange;
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

{ TPascalTryFinally }

class function TPascalTryFinally.Offer(const AText: string; ALine: Integer; out AAction: TCodeAction): Boolean;
var
  mTree: TSyntaxTree;
begin
  mTree := TSyntaxTreeCache.Parse(AText);
  try
    Result := Offer(AText, mTree, TTextRange.Create(ALine, 0, ALine, 0), TFormatStyle.Default, AAction);
  finally
    mTree.Free;
  end;
end;

end.
