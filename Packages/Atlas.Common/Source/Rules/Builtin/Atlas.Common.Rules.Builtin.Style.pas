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
//   line-length              Zeile über der Grenze "max" (Vorgabe 120, Tabs nach format.indentSize), Strings
//                            und Kommentare abschaltbar ausgenommen (Standard aus); Korrektur bricht hinter
//                            Kommas bzw. vor Operatoren um. Über 1023 Zeichen immer Error wie F2069 (#938)
//   public-field             Feld im public- oder published-Abschnitt einer Klasse (Standard aus, #940);
//                            Records nur mit includeRecords. Der Abschnitt ohne Sichtbarkeitswort zählt nur
//                            bei Klassen ohne Vorfahren bzw. mit TObject: sonst stehen dort die Felder des
//                            Designers. Korrektur „Feld kapseln“: FName im private-Abschnitt am Ende der Klasse,
//                            dazu property Name read FName write FName (wie /encapsulate, #298)
//   global-variable          var bzw. threadvar im interface-Teil einer Unit (Standard aus, #941); die
//                            Formularvariable des Designers (frmHaupt: TfrmHaupt) nur mit
//                            includeFormVariables
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

/// <summary>Registriert die Stilregeln.</summary>
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

  TPublicFieldRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TGlobalVariableRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TLineLengthRule = class(TInterfacedObject, IRule)
  public const
    DefaultMax = 120;
    /// <summary>Längere Zeilen lehnt der Compiler ab (F2069).</summary>
    CompilerLimit = 1023;
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

procedure RegisterStyleRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Math,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.DeclaredTypes,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.Extract,
  Atlas.Common.Editing.Formatter.Layout,
  Atlas.Text.Lines,
  Atlas.Common.Rules.Options;

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

{ TWithStatementRule }

function TWithStatementRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('with-statement', TRuleSeverity.Hint, 'with-Anweisung');
end;

procedure VisitWith(ANode: TSyntaxNode; const ATokens: TTokens; const AReport: IRuleReport);
var
  Index, Keyword: Integer;
begin
  if ANode.Kind = TSyntaxKind.WithStatement then
  begin
    // Gemeldet wird das Schlüsselwort; die Aktion "with auflösen" liefert #50.
    Keyword := TokenIndexAt(ATokens, ANode.StartPos);
    if (Keyword >= 0) and ATokens[Keyword].IsKeyword('with') then
      AReport.Add(RangeOf(ATokens, Keyword, Keyword),
        'with verdeckt, zu welchem Objekt ein Bezeichner gehört; besser den Ausdruck ausschreiben',
        TRuleConfidence.High);
  end;
  for Index := 0 to ANode.ChildCount - 1 do
    VisitWith(ANode[Index], ATokens, AReport);
end;

