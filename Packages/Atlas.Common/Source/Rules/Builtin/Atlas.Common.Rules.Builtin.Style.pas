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
//                            „Konstante einführen“ aus #50 (#937)
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
    DefaultAllowed: array[0..5] of Double = (0, 1, -1, 2, 10, 100);
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
  Atlas.Common.Rules.Builtin.Style.BeginEnd;

/// <summary>Index der schließenden Klammer zu AOpen; -1 ohne.</summary>
function Closing(const ATokens: TTokens; AOpen: Integer): Integer;
var
  Depth: Integer;
begin
  Depth := 0;
  for Result := AOpen to High(ATokens) do
  begin
    if ATokens[Result].IsSymbol('(') or ATokens[Result].IsSymbol('[') then
    begin
      Inc(Depth);
    end
    else if ATokens[Result].IsSymbol(')') or ATokens[Result].IsSymbol(']') then
    begin
      Dec(Depth);
      if Depth = 0 then
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
  Root: TSyntaxNode;
  Position: TTextPosition;
begin
  Root := ANode;
  Position := APosition;
  // Iterativ (Bericht M1): Der Weg zur Position kann durch lange Ausdrucksketten führen.
  Result := ANode.Search(
    function(AVisited: TSyntaxNode): TSyntaxSearchStep
    begin
      if AVisited = Root then
      begin
        Exit(TSyntaxSearchStep.Descend);
      end;
      if not (Before(AVisited.StartPos, Position) and Before(Position, AVisited.EndPos)) then
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
  Index: Integer;
begin
  Result := '';
  for Index := AFirst to ALast do
  begin
    if IsTrivia(ATokens[Index]) then
    begin
      Continue;
    end;
    if (Result <> '') and (Index > AFirst) and ((ATokens[Index].StartPos.Line <> ATokens[Index - 1].EndPos.Line) or
      (ATokens[Index].StartPos.Character > ATokens[Index - 1].EndPos.Character)) then
    begin
      Result := Result + ' ';
    end;
    Result := Result + ATokens[Index].Text;
  end;
end;

{ TBoolCompareRule }

function TBoolCompareRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('bool-compare', TRuleSeverity.Hint, 'Vergleich mit True oder False');
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
  Prev, Next: Integer;
begin
  Prev := PreviousCode(ATokens, ACompare.Left);
  Next := NextCode(ATokens, ACompare.Right + 1);
  Result := (Prev >= 0) and (Next <= High(ATokens));
  Result := Result and OpensCondition(ATokens[Prev]) and ClosesCondition(ATokens[Next]);
end;

procedure ReportBoolCompare(const ATokens: TTokens; AIndex: Integer; const ACompare: TBoolCompare;
  const AReport: IRuleReport);
var
  Negate: Boolean;
  Text: string;
begin
  Negate := SameText(ATokens[ACompare.Literal].Text, 'False') <> ATokens[AIndex].IsSymbol('<>');
  Text := IfThen(Negate, 'not ', '') + ATokens[ACompare.Name].Text;
  AReport.Add(RangeOf(ATokens, ACompare.Left, ACompare.Right), 'Vergleich mit ' + ATokens[ACompare.Literal].Text +
    ' ist überflüssig', TRuleConfidence.High, [TRuleFix.Create('Durch ' + Text + ' ersetzen',
    [TRuleEdit.Create(RangeOf(ATokens, ACompare.Left, ACompare.Right), Text)], True)]);
end;

procedure TBoolCompareRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TTokens;
  Types: TDeclaredTypes;
  Index: Integer;
  Compare: TBoolCompare;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  Tokens := AContext.Tree.Tokens;
  Types := TDeclaredTypes.Create(AContext.Tree, AContext.Text);
  try
    for Index := 0 to High(Tokens) do
    begin
      if not (Tokens[Index].IsSymbol('=') or Tokens[Index].IsSymbol('<>')) then
      begin
        Continue;
      end;
      if not BoolCompareAt(Tokens, Index, Compare) or not WholeCondition(Tokens, Compare) then
      begin
        Continue;
      end;
      if InStatements(AContext.Tree.Root, Tokens[Index].StartPos) and
        SameText(Types.DeclaredType(Tokens[Compare.Name].Text, Tokens[Compare.Name].StartPos), 'Boolean') then
      begin
        ReportBoolCompare(Tokens, Index, Compare, AReport);
      end;
    end;
  finally
    Types.Free;
  end;
end;

{ TRedundantAssignedFreeRule }

function TRedundantAssignedFreeRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('redundant-assigned-free', TRuleSeverity.Hint,
    'Assigned-Prüfung vor Free ist überflüssig');
end;

/// <summary>Passen die Tokens ab AAt zum Pfad APath (z. B. "Self.FListe")? AEnd: letztes Token.</summary>
function MatchesPath(const ATokens: TTokens; AAt: Integer; const APath: string; out AEnd: Integer): Boolean;
var
  Text: string;
begin
  Text := '';
  AEnd := AAt;
  while (AEnd <= High(ATokens)) and (Length(Text) < Length(APath)) do
  begin
    if not IsTrivia(ATokens[AEnd]) then
    begin
      Text := Text + ATokens[AEnd].Text;
    end;
    Inc(AEnd);
  end;
  Dec(AEnd);
  Result := SameText(Text, APath);
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
  Run: Integer;
begin
  APath := '';
  Result := AClose > AOpen + 1;
  for Run := AOpen + 1 to AClose - 1 do
  begin
    if IsTrivia(ATokens[Run]) then
    begin
      Continue;
    end;
    if (ATokens[Run].Kind = TPascalTokenKind.Identifier) or ATokens[Run].IsSymbol('.') then
    begin
      APath := APath + ATokens[Run].Text;
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
  At, Open, Close: Integer;
begin
  Result := False;
  APath := '';
  AThen := -1;
  At := NextCode(ATokens, AIf + 1);
  if (At > High(ATokens)) or not SameText(ATokens[At].Text, 'Assigned') then
  begin
    Exit;
  end;
  Open := NextCode(ATokens, At + 1);
  if (Open > High(ATokens)) or not ATokens[Open].IsSymbol('(') then
  begin
    Exit;
  end;
  Close := Closing(ATokens, Open);
  if (Close < 0) or not PathBetween(ATokens, Open, Close, APath) then
  begin
    Exit;
  end;
  AThen := NextCode(ATokens, Close + 1);
  Result := (AThen <= High(ATokens)) and ATokens[AThen].IsKeyword('then');
end;

/// <summary>begin X.Free; X := nil; end ab ABegin: Korrektur FreeAndNil(X).</summary>
function FreeAndNilBlock(const ATokens: TTokens; ABegin: Integer; var AFree: TAssignedFree): Boolean;
var
  PathEnd, Last: Integer;
begin
  Result := False;
  if not MatchesPath(ATokens, NextCode(ATokens, ABegin + 1), AFree.Path + '.Free;' + AFree.Path + ':=nil',
    PathEnd) then
  begin
    Exit;
  end;
  Last := NextCode(ATokens, PathEnd + 1);
  if (Last <= High(ATokens)) and ATokens[Last].IsSymbol(';') then
  begin
    Last := NextCode(ATokens, Last + 1);
  end;
  if (Last > High(ATokens)) or not ATokens[Last].IsKeyword('end') then
  begin
    Exit;
  end;
  AFree.Last := Last;
  AFree.Fix := 'FreeAndNil(' + AFree.Path + ')';
  AFree.Title := 'Durch FreeAndNil ersetzen';
  Result := True;
end;

/// <summary>X.Free ab AAt: Korrektur ohne die Prüfung.</summary>
function PlainFree(const ATokens: TTokens; AAt: Integer; var AFree: TAssignedFree): Boolean;
var
  PathEnd: Integer;
begin
  Result := MatchesPath(ATokens, AAt, AFree.Path + '.Free', PathEnd);
  if Result then
  begin
    AFree.Last := PathEnd;
    AFree.Fix := AFree.Path + '.Free';
    AFree.Title := 'Prüfung entfernen';
  end;
end;

/// <summary>if Assigned(X) then X.Free bzw. then begin X.Free; X := nil; end ab AIf, ohne else dahinter.</summary>
function AssignedFreeAt(const ATokens: TTokens; AIf: Integer; out AFree: TAssignedFree): Boolean;
var
  Then_, At, Next: Integer;
begin
  AFree := Default(TAssignedFree);
  Result := AssignedCondition(ATokens, AIf, AFree.Path, Then_);
  if not Result then
  begin
    Exit;
  end;
  At := NextCode(ATokens, Then_ + 1);
  if At > High(ATokens) then
  begin
    Exit(False);
  end;
  if ATokens[At].IsKeyword('begin') then
  begin
    Result := FreeAndNilBlock(ATokens, At, AFree);
  end
  else
  begin
    Result := PlainFree(ATokens, At, AFree);
  end;
  // if … then X.Free else … nicht anfassen.
  Next := NextCode(ATokens, AFree.Last + 1);
  Result := Result and not ((Next <= High(ATokens)) and ATokens[Next].IsKeyword('else'));
end;

procedure TRedundantAssignedFreeRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TTokens;
  Index: Integer;
  Found: TAssignedFree;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  Tokens := AContext.Tree.Tokens;
  for Index := 0 to High(Tokens) do
  begin
    if Tokens[Index].IsKeyword('if') and AssignedFreeAt(Tokens, Index, Found) then
    begin
      AReport.Add(RangeOf(Tokens, Index, Found.Last), 'Free prüft selbst auf nil; Assigned davor ist überflüssig',
        TRuleConfidence.High, [TRuleFix.Create(Found.Title, [TRuleEdit.Create(RangeOf(Tokens, Index, Found.Last),
        Found.Fix)], True)]);
    end;
  end;
end;

{ TRaiseInFinallyRule }

function TRaiseInFinallyRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('raise-in-finally', TRuleSeverity.Warning, 'raise in einem finally-Block');
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
    ANode.StartPos.Character + Length('raise'))), 'raise im finally-Block überdeckt eine laufende Ausnahme',
    TRuleConfidence.High);
