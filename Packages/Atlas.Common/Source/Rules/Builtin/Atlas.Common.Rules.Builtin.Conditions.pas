unit Atlas.Common.Rules.Builtin.Conditions;

// Bedingungen und Schleifen (#909, Gruppe Fehler finden):
//   constant-condition  Bedingung von if, while oder until steht fest (#1041):
//                       True, False, Vergleiche von Zahlen und untypisierte
//                       Konstanten der Datei, auch über and, or, xor und not;
//                       "X or True" ist immer wahr, "X and False" immer falsch.
//                       while True do und repeat … until False sind gewollte
//                       Endlosschleifen und bleiben still (dafür infinite-loop).
//                       Konstanten aus der Option switchConstants, Konstanten in
//                       einem Zweig von {$IF…} und solche aus anderen Units gelten
//                       als unbekannt. Korrektur bei if: toten Zweig entfernen
//                       bzw. die Bedingung entfernen (Zweig bleibt).

interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  ConstantConditionRuleId = 'constant-condition';

type
  TConstantConditionRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

procedure RegisterConditionRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Text.Lines,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.ConditionalBranches,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Semantics.OrdinalConstants,
  Atlas.Common.Rules.Options;

type
  TTokens = TArray<TPascalToken>;

  TConstantKind = (Unknown, Bool, Int);

  /// <summary>Wert eines Ausdrucks; Shown ist der Teil, der den Wert festlegt (z. B. "… or True").</summary>
  TConstantValue = record
    Kind: TConstantKind;
    Bool: Boolean;
    Int: Int64;
    Shown: string;
    class function Unknown: TConstantValue; static;
    class function OfBool(AValue: Boolean; const AShown: string): TConstantValue; static;
    class function OfInt(AValue: Int64): TConstantValue; static;
  end;

  /// <summary>Wertet Bedingungen aus dem Syntaxbaum aus; Namen über die Namensauflösung.</summary>
  TConditionValues = class
  private
    FTree: TSyntaxTree;
    FText: string;
    FFileName: string;
    FResolver: TNameResolver;
    FPaths: TArray<string>;
    FSwitches: TArray<string>;
    /// <summary>Untypisierte Konstanten der Datei außerhalb von {$IF…}, Schlüssel klein.</summary>
    FConstants: TDictionary<string, Boolean>;
    FDepth: Integer;
    procedure CollectConstants(ANode: TSyntaxNode);
    function FirstToken(AOffset: Integer): Integer;
    function HasDirective(ANode: TSyntaxNode): Boolean;
    function IsPlainConstant(ANode: TSyntaxNode): Boolean;
    function FindConstant(ANode: TSyntaxNode; const AName: string; const APosition: TTextPosition): TSyntaxNode;
    function NameValue(ANode: TSyntaxNode): TConstantValue;
    function Binary(ANode: TSyntaxNode): TConstantValue;
  public
    constructor Create(ATree: TSyntaxTree; const AText, AFileName: string; AResolver: TNameResolver;
      const ASwitches: TArray<string>);
    destructor Destroy; override;
    function Evaluate(ANode: TSyntaxNode): TConstantValue;
    /// <summary>Steht in der Bedingung ANode oder direkt davor bzw. dahinter eine Direktive (bedingter Teil)?</summary>
    function Conditional(ANode: TSyntaxNode): Boolean;
  end;

{ TConstantValue }

class function TConstantValue.Unknown: TConstantValue;
begin
  Result := Default(TConstantValue);
end;

class function TConstantValue.OfBool(AValue: Boolean; const AShown: string): TConstantValue;
begin
  Result := Default(TConstantValue);
  Result.Kind := TConstantKind.Bool;
  Result.Bool := AValue;
  Result.Shown := AShown;
end;

class function TConstantValue.OfInt(AValue: Int64): TConstantValue;
begin
  Result := Default(TConstantValue);
  Result.Kind := TConstantKind.Int;
  Result.Int := AValue;
end;

function BoolText(AValue: Boolean): string;
begin
  if AValue then
    Result := 'True'
  else
    Result := 'False';
end;