procedure TWithStatementRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  if (AContext.Tree <> nil) and (AContext.Tree.Root <> nil) then
    VisitWith(AContext.Tree.Root, AContext.Tree.Tokens, AReport);
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
      if Result.ChildCount = 1 then
        Result := Result[0]
      else
        Result := nil;
  end;

  // 1 für True, 0 für False, -1 sonst.
  function BoolValue(ANode: TSyntaxNode): Integer;
  begin
    Result := -1;
    if (ANode <> nil) and (ANode.Kind = TSyntaxKind.Identifier) then
      if SameText(ANode.Name, 'True') then
        Result := 1
      else if SameText(ANode.Name, 'False') then
        Result := 0;
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
    if (ANode <> nil) and (ANode.Kind = TSyntaxKind.CallStatement) and (ANode.ChildCount = 1) and
      (ANode[0].Kind = TSyntaxKind.Call) and SameText(ANode[0].Name, 'Exit') and (ANode[0].ChildCount = 2) then
      Result := BoolValue(ANode[0][1]);
  end;

  function Negated(ACondition: TSyntaxNode): string;
  begin
    if (ACondition.Kind = TSyntaxKind.UnaryExpr) and SameText(ACondition.Name, 'not') and
      (ACondition.ChildCount = 1) then
      Result := Text(ACondition[0])
    else if ACondition.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess, TSyntaxKind.Call,
      TSyntaxKind.IndexAccess, TSyntaxKind.ParenExpr] then
      Result := 'not ' + Text(ACondition)
    else
      Result := 'not (' + Text(ACondition) + ')';
  end;

  function HasComment(AStart, AEnd: Integer): Boolean;
  var
    Token: TPascalToken;
  begin
    for Token in Tokens do
      if (Token.Offset >= AStart) and (Token.Offset < AEnd) and (Token.Kind = TPascalTokenKind.Comment) then
        Exit(True);
    Result := False;
  end;

  procedure Report(AIf, ALast: TSyntaxNode; const ANewText: string);
  var
    Fixes: TArray<TRuleFix>;
  begin
    Fixes := nil;
    if not HasComment(AIf.StartOffset, ALast.EndOffset) then
      Fixes := [TRuleFix.Create('Durch ' + ANewText + ' ersetzen', [TRuleEdit.Create(TTextRange.Create(AIf.StartPos,
        ALast.EndPos), ANewText)])];
    AReport.Add(TTextRange.Create(AIf.StartPos, AIf[0].EndPos), Message, TRuleConfidence.High, Fixes);
  end;

  function Expression(ACondition: TSyntaxNode; AValue: Integer): string;
  begin
    if AValue = 1 then
      Result := Text(ACondition)
    else
      Result := Negated(ACondition);
  end;

  procedure CheckIf(AIf: TSyntaxNode; ANext: TSyntaxNode);
  var
    ThenTarget, ElseTarget: TSyntaxNode;
    ThenValue, ElseValue: Integer;
  begin
    if AIf.ChildCount < 2 then
      Exit;
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
        Report(AIf, AIf, 'Exit(' + Expression(AIf[0], ThenValue) + ')');
      Exit;
    end;
    // if B then Exit(True); Exit(False);
    ThenValue := ExitValue(Single(AIf[1]));
    ElseValue := ExitValue(ANext);
    if (ThenValue >= 0) and (ElseValue >= 0) and (ThenValue <> ElseValue) then
      Report(AIf, ANext, 'Exit(' + Expression(AIf[0], ThenValue) + ')');
  end;

  procedure Visit(ANode: TSyntaxNode);
  var
    Index: Integer;
    Next: TSyntaxNode;
  begin
    for Index := 0 to ANode.ChildCount - 1 do
    begin
      if ANode[Index].Kind = TSyntaxKind.IfStatement then
      begin
        Next := nil;
        // Folgeanweisung nur in Anweisungslisten, nicht im else-Zweig eines äußeren if.
        if (Index < ANode.ChildCount - 1) and (ANode.Kind in [TSyntaxKind.Block, TSyntaxKind.TryStatement,
          TSyntaxKind.FinallyBlock, TSyntaxKind.ExceptBlock, TSyntaxKind.RepeatStatement]) then
          Next := ANode[Index + 1];
        CheckIf(ANode[Index], Next);
      end;
      Visit(ANode[Index]);
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
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
      Result := Result[0];
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
      Member := Member[0];
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
      Exit;
    if AUpper then
      Result := AnsiUpperCase(Value) = Value
    else
      Result := AnsiLowerCase(Value) = Value;
  end;

  procedure CheckComparison(ANode: TSyntaxNode);
  var
    Left, Right: TCaseSide;
    HasLeft, HasRight, Locale: Boolean;
    First, Second, Name, SameName, Replacement: string;
  begin
    if ANode.ChildCount <> 2 then
      Exit;
    HasLeft := CaseSide(ANode[0], Left);
    HasRight := CaseSide(ANode[1], Right);
    if HasLeft and HasRight then
    begin
      // UpperCase(A) = LowerCase(B) ist ein anderer Fehler.
      if Left.Upper <> Right.Upper then
        Exit;
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
      Exit;
    if Locale then
      SameName := 'AnsiSameText'
    else
      SameName := 'SameText';
    Replacement := SameName + '(' + First + ', ' + Second + ')';
    if ANode.Name = '<>' then
      Replacement := 'not ' + Replacement;
    AReport.Add(TTextRange.Create(ANode.StartPos, ANode.EndPos), Format('Vergleich über %s; %s vergleicht ohne ' +
      'Zwischenstrings.', [Name, SameName]), TRuleConfidence.High,
      [TRuleFix.Create('Durch ' + Replacement + ' ersetzen', [TRuleEdit.Create(TTextRange.Create(ANode.StartPos,
      ANode.EndPos), Replacement)])]);
  end;

  procedure Visit(ANode: TSyntaxNode);
  var
    Index: Integer;
  begin
    if (ANode.Kind = TSyntaxKind.BinaryExpr) and ((ANode.Name = '=') or (ANode.Name = '<>')) then
      CheckComparison(ANode);
    for Index := 0 to ANode.ChildCount - 1 do
      Visit(ANode[Index]);
  end;

