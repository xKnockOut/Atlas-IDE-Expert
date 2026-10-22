unit Atlas.Common.Rules.Builtin.Constants;

// Regeln für Konstanten und Zahlen (#909, Gruppe Compiler vorab):
//   constant-expression-error  Fehler in einem konstanten Ausdruck (#992):
//                              Division durch null mit bekannten Operanden
//                              (E2098), Überlauf über den Bereich von Int64
//                              und UInt64 hinaus (E2099), Untergrenze über
//                              der Obergrenze eines Bereichs (array[5..1],
//                              E2011), Konstante außerhalb eines ganzzahligen
//                              Typs fester Größe bzw. eines Teilbereichstyps
//                              (W1012) und Hex-, Binär- oder Oktalliterale
//                              über 64 Bit (E2102).
//
// Ausgewertet wird mit Semantics.ConstantValues (Literale, Konstanten auch aus
// anderen Units, SizeOf/High/Low von Typen fester Größe). Konstanten aus einem
// {$IF}-Zweig, den die Stelle nicht sicher mit übersetzt, gelten als unbekannt.

interface

uses
  System.SysUtils,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  ConstantExpressionErrorRuleId = 'constant-expression-error';

type
  TConstantExpressionErrorRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Ist das Zahl-Token ATokenText ein Hex-, Binär- oder Oktalliteral, das nicht in 64 Bit passt
    /// (wie E2102)? Dezimalzahlen macht Delphi zu Gleitkommazahlen, sie zählen nicht.</summary>
    class function TooLargeLiteral(const ATokenText: string): Boolean; static;
  end;

procedure RegisterConstantRules(const ARegistry: TRuleRegistry);

implementation

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Semantics.OrdinalConstants,
  Atlas.Common.Semantics.ConstantValues;

/// <summary>Wertebereich eines ganzzahligen Typs fester Größe (Byte … Int64); False bei Zeichen, Boolean,
/// Gleitkomma, UInt64 und unbekannten Typen.</summary>
function IntegerRange(const ATypeName: string; out ALow, AHigh: Int64): Boolean;
var
  Name: string;
  HighKnown: Boolean;
  Size: Integer;
begin
  Name := LowerCase(ATypeName);
  if Name.StartsWith('system.') then
    Name := Copy(Name, Length('system.') + 1, MaxInt);
  Result := (Name <> 'char') and (Name <> 'widechar') and (Name <> 'ansichar') and (Name <> 'boolean') and
    (Name <> 'bytebool') and TOrdinalConstants.FixedType(Name, ALow, AHigh, HighKnown, Size) and HighKnown;
end;

/// <summary>Bereich eines Teilbereichstyps aus seiner Signatur ("TProzent = 0..100"); nur mit Zahlen.</summary>
function SubrangeOf(const ASignature: string; out ALow, AHigh: Int64): Boolean;
var
  Text: string;
  Equals, Dots: Integer;
begin
  Result := False;
  Equals := Pos('=', ASignature);
  if Equals = 0 then
    Exit;
  Text := Trim(Copy(ASignature, Equals + 1, MaxInt));
  if Text.EndsWith(';') then
    Text := Trim(Copy(Text, 1, Length(Text) - 1));
  Dots := Pos('..', Text);
  if Dots = 0 then
    Exit;
  Result := TOrdinalConstants.Evaluate(Copy(Text, 1, Dots - 1), nil, ALow) and
    TOrdinalConstants.Evaluate(Copy(Text, Dots + 2, MaxInt), nil, AHigh) and (ALow <= AHigh);
end;

{ TConstantExpressionErrorRule }

function TConstantExpressionErrorRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(ConstantExpressionErrorRuleId, TRuleSeverity.Error,
    'Fehler in einem konstanten Ausdruck');
end;

class function TConstantExpressionErrorRule.TooLargeLiteral(const ATokenText: string): Boolean;
var
  Text: string;
  Bits, Index, Digit: Integer;
  Significant: Boolean;
begin
  Result := False;
  Text := StringReplace(ATokenText, '_', '', [rfReplaceAll]);
  if Length(Text) < 2 then
    Exit;
  case Text[1] of
    '$':
      Bits := 4;
    '%':
      Bits := 1;
    '&':
      Bits := 3;
  else
    Exit;
  end;
  // Führende Nullen zählen nicht; danach bestimmt die erste Ziffer, wie viele Bits sie belegt.
  Significant := False;
  Digit := 0;
  for Index := 2 to Length(Text) do
  begin
    if not Significant and (Text[Index] = '0') then
      Continue;
    if not Significant then
    begin
      Significant := True;
      case Text[Index] of
        '0'..'9':
          Digit := Ord(Text[Index]) - Ord('0');
        'a'..'f':
          Digit := Ord(Text[Index]) - Ord('a') + 10;
        'A'..'F':
          Digit := Ord(Text[Index]) - Ord('A') + 10;
      else
        Exit;
      end;
      // Bits der ersten Ziffer plus volle Bits aller weiteren.
      Bits := Bits * (Length(Text) - Index);
      while Digit > 0 do
      begin
        Inc(Bits);
        Digit := Digit shr 1;
      end;
      Exit(Bits > 64);
    end;
  end;
