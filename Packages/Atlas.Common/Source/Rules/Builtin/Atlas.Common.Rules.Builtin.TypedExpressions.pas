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
//   case-selector-not-ordinal
//                     case über einen nicht ordinalen Ausdruck (#1067, wie E2001):
//                     Strings, Gleitkommazahlen, Klassen und Interfaces; for-Schleife
//                     mit nicht ordinaler Zählvariable (wie E2032); case-Marken und
//                     Array-Grenzen, die Variablen, Felder, Properties, Parameter oder
//                     typisierte Konstanten sind (wie E2026). Korrektur bei Strings
//                     mit lauter String-Marken: case IndexStr(S, […]) of mit den
//                     Positionen als Marken, System.StrUtils in uses.
//   suspicious-string-pointer-cast
//                     PChar bzw. PWideChar auf einen AnsiString, RawByteString oder
//                     UTF8String und PAnsiChar auf einen string, UnicodeString oder
//                     WideString (#1080, wie W1044): Zeiger und Zeichenbreite passen
//                     nicht zusammen. string(PAnsiChar) wandelt korrekt um, ein
//                     Zeiger auf TBytes kann gewollt sein; beides meldet die Regel
//                     nicht. Korrekturen: eigene Variable mit passendem Stringtyp
//                     deklarieren, string(…) bzw. AnsiString(…) um das Argument,
//                     passenden Zeigertyp verwenden.

interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  ComparisonAlwaysConstantRuleId = 'comparison-always-constant';
  ConstantInitializerMismatchRuleId = 'constant-initializer-mismatch';
  CaseSelectorNotOrdinalRuleId = 'case-selector-not-ordinal';
  SuspiciousStringPointerCastRuleId = 'suspicious-string-pointer-cast';

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

  TCaseSelectorNotOrdinalRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Ist der eingebaute Typ ATypeName sicher nicht ordinal (Strings, Gleitkommazahlen)?</summary>
    class function NotOrdinal(const ATypeName: string): Boolean; static;
  end;

  TSuspiciousStringPointerCastRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Zeichenbreite des eingebauten Stringtyps ATypeName: 1 für AnsiString, RawByteString und
    /// UTF8String, 2 für string, UnicodeString und WideString, 0 für andere.</summary>
    class function StringWidth(const ATypeName: string): Integer; static;
  end;