begin
  if (AContext.Tree <> nil) and (AContext.Tree.Root <> nil) then
    Visit(AContext.Tree.Root);
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
      Exit;
    if ALiteral[1] = '$' then
    begin
      Result := TryStrToInt64(ALiteral, Hex);
      AValue := Hex;
    end
    else if CharInSet(ALiteral[1], ['0'..'9']) then
      Result := TryStrToFloat(ALiteral, AValue, Settings);
  end;

  function IsAllowed(AValue: Double): Boolean;
  var
    Value: Double;
  begin
    for Value in Allowed do
      if SameValue(Value, AValue) then
        Exit(True);
    Result := False;
  end;

  procedure CheckLiteral(ALiteral: TSyntaxNode);
  var
    Node: TSyntaxNode;
    Value: Double;
    Action: TCodeAction;
    Fixes: TArray<TRuleFix>;
  begin
    if not NumberValue(Text(ALiteral), Value) then
      Exit;
    Node := ALiteral;
    // -5: das Vorzeichen gehört zur Zahl.
    if (Node.Parent <> nil) and (Node.Parent.Kind = TSyntaxKind.UnaryExpr) and (Node.Parent.Name = '-') and
      (Node.Parent.ChildCount = 1) then
    begin
      Node := Node.Parent;
      Value := -Value;
    end;
    if IsAllowed(Value) then
      Exit;
    Fixes := nil;
    if TExtractRefactoring.ExtractConstant(AContext.Text, AContext.Tree, TTextRange.Create(Node.StartPos, Node.EndPos),
      TExtractOptions.Default, False, Action) then
      Fixes := [TRuleFix.Create('Konstante einführen', Action.Edits)];
    AReport.Add(TTextRange.Create(Node.StartPos, Node.EndPos), Format('Zahl %s ohne Namen; als Konstante wird klar, ' +
      'was sie bedeutet.', [Text(Node)]), TRuleConfidence.Low, Fixes);
  end;

  procedure Visit(ANode: TSyntaxNode; AInBody: Boolean);
  var
    Index: Integer;
  begin
    case ANode.Kind of
      // Konstanten, Typen, Array-Grenzen und Teilbereiche haben ihren Namen schon.
      TSyntaxKind.ConstSection, TSyntaxKind.ConstDecl, TSyntaxKind.InlineConst, TSyntaxKind.TypeSection,
      TSyntaxKind.TypeDecl, TSyntaxKind.TypeReference, TSyntaxKind.ArrayType, TSyntaxKind.SubrangeType,
      TSyntaxKind.SetType, TSyntaxKind.EnumType, TSyntaxKind.VarSection, TSyntaxKind.Attribute,
      TSyntaxKind.AsmBlock, TSyntaxKind.RoutineHeader:
        Exit;
      TSyntaxKind.Block:
        AInBody := True;
      TSyntaxKind.Literal:
        if AInBody then
          CheckLiteral(ANode);
    end;
    for Index := 0 to ANode.ChildCount - 1 do
      Visit(ANode[Index], AInBody);
  end;

var
  Defaults: TArray<Double>;
  Value: Double;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  Defaults := nil;
  for Value in DefaultAllowed do
    Defaults := Defaults + [Value];
  Allowed := TRuleOptions.Numbers(AContext.Options, 'allowed', Defaults);
  Settings := TFormatSettings.Invariant;
  Visit(AContext.Tree.Root, False);
