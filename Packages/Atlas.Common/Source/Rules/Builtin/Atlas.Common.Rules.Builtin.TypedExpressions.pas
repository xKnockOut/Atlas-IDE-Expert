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
//   constant-initializer-mismatch
//                     Typisierte Konstante bzw. initialisierte Variable vom
//                     statischen Array-Typ mit mehr oder weniger Elementen als der
//                     Indexbereich (#1015, wie E2072), auch je Dimension und in
//                     benannten Array-Typen der Datei; Record-Konstanten mit
//                     Feldern in anderer Reihenfolge als deklariert (wie E2083).
//                     Indexbereiche: Teilbereiche über Semantics.ConstantValues,
//                     Aufzählungen (ohne eigene Werte und bedingte Werte), Boolean,
//                     Byte, Char usw. Deklarationen mit bedingten Direktiven gelten
//                     als unsicher. Korrekturen: fehlende Einträge mit Platzhalter
//                     ergänzen (Name des Aufzählungswerts als Kommentar), Felder in
//                     die Reihenfolge der Deklaration bringen.

interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  ComparisonAlwaysConstantRuleId = 'comparison-always-constant';
  ConstantInitializerMismatchRuleId = 'constant-initializer-mismatch';

type
  TComparisonAlwaysConstantRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Ergebnis von "X AOperator AValue" für X im Bereich ALow..AHigh: 1 immer wahr, 0 immer falsch,
    /// -1 abhängig von X. AOperator ist = &lt;&gt; &lt; &lt;= &gt; &gt;=.</summary>
    class function Outcome(const AOperator: string; AValue, ALow, AHigh: Int64): Integer; static;
  end;

  TConstantInitializerMismatchRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Platzhalter für ein fehlendes Element vom Typ ATypeName ('' = keiner bekannt): '' für Strings,
    /// 0 für Zahlen, False, #0, nil für Zeiger.</summary>
    class function Placeholder(const ATypeName: string): string; static;
    /// <summary>Zahl der Werte des eingebauten ordinalen Typs ATypeName als Indexbereich (Boolean 2, Byte
    /// 256, Char 65536 …); 0 für andere.</summary>
    class function BuiltinIndexCount(const ATypeName: string): Int64; static;
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
  Atlas.Common.Pascal.Lexer,
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

{ TConstantInitializerMismatchRule }

function TConstantInitializerMismatchRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(ConstantInitializerMismatchRuleId, TRuleSeverity.Error,
    'Initialisierung einer Konstanten passt nicht');
end;

class function TConstantInitializerMismatchRule.Placeholder(const ATypeName: string): string;
begin
  case IndexText(ATypeName, ['string', 'UnicodeString', 'AnsiString', 'WideString', 'ShortString', 'RawByteString',
    'UTF8String', 'Integer', 'Cardinal', 'Int64', 'UInt64', 'NativeInt', 'NativeUInt', 'Byte', 'Word', 'ShortInt',
    'SmallInt', 'LongInt', 'LongWord', 'Double', 'Single', 'Extended', 'Currency', 'Real', 'Boolean', 'Char',
    'WideChar', 'AnsiChar', 'Pointer', 'PChar', 'PWideChar', 'PAnsiChar']) of
    0..6:
      Result := '''''';
    7..23:
      Result := '0';
    24:
      Result := 'False';
    25..27:
      Result := '#0';
    28..31:
      Result := 'nil';
  else
    Result := '';
  end;
end;

class function TConstantInitializerMismatchRule.BuiltinIndexCount(const ATypeName: string): Int64;
begin
  case IndexText(ATypeName, ['Boolean', 'Byte', 'UInt8', 'ShortInt', 'Int8', 'AnsiChar', 'Word', 'UInt16',
    'SmallInt', 'Int16', 'Char', 'WideChar']) of
    0:
      Result := 2;
    1..5:
      Result := 256;
    6..11:
      Result := 65536;
  else
    Result := 0;
  end;
end;

/// <summary>"1 Wert" bzw. "3 Werte".</summary>
function Counted(ACount: Int64; const AOne, AMany: string): string;
begin
  if ACount = 1 then
    Result := '1 ' + AOne
  else
    Result := IntToStr(ACount) + ' ' + AMany;
end;

procedure TConstantInitializerMismatchRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
type
  /// <summary>Indexbereich einer Dimension: Zahl der Werte, bei Aufzählungen ihre Namen, Text für die Meldung.
  /// </summary>
  TIndexInfo = record
    Count: Int64;
    Names: TArray<string>;
    Text: string;
  end;
var
  Scope: TTypedScope;
  Tokens: TArray<TPascalToken>;

  /// <summary>Steht in ANode eine bedingte Direktive ({$IFDEF}, {$ELSE} …)? Dann ist der Inhalt unsicher.
  /// </summary>
  function HasConditional(ANode: TSyntaxNode): Boolean;
  var
    Index: Integer;
    Name: string;
  begin
    Result := False;
    Index := TConstantValues.TokenFrom(Tokens, ANode.StartOffset);
    while (Index <= High(Tokens)) and (Tokens[Index].Offset < ANode.EndOffset) do
    begin
      if Tokens[Index].Kind = TPascalTokenKind.Directive then
      begin
        Name := TPascalLexer.DirectiveName(Tokens[Index].Text);
        if StartsText('IF', Name) or StartsText('ELSE', Name) or SameText(Name, 'ENDIF') then
          Exit(True);
      end;
      Inc(Index);
    end;
  end;

  /// <summary>Deklaration (TypeDecl) des Typs ASymbol in diesem Baum; nil in anderen Units, ohne Treffer oder mit
  /// bedingten Direktiven.</summary>
  function TypeDeclOf(const ASymbol: TResolvedSymbol): TSyntaxNode;
  var
    Found: TSyntaxNode;

    procedure Search(ANode: TSyntaxNode);
    var
      Index: Integer;
    begin
      if Found <> nil then
        Exit;
      if (ANode.Kind = TSyntaxKind.TypeDecl) and SameText(ANode.Name, ASymbol.Name) and
        (ANode.StartPos.Line <= ASymbol.SelectionRange.StartPos.Line) and
        (ANode.EndPos.Line >= ASymbol.SelectionRange.StartPos.Line) then
      begin
        Found := ANode;
        Exit;
      end;
      for Index := 0 to ANode.ChildCount - 1 do
        Search(ANode[Index]);
    end;

  begin
    Found := nil;
    if (ASymbol.Kind = TResolvedKind.Local) or (ASymbol.FileName = '') or SameText(ASymbol.FileName,
      Scope.FileName) then
      Search(AContext.Tree.Root);
    if (Found <> nil) and HasConditional(Found) then
      Found := nil;
    Result := Found;
  end;

  /// <summary>Typknoten einer TypeDecl (ohne Typparameter); nil ohne.</summary>
  function DeclaredType(ADecl: TSyntaxNode): TSyntaxNode;
  var
    Index: Integer;
  begin
    Result := nil;
    if ADecl = nil then
      Exit;
    for Index := 0 to ADecl.ChildCount - 1 do
      if not (ADecl[Index].Kind in [TSyntaxKind.GenericParams, TSyntaxKind.Attribute]) then
        Exit(ADecl[Index]);
  end;

  /// <summary>Symbol und Typ eines benannten Typs (TypeReference) an seiner Stelle; False, wenn unbekannt oder
  /// nicht immer mit ANode übersetzt.</summary>
  function NamedType(ARef: TSyntaxNode; out ASymbol, AType: TResolvedSymbol): Boolean;
  begin
    AType := Default(TResolvedSymbol);
    Result := False;
    if (ARef.Kind <> TSyntaxKind.TypeReference) or (ARef.ChildCount > 0) or (Pos('.', ARef.Name) > 0) then
      Exit;
    ASymbol := Scope.Resolver.Resolve(AContext.Tree, Scope.FileName, ARef.StartPos);
    if not ASymbol.Found or not Scope.DeclarationSure(ASymbol, ARef) then
      Exit;
    AType := Scope.Resolver.ResolveType(AContext.Tree, Scope.FileName, ARef.StartPos);
    Result := True;
  end;

  function IndexInfo(ANode: TSyntaxNode; out AInfo: TIndexInfo): Boolean;
  var
    LowValue, HighValue: Int64;
    Index: Integer;
    Symbol, TypeInfo: TResolvedSymbol;
  begin
    AInfo := Default(TIndexInfo);
    Result := False;
    if ANode = nil then
      Exit;
    case ANode.Kind of
      TSyntaxKind.SubrangeType:
        if (ANode.ChildCount = 2) and Scope.Values.EvaluateNode(ANode[0], LowValue) and
          Scope.Values.EvaluateNode(ANode[1], HighValue) and (HighValue >= LowValue) then
        begin
          AInfo.Count := HighValue - LowValue + 1;
          AInfo.Text := Scope.Text(ANode);
          Result := True;
        end;
      TSyntaxKind.EnumType:
        begin
          for Index := 0 to ANode.ChildCount - 1 do
            if ANode[Index].Kind = TSyntaxKind.Identifier then
              AInfo.Names := AInfo.Names + [ANode[Index].Name]
            else
              Exit;
          AInfo.Count := Length(AInfo.Names);
          AInfo.Text := Scope.Text(ANode);
          Result := AInfo.Count > 0;
        end;
      TSyntaxKind.TypeReference:
        begin
          if (ANode.ChildCount > 0) or (Pos('.', ANode.Name) > 0) then
            Exit;
          Symbol := Scope.Resolver.Resolve(AContext.Tree, Scope.FileName, ANode.StartPos);
          if not Symbol.Found or SameText(Symbol.UnitName, 'System') then
          begin
            // Eingebaute Typen haben keine Deklaration im Quelltext.
            AInfo.Count := BuiltinIndexCount(ANode.Name);
            AInfo.Text := ANode.Name;
            Exit(AInfo.Count > 0);
          end;
          if not Scope.DeclarationSure(Symbol, ANode) then
            Exit;
          // Typ dieser Datei: Die Extraktion aus dem Baum kennt keine Bedingungen, deshalb die Direktiven in der
          // Deklaration selbst prüfen (TypeDeclOf liefert dann nil).
          if ((Symbol.Kind = TResolvedKind.Local) or (Symbol.FileName = '') or SameText(Symbol.FileName,
            Scope.FileName)) and (TypeDeclOf(Symbol) = nil) then
            Exit;
          TypeInfo := Scope.Resolver.ResolveType(AContext.Tree, Scope.FileName, ANode.StartPos);
          if TypeInfo.Found and (TypeInfo.SymbolKind = TIndexSymbolKind.EnumType) then
          begin
            Result := Scope.Values.EnumMembers(TypeInfo, AInfo.Names);
            AInfo.Count := Length(AInfo.Names);
            AInfo.Text := ANode.Name;
            Exit;
          end;
          // Teilbereich oder Aufzählung als benannter Typ dieser Datei: TIndex = 1..5.
          Result := IndexInfo(DeclaredType(TypeDeclOf(Symbol)), AInfo);
          if Result then
            AInfo.Text := ANode.Name;
        end;
    end;
  end;

  /// <summary>Typknoten hinter einem benannten Typ dieser Datei (TNamen = array[…] of string); sonst ANode.
  /// ASymbol und AType sind bei benannten Typen gesetzt.</summary>
  function Expanded(ANode: TSyntaxNode; out ASymbol, AType: TResolvedSymbol): TSyntaxNode;
  var
    Inner: TSyntaxNode;
  begin
    Result := ANode;
    ASymbol := Default(TResolvedSymbol);
    AType := Default(TResolvedSymbol);
    if (ANode = nil) or (ANode.Kind <> TSyntaxKind.TypeReference) or not NamedType(ANode, ASymbol, AType) then
      Exit;
    Inner := DeclaredType(TypeDeclOf(ASymbol));
    if (Inner <> nil) and (Inner.Kind in [TSyntaxKind.ArrayType, TSyntaxKind.TypeReference]) and (Inner <> ANode) then
      Result := Inner;
  end;

  /// <summary>Platzhalter für ein Element vom Typ ANode ('' = keiner).</summary>
  function ElementPlaceholder(ANode: TSyntaxNode): string;
  var
    Symbol, TypeInfo: TResolvedSymbol;
  begin
    Result := '';
    if (ANode = nil) or (ANode.Kind <> TSyntaxKind.TypeReference) or (ANode.ChildCount > 0) then
      Exit;
    Result := Placeholder(ANode.Name);
    if Result <> '' then
      Exit;
    if not NamedType(ANode, Symbol, TypeInfo) or not TypeInfo.Found then
      Exit;
    if TypeInfo.SymbolKind in [TIndexSymbolKind.ClassType, TIndexSymbolKind.InterfaceType] then
      Result := 'nil'
    else if TypeInfo.SymbolKind = TIndexSymbolKind.EnumType then
      Result := 'Low(' + ANode.Name + ')'
    else if TypeInfo.Builtin then
      Result := Placeholder(TypeInfo.Name);
  end;

  /// <summary>Text für die fehlenden Einträge ab AGiven: ", ''{stArchiviert}" je Eintrag.</summary>
  function MissingText(const AInfo: TIndexInfo; AGiven: Integer; const APlaceholder: string): string;
  var
    Index: Integer;
  begin
    Result := '';
    for Index := AGiven to Integer(AInfo.Count) - 1 do
    begin
      Result := Result + ', ' + APlaceholder;
      if Index < Length(AInfo.Names) then
        Result := Result + '{' + AInfo.Names[Index] + '}';
    end;
  end;

  procedure CheckValue(ATypeNode, AValue: TSyntaxNode); forward;

  procedure CheckRecord(const AType: TResolvedSymbol; AValue: TSyntaxNode);
  var
    Owner: TUnitIndex;
    Symbol: TIndexSymbol;
    Fields, Given: TArray<string>;
    Positions: TArray<Integer>;
    Index, Field, Earlier, Swap: Integer;
    Container, Text: string;
    Parts: TArray<string>;
    Order: TArray<Integer>;
  begin
    if (AValue.Kind <> TSyntaxKind.ParenExpr) or (AValue.ChildCount = 0) or Odd(AValue.ChildCount) or
      not Scope.Resolver.DeclaringUnit(AType, Owner) then
      Exit;
    Container := AType.QualifiedName;
    Fields := nil;
    for Symbol in Owner.Symbols do
      if (Symbol.Kind = TIndexSymbolKind.Field) and SameText(Symbol.Container, Container) then
      begin
        // Variante Teile und bedingte Felder: Reihenfolge nicht sicher.
        if (Symbol.VariantBranch <> '') or (Symbol.Condition <> '') then
          Exit;
        Fields := Fields + [Symbol.Name];
      end;
    if Fields = nil then
      Exit;
    // (X: 1; Y: 2): Kinder abwechselnd Feldname und Wert.
    Given := nil;
    Positions := nil;
    Index := 0;
    while Index < AValue.ChildCount do
    begin
      if AValue[Index].Kind <> TSyntaxKind.Identifier then
        Exit;
      Field := IndexText(AValue[Index].Name, Fields);
      if Field < 0 then
        Exit;
      Given := Given + [AValue[Index].Name];
      Positions := Positions + [Field];
      Inc(Index, 2);
    end;
    for Index := 1 to High(Positions) do
      if Positions[Index] < Positions[Index - 1] then
      begin
        // Korrektur: die Paare in der Reihenfolge der Deklaration, je Paar der Text aus der Datei.
        Order := nil;
        for Earlier := 0 to High(Positions) do
          Order := Order + [Earlier];
        for Earlier := 0 to High(Order) do
          for Swap := Earlier + 1 to High(Order) do
            if Positions[Order[Swap]] < Positions[Order[Earlier]] then
            begin
              Field := Order[Earlier];
              Order[Earlier] := Order[Swap];
              Order[Swap] := Field;
            end;
        Parts := nil;
        for Earlier := 0 to High(Order) do
          Parts := Parts + [Copy(AContext.Text, AValue[Order[Earlier] * 2].StartOffset + 1,
            AValue[Order[Earlier] * 2 + 1].EndOffset - AValue[Order[Earlier] * 2].StartOffset)];
        Text := string.Join('; ', Parts);
        AReport.Add(TTextRange.Create(AValue[(Index) * 2].StartPos, AValue[Index * 2].EndPos), Format(
          '%s steht in %s vor %s; die Felder müssen in der Reihenfolge der Deklaration stehen (wie E2083).',
          [Given[Index], AType.Name, Given[Index - 1]]), TRuleConfidence.High,
          [TRuleFix.Create('Felder in die Reihenfolge der Deklaration bringen', [TTextEdit.Create(TTextRange.Create(
          AValue[0].StartPos, AValue[AValue.ChildCount - 1].EndPos), Text)])]);
        Exit;
      end;
    // Werte der Felder: verschachtelte Records und Arrays sind hier nicht bekannt.
  end;

  procedure CheckArray(AArray: TSyntaxNode; ADimension: Integer; AValue: TSyntaxNode);
  var
    Dimensions, Index: Integer;
    Info: TIndexInfo;
    Message, Missing, Filler: string;
    Fixes: TArray<TRuleFix>;
    Names: TArray<string>;
    Last: TSyntaxNode;
  begin
    Dimensions := AArray.ChildCount - 1;
    if AValue.Kind <> TSyntaxKind.ParenExpr then
      Exit;
    if ADimension >= Dimensions then
    begin
      // Dynamisches Array: keine Länge, aber Elemente prüfen.
      for Index := 0 to AValue.ChildCount - 1 do
        CheckValue(AArray[AArray.ChildCount - 1], AValue[Index]);
      Exit;
    end;
    if not IndexInfo(AArray[ADimension], Info) then
      Exit;
    if Info.Count <> AValue.ChildCount then
    begin
      Message := Format('%s hat %s, die Konstante %s', [Info.Text, Counted(Info.Count, 'Wert', 'Werte'),
        Counted(AValue.ChildCount, 'Eintrag', 'Einträge')]);
      Names := nil;
      for Index := AValue.ChildCount to Integer(Length(Info.Names)) - 1 do
        Names := Names + [Info.Names[Index]];
      if Length(Names) = 1 then
        Message := Message + '; ' + Names[0] + ' fehlt'
      else if Length(Names) > 3 then
        Message := Message + '; ' + string.Join(', ', Copy(Names, 0, 3)) + ' … fehlen'
      else if Length(Names) > 1 then
        Message := Message + '; ' + string.Join(', ', Names) + ' fehlen';
      Fixes := nil;
      if (Info.Count > AValue.ChildCount) and (AValue.ChildCount > 0) and (ADimension = Dimensions - 1) and
        (Info.Count - AValue.ChildCount <= 64) then
      begin
        Filler := ElementPlaceholder(AArray[AArray.ChildCount - 1]);
        if Filler <> '' then
        begin
          Last := AValue[AValue.ChildCount - 1];
          Missing := MissingText(Info, AValue.ChildCount, Filler);
          Fixes := [TRuleFix.Create('Fehlende Einträge mit Platzhalter ergänzen', [TTextEdit.Create(TTextRange.Create(
            Last.EndPos, Last.EndPos), Missing)])];
        end;
      end;
      AReport.Add(TTextRange.Create(AValue.StartPos, AValue.EndPos), Message + ' (wie E2072).', TRuleConfidence.High,
        Fixes);
      Exit;
    end;
    for Index := 0 to AValue.ChildCount - 1 do
      if ADimension + 1 < Dimensions then
        CheckArray(AArray, ADimension + 1, AValue[Index])
      else
        CheckValue(AArray[AArray.ChildCount - 1], AValue[Index]);
  end;

  procedure CheckValue(ATypeNode, AValue: TSyntaxNode);
  var
    Node: TSyntaxNode;
    Symbol, TypeInfo: TResolvedSymbol;
  begin
    if (ATypeNode = nil) or (AValue = nil) then
      Exit;
    Node := Expanded(ATypeNode, Symbol, TypeInfo);
    if Node.Kind = TSyntaxKind.ArrayType then
      CheckArray(Node, 0, AValue)
    else if (Node.Kind = TSyntaxKind.TypeReference) and TypeInfo.Found and
      (TypeInfo.SymbolKind = TIndexSymbolKind.RecordType) and not TypeInfo.Builtin then
      CheckRecord(TypeInfo, AValue);
  end;

  procedure Visit(ANode: TSyntaxNode);
  var
    Index: Integer;
  begin
    if (ANode.Kind in [TSyntaxKind.ConstDecl, TSyntaxKind.VarDecl]) and (ANode.ChildCount >= 2) and
      (ANode[ANode.ChildCount - 1].Kind = TSyntaxKind.ParenExpr) and not HasConditional(ANode) then
      CheckValue(ANode[0], ANode[ANode.ChildCount - 1]);
    for Index := 0 to ANode.ChildCount - 1 do
      Visit(ANode[Index]);
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  Tokens := AContext.Tree.Tokens;
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
  ARegistry.Register(TConstantInitializerMismatchRule.Create);
end;

end.
