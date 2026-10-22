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
//   default-parameter-invalid  Unzulässiger Standardwert eines Parameters
//                              (#993): mehrere Namen mit einem Standardwert
//                              (A, B: Integer = 0, E2237), Parameter ohne
//                              Standardwert nach einem mit (E2238), var- und
//                              out-Parameter mit Standardwert (E2239), Records
//                              und statische Arrays mit Standardwert (E2268),
//                              Mengen über 4 Byte mit Standardwert (E2146, nur
//                              "kleine Mengen" sind erlaubt; mittlere Konfidenz).
//   signed-unsigned-mix        Vorzeichenbehaftet und vorzeichenlos gemischt
//                              (#1012): Vergleich (W1023) oder Rechnung
//                              (W1024) eines Operanden bis 32 Bit mit Vorzeichen
//                              und eines vorzeichenlosen 32-Bit-Operanden, und
//                              jede Mischung mit UInt64 (Rechnung W1073,
//                              Vergleich W1023). Typen aus der Namensauflösung,
//                              nur bei sicher bekanntem Typ beider Operanden;
//                              Literale zählen nicht. Korrektur: den
//                              vorzeichenlosen Operanden in Int64 umwandeln.
//                              Korrekturen: Parameter einzeln deklarieren;
//                              Parameter mit Standardwert ans Ende verschieben,
//                              auch im zugehörigen Kopf derselben Datei
//                              (Deklaration bzw. Implementierung).
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
  DefaultParameterInvalidRuleId = 'default-parameter-invalid';
  SignedUnsignedMixRuleId = 'signed-unsigned-mix';

type
  TConstantExpressionErrorRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Ist das Zahl-Token ATokenText ein Hex-, Binär- oder Oktalliteral, das nicht in 64 Bit passt
    /// (wie E2102)? Dezimalzahlen macht Delphi zu Gleitkommazahlen, sie zählen nicht.</summary>
    class function TooLargeLiteral(const ATokenText: string): Boolean; static;
  end;

  TDefaultParameterInvalidRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TSignedUnsignedMixRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

procedure RegisterConstantRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.StrUtils,
  System.Generics.Collections,
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

/// <summary>Text hinter "=" einer Typsignatur ("TGroesse = UInt64" → UInt64), ohne Semikolon; '' ohne "=" und
/// bei gekürzten Signaturen.</summary>
function TypeBodyOf(const ASignature: string): string;
var
  Equals: Integer;
begin
  Result := '';
  Equals := Pos('=', ASignature);
  if (Equals = 0) or ASignature.EndsWith('…') then
    Exit;
  Result := Trim(Copy(ASignature, Equals + 1, MaxInt));
  if Result.EndsWith(';') then
    Result := Trim(Copy(Result, 1, Length(Result) - 1));
end;

type
  /// <summary>Ganzzahliger Typ fester Größe: Bits und Vorzeichen; Bits = 0 bei anderen Typen.</summary>
  TIntegerKind = record
    Bits: Integer;
    Signed: Boolean;
  end;

/// <summary>Art des ganzzahligen Typs ATypeName (Integer, Cardinal, DWORD …); NativeInt und NativeUInt hängen
/// von der Plattform ab und zählen nicht.</summary>
function IntegerKindOf(const ATypeName: string): TIntegerKind;
var
  Name: string;
begin
  Result := Default(TIntegerKind);
  Name := LowerCase(ATypeName);
  if Name.StartsWith('system.') then
    Name := Copy(Name, Length('system.') + 1, MaxInt);
  if (Name = 'shortint') or (Name = 'int8') then
    Result.Bits := 8
  else if (Name = 'smallint') or (Name = 'int16') then
    Result.Bits := 16
  else if (Name = 'integer') or (Name = 'longint') or (Name = 'int32') then
    Result.Bits := 32
  else if Name = 'int64' then
    Result.Bits := 64;
  if Result.Bits > 0 then
  begin
    Result.Signed := True;
    Exit;
  end;
  if (Name = 'byte') or (Name = 'uint8') then
    Result.Bits := 8
  else if (Name = 'word') or (Name = 'uint16') then
    Result.Bits := 16
  else if (Name = 'cardinal') or (Name = 'longword') or (Name = 'uint32') or (Name = 'dword') then
    Result.Bits := 32
  else if Name = 'uint64' then
    Result.Bits := 64;
