unit BDLsp.Common.Rules.Builtin.Style;

// Stilregeln (#104), jede einzeln abschaltbar:
//   bool-compare             X = True / X = False bei Boolean (nicht LongBool, WordBool, ByteBool)
//   redundant-assigned-free  if Assigned(X) then X.Free; Free prüft selbst auf nil
//   raise-in-finally         raise in einem finally-Block überdeckt die laufende Ausnahme
//   redundant-parens         Klammern um die ganze Bedingung bzw. rechte Seite (Standard aus)
//   redundant-begin-end      begin/end um eine einzelne Anweisung (Standard aus)
// Exit, Break und Continue aus einem finally-Block lehnt der Compiler selbst ab;
// dafür gibt es keine eigene Regel.

interface

uses
  BDLsp.Common.Rules.Contract,
  BDLsp.Common.Rules.Registry;

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

/// <summary>Registriert die Stilregeln.</summary>
procedure RegisterStyleRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  BDLsp.Common.Documents.Contract,
  BDLsp.Common.Configuration.Contract,
  BDLsp.Common.Pascal.Contract,
  BDLsp.Common.Pascal.SyntaxTree,
  BDLsp.Common.Rules.DeclaredTypes;

type
  TTokens = TArray<TPascalToken>;

function IsTrivia(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive];
end;

function NextCode(const ATokens: TTokens; AIndex: Integer): Integer;
begin
  Result := AIndex;
  while (Result <= High(ATokens)) and IsTrivia(ATokens[Result]) do
    Inc(Result);
end;

function PreviousCode(const ATokens: TTokens; AIndex: Integer): Integer;
begin
  Result := AIndex - 1;
  while (Result >= 0) and IsTrivia(ATokens[Result]) do
    Dec(Result);
end;

/// <summary>Index der schließenden Klammer zu AOpen; -1 ohne.</summary>
function Closing(const ATokens: TTokens; AOpen: Integer): Integer;
var
  Depth: Integer;
begin
  Depth := 0;
  for Result := AOpen to High(ATokens) do
    if ATokens[Result].IsSymbol('(') or ATokens[Result].IsSymbol('[') then
      Inc(Depth)
    else if ATokens[Result].IsSymbol(')') or ATokens[Result].IsSymbol(']') then
    begin
      Dec(Depth);
      if Depth = 0 then
        Exit;
    end;
  Result := -1;
end;

function RangeOf(const ATokens: TTokens; AFirst, ALast: Integer): TTextRange;
begin
  Result := TTextRange.Create(ATokens[AFirst].StartPos, ATokens[ALast].EndPos);
end;

function Before(const A, B: TTextPosition): Boolean;
begin
  Result := (A.Line < B.Line) or ((A.Line = B.Line) and (A.Character <= B.Character));
end;

/// <summary>Liegt APosition in einem begin … end?</summary>
function InStatements(ANode: TSyntaxNode; const APosition: TTextPosition): Boolean;
var
  Index: Integer;
  Child: TSyntaxNode;
begin
  for Index := 0 to ANode.ChildCount - 1 do
  begin
    Child := ANode[Index];
    if not (Before(Child.StartPos, APosition) and Before(APosition, Child.EndPos)) then
      Continue;
    if Child.Kind = TSyntaxKind.Block then
      Exit(True);
    if InStatements(Child, APosition) then
      Exit(True);
  end;
  Result := False;
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
      Continue;
    if (Result <> '') and (Index > AFirst) and ((ATokens[Index].StartPos.Line <> ATokens[Index - 1].EndPos.Line) or
      (ATokens[Index].StartPos.Character > ATokens[Index - 1].EndPos.Character)) then
      Result := Result + ' ';
    Result := Result + ATokens[Index].Text;
  end;
end;

{ TBoolCompareRule }

function TBoolCompareRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('bool-compare', TRuleSeverity.Hint, 'Vergleich mit True oder False');
end;

procedure TBoolCompareRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TTokens;
  Types: TDeclaredTypes;
  Index, Left, Right, Prev, Next, Name, Literal: Integer;
  Negate: Boolean;
  Text: string;