end;

function HasExceptBlock(ATry: TSyntaxNode): Boolean;
var
  Index: Integer;
begin
  for Index := 0 to ATry.ChildCount - 1 do
  begin
    if ATry[Index].Kind = TSyntaxKind.ExceptBlock then
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
  Index: Integer;
  Child: TSyntaxNode;
  HasExcept: Boolean;
begin
  HasExcept := HasExceptBlock(ATry);
  for Index := ATry.ChildCount - 1 downto 0 do
  begin
    Child := ATry[Index];
    if Child.Kind = TSyntaxKind.FinallyBlock then
    begin
      APending.Push(FinallyEntry(Child, True));
    end
    else if Child.Kind = TSyntaxKind.ExceptBlock then
    begin
      APending.Push(FinallyEntry(Child, AInFinally));
    end
    else
    begin
      APending.Push(FinallyEntry(Child, AInFinally and not HasExcept));
    end;
  end;
end;

procedure PushChildren(APending: TStack<TFinallyEntry>; ANode: TSyntaxNode; AInFinally: Boolean);
var
  Index: Integer;
begin
  for Index := ANode.ChildCount - 1 downto 0 do
  begin
    APending.Push(FinallyEntry(ANode[Index], AInFinally));
  end;
end;

procedure VisitFinally(ARoot: TSyntaxNode; const AReport: IRuleReport);
var
  Pending: TStack<TFinallyEntry>;
  Entry: TFinallyEntry;
  InFinally: Boolean;
