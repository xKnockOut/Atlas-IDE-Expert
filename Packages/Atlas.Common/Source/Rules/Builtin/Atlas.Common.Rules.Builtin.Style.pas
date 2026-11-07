unit Atlas.Common.Rules.Builtin.Style;

// Stilregeln (#104), jede einzeln abschaltbar:
//   bool-compare             X = True / X = False bei Boolean (nicht LongBool, WordBool, ByteBool)
//   redundant-assigned-free  if Assigned(X) then X.Free; Free prüft selbst auf nil
//   raise-in-finally         raise in einem finally-Block überdeckt die laufende Ausnahme
//   redundant-parens         Klammern um die ganze Bedingung bzw. rechte Seite (Standard aus)
//   redundant-begin-end      begin/end um eine einzelne Anweisung (Standard aus)
//   with-statement           with verdeckt, zu welchem Objekt ein Bezeichner gehört (#94)
//   boolean-assign-if        if B then X := True else X := False bzw. if B then Exit(True); Exit(False);
//                            Korrektur X := B, X := not B bzw. Exit(B) (#935)
//   case-insensitive-compare UpperCase(A) = UpperCase(B), LowerCase(A) = 'x', A.ToUpper = B.ToUpper …;
//                            Korrektur SameText bzw. AnsiSameText (#936)
//   magic-number             Zahlenliteral in Anweisungen außerhalb von const, Typen und Array-Grenzen,
//                            nicht in der Option "allowed" (Standard aus, niedrige Konfidenz); Korrektur
//                            „Konstante einführen“ aus #50 (#937). Still bei Zahlen, die für sich sprechen: DPI-Basis
//                            96 in MulDiv, volle Bitmasken ($FF, $FFFF, $FFFFFFFF), Zeiteinheiten 24, 60, 1000, 3600
//                            in *, /, div, mod und Argumente von Aufrufen in einem Array-Literal, deren Argumente
//                            alle Zahlen sind (Punktlisten wie [P(3.5, 1.5), P(9.5, 1.5)])
//   line-length, public-field, global-variable und missing-begin-end stehen in Style.LineLength,
//                            Style.Declarations und Style.BeginEnd; RegisterStyleRules meldet auch sie an.
// Exit, Break und Continue aus einem finally-Block lehnt der Compiler selbst ab;
// dafür gibt es keine eigene Regel.

interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

type
  TBoolCompareRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TRedundantAssignedFreeRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TRaiseInFinallyRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TRedundantParensRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TRedundantBeginEndRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TWithStatementRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TBooleanAssignIfRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TCaseInsensitiveCompareRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TMagicNumberRule = class(TInterfacedObject, IRule)
  public const
    cDefaultAllowed: array[0..5] of Double = (0, 1, -1, 2, 10, 100);
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

/// <summary>Registriert die Stilregeln, auch die aus Style.LineLength, Style.Declarations und Style.BeginEnd.
/// </summary>
procedure RegisterStyleRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Math,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.DeclaredTypes,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.Extract,
  Atlas.Text.Lines,
  Atlas.Common.Rules.Options,
  Atlas.Common.Rules.Builtin.Style.Tokens,
  Atlas.Common.Rules.Builtin.Style.LineLength,
  Atlas.Common.Rules.Builtin.Style.Declarations,
  Atlas.Common.Rules.Builtin.Style.BeginEnd,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TStyleText = (BoolCompareTitle, AssignedFreeTitle, ToFreeAndNil, RemoveCheck, AssignedFree, RaiseFinallyTitle,
    RaiseFinally, ParensTitle, Parens, RemoveParens, BeginEndTitle, BeginEnd, RemoveBeginEnd, WithHides, IfBoolTitle,
    IfBool, CaseCompareTitle, CaseCompare, MagicTitle, IntroduceConstant, Magic, BoolCompare, ReplaceWith);

const
  cTexts: array[TStyleText] of TAtlasText = (
    (De: 'Vergleich mit True oder False'; En: 'Comparison with True or False'),
    (De: 'Assigned-Prüfung vor Free ist überflüssig'; En: 'Assigned check before Free is superfluous'),
    (De: 'Durch FreeAndNil ersetzen'; En: 'Replace with FreeAndNil'),
    (De: 'Prüfung entfernen'; En: 'Remove check'),
    (De: 'Free prüft selbst auf nil; Assigned davor ist überflüssig';
     En: 'Free checks for nil itself; Assigned before it is superfluous'),
    (De: 'raise in einem finally-Block'; En: 'raise in a finally block'),
    (De: 'raise im finally-Block überdeckt eine laufende Ausnahme';
     En: 'raise in the finally block hides a running exception'),
    (De: 'Überflüssige Klammern'; En: 'Superfluous parentheses'),
    (De: 'Die Klammern um den ganzen Ausdruck sind überflüssig';
     En: 'The parentheses around the whole expression are superfluous'),
    (De: 'Klammern entfernen'; En: 'Remove parentheses'),
    (De: 'begin/end um eine einzelne Anweisung'; En: 'begin/end around a single statement'),
    (De: 'begin/end um eine einzelne Anweisung ist überflüssig';
     En: 'begin/end around a single statement is superfluous'),
    (De: 'begin/end entfernen'; En: 'Remove begin/end'),
    (De: 'with verdeckt, zu welchem Objekt ein Bezeichner gehört; besser den Ausdruck ausschreiben';
     En: 'with hides which object an identifier belongs to; better write out the expression'),
    (De: 'if, das nur True oder False zuweist'; En: 'if that only assigns True or False'),
    (De: 'Das if weist nur True oder False zu.'; En: 'The if only assigns True or False.'),
    (De: 'Vergleich über UpperCase oder LowerCase'; En: 'Comparison via UpperCase or LowerCase'),
    (De: 'Vergleich über %s; %s vergleicht ohne Zwischenstrings.';
     En: 'Comparison via %s; %s compares without intermediate strings.'),
    (De: 'Zahl ohne Namen im Code'; En: 'Number without name in the code'),
    (De: 'Konstante einführen'; En: 'Introduce constant'),
    (De: 'Zahl %s ohne Namen; als Konstante wird klar, was sie bedeutet.';
     En: 'Number %s without name; as a constant it becomes clear what it means.'),
    (De: 'Vergleich mit %s ist überflüssig'; En: 'Comparison with %s is superfluous'),
    (De: 'Durch %s ersetzen'; En: 'Replace with %s'));

{$SCOPEDENUMS OFF}

/// <summary>Index der schließenden Klammer zu AOpen; -1 ohne.</summary>
function Closing(const ATokens: TTokens; AOpen: Integer): Integer;
var
  mDepth: Integer;
begin
  mDepth := 0;
  for Result := AOpen to High(ATokens) do
  begin
    if ATokens[Result].IsSymbol('(') or ATokens[Result].IsSymbol('[') then
    begin
      Inc(mDepth);
    end
    else if ATokens[Result].IsSymbol(')') or ATokens[Result].IsSymbol(']') then
    begin
      Dec(mDepth);
      if mDepth = 0 then
      begin
        Exit;
      end;
    end;
  end;
  Result := -1;
end;

function Before(const A, B: TTextPosition): Boolean;
begin
  Result := (A.Line < B.Line) or ((A.Line = B.Line) and (A.Character <= B.Character));