begin
  if AContext.Tree = nil then
    Exit;
  Tokens := AContext.Tree.Tokens;
  Types := TDeclaredTypes.Create(AContext.Tree, AContext.Text);
  try
    for Index := 0 to High(Tokens) do
    begin
      if not (Tokens[Index].IsSymbol('=') or Tokens[Index].IsSymbol('<>')) then
        Continue;
      Left := PreviousCode(Tokens, Index);
      Right := NextCode(Tokens, Index + 1);
      if (Left < 0) or (Right > High(Tokens)) then
        Continue;
      if MatchText(Tokens[Right].Text, ['True', 'False']) then
      begin
        Name := Left;
        Literal := Right;
      end
      else if MatchText(Tokens[Left].Text, ['True', 'False']) then
      begin
        Name := Right;
        Literal := Left;
      end
      else
        Continue;
      if (Tokens[Name].Kind <> TPascalTokenKind.Identifier) or MatchText(Tokens[Name].Text, ['True', 'False']) then
        Continue;
      // Nur ganze Bedingungen: davor if/while/until/(/:=/, und danach then/do/)/;/,. Sonst bindet
      // z. B. "A and X = True" anders, als es aussieht.
      Prev := PreviousCode(Tokens, Left);
      Next := NextCode(Tokens, Right + 1);
      if (Prev < 0) or (Next > High(Tokens)) or
        not (Tokens[Prev].IsKeyword('if') or Tokens[Prev].IsKeyword('while') or Tokens[Prev].IsKeyword('until') or
        Tokens[Prev].IsSymbol('(') or Tokens[Prev].IsSymbol(':=') or Tokens[Prev].IsSymbol(',')) or
        not (Tokens[Next].IsKeyword('then') or Tokens[Next].IsKeyword('do') or Tokens[Next].IsSymbol(')') or
        Tokens[Next].IsSymbol(';') or Tokens[Next].IsSymbol(',') or Tokens[Next].IsKeyword('end')) then
        Continue;
      if not InStatements(AContext.Tree.Root, Tokens[Index].StartPos) or
        not SameText(Types.DeclaredType(Tokens[Name].Text, Tokens[Name].StartPos), 'Boolean') then
        Continue;
      Negate := SameText(Tokens[Literal].Text, 'False') <> Tokens[Index].IsSymbol('<>');
      Text := IfThen(Negate, 'not ', '') + Tokens[Name].Text;
      AReport.Add(RangeOf(Tokens, Left, Right), 'Vergleich mit ' + Tokens[Literal].Text + ' ist überflüssig',
        TRuleConfidence.High, [TRuleFix.Create('Durch ' + Text + ' ersetzen',
        [TRuleEdit.Create(RangeOf(Tokens, Left, Right), Text)], True)]);
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
      Text := Text + ATokens[AEnd].Text;
    Inc(AEnd);
  end;
  Dec(AEnd);
  Result := SameText(Text, APath);
end;

procedure TRedundantAssignedFreeRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TTokens;
  Index, Open, Close, Then_, At, PathEnd, Last, Next: Integer;
  Path, Fix, Title: string;
  Run: Integer;
  PathOk: Boolean;
begin
  if AContext.Tree = nil then
    Exit;
  Tokens := AContext.Tree.Tokens;
  for Index := 0 to High(Tokens) do
  begin
    if not Tokens[Index].IsKeyword('if') then
      Continue;
    At := NextCode(Tokens, Index + 1);
    if (At > High(Tokens)) or not SameText(Tokens[At].Text, 'Assigned') then
      Continue;
    Open := NextCode(Tokens, At + 1);
    if (Open > High(Tokens)) or not Tokens[Open].IsSymbol('(') then
      Continue;
    Close := Closing(Tokens, Open);
    if Close < 0 then
      Continue;
    // Nur Bezeichnerketten A.B.C in Assigned(…).
    Path := '';
    PathOk := Close > Open + 1;
    for Run := Open + 1 to Close - 1 do
      if IsTrivia(Tokens[Run]) then
        Continue
      else if (Tokens[Run].Kind = TPascalTokenKind.Identifier) or Tokens[Run].IsSymbol('.') then
        Path := Path + Tokens[Run].Text
      else
        PathOk := False;
    Then_ := NextCode(Tokens, Close + 1);
    if not PathOk or (Then_ > High(Tokens)) or not Tokens[Then_].IsKeyword('then') then
      Continue;
    At := NextCode(Tokens, Then_ + 1);
    if At > High(Tokens) then
      Continue;
    if Tokens[At].IsKeyword('begin') then
    begin
      // begin X.Free; X := nil; end  →  FreeAndNil(X)
      if not MatchesPath(Tokens, NextCode(Tokens, At + 1), Path + '.Free;' + Path + ':=nil', PathEnd) then
        Continue;
      Last := NextCode(Tokens, PathEnd + 1);
      if (Last <= High(Tokens)) and Tokens[Last].IsSymbol(';') then
        Last := NextCode(Tokens, Last + 1);
      if (Last > High(Tokens)) or not Tokens[Last].IsKeyword('end') then
        Continue;
      Fix := 'FreeAndNil(' + Path + ')';
      Title := 'Durch FreeAndNil ersetzen';
    end
    else
    begin
      if not MatchesPath(Tokens, At, Path + '.Free', PathEnd) then
        Continue;
      Last := PathEnd;
      Fix := Path + '.Free';
      Title := 'Prüfung entfernen';
    end;
    // if … then X.Free else … nicht anfassen.
    Next := NextCode(Tokens, Last + 1);
    if (Next <= High(Tokens)) and Tokens[Next].IsKeyword('else') then
      Continue;
    AReport.Add(RangeOf(Tokens, Index, Last), 'Free prüft selbst auf nil; Assigned davor ist überflüssig',
      TRuleConfidence.High, [TRuleFix.Create(Title, [TRuleEdit.Create(RangeOf(Tokens, Index, Last), Fix)], True)]);
  end;
