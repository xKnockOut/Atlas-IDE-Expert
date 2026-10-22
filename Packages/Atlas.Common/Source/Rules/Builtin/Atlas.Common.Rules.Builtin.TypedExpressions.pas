unit Atlas.Common.Rules.Builtin.TypedExpressions;

// Regeln der Gruppe „Compiler vorab“, die den Typ eines Ausdrucks brauchen
// (Stufe T in #1024). Den Typ liefert TNameResolver.NodeType; gemeldet wird nur,
// wenn er sicher bekannt ist und seine Deklaration immer mit der Stelle
// übersetzt wird (Pascal.ConditionalBranches bzw. Condition im Index):
//   comparison-always-constant
//                     Vergleich einer Variablen, eines Feldes, einer Property oder
//                     eines Funktionsergebnisses vom eingebauten Ganzzahltyp mit
//                     einer Konstanten außerhalb bzw. am Rand des Wertebereichs
//                     (#1011): Cardinal >= 0 ist immer wahr (wie W1022), Byte > 255
//                     immer falsch (wie W1021); case-Marken außerhalb des Bereichs
//                     des Ausdrucks (wie W1018). Die Konstante rechnet
//                     Semantics.ConstantValues aus. NativeInt, LongInt und ihre
//                     vorzeichenlosen Gegenstücke gelten mit dem weitesten Bereich
//                     aller Plattformen; Teilbereichstypen meldet die Regel nicht.
//                     Length(…) < 0 und Length(…) >= 0 meldet sie auch, obwohl dcc
//                     dort nicht warnt (Wunsch aus #1011: offensichtlich falsch);
//                     die Meldung sagt das dazu.

interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  ComparisonAlwaysConstantRuleId = 'comparison-always-constant';

type
  TComparisonAlwaysConstantRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Ergebnis von "X AOperator AValue" für X im Bereich ALow..AHigh: 1 immer wahr, 0 immer falsch,
    /// -1 abhängig von X. AOperator ist = &lt;&gt; &lt; &lt;= &gt; &gt;=.</summary>
    class function Outcome(const AOperator: string; AValue, ALow, AHigh: Int64): Integer; static;
  end;

procedure RegisterTypedExpressionRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.ConditionalBranches,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Semantics.ConstantValues;

type
  /// <summary>Gemeinsamer Rahmen der Regeln: Namensauflösung über den gepinnten Baum, Konstantenwerte und die
  /// Prüfung, ob eine Deklaration immer mit einer Stelle übersetzt wird.</summary>
  TTypedScope = class
  private
    FContext: TRuleContext;
    FFileName: string;
    FResolver: TNameResolver;
    FValues: TConstantValues;
    FPaths: TArray<string>;
    FTokens: TArray<TPascalToken>;
    function TokenAtPosition(const APosition: TTextPosition): Integer;
  public
    constructor Create(const AContext: TRuleContext);
    destructor Destroy; override;
    /// <summary>Quelltext von ANode, Leerraum zu einem Leerzeichen zusammengefasst.</summary>
    function Text(ANode: TSyntaxNode): string;
    /// <summary>Wird die Deklaration ASymbol immer übersetzt, wenn ANode übersetzt wird?</summary>
    function DeclarationSure(const ASymbol: TResolvedSymbol; ANode: TSyntaxNode): Boolean;
    /// <summary>Deklaration und Typ von ANode wie TNameResolver.NodeType, aber nur bei sicher bekanntem Typ und
    /// einer Deklaration, die immer mit ANode übersetzt wird.</summary>
    function SureType(ANode: TSyntaxNode; out ASymbol, AType: TResolvedSymbol): Boolean;
    property Resolver: TNameResolver read FResolver;
    property Values: TConstantValues read FValues;
    property FileName: string read FFileName;
  end;

