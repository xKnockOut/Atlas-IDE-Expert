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
//                              Korrekturen: Parameter einzeln deklarieren;
//                              Parameter mit Standardwert ans Ende verschieben,
//                              auch im zugehörigen Kopf derselben Datei
//                              (Deklaration bzw. Implementierung).
//   signed-unsigned-mix        Vorzeichenbehaftet und vorzeichenlos gemischt
//                              (#1012): Vergleich (W1023) oder Rechnung
//                              (W1024) eines Operanden bis 32 Bit mit Vorzeichen
//                              und eines vorzeichenlosen 32-Bit-Operanden, und
//                              jede Mischung mit UInt64 (Rechnung W1073,
//                              Vergleich W1023). Typen aus der Namensauflösung,
//                              nur bei sicher bekanntem Typ beider Operanden;
//                              Literale zählen nicht. Korrektur: den
//                              vorzeichenlosen Operanden in Int64 umwandeln.
//   narrowing-assignment       Zuweisung mit möglichem Datenverlust (#1013,
//                              standardmäßig aus): Quelltyp und Zieltyp bilden
//                              ein Paar aus der Option types (Vorgabe
//                              Int64>Integer und NativeInt>Integer), wie W1071,
//                              bei Gleitkomma W1072, Extended>Double W1066.
//                              Zuweisungen und Inline-Variablen mit Wert;
//                              Operanden und ganzzahlige Rechnungen mit sicher
//                              bekanntem Typ. Korrekturen: ausdrücklich
//                              umwandeln; Zieltyp der Deklaration vergrößern.
//   typed-constant-modified    Typisierte Konstante verändert (#1014):
//                              Zuweisung (W1017, auch an Element oder Feld)
//                              und Übergabe als var- oder out-Argument samt
//                              Inc, Dec, Include, Exclude … (W1016); steht
//                              vor der Deklaration in derselben Datei {$J-},
//                              ist es ein Fehler (E2064 bzw. E2197). Dazu 0
//                              als Wert einer Zeigerkonstante (W1013).
//                              Korrekturen: globale Konstante in eine
//                              Variable mit Initialwert umwandeln; nil
//                              statt 0.
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
  NarrowingAssignmentRuleId = 'narrowing-assignment';
  TypedConstantModifiedRuleId = 'typed-constant-modified';

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

  TNarrowingAssignmentRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Einheitlicher Name eines eingebauten Zahltyps (LongInt → integer, DWORD → cardinal, Real →
    /// double); sonst der Name in Kleinbuchstaben ohne "System.".</summary>
    class function CanonicalTypeName(const ATypeName: string): string; static;
    /// <summary>Vorgabe der Option types: Int64>Integer und NativeInt>Integer.</summary>
    class function DefaultTypes: TArray<string>; static;
  end;

  TTypedConstantModifiedRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Je Parameter der Signatur (mehrere Namen einzeln), ob er var oder out ist; nil ohne
    /// Parameterliste.</summary>
    class function VarParameters(const ASignature: string): TArray<Boolean>; static;
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
  Atlas.Common.Semantics.ConstantValues,
  Atlas.Common.Rules.Options,
  Atlas.Text.Lines;

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

/// <summary>Wörter einer Deklaration oder Signatur (Namen, Typen) ohne Satzzeichen.</summary>
function DeclarationWords(const AText: string): TArray<string>;
begin
  Result := AText.Split([' ', ':', ';', '(', ')', '[', ']', ',', '=', '<', '>', #9, #10, #13],
    TStringSplitOptions.ExcludeEmpty);
end;

type
  /// <summary>Vorfilter vor der Namensauflösung: Namen (Variablen, Felder, Parameter, Properties, Funktionen),
  /// deren Deklaration einen der gesuchten Typen nennt, in der Datei oder im Index. Gesuchte Typen sind
  /// einheitliche Namen (CanonicalTypeName); eigene Aliase der Datei und Aliase aus dem Index zählen mit.</summary>
  TTypedNames = class
  private
    FIndex: ISymbolIndex;
    FText: string;
    FWanted: TDictionary<string, Boolean>;
    // Typname → gesucht (auch über Aliase), zwischengespeichert.
    FTypes: TDictionary<string, Boolean>;
    FLocal: TDictionary<string, Boolean>;
    FSuspects: TDictionary<string, Boolean>;
    function NodeText(ANode: TSyntaxNode): string;
    function Mentions(const AText: string): Boolean;
    procedure CollectTypes(ANode: TSyntaxNode);
    procedure CollectLocal(ANode: TSyntaxNode);
  public
    constructor Create(const AContext: TRuleContext; const AWanted: TArray<string>);
    destructor Destroy; override;
    /// <summary>Ist ATypeName einer der gesuchten Typen oder ein Alias darauf?</summary>
    function Wanted(const ATypeName: string): Boolean;
    /// <summary>Kann der Name AName (letzter Teil eines Operanden) einen gesuchten Typ haben?</summary>
    function Suspect(const AName: string): Boolean;
  end;

constructor TTypedNames.Create(const AContext: TRuleContext; const AWanted: TArray<string>);
var
  Name: string;
begin
  inherited Create;
  FIndex := AContext.Index;
  FText := AContext.Text;
  FWanted := TDictionary<string, Boolean>.Create;
  for Name in AWanted do
    FWanted.AddOrSetValue(TNarrowingAssignmentRule.CanonicalTypeName(Name), True);
  FTypes := TDictionary<string, Boolean>.Create;
  FLocal := TDictionary<string, Boolean>.Create;
  FSuspects := TDictionary<string, Boolean>.Create;
  if (AContext.Tree <> nil) and (AContext.Tree.Root <> nil) then
  begin
    CollectTypes(AContext.Tree.Root);
    CollectLocal(AContext.Tree.Root);
  end;
end;

destructor TTypedNames.Destroy;
begin
  FSuspects.Free;
  FLocal.Free;
  FTypes.Free;
  FWanted.Free;
  inherited;
end;

function TTypedNames.NodeText(ANode: TSyntaxNode): string;
begin
  Result := Copy(FText, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
end;

function TTypedNames.Wanted(const ATypeName: string): Boolean;
var
  Key: string;
  Location: TSymbolLocation;
begin
  Key := TNarrowingAssignmentRule.CanonicalTypeName(ATypeName);
  if FWanted.ContainsKey(Key) then
    Exit(True);
  if FTypes.TryGetValue(Key, Result) then
    Exit;
  // Vorläufig False: schützt vor zyklischen Aliasen.
  FTypes.Add(Key, False);
  Result := False;
  if (FIndex <> nil) and IsValidIdent(ATypeName, True) then
    for Location in FIndex.FindSymbols(ATypeName) do
      if (Location.Symbol.Kind = TIndexSymbolKind.TypeAlias) and Wanted(TypeBodyOf(Location.Symbol.Signature)) then
      begin
        Result := True;
        Break;
      end;
  FTypes[Key] := Result;
end;

function TTypedNames.Mentions(const AText: string): Boolean;
var
  Word: string;
begin
  for Word in DeclarationWords(AText) do
    if Wanted(Word) then
      Exit(True);
  Result := False;
end;

procedure TTypedNames.CollectTypes(ANode: TSyntaxNode);
var
  Index: Integer;
  Body: string;
begin
  if (ANode.Kind = TSyntaxKind.TypeDecl) and (ANode.ChildCount > 0) then
  begin
    Body := Trim(NodeText(ANode[0]));
    if (Pos(' ', Body) = 0) and Wanted(Body) then
      FTypes.AddOrSetValue(TNarrowingAssignmentRule.CanonicalTypeName(ANode.Name), True);
  end;
  for Index := 0 to ANode.ChildCount - 1 do
    CollectTypes(ANode[Index]);
end;

procedure TTypedNames.CollectLocal(ANode: TSyntaxNode);
var
  Index: Integer;
  Name, Header: string;
begin
  if (ANode.Kind in [TSyntaxKind.VarDecl, TSyntaxKind.Field, TSyntaxKind.Parameter, TSyntaxKind.ConstDecl,
    TSyntaxKind.PropertyDecl, TSyntaxKind.InlineVar]) and (ANode.ChildCount > 0) and
    Mentions(NodeText(ANode[0])) then
    for Name in ANode.Name.Split([',']) do
      FLocal.AddOrSetValue(LowerCase(Trim(Name)), True);
  // Funktionen mit gesuchtem Ergebnistyp.
  if ANode.Kind = TSyntaxKind.RoutineHeader then
  begin
    Header := NodeText(ANode);
    if Mentions(Copy(Header, LastDelimiter(')', Header) + 1, MaxInt)) then
      FLocal.AddOrSetValue(LowerCase(Copy(ANode.Name, LastDelimiter('.', ANode.Name) + 1, MaxInt)), True);
  end;
  for Index := 0 to ANode.ChildCount - 1 do
    CollectLocal(ANode[Index]);
end;

function TTypedNames.Suspect(const AName: string): Boolean;
var
  Key: string;
  Location: TSymbolLocation;
begin
  Key := LowerCase(AName);
  if (Key = '') or FLocal.ContainsKey(Key) then
    Exit(Key <> '');
  if FSuspects.TryGetValue(Key, Result) then
    Exit;
  Result := False;
  if FIndex <> nil then
    for Location in FIndex.FindSymbols(AName) do
      if (Location.Symbol.Kind in [TIndexSymbolKind.Variable, TIndexSymbolKind.Field, TIndexSymbolKind.Property_,
        TIndexSymbolKind.Method, TIndexSymbolKind.Routine, TIndexSymbolKind.Constant]) and
        (Location.Symbol.TypeName <> '') and Wanted(Location.Symbol.TypeName) then
      begin
        Result := True;
        Break;
      end;
  FSuspects.Add(Key, Result);
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
  // Vorfilter vor der Namensauflösung: Namen mit vorzeichenlosem Typ.
  Unsigned: TTypedNames;

  function NodeText(ANode: TSyntaxNode): string;
  begin
    Result := Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
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
    if not Unsigned.Suspect(OperandName(ANode[0])) and not Unsigned.Suspect(OperandName(ANode[1])) then
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
  Unsigned := TTypedNames.Create(AContext, ['Cardinal', 'UInt64']);
  try
    Visit(AContext.Tree.Root);
  finally
    if Resolver <> nil then
    begin
      Resolver.UnpinTree;
      Resolver.Free;
    end;
    Unsigned.Free;
  end;
end;

{ TNarrowingAssignmentRule }

function TNarrowingAssignmentRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(NarrowingAssignmentRuleId, TRuleSeverity.Warning,
    'Zuweisung mit möglichem Datenverlust', True);
end;

class function TNarrowingAssignmentRule.DefaultTypes: TArray<string>;
begin
  Result := ['Int64>Integer', 'NativeInt>Integer'];
end;

class function TNarrowingAssignmentRule.CanonicalTypeName(const ATypeName: string): string;
begin
  Result := LowerCase(Trim(ATypeName));
  if Result.StartsWith('system.') then
    Result := Copy(Result, Length('system.') + 1, MaxInt);
  if (Result = 'longint') or (Result = 'int32') then
    Result := 'integer'
  else if (Result = 'longword') or (Result = 'uint32') or (Result = 'dword') then
    Result := 'cardinal'
  else if Result = 'int16' then
    Result := 'smallint'
  else if Result = 'int8' then
    Result := 'shortint'
  else if Result = 'uint16' then
    Result := 'word'
  else if Result = 'uint8' then
    Result := 'byte'
  else if Result = 'intptr' then
    Result := 'nativeint'
  else if Result = 'uintptr' then
    Result := 'nativeuint'
  else if Result = 'real' then
    Result := 'double';
end;

/// <summary>Ist der einheitliche Typname ein Gleitkommatyp?</summary>
function IsFloatName(const ACanonical: string): Boolean;
begin
  Result := (ACanonical = 'single') or (ACanonical = 'double') or (ACanonical = 'extended') or
    (ACanonical = 'real48') or (ACanonical = 'comp') or (ACanonical = 'currency');
end;

/// <summary>Breite eines ganzzahligen Typs für Rechnungen: 0 = kein ganzzahliger Typ, 32 = bis 32 Bit,
/// 48 = NativeInt/NativeUInt (plattformabhängig), 64 = Int64/UInt64.</summary>
function IntegerWidth(const ACanonical: string): Integer;
begin
  Result := 0;
  if (ACanonical = 'int64') or (ACanonical = 'uint64') then
    Result := 64
  else if (ACanonical = 'nativeint') or (ACanonical = 'nativeuint') then
    Result := 48
  else if IntegerKindOf(ACanonical).Bits > 0 then
    Result := 32;
end;

procedure TNarrowingAssignmentRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
const
  MaxValueText = 30;
var
  FileName: string;
  Resolver: TNameResolver;
  Sources: TTypedNames;
  // Paare "quelle>ziel" in einheitlichen Namen.
  Pairs: TDictionary<string, Boolean>;

  function NodeText(ANode: TSyntaxNode): string;
  begin
    Result := Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
  end;

  procedure EnsureResolver;
  begin
    if Resolver = nil then
    begin
      Resolver := TNameResolver.Create(AContext.Index, AContext.EnsureUnit);
      Resolver.Namespaces := AContext.Namespaces;
      Resolver.PinTree(AContext.Tree, FileName);
    end;
  end;

  /// <summary>Einheitlicher Name des Typs ATypeName; eigene Aliase über den aufgelösten Typ
  /// (ATypeInfo aus NodeType bzw. ResolveType).</summary>
  function Canonical(const ATypeName: string; const ATypeInfo: TResolvedSymbol; ATypeFound: Boolean): string;
  var
    Body: string;
  begin
    Result := CanonicalTypeName(ATypeName);
    if (IntegerWidth(Result) > 0) or IsFloatName(Result) or not ATypeFound then
      Exit;
    // Aufgelöst ist entweder der Zieltyp selbst (Integer) oder der Alias mit Signatur (TZahl = Integer).
    Body := CanonicalTypeName(ATypeInfo.Name);
    if (IntegerWidth(Body) = 0) and not IsFloatName(Body) then
      Body := CanonicalTypeName(TypeBodyOf(ATypeInfo.Signature));
    if (IntegerWidth(Body) > 0) or IsFloatName(Body) then
      Result := Body;
  end;

  /// <summary>Typ des Ausdrucks ANode: Operand mit sicher bekanntem Typ oder ganzzahlige Rechnung daraus.
  /// ADisplay ist der Typ wie deklariert; False, wenn er nicht sicher bekannt ist.</summary>
  function ExpressionType(ANode: TSyntaxNode; out ACanonical, ADisplay: string): Boolean;
  var
    Symbol, TypeInfo: TResolvedSymbol;
    TypeFound: Boolean;
    LeftCanonical, LeftDisplay, RightCanonical, RightDisplay: string;
    Value: Int64;
  begin
    Result := False;
    ACanonical := '';
    ADisplay := '';
    case ANode.Kind of
      TSyntaxKind.ParenExpr:
        if ANode.ChildCount = 1 then
          Result := ExpressionType(ANode[0], ACanonical, ADisplay);
      TSyntaxKind.UnaryExpr:
        if (ANode.ChildCount = 1) and ((ANode.Name = '-') or (ANode.Name = '+')) then
          Result := ExpressionType(ANode[0], ACanonical, ADisplay);
      TSyntaxKind.Literal:
        // Nur innerhalb ganzzahliger Rechnungen: kleine Zahlen ändern die Breite nicht.
        if TOrdinalConstants.Evaluate(NodeText(ANode), nil, Value) and (Value >= Low(Integer)) and
          (Value <= High(Integer)) then
        begin
          ACanonical := 'integer';
          ADisplay := 'Integer';
          Result := True;
        end;
      TSyntaxKind.BinaryExpr:
        if (ANode.ChildCount = 2) and ((ANode.Name = '+') or (ANode.Name = '-') or (ANode.Name = '*') or
          SameText(ANode.Name, 'div') or SameText(ANode.Name, 'mod') or SameText(ANode.Name, 'and') or
          SameText(ANode.Name, 'or') or SameText(ANode.Name, 'xor')) and
          ExpressionType(ANode[0], LeftCanonical, LeftDisplay) and
          ExpressionType(ANode[1], RightCanonical, RightDisplay) and (IntegerWidth(LeftCanonical) > 0) and
          (IntegerWidth(RightCanonical) > 0) then
        begin
          // Die breitere Seite bestimmt den Typ der Rechnung.
          if IntegerWidth(RightCanonical) > IntegerWidth(LeftCanonical) then
          begin
            ACanonical := RightCanonical;
            ADisplay := RightDisplay;
          end
          else
          begin
            ACanonical := LeftCanonical;
            ADisplay := LeftDisplay;
          end;
          Result := True;
        end;
      TSyntaxKind.Identifier, TSyntaxKind.MemberAccess, TSyntaxKind.Call, TSyntaxKind.IndexAccess:
        begin
          EnsureResolver;
          if Resolver.NodeType(AContext.Tree, FileName, ANode, Symbol, TypeInfo, TypeFound) and
            (Symbol.SymbolKind in [TIndexSymbolKind.Variable, TIndexSymbolKind.Field, TIndexSymbolKind.Property_,
            TIndexSymbolKind.Method, TIndexSymbolKind.Routine, TIndexSymbolKind.Constant]) and
            (Symbol.TypeName <> '') then
          begin
            ACanonical := Canonical(Symbol.TypeName, TypeInfo, TypeFound);
            ADisplay := Symbol.TypeName;
            Result := (IntegerWidth(ACanonical) > 0) or IsFloatName(ACanonical);
          end;
        end;
    end;
  end;

  /// <summary>Kann der Ausdruck einen Quelltyp aus den Paaren haben (Vorfilter ohne Namensauflösung)?</summary>
  function MaySource(ANode: TSyntaxNode): Boolean;
  var
    Index: Integer;
  begin
    if ANode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess, TSyntaxKind.Call,
      TSyntaxKind.IndexAccess] then
      Exit(Sources.Suspect(OperandName(ANode)));
    Result := False;
    if ANode.Kind in [TSyntaxKind.ParenExpr, TSyntaxKind.UnaryExpr, TSyntaxKind.BinaryExpr] then
      for Index := 0 to ANode.ChildCount - 1 do
        if MaySource(ANode[Index]) then
          Exit(True);
  end;

  /// <summary>Typknoten der Deklaration des Ziels in dieser Datei (einzelne Variable oder einzelnes Feld);
  /// nil, wenn die Deklaration woanders steht oder mehrere Namen teilt.</summary>
  function DeclarationTypeNode(const ASymbol: TResolvedSymbol): TSyntaxNode;
  var
    Found: TSyntaxNode;

    procedure Search(ANode: TSyntaxNode);
    var
      Index: Integer;
    begin
      if Found <> nil then
        Exit;
      if (ANode.Kind in [TSyntaxKind.VarDecl, TSyntaxKind.Field, TSyntaxKind.InlineVar]) and
        (ANode.ChildCount > 0) and SameText(ANode.Name, ASymbol.Name) and
        (ANode.StartPos.Line = ASymbol.SelectionRange.StartPos.Line) and
        (ANode[0].Kind = TSyntaxKind.TypeReference) then
      begin
        Found := ANode[0];
        Exit;
      end;
      for Index := 0 to ANode.ChildCount - 1 do
        Search(ANode[Index]);
    end;

  begin
    Found := nil;
    if (ASymbol.FileName = '') or SameText(ASymbol.FileName, FileName) or
      SameText(ExtractFileName(ASymbol.FileName), ExtractFileName(FileName)) then
      Search(AContext.Tree.Root);
    Result := Found;
  end;

  procedure Report(AValue: TSyntaxNode; const ATargetDisplay, ATargetCanonical: string;
    ATargetTypeNode: TSyntaxNode);
  var
    SourceCanonical, SourceDisplay, ValueText, Code, Message: string;
    Fixes: TArray<TRuleFix>;
  begin
    if not MaySource(AValue) or not ExpressionType(AValue, SourceCanonical, SourceDisplay) or
      not Pairs.ContainsKey(SourceCanonical + '>' + ATargetCanonical) then
      Exit;
    if IsFloatName(ATargetCanonical) then
    begin
      if (SourceCanonical = 'extended') and (ATargetCanonical = 'double') then
        Code := 'W1066'
      else
        Code := 'W1072';
    end
    else
      Code := 'W1071';
    ValueText := NodeText(AValue);
    if (Length(ValueText) > MaxValueText) or (Pos(#10, ValueText) > 0) then
      ValueText := 'Der Wert';
    Message := Format('%s ist %s; die Zuweisung an %s kann Daten verlieren (wie %s).',
      [ValueText, SourceDisplay, ATargetDisplay, Code]);
    Fixes := [TRuleFix.Create('Ausdrücklich in ' + ATargetDisplay + ' umwandeln',
      [TTextEdit.Create(TTextRange.Create(AValue.StartPos, AValue.EndPos),
      ATargetDisplay + '(' + NodeText(AValue) + ')')])];
    if ATargetTypeNode <> nil then
      Fixes := Fixes + [TRuleFix.Create('Zieltyp auf ' + SourceDisplay + ' vergrößern',
        [TTextEdit.Create(TTextRange.Create(ATargetTypeNode.StartPos, ATargetTypeNode.EndPos), SourceDisplay)])];
    AReport.Add(TTextRange.Create(AValue.StartPos, AValue.EndPos), Message, TRuleConfidence.Medium, Fixes);
  end;

  procedure CheckAssignment(ANode: TSyntaxNode);
  var
    Symbol, TypeInfo: TResolvedSymbol;
    TypeFound: Boolean;
    Target: string;
  begin
    if (ANode.ChildCount <> 2) or not MaySource(ANode[1]) then
      Exit;
    EnsureResolver;
    if not (ANode[0].Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess, TSyntaxKind.IndexAccess]) or
      not Resolver.NodeType(AContext.Tree, FileName, ANode[0], Symbol, TypeInfo, TypeFound) or
      not (Symbol.SymbolKind in [TIndexSymbolKind.Variable, TIndexSymbolKind.Field,
      TIndexSymbolKind.Property_]) or (Symbol.TypeName = '') then
      Exit;
    Target := Canonical(Symbol.TypeName, TypeInfo, TypeFound);
    if (ANode[0].Kind = TSyntaxKind.Identifier) and not Symbol.IsParameter then
      Report(ANode[1], Symbol.TypeName, Target, DeclarationTypeNode(Symbol))
    else
      Report(ANode[1], Symbol.TypeName, Target, nil);
  end;

  procedure CheckInlineVar(ANode: TSyntaxNode);
  var
    TypeInfo: TResolvedSymbol;
    TypeName: string;
  begin
    if (ANode.ChildCount <> 2) or (ANode[0].Kind <> TSyntaxKind.TypeReference) or (Pos(',', ANode.Name) > 0) or
      not MaySource(ANode[1]) then
      Exit;
    EnsureResolver;
    TypeName := NodeText(ANode[0]);
    TypeInfo := Resolver.ResolveType(AContext.Tree, FileName, ANode[0].StartPos);
    Report(ANode[1], TypeName, Canonical(TypeName, TypeInfo, TypeInfo.Found), ANode[0]);
  end;

  procedure Visit(ANode: TSyntaxNode);
  var
    Index: Integer;
  begin
    if ANode.Kind = TSyntaxKind.AssignStatement then
      CheckAssignment(ANode)
    else if ANode.Kind = TSyntaxKind.InlineVar then
      CheckInlineVar(ANode);
    for Index := 0 to ANode.ChildCount - 1 do
      Visit(ANode[Index]);
  end;

var
  Pair, SourceName, TargetName: string;
  SourceNames: TArray<string>;
  Separator: Integer;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  FileName := AContext.FileName;
  if FileName = '' then
    FileName := AContext.RelativePath;
  if FileName = '' then
    FileName := AContext.UnitName + '.pas';
  Pairs := TDictionary<string, Boolean>.Create;
  Resolver := nil;
  Sources := nil;
  try
    SourceNames := nil;
    for Pair in TRuleOptions.Strings(AContext.Options, 'types', DefaultTypes) do
    begin
      Separator := Pos('>', Pair);
      if Separator = 0 then
        Continue;
      SourceName := CanonicalTypeName(Copy(Pair, 1, Separator - 1));
      TargetName := CanonicalTypeName(Copy(Pair, Separator + 1, MaxInt));
      if (SourceName = '') or (TargetName = '') then
        Continue;
      Pairs.AddOrSetValue(SourceName + '>' + TargetName, True);
      SourceNames := SourceNames + [SourceName];
    end;
    if Pairs.Count = 0 then
      Exit;
    Sources := TTypedNames.Create(AContext, SourceNames);
    Visit(AContext.Tree.Root);
  finally
    if Resolver <> nil then
    begin
      Resolver.UnpinTree;
      Resolver.Free;
    end;
    Sources.Free;
    Pairs.Free;
  end;
end;

{ TTypedConstantModifiedRule }

function TTypedConstantModifiedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(TypedConstantModifiedRuleId, TRuleSeverity.Warning,
    'Typisierte Konstante verändert');
end;

class function TTypedConstantModifiedRule.VarParameters(const ASignature: string): TArray<Boolean>;
var
  Open, Close, Depth, Index, Start, Colon, Count: Integer;
  Group, Names, Head: string;
  IsVar: Boolean;
begin
  Result := nil;
  Open := Pos('(', ASignature);
  if Open = 0 then
    Exit;
  Depth := 0;
  Close := 0;
  for Index := Open to Length(ASignature) do
    if ASignature[Index] = '(' then
      Inc(Depth)
    else if ASignature[Index] = ')' then
    begin
      Dec(Depth);
      if Depth = 0 then
      begin
        Close := Index;
        Break;
      end;
    end;
  if Close = 0 then
    Exit;
  Depth := 0;
  Start := Open + 1;
  for Index := Open + 1 to Close do
  begin
    if CharInSet(ASignature[Index], ['(', '[', '<']) then
      Inc(Depth)
    else if CharInSet(ASignature[Index], [']', '>']) or ((ASignature[Index] = ')') and (Index < Close)) then
      Dec(Depth)
    else if ((ASignature[Index] = ';') and (Depth = 0)) or (Index = Close) then
    begin
      Group := Trim(Copy(ASignature, Start, Index - Start));
      Start := Index + 1;
      if Group = '' then
        Continue;
      // Standardwert und Typ abschneiden: nur die Namen zählen.
      Colon := Pos(':', Group);
      if Colon > 0 then
        Names := Trim(Copy(Group, 1, Colon - 1))
      else
        Names := Group;
      Head := LowerCase(Names);
      IsVar := Head.StartsWith('var ') or Head.StartsWith('out ');
      Count := Length(Names.Split([','], TStringSplitOptions.ExcludeEmpty));
      while Count > 0 do
      begin
        Result := Result + [IsVar];
        Dec(Count);
      end;
    end;
  end;
end;

/// <summary>Positionen der var-Argumente eingebauter Routinen (Inc, Dec, Include …); nil bei anderen Namen.
/// </summary>
function BuiltinVarArguments(const AName: string): TArray<Integer>;
var
  Name: string;
begin
  Result := nil;
  Name := LowerCase(AName);
  if Name.StartsWith('system.') then
    Name := Copy(Name, Length('system.') + 1, MaxInt);
  if (Name = 'inc') or (Name = 'dec') or (Name = 'include') or (Name = 'exclude') or (Name = 'setlength') or
    (Name = 'delete') or (Name = 'fillchar') or (Name = 'initialize') or (Name = 'finalize') then
    Result := [0]
  else if (Name = 'insert') or (Name = 'str') or (Name = 'move') then
    Result := [1]
  else if Name = 'val' then
    Result := [1, 2];
end;

/// <summary>Ist die Konstante typisiert? Bei zusammengesetzten Typen (array[0..1] of Integer) fehlt TypeName,
/// die Signatur hat dann einen Doppelpunkt vor dem Gleichheitszeichen.</summary>
function IsTypedConstant(const ATypeName, ASignature: string): Boolean;
var
  Colon, Equals: Integer;
begin
  if ATypeName <> '' then
    Exit(True);
  Colon := Pos(':', ASignature);
  Equals := Pos('=', ASignature);
  Result := (Colon > 0) and ((Equals = 0) or (Colon < Equals));
end;

/// <summary>Ist der Typname ein eingebauter Zeigertyp (Pointer, PChar …)?</summary>
function IsPointerName(const ATypeName: string): Boolean;
var
  Name: string;
begin
  Name := LowerCase(Trim(ATypeName));
  if Name.StartsWith('system.') then
    Name := Copy(Name, Length('system.') + 1, MaxInt);
  Result := (Name = 'pointer') or (Name = 'pchar') or (Name = 'pansichar') or (Name = 'pwidechar') or
    (Name = 'pbyte') or (Name = 'pword') or (Name = 'pinteger') or (Name = 'pcardinal') or (Name = 'pint64') or
    (Name = 'puint64') or (Name = 'psingle') or (Name = 'pdouble') or (Name = 'pextended') or
    (Name = 'pnativeint') or (Name = 'pnativeuint') or (Name = 'pboolean') or (Name = 'pstring');
end;

procedure TTypedConstantModifiedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
type
  // Stand von {$J}/{$WRITEABLECONST} vor einer Stelle der Datei.
  TWriteable = (Unknown, Off, On_);
var
  FileName, LineBreak: string;
  Lines: TArray<string>;
  Resolver: TNameResolver;
  // Namen typisierter Konstanten (Vorfilter): aus der Datei und aus dem Index.
  LocalNames, Suspects: TDictionary<string, Boolean>;

  function NodeText(ANode: TSyntaxNode): string;
  begin
    Result := Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
  end;

  function Before(const A, B: TTextPosition): Boolean;
  begin
    Result := (A.Line < B.Line) or ((A.Line = B.Line) and (A.Character < B.Character));
  end;

  /// <summary>Letzte Einstellung von {$J±} bzw. {$WRITEABLECONST} vor APosition in dieser Datei.</summary>
  function WriteableAt(const APosition: TTextPosition): TWriteable;
  var
    Token: TPascalToken;
    Text, Item: string;
  begin
    Result := TWriteable.Unknown;
    for Token in AContext.Tree.Tokens do
    begin
      if not Before(Token.StartPos, APosition) then
        Break;
      if Token.Kind <> TPascalTokenKind.Directive then
        Continue;
      Text := UpperCase(StringReplace(Token.Text, ' ', '', [rfReplaceAll]));
      if Text.StartsWith('{$') then
        Text := Copy(Text, 3, MaxInt)
      else if Text.StartsWith('(*$') then
        Text := Copy(Text, 4, MaxInt)
      else
        Continue;
      Text := Text.TrimRight(['}', ')', '*']);
      if Text.StartsWith('WRITEABLECONST') then
      begin
        if (Text = 'WRITEABLECONSTON') or (Text = 'WRITEABLECONST+') then
          Result := TWriteable.On_
        else if (Text = 'WRITEABLECONSTOFF') or (Text = 'WRITEABLECONST-') then
          Result := TWriteable.Off;
        Continue;
      end;
      for Item in Text.Split([',']) do
        if Item = 'J+' then
          Result := TWriteable.On_
        else if Item = 'J-' then
          Result := TWriteable.Off;
    end;
  end;

  procedure CollectLocal(ANode: TSyntaxNode);
  var
    Index: Integer;
  begin
    if (ANode.Kind = TSyntaxKind.ConstDecl) and (ANode.ChildCount = 2) then
      LocalNames.AddOrSetValue(LowerCase(ANode.Name), True);
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
        if (Location.Symbol.Kind = TIndexSymbolKind.Constant) and
          IsTypedConstant(Location.Symbol.TypeName, Location.Symbol.Signature) then
        begin
          Result := True;
          Break;
        end;
    Suspects.Add(Key, Result);
  end;

  /// <summary>Nennt der Zugriff ANode (Name, Feld, Element) einen verdächtigen Namen?</summary>
  function MentionsSuspect(ANode: TSyntaxNode): Boolean;
  begin
    case ANode.Kind of
      TSyntaxKind.Identifier:
        Result := Suspect(ANode.Name);
      TSyntaxKind.MemberAccess:
        Result := Suspect(ANode.Name) or ((ANode.ChildCount > 0) and MentionsSuspect(ANode[0]));
      TSyntaxKind.IndexAccess:
        Result := (ANode.ChildCount > 0) and MentionsSuspect(ANode[0]);
    else
      Result := False;
    end;
  end;

  procedure EnsureResolver;
  begin
    if Resolver = nil then
    begin
      Resolver := TNameResolver.Create(AContext.Index, AContext.EnsureUnit);
      Resolver.Namespaces := AContext.Namespaces;
      Resolver.PinTree(AContext.Tree, FileName);
    end;
  end;

  /// <summary>Typisierte Konstante, die der Zugriff ANode verändert: die Konstante selbst, ein Element oder ein
  /// Feld davon (nicht über Zeiger).</summary>
  function ModifiedConstant(ANode: TSyntaxNode; out ASymbol: TResolvedSymbol): Boolean;
  var
    TypeInfo: TResolvedSymbol;
    TypeFound: Boolean;
  begin
    Result := False;
    if not (ANode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess, TSyntaxKind.IndexAccess]) or
      not MentionsSuspect(ANode) then
      Exit;
    EnsureResolver;
    if ANode.Kind <> TSyntaxKind.IndexAccess then
    begin
      if not Resolver.NodeType(AContext.Tree, FileName, ANode, ASymbol, TypeInfo, TypeFound) then
        Exit;
      if (ASymbol.SymbolKind = TIndexSymbolKind.Constant) and IsTypedConstant(ASymbol.TypeName, ASymbol.Signature) then
        Exit(True);
      // Feld eines Records: weiter zum Empfänger.
      if (ANode.Kind = TSyntaxKind.MemberAccess) and (ASymbol.SymbolKind = TIndexSymbolKind.Field) and
        (ANode.ChildCount > 0) then
        Exit(ModifiedConstant(ANode[0], ASymbol));
      Exit;
    end;
    // Element: nur Arrays und Strings, nicht der Speicher hinter einem Zeiger.
    if (ANode.ChildCount = 0) or not ModifiedConstant(ANode[0], ASymbol) or IsPointerName(ASymbol.TypeName) or
      ASymbol.TypeName.StartsWith('^') then
      Exit;
    if Resolver.NodeType(AContext.Tree, FileName, ANode[0], ASymbol, TypeInfo, TypeFound) and TypeFound and
      (Pos('^', TypeBodyOf(TypeInfo.Signature)) > 0) then
      Exit;
    Result := True;
  end;

  /// <summary>Deklaration der Konstante ASymbol in dieser Datei; nil, wenn sie woanders steht.</summary>
  function DeclarationOf(const ASymbol: TResolvedSymbol): TSyntaxNode;
  var
    Found: TSyntaxNode;

    procedure Search(ANode: TSyntaxNode);
    var
      Index: Integer;
    begin
      if Found <> nil then
        Exit;
      if (ANode.Kind = TSyntaxKind.ConstDecl) and (ANode.ChildCount = 2) and SameText(ANode.Name, ASymbol.Name) and
        (ANode.StartPos.Line = ASymbol.SelectionRange.StartPos.Line) then
      begin
        Found := ANode;
        Exit;
      end;
      for Index := 0 to ANode.ChildCount - 1 do
        Search(ANode[Index]);
    end;

  begin
    Found := nil;
    if (ASymbol.FileName = '') or SameText(ASymbol.FileName, FileName) or
      SameText(ExtractFileName(ASymbol.FileName), ExtractFileName(FileName)) then
      Search(AContext.Tree.Root);
    Result := Found;
  end;

  /// <summary>Text vom Zeilenanfang bis APosition, wenn dort nur Leerraum steht; sonst False.</summary>
  function IndentBefore(const APosition: TTextPosition; out AIndent: string): Boolean;
  begin
    if Lines = nil then
      Lines := TTextLines.SplitLines(AContext.Text);
    Result := False;
    AIndent := '';
    if (APosition.Line < 0) or (APosition.Line > High(Lines)) then
      Exit;
    AIndent := Copy(Lines[APosition.Line], 1, APosition.Character);
    Result := Trim(AIndent) = '';
  end;

  /// <summary>Korrektur "In var mit Initialwert umwandeln" für eine globale Konstante ADecl: die Deklaration
  /// kommt in einen eigenen var-Abschnitt, die übrigen bleiben const.</summary>
  function VarFix(ADecl: TSyntaxNode; out AFix: TRuleFix): Boolean;
  var
    Section, Previous, Next: TSyntaxNode;
    Position, Indent, DeclIndent: Integer;
    SectionIndent, Dummy: string;
    Edits: TArray<TRuleEdit>;
  begin
    Result := False;
    Section := ADecl.Parent;
    if (Section = nil) or (Section.Kind <> TSyntaxKind.ConstSection) or (Section.Parent = nil) or
      not (Section.Parent.Kind in [TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection]) or
      not SameText(Copy(NodeText(Section), 1, 5), 'const') or not IndentBefore(Section.StartPos, SectionIndent) then
      Exit;
    Position := -1;
    for Indent := 0 to Section.ChildCount - 1 do
      if Section[Indent] = ADecl then
        Position := Indent;
    if Position < 0 then
      Exit;
    Edits := nil;
    if Position = 0 then
      Edits := Edits + [TTextEdit.Create(TTextRange.Create(Section.StartPos,
        TTextPosition.Create(Section.StartPos.Line, Section.StartPos.Character + Length('const'))), 'var')]
    else
    begin
      Previous := Section[Position - 1];
      if (Previous.EndPos.Line >= ADecl.StartPos.Line) or not IndentBefore(ADecl.StartPos, Dummy) then
        Exit;
      DeclIndent := ADecl.StartPos.Line;
      Edits := Edits + [TTextEdit.Create(TTextRange.Create(TTextPosition.Create(DeclIndent, 0),
        TTextPosition.Create(DeclIndent, 0)), SectionIndent + 'var' + LineBreak)];
    end;
    if Position < Section.ChildCount - 1 then
    begin
      Next := Section[Position + 1];
      if (ADecl.EndPos.Line >= Next.StartPos.Line) or not IndentBefore(Next.StartPos, Dummy) then
        Exit;
      Edits := Edits + [TTextEdit.Create(TTextRange.Create(TTextPosition.Create(Next.StartPos.Line, 0),
        TTextPosition.Create(Next.StartPos.Line, 0)), SectionIndent + 'const' + LineBreak)];
    end;
    AFix := TRuleFix.Create('In var mit Initialwert umwandeln', Edits);
    Result := True;
  end;

  procedure Report(ATarget: TSyntaxNode; AsArgument: Boolean);
  var
    Symbol: TResolvedSymbol;
    Decl: TSyntaxNode;
    Fix: TRuleFix;
    Fixes: TArray<TRuleFix>;
    Code: string;
  begin
    if not ModifiedConstant(ATarget, Symbol) then
      Exit;
    Fixes := nil;
    Decl := DeclarationOf(Symbol);
    if (Decl <> nil) and VarFix(Decl, Fix) then
      Fixes := [Fix];
    // Mit {$J-} vor der Deklaration übersetzt Delphi die Änderung nicht.
    if (Decl <> nil) and (WriteableAt(Decl.StartPos) = TWriteable.Off) then
    begin
      if AsArgument then
        Code := 'E2197'
      else
        Code := 'E2064';
      AReport.AddWithSeverity(TTextRange.Create(ATarget.StartPos, ATarget.EndPos), Format('%s ist eine ' +
        'typisierte Konstante und kann ohne {$J+} nicht verändert werden (wie %s).', [Symbol.Name, Code]),
        TRuleSeverity.Error, Fixes);
      Exit;
    end;
    if AsArgument then
      Code := 'W1016'
    else
      Code := 'W1017';
    AReport.Add(TTextRange.Create(ATarget.StartPos, ATarget.EndPos), Format('%s ist eine typisierte Konstante ' +
      'und wird verändert (wie %s).', [Symbol.Name, Code]), TRuleConfidence.High, Fixes);
  end;

  procedure CheckCall(ANode: TSyntaxNode);
  var
    Callee: TSyntaxNode;
    Symbol, TypeInfo: TResolvedSymbol;
    TypeFound, Any: Boolean;
    VarArgs: TArray<Boolean>;
    Builtin: TArray<Integer>;
    Index, Position: Integer;
  begin
    if ANode.ChildCount < 2 then
      Exit;
    Any := False;
    for Index := 1 to ANode.ChildCount - 1 do
      if MentionsSuspect(ANode[Index]) then
        Any := True;
    if not Any then
      Exit;
    Callee := ANode[0];
    VarArgs := nil;
    EnsureResolver;
    if (Callee.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) and
      Resolver.NodeType(AContext.Tree, FileName, Callee, Symbol, TypeInfo, TypeFound) then
    begin
      // Überladungen können andere Parameter haben: dann keine Aussage.
      if not (Symbol.SymbolKind in [TIndexSymbolKind.Method, TIndexSymbolKind.Routine,
        TIndexSymbolKind.Constructor_]) or (Length(Symbol.Overloads) > 0) or (Length(Symbol.VariantParams) > 1) then
        Exit;
      VarArgs := VarParameters(Symbol.Signature);
    end
    else if Callee.Kind = TSyntaxKind.Identifier then
    begin
      Builtin := BuiltinVarArguments(Callee.Name);
      for Position in Builtin do
        if Position + 1 < ANode.ChildCount then
          Report(ANode[Position + 1], True);
      Exit;
    end;
    for Index := 1 to ANode.ChildCount - 1 do
      if (Index - 1 <= High(VarArgs)) and VarArgs[Index - 1] then
        Report(ANode[Index], True);
  end;

  /// <summary>0 als Wert einer Zeigerkonstante bzw. initialisierten Zeigervariable (W1013).</summary>
  procedure CheckZeroPointer(ANode: TSyntaxNode);
  var
    Value, TypeNode: TSyntaxNode;
    TypeInfo: TResolvedSymbol;
    IsPointer: Boolean;
  begin
    if ANode.ChildCount <> 2 then
      Exit;
    TypeNode := ANode[0];
    Value := ANode[1];
    if (Value.Kind <> TSyntaxKind.Literal) or (Trim(NodeText(Value)) <> '0') then
      Exit;
    IsPointer := (TypeNode.Kind = TSyntaxKind.PointerType) or
      ((TypeNode.Kind = TSyntaxKind.TypeReference) and IsPointerName(NodeText(TypeNode)));
    if not IsPointer and (TypeNode.Kind = TSyntaxKind.TypeReference) then
    begin
      EnsureResolver;
      TypeInfo := Resolver.ResolveType(AContext.Tree, FileName, TypeNode.StartPos);
      IsPointer := TypeInfo.Found and (TypeInfo.SymbolKind = TIndexSymbolKind.TypeAlias) and
        ((Pos('^', TypeBodyOf(TypeInfo.Signature)) = 1) or IsPointerName(TypeBodyOf(TypeInfo.Signature)));
    end;
    if not IsPointer then
      Exit;
    AReport.Add(TTextRange.Create(Value.StartPos, Value.EndPos), Format('%s ist ein Zeiger; die 0 wird zu nil ' +
      'umgewandelt (wie W1013).', [ANode.Name]), TRuleConfidence.High,
      [TRuleFix.Create('nil schreiben', [TTextEdit.Create(TTextRange.Create(Value.StartPos, Value.EndPos), 'nil')],
      True)]);
  end;

  procedure Visit(ANode: TSyntaxNode);
  var
    Index: Integer;
  begin
    case ANode.Kind of
      TSyntaxKind.AssignStatement:
        if ANode.ChildCount = 2 then
          Report(ANode[0], False);
      TSyntaxKind.Call:
        CheckCall(ANode);
      TSyntaxKind.ConstDecl, TSyntaxKind.VarDecl:
        CheckZeroPointer(ANode);
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
  LineBreak := TTextLines.LineBreakOf(AContext.Text);
  Lines := nil;
  Resolver := nil;
  LocalNames := TDictionary<string, Boolean>.Create;
  Suspects := TDictionary<string, Boolean>.Create;
  try
    CollectLocal(AContext.Tree.Root);
    Visit(AContext.Tree.Root);
  finally
    if Resolver <> nil then
    begin
      Resolver.UnpinTree;
      Resolver.Free;
    end;
    Suspects.Free;
    LocalNames.Free;
  end;
end;

procedure RegisterConstantRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TConstantExpressionErrorRule.Create);
  ARegistry.Register(TDefaultParameterInvalidRule.Create);
  ARegistry.Register(TSignedUnsignedMixRule.Create);
  ARegistry.Register(TNarrowingAssignmentRule.Create);
  ARegistry.Register(TTypedConstantModifiedRule.Create);
end;

end.