end;

{ TRaiseInFinallyRule }

function TRaiseInFinallyRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('raise-in-finally', TRuleSeverity.Warning, 'raise in einem finally-Block');
end;

procedure VisitFinally(ANode: TSyntaxNode; AInFinally: Boolean; const AReport: IRuleReport);
var
  Index: Integer;
  Child: TSyntaxNode;
  HasExcept: Boolean;
begin
  if ANode.Kind = TSyntaxKind.RaiseStatement then
  begin
    if AInFinally then
      AReport.Add(TTextRange.Create(ANode.StartPos, TTextPosition.Create(ANode.StartPos.Line,
        ANode.StartPos.Character + Length('raise'))), 'raise im finally-Block überdeckt eine laufende Ausnahme',
        TRuleConfidence.High);
    Exit;
  end;
  // Anonyme Methoden und eingebettete Routinen laufen später bzw. eigenständig.
  if ANode.Kind in [TSyntaxKind.AnonymousMethod, TSyntaxKind.RoutineDecl] then
    AInFinally := False;
  if ANode.Kind = TSyntaxKind.TryStatement then
  begin
    HasExcept := False;
    for Index := 0 to ANode.ChildCount - 1 do
      if ANode[Index].Kind = TSyntaxKind.ExceptBlock then
        HasExcept := True;
    for Index := 0 to ANode.ChildCount - 1 do
    begin
      Child := ANode[Index];
      if Child.Kind = TSyntaxKind.FinallyBlock then
        VisitFinally(Child, True, AReport)
      else if Child.Kind = TSyntaxKind.ExceptBlock then
        VisitFinally(Child, AInFinally, AReport)
      else
        // Im try-Teil fängt ein eigenes except die Ausnahme ab.
        VisitFinally(Child, AInFinally and not HasExcept, AReport);
    end;
    Exit;
  end;
  for Index := 0 to ANode.ChildCount - 1 do
    VisitFinally(ANode[Index], AInFinally, AReport);
end;

procedure TRaiseInFinallyRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  if (AContext.Tree <> nil) and (AContext.Tree.Root <> nil) then
    VisitFinally(AContext.Tree.Root, False, AReport);
end;

{ TRedundantParensRule }

function TRedundantParensRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('redundant-parens', TRuleSeverity.Hint, 'Überflüssige Klammern', True);
end;

procedure TRedundantParensRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TTokens;
  Index, Open, Close, After: Integer;
  Fits: Boolean;
begin
  if AContext.Tree = nil then
    Exit;
  Tokens := AContext.Tree.Tokens;
  for Index := 0 to High(Tokens) do
  begin
    if not (Tokens[Index].IsKeyword('if') or Tokens[Index].IsKeyword('while') or Tokens[Index].IsKeyword('until') or
      Tokens[Index].IsKeyword('case') or Tokens[Index].IsSymbol(':=')) then
      Continue;
    Open := NextCode(Tokens, Index + 1);
    if (Open > High(Tokens)) or not Tokens[Open].IsSymbol('(') then
      Continue;
    Close := Closing(Tokens, Open);
    if (Close < 0) or not Tokens[Close].IsSymbol(')') then
      Continue;
    After := NextCode(Tokens, Close + 1);
    if After > High(Tokens) then
      Continue;
    // Die Klammer muss den ganzen Ausdruck umfassen.
    if Tokens[Index].IsKeyword('if') then
      Fits := Tokens[After].IsKeyword('then')
    else if Tokens[Index].IsKeyword('while') then
      Fits := Tokens[After].IsKeyword('do')
    else if Tokens[Index].IsKeyword('case') then
      Fits := Tokens[After].IsKeyword('of')
    else
      Fits := Tokens[After].IsSymbol(';') or Tokens[After].IsKeyword('end') or Tokens[After].IsKeyword('else') or
        Tokens[After].IsKeyword('until') or Tokens[After].IsKeyword('except') or Tokens[After].IsKeyword('finally');
    if not Fits or not InStatements(AContext.Tree.Root, Tokens[Open].StartPos) then
      Continue;
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
begin
  case ANode.Kind of
    TSyntaxKind.IfStatement:
      Result := (ANode.ChildCount < 3) or EndsWithOpenIf(ANode[ANode.ChildCount - 1]);
    TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement, TSyntaxKind.WhileStatement, TSyntaxKind.WithStatement:
      Result := (ANode.ChildCount > 0) and EndsWithOpenIf(ANode[ANode.ChildCount - 1]);
  else
    Result := False;
  end;