end;

{ TPublicFieldRule }

function TPublicFieldRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('public-field', TRuleSeverity.Hint, 'Öffentliches Feld', True);
end;

procedure TPublicFieldRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Lines: TArray<string>;
  LineBreak: string;
  IncludeRecords: Boolean;

  function NodeText(ANode: TSyntaxNode): string;
  begin
    Result := Trim(Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset));
  end;

  function LineOf(ALine: Integer): string;
  begin
    Result := '';
    if (ALine >= 0) and (ALine <= High(Lines)) then
      Result := Lines[ALine];
  end;

  // Steht ANode allein in seiner Zeile (nur Leerraum davor und dahinter)?
  function AloneInLine(ANode: TSyntaxNode): Boolean;
  begin
    Result := (ANode.StartPos.Line = ANode.EndPos.Line) and
      (Trim(Copy(LineOf(ANode.StartPos.Line), 1, ANode.StartPos.Character)) = '') and
      (Trim(Copy(LineOf(ANode.EndPos.Line), ANode.EndPos.Character + 1, MaxInt)) = '');
  end;

  function HasMember(AType: TSyntaxNode; const AName: string): Boolean;
  var
    Index: Integer;
    Name: string;
  begin
    for Index := 0 to AType.ChildCount - 1 do
      if AType[Index].Kind in [TSyntaxKind.Field, TSyntaxKind.PropertyDecl, TSyntaxKind.RoutineHeader] then
        for Name in AType[Index].Name.Split([',']) do
          if SameText(Trim(Name), AName) then
            Exit(True);
    Result := False;
  end;

  // FName in private am Ende des Typs, Property im alten Abschnitt; der leere Abschnitt fällt weg.
  function Encapsulate(AType, AField, ASection: TSyntaxNode; const AVisibility: string;
    out AFix: TRuleFix): Boolean;
  var
    TypeRef, Next: TSyntaxNode;
    Name, FieldName, TypeName, Indent: string;
    EndLine, Index, Position: Integer;
    Edits: TArray<TTextEdit>;
  begin
    Result := False;
    Name := Trim(AField.Name);
    TypeRef := AField.FindChild(TSyntaxKind.TypeReference);
    if (Pos(',', Name) > 0) or (TypeRef = nil) or not AloneInLine(AField) then
      Exit;
    // Mit F-Präfix hieße die Property anders als das Feld; Zugriffe von außen gingen verloren.
    if (Length(Name) >= 2) and CharInSet(Name[1], ['F', 'f']) and CharInSet(Name[2], ['A'..'Z']) then
      Exit;
    FieldName := 'F' + UpperCase(Copy(Name, 1, 1)) + Copy(Name, 2, MaxInt);
    if HasMember(AType, FieldName) then
      Exit;
    TypeName := NodeText(TypeRef);
    EndLine := AType.EndPos.Line;
    if Trim(Copy(LineOf(EndLine), 1, AType.EndPos.Character - 3)) <> '' then
      Exit;
    Indent := TTextLines.IndentOf(LineOf(EndLine));
    Edits := [TTextEdit.Create(TTextRange.Create(AField.StartPos.Line, 0, AField.StartPos.Line + 1, 0), '')];
    // Einziges Mitglied seines Abschnitts: das Sichtbarkeitswort geht mit.
    if (ASection <> nil) and AloneInLine(ASection) then
    begin
      Position := -1;
      for Index := 0 to AType.ChildCount - 1 do
        if AType[Index] = AField then
          Position := Index;
      Next := nil;
      if (Position >= 0) and (Position < AType.ChildCount - 1) then
        Next := AType[Position + 1];
      if (Position > 0) and (AType[Position - 1] = ASection) and
        ((Next = nil) or (Next.Kind = TSyntaxKind.Visibility)) then
        Edits := [TTextEdit.Create(TTextRange.Create(ASection.StartPos.Line, 0, ASection.StartPos.Line + 1, 0), '')] +
          Edits;
    end;
    Edits := Edits + [TTextEdit.Create(TTextRange.Create(EndLine, 0, EndLine, 0), Indent + 'private' + LineBreak +
      Indent + '  ' + FieldName + ': ' + TypeName + ';' + LineBreak + Indent + AVisibility + LineBreak + Indent +
      '  property ' + Name + ': ' + TypeName + ' read ' + FieldName + ' write ' + FieldName + ';' + LineBreak)];
    AFix := TRuleFix.Create('Feld kapseln', Edits);
    Result := True;
  end;

  procedure CheckType(AType: TSyntaxNode; AImplicitCounts: Boolean; const AImplicit: string);
  var
    Index: Integer;
    Child, Section: TSyntaxNode;
    Visibility, Name: string;
    Fix: TRuleFix;
    Fixes: TArray<TRuleFix>;
  begin
    Visibility := '';
    Section := nil;
    for Index := 0 to AType.ChildCount - 1 do
    begin
      Child := AType[Index];
      if Child.Kind = TSyntaxKind.Visibility then
      begin
        Visibility := Child.Name;
        Section := Child;
        Continue;
      end;
      if Child.Kind <> TSyntaxKind.Field then
        Continue;
      if Visibility = '' then
      begin
        if not AImplicitCounts then
          Continue;
      end
      else if not MatchText(Visibility, ['public', 'published']) then
        Continue;
      Fixes := nil;
      if Visibility = '' then
      begin
        if Encapsulate(AType, Child, nil, AImplicit, Fix) then
          Fixes := [Fix];
      end
      else if Encapsulate(AType, Child, Section, Visibility, Fix) then
        Fixes := [Fix];
      for Name in Child.Name.Split([',']) do
        AReport.Add(TTextRange.Create(Child.StartPos, Child.EndPos), Format('Öffentliches Feld %s; eine Property ' +
          'hält die Klasse änderbar.', [Trim(Name)]), Fixes);
    end;
  end;

  // Abschnitt ohne Sichtbarkeitswort: bei Klassen ohne Vorfahren public, sonst oft Felder des Designers.
  function PlainClass(AClass: TSyntaxNode): Boolean;
  var
    Ancestor: TSyntaxNode;
  begin
    Ancestor := AClass.FindChild(TSyntaxKind.TypeReference);
    Result := (Ancestor = nil) or SameText(NodeText(Ancestor), 'TObject');
  end;

  procedure Visit(ANode: TSyntaxNode);
  var
    Index: Integer;
  begin
    case ANode.Kind of
      TSyntaxKind.ClassType:
        CheckType(ANode, PlainClass(ANode), 'public');
      TSyntaxKind.RecordType:
        if IncludeRecords then
          CheckType(ANode, True, 'public');
      TSyntaxKind.Block, TSyntaxKind.AsmBlock:
        Exit;
    end;
    for Index := 0 to ANode.ChildCount - 1 do
      Visit(ANode[Index]);
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  IncludeRecords := TRuleOptions.Bool(AContext.Options, 'includeRecords', False);
  Lines := TTextLines.SplitLines(AContext.Text, LineBreak);
  Visit(AContext.Tree.Root);