begin
  // Iterativ (Bericht M1) mit eigenem Stapel; die Kinder rückwärts darauf, damit die Reihenfolge der Treffer die der
  // früheren Rekursion bleibt.
  Pending := TStack<TFinallyEntry>.Create;
  try
    Pending.Push(FinallyEntry(ARoot, False));
    while Pending.Count > 0 do
    begin
      Entry := Pending.Pop;
      if Entry.Node.Kind = TSyntaxKind.RaiseStatement then
      begin
        if Entry.InFinally then
        begin
          ReportRaise(Entry.Node, AReport);
        end;
        Continue;
      end;
      // Anonyme Methoden und eingebettete Routinen laufen später bzw. eigenständig.
      InFinally := Entry.InFinally and not (Entry.Node.Kind in [TSyntaxKind.AnonymousMethod, TSyntaxKind.RoutineDecl]);
      if Entry.Node.Kind = TSyntaxKind.TryStatement then
      begin
        PushTryChildren(Pending, Entry.Node, InFinally);
      end
      else
      begin
        PushChildren(Pending, Entry.Node, InFinally);
      end;
    end;
  finally
    Pending.Free;
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
  Result := TRuleDescriptor.Create('redundant-parens', TRuleSeverity.Hint, 'Überflüssige Klammern', True);
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
  After: Integer;
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
  After := NextCode(ATokens, AClose + 1);
  Result := (After <= High(ATokens)) and ParensFit(ATokens[ALead], ATokens[After]);