end;

/// <summary>Ist AWord ein vorzeichenloser Typ mit 32 oder 64 Bit?</summary>
function IsUnsignedName(const AWord: string): Boolean;
var
  Word: string;
begin
  Word := LowerCase(AWord);
  if Word.StartsWith('system.') then
    Word := Copy(Word, Length('system.') + 1, MaxInt);
  Result := (Word = 'cardinal') or (Word = 'longword') or (Word = 'uint32') or (Word = 'dword') or
    (Word = 'uint64');
end;

/// <summary>Wörter einer Deklaration oder Signatur (Namen, Typen) ohne Satzzeichen.</summary>
function DeclarationWords(const AText: string): TArray<string>;
begin
  Result := AText.Split([' ', ':', ';', '(', ')', '[', ']', ',', '=', '<', '>', #9, #10, #13],
    TStringSplitOptions.ExcludeEmpty);
end;

/// <summary>Letzter Name eines Operanden (Liste.Count → Count, F(X) → F, A[I] → A); '' ohne.</summary>
function OperandName(ANode: TSyntaxNode): string;
begin
  Result := '';
  case ANode.Kind of
    TSyntaxKind.Identifier, TSyntaxKind.MemberAccess:
      Result := ANode.Name;
    TSyntaxKind.Call, TSyntaxKind.IndexAccess:
      if ANode.ChildCount > 0 then
        Result := OperandName(ANode[0]);
    TSyntaxKind.ParenExpr:
      if ANode.ChildCount = 1 then
        Result := OperandName(ANode[0]);
  end;
end;

/// <summary>Ganzzahliger Typ des Operanden ANode (Variable, Feld, Property, Funktionsergebnis, Element) über die
/// Namensauflösung; False, wenn er nicht sicher bekannt ist. ATypeName ist der Name wie deklariert.</summary>
function OperandKind(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string; ANode: TSyntaxNode;
  out AKind: TIntegerKind; out ATypeName: string): Boolean;
var
  Symbol, TypeInfo: TResolvedSymbol;
  TypeFound: Boolean;
begin
  Result := False;
  AKind := Default(TIntegerKind);
  ATypeName := '';
  if (ANode.Kind = TSyntaxKind.ParenExpr) and (ANode.ChildCount = 1) then
    Exit(OperandKind(AResolver, ATree, AFileName, ANode[0], AKind, ATypeName));
  if not (ANode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess, TSyntaxKind.Call,
    TSyntaxKind.IndexAccess]) or not AResolver.NodeType(ATree, AFileName, ANode, Symbol, TypeInfo, TypeFound) or
    not (Symbol.SymbolKind in [TIndexSymbolKind.Variable, TIndexSymbolKind.Field, TIndexSymbolKind.Property_,
    TIndexSymbolKind.Method, TIndexSymbolKind.Routine]) then
    Exit;
  ATypeName := Symbol.TypeName;
  AKind := IntegerKindOf(ATypeName);
  // Eigene Aliase (type TGroesse = UInt64) über den aufgelösten Typ.
  if (AKind.Bits = 0) and TypeFound then
  begin
    AKind := IntegerKindOf(TypeInfo.Name);
    if AKind.Bits = 0 then
      AKind := IntegerKindOf(TypeBodyOf(TypeInfo.Signature));
  end;
  Result := AKind.Bits > 0;
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

{ TDefaultParameterInvalidRule }

function TDefaultParameterInvalidRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(DefaultParameterInvalidRuleId, TRuleSeverity.Error,
    'Unzulässiger Standardwert eines Parameters');
end;

/// <summary>Hat der Parameter einen Standardwert? Kinder sind Typ und Wert; ohne Typ gibt es keinen Wert.</summary>
function HasDefault(AParameter: TSyntaxNode): Boolean;
begin
  Result := AParameter.ChildCount >= 2;