function NodeText(const AText: string; ANode: TSyntaxNode): string;
begin
  Result := Copy(AText, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
end;

function NodeRange(ANode: TSyntaxNode): TTextRange;
begin
  Result := TTextRange.Create(ANode.StartPos, ANode.EndPos);
end;

function Unwrapped(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := ANode;
  while (Result <> nil) and (Result.Kind = TSyntaxKind.ParenExpr) and (Result.ChildCount = 1) do
    Result := Result[0];
end;

function IsBoolLiteral(ANode: TSyntaxNode; AValue: Boolean): Boolean;
begin
  ANode := Unwrapped(ANode);
  Result := (ANode <> nil) and (ANode.Kind = TSyntaxKind.Identifier) and SameText(ANode.Name, BoolText(AValue));
end;

{ TConditionValues }

constructor TConditionValues.Create(ATree: TSyntaxTree; const AText, AFileName: string; AResolver: TNameResolver;
  const ASwitches: TArray<string>);
begin
  inherited Create;
  FTree := ATree;
  FText := AText;
  FFileName := AFileName;
  FResolver := AResolver;
  FSwitches := ASwitches;
  FPaths := TConditionalBranches.Paths(ATree.Tokens);
  FConstants := TDictionary<string, Boolean>.Create;
  if ATree.Root <> nil then
    CollectConstants(ATree.Root);
end;

destructor TConditionValues.Destroy;
begin
  FConstants.Free;
  inherited;
end;

function TConditionValues.FirstToken(AOffset: Integer): Integer;
var
  Lo, Hi, Middle: Integer;
begin
  Lo := 0;
  Hi := Length(FTree.Tokens);
  while Lo < Hi do
  begin
    Middle := (Lo + Hi) div 2;
    if FTree.Tokens[Middle].Offset < AOffset then
      Lo := Middle + 1
    else
      Hi := Middle;
  end;
  Result := Lo;
end;

function TConditionValues.HasDirective(ANode: TSyntaxNode): Boolean;
var
  Index: Integer;
begin
  Index := FirstToken(ANode.StartOffset);
  while (Index <= High(FTree.Tokens)) and (FTree.Tokens[Index].Offset < ANode.EndOffset) do
  begin
    if FTree.Tokens[Index].Kind = TPascalTokenKind.Directive then
      Exit(True);
    Inc(Index);
  end;
  Result := False;
end;

function TConditionValues.Conditional(ANode: TSyntaxNode): Boolean;
var
  First, Last, Index: Integer;
begin
  // Vom Schlüsselwort vor der Bedingung (if, while, until) bis zu dem dahinter (then, do, ;).
  First := FirstToken(ANode.StartOffset) - 1;
  while (First > 0) and (FTree.Tokens[First].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
    Dec(First);
  Last := FirstToken(ANode.EndOffset);
  while (Last < High(FTree.Tokens)) and
    (FTree.Tokens[Last].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
    Inc(Last);
  for Index := First + 1 to Last - 1 do
    if FTree.Tokens[Index].Kind = TPascalTokenKind.Directive then
      Exit(True);
  Result := False;
end;

function TConditionValues.IsPlainConstant(ANode: TSyntaxNode): Boolean;
var
  Index, Values: Integer;
begin
  // Name = Wert; ohne Typ (sonst typisierte Konstante), ohne Direktive, außerhalb von {$IF…}.
  Values := 0;
  for Index := 0 to ANode.ChildCount - 1 do
    if ANode[Index].Kind <> TSyntaxKind.Directive then
      Inc(Values);
  Result := (Values = 1) and not HasDirective(ANode) and
    (TConditionalBranches.PathAt(FPaths, FirstToken(ANode.StartOffset)) = '');
end;

procedure TConditionValues.CollectConstants(ANode: TSyntaxNode);
var
  Index: Integer;
begin
  for Index := 0 to ANode.ChildCount - 1 do
  begin
    if (ANode[Index].Kind = TSyntaxKind.ConstDecl) and IsPlainConstant(ANode[Index]) and
      not MatchText(ANode[Index].Name, FSwitches) then
      FConstants.AddOrSetValue(LowerCase(ANode[Index].Name), True);
    CollectConstants(ANode[Index]);
  end;
end;

function TConditionValues.FindConstant(ANode: TSyntaxNode; const AName: string;
  const APosition: TTextPosition): TSyntaxNode;
var
  Index: Integer;
  Child: TSyntaxNode;
begin
  // ConstDecl mit dem Namen, die APosition enthält.
  Result := nil;
  for Index := 0 to ANode.ChildCount - 1 do
  begin
    Child := ANode[Index];
    if (Child.StartPos.Line > APosition.Line) or ((Child.EndPos.Line < APosition.Line)) then
      Continue;
    if (Child.Kind = TSyntaxKind.ConstDecl) and SameText(Child.Name, AName) then
      Exit(Child);
    Result := FindConstant(Child, AName, APosition);
    if Result <> nil then
      Exit;
  end;
end;

function TConditionValues.NameValue(ANode: TSyntaxNode): TConstantValue;
var
  Resolved: TResolvedSymbol;
  Declaration: TSyntaxNode;
  Index: Integer;
begin
  Result := TConstantValue.Unknown;
  if SameText(ANode.Name, 'True') or SameText(ANode.Name, 'False') then
    Exit(TConstantValue.OfBool(SameText(ANode.Name, 'True'), ANode.Name));
  if not FConstants.ContainsKey(LowerCase(ANode.Name)) or (FDepth >= 8) then
    Exit;
  Resolved := FResolver.ResolveChain(FTree, FFileName, [ANode.Name], ANode.StartOffset);
  if not Resolved.Found or (Resolved.SymbolKind <> TIndexSymbolKind.Constant) or
    not ((Resolved.Kind = TResolvedKind.Local) or (Resolved.FileName = '') or
    SameText(Resolved.FileName, FFileName)) then
    Exit;
  Declaration := FindConstant(FTree.Root, ANode.Name, Resolved.Range.StartPos);
  if (Declaration = nil) or not IsPlainConstant(Declaration) then
    Exit;
  Inc(FDepth);
  try
    for Index := Declaration.ChildCount - 1 downto 0 do
      if Declaration[Index].Kind <> TSyntaxKind.Directive then
      begin
        Result := Evaluate(Declaration[Index]);
        Break;
      end;
  finally
    Dec(FDepth);
  end;
  if Result.Kind = TConstantKind.Bool then
    Result.Shown := ANode.Name + ' = ' + BoolText(Result.Bool);
end;

function TConditionValues.Binary(ANode: TSyntaxNode): TConstantValue;
var
  Left, Right: TConstantValue;
  Op: string;
  Compared: Integer;
begin
  Result := TConstantValue.Unknown;
  if ANode.ChildCount <> 2 then
    Exit;
  Op := ANode.Name;
  Left := Evaluate(ANode[0]);
  Right := Evaluate(ANode[1]);
  if (Op = 'and') or (Op = 'or') then
  begin
    // Ein fester Operand entscheidet allein: X or True, False and X.
    if (Left.Kind = TConstantKind.Bool) and (Left.Bool = (Op = 'or')) then
      Exit(TConstantValue.OfBool(Left.Bool, Left.Shown + ' ' + Op + ' …'));
    if (Right.Kind = TConstantKind.Bool) and (Right.Bool = (Op = 'or')) then
      Exit(TConstantValue.OfBool(Right.Bool, '… ' + Op + ' ' + Right.Shown));
    if (Left.Kind = TConstantKind.Bool) and (Right.Kind = TConstantKind.Bool) then
      Exit(TConstantValue.OfBool(Right.Bool, NodeText(FText, ANode)));
    Exit;
  end;
  if (Left.Kind = TConstantKind.Unknown) or (Left.Kind <> Right.Kind) then
    Exit;
  if Left.Kind = TConstantKind.Bool then
  begin
    if Op = 'xor' then
      Exit(TConstantValue.OfBool(Left.Bool <> Right.Bool, NodeText(FText, ANode)));
    Compared := Ord(Left.Bool) - Ord(Right.Bool);
  end
  else
  begin
    if Op = '+' then
      Exit(TConstantValue.OfInt(Left.Int + Right.Int));
    if Op = '-' then
      Exit(TConstantValue.OfInt(Left.Int - Right.Int));
    if Op = '*' then
      Exit(TConstantValue.OfInt(Left.Int * Right.Int));
    if ((Op = 'div') or (Op = 'mod')) and (Right.Int <> 0) then
    begin
      if Op = 'div' then
        Exit(TConstantValue.OfInt(Left.Int div Right.Int));
      Exit(TConstantValue.OfInt(Left.Int mod Right.Int));
    end;
    if Left.Int < Right.Int then
      Compared := -1
    else if Left.Int > Right.Int then
      Compared := 1
    else
      Compared := 0;
  end;
  if Op = '=' then
    Result := TConstantValue.OfBool(Compared = 0, '')
  else if Op = '<>' then
    Result := TConstantValue.OfBool(Compared <> 0, '')
  else if Op = '<' then
    Result := TConstantValue.OfBool(Compared < 0, '')
  else if Op = '>' then
    Result := TConstantValue.OfBool(Compared > 0, '')
  else if Op = '<=' then
    Result := TConstantValue.OfBool(Compared <= 0, '')
  else if Op = '>=' then
    Result := TConstantValue.OfBool(Compared >= 0, '');
  if Result.Kind = TConstantKind.Bool then
    Result.Shown := NodeText(FText, ANode);
end;

function TConditionValues.Evaluate(ANode: TSyntaxNode): TConstantValue;
var
  Inner: TConstantValue;
  Number: Int64;
begin
  Result := TConstantValue.Unknown;
  if ANode = nil then
    Exit;
  case ANode.Kind of
    TSyntaxKind.ParenExpr:
      if ANode.ChildCount = 1 then
        Result := Evaluate(ANode[0]);
    TSyntaxKind.Identifier:
      Result := NameValue(ANode);
    TSyntaxKind.Literal:
      if TOrdinalConstants.TryNumber(ANode.Name, Number) then
        Result := TConstantValue.OfInt(Number);
    TSyntaxKind.UnaryExpr:
      if ANode.ChildCount = 1 then
      begin
        Inner := Evaluate(ANode[0]);
        if (ANode.Name = 'not') and (Inner.Kind = TConstantKind.Bool) then
          Result := TConstantValue.OfBool(not Inner.Bool, 'not ' + Inner.Shown)
        else if (ANode.Name = '-') and (Inner.Kind = TConstantKind.Int) then
          Result := TConstantValue.OfInt(-Inner.Int)
        else if (ANode.Name = '+') and (Inner.Kind = TConstantKind.Int) then
          Result := Inner;
      end;
    TSyntaxKind.BinaryExpr:
      Result := Binary(ANode);
  end;
end;

{ TConstantConditionRule }

function TConstantConditionRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(ConstantConditionRuleId, TRuleSeverity.Warning, 'Bedingung ist immer gleich');
end;

/// <summary>Text des Knotens; Folgezeilen um die Spalte des Knotens gegenüber AColumn ausgerückt.</summary>
function Outdented(const AText: string; ANode: TSyntaxNode; AColumn: Integer): string;
var
  Lines: TArray<string>;
  LineBreak: string;
  Index, Shift, Remove: Integer;
begin
  Lines := TTextLines.SplitLines(NodeText(AText, ANode), LineBreak);
  Shift := ANode.StartPos.Character - AColumn;
  if Shift > 0 then
    for Index := 1 to High(Lines) do
    begin
      Remove := TTextLines.IndentLength(Lines[Index]);
      if Remove > Shift then
        Remove := Shift;
      Lines[Index] := Copy(Lines[Index], Remove + 1, MaxInt);
    end;
  Result := TTextLines.JoinLines(Lines, LineBreak);
end;

/// <summary>Bereich, der eine ganze Anweisung entfernt: mit folgendem Semikolon und, wenn sie allein auf ihren
/// Zeilen steht, mit den Zeilen.</summary>
function StatementRemoval(const AText: string; ANode: TSyntaxNode): TTextRange;
var
  Lines: TLineTable;
  First, Last, Probe: Integer;
begin
  Lines := TLineTable.Build(AText);
  First := ANode.StartOffset;
  Last := ANode.EndOffset;
  Probe := Last;
  while (Probe < Length(AText)) and CharInSet(AText[Probe + 1], [' ', #9]) do
    Inc(Probe);
  if (Probe < Length(AText)) and (AText[Probe + 1] = ';') then
    Last := Probe + 1;
  Probe := Last;
  while (Probe < Length(AText)) and CharInSet(AText[Probe + 1], [' ', #9]) do
    Inc(Probe);
  if ((Probe = Length(AText)) or CharInSet(AText[Probe + 1], [#13, #10])) and
    (Trim(Copy(AText, Lines.LineStart(ANode.StartPos.Line) + 1, First - Lines.LineStart(ANode.StartPos.Line))) = '') then
  begin
    First := Lines.LineStart(ANode.StartPos.Line);
    Last := Lines.LineStart(Lines.PositionAt(Probe).Line + 1);
    if Last <= Probe then
      Last := Probe;
  end;
  Result := TTextRange.Create(Lines.PositionAt(First), Lines.PositionAt(Last));
end;

procedure TConstantConditionRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Values: TConditionValues;
  Resolver: TNameResolver;
  FileName: string;

  procedure ReportIf(ANode: TSyntaxNode; const AValue: TConstantValue);
  var
    Message: string;
    Fixes: TArray<TRuleFix>;
    Branch: TSyntaxNode;
  begin
    if AValue.Bool then
      Message := Format('Die Bedingung ist immer wahr (%s).', [AValue.Shown])
    else
      Message := Format('Die Bedingung ist immer falsch (%s).', [AValue.Shown]);
    Fixes := nil;
    Branch := nil;
    if AValue.Bool and (ANode.ChildCount >= 2) then
      Branch := ANode[1]
    else if not AValue.Bool and (ANode.ChildCount >= 3) then
      Branch := ANode[2];
    if (Branch <> nil) and (Branch.Kind <> TSyntaxKind.EmptyStatement) then
    begin
      if AValue.Bool then
        Fixes := [TRuleFix.Create('Bedingung entfernen', [TRuleEdit.Create(NodeRange(ANode),
          Outdented(AContext.Text, Branch, ANode.StartPos.Character))])]
      else
        Fixes := [TRuleFix.Create('Toten Zweig entfernen', [TRuleEdit.Create(NodeRange(ANode),
          Outdented(AContext.Text, Branch, ANode.StartPos.Character))])];
    end
    else if not AValue.Bool then
      Fixes := [TRuleFix.Create('Toten Zweig entfernen', [TRuleEdit.Create(StatementRemoval(AContext.Text, ANode),
        '')])];
    AReport.Add(NodeRange(ANode[0]), Message, TRuleConfidence.High, Fixes);
  end;

  procedure Visit(ANode: TSyntaxNode);
  var
    Index: Integer;
    Condition: TSyntaxNode;
    Value: TConstantValue;
  begin
    Condition := nil;
    case ANode.Kind of
      TSyntaxKind.IfStatement, TSyntaxKind.WhileStatement:
        if ANode.ChildCount > 0 then
          Condition := ANode[0];
      TSyntaxKind.RepeatStatement:
        if ANode.ChildCount > 0 then
          Condition := ANode[ANode.ChildCount - 1];
    end;
    if (Condition <> nil) and not Values.Conditional(Condition) then
    begin
      Value := Values.Evaluate(Condition);
      // while True do und repeat … until False: gewollte Endlosschleife (infinite-loop prüft den Ausgang).
      if (Value.Kind = TConstantKind.Bool) and
        not ((ANode.Kind = TSyntaxKind.WhileStatement) and IsBoolLiteral(Condition, True)) and
        not ((ANode.Kind = TSyntaxKind.RepeatStatement) and IsBoolLiteral(Condition, False)) then
      begin
        if ANode.Kind = TSyntaxKind.IfStatement then
          ReportIf(ANode, Value)
        else if Value.Bool then
          AReport.Add(NodeRange(Condition), Format('Die Bedingung ist immer wahr (%s).', [Value.Shown]),
            TRuleConfidence.High)
        else
          AReport.Add(NodeRange(Condition), Format('Die Bedingung ist immer falsch (%s).', [Value.Shown]),
            TRuleConfidence.High);
      end;
    end;
    for Index := 0 to ANode.ChildCount - 1 do
      Visit(ANode[Index]);
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  FileName := AContext.FileName;
  if FileName = '' then
    FileName := AContext.RelativePath;
  if FileName = '' then
    FileName := AContext.UnitName + '.pas';
  Resolver := TNameResolver.Create(AContext.Index, AContext.EnsureUnit);
  try
    Resolver.Namespaces := AContext.Namespaces;
    Resolver.PinTree(AContext.Tree, FileName);
    Values := TConditionValues.Create(AContext.Tree, AContext.Text, FileName, Resolver,
      TRuleOptions.Strings(AContext.Options, 'switchConstants', []));
    try
      Visit(AContext.Tree.Root);
    finally
      Values.Free;
      Resolver.UnpinTree;
    end;
  finally
    Resolver.Free;
  end;
end;

procedure RegisterConditionRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TConstantConditionRule.Create);
end;

end.