end;

function TokenIndexAt(const ATokens: TTokens; const APosition: TTextPosition): Integer;
begin
  for Result := 0 to High(ATokens) do
    if (ATokens[Result].StartPos.Line = APosition.Line) and
      (ATokens[Result].StartPos.Character = APosition.Character) then
      Exit;
  Result := -1;
end;

procedure VisitBlocks(ANode: TSyntaxNode; const ATokens: TTokens; const AReport: IRuleReport);
var
  Index, First, Last, BodyFirst, BodyLast: Integer;
  Child, Statement: TSyntaxNode;
  IsThenOfElse: Boolean;
begin
  for Index := 0 to ANode.ChildCount - 1 do
  begin
    Child := ANode[Index];
    VisitBlocks(Child, ATokens, AReport);
    if (Child.Kind <> TSyntaxKind.Block) or (Child.ChildCount <> 1) or not (ANode.Kind in [TSyntaxKind.IfStatement,
      TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement, TSyntaxKind.WhileStatement, TSyntaxKind.WithStatement,
      TSyntaxKind.CaseItem, TSyntaxKind.CaseElse, TSyntaxKind.ExceptionHandler]) then
      Continue;
    // Die Bedingung des if ist kein Rumpf.
    if (ANode.Kind = TSyntaxKind.IfStatement) and (Index = 0) then
      Continue;
    Statement := Child[0];
    // Dangling else: if A then begin if B then X; end else Y;
    IsThenOfElse := (ANode.Kind = TSyntaxKind.IfStatement) and (Index = 1) and (ANode.ChildCount > 2);
    if IsThenOfElse and EndsWithOpenIf(Statement) then
      Continue;
    First := TokenIndexAt(ATokens, Child.StartPos);
    if (First < 0) or not ATokens[First].IsKeyword('begin') then
      Continue;
    Last := First;
    while (Last <= High(ATokens)) and ((ATokens[Last].EndPos.Line < Child.EndPos.Line) or
      ((ATokens[Last].EndPos.Line = Child.EndPos.Line) and (ATokens[Last].EndPos.Character < Child.EndPos.Character)))
      do
      Inc(Last);
    if (Last > High(ATokens)) or not ATokens[Last].IsKeyword('end') then
      Continue;
    BodyFirst := TokenIndexAt(ATokens, Statement.StartPos);
    if BodyFirst < 0 then
      Continue;
    // Bis vor "end", ohne das abschließende Semikolon der Anweisung.
    BodyLast := PreviousCode(ATokens, Last);
    if ATokens[BodyLast].IsSymbol(';') then
      BodyLast := PreviousCode(ATokens, BodyLast);
    if BodyLast < BodyFirst then
      Continue;
    AReport.Add(RangeOf(ATokens, First, First), 'begin/end um eine einzelne Anweisung ist überflüssig',
      TRuleConfidence.High, [TRuleFix.Create('begin/end entfernen', [TRuleEdit.Create(RangeOf(ATokens, First, Last),
      TokenText(ATokens, BodyFirst, BodyLast))])]);
  end;
end;

procedure TRedundantBeginEndRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  if (AContext.Tree <> nil) and (AContext.Tree.Root <> nil) then
    VisitBlocks(AContext.Tree.Root, AContext.Tree.Tokens, AReport);
end;

procedure RegisterStyleRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TBoolCompareRule.Create);
  ARegistry.Register(TRedundantAssignedFreeRule.Create);
  ARegistry.Register(TRaiseInFinallyRule.Create);
  ARegistry.Register(TRedundantParensRule.Create);
  ARegistry.Register(TRedundantBeginEndRule.Create);
end;

end.