end;

procedure TDefaultParameterInvalidRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  FileName: string;
  Resolver: TNameResolver;

  function NodeText(ANode: TSyntaxNode): string;
  begin
    Result := Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
  end;

  function NodeRange(ANode: TSyntaxNode): TTextRange;
  begin
    Result := TTextRange.Create(ANode.StartPos, ANode.EndPos);
  end;

  /// <summary>Text des Parameters ab dem Typ ("Integer = 0") und der Modifizierer davor.</summary>
  function TypeAndDefault(AParameter: TSyntaxNode): string;
  begin
    Result := Copy(AContext.Text, AParameter[0].StartOffset + 1, AParameter.EndOffset - AParameter[0].StartOffset);
  end;

  function ModifierText(AParameter: TSyntaxNode): string;
  begin
    case AParameter.Modifier of
      TParameterModifier.ConstParam:
        Result := 'const ';
      TParameterModifier.VarParam:
        Result := 'var ';
      TParameterModifier.OutParam:
        Result := 'out ';
      TParameterModifier.ConstRefParam:
        Result := 'constref ';
    else
      Result := '';
    end;
  end;

  /// <summary>Name der Routine mit Klasse (TKunde.Senden); '' bei Prozedurtypen.</summary>
  function QualifiedRoutine(AParameters: TSyntaxNode): string;
  var
    Header, Node: TSyntaxNode;
  begin
    Result := '';
    Header := AParameters.Parent;
    if (Header = nil) or (Header.Kind <> TSyntaxKind.RoutineHeader) then
      Exit;
    Result := Header.Name;
    Node := Header.Parent;
    while (Node <> nil) and not (Node.Kind in [TSyntaxKind.TypeDecl, TSyntaxKind.RoutineDecl,
      TSyntaxKind.ImplementationSection]) do
      Node := Node.Parent;
    if (Node <> nil) and (Node.Kind = TSyntaxKind.TypeDecl) then
      Result := Node.Name + '.' + Result;
  end;

  function NamesKey(AParameters: TSyntaxNode): string;
  var
    Index: Integer;
  begin
    Result := '';
    for Index := 0 to AParameters.ChildCount - 1 do
      if AParameters[Index].Kind = TSyntaxKind.Parameter then
        Result := Result + LowerCase(AParameters[Index].Name) + ';';
  end;

  function FindPaired(ANode, AParameters: TSyntaxNode; const AName, AKey: string): TSyntaxNode;
  var
    Index: Integer;
  begin
    if (ANode.Kind = TSyntaxKind.Parameters) and (ANode <> AParameters) and
      SameText(QualifiedRoutine(ANode), AName) and (NamesKey(ANode) = AKey) then
      Exit(ANode);
    Result := nil;
    Index := 0;
    while (Result = nil) and (Index < ANode.ChildCount) do
    begin
      Result := FindPaired(ANode[Index], AParameters, AName, AKey);
      Inc(Index);
    end;
  end;

  /// <summary>Der zugehörige Kopf in derselben Datei: Deklaration zur Implementierung und umgekehrt.</summary>
  function PairedParameters(AParameters: TSyntaxNode): TSyntaxNode;
  var
    Name: string;
  begin
    Result := nil;
    Name := QualifiedRoutine(AParameters);
    if Name <> '' then
      Result := FindPaired(AContext.Tree.Root, AParameters, Name, NamesKey(AParameters));
  end;

  /// <summary>Parameterliste mit den Parametern ohne Standardwert zuerst; die Standardwerte stehen nur in
  /// ADefaults (Parameter mit Wert in der Liste, die sie trägt), damit der zugehörige Kopf mitzieht.</summary>
  function Reordered(AParameters: TSyntaxNode; const ADefaults: string): string;
  var
    Index: Integer;
    Parameter: TSyntaxNode;
    Front, Back: TArray<string>;
  begin
    Front := nil;
    Back := nil;
    for Index := 0 to AParameters.ChildCount - 1 do
    begin
      Parameter := AParameters[Index];
      if Parameter.Kind <> TSyntaxKind.Parameter then
        Continue;
      if Pos(';' + LowerCase(Parameter.Name) + ';', ADefaults) > 0 then
        Back := Back + [NodeText(Parameter)]
      else
        Front := Front + [NodeText(Parameter)];
    end;
    Result := string.Join('; ', Front + Back);
  end;

  function ListRange(AParameters: TSyntaxNode; out ARange: TTextRange): Boolean;
  var
    Index: Integer;
    First, Last: TSyntaxNode;
  begin
    First := nil;
    Last := nil;
    for Index := 0 to AParameters.ChildCount - 1 do
      if AParameters[Index].Kind = TSyntaxKind.Parameter then
      begin
        if First = nil then
          First := AParameters[Index];
        Last := AParameters[Index];
      end;
    Result := First <> nil;
    if Result then
      ARange := TTextRange.Create(First.StartPos, Last.EndPos);
  end;

  function MoveFix(AParameters: TSyntaxNode; out AFix: TRuleFix): Boolean;
  var
    Defaults: string;
    Index: Integer;
    Range: TTextRange;
    Paired: TSyntaxNode;
    Edits: TArray<TRuleEdit>;
  begin
    // Parameter einzeln und ohne Kommentare dazwischen, sonst lieber keine Korrektur.
    Result := False;
    Defaults := ';';
    for Index := 0 to AParameters.ChildCount - 1 do
      if AParameters[Index].Kind = TSyntaxKind.Parameter then
      begin
        if Pos(',', AParameters[Index].Name) > 0 then
          Exit;
        if HasDefault(AParameters[Index]) then
          Defaults := Defaults + LowerCase(AParameters[Index].Name) + ';';
      end
      else
        Exit;
    if not ListRange(AParameters, Range) then
      Exit;
    Edits := [TTextEdit.Create(Range, Reordered(AParameters, Defaults))];
    Paired := PairedParameters(AParameters);
    if (Paired <> nil) and ListRange(Paired, Range) then
      Edits := Edits + [TTextEdit.Create(Range, Reordered(Paired, Defaults))];
    AFix := TRuleFix.Create('Parameter mit Standardwert ans Ende verschieben', Edits);
    Result := True;
  end;

  procedure EnsureResolver;
  begin
    // Erst hier die Namensauflösung: Die meisten Dateien haben keinen Standardwert mit eigenem Typ.
    if Resolver = nil then
    begin
      Resolver := TNameResolver.Create(AContext.Index, AContext.EnsureUnit);
      Resolver.Namespaces := AContext.Namespaces;
      Resolver.PinTree(AContext.Tree, FileName);
    end;
  end;

  /// <summary>Anzahl der Werte einer Aufzählung "(a, b, c)"; 0, wenn es keine ist.</summary>
  function EnumCount(const ABody: string): Integer;
  begin
    Result := 0;
    if ABody.StartsWith('(') and ABody.EndsWith(')') then
      Result := Length(ABody.Split([',']));
  end;

  /// <summary>Belegt eine Menge mit dem Basistyp ABase sicher mehr als 4 Byte (keine "kleine Menge")?</summary>
  function LargeBase(const ABase: string): Boolean;
  var
    Base: string;
    Dots: Integer;
    Lowest, Highest: Int64;
    Enum: TResolvedSymbol;
  begin
    Base := LowerCase(Trim(ABase));
    if (Base = 'ansichar') or (Base = 'char') or (Base = 'widechar') or (Base = 'byte') or (Base = 'word') then
      Exit(True);
    if EnumCount(Base) > 0 then
      Exit(EnumCount(Base) > 32);
    Dots := Pos('..', Base);
    if Dots > 0 then
    begin
      // Größe in Byte wie beim Compiler: von Low div 8 bis High div 8.
      Result := TOrdinalConstants.Evaluate(Copy(ABase, 1, Dots - 1), nil, Lowest) and
        TOrdinalConstants.Evaluate(Copy(ABase, Dots + 2, MaxInt), nil, Highest) and (Lowest >= 0) and
        (Highest div 8 - Lowest div 8 + 1 > 4);
      Exit;
    end;
    Result := Resolver.ResolveTypeFrom(Resolver.ExtractedUnit(AContext.Tree, FileName), Trim(ABase), Enum) and
      (Enum.SymbolKind = TIndexSymbolKind.EnumType) and (EnumCount(TypeBodyOf(Enum.Signature)) > 32);
  end;

  /// <summary>Typ eines Parameters mit Standardwert; eingebaute einfache Typen (string, Integer …) brauchen
  /// keine Auflösung.</summary>
  function ParameterType(ATypeNode: TSyntaxNode; out AType: TResolvedSymbol): Boolean;
  var
    Name: string;
  begin
    Result := False;
    Name := LowerCase(ATypeNode.Name);
    if (ATypeNode.Kind <> TSyntaxKind.TypeReference) or (ATypeNode.ChildCount > 0) or (Pos('<', Name) > 0) or
      (IndexText(Name, ['string', 'unicodestring', 'ansistring', 'widestring', 'shortstring', 'integer',
      'cardinal', 'int64', 'uint64', 'nativeint', 'nativeuint', 'byte', 'word', 'smallint', 'shortint',
      'longint', 'longword', 'boolean', 'char', 'ansichar', 'widechar', 'double', 'single', 'extended',
      'currency', 'real', 'pointer', 'pchar', 'tobject', 'tclass', 'variant', 'tdatetime']) >= 0) then
      Exit;
    EnsureResolver;
    AType := Resolver.ResolveType(AContext.Tree, FileName, ATypeNode.StartPos);
    Result := AType.Found;
  end;

  /// <summary>Records und statische Arrays haben keine Standardwerte (E2268).</summary>
  function NoDefaultType(const AType: TResolvedSymbol): Boolean;
  begin
    Result := (AType.SymbolKind = TIndexSymbolKind.RecordType) or
      ((AType.SymbolKind = TIndexSymbolKind.TypeAlias) and
      (Pos('array[', LowerCase(StringReplace(AType.Signature, ' ', '', [rfReplaceAll]))) > 0));
  end;

  /// <summary>Mengentyp, der mehr als 4 Byte belegt (E2146).</summary>
  function LargeSetType(const AType: TResolvedSymbol): Boolean;
  var
    Body: string;
  begin
    Body := TypeBodyOf(AType.Signature);
    Result := StartsText('set of ', Body) and LargeBase(Copy(Body, Length('set of ') + 1, MaxInt));
  end;

  procedure CheckParameters(AParameters: TSyntaxNode);
  var
    Index: Integer;
    Parameter: TSyntaxNode;
    SeenDefault, Moved: Boolean;
    Names: TArray<string>;
    Name, Text: string;
    ParamType: TResolvedSymbol;
    Fix: TRuleFix;
    Fixes: TArray<TRuleFix>;
  begin
    SeenDefault := False;
    Moved := False;
    for Index := 0 to AParameters.ChildCount - 1 do
    begin
      Parameter := AParameters[Index];
      if Parameter.Kind <> TSyntaxKind.Parameter then
        Continue;
      if HasDefault(Parameter) then
      begin
        SeenDefault := True;
        Names := Parameter.Name.Split([',']);
        if Length(Names) > 1 then
        begin
          // A, B: Integer = 0 wird A: Integer = 0; B: Integer = 0.
          Text := '';
          for Name in Names do
          begin
            if Text <> '' then
              Text := Text + '; ';
            Text := Text + ModifierText(Parameter) + Trim(Name) + ': ' + TypeAndDefault(Parameter);
          end;
          AReport.Add(NodeRange(Parameter), Format('%s: Standardwerte gibt es nur für einzeln deklarierte ' +
            'Parameter (wie E2237).', [StringReplace(Parameter.Name, ',', ', ', [rfReplaceAll])]),
            TRuleConfidence.High, [TRuleFix.Create('Parameter einzeln deklarieren',
            [TTextEdit.Create(NodeRange(Parameter), Text)])]);
        end;
        if Parameter.Modifier in [TParameterModifier.VarParam, TParameterModifier.OutParam] then
          AReport.Add(NodeRange(Parameter), Format('%s ist ein %s-Parameter und kann keinen Standardwert haben ' +
            '(wie E2239).', [Parameter.Name, Trim(ModifierText(Parameter))]), TRuleConfidence.High)
        else if ParameterType(Parameter[0], ParamType) then
        begin
          if NoDefaultType(ParamType) then
            AReport.Add(NodeRange(Parameter), Format('Parameter vom Typ %s können keinen Standardwert haben ' +
              '(wie E2268).', [Parameter[0].Name]), TRuleConfidence.High)
          else if LargeSetType(ParamType) then
            AReport.Add(NodeRange(Parameter), Format('%s ist eine Menge über 4 Byte; Standardwerte gibt es nur ' +
              'für ordinale, Zeiger- und kleine Mengentypen (wie E2146).', [Parameter[0].Name]),
              TRuleConfidence.Medium);
        end;
      end
      else if SeenDefault then
      begin
        Fixes := nil;
        // Die Korrektur nur am ersten betroffenen Parameter; sie ordnet die ganze Liste.
        if not Moved and MoveFix(AParameters, Fix) then
          Fixes := [Fix];
        Moved := True;
        AReport.Add(NodeRange(Parameter), Format('%s braucht einen Standardwert, weil ein vorheriger Parameter ' +
          'einen hat (wie E2238).', [StringReplace(Parameter.Name, ',', ', ', [rfReplaceAll])]),
          TRuleConfidence.High, Fixes);
      end;
    end;
  end;

  procedure Visit(ANode: TSyntaxNode);
  var
    Index: Integer;
  begin
    if ANode.Kind = TSyntaxKind.Parameters then
      CheckParameters(ANode);
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
  Resolver := nil;
  try
    Visit(AContext.Tree.Root);
  finally
    if Resolver <> nil then
    begin
      Resolver.UnpinTree;
      Resolver.Free;
    end;
  end;