end;

/// <summary>Liegt APosition in einem begin … end?</summary>
function InStatements(ANode: TSyntaxNode; const APosition: TTextPosition): Boolean;
var
  mRoot: TSyntaxNode;
  mPosition: TTextPosition;
begin
  mRoot := ANode;
  mPosition := APosition;
  // Iterativ (Bericht M1): Der Weg zur Position kann durch lange Ausdrucksketten führen.
  Result := ANode.Search(
    function(AVisited: TSyntaxNode): TSyntaxSearchStep
    begin
      if AVisited = mRoot then
      begin
        Exit(TSyntaxSearchStep.Descend);
      end;
      if not (Before(AVisited.StartPos, mPosition) and Before(mPosition, AVisited.EndPos)) then
      begin
        Exit(TSyntaxSearchStep.Skip);
      end;
      if AVisited.Kind = TSyntaxKind.Block then
      begin
        Exit(TSyntaxSearchStep.Found);
      end;
      Result := TSyntaxSearchStep.Descend;
    end) <> nil;
end;

/// <summary>Text der Tokens AFirst..ALast ohne Kommentare, mit einem Leerzeichen wo im Quelltext Abstand war.</summary>
function TokenText(const ATokens: TTokens; AFirst, ALast: Integer): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := AFirst to ALast do
  begin
    if IsTrivia(ATokens[mIndex]) then
    begin
      Continue;
    end;
    if (Result <> '') and (mIndex > AFirst) and ((ATokens[mIndex].StartPos.Line <> ATokens[mIndex - 1].EndPos.Line) or
      (ATokens[mIndex].StartPos.Character > ATokens[mIndex - 1].EndPos.Character)) then
    begin
      Result := Result + ' ';
    end;
    Result := Result + ATokens[mIndex].Text;
  end;
end;

{ TBoolCompareRule }

function TBoolCompareRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('bool-compare', TRuleSeverity.Hint, cTexts[TStyleText.BoolCompareTitle].Text);
end;

type
  /// <summary>Vergleich mit True oder False: Token links und rechts des Operators, der Bezeichner und das Literal.
  /// </summary>
  TBoolCompare = record
    Left: Integer;
    Right: Integer;
    Name: Integer;
    Literal: Integer;
  end;

function IsBoolLiteral(const AToken: TPascalToken): Boolean;
begin
  Result := MatchText(AToken.Text, ['True', 'False']);
end;

/// <summary>Steht am Operator AIndex ein Bezeichner im Vergleich mit True oder False?</summary>
function BoolCompareAt(const ATokens: TTokens; AIndex: Integer; out ACompare: TBoolCompare): Boolean;
begin
  Result := False;
  ACompare := Default(TBoolCompare);
  ACompare.Left := PreviousCode(ATokens, AIndex);
  ACompare.Right := NextCode(ATokens, AIndex + 1);
  if (ACompare.Left < 0) or (ACompare.Right > High(ATokens)) then
  begin
    Exit;
  end;
  if IsBoolLiteral(ATokens[ACompare.Right]) then
  begin
    ACompare.Name := ACompare.Left;
    ACompare.Literal := ACompare.Right;
  end
  else if IsBoolLiteral(ATokens[ACompare.Left]) then
  begin
    ACompare.Name := ACompare.Right;
    ACompare.Literal := ACompare.Left;
  end
  else
  begin
    Exit;
  end;
  Result := (ATokens[ACompare.Name].Kind = TPascalTokenKind.Identifier) and not IsBoolLiteral(ATokens[ACompare.Name]);
end;