procedure RegisterTypedExpressionRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Semantics.ConstantValues,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Rules.TypedScope,
  Atlas.Text.Lines;

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

  procedure Visit(ARoot: TSyntaxNode);
  var
    Index: Integer;
    Node: TSyntaxNode;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if (Node.Kind = TSyntaxKind.BinaryExpr) and MatchStr(Node.Name, ['=', '<>', '<', '<=', '>', '>=']) then
          CheckComparison(Node)
        else if Node.Kind = TSyntaxKind.CaseStatement then
          CheckCase(Node);
        for Index := Node.ChildCount - 1 downto 0 do
          Pending.Push(Node[Index]);
      end;
    finally
      Pending.Free;
    end;
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

    procedure Search(ARoot: TSyntaxNode);
    var
      Index: Integer;
      Node: TSyntaxNode;
      Pending: TStack<TSyntaxNode>;
    begin
      // Iterativ (Bericht M1).
      Pending := TStack<TSyntaxNode>.Create;
      try
        Pending.Push(ARoot);
        while Pending.Count > 0 do
        begin
          Node := Pending.Pop;
          if (Node.Kind = TSyntaxKind.TypeDecl) and SameText(Node.Name, ASymbol.Name) and
            (Node.StartPos.Line <= ASymbol.SelectionRange.StartPos.Line) and
            (Node.EndPos.Line >= ASymbol.SelectionRange.StartPos.Line) then
          begin
            Found := Node;
            Exit;
          end;
          for Index := Node.ChildCount - 1 downto 0 do
            Pending.Push(Node[Index]);
        end;
      finally
        Pending.Free;
      end;
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
    Node: TSyntaxNode;
    OuterName: string;
    Seen: TList<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1): benannte Typen dieser Datei (TIndex = TBereich) werden in einer Schleife aufgelöst;
    // die Meldung nennt den äußersten Namen. Seen schützt vor Zyklen wie TA = TB; TB = TA.
    AInfo := Default(TIndexInfo);
    Result := False;
    OuterName := '';
    Node := ANode;
    Seen := TList<TSyntaxNode>.Create;
    try
      while (Node <> nil) and not Seen.Contains(Node) do
      begin
        Seen.Add(Node);
        case Node.Kind of
          TSyntaxKind.SubrangeType:
            if (Node.ChildCount = 2) and Scope.Values.EvaluateNode(Node[0], LowValue) and
              Scope.Values.EvaluateNode(Node[1], HighValue) and (HighValue >= LowValue) then
            begin
              AInfo.Count := HighValue - LowValue + 1;
              AInfo.Text := Scope.Text(Node);
              Result := True;
            end;
          TSyntaxKind.EnumType:
            begin
              for Index := 0 to Node.ChildCount - 1 do
                if Node[Index].Kind = TSyntaxKind.Identifier then
                  AInfo.Names := AInfo.Names + [Node[Index].Name]
                else
                  Exit;
              AInfo.Count := Length(AInfo.Names);
              AInfo.Text := Scope.Text(Node);
              Result := AInfo.Count > 0;
            end;
          TSyntaxKind.TypeReference:
            begin
              if (Node.ChildCount > 0) or (Pos('.', Node.Name) > 0) then
                Exit;
              Symbol := Scope.Resolver.Resolve(AContext.Tree, Scope.FileName, Node.StartPos);
              if not Symbol.Found or SameText(Symbol.UnitName, 'System') then
              begin
                // Eingebaute Typen haben keine Deklaration im Quelltext.
                AInfo.Count := BuiltinIndexCount(Node.Name);
                AInfo.Text := Node.Name;
                Result := AInfo.Count > 0;
              end
              else
              begin
                if not Scope.DeclarationSure(Symbol, Node) then
                  Exit;
                // Typ dieser Datei: Die Extraktion aus dem Baum kennt keine Bedingungen, deshalb die Direktiven in
                // der Deklaration selbst prüfen (TypeDeclOf liefert dann nil).
                if ((Symbol.Kind = TResolvedKind.Local) or (Symbol.FileName = '') or SameText(Symbol.FileName,
                  Scope.FileName)) and (TypeDeclOf(Symbol) = nil) then
                  Exit;
                TypeInfo := Scope.Resolver.ResolveType(AContext.Tree, Scope.FileName, Node.StartPos);
                if TypeInfo.Found and (TypeInfo.SymbolKind = TIndexSymbolKind.EnumType) then
                begin
                  Result := Scope.Values.EnumMembers(TypeInfo, AInfo.Names);
                  AInfo.Count := Length(AInfo.Names);
                  AInfo.Text := Node.Name;
                end
                else
                begin
                  // Teilbereich oder Aufzählung als benannter Typ dieser Datei: TIndex = 1..5.
                  if OuterName = '' then
                    OuterName := Node.Name;
                  Node := DeclaredType(TypeDeclOf(Symbol));
                  Continue;
                end;
              end;
            end;
        end;
        Break;
      end;
      if Result and (OuterName <> '') then
        AInfo.Text := OuterName;
    finally
      Seen.Free;
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

  // CheckArray und CheckValue rufen sich gegenseitig auf; die Rekursion bleibt (Bericht M1): jede Ebene ist eine
  // Dimension bzw. ein Elementtyp des deklarierten Arraytyps und ein Klammerpaar der Konstanten, keine Kette.
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

  procedure Visit(ARoot: TSyntaxNode);
  var
    Index: Integer;
    Node: TSyntaxNode;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if (Node.Kind in [TSyntaxKind.ConstDecl, TSyntaxKind.VarDecl]) and (Node.ChildCount >= 2) and
          (Node[Node.ChildCount - 1].Kind = TSyntaxKind.ParenExpr) and not HasConditional(Node) then
          CheckValue(Node[0], Node[Node.ChildCount - 1]);
        for Index := Node.ChildCount - 1 downto 0 do
          Pending.Push(Node[Index]);
      end;
    finally
      Pending.Free;
    end;
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

{ TCaseSelectorNotOrdinalRule }

function TCaseSelectorNotOrdinalRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(CaseSelectorNotOrdinalRuleId, TRuleSeverity.Error,
    'case oder for über einen nicht ordinalen Typ');