end;

{ TGlobalVariableRule }

function TGlobalVariableRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('global-variable', TRuleSeverity.Hint, 'Globale Variable im interface', True);
end;

procedure TGlobalVariableRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
const
  FormRoots: array[0..7] of string = ('TForm', 'TCustomForm', 'TFrame', 'TCustomFrame', 'TDataModule',
    'TService', 'TWebModule', 'TCustomDataModule');
var
  Tokens: TTokens;
  FormClasses: TArray<string>;
  IncludeForms: Boolean;

  function NodeText(ANode: TSyntaxNode): string;
  begin
    Result := Trim(Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset));
  end;

  // Klassen der Unit, die ein Formular, Frame oder Datenmodul sind: mit Formulardatei jede Klasse mit
  // Vorfahren, sonst die direkten Nachfahren bekannter Designerklassen.
  procedure CollectForms(ANode: TSyntaxNode);
  var
    Index: Integer;
    Body, Ancestor: TSyntaxNode;
  begin
    if ANode.Kind = TSyntaxKind.TypeDecl then
    begin
      Body := ANode.FindChild(TSyntaxKind.ClassType);
      if Body <> nil then
      begin
        Ancestor := Body.FindChild(TSyntaxKind.TypeReference);
        if (Ancestor <> nil) and ((AContext.FormText <> '') or MatchText(NodeText(Ancestor), FormRoots)) then
          FormClasses := FormClasses + [ANode.Name];
      end;
      Exit;
    end;
    if ANode.Kind in [TSyntaxKind.Block, TSyntaxKind.AsmBlock, TSyntaxKind.RoutineDecl] then
      Exit;
    for Index := 0 to ANode.ChildCount - 1 do
      CollectForms(ANode[Index]);
  end;

  function NameRange(ADecl: TSyntaxNode; const AName: string): TTextRange;
  var
    Index: Integer;
  begin
    Result := TTextRange.Create(ADecl.StartPos, ADecl.EndPos);
    for Index := 0 to High(Tokens) do
      if (Tokens[Index].Offset >= ADecl.StartOffset) and (Tokens[Index].Offset < ADecl.EndOffset) and
        (Tokens[Index].Kind = TPascalTokenKind.Identifier) and SameText(Tokens[Index].Text, AName) then
        Exit(TTextRange.Create(Tokens[Index].StartPos, Tokens[Index].EndPos));
  end;

  procedure CheckSection(ASection: TSyntaxNode);
  var
    Index: Integer;
    Decl, TypeRef: TSyntaxNode;
    Name: string;
  begin
    for Index := 0 to ASection.ChildCount - 1 do
    begin
      Decl := ASection[Index];
      if Decl.Kind <> TSyntaxKind.VarDecl then
        Continue;
      TypeRef := Decl.FindChild(TSyntaxKind.TypeReference);
      if not IncludeForms and (TypeRef <> nil) and MatchText(NodeText(TypeRef), FormClasses) then
        Continue;
      for Name in Decl.Name.Split([',']) do
        AReport.Add(NameRange(Decl, Trim(Name)), Format('Globale Variable %s ist in jeder Unit sichtbar, die ' +
          'diese verwendet.', [Trim(Name)]));
    end;
  end;