end;

procedure TRedundantParensRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TTokens;
  Index, Open, Close: Integer;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  Tokens := AContext.Tree.Tokens;
  for Index := 0 to High(Tokens) do
  begin
    if not IsParensLead(Tokens[Index]) or not WholeParens(Tokens, Index, Open, Close) or
      not InStatements(AContext.Tree.Root, Tokens[Open].StartPos) then
    begin
      Continue;
    end;
    AReport.Add(RangeOf(Tokens, Open, Close), 'Die Klammern um den ganzen Ausdruck sind überflüssig',
      TRuleConfidence.High, [TRuleFix.Create('Klammern entfernen', [
      TRuleEdit.Create(RangeOf(Tokens, Open, Open), ''), TRuleEdit.Create(RangeOf(Tokens, Close, Close), '')],
      True)]);
  end;
end;

{ TRedundantBeginEndRule }

function TRedundantBeginEndRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('redundant-begin-end', TRuleSeverity.Hint,
    'begin/end um eine einzelne Anweisung', True);
end;

/// <summary>Endet die Anweisung mit einem if ohne else (auch verschachtelt in for/while/with)?</summary>
function EndsWithOpenIf(ANode: TSyntaxNode): Boolean;
var
  Node: TSyntaxNode;
begin
  // Iterativ (Bericht M1): am letzten Kind entlang, z. B. durch lange else-if-Ketten.
  Result := False;
  Node := ANode;
  while Node <> nil do
    case Node.Kind of
      TSyntaxKind.IfStatement:
        if Node.ChildCount < 3 then
        begin
          Result := True;
          Node := nil;
        end
        else
        begin
          Node := Node[Node.ChildCount - 1];
        end;
      TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement, TSyntaxKind.WhileStatement, TSyntaxKind.WithStatement:
        if Node.ChildCount = 0 then
        begin
          Node := nil;
        end
        else
        begin
          Node := Node[Node.ChildCount - 1];
        end;
    else
      Node := nil;
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
  Child: TSyntaxNode;
  IsThenOfElse: Boolean;
begin
  Child := ANode[AIndex];
  Result := (Child.Kind = TSyntaxKind.Block) and (Child.ChildCount = 1) and HasBodies(ANode);
  // Die Bedingung des if ist kein Rumpf.
  Result := Result and not ((ANode.Kind = TSyntaxKind.IfStatement) and (AIndex = 0));
  if not Result then
  begin
    Exit;
  end;
  // Dangling else: if A then begin if B then X; end else Y;
  IsThenOfElse := (ANode.Kind = TSyntaxKind.IfStatement) and (AIndex = 1) and (ANode.ChildCount > 2);
  Result := not (IsThenOfElse and EndsWithOpenIf(Child[0]));
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
  Child: TSyntaxNode;
  First, Last, BodyFirst, BodyLast: Integer;