end;

class function TCaseSelectorNotOrdinalRule.NotOrdinal(const ATypeName: string): Boolean;
begin
  Result := MatchText(ATypeName, ['string', 'UnicodeString', 'AnsiString', 'WideString', 'ShortString',
    'RawByteString', 'UTF8String', 'Double', 'Single', 'Extended', 'Real', 'Currency', 'Comp', 'Real48']);
end;

procedure TCaseSelectorNotOrdinalRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Scope: TTypedScope;
  Tokens: TArray<TPascalToken>;

  /// <summary>Name des Typs, wenn ATypeInfo sicher nicht ordinal ist; '' sonst.</summary>
  function NonOrdinalName(const ATypeInfo: TResolvedSymbol): string;
  begin
    Result := '';
    if not ATypeInfo.Found then
      Exit;
    if (ATypeInfo.Builtin or SameText(ATypeInfo.UnitName, 'System')) and NotOrdinal(ATypeInfo.Name) then
      Result := ATypeInfo.Name
    else if not ATypeInfo.Builtin and (ATypeInfo.SymbolKind in [TIndexSymbolKind.ClassType,
      TIndexSymbolKind.InterfaceType]) then
      Result := ATypeInfo.Name;
  end;

  /// <summary>Korrektur case IndexStr(S, ['a', 'b']) of, wenn jede Marke ein String-Literal ist.</summary>
  function IndexStrFix(ACase: TSyntaxNode; const ATypeName: string; out AFix: TRuleFix): Boolean;
  var
    ItemIndex, LabelIndex, Position: Integer;
    Item, Labeled, Selector: TSyntaxNode;
    Literals: TArray<string>;
    Edits: TArray<TTextEdit>;
    UsesEdit: TTextEdit;
  begin
    Result := False;
    if not MatchText(ATypeName, ['string', 'UnicodeString']) then
      Exit;
    Selector := ACase[0];
    Literals := nil;
    Edits := nil;
    Position := 0;
    for ItemIndex := 1 to ACase.ChildCount - 1 do
    begin
      Item := ACase[ItemIndex];
      if Item.Kind <> TSyntaxKind.CaseItem then
        Continue;
      for LabelIndex := 0 to Item.ChildCount - 2 do
      begin
        Labeled := Item[LabelIndex];
        if (Labeled.Kind <> TSyntaxKind.Literal) or not StartsStr('''', Labeled.Name) then
          Exit;
        Literals := Literals + [Scope.Text(Labeled)];
        Edits := Edits + [TTextEdit.Create(TTextRange.Create(Labeled.StartPos, Labeled.EndPos), IntToStr(Position))];
        Inc(Position);
      end;
    end;
    if Literals = nil then
      Exit;
    Edits := [TTextEdit.Create(TTextRange.Create(Selector.StartPos, Selector.EndPos), Format('IndexStr(%s, [%s])',
      [Scope.Text(Selector), string.Join(', ', Literals)]))] + Edits;
    if not TUsesClauses.IsUsed(TUsesClauses.UsedUnits(Tokens), 'System.StrUtils', AContext.Namespaces) then
    begin
      if not TUsesClauses.AddUnit(Tokens, ACase.StartOffset, 'System.StrUtils', TTextLines.LineBreakOf(AContext.Text),
        UsesEdit) then
        Exit;
      Edits := Edits + [UsesEdit];
    end;
    AFix := TRuleFix.Create('In case IndexStr(…) of umwandeln', Edits);
    Result := True;
  end;

  procedure CheckCase(ANode: TSyntaxNode);
  var
    Selector: TSyntaxNode;
    Symbol, TypeInfo: TResolvedSymbol;
    Name: string;
    Fix: TRuleFix;
    Fixes: TArray<TRuleFix>;
  begin
    if ANode.ChildCount = 0 then
      Exit;
    Selector := Unwrapped(ANode[0]);
    if not Scope.SureType(Selector, Symbol, TypeInfo) then
      Exit;
    Name := NonOrdinalName(TypeInfo);
    if Name = '' then
      Exit;
    Fixes := nil;
    if IndexStrFix(ANode, Name, Fix) then
      Fixes := [Fix];
    AReport.Add(TTextRange.Create(ANode[0].StartPos, ANode[0].EndPos), Format(
      'case braucht einen ordinalen Typ; %s ist %s (wie E2001).', [Scope.Text(ANode[0]), Name]),
      TRuleConfidence.High, Fixes);
  end;

  procedure CheckFor(ANode: TSyntaxNode);
  var
    Index: Integer;
    Variable: TPascalToken;
    Owner, TypeInfo: TResolvedSymbol;
    TypeFound: Boolean;
    Name: string;
  begin
    // for [var] I [: Typ] := …: der Name ist das erste Bezeichner-Token nach for bzw. var.
    Index := TConstantValues.TokenFrom(Tokens, ANode.StartOffset);
    while (Index <= High(Tokens)) and (Tokens[Index].Kind <> TPascalTokenKind.Identifier) do
      Inc(Index);
    if (Index > High(Tokens)) or not SameText(Tokens[Index].Text, ANode.Name) then
      Exit;
    Variable := Tokens[Index];
    if (ANode.ChildCount > 0) and (ANode[0].Kind = TSyntaxKind.TypeReference) then
    begin
      // for var X: Double := …
      if (ANode[0].ChildCount > 0) or (Pos('.', ANode[0].Name) > 0) then
        Exit;
      if NotOrdinal(ANode[0].Name) then
        Name := ANode[0].Name
      else
      begin
        if not Scope.Resolver.ChainType(AContext.Tree, Scope.FileName, [ANode[0].Name], ANode[0].StartOffset, Owner,
          TypeInfo, TypeFound) or not TypeFound or not Scope.DeclarationSure(Owner, ANode) then
          Exit;
        Name := NonOrdinalName(TypeInfo);
      end;
    end
    else
    begin
      if not Scope.Resolver.ChainType(AContext.Tree, Scope.FileName, [ANode.Name], Variable.Offset, Owner, TypeInfo,
        TypeFound) or not TypeFound or Owner.IsType or not Scope.DeclarationSure(Owner, ANode) then
        Exit;
      Name := NonOrdinalName(TypeInfo);
    end;
    if Name <> '' then
      AReport.Add(TTextRange.Create(Variable.StartPos, Variable.EndPos), Format(
        'for braucht eine ordinale Zählvariable; %s ist %s (wie E2032).', [ANode.Name, Name]), TRuleConfidence.High);
  end;

  /// <summary>"eine Variable", "ein Feld" … wenn ASymbol sicher keine echte Konstante ist; '' sonst.</summary>
  function NotConstant(const ASymbol: TResolvedSymbol): string;
  begin
    Result := '';
    if ASymbol.IsParameter then
      Result := 'ein Parameter'
    else
      case ASymbol.SymbolKind of
        TIndexSymbolKind.Variable:
          Result := 'eine Variable';
        TIndexSymbolKind.Field:
          Result := 'ein Feld';
        TIndexSymbolKind.Property_:
          Result := 'eine Property';
        TIndexSymbolKind.Constant:
          if ASymbol.TypeName <> '' then
            Result := 'eine typisierte Konstante';
      end;
  end;

  /// <summary>Meldet AExpr (case-Marke bzw. Arraygrenze), wenn es ein Name für etwas Veränderliches ist.</summary>
  procedure CheckConstant(AExpr: TSyntaxNode; const AWhat: string);
  var
    Symbol, TypeInfo: TResolvedSymbol;
    TypeFound: Boolean;
    Kind: string;
  begin
    if AExpr.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess] then
    begin
      if not Scope.Resolver.NodeType(AContext.Tree, Scope.FileName, AExpr, Symbol, TypeInfo, TypeFound) then
        Exit;
    end
    else if (AExpr.Kind = TSyntaxKind.TypeReference) and (AExpr.ChildCount = 0) and (Pos('.', AExpr.Name) = 0) then
      Symbol := Scope.Resolver.Resolve(AContext.Tree, Scope.FileName, AExpr.StartPos)
    else
      Exit;
    if not Symbol.Found or (Symbol.Kind = TResolvedKind.UnitName) or not Scope.DeclarationSure(Symbol, AExpr) then
      Exit;
    Kind := NotConstant(Symbol);
    if Kind <> '' then
      AReport.Add(TTextRange.Create(AExpr.StartPos, AExpr.EndPos), Format('%s %s ist %s, keine Konstante (wie E2026).',
        [AWhat, Scope.Text(AExpr), Kind]), TRuleConfidence.High);
  end;

  procedure CheckLabels(ANode: TSyntaxNode);
  var
    ItemIndex, LabelIndex: Integer;
    Item, Labeled: TSyntaxNode;
  begin
    for ItemIndex := 1 to ANode.ChildCount - 1 do
    begin
      Item := ANode[ItemIndex];
      if Item.Kind <> TSyntaxKind.CaseItem then
        Continue;
      for LabelIndex := 0 to Item.ChildCount - 2 do
      begin
        Labeled := Item[LabelIndex];
        if (Labeled.Kind = TSyntaxKind.RangeExpr) and (Labeled.ChildCount = 2) then
        begin
          CheckConstant(Unwrapped(Labeled[0]), 'Die case-Marke');
          CheckConstant(Unwrapped(Labeled[1]), 'Die case-Marke');
        end
        else
          CheckConstant(Unwrapped(Labeled), 'Die case-Marke');
      end;
    end;
  end;

  procedure CheckBounds(AArray: TSyntaxNode);
  var
    Index: Integer;
    Bound: TSyntaxNode;
  begin
    for Index := 0 to AArray.ChildCount - 2 do
    begin
      Bound := AArray[Index];
      if (Bound.Kind = TSyntaxKind.SubrangeType) and (Bound.ChildCount = 2) then
      begin
        CheckConstant(Unwrapped(Bound[0]), 'Die Arraygrenze');
        CheckConstant(Unwrapped(Bound[1]), 'Die Arraygrenze');
      end;
    end;
  end;

  procedure Visit(ARoot: TSyntaxNode);
  var
    Index: Integer;
    Node: TSyntaxNode;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        case Node.Kind of
          TSyntaxKind.CaseStatement:
            begin
              CheckCase(Node);
              CheckLabels(Node);
            end;
          TSyntaxKind.ForStatement:
            CheckFor(Node);
          TSyntaxKind.ArrayType:
            CheckBounds(Node);
        end;
        for Index := Node.ChildCount - 1 downto 0 do
          Pending.Push(Node[Index]);
      end;
    finally
      Pending.Free;
    end;
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

{ TSuspiciousStringPointerCastRule }

function TSuspiciousStringPointerCastRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(SuspiciousStringPointerCastRuleId, TRuleSeverity.Warning,
    'Zeiger und Zeichenbreite eines Strings passen nicht zusammen');
end;

class function TSuspiciousStringPointerCastRule.StringWidth(const ATypeName: string): Integer;
begin
  Result := 0;
  if MatchText(ATypeName, ['AnsiString', 'RawByteString', 'UTF8String']) then
    Result := 1
  else if MatchText(ATypeName, ['string', 'UnicodeString', 'WideString']) then
    Result := 2;
end;

procedure TSuspiciousStringPointerCastRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Scope: TTypedScope;
  Tokens: TArray<TPascalToken>;

  /// <summary>Nächstes Token ab AIndex, das kein Kommentar ist; Length(Tokens) am Ende.</summary>
  function NextToken(AIndex: Integer): Integer;
  begin
    Result := AIndex;
    while (Result <= High(Tokens)) and (Tokens[Result].Kind = TPascalTokenKind.Comment) do
      Inc(Result);
  end;

  /// <summary>Korrektur "Pfad als string deklarieren": nur für eine Variable dieser Datei, die allein mit
  /// "Name: Typ" deklariert ist, wobei Typ einer der Stringtypen der Breite AWidth ist.</summary>
  function DeclarationFix(const ASymbol: TResolvedSymbol; AWidth: Integer; out AFix: TRuleFix): Boolean;
  var
    Index: Integer;
  begin
    Result := False;
    if ASymbol.IsParameter or (ASymbol.SymbolKind <> TIndexSymbolKind.Variable) or ((ASymbol.Kind <>
      TResolvedKind.Local) and not SameText(ASymbol.FileName, Scope.FileName)) then
      Exit;
    Index := Scope.TokenAtPosition(ASymbol.SelectionRange.StartPos);
    if (Index > High(Tokens)) or not SameText(Tokens[Index].Text, ASymbol.Name) then
      Exit;
    // Vor dem Namen kein Komma (A, B: AnsiString änderte beide).
    if (Index > 0) and (Tokens[Index - 1].Text = ',') then
      Exit;
    Index := NextToken(Index + 1);
    if (Index > High(Tokens)) or (Tokens[Index].Text <> ':') then
      Exit;
    Index := NextToken(Index + 1);
    if (Index > High(Tokens)) or (Tokens[Index].Kind <> TPascalTokenKind.Identifier) or
      (StringWidth(Tokens[Index].Text) <> AWidth) then
      Exit;
    if (NextToken(Index + 1) > High(Tokens)) or not MatchStr(Tokens[NextToken(Index + 1)].Text, [';', '=', ':=']) then
      Exit;
    AFix := TRuleFix.Create(Format('%s als string deklarieren', [ASymbol.Name]),
      [TTextEdit.Create(TTextRange.Create(Tokens[Index].StartPos, Tokens[Index].EndPos), 'string')]);
    Result := True;
  end;

  procedure CheckCast(ANode: TSyntaxNode);
  var
    Argument: TSyntaxNode;
    Symbol, TypeInfo: TResolvedSymbol;
    PointerWidth, Width: Integer;
    Message, Conversion, OtherPointer: string;
    Fix: TRuleFix;
    Fixes: TArray<TRuleFix>;
  begin
    // PChar(X): Callee und genau ein Argument.
    if ANode.ChildCount <> 2 then
      Exit;
    if MatchText(ANode.Name, ['PChar', 'PWideChar']) then
      PointerWidth := 2
    else if SameText(ANode.Name, 'PAnsiChar') then
      PointerWidth := 1
    else
      Exit;
    Argument := Unwrapped(ANode[1]);
    if not Scope.SureType(Argument, Symbol, TypeInfo) then
      Exit;
    if not TypeInfo.Builtin and not SameText(TypeInfo.UnitName, 'System') then
      Exit;
    Width := StringWidth(TypeInfo.Name);
    if (Width = 0) or (Width = PointerWidth) then
      Exit;
    Fixes := nil;
    if PointerWidth = 2 then
    begin
      Message := Format('%s zeigt auf WideChar, %s ist %s; die API liest Datenmüll (wie W1044).',
        [ANode.Name, Scope.Text(Argument), TypeInfo.Name]);
      if DeclarationFix(Symbol, Width, Fix) then
        Fixes := [Fix];
      Conversion := 'string';
      OtherPointer := 'PAnsiChar';
    end
    else
    begin
      Message := Format('%s zeigt auf AnsiChar, %s ist %s; die API liest nur das erste Zeichen (wie W1044).',
        [ANode.Name, Scope.Text(Argument), TypeInfo.Name]);
      Conversion := 'AnsiString';
      OtherPointer := 'PChar';
    end;
    Fix := TRuleFix.Create(Format('In %s umwandeln: %s(%s(…))', [Conversion, ANode.Name, Conversion]),
      [TTextEdit.Create(TTextRange.Create(ANode[1].StartPos, ANode[1].EndPos), Format('%s(%s)', [Conversion,
      Scope.Text(ANode[1])]))]);
    Fix.Alternative := Fixes <> nil;
    Fixes := Fixes + [Fix];
    Fix := TRuleFix.Create(Format('Passenden Zeigertyp verwenden: %s', [OtherPointer]),
      [TTextEdit.Create(TTextRange.Create(ANode[0].StartPos, ANode[0].EndPos), OtherPointer)]);
    Fix.Alternative := True;
    Fixes := Fixes + [Fix];
    AReport.Add(TTextRange.Create(ANode.StartPos, ANode.EndPos), Message, TRuleConfidence.High, Fixes);
  end;

  procedure Visit(ARoot: TSyntaxNode);
  var
    Index: Integer;
    Node: TSyntaxNode;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if Node.Kind = TSyntaxKind.Call then
          CheckCast(Node);
        for Index := Node.ChildCount - 1 downto 0 do
          Pending.Push(Node[Index]);
      end;
    finally
      Pending.Free;
    end;
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
  ARegistry.Register(TCaseSelectorNotOrdinalRule.Create);
  ARegistry.Register(TSuspiciousStringPointerCastRule.Create);
end;

end.