/// <summary>Token, hinter dem eine ganze Bedingung beginnt: if, while, until, (, :=, Komma.</summary>
function OpensCondition(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.IsKeyword('if') or AToken.IsKeyword('while') or AToken.IsKeyword('until');
  Result := Result or AToken.IsSymbol('(') or AToken.IsSymbol(':=') or AToken.IsSymbol(',');
end;

/// <summary>Token, vor dem eine ganze Bedingung endet: then, do, end, ), ;, Komma.</summary>
function ClosesCondition(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.IsKeyword('then') or AToken.IsKeyword('do') or AToken.IsKeyword('end');
  Result := Result or AToken.IsSymbol(')') or AToken.IsSymbol(';') or AToken.IsSymbol(',');
end;

/// <summary>Ist der Vergleich eine ganze Bedingung? Sonst bindet z. B. "A and X = True" anders, als es aussieht.
/// </summary>
function WholeCondition(const ATokens: TTokens; const ACompare: TBoolCompare): Boolean;
var
  mPrev, mNext: Integer;
begin
  mPrev := PreviousCode(ATokens, ACompare.Left);
  mNext := NextCode(ATokens, ACompare.Right + 1);
  Result := (mPrev >= 0) and (mNext <= High(ATokens));
  Result := Result and OpensCondition(ATokens[mPrev]) and ClosesCondition(ATokens[mNext]);
end;

procedure ReportBoolCompare(const ATokens: TTokens; AIndex: Integer; const ACompare: TBoolCompare;
  const AReport: IRuleReport);
var
  mNegate: Boolean;
  mText: string;
begin
  mNegate := SameText(ATokens[ACompare.Literal].Text, 'False') <> ATokens[AIndex].IsSymbol('<>');
  mText := IfThen(mNegate, 'not ', '') + ATokens[ACompare.Name].Text;
  AReport.Add(RangeOf(ATokens, ACompare.Left, ACompare.Right),
    cTexts[TStyleText.BoolCompare].Fmt([ATokens[ACompare.Literal].Text]),
    TRuleConfidence.High, [TRuleFix.Create(cTexts[TStyleText.ReplaceWith].Fmt([mText]),
    [TRuleEdit.Create(RangeOf(ATokens, ACompare.Left, ACompare.Right), mText)], True)]);
end;

procedure TBoolCompareRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TTokens;
  mTypes: TDeclaredTypes;
  mIndex: Integer;
  mCompare: TBoolCompare;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  mTokens := AContext.Tree.Tokens;
  mTypes := TDeclaredTypes.Create(AContext.Tree, AContext.Text);
  try
    for mIndex := 0 to High(mTokens) do
    begin
      if not (mTokens[mIndex].IsSymbol('=') or mTokens[mIndex].IsSymbol('<>')) then
      begin
        Continue;
      end;
      if not BoolCompareAt(mTokens, mIndex, mCompare) or not WholeCondition(mTokens, mCompare) then
      begin
        Continue;
      end;
      if InStatements(AContext.Tree.Root, mTokens[mIndex].StartPos) and
        SameText(mTypes.DeclaredType(mTokens[mCompare.Name].Text, mTokens[mCompare.Name].StartPos), 'Boolean') then
      begin
        ReportBoolCompare(mTokens, mIndex, mCompare, AReport);
      end;
    end;
  finally
    mTypes.Free;
  end;
end;

{ TRedundantAssignedFreeRule }

function TRedundantAssignedFreeRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('redundant-assigned-free', TRuleSeverity.Hint,
    cTexts[TStyleText.AssignedFreeTitle].Text);
end;

/// <summary>Passen die Tokens ab AAt zum Pfad APath (z. B. "Self.FListe")? AEnd: letztes Token.</summary>
function MatchesPath(const ATokens: TTokens; AAt: Integer; const APath: string; out AEnd: Integer): Boolean;
var
  mText: string;
begin
  mText := '';
  AEnd := AAt;
  while (AEnd <= High(ATokens)) and (Length(mText) < Length(APath)) do
  begin
    if not IsTrivia(ATokens[AEnd]) then
    begin
      mText := mText + ATokens[AEnd].Text;
    end;
    Inc(AEnd);
  end;
  Dec(AEnd);
  Result := SameText(mText, APath);
end;

type
  /// <summary>Gefundenes if Assigned(X) then …: Pfad X, letztes Token der Anweisung und die Korrektur.</summary>
  TAssignedFree = record
    Path: string;
    Last: Integer;
    Fix: string;
    Title: string;
  end;

/// <summary>Bezeichnerkette A.B.C zwischen AOpen und AClose; False bei anderem Inhalt.</summary>
function PathBetween(const ATokens: TTokens; AOpen, AClose: Integer; out APath: string): Boolean;
var
  mRun: Integer;
begin
  APath := '';
  Result := AClose > AOpen + 1;
  for mRun := AOpen + 1 to AClose - 1 do
  begin
    if IsTrivia(ATokens[mRun]) then
    begin
      Continue;
    end;
    if (ATokens[mRun].Kind = TPascalTokenKind.Identifier) or ATokens[mRun].IsSymbol('.') then
    begin
      APath := APath + ATokens[mRun].Text;
    end
    else
    begin
      Result := False;
    end;
  end;
end;

/// <summary>if Assigned(Pfad) then ab AIf; AThen: Index von then.</summary>
function AssignedCondition(const ATokens: TTokens; AIf: Integer; out APath: string; out AThen: Integer): Boolean;
var
  mAt, mOpen, mClose: Integer;
begin
  Result := False;
  APath := '';
  AThen := -1;
  mAt := NextCode(ATokens, AIf + 1);
  if (mAt > High(ATokens)) or not SameText(ATokens[mAt].Text, 'Assigned') then
  begin
    Exit;
  end;
  mOpen := NextCode(ATokens, mAt + 1);
  if (mOpen > High(ATokens)) or not ATokens[mOpen].IsSymbol('(') then
  begin
    Exit;
  end;
  mClose := Closing(ATokens, mOpen);
  if (mClose < 0) or not PathBetween(ATokens, mOpen, mClose, APath) then
  begin
    Exit;
  end;
  AThen := NextCode(ATokens, mClose + 1);
  Result := (AThen <= High(ATokens)) and ATokens[AThen].IsKeyword('then');
end;

/// <summary>begin X.Free; X := nil; end ab ABegin: Korrektur FreeAndNil(X).</summary>
function FreeAndNilBlock(const ATokens: TTokens; ABegin: Integer; var AFree: TAssignedFree): Boolean;
var
  mPathEnd, mLast: Integer;
begin
  Result := False;
  if not MatchesPath(ATokens, NextCode(ATokens, ABegin + 1), AFree.Path + '.Free;' + AFree.Path + ':=nil',
    mPathEnd) then
  begin
    Exit;
  end;
  mLast := NextCode(ATokens, mPathEnd + 1);
  if (mLast <= High(ATokens)) and ATokens[mLast].IsSymbol(';') then
  begin
    mLast := NextCode(ATokens, mLast + 1);
  end;
  if (mLast > High(ATokens)) or not ATokens[mLast].IsKeyword('end') then
  begin
    Exit;
  end;
  AFree.Last := mLast;
  AFree.Fix := 'FreeAndNil(' + AFree.Path + ')';
  AFree.Title := cTexts[TStyleText.ToFreeAndNil].Text;
  Result := True;
end;

/// <summary>X.Free ab AAt: Korrektur ohne die Prüfung.</summary>
function PlainFree(const ATokens: TTokens; AAt: Integer; var AFree: TAssignedFree): Boolean;
var
  mPathEnd: Integer;
begin
  Result := MatchesPath(ATokens, AAt, AFree.Path + '.Free', mPathEnd);
  if Result then
  begin
    AFree.Last := mPathEnd;
    AFree.Fix := AFree.Path + '.Free';
    AFree.Title := cTexts[TStyleText.RemoveCheck].Text;
  end;
end;

/// <summary>if Assigned(X) then X.Free bzw. then begin X.Free; X := nil; end ab AIf, ohne else dahinter.</summary>
function AssignedFreeAt(const ATokens: TTokens; AIf: Integer; out AFree: TAssignedFree): Boolean;
var
  mThen_, mAt, mNext: Integer;
begin
  AFree := Default(TAssignedFree);
  Result := AssignedCondition(ATokens, AIf, AFree.Path, mThen_);
  if not Result then
  begin
    Exit;
  end;
  mAt := NextCode(ATokens, mThen_ + 1);
  if mAt > High(ATokens) then
  begin
    Exit(False);
  end;
  if ATokens[mAt].IsKeyword('begin') then
  begin
    Result := FreeAndNilBlock(ATokens, mAt, AFree);
  end
  else
  begin
    Result := PlainFree(ATokens, mAt, AFree);
  end;
  // if … then X.Free else … nicht anfassen.
  mNext := NextCode(ATokens, AFree.Last + 1);
  Result := Result and not ((mNext <= High(ATokens)) and ATokens[mNext].IsKeyword('else'));
end;

procedure TRedundantAssignedFreeRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TTokens;
  mIndex: Integer;
  mFound: TAssignedFree;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  mTokens := AContext.Tree.Tokens;
  for mIndex := 0 to High(mTokens) do
  begin
    if mTokens[mIndex].IsKeyword('if') and AssignedFreeAt(mTokens, mIndex, mFound) then
    begin
      AReport.Add(RangeOf(mTokens, mIndex, mFound.Last), cTexts[TStyleText.AssignedFree].Text,
        TRuleConfidence.High, [TRuleFix.Create(mFound.Title, [TRuleEdit.Create(RangeOf(mTokens, mIndex, mFound.Last),
        mFound.Fix)], True)]);
    end;
  end;
end;

{ TRaiseInFinallyRule }

function TRaiseInFinallyRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('raise-in-finally', TRuleSeverity.Warning,
    cTexts[TStyleText.RaiseFinallyTitle].Text);
end;

type
  /// <summary>Eintrag von VisitFinally: Knoten und ob er in einem finally-Block liegt.</summary>
  TFinallyEntry = record
    Node: TSyntaxNode;
    InFinally: Boolean;
  end;

function FinallyEntry(ANode: TSyntaxNode; AInFinally: Boolean): TFinallyEntry;
begin
  Result.Node := ANode;
  Result.InFinally := AInFinally;
end;

procedure ReportRaise(ANode: TSyntaxNode; const AReport: IRuleReport);
begin
  AReport.Add(TTextRange.Create(ANode.StartPos, TTextPosition.Create(ANode.StartPos.Line,
    ANode.StartPos.Character + Length('raise'))), cTexts[TStyleText.RaiseFinally].Text,
    TRuleConfidence.High);
end;

function HasExceptBlock(ATry: TSyntaxNode): Boolean;
var
  mIndex: Integer;
begin
  for mIndex := 0 to ATry.ChildCount - 1 do
  begin
    if ATry[mIndex].Kind = TSyntaxKind.ExceptBlock then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Kinder eines try rückwärts auf den Stapel: finally-Block im finally, im try-Teil fängt ein eigenes except
/// die Ausnahme ab.</summary>
procedure PushTryChildren(APending: TStack<TFinallyEntry>; ATry: TSyntaxNode; AInFinally: Boolean);
var
  mIndex: Integer;
  mChild: TSyntaxNode;
  mHasExcept: Boolean;
begin
  mHasExcept := HasExceptBlock(ATry);
  for mIndex := ATry.ChildCount - 1 downto 0 do
  begin
    mChild := ATry[mIndex];
    if mChild.Kind = TSyntaxKind.FinallyBlock then
    begin
      APending.Push(FinallyEntry(mChild, True));
    end
    else if mChild.Kind = TSyntaxKind.ExceptBlock then
    begin
      APending.Push(FinallyEntry(mChild, AInFinally));
    end
    else
    begin
      APending.Push(FinallyEntry(mChild, AInFinally and not mHasExcept));
    end;
  end;
end;

procedure PushChildren(APending: TStack<TFinallyEntry>; ANode: TSyntaxNode; AInFinally: Boolean);
var
  mIndex: Integer;
begin
  for mIndex := ANode.ChildCount - 1 downto 0 do
  begin
    APending.Push(FinallyEntry(ANode[mIndex], AInFinally));
  end;
end;

procedure VisitFinally(ARoot: TSyntaxNode; const AReport: IRuleReport);
var
  mPending: TStack<TFinallyEntry>;
  mEntry: TFinallyEntry;
  mInFinally: Boolean;
begin
  // Iterativ (Bericht M1) mit eigenem Stapel; die Kinder rückwärts darauf, damit die Reihenfolge der Treffer die der
  // früheren Rekursion bleibt.
  mPending := TStack<TFinallyEntry>.Create;
  try
    mPending.Push(FinallyEntry(ARoot, False));
    while mPending.Count > 0 do
    begin
      mEntry := mPending.Pop;
      if mEntry.Node.Kind = TSyntaxKind.RaiseStatement then
      begin
        if mEntry.InFinally then
        begin
          ReportRaise(mEntry.Node, AReport);
        end;
        Continue;
      end;
      // Anonyme Methoden und eingebettete Routinen laufen später bzw. eigenständig.
      mInFinally := mEntry.InFinally and not (mEntry.Node.Kind in [TSyntaxKind.AnonymousMethod,
        TSyntaxKind.RoutineDecl]);
      if mEntry.Node.Kind = TSyntaxKind.TryStatement then
      begin
        PushTryChildren(mPending, mEntry.Node, mInFinally);
      end
      else
      begin
        PushChildren(mPending, mEntry.Node, mInFinally);
      end;
    end;
  finally
    mPending.Free;
  end;
end;

procedure TRaiseInFinallyRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  if (AContext.Tree <> nil) and (AContext.Tree.Root <> nil) then
  begin
    VisitFinally(AContext.Tree.Root, AReport);
  end;
end;

{ TRedundantParensRule }

function TRedundantParensRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('redundant-parens', TRuleSeverity.Hint, cTexts[TStyleText.ParensTitle].Text, True);
end;

/// <summary>Token, hinter dem ein ganzer Ausdruck folgt: if, while, until, case, :=.</summary>
function IsParensLead(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.IsKeyword('if') or AToken.IsKeyword('while') or AToken.IsKeyword('until');
  Result := Result or AToken.IsKeyword('case') or AToken.IsSymbol(':=');
end;

/// <summary>Token, vor dem eine Anweisung endet: ;, end, else, until, except, finally.</summary>
function EndsStatement(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.IsSymbol(';') or AToken.IsKeyword('end') or AToken.IsKeyword('else');
  Result := Result or AToken.IsKeyword('until') or AToken.IsKeyword('except') or AToken.IsKeyword('finally');
end;

/// <summary>Umfasst die Klammer, auf die AAfter folgt, den ganzen Ausdruck hinter ALead?</summary>
function ParensFit(const ALead, AAfter: TPascalToken): Boolean;
begin
  if ALead.IsKeyword('if') then
  begin
    Result := AAfter.IsKeyword('then');
  end
  else if ALead.IsKeyword('while') then
  begin
    Result := AAfter.IsKeyword('do');
  end
  else if ALead.IsKeyword('case') then
  begin
    Result := AAfter.IsKeyword('of');
  end
  else
  begin
    Result := EndsStatement(AAfter);
  end;
end;

/// <summary>Runde Klammer direkt hinter ALead um den ganzen Ausdruck; AOpen, AClose: ihre Token.</summary>
function WholeParens(const ATokens: TTokens; ALead: Integer; out AOpen, AClose: Integer): Boolean;
var
  mAfter: Integer;
begin
  Result := False;
  AClose := -1;
  AOpen := NextCode(ATokens, ALead + 1);
  if (AOpen > High(ATokens)) or not ATokens[AOpen].IsSymbol('(') then
  begin
    Exit;
  end;
  AClose := Closing(ATokens, AOpen);
  if (AClose < 0) or not ATokens[AClose].IsSymbol(')') then
  begin
    Exit;
  end;
  mAfter := NextCode(ATokens, AClose + 1);
  Result := (mAfter <= High(ATokens)) and ParensFit(ATokens[ALead], ATokens[mAfter]);
end;

procedure TRedundantParensRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TTokens;
  mIndex, mOpen, mClose: Integer;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  mTokens := AContext.Tree.Tokens;
  for mIndex := 0 to High(mTokens) do
  begin
    if not IsParensLead(mTokens[mIndex]) or not WholeParens(mTokens, mIndex, mOpen, mClose) or
      not InStatements(AContext.Tree.Root, mTokens[mOpen].StartPos) then
    begin
      Continue;
    end;
    AReport.Add(RangeOf(mTokens, mOpen, mClose), cTexts[TStyleText.Parens].Text,
      TRuleConfidence.High, [TRuleFix.Create(cTexts[TStyleText.RemoveParens].Text, [
      TRuleEdit.Create(RangeOf(mTokens, mOpen, mOpen), ''), TRuleEdit.Create(RangeOf(mTokens, mClose, mClose), '')],
      True)]);
  end;
end;

{ TRedundantBeginEndRule }

function TRedundantBeginEndRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('redundant-begin-end', TRuleSeverity.Hint,
    cTexts[TStyleText.BeginEndTitle].Text, True);
end;

/// <summary>Endet die Anweisung mit einem if ohne else (auch verschachtelt in for/while/with)?</summary>
function EndsWithOpenIf(ANode: TSyntaxNode): Boolean;
var
  mNode: TSyntaxNode;
begin
  // Iterativ (Bericht M1): am letzten Kind entlang, z. B. durch lange else-if-Ketten.
  Result := False;
  mNode := ANode;
  while mNode <> nil do
    case mNode.Kind of
      TSyntaxKind.IfStatement:
        if mNode.ChildCount < 3 then
        begin
          Result := True;
          mNode := nil;
        end
        else
        begin
          mNode := mNode[mNode.ChildCount - 1];
        end;
      TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement, TSyntaxKind.WhileStatement, TSyntaxKind.WithStatement:
        if mNode.ChildCount = 0 then
        begin
          mNode := nil;
        end
        else
        begin
          mNode := mNode[mNode.ChildCount - 1];
        end;
    else
      mNode := nil;
    end;
end;

function TokenIndexAt(const ATokens: TTokens; const APosition: TTextPosition): Integer;
begin
  for Result := 0 to High(ATokens) do
  begin
    if (ATokens[Result].StartPos.Line = APosition.Line) and
      (ATokens[Result].StartPos.Character = APosition.Character) then
    begin
      Exit;
    end;
  end;
  Result := -1;
end;

/// <summary>Knoten, deren Kinder Rümpfe sind (if, Schleifen, with, case-Zweige, except-Handler).</summary>
function HasBodies(ANode: TSyntaxNode): Boolean;
begin
  Result := ANode.Kind in [TSyntaxKind.IfStatement, TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement,
    TSyntaxKind.WhileStatement, TSyntaxKind.WithStatement, TSyntaxKind.CaseItem, TSyntaxKind.CaseElse,
    TSyntaxKind.ExceptionHandler];
end;

/// <summary>Ist das Kind AIndex von ANode ein Rumpf aus begin/end mit genau einer Anweisung, deren begin/end
/// wegfallen kann?</summary>
function SingleStatementBlock(ANode: TSyntaxNode; AIndex: Integer): Boolean;
var
  mChild: TSyntaxNode;
  mIsThenOfElse: Boolean;
begin
  mChild := ANode[AIndex];
  Result := (mChild.Kind = TSyntaxKind.Block) and (mChild.ChildCount = 1) and HasBodies(ANode);
  // Die Bedingung des if ist kein Rumpf.
  Result := Result and not ((ANode.Kind = TSyntaxKind.IfStatement) and (AIndex = 0));
  if not Result then
  begin
    Exit;
  end;
  // Dangling else: if A then begin if B then X; end else Y;
  mIsThenOfElse := (ANode.Kind = TSyntaxKind.IfStatement) and (AIndex = 1) and (ANode.ChildCount > 2);
  Result := not (mIsThenOfElse and EndsWithOpenIf(mChild[0]));
end;

/// <summary>Token, an dem ABlock endet (ab AFirst gesucht); High + 1 ohne.</summary>
function BlockEnd(const ATokens: TTokens; AFirst: Integer; ABlock: TSyntaxNode): Integer;
begin
  Result := AFirst;
  while (Result <= High(ATokens)) and ((ATokens[Result].EndPos.Line < ABlock.EndPos.Line) or
    ((ATokens[Result].EndPos.Line = ABlock.EndPos.Line) and (ATokens[Result].EndPos.Character <
    ABlock.EndPos.Character))) do
  begin
    Inc(Result);
  end;
end;

/// <summary>Letztes Token der Anweisung vor "end" (ALast), ohne ihr abschließendes Semikolon.</summary>
function BodyEnd(const ATokens: TTokens; ALast: Integer): Integer;
begin
  Result := PreviousCode(ATokens, ALast);
  if ATokens[Result].IsSymbol(';') then
  begin
    Result := PreviousCode(ATokens, Result);
  end;
end;

/// <summary>Meldet das Kind AIndex von ANode, wenn es begin/end um eine einzelne Anweisung ist.</summary>
procedure CheckBlock(ANode: TSyntaxNode; AIndex: Integer; const ATokens: TTokens; const AReport: IRuleReport);
var
  mChild: TSyntaxNode;
  mFirst, mLast, mBodyFirst, mBodyLast: Integer;
begin
  mChild := ANode[AIndex];
  mFirst := TokenIndexAt(ATokens, mChild.StartPos);
  if (mFirst < 0) or not ATokens[mFirst].IsKeyword('begin') then
  begin
    Exit;
  end;
  mLast := BlockEnd(ATokens, mFirst, mChild);
  if (mLast > High(ATokens)) or not ATokens[mLast].IsKeyword('end') then
  begin
    Exit;
  end;
  mBodyFirst := TokenIndexAt(ATokens, mChild[0].StartPos);
  if mBodyFirst < 0 then
  begin
    Exit;
  end;
  mBodyLast := BodyEnd(ATokens, mLast);
  if mBodyLast < mBodyFirst then
  begin
    Exit;
  end;
  AReport.Add(RangeOf(ATokens, mFirst, mFirst), cTexts[TStyleText.BeginEnd].Text,
    TRuleConfidence.High, [TRuleFix.Create(cTexts[TStyleText.RemoveBeginEnd].Text, [TRuleEdit.Create(RangeOf(ATokens,
      mFirst, mLast),
    TokenText(ATokens, mBodyFirst, mBodyLast))])]);
end;

/// <summary>Meldet begin/end um eine einzelne Anweisung unter den Kindern von ANode (nicht tiefer).</summary>
procedure CheckBlocks(ANode: TSyntaxNode; const ATokens: TTokens; const AReport: IRuleReport);
var
  mIndex: Integer;
begin
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    if SingleStatementBlock(ANode, mIndex) then
    begin
      CheckBlock(ANode, mIndex, ATokens, AReport);
    end;
  end;
end;

procedure TRedundantBeginEndRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TTokens;
  mReport: IRuleReport;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mTokens := AContext.Tree.Tokens;
  mReport := AReport;
  // Iterativ (Bericht M1): Jeder Knoten prüft seine Kinder; die Treffer sortiert die Engine nach Position.
  AContext.Tree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      CheckBlocks(ANode, mTokens, mReport);
      Result := True;
    end);
end;

{ TWithStatementRule }

function TWithStatementRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('with-statement', TRuleSeverity.Hint, 'with-Anweisung');
end;

procedure TWithStatementRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TTokens;
  mReport: IRuleReport;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mTokens := AContext.Tree.Tokens;
  mReport := AReport;
  // Iterativ (Bericht M1).
  AContext.Tree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    var
      Keyword: Integer;
    begin
      Result := True;
      if ANode.Kind <> TSyntaxKind.WithStatement then
      begin
        Exit;
      end;
      // Gemeldet wird das Schlüsselwort; die Aktion "with auflösen" liefert #50.
      Keyword := TokenIndexAt(mTokens, ANode.StartPos);
      if (Keyword >= 0) and mTokens[Keyword].IsKeyword('with') then
      begin
        mReport.Add(RangeOf(mTokens, Keyword, Keyword),
          cTexts[TStyleText.WithHides].Text,
          TRuleConfidence.High);
      end;
    end);
end;

{ TBooleanAssignIfRule }

function TBooleanAssignIfRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('boolean-assign-if', TRuleSeverity.Hint, cTexts[TStyleText.IfBoolTitle].Text);
end;

procedure TBooleanAssignIfRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TTokens;

  function Text(ANode: TSyntaxNode): string;
  begin
    Result := Trim(Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset));
  end;

  // Vergleichsschlüssel ohne Leerraum.
  function Key(ANode: TSyntaxNode): string;
  begin
    Result := LowerCase(StringReplace(StringReplace(Text(ANode), ' ', '', [rfReplaceAll]), #9, '', [rfReplaceAll]));
  end;

  // begin X end mit genau einer Anweisung: die Anweisung.
  function Single(ANode: TSyntaxNode): TSyntaxNode;
  begin
    Result := ANode;
    while (Result <> nil) and (Result.Kind = TSyntaxKind.Block) do
    begin
      if Result.ChildCount = 1 then
      begin
        Result := Result[0];
      end
      else
      begin
        Result := nil;
      end;
    end;
  end;

  // 1 für True, 0 für False, -1 sonst.
  function BoolValue(ANode: TSyntaxNode): Integer;
  begin
    Result := -1;
    if (ANode <> nil) and (ANode.Kind = TSyntaxKind.Identifier) then
    begin
      if SameText(ANode.Name, 'True') then
      begin
        Result := 1;
      end
      else if SameText(ANode.Name, 'False') then
      begin
        Result := 0;
      end;
    end;
  end;

  // X := True/False: Wert, Ziel in ATarget.
  function AssignedValue(ANode: TSyntaxNode; out ATarget: TSyntaxNode): Integer;
  begin
    Result := -1;
    ATarget := nil;
    if (ANode <> nil) and (ANode.Kind = TSyntaxKind.AssignStatement) and (ANode.ChildCount = 2) then
    begin
      ATarget := ANode[0];
      Result := BoolValue(ANode[1]);
    end;
  end;

  // Exit(True/False) als Anweisung.
  function ExitValue(ANode: TSyntaxNode): Integer;
  begin
    Result := -1;
    if (ANode = nil) or (ANode.Kind <> TSyntaxKind.CallStatement) or (ANode.ChildCount <> 1) then
    begin
      Exit;
    end;
    if (ANode[0].Kind = TSyntaxKind.Call) and SameText(ANode[0].Name, 'Exit') and (ANode[0].ChildCount = 2) then
    begin
      Result := BoolValue(ANode[0][1]);
    end;
  end;

  function Negated(ACondition: TSyntaxNode): string;
  begin
    if (ACondition.Kind = TSyntaxKind.UnaryExpr) and SameText(ACondition.Name, 'not') and
      (ACondition.ChildCount = 1) then
    begin
      Result := Text(ACondition[0]);
    end
    else if ACondition.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess, TSyntaxKind.Call,
      TSyntaxKind.IndexAccess, TSyntaxKind.ParenExpr] then
    begin
      Result := 'not ' + Text(ACondition);
    end
    else
    begin
      Result := 'not (' + Text(ACondition) + ')';
    end;
  end;

  function HasComment(AStart, AEnd: Integer): Boolean;
  var
    mIndex: Integer;
  begin
    // Binär zum ersten Token des Bereichs statt ab Dateianfang (#1323).
    mIndex := AContext.Tree.FirstTokenFrom(AStart);
    while (mIndex <= High(mTokens)) and (mTokens[mIndex].Offset < AEnd) do
    begin
      if mTokens[mIndex].Kind = TPascalTokenKind.Comment then
      begin
        Exit(True);
      end;
      Inc(mIndex);
    end;
    Result := False;
  end;

  procedure Report(AIf, ALast: TSyntaxNode; const ANewText: string);
  var
    mFixes: TArray<TRuleFix>;
  begin
    mFixes := nil;
    if not HasComment(AIf.StartOffset, ALast.EndOffset) then
    begin
      mFixes := [TRuleFix.Create(cTexts[TStyleText.ReplaceWith].Fmt([ANewText]),
        [TRuleEdit.Create(TTextRange.Create(AIf.StartPos,
        ALast.EndPos), ANewText)])];
    end;
    AReport.Add(TTextRange.Create(AIf.StartPos, AIf[0].EndPos), cTexts[TStyleText.IfBool].Text, TRuleConfidence.High,
      mFixes);
  end;

  function Expression(ACondition: TSyntaxNode; AValue: Integer): string;
  begin
    if AValue = 1 then
    begin
      Result := Text(ACondition);
    end
    else
    begin
      Result := Negated(ACondition);
    end;
  end;

  procedure CheckIf(AIf: TSyntaxNode; ANext: TSyntaxNode);
  var
    mThenTarget, mElseTarget: TSyntaxNode;
    mThenValue, mElseValue: Integer;
  begin
    if AIf.ChildCount < 2 then
    begin
      Exit;
    end;
    if AIf.ChildCount = 3 then
    begin
      // if B then X := True else X := False
      mThenValue := AssignedValue(Single(AIf[1]), mThenTarget);
      mElseValue := AssignedValue(Single(AIf[2]), mElseTarget);
      if (mThenValue >= 0) and (mElseValue >= 0) and (mThenValue <> mElseValue) and
        (Key(mThenTarget) = Key(mElseTarget)) then
      begin
        Report(AIf, AIf, Text(mThenTarget) + ' := ' + Expression(AIf[0], mThenValue));
        Exit;
      end;
      // if B then Exit(True) else Exit(False)
      mThenValue := ExitValue(Single(AIf[1]));
      mElseValue := ExitValue(Single(AIf[2]));
      if (mThenValue >= 0) and (mElseValue >= 0) and (mThenValue <> mElseValue) then
      begin
        Report(AIf, AIf, 'Exit(' + Expression(AIf[0], mThenValue) + ')');
      end;
      Exit;
    end;
    // if B then Exit(True); Exit(False);
    mThenValue := ExitValue(Single(AIf[1]));
    mElseValue := ExitValue(ANext);
    if (mThenValue >= 0) and (mElseValue >= 0) and (mThenValue <> mElseValue) then
    begin
      Report(AIf, ANext, 'Exit(' + Expression(AIf[0], mThenValue) + ')');
    end;
  end;

  procedure Visit(ANode: TSyntaxNode);
  var
    mParents: TStack<TSyntaxNode>;
    mIndexes: TStack<Integer>;
    mParent, mChild, mNext: TSyntaxNode;
    mIndex, mItem: Integer;
  begin
    // Iterativ (Bericht M1): Paare (Elternknoten, Kindindex), Reihenfolge wie die frühere Rekursion.
    mParents := TStack<TSyntaxNode>.Create;
    mIndexes := TStack<Integer>.Create;
    try
      for mItem := ANode.ChildCount - 1 downto 0 do
      begin
        mParents.Push(ANode);
        mIndexes.Push(mItem);
      end;
      while mParents.Count > 0 do
      begin
        mParent := mParents.Pop;
        mIndex := mIndexes.Pop;
        mChild := mParent[mIndex];
        if mChild.Kind = TSyntaxKind.IfStatement then
        begin
          mNext := nil;
          // Folgeanweisung nur in Anweisungslisten, nicht im else-Zweig eines äußeren if.
          if (mIndex < mParent.ChildCount - 1) and (mParent.Kind in [TSyntaxKind.Block, TSyntaxKind.TryStatement,
            TSyntaxKind.FinallyBlock, TSyntaxKind.ExceptBlock, TSyntaxKind.RepeatStatement]) then
          begin
            mNext := mParent[mIndex + 1];
          end;
          CheckIf(mChild, mNext);
        end;
        for mItem := mChild.ChildCount - 1 downto 0 do
        begin
          mParents.Push(mChild);
          mIndexes.Push(mItem);
        end;
      end;
    finally
      mIndexes.Free;
      mParents.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mTokens := AContext.Tree.Tokens;
  Visit(AContext.Tree.Root);
end;

{ TCaseInsensitiveCompareRule }

type
  /// <summary>Eine Seite des Vergleichs: UpperCase(X), X.ToLower …</summary>
  TCaseSide = record
    Argument: TSyntaxNode;
    Name: string;
    Upper: Boolean;
    Locale: Boolean;
  end;

function TCaseInsensitiveCompareRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('case-insensitive-compare', TRuleSeverity.Hint,
    cTexts[TStyleText.CaseCompareTitle].Text);
end;

procedure TCaseInsensitiveCompareRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);

  function Text(ANode: TSyntaxNode): string;
  begin
    Result := Trim(Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset));
  end;

  function Unwrapped(ANode: TSyntaxNode): TSyntaxNode;
  begin
    Result := ANode;
    while (Result.Kind = TSyntaxKind.ParenExpr) and (Result.ChildCount = 1) do
    begin
      Result := Result[0];
    end;
  end;

  function CaseSide(ANode: TSyntaxNode; out ASide: TCaseSide): Boolean;
  var
    mNode, mMember: TSyntaxNode;
  begin
    ASide := Default(TCaseSide);
    mNode := Unwrapped(ANode);
    // UpperCase(X), AnsiLowerCase(X), SysUtils.UpperCase(X)
    if (mNode.Kind = TSyntaxKind.Call) and (mNode.ChildCount = 2) and MatchText(mNode.Name, ['UpperCase', 'LowerCase',
      'AnsiUpperCase', 'AnsiLowerCase']) then
    begin
      ASide.Argument := mNode[1];
      ASide.Name := mNode[0].Name;
      ASide.Upper := ContainsText(mNode.Name, 'Upper');
      ASide.Locale := StartsText('Ansi', mNode.Name);
      Exit(True);
    end;
    // X.ToUpper, X.ToLower() – die Helfer arbeiten mit Unicode wie AnsiSameText.
    mMember := mNode;
    if (mMember.Kind = TSyntaxKind.Call) and (mMember.ChildCount = 1) then
    begin
      mMember := mMember[0];
    end;
    if (mMember.Kind = TSyntaxKind.MemberAccess) and (mMember.ChildCount = 1) and
      MatchText(mMember.Name, ['ToUpper', 'ToLower']) then
    begin
      ASide.Argument := mMember[0];
      ASide.Name := mMember.Name;
      ASide.Upper := SameText(mMember.Name, 'ToUpper');
      ASide.Locale := True;
      Exit(True);
    end;
    Result := False;
  end;

  // String-Literal, das die Umwandlung nicht ändert: 'ABC' bei UpperCase.
  function MatchingLiteral(ANode: TSyntaxNode; AUpper: Boolean): Boolean;
  var
    mNode: TSyntaxNode;
    mValue: string;
  begin
    mNode := Unwrapped(ANode);
    mValue := Text(mNode);
    Result := (mNode.Kind = TSyntaxKind.Literal) and StartsStr('''', mValue);
    if not Result then
    begin
      Exit;
    end;
    if AUpper then
    begin
      Result := AnsiUpperCase(mValue) = mValue;
    end
    else
    begin
      Result := AnsiLowerCase(mValue) = mValue;
    end;
  end;

  procedure CheckComparison(ANode: TSyntaxNode);
  var
    mLeft, mRight: TCaseSide;
    mHasLeft, mHasRight, mLocale: Boolean;
    mFirst, mSecond, mName, mSameName, mReplacement: string;
  begin
    if ANode.ChildCount <> 2 then
    begin
      Exit;
    end;
    mHasLeft := CaseSide(ANode[0], mLeft);
    mHasRight := CaseSide(ANode[1], mRight);
    if mHasLeft and mHasRight then
    begin
      // UpperCase(A) = LowerCase(B) ist ein anderer Fehler.
      if mLeft.Upper <> mRight.Upper then
      begin
        Exit;
      end;
      mFirst := Text(mLeft.Argument);
      mSecond := Text(mRight.Argument);
      mName := mLeft.Name;
      mLocale := mLeft.Locale or mRight.Locale;
    end
    else if mHasLeft and MatchingLiteral(ANode[1], mLeft.Upper) then
    begin
      mFirst := Text(mLeft.Argument);
      mSecond := Text(Unwrapped(ANode[1]));
      mName := mLeft.Name;
      mLocale := mLeft.Locale;
    end
    else if mHasRight and MatchingLiteral(ANode[0], mRight.Upper) then
    begin
      mFirst := Text(mRight.Argument);
      mSecond := Text(Unwrapped(ANode[0]));
      mName := mRight.Name;
      mLocale := mRight.Locale;
    end
    else
    begin
      Exit;
    end;
    if mLocale then
    begin
      mSameName := 'AnsiSameText';
    end
    else
    begin
      mSameName := 'SameText';
    end;
    mReplacement := mSameName + '(' + mFirst + ', ' + mSecond + ')';
    if ANode.Name = '<>' then
    begin
      mReplacement := 'not ' + mReplacement;
    end;
    AReport.Add(TTextRange.Create(ANode.StartPos, ANode.EndPos), cTexts[TStyleText.CaseCompare].Fmt([mName, mSameName]),
      TRuleConfidence.High,
      [TRuleFix.Create(cTexts[TStyleText.ReplaceWith].Fmt([mReplacement]),
        [TRuleEdit.Create(TTextRange.Create(ANode.StartPos,
      ANode.EndPos), mReplacement)])]);
  end;

  procedure Visit(ANode: TSyntaxNode);
  var
    mPending: TStack<TSyntaxNode>;
    mNode: TSyntaxNode;
    mIndex: Integer;
  begin
    // Iterativ (Bericht M1).
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ANode);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if (mNode.Kind = TSyntaxKind.BinaryExpr) and ((mNode.Name = '=') or (mNode.Name = '<>')) then
        begin
          CheckComparison(mNode);
        end;
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          mPending.Push(mNode[mIndex]);
        end;
      end;
    finally
      mPending.Free;
    end;
  end;

begin
  if (AContext.Tree <> nil) and (AContext.Tree.Root <> nil) then
  begin
    Visit(AContext.Tree.Root);
  end;
end;

{ TMagicNumberRule }

function TMagicNumberRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('magic-number', TRuleSeverity.Hint, cTexts[TStyleText.MagicTitle].Text, True);
end;

procedure TMagicNumberRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mAllowed: TArray<Double>;
  mSettings: TFormatSettings;

  function Text(ANode: TSyntaxNode): string;
  begin
    Result := Trim(Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset));
  end;

  // Wert eines Zahlenliterals (dezimal, $hex, Gleitkomma); False bei Strings und Zeichen (#13).
  function NumberValue(const ALiteral: string; out AValue: Double): Boolean;
  var
    mHex: Int64;
  begin
    Result := False;
    if ALiteral = '' then
    begin
      Exit;
    end;
    if ALiteral[1] = '$' then
    begin
      Result := TryStrToInt64(ALiteral, mHex);
      AValue := mHex;
    end
    else if CharInSet(ALiteral[1], ['0'..'9']) then
    begin
      Result := TryStrToFloat(ALiteral, AValue, mSettings);
    end;
  end;

  function IsAllowed(AValue: Double): Boolean;
  var
    mValue: Double;
  begin
    for mValue in mAllowed do
    begin
      if SameValue(mValue, AValue) then
      begin
        Exit(True);
      end;
    end;
    Result := False;
  end;

  // Zahl als Literal (auch negativ)?
  function IsNumberNode(ANode: TSyntaxNode): Boolean;
  var
    mValue: Double;
  begin
    if (ANode.Kind = TSyntaxKind.UnaryExpr) and (ANode.Name = '-') and (ANode.ChildCount = 1) then
    begin
      ANode := ANode[0];
    end;
    Result := (ANode.Kind = TSyntaxKind.Literal) and NumberValue(Text(ANode), mValue);
  end;

  // Element einer Punktliste: Aufruf in einem Array-Literal mit mindestens zwei Argumenten, die alle Zahlen sind
  // ([P(3.5, 1.5), P(9.5, 1.5)]). SetBounds(12, 9, 360, 23) allein zählt nicht: Pixelwerte brauchen Namen.
  function AllNumberArguments(ACall: TSyntaxNode): Boolean;
  var
    mIndex: Integer;
  begin
    Result := (ACall.ChildCount >= 3) and (ACall.Parent <> nil) and (ACall.Parent.Kind = TSyntaxKind.SetConstructor);
    for mIndex := 1 to ACall.ChildCount - 1 do
    begin
      Result := Result and IsNumberNode(ACall[mIndex]);
    end;
  end;

  // Zahlen, die für sich sprechen (siehe Kopf der Unit). SameValue nur mit Double-Werten: Mit einem
  // Ganzzahl-Argument wählt FPC die Single-Überladung, dann gälte 65536 als $FFFF.
  function SpeaksForItself(ANode: TSyntaxNode; AValue: Double): Boolean;
  const
    cFullMasks: array[0..2] of Double = (255, 65535, 4294967295);
    cTimeUnits: array[0..3] of Double = (24, 60, 1000, 3600);
    cDpiBase: Double = 96;
  var
    mParent: TSyntaxNode;

    function OneOf(const AValues: array of Double): Boolean;
    var
      mValue: Double;
    begin
      Result := False;
      for mValue in AValues do
      begin
        Result := Result or SameValue(AValue, mValue);
      end;
    end;

  begin
    if StartsText('$', Text(ANode)) and OneOf(cFullMasks) then
    begin
      Exit(True);
    end;
    mParent := ANode.Parent;
    if mParent = nil then
    begin
      Exit(False);
    end;
    if mParent.Kind = TSyntaxKind.Call then
    begin
      Result := (SameText(mParent.Name, 'MulDiv') and SameValue(AValue, cDpiBase)) or AllNumberArguments(mParent);
    end
    else
    begin
      Result := (mParent.Kind = TSyntaxKind.BinaryExpr) and MatchText(mParent.Name, ['*', '/', 'div', 'mod']) and
        OneOf(cTimeUnits);
    end;
  end;

  procedure CheckLiteral(ALiteral: TSyntaxNode);
  var
    mNode: TSyntaxNode;
    mValue: Double;
    mAction: TCodeAction;
    mFixes: TArray<TRuleFix>;
    mOptions: TExtractOptions;
  begin
    if not NumberValue(Text(ALiteral), mValue) then
    begin
      Exit;
    end;
    mNode := ALiteral;
    // -5: das Vorzeichen gehört zur Zahl.
    if (mNode.Parent <> nil) and (mNode.Parent.Kind = TSyntaxKind.UnaryExpr) and (mNode.Parent.Name = '-') and
      (mNode.Parent.ChildCount = 1) then
    begin
      mNode := mNode.Parent;
      mValue := -mValue;
    end;
    if IsAllowed(mValue) or SpeaksForItself(mNode, mValue) then
    begin
      Exit;
    end;
    mFixes := nil;
    mOptions := TExtractOptions.Default;
    // Name nach der Namensregel (cNewConstant), sonst meldet naming-prefix die Korrektur gleich wieder.
    mOptions.Names := AContext.NewNames;
    if TExtractRefactoring.ExtractConstant(AContext.Text, AContext.Tree,
      TTextRange.Create(mNode.StartPos, mNode.EndPos),
      mOptions, False, mAction) then
    begin
      mFixes := [TRuleFix.Create(cTexts[TStyleText.IntroduceConstant].Text, mAction.Edits)];
    end;
    AReport.Add(TTextRange.Create(mNode.StartPos, mNode.EndPos), cTexts[TStyleText.Magic].Fmt([Text(mNode)]),
      TRuleConfidence.Low, mFixes);
  end;

  procedure Visit(ANode: TSyntaxNode; AInBody: Boolean);
  var
    mPending: TStack<TSyntaxNode>;
    mInBodies: TStack<Boolean>;
    mNode: TSyntaxNode;
    mInBody: Boolean;
    mIndex: Integer;
  begin
    // Iterativ (Bericht M1); InBodies führt AInBody je Knoten mit.
    mPending := TStack<TSyntaxNode>.Create;
    mInBodies := TStack<Boolean>.Create;
    try
      mPending.Push(ANode);
      mInBodies.Push(AInBody);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        mInBody := mInBodies.Pop;
        case mNode.Kind of
          // Konstanten, Typen, Array-Grenzen und Teilbereiche haben ihren Namen schon.
          TSyntaxKind.ConstSection, TSyntaxKind.ConstDecl, TSyntaxKind.InlineConst, TSyntaxKind.TypeSection,
          TSyntaxKind.TypeDecl, TSyntaxKind.TypeReference, TSyntaxKind.ArrayType, TSyntaxKind.SubrangeType,
          TSyntaxKind.SetType, TSyntaxKind.EnumType, TSyntaxKind.VarSection, TSyntaxKind.Attribute,
          TSyntaxKind.AsmBlock, TSyntaxKind.RoutineHeader:
            Continue;
          TSyntaxKind.Block:
            mInBody := True;
          TSyntaxKind.Literal:
            if mInBody then
            begin
              CheckLiteral(mNode);
            end;
        else
          // Übrige Werte bewusst ohne Wirkung.
        end;
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          mPending.Push(mNode[mIndex]);
          mInBodies.Push(mInBody);
        end;
      end;
    finally
      mInBodies.Free;
      mPending.Free;
    end;
  end;

var
  mDefaults: TArray<Double>;
  Value: Double;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mDefaults := nil;
  for Value in cDefaultAllowed do
  begin
    mDefaults := mDefaults + [Value];
  end;
  mAllowed := TRuleOptions.Numbers(AContext.Options, 'allowed', mDefaults);
  mSettings := TFormatSettings.Invariant;
  Visit(AContext.Tree.Root, False);
end;

procedure RegisterStyleRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TBoolCompareRule.Create);
  ARegistry.Register(TRedundantAssignedFreeRule.Create);
  ARegistry.Register(TRaiseInFinallyRule.Create);
  ARegistry.Register(TRedundantParensRule.Create);
  ARegistry.Register(TRedundantBeginEndRule.Create);
  ARegistry.Register(TWithStatementRule.Create);
  ARegistry.Register(TBooleanAssignIfRule.Create);
  ARegistry.Register(TCaseInsensitiveCompareRule.Create);
  ARegistry.Register(TMagicNumberRule.Create);
  ARegistry.Register(TLineLengthRule.Create);
  ARegistry.Register(TPublicFieldRule.Create);
  ARegistry.Register(TGlobalVariableRule.Create);
  ARegistry.Register(TMissingBeginEndRule.Create);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Style', cTexts);

end.