constructor TTypedScope.Create(const AContext: TRuleContext);
begin
  inherited Create;
  FContext := AContext;
  FFileName := AContext.FileName;
  if FFileName = '' then
    FFileName := AContext.RelativePath;
  if FFileName = '' then
    FFileName := AContext.UnitName + '.pas';
  FTokens := AContext.Tree.Tokens;
  FPaths := TConditionalBranches.Paths(FTokens);
  FResolver := TNameResolver.Create(AContext.Index, AContext.EnsureUnit);
  FResolver.Namespaces := AContext.Namespaces;
  FResolver.PinTree(AContext.Tree, FFileName);
  FValues := TConstantValues.Create(AContext.Tree, FFileName, AContext.Index, FResolver);
end;

destructor TTypedScope.Destroy;
begin
  FValues.Free;
  if FResolver <> nil then
    FResolver.UnpinTree;
  FResolver.Free;
  inherited;
end;

function TTypedScope.Text(ANode: TSyntaxNode): string;
var
  Index: Integer;
  Space: Boolean;
  Raw: string;
begin
  Raw := Copy(FContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
  Result := '';
  Space := False;
  for Index := 1 to Length(Raw) do
    if CharInSet(Raw[Index], [' ', #9, #10, #13]) then
      Space := True
    else
    begin
      if Space and (Result <> '') then
        Result := Result + ' ';
      Space := False;
      Result := Result + Raw[Index];
    end;
end;

function TTypedScope.TokenAtPosition(const APosition: TTextPosition): Integer;
var
  Low, High, Middle: Integer;
begin
  Low := 0;
  High := Length(FTokens);
  while Low < High do
  begin
    Middle := (Low + High) div 2;
    if (FTokens[Middle].StartPos.Line < APosition.Line) or ((FTokens[Middle].StartPos.Line = APosition.Line) and
      (FTokens[Middle].StartPos.Character < APosition.Character)) then
      Low := Middle + 1
    else
      High := Middle;
  end;
  Result := Low;
end;

function TTypedScope.DeclarationSure(const ASymbol: TResolvedSymbol; ANode: TSyntaxNode): Boolean;
var
  Use: Integer;
begin
  if ASymbol.Condition <> '' then
    Exit(False);
  if (ASymbol.Kind <> TResolvedKind.Local) and (ASymbol.FileName <> '') and not SameText(ASymbol.FileName,
    FFileName) then
    Exit(True);
  // Deklaration in dieser Datei: Der Baum enthält beide Zweige von {$IFDEF} … {$ELSE}.
  if FPaths = nil then
    Exit(True);
  Use := TConstantValues.TokenFrom(FTokens, ANode.StartOffset);
  Result := TConditionalBranches.Implies(TConditionalBranches.PathAt(FPaths, Use),
    TConditionalBranches.PathAt(FPaths, TokenAtPosition(ASymbol.Range.StartPos)));
end;

function TTypedScope.SureType(ANode: TSyntaxNode; out ASymbol, AType: TResolvedSymbol): Boolean;
var
  TypeFound: Boolean;
begin
  Result := (ANode <> nil) and (ANode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess, TSyntaxKind.Call,
    TSyntaxKind.IndexAccess]) and FResolver.NodeType(FContext.Tree, FFileName, ANode, ASymbol, AType, TypeFound) and
    TypeFound and (ASymbol.Kind <> TResolvedKind.UnitName) and DeclarationSure(ASymbol, ANode);
end;

/// <summary>Ausdruck ohne umschließende Klammern.</summary>
function Unwrapped(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := ANode;
  while (Result <> nil) and (Result.Kind = TSyntaxKind.ParenExpr) and (Result.ChildCount = 1) do
    Result := Result[0];
end;

{ TComparisonAlwaysConstantRule }

function TComparisonAlwaysConstantRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(ComparisonAlwaysConstantRuleId, TRuleSeverity.Warning,
    'Vergleich immer wahr oder immer falsch');
end;

class function TComparisonAlwaysConstantRule.Outcome(const AOperator: string; AValue, ALow, AHigh: Int64): Integer;
begin
  Result := -1;
  if AOperator = '=' then
  begin
    if (AValue < ALow) or (AValue > AHigh) then
      Result := 0;
  end
  else if AOperator = '<>' then
  begin
    if (AValue < ALow) or (AValue > AHigh) then
      Result := 1;
  end
  else if AOperator = '<' then
  begin
    if AValue > AHigh then
      Result := 1
    else if AValue <= ALow then
      Result := 0;
  end
  else if AOperator = '<=' then
  begin
    if AValue >= AHigh then
      Result := 1
    else if AValue < ALow then
      Result := 0;
  end
  else if AOperator = '>' then
  begin
    if AValue < ALow then
      Result := 1
    else if AValue >= AHigh then
      Result := 0;
  end
  else if AOperator = '>=' then
  begin
    if AValue <= ALow then
      Result := 1
    else if AValue > AHigh then
      Result := 0;
  end;
end;

/// <summary>Operator mit vertauschten Seiten: 0 &lt; X ist X &gt; 0.</summary>
function Mirrored(const AOperator: string): string;
begin
  Result := AOperator;
  if AOperator = '<' then
    Result := '>'
  else if AOperator = '>' then
    Result := '<'
  else if AOperator = '<=' then
    Result := '>='
  else if AOperator = '>=' then
    Result := '<=';
end;

procedure TComparisonAlwaysConstantRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Scope: TTypedScope;

  /// <summary>Wertebereich von ANode, wenn sein Typ sicher ein eingebauter Ganzzahltyp ist.</summary>
  function IntegerOperand(ANode: TSyntaxNode; out ATypeName: string; out ALow, AHigh: Int64): Boolean;
  var
    Symbol, TypeInfo: TResolvedSymbol;
  begin
    Result := Scope.SureType(ANode, Symbol, TypeInfo) and (TypeInfo.Builtin or SameText(TypeInfo.UnitName,
      'System')) and TConstantValues.IntegerRange(TypeInfo.Name, ALow, AHigh);
    if Result then
      ATypeName := TypeInfo.Name;
  end;

  /// <summary>", die Schleife endet nie" bzw. "läuft nie", wenn ANode die ganze Bedingung einer Schleife ist.
  /// </summary>
  function LoopNote(ANode: TSyntaxNode; AAlways: Boolean): string;
  var
    Node: TSyntaxNode;
  begin
    Result := '';
    Node := ANode;
    while (Node.Parent <> nil) and (Node.Parent.Kind = TSyntaxKind.ParenExpr) do
      Node := Node.Parent;
    if Node.Parent = nil then
      Exit;
    if (Node.Parent.Kind = TSyntaxKind.WhileStatement) and (Node.Parent[0] = Node) then
    begin
      if AAlways then
        Result := ', die Schleife endet nie'
      else
        Result := ', die Schleife läuft nie';
    end
    else if (Node.Parent.Kind = TSyntaxKind.RepeatStatement) and (Node.Parent[Node.Parent.ChildCount - 1] = Node) and
      not AAlways then
      Result := ', die Schleife endet nie';
  end;

  /// <summary>Ist ANode ein Aufruf von Length aus System (nie negativ)?</summary>
  function IsLengthCall(ANode: TSyntaxNode): Boolean;
  var
    Callee: TResolvedSymbol;
  begin
    Result := (ANode <> nil) and (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount = 2) and
      (ANode[0].Kind = TSyntaxKind.Identifier) and SameText(ANode[0].Name, 'Length');
    if not Result then
      Exit;
    // Eine eigene Funktion Length kann negativ werden.
    Callee := Scope.Resolver.Resolve(AContext.Tree, Scope.FileName, ANode[0].StartPos);
    Result := not Callee.Found or SameText(Callee.UnitName, 'System');
  end;

  procedure CheckComparison(ANode: TSyntaxNode);
  var
    Left, Right, Operand: TSyntaxNode;
    Value, LowValue, HighValue: Int64;
    Operation, TypeName, Note: string;
    Verdict: Integer;
  begin
    if ANode.ChildCount <> 2 then
      Exit;
    Left := Unwrapped(ANode[0]);
    Right := Unwrapped(ANode[1]);
    Operation := ANode.Name;
    if Scope.Values.EvaluateNode(Right, Value) then
      Operand := Left
    else if Scope.Values.EvaluateNode(Left, Value) then
    begin
      Operand := Right;
      Operation := Mirrored(Operation);
    end
    else
      Exit;
    if IsLengthCall(Operand) then
    begin
      Verdict := Outcome(Operation, Value, 0, High(Int64));
      if Verdict < 0 then
        Exit;
      Note := LoopNote(ANode, Verdict = 1);
      if Verdict = 1 then
        AReport.Add(TTextRange.Create(ANode.StartPos, ANode.EndPos), Format(
          '%s ist nie negativ; %s ist immer wahr%s (dcc meldet das nicht).', [Scope.Text(Operand), Scope.Text(ANode),
          Note]), TRuleConfidence.High)
      else
        AReport.Add(TTextRange.Create(ANode.StartPos, ANode.EndPos), Format(
          '%s ist nie negativ; %s ist immer falsch%s (dcc meldet das nicht).', [Scope.Text(Operand), Scope.Text(ANode),
          Note]), TRuleConfidence.High);
      Exit;
    end;
    if not IntegerOperand(Operand, TypeName, LowValue, HighValue) then
      Exit;
    Verdict := Outcome(Operation, Value, LowValue, HighValue);
    if Verdict < 0 then
      Exit;
    Note := LoopNote(ANode, Verdict = 1);
    if Verdict = 1 then
      AReport.Add(TTextRange.Create(ANode.StartPos, ANode.EndPos), Format('%s ist %s; %s ist immer wahr%s (wie W1022).',
        [Scope.Text(Operand), TypeName, Scope.Text(ANode), Note]), TRuleConfidence.High)
    else
      AReport.Add(TTextRange.Create(ANode.StartPos, ANode.EndPos), Format('%s ist %s; %s ist immer falsch%s (wie W1021).',
        [Scope.Text(Operand), TypeName, Scope.Text(ANode), Note]), TRuleConfidence.High);
  end;

  procedure CheckCase(ANode: TSyntaxNode);
  var
    Item, Labeled: TSyntaxNode;
    ItemIndex, LabelIndex: Integer;
    LowValue, HighValue, First, Last: Int64;
    TypeName: string;
    Outside: Boolean;
  begin
    if (ANode.ChildCount = 0) or not IntegerOperand(Unwrapped(ANode[0]), TypeName, LowValue, HighValue) then
      Exit;
    for ItemIndex := 1 to ANode.ChildCount - 1 do
    begin
      Item := ANode[ItemIndex];
      if Item.Kind <> TSyntaxKind.CaseItem then
        Continue;
      // Das letzte Kind ist die Anweisung, davor stehen die Marken.
      for LabelIndex := 0 to Item.ChildCount - 2 do
      begin
        Labeled := Item[LabelIndex];
        if (Labeled.Kind = TSyntaxKind.RangeExpr) and (Labeled.ChildCount = 2) then
          Outside := Scope.Values.EvaluateNode(Labeled[0], First) and Scope.Values.EvaluateNode(Labeled[1], Last) and
            (First <= Last) and ((Last < LowValue) or (First > HighValue))
        else
          Outside := Scope.Values.EvaluateNode(Labeled, First) and ((First < LowValue) or (First > HighValue));
        if Outside then
          AReport.Add(TTextRange.Create(Labeled.StartPos, Labeled.EndPos), Format(
            '%s liegt außerhalb des Bereichs von %s; der Zweig wird nie ausgeführt (wie W1018).',
            [Scope.Text(Labeled), TypeName]), TRuleConfidence.High);
      end;
    end;
  end;

  procedure Visit(ANode: TSyntaxNode);
  var
    Index: Integer;
  begin
    if (ANode.Kind = TSyntaxKind.BinaryExpr) and MatchStr(ANode.Name, ['=', '<>', '<', '<=', '>', '>=']) then
      CheckComparison(ANode)
    else if ANode.Kind = TSyntaxKind.CaseStatement then
      CheckCase(ANode);
    for Index := 0 to ANode.ChildCount - 1 do
      Visit(ANode[Index]);
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  Scope := TTypedScope.Create(AContext);
  try
    Visit(AContext.Tree.Root);
  finally
    Scope.Free;
  end;
end;

procedure RegisterTypedExpressionRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TComparisonAlwaysConstantRule.Create);
end;

end.