end;

procedure TConstantExpressionErrorRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  FileName: string;
  Resolver: TNameResolver;
  Values: TConstantValues;

  function NodeRange(ANode: TSyntaxNode): TTextRange;
  begin
    Result := TTextRange.Create(ANode.StartPos, ANode.EndPos);
  end;

  /// <summary>Wert des Knotens; False, wenn nicht sicher bekannt.</summary>
  function ValueOf(ANode: TSyntaxNode; out AValue: Int64): Boolean;
  begin
    Result := Values.Check(ANode, AValue) = TOrdinalStatus.Value;
  end;

  /// <summary>Wurzel eines Ausdrucks: kein Operand eines umgebenden Operators oder einer Klammer.</summary>
  function IsExpressionRoot(ANode: TSyntaxNode): Boolean;
  begin
    Result := (ANode.Parent = nil) or not (ANode.Parent.Kind in [TSyntaxKind.BinaryExpr, TSyntaxKind.UnaryExpr,
      TSyntaxKind.ParenExpr]);
  end;

  procedure CheckDivision(ANode: TSyntaxNode);
  var
    Left, Right: Int64;
    Message: string;
  begin
    // Erst der Teiler: meist ist er keine Null, dann bleibt die linke Seite unausgewertet.
    if (ANode.ChildCount <> 2) or not (SameText(ANode.Name, 'div') or SameText(ANode.Name, 'mod')) or
      not ValueOf(ANode[1], Right) or (Right <> 0) or not ValueOf(ANode[0], Left) then
      Exit;
    if ANode[1].Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess] then
      Message := Format('Division durch null in einem konstanten Ausdruck (%s = 0, wie E2098).',
        [Copy(AContext.Text, ANode[1].StartOffset + 1, ANode[1].EndOffset - ANode[1].StartOffset)])
    else
      Message := 'Division durch null in einem konstanten Ausdruck (wie E2098).';
    AReport.Add(NodeRange(ANode), Message, TRuleConfidence.High);
  end;

  /// <summary>Kann der Ausdruck überhaupt überlaufen? Nur mit Multiplikation, großen Zahlen oder High/Low; so
  /// bleiben die meisten Ausdrücke ohne Namensauflösung.</summary>
  function MayOverflow(ANode: TSyntaxNode): Boolean;
  var
    Index: Integer;
  begin
    Result := ((ANode.Kind = TSyntaxKind.BinaryExpr) and (ANode.Name = '*')) or
      ((ANode.Kind = TSyntaxKind.Literal) and (Length(ANode.Name) >= 10)) or
      ((ANode.Kind = TSyntaxKind.Identifier) and (SameText(ANode.Name, 'High') or SameText(ANode.Name, 'Low')));
    Index := 0;
    while not Result and (Index < ANode.ChildCount) do
    begin
      Result := MayOverflow(ANode[Index]);
      Inc(Index);
    end;
  end;

  procedure CheckOverflow(ANode: TSyntaxNode);
  var
    Value: Int64;
  begin
    if IsExpressionRoot(ANode) and MayOverflow(ANode) and
      (Values.Check(ANode, Value) = TOrdinalStatus.Overflow) then
      AReport.Add(NodeRange(ANode),
        'Überlauf in einem konstanten Ausdruck: Das Ergebnis passt in keinen Ganzzahltyp (wie E2099).',
        TRuleConfidence.High);
  end;

  procedure CheckSubrange(ANode: TSyntaxNode);
  var
    Lowest, Highest: Int64;
  begin
    if (ANode.ChildCount = 2) and ValueOf(ANode[0], Lowest) and ValueOf(ANode[1], Highest) and
      (Lowest > Highest) then
      AReport.Add(NodeRange(ANode), Format('Die Untergrenze %d liegt über der Obergrenze %d (wie E2011).',
        [Lowest, Highest]), TRuleConfidence.High);
  end;

  /// <summary>Bereich des Typs ATypeName (Typ fester Größe oder Teilbereichstyp, aufgelöst an ANode).</summary>
  function TargetRange(ATypeNode: TSyntaxNode; const ATypeName: string; out ALow, AHigh: Int64): Boolean;
  var
    TypeSymbol: TResolvedSymbol;
  begin
    if IntegerRange(ATypeName, ALow, AHigh) then
      Exit(True);
    Result := False;
    if (ATypeNode = nil) or (ATypeName = '') or (Pos('<', ATypeName) > 0) then
      Exit;
    TypeSymbol := Resolver.ResolveType(AContext.Tree, FileName, ATypeNode.StartPos);
    Result := TypeSymbol.Found and SubrangeOf(TypeSymbol.Signature, ALow, AHigh);
  end;

  procedure ReportRange(AValueNode: TSyntaxNode; AValue, ALow, AHigh: Int64; const ATypeName: string);
  begin
    AReport.AddWithSeverity(NodeRange(AValueNode), Format('%d liegt außerhalb des Bereichs von %s (%d..%d, wie W1012).',
      [AValue, ATypeName, ALow, AHigh]), TRuleSeverity.Warning, nil);
  end;

  /// <summary>Typisierte Konstante bzw. initialisierte Variable: Typ und Wert sind Kinder der Deklaration.</summary>
  procedure CheckInitializer(ADecl: TSyntaxNode);
  var
    TypeNode, ValueNode: TSyntaxNode;
    Value, Lowest, Highest: Int64;
  begin
    if (ADecl.ChildCount < 2) or (ADecl[0].Kind <> TSyntaxKind.TypeReference) or (ADecl[0].ChildCount > 0) then
      Exit;
    TypeNode := ADecl[0];
    ValueNode := ADecl[ADecl.ChildCount - 1];
    if (ValueNode.Kind = TSyntaxKind.TypeReference) or not ValueOf(ValueNode, Value) or
      not TargetRange(TypeNode, TypeNode.Name, Lowest, Highest) then
      Exit;
    if (Value < Lowest) or (Value > Highest) then
      ReportRange(ValueNode, Value, Lowest, Highest, TypeNode.Name);
  end;

  procedure CheckAssignment(AStatement: TSyntaxNode);
  var
    Target, Source: TSyntaxNode;
    Symbol, TypeInfo: TResolvedSymbol;
    TypeFound: Boolean;
    Value, Lowest, Highest: Int64;
    TypeName: string;
  begin
    if AStatement.ChildCount <> 2 then
      Exit;
    Target := AStatement[0];
    Source := AStatement[1];
    if not (Target.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) or
      not (Source.Kind in [TSyntaxKind.Literal, TSyntaxKind.UnaryExpr, TSyntaxKind.BinaryExpr,
      TSyntaxKind.ParenExpr, TSyntaxKind.Identifier, TSyntaxKind.MemberAccess, TSyntaxKind.Call]) or
      not ValueOf(Source, Value) then
      Exit;
    // 0..127 passt in jeden ganzzahligen Typ; Teilbereichstypen prüft die Regel nur ab hier, damit nicht jede
    // Zuweisung einer kleinen Zahl die Namensauflösung braucht.
    if (Value >= 0) and (Value <= 127) then
      Exit;
    if not Resolver.NodeType(AContext.Tree, FileName, Target, Symbol, TypeInfo, TypeFound) or
      not (Symbol.SymbolKind in [TIndexSymbolKind.Variable, TIndexSymbolKind.Field]) then
      Exit;
    TypeName := Symbol.TypeName;
    if not IntegerRange(TypeName, Lowest, Highest) then
    begin
      if not TypeFound or not SubrangeOf(TypeInfo.Signature, Lowest, Highest) then
        Exit;
      TypeName := TypeInfo.Name;
    end;
    if (Value < Lowest) or (Value > Highest) then
      ReportRange(Source, Value, Lowest, Highest, TypeName);
  end;

  procedure Visit(ANode: TSyntaxNode);
  var
    Index: Integer;
  begin
    case ANode.Kind of
      TSyntaxKind.BinaryExpr:
        begin
          CheckDivision(ANode);
          CheckOverflow(ANode);
        end;
      TSyntaxKind.UnaryExpr:
        CheckOverflow(ANode);
      TSyntaxKind.SubrangeType:
        CheckSubrange(ANode);
      TSyntaxKind.ConstDecl, TSyntaxKind.VarDecl:
        CheckInitializer(ANode);
      TSyntaxKind.AssignStatement:
        CheckAssignment(ANode);
    end;
    for Index := 0 to ANode.ChildCount - 1 do
      Visit(ANode[Index]);
  end;

var
  Token: TPascalToken;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  for Token in AContext.Tree.Tokens do
    if (Token.Kind = TPascalTokenKind.Number) and TooLargeLiteral(Token.Text) then
      AReport.Add(TTextRange.Create(Token.StartPos, Token.EndPos),
        Format('Ganzzahlkonstante zu groß: %s passt nicht in 64 Bit (wie E2102).', [Token.Text]),
        TRuleConfidence.High);
  FileName := AContext.FileName;
  if FileName = '' then
    FileName := AContext.RelativePath;
  if FileName = '' then
    FileName := AContext.UnitName + '.pas';
  Resolver := TNameResolver.Create(AContext.Index, AContext.EnsureUnit);
  try
    Resolver.Namespaces := AContext.Namespaces;
    Resolver.PinTree(AContext.Tree, FileName);
    try
      Values := TConstantValues.Create(AContext.Tree, FileName, AContext.Index, Resolver);
      try
        Visit(AContext.Tree.Root);
      finally
        Values.Free;
      end;
    finally
      Resolver.UnpinTree;
    end;
  finally
    Resolver.Free;
  end;
end;

procedure RegisterConstantRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TConstantExpressionErrorRule.Create);
end;

end.