var
  InterfacePart: TSyntaxNode;
  Index: Integer;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  InterfacePart := AContext.Tree.Root.FindChild(TSyntaxKind.InterfaceSection);
  if InterfacePart = nil then
    Exit;
  Tokens := AContext.Tree.Tokens;
  IncludeForms := TRuleOptions.Bool(AContext.Options, 'includeFormVariables', False);
  FormClasses := nil;
  CollectForms(InterfacePart);
  for Index := 0 to InterfacePart.ChildCount - 1 do
    if InterfacePart[Index].Kind = TSyntaxKind.VarSection then
      CheckSection(InterfacePart[Index]);
end;

{ TLineLengthRule }

function TLineLengthRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('line-length', TRuleSeverity.Hint, 'Zeile zu lang', True);
end;

procedure TLineLengthRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
const
  Operators: array[0..11] of string = ('+', '-', '*', '/', 'and', 'or', 'xor', 'div', 'mod', 'shl', 'shr', '<>');
var
  Lines: TArray<string>;
  LineBreak, Continuation: string;
  Tokens: TTokens;
  ByLine: TArray<TArray<Integer>>;
  // Zeilen, in die ein mehrzeiliges Token hineinragt: dort wird nicht umgebrochen.
  Spanned: TArray<Boolean>;
  MaxLength, TabWidth: Integer;
  IgnoreStrings, IgnoreComments: Boolean;
  Style: TFormatStyle;

  // Sichtbare Spalte vor jedem Zeichen: AColumns[I] = Breite von ALine[1..I]; Tabs springen zur nächsten
  // Tabstelle, das zweite Zeichen eines Surrogatpaars zählt nicht.
  function Columns(const ALine: string): TArray<Integer>;
  var
    Index: Integer;
  begin
    SetLength(Result, Length(ALine) + 1);
    Result[0] := 0;
    for Index := 1 to Length(ALine) do
      if ALine[Index] = #9 then
        Result[Index] := (Result[Index - 1] div TabWidth + 1) * TabWidth
      else if (ALine[Index] >= #$DC00) and (ALine[Index] <= #$DFFF) then
        Result[Index] := Result[Index - 1]
      else
        Result[Index] := Result[Index - 1] + 1;
  end;

  function Clamp(AValue, AHigh: Integer): Integer;
  begin
    Result := Min(Max(AValue, 0), AHigh);
  end;

  // Breite ohne Strings bzw. Kommentare nach den Optionen; Anführungszeichen und Kommentarzeichen bleiben.
  function CountedWidth(ALine: Integer; const AColumns: TArray<Integer>): Integer;
  var
    TokenIndex, First, Last: Integer;
    Token: TPascalToken;
  begin
    Result := AColumns[High(AColumns)];
    for TokenIndex in ByLine[ALine] do
    begin
      Token := Tokens[TokenIndex];
      if not ((IgnoreStrings and (Token.Kind = TPascalTokenKind.StringLiteral)) or
        (IgnoreComments and (Token.Kind = TPascalTokenKind.Comment))) then
        Continue;
      First := 0;
      if Token.StartPos.Line = ALine then
        First := Token.StartPos.Character;
      Last := High(AColumns);
      if Token.EndPos.Line = ALine then
        Last := Token.EndPos.Character;
      First := Clamp(First, High(AColumns));
      Last := Clamp(Last, High(AColumns));
      Result := Result - Max(AColumns[Last] - AColumns[First] - 2, 0);
    end;
  end;

  function IsBreak(APrevious, AToken: Integer): Boolean;
  var
    Previous, Token: TPascalToken;
  begin
    Previous := Tokens[APrevious];
    Token := Tokens[AToken];
    if Token.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive] then
      Exit(False);
    // Hinter einem Komma oder vor einem zweistelligen Operator, wie der Formatierer (#43).
    Result := Previous.IsSymbol(',') or (MatchText(Token.Text, Operators) and
      ((Previous.Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Number, TPascalTokenKind.StringLiteral,
      TPascalTokenKind.CharLiteral]) or Previous.IsSymbol(')') or Previous.IsSymbol(']')));
  end;

  // Umbruchstellen von links nach rechts, so spät wie möglich; nil, wenn ein Stück nicht unter die Grenze passt.
  function WrapEdits(ALine: Integer; const AColumns: TArray<Integer>): TArray<TTextEdit>;
  var
    Candidates: TArray<Integer>;
    Position, Best, SegmentStart, Prefix, Column, Cut: Integer;
    Items: TArray<Integer>;
    Text: string;
  begin
    Result := nil;
    Items := nil;
    for Position in ByLine[ALine] do
      if Tokens[Position].StartPos.Line = ALine then
        Items := Items + [Position];
    if Spanned[ALine] or (Length(Items) < 2) then
      Exit;
    Candidates := nil;
    for Position := 1 to High(Items) do
      if (Tokens[Items[Position]].EndPos.Line = ALine) and
        not (Tokens[Items[Position - 1]].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) and
        IsBreak(Items[Position - 1], Items[Position]) then
        Candidates := Candidates + [Tokens[Items[Position]].StartPos.Character];
    Text := Lines[ALine];
    SegmentStart := TTextLines.IndentLength(Text);
    Prefix := AColumns[SegmentStart];
    Best := -1;
    Position := 0;
    while Prefix + AColumns[Length(Text)] - AColumns[SegmentStart] > MaxLength do
    begin
      // Spätester Schnitt, bei dem das Stück davor passt.
      while (Position <= High(Candidates)) and
        (Prefix + AColumns[Length(TrimRight(Copy(Text, 1, Candidates[Position])))] - AColumns[SegmentStart] <=
        MaxLength) do
      begin
        if Candidates[Position] > SegmentStart then
          Best := Candidates[Position];
        Inc(Position);
      end;
      if Best < 0 then
      begin
        Result := nil;
        Exit;
      end;
      Cut := Length(TrimRight(Copy(Text, 1, Best)));
      Result := Result + [TTextEdit.Create(TTextRange.Create(TTextPosition.Create(ALine, Cut),
        TTextPosition.Create(ALine, Best)), LineBreak + Continuation)];
      SegmentStart := Best;
      Column := 0;
      for Cut := 1 to Length(Continuation) do
        if Continuation[Cut] = #9 then
          Column := (Column div TabWidth + 1) * TabWidth
        else
          Inc(Column);
      Prefix := Column;
      Best := -1;
    end;
  end;

  // Erstes Zeichen hinter der Grenze; dort beginnt die Markierung.
  function OverflowStart(const AColumns: TArray<Integer>): Integer;
  begin
    Result := 0;
    while (Result < High(AColumns)) and (AColumns[Result + 1] <= MaxLength) do
      Inc(Result);
  end;

  procedure CheckLine(ALine: Integer);
  var
    Text: string;
    ColumnsOfLine: TArray<Integer>;
    Width: Integer;
    Edits: TArray<TTextEdit>;
    Fixes: TArray<TRuleFix>;
  begin
    Text := Lines[ALine];
    if Length(Text) > CompilerLimit then
    begin
      AReport.AddWithSeverity(TTextRange.Create(TTextPosition.Create(ALine, 0), TTextPosition.Create(ALine,
        Length(Text))), Format('Zeile mit %d Zeichen; der Compiler bricht über %d Zeichen ab (wie F2069).',
        [Length(Text), CompilerLimit]), TRuleSeverity.Error, nil);
      Exit;
    end;
    ColumnsOfLine := Columns(Text);
    Width := ColumnsOfLine[High(ColumnsOfLine)];
    if (Width <= MaxLength) or (CountedWidth(ALine, ColumnsOfLine) <= MaxLength) then
      Exit;
    Fixes := nil;
    Edits := WrapEdits(ALine, ColumnsOfLine);
    if Edits <> nil then
      Fixes := [TRuleFix.Create('Zeile umbrechen', Edits)];
    AReport.Add(TTextRange.Create(TTextPosition.Create(ALine, OverflowStart(ColumnsOfLine)),
      TTextPosition.Create(ALine, Length(Text))), Format('Zeile hat %d Zeichen (Grenze %d).', [Width, MaxLength]),
      Fixes);
  end;