begin
  Child := ANode[AIndex];
  First := TokenIndexAt(ATokens, Child.StartPos);
  if (First < 0) or not ATokens[First].IsKeyword('begin') then
  begin
    Exit;
  end;
  Last := BlockEnd(ATokens, First, Child);
  if (Last > High(ATokens)) or not ATokens[Last].IsKeyword('end') then
  begin
    Exit;
  end;
  BodyFirst := TokenIndexAt(ATokens, Child[0].StartPos);
  if BodyFirst < 0 then
  begin
    Exit;
  end;
  BodyLast := BodyEnd(ATokens, Last);
  if BodyLast < BodyFirst then
  begin
    Exit;
  end;
  AReport.Add(RangeOf(ATokens, First, First), 'begin/end um eine einzelne Anweisung ist überflüssig',
    TRuleConfidence.High, [TRuleFix.Create('begin/end entfernen', [TRuleEdit.Create(RangeOf(ATokens, First, Last),
    TokenText(ATokens, BodyFirst, BodyLast))])]);
end;

/// <summary>Meldet begin/end um eine einzelne Anweisung unter den Kindern von ANode (nicht tiefer).</summary>
procedure CheckBlocks(ANode: TSyntaxNode; const ATokens: TTokens; const AReport: IRuleReport);
var
  Index: Integer;
begin
  for Index := 0 to ANode.ChildCount - 1 do
  begin
    if SingleStatementBlock(ANode, Index) then
    begin
      CheckBlock(ANode, Index, ATokens, AReport);
    end;
  end;
end;

procedure TRedundantBeginEndRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TTokens;
  Report: IRuleReport;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  Tokens := AContext.Tree.Tokens;
  Report := AReport;
  // Iterativ (Bericht M1): Jeder Knoten prüft seine Kinder; die Treffer sortiert die Engine nach Position.
  AContext.Tree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      CheckBlocks(ANode, Tokens, Report);
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
  Tokens: TTokens;
  Report: IRuleReport;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  Tokens := AContext.Tree.Tokens;
  Report := AReport;
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
      Keyword := TokenIndexAt(Tokens, ANode.StartPos);
      if (Keyword >= 0) and Tokens[Keyword].IsKeyword('with') then
      begin
        Report.Add(RangeOf(Tokens, Keyword, Keyword),
          'with verdeckt, zu welchem Objekt ein Bezeichner gehört; besser den Ausdruck ausschreiben',
          TRuleConfidence.High);
      end;
    end);
end;

{ TBooleanAssignIfRule }

function TBooleanAssignIfRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('boolean-assign-if', TRuleSeverity.Hint, 'if, das nur True oder False zuweist');
end;

procedure TBooleanAssignIfRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
const
  Message = 'Das if weist nur True oder False zu.';