end;

{ TSignedUnsignedMixRule }

function TSignedUnsignedMixRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(SignedUnsignedMixRuleId, TRuleSeverity.Warning,
    'Vorzeichenbehaftet und vorzeichenlos gemischt');
end;

procedure TSignedUnsignedMixRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
const
  // Kürzer gehaltene Operanden erscheinen mit Namen in der Meldung.
  MaxOperandText = 30;
var
  FileName: string;
  Resolver: TNameResolver;
  // Namen, deren Deklaration einen vorzeichenlosen Typ nennt (Vorfilter vor der Namensauflösung).
  Suspects: TDictionary<string, Boolean>;
  LocalNames: TDictionary<string, Boolean>;
  // Vorzeichenlose Typnamen (eingebaut oder Alias wie TGroesse = UInt64) samt Ergebnis der Prüfung.
  UnsignedTypes: TDictionary<string, Boolean>;

  function NodeText(ANode: TSyntaxNode): string;
  begin
    Result := Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
  end;

  /// <summary>Ist ATypeName vorzeichenlos: eingebaut, eigener Alias der Datei oder Alias aus dem Index?</summary>
  function UnsignedType(const ATypeName: string): Boolean;
  var
    Key: string;
    Location: TSymbolLocation;
  begin
    if IsUnsignedName(ATypeName) then
      Exit(True);
    Key := LowerCase(ATypeName);
    if UnsignedTypes.TryGetValue(Key, Result) then
      Exit;
    // Vorläufig False: schützt vor zyklischen Aliasen.
    UnsignedTypes.Add(Key, False);
    Result := False;
    if (AContext.Index <> nil) and IsValidIdent(ATypeName, True) then
      for Location in AContext.Index.FindSymbols(ATypeName) do
        if (Location.Symbol.Kind = TIndexSymbolKind.TypeAlias) and
          UnsignedType(TypeBodyOf(Location.Symbol.Signature)) then
        begin
          Result := True;
          Break;
        end;
    UnsignedTypes[Key] := Result;
  end;

  function MentionsUnsigned(const AText: string): Boolean;
  var
    Word: string;
  begin
    for Word in DeclarationWords(AText) do
      if UnsignedType(Word) then
        Exit(True);
    Result := False;
  end;

  /// <summary>Eigene Aliase der Datei auf vorzeichenlose Typen (type TGroesse = UInt64).</summary>
  procedure CollectTypes(ANode: TSyntaxNode);
  var
    Index: Integer;
    Body: string;
  begin
    if (ANode.Kind = TSyntaxKind.TypeDecl) and (ANode.ChildCount > 0) then
    begin
      Body := Trim(NodeText(ANode[0]));
      if (Pos(' ', Body) = 0) and UnsignedType(Body) then
        UnsignedTypes.AddOrSetValue(LowerCase(ANode.Name), True);
    end;
    for Index := 0 to ANode.ChildCount - 1 do
      CollectTypes(ANode[Index]);
  end;

  /// <summary>Deklarationen der Datei mit vorzeichenlosem Typ: Variablen, Felder, Parameter, Konstanten.</summary>
  procedure CollectLocal(ANode: TSyntaxNode);
  var
    Index: Integer;
    Name: string;
  begin
    if (ANode.Kind in [TSyntaxKind.VarDecl, TSyntaxKind.Field, TSyntaxKind.Parameter, TSyntaxKind.ConstDecl,
      TSyntaxKind.PropertyDecl, TSyntaxKind.InlineVar]) and (ANode.ChildCount > 0) and
      MentionsUnsigned(NodeText(ANode[0])) then
      for Name in ANode.Name.Split([',']) do
        LocalNames.AddOrSetValue(LowerCase(Trim(Name)), True);
    // Funktionen mit vorzeichenlosem Ergebnis.
    if (ANode.Kind = TSyntaxKind.RoutineHeader) and MentionsUnsigned(Copy(NodeText(ANode),
      LastDelimiter(')', NodeText(ANode)) + 1, MaxInt)) then
      LocalNames.AddOrSetValue(LowerCase(Copy(ANode.Name, LastDelimiter('.', ANode.Name) + 1, MaxInt)), True);
    for Index := 0 to ANode.ChildCount - 1 do
      CollectLocal(ANode[Index]);
  end;

  function Suspect(const AName: string): Boolean;
  var
    Key: string;
    Location: TSymbolLocation;
  begin
    Key := LowerCase(AName);
    if (Key = '') or LocalNames.ContainsKey(Key) then
      Exit(Key <> '');
    if Suspects.TryGetValue(Key, Result) then
      Exit;
    Result := False;
    if AContext.Index <> nil then
      for Location in AContext.Index.FindSymbols(AName) do
        if (Location.Symbol.Kind in [TIndexSymbolKind.Variable, TIndexSymbolKind.Field,
          TIndexSymbolKind.Property_, TIndexSymbolKind.Method, TIndexSymbolKind.Routine]) and
          (Location.Symbol.TypeName <> '') and UnsignedType(Location.Symbol.TypeName) then
        begin
          Result := True;
          Break;
        end;
    Suspects.Add(Key, Result);
  end;

  procedure CheckMix(ANode: TSyntaxNode);
  var
    Comparison: Boolean;
    LeftKind, RightKind, SignedKind, UnsignedKind: TIntegerKind;
    LeftType, RightType, SignedType, UnsignedType, SignedText, Message, Subject: string;
    SignedNode, UnsignedNode: TSyntaxNode;
  begin
    Comparison := (ANode.Name = '=') or (ANode.Name = '<>') or (ANode.Name = '<') or (ANode.Name = '>') or
      (ANode.Name = '<=') or (ANode.Name = '>=');
    if (ANode.ChildCount <> 2) or not (Comparison or (ANode.Name = '+') or (ANode.Name = '-') or
      (ANode.Name = '*') or SameText(ANode.Name, 'div') or SameText(ANode.Name, 'mod')) then
      Exit;
    if not Suspect(OperandName(ANode[0])) and not Suspect(OperandName(ANode[1])) then
      Exit;
    if Resolver = nil then
    begin
      Resolver := TNameResolver.Create(AContext.Index, AContext.EnsureUnit);
      Resolver.Namespaces := AContext.Namespaces;
      Resolver.PinTree(AContext.Tree, FileName);
    end;
    if not OperandKind(Resolver, AContext.Tree, FileName, ANode[0], LeftKind, LeftType) or
      not OperandKind(Resolver, AContext.Tree, FileName, ANode[1], RightKind, RightType) or
      (LeftKind.Signed = RightKind.Signed) then
      Exit;
    if LeftKind.Signed then
    begin
      SignedKind := LeftKind;
      SignedType := LeftType;
      SignedNode := ANode[0];
      UnsignedKind := RightKind;
      UnsignedType := RightType;
      UnsignedNode := ANode[1];
    end
    else
    begin
      SignedKind := RightKind;
      SignedType := RightType;
      SignedNode := ANode[1];
      UnsignedKind := LeftKind;
      UnsignedType := LeftType;
      UnsignedNode := ANode[0];
    end;
    // Byte und Word passen in Integer, Cardinal passt in Int64: dann rechnet Delphi ohne Warnung.
    if (UnsignedKind.Bits < 32) or ((UnsignedKind.Bits = 32) and (SignedKind.Bits = 64)) then
      Exit;
    if Comparison then
      Subject := 'verglichen'
    else
      Subject := 'gemischt';
    SignedText := NodeText(SignedNode);
    if (Length(SignedText) > MaxOperandText) or (Pos(#10, SignedText) > 0) then
      SignedText := 'Wert';
    if UnsignedKind.Bits = 64 then
    begin
      if Comparison then
        Message := Format('%s und %s verglichen: ein negativer Wert in %s wird vorzeichenlos verglichen (wie W1023).',
          [SignedType, UnsignedType, SignedText])
      else
        Message := Format('%s und %s gemischt: ein negativer Wert in %s wird vorzeichenlos gerechnet (wie W1073).',
          [SignedType, UnsignedType, SignedText]);
    end
    else if Comparison then
      Message := Format('%s und %s %s: beide Operanden werden auf Int64 erweitert (wie W1023).',
        [SignedType, UnsignedType, Subject])
    else
      Message := Format('%s und %s %s: beide Operanden werden auf Int64 erweitert (wie W1024).',
        [SignedType, UnsignedType, Subject]);
    AReport.Add(TTextRange.Create(ANode.StartPos, ANode.EndPos), Message, TRuleConfidence.Medium,
      [TRuleFix.Create(Format('%s in Int64 umwandeln', [NodeText(UnsignedNode)]),
      [TTextEdit.Create(TTextRange.Create(UnsignedNode.StartPos, UnsignedNode.EndPos),
      'Int64(' + NodeText(UnsignedNode) + ')')])]);
  end;

  procedure Visit(ANode: TSyntaxNode);
  var
    Index: Integer;
  begin
    if ANode.Kind = TSyntaxKind.BinaryExpr then
      CheckMix(ANode);
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
  Resolver := nil;
  Suspects := TDictionary<string, Boolean>.Create;
  LocalNames := TDictionary<string, Boolean>.Create;
  UnsignedTypes := TDictionary<string, Boolean>.Create;
  try
    CollectTypes(AContext.Tree.Root);
    CollectLocal(AContext.Tree.Root);
    Visit(AContext.Tree.Root);
  finally
    if Resolver <> nil then
    begin
      Resolver.UnpinTree;
      Resolver.Free;
    end;
    UnsignedTypes.Free;
    LocalNames.Free;
    Suspects.Free;
  end;
end;

procedure RegisterConstantRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TConstantExpressionErrorRule.Create);
  ARegistry.Register(TDefaultParameterInvalidRule.Create);
  ARegistry.Register(TSignedUnsignedMixRule.Create);
end;

end.