var
  Index, Line: Integer;
begin
  if AContext.Text = '' then
    Exit;
  MaxLength := TRuleOptions.Int(AContext.Options, 'max', DefaultMax);
  if MaxLength <= 0 then
    MaxLength := DefaultMax;
  IgnoreStrings := TRuleOptions.Bool(AContext.Options, 'ignoreStrings', True);
  IgnoreComments := TRuleOptions.Bool(AContext.Options, 'ignoreComments', False);
  Style := AContext.Formatting;
  if Style.IndentSize <= 0 then
    Style.IndentSize := 2;
  TabWidth := Style.IndentSize;
  Lines := TTextLines.SplitLines(AContext.Text, LineBreak);
  SetLength(ByLine, Length(Lines));
  SetLength(Spanned, Length(Lines));
  Tokens := nil;
  if AContext.Tree <> nil then
    Tokens := AContext.Tree.Tokens;
  for Index := 0 to High(Tokens) do
    for Line := Max(Tokens[Index].StartPos.Line, 0) to Min(Tokens[Index].EndPos.Line, High(Lines)) do
    begin
      ByLine[Line] := ByLine[Line] + [Index];
      if Line > Tokens[Index].StartPos.Line then
        Spanned[Line] := True;
    end;
  Continuation := '';
  for Line := 0 to High(Lines) do
    // Ohne Tabs ist die Breite höchstens die Länge.
    if (Length(Lines[Line]) > Min(MaxLength, CompilerLimit)) or
      ((Pos(#9, Lines[Line]) > 0) and (Length(Lines[Line]) * TabWidth > MaxLength)) then
    begin
      Continuation := TTextLines.IndentOf(Lines[Line]) + TFormatLayout.IndentUnit(Style);
      CheckLine(Line);
    end;
  ByLine := nil;
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
end;

end.