var
  Tokens: TTokens;

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
    while (mIndex <= High(Tokens)) and (Tokens[mIndex].Offset < AEnd) do
    begin
      if Tokens[mIndex].Kind = TPascalTokenKind.Comment then
      begin
        Exit(True);
      end;
      Inc(mIndex);
    end;
    Result := False;
  end;

  procedure Report(AIf, ALast: TSyntaxNode; const ANewText: string);
  var
    Fixes: TArray<TRuleFix>;
  begin
    Fixes := nil;
    if not HasComment(AIf.StartOffset, ALast.EndOffset) then
    begin
      Fixes := [TRuleFix.Create('Durch ' + ANewText + ' ersetzen', [TRuleEdit.Create(TTextRange.Create(AIf.StartPos,
        ALast.EndPos), ANewText)])];
    end;
    AReport.Add(TTextRange.Create(AIf.StartPos, AIf[0].EndPos), Message, TRuleConfidence.High, Fixes);
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
    ThenTarget, ElseTarget: TSyntaxNode;
    ThenValue, ElseValue: Integer;
  begin
    if AIf.ChildCount < 2 then
    begin
      Exit;
    end;
    if AIf.ChildCount = 3 then
    begin
      // if B then X := True else X := False
      ThenValue := AssignedValue(Single(AIf[1]), ThenTarget);
      ElseValue := AssignedValue(Single(AIf[2]), ElseTarget);
      if (ThenValue >= 0) and (ElseValue >= 0) and (ThenValue <> ElseValue) and (Key(ThenTarget) = Key(ElseTarget)) then
      begin
        Report(AIf, AIf, Text(ThenTarget) + ' := ' + Expression(AIf[0], ThenValue));
        Exit;
      end;
      // if B then Exit(True) else Exit(False)
      ThenValue := ExitValue(Single(AIf[1]));
      ElseValue := ExitValue(Single(AIf[2]));
      if (ThenValue >= 0) and (ElseValue >= 0) and (ThenValue <> ElseValue) then
      begin
        Report(AIf, AIf, 'Exit(' + Expression(AIf[0], ThenValue) + ')');
      end;
      Exit;
    end;
    // if B then Exit(True); Exit(False);
    ThenValue := ExitValue(Single(AIf[1]));
    ElseValue := ExitValue(ANext);
    if (ThenValue >= 0) and (ElseValue >= 0) and (ThenValue <> ElseValue) then
    begin
      Report(AIf, ANext, 'Exit(' + Expression(AIf[0], ThenValue) + ')');
    end;
  end;

  procedure Visit(ANode: TSyntaxNode);
  var
    Parents: TStack<TSyntaxNode>;
    Indexes: TStack<Integer>;
    Parent, Child, Next: TSyntaxNode;
    Index, Item: Integer;
  begin
    // Iterativ (Bericht M1): Paare (Elternknoten, Kindindex), Reihenfolge wie die frühere Rekursion.
    Parents := TStack<TSyntaxNode>.Create;
    Indexes := TStack<Integer>.Create;
    try
      for Item := ANode.ChildCount - 1 downto 0 do
      begin
        Parents.Push(ANode);
        Indexes.Push(Item);
      end;
      while Parents.Count > 0 do
      begin
        Parent := Parents.Pop;
        Index := Indexes.Pop;
        Child := Parent[Index];
        if Child.Kind = TSyntaxKind.IfStatement then
        begin
          Next := nil;
          // Folgeanweisung nur in Anweisungslisten, nicht im else-Zweig eines äußeren if.
          if (Index < Parent.ChildCount - 1) and (Parent.Kind in [TSyntaxKind.Block, TSyntaxKind.TryStatement,
            TSyntaxKind.FinallyBlock, TSyntaxKind.ExceptBlock, TSyntaxKind.RepeatStatement]) then
          begin
            Next := Parent[Index + 1];
          end;
          CheckIf(Child, Next);
        end;
        for Item := Child.ChildCount - 1 downto 0 do
        begin
          Parents.Push(Child);
          Indexes.Push(Item);
        end;
      end;
    finally
      Indexes.Free;
      Parents.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  Tokens := AContext.Tree.Tokens;
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
    'Vergleich über UpperCase oder LowerCase');
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
    Node, Member: TSyntaxNode;
  begin
    ASide := Default(TCaseSide);
    Node := Unwrapped(ANode);
    // UpperCase(X), AnsiLowerCase(X), SysUtils.UpperCase(X)
    if (Node.Kind = TSyntaxKind.Call) and (Node.ChildCount = 2) and MatchText(Node.Name, ['UpperCase', 'LowerCase',
      'AnsiUpperCase', 'AnsiLowerCase']) then
    begin
      ASide.Argument := Node[1];
      ASide.Name := Node[0].Name;
      ASide.Upper := ContainsText(Node.Name, 'Upper');
      ASide.Locale := StartsText('Ansi', Node.Name);
      Exit(True);
    end;
    // X.ToUpper, X.ToLower() – die Helfer arbeiten mit Unicode wie AnsiSameText.
    Member := Node;
    if (Member.Kind = TSyntaxKind.Call) and (Member.ChildCount = 1) then
    begin
      Member := Member[0];
    end;
    if (Member.Kind = TSyntaxKind.MemberAccess) and (Member.ChildCount = 1) and
      MatchText(Member.Name, ['ToUpper', 'ToLower']) then
    begin
      ASide.Argument := Member[0];
      ASide.Name := Member.Name;
      ASide.Upper := SameText(Member.Name, 'ToUpper');
      ASide.Locale := True;
      Exit(True);
    end;
    Result := False;
  end;

  // String-Literal, das die Umwandlung nicht ändert: 'ABC' bei UpperCase.
  function MatchingLiteral(ANode: TSyntaxNode; AUpper: Boolean): Boolean;
  var
    Node: TSyntaxNode;
    Value: string;
  begin
    Node := Unwrapped(ANode);
    Value := Text(Node);
    Result := (Node.Kind = TSyntaxKind.Literal) and StartsStr('''', Value);
    if not Result then
    begin
      Exit;
    end;
    if AUpper then
    begin
      Result := AnsiUpperCase(Value) = Value;
    end
    else
    begin
      Result := AnsiLowerCase(Value) = Value;
    end;
  end;

  procedure CheckComparison(ANode: TSyntaxNode);
  var
    Left, Right: TCaseSide;
    HasLeft, HasRight, Locale: Boolean;
    First, Second, Name, SameName, Replacement: string;
  begin
    if ANode.ChildCount <> 2 then
    begin
      Exit;
    end;
    HasLeft := CaseSide(ANode[0], Left);
    HasRight := CaseSide(ANode[1], Right);
    if HasLeft and HasRight then
    begin
      // UpperCase(A) = LowerCase(B) ist ein anderer Fehler.
      if Left.Upper <> Right.Upper then
      begin
        Exit;
      end;
      First := Text(Left.Argument);
      Second := Text(Right.Argument);
      Name := Left.Name;
      Locale := Left.Locale or Right.Locale;
    end
    else if HasLeft and MatchingLiteral(ANode[1], Left.Upper) then
    begin
      First := Text(Left.Argument);
      Second := Text(Unwrapped(ANode[1]));
      Name := Left.Name;
      Locale := Left.Locale;
    end
    else if HasRight and MatchingLiteral(ANode[0], Right.Upper) then
    begin
      First := Text(Right.Argument);
      Second := Text(Unwrapped(ANode[0]));
      Name := Right.Name;
      Locale := Right.Locale;
    end
    else
    begin
      Exit;
    end;
    if Locale then
    begin
      SameName := 'AnsiSameText';
    end
    else
    begin
      SameName := 'SameText';
    end;
    Replacement := SameName + '(' + First + ', ' + Second + ')';
    if ANode.Name = '<>' then
    begin
      Replacement := 'not ' + Replacement;
    end;
    AReport.Add(TTextRange.Create(ANode.StartPos, ANode.EndPos), Format('Vergleich über %s; %s vergleicht ohne ' +
      'Zwischenstrings.', [Name, SameName]), TRuleConfidence.High,
      [TRuleFix.Create('Durch ' + Replacement + ' ersetzen', [TRuleEdit.Create(TTextRange.Create(ANode.StartPos,
      ANode.EndPos), Replacement)])]);
  end;

  procedure Visit(ANode: TSyntaxNode);
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Index: Integer;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if (Node.Kind = TSyntaxKind.BinaryExpr) and ((Node.Name = '=') or (Node.Name = '<>')) then
        begin
          CheckComparison(Node);
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
        end;
      end;
    finally
      Pending.Free;
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
  Result := TRuleDescriptor.Create('magic-number', TRuleSeverity.Hint, 'Zahl ohne Namen im Code', True);
end;

procedure TMagicNumberRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Allowed: TArray<Double>;
  Settings: TFormatSettings;

  function Text(ANode: TSyntaxNode): string;
  begin
    Result := Trim(Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset));
  end;

  // Wert eines Zahlenliterals (dezimal, $hex, Gleitkomma); False bei Strings und Zeichen (#13).
  function NumberValue(const ALiteral: string; out AValue: Double): Boolean;
  var
    Hex: Int64;
  begin
    Result := False;
    if ALiteral = '' then
    begin
      Exit;
    end;
    if ALiteral[1] = '$' then
    begin
      Result := TryStrToInt64(ALiteral, Hex);
      AValue := Hex;
    end
    else if CharInSet(ALiteral[1], ['0'..'9']) then
    begin
      Result := TryStrToFloat(ALiteral, AValue, Settings);
    end;
  end;

  function IsAllowed(AValue: Double): Boolean;
  var
    Value: Double;
  begin
    for Value in Allowed do
    begin
      if SameValue(Value, AValue) then
      begin
        Exit(True);
      end;
    end;
    Result := False;
  end;

  procedure CheckLiteral(ALiteral: TSyntaxNode);
  var
    Node: TSyntaxNode;
    Value: Double;
    Action: TCodeAction;
    Fixes: TArray<TRuleFix>;
    Options: TExtractOptions;
  begin
    if not NumberValue(Text(ALiteral), Value) then
    begin
      Exit;
    end;
    Node := ALiteral;
    // -5: das Vorzeichen gehört zur Zahl.
    if (Node.Parent <> nil) and (Node.Parent.Kind = TSyntaxKind.UnaryExpr) and (Node.Parent.Name = '-') and
      (Node.Parent.ChildCount = 1) then
    begin
      Node := Node.Parent;
      Value := -Value;
    end;
    if IsAllowed(Value) then
    begin
      Exit;
    end;
    Fixes := nil;
    Options := TExtractOptions.Default;
    // Name nach der Namensregel (cNewConstant), sonst meldet naming-prefix die Korrektur gleich wieder.
    Options.Names := AContext.NewNames;
    if TExtractRefactoring.ExtractConstant(AContext.Text, AContext.Tree, TTextRange.Create(Node.StartPos, Node.EndPos),
      Options, False, Action) then
    begin
      Fixes := [TRuleFix.Create('Konstante einführen', Action.Edits)];
    end;
    AReport.Add(TTextRange.Create(Node.StartPos, Node.EndPos), Format('Zahl %s ohne Namen; als Konstante wird klar, ' +
      'was sie bedeutet.', [Text(Node)]), TRuleConfidence.Low, Fixes);
  end;

  procedure Visit(ANode: TSyntaxNode; AInBody: Boolean);
  var
    Pending: TStack<TSyntaxNode>;
    InBodies: TStack<Boolean>;
    Node: TSyntaxNode;
    InBody: Boolean;
    Index: Integer;
  begin
    // Iterativ (Bericht M1); InBodies führt AInBody je Knoten mit.
    Pending := TStack<TSyntaxNode>.Create;
    InBodies := TStack<Boolean>.Create;
    try
      Pending.Push(ANode);
      InBodies.Push(AInBody);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        InBody := InBodies.Pop;
        case Node.Kind of
          // Konstanten, Typen, Array-Grenzen und Teilbereiche haben ihren Namen schon.
          TSyntaxKind.ConstSection, TSyntaxKind.ConstDecl, TSyntaxKind.InlineConst, TSyntaxKind.TypeSection,
          TSyntaxKind.TypeDecl, TSyntaxKind.TypeReference, TSyntaxKind.ArrayType, TSyntaxKind.SubrangeType,
          TSyntaxKind.SetType, TSyntaxKind.EnumType, TSyntaxKind.VarSection, TSyntaxKind.Attribute,
          TSyntaxKind.AsmBlock, TSyntaxKind.RoutineHeader:
            Continue;
          TSyntaxKind.Block:
            InBody := True;
          TSyntaxKind.Literal:
            if InBody then
            begin
              CheckLiteral(Node);
            end;
        else
          // Übrige Werte bewusst ohne Wirkung.
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
          InBodies.Push(InBody);
        end;
      end;
    finally
      InBodies.Free;
      Pending.Free;
    end;
  end;

var
  Defaults: TArray<Double>;
  Value: Double;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  Defaults := nil;
  for Value in DefaultAllowed do
  begin
    Defaults := Defaults + [Value];
  end;
  Allowed := TRuleOptions.Numbers(AContext.Options, 'allowed', Defaults);
  Settings := TFormatSettings.Invariant;
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

end.
