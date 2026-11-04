unit Atlas.Common.Rules.Builtin.Constants;

// Regeln für Konstanten und Zahlen (#909, Gruppe Compiler vorab):
//   constant-expression-error  Fehler in einem konstanten Ausdruck (#992):
//                              Division durch null mit bekannten Operanden
//                              (E2098), Überlauf über den Bereich von Int64
//                              und UInt64 hinaus (E2099), Untergrenze über
//                              der Obergrenze eines Bereichs (array[5..1],
//                              E2011), Konstante außerhalb eines ganzzahligen
//                              Typs fester Größe bzw. eines Teilbereichstyps
//                              (E1012; nur Werte, die als gleich breite Zahl
//                              mit anderem Vorzeichen passen, wie $FFFFFFFF
//                              für Integer, als Warnung W1012), Hex-, Binär-
//                              oder Oktalliterale über 64 Bit (E2102, an Int64
//                              zugewiesen zusätzlich W1012). Dazu (#1372):
//                              konstanter Index außerhalb eines statischen
//                              Arrays der Datei und case-Marke außerhalb des
//                              Typs des case-Ausdrucks (E1012), Überlauf über
//                              High(Int64) mit lauter Operanden mit Vorzeichen
//                              (E2099), Menge über mehr als 256 Werte (E2028)
//                              und Zahlen statt Sichtbarkeiten in {$RTTI}
//                              (E2572). Zahlen in asm-Blöcken prüft
//                              asm-invalid (dcc meldet dort E2113, #1375).
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
//                              Int64>Integer und NativeInt>Integer), bei
//                              Gleitkomma wie W1072, Extended>Double W1066.
//                              Ganzzahlen ohne Code: W1071 meldet Delphi 13
//                              auch mit {$WARN IMPLICIT_INTEGER_CAST_LOSS ON}
//                              nicht (#1383).
//                              Zuweisungen und Inline-Variablen mit Wert;
//                              Operanden und ganzzahlige Rechnungen mit sicher
//                              bekanntem Typ. Korrekturen: ausdrücklich
//                              umwandeln; Zieltyp der Deklaration vergrößern.
//   typed-constant-modified    Typisierte Konstante verändert (#1014):
//                              Zuweisung (W1017, auch an Element oder Feld)
//                              und Übergabe als var- oder out-Argument samt
//                              Inc, Dec, Include, Exclude … (W1016); steht
//                              vor der Deklaration in derselben Datei {$J-},
//                              ist es ein Fehler (E2064 bzw. E2197), mit
//                              {$J+} schweigt die Regel wie dcc; {$J±}
//                              aus einer mit {$I} eingebundenen Datei zählt
//                              mit (#1328), eine unlesbare macht den Stand
//                              unbekannt. Dazu 0
//                              als Wert einer Zeigerkonstante (W1013).
//                              Korrekturen: globale Konstante in eine
//                              Variable mit Initialwert umwandeln; nil
//                              statt 0.
//   string-length-limit        String-Grenze überschritten (#1036): Literal,
//                              das an string[N]/ShortString gekürzt wird
//                              (Zuweisung, typisierte Konstante, initialisierte
//                              Variable; W1014), ein Literal über 255 Zeichen
//                              vor Delphi 12 (E2056) und ein resourcestring
//                              über 4096 Zeichen (E2381). Korrekturen: Ziel als
//                              string deklarieren; Literal teilen.
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

type
  TConstantExpressionErrorRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Ist das Zahl-Token ATokenText ein Hex-, Binär- oder Oktalliteral, das nicht in 64 Bit passt
    /// (wie E2102)? Dezimalzahlen macht Delphi zu Gleitkommazahlen, sie zählen nicht.</summary>
    class function TooLargeLiteral(const ATokenText: string): Boolean; static;
    /// <summary>Ist AValue außerhalb des ganzzahligen Typs fester Größe ATypeName ein Fehler (wie E1012)? Nur
    /// Werte, die in einen gleich breiten Typ mit anderem Vorzeichen passen ($FFFFFFFF für Integer, -1 für
    /// Cardinal), sind eine Warnung (wie W1012). False auch für Werte im Bereich und für andere Typen.</summary>
    class function OutsideIsError(AValue: Int64; const ATypeName: string): Boolean; static;
    /// <summary>Fehlerhafte Sichtbarkeitsmenge in einer {$RTTI}-Direktive (Text samt Klammern) wie
    /// "METHODS([1])"; '' ohne. Gemeldet werden nur Zahlen, Strings und Zeichen als Element (wie E2572).</summary>
    class function InvalidRttiVisibility(const ADirective: string): string; static;
  end;

  TDefaultParameterInvalidRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

procedure RegisterConstantRules(const ARegistry: TRuleRegistry);

implementation

uses
  Atlas.Common.Index.NameFacts,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.DirectiveNames,
  Atlas.Common.Pascal.ConditionalBranches,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Semantics.OrdinalConstants,
  Atlas.Common.Semantics.ConstantValues,
  Atlas.Common.Rules.TypedScope,
  Atlas.Common.Rules.Options,
  Atlas.Text.Lines,
  Atlas.Common.Rules.Builtin.Constants.Types,
  Atlas.Common.Rules.Builtin.Constants.Conversions,
  Atlas.Common.Rules.Builtin.Constants.TypedConstants;

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
begin
  Result := False;
  Text := StringReplace(ATokenText, '_', '', [rfReplaceAll]);
  if Length(Text) < 2 then
  begin
    Exit;
  end;
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
  for Index := 2 to Length(Text) do
  begin
    if Text[Index] = '0' then
    begin
      Continue;
    end;
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

class function TConstantExpressionErrorRule.OutsideIsError(AValue: Int64; const ATypeName: string): Boolean;
var
  mKind: TIntegerKind;
  mLow, mHigh: Int64;
begin
  Result := False;
  mKind := IntegerKindOf(ATypeName);
  if (mKind.Bits = 0) or not IntegerRange(ATypeName, mLow, mHigh) or ((AValue >= mLow) and (AValue <= mHigh)) then
  begin
    Exit;
  end;
  if mKind.Bits >= 64 then
  begin
    Exit(True);
  end;
  // Passt der Wert in den gleich breiten Typ mit anderem Vorzeichen, legt dcc die Bits nur anders aus und warnt
  // (W1012); sonst ist es ein Fehler (E1012, #1372).
  if mKind.Signed then
  begin
    Result := (AValue < mLow) or (AValue > (Int64(1) shl mKind.Bits) - 1);
  end
  else
  begin
    Result := (AValue > mHigh) or (AValue < -(Int64(1) shl (mKind.Bits - 1)));
  end;
end;

/// <summary>Position des ersten Zeichens ab AStart, das kein Leerraum ist.</summary>
function SkipBlanks(const AText: string; AStart: Integer): Integer;
begin
  Result := AStart;
  while (Result <= Length(AText)) and CharInSet(AText[Result], [' ', #9, #10, #13]) do
  begin
    Inc(Result);
  end;
end;

/// <summary>Position der schließenden Klammer zur öffnenden an AOpen; hinter dem Textende, wenn keine passt.</summary>
function MatchingParen(const AText: string; AOpen: Integer): Integer;
var
  mDepth: Integer;
begin
  mDepth := 0;
  Result := AOpen;
  while Result <= Length(AText) do
  begin
    if AText[Result] = '(' then
    begin
      Inc(mDepth);
    end
    else if AText[Result] = ')' then
    begin
      Dec(mDepth);
      if mDepth = 0 then
      begin
        Exit;
      end;
    end;
    Inc(Result);
  end;
end;

/// <summary>Ist AContent eine Menge mit einer Zahl, einem String oder einem Zeichen als Element? Nur solche sind
/// sicher keine Sichtbarkeiten; Namen können Konstanten vom Typ TVisibilityClass sein.</summary>
function HasLiteralElement(const AContent: string): Boolean;
var
  mElement: string;
begin
  Result := False;
  if (Length(AContent) < 2) or (AContent[1] <> '[') or (AContent[Length(AContent)] <> ']') then
  begin
    Exit;
  end;
  for mElement in Copy(AContent, 2, Length(AContent) - 2).Split(TArray<string>.Create(',', '..')) do
  begin
    if (Trim(mElement) <> '') and CharInSet(Trim(mElement)[1], ['0'..'9', '$', '%', '#', '''', '-', '+']) then
    begin
      Exit(True);
    end;
  end;
end;

class function TConstantExpressionErrorRule.InvalidRttiVisibility(const ADirective: string): string;
var
  mUpper, mKey: string;
  mStart, mOpen, mClose: Integer;
begin
  Result := '';
  mUpper := UpperCase(ADirective);
  for mKey in TArray<string>.Create('METHODS', 'FIELDS', 'PROPERTIES') do
  begin
    mStart := Pos(mKey, mUpper);
    if mStart = 0 then
    begin
      Continue;
    end;
    mOpen := SkipBlanks(mUpper, mStart + Length(mKey));
    if (mOpen > Length(mUpper)) or (mUpper[mOpen] <> '(') then
    begin
      Continue;
    end;
    mClose := MatchingParen(ADirective, mOpen);
    if (mClose <= Length(ADirective)) and
      HasLiteralElement(Trim(Copy(ADirective, mOpen + 1, mClose - mOpen - 1))) then
    begin
      Exit(Copy(ADirective, mStart, mClose - mStart + 1));
    end;
  end;
end;

/// <summary>Liegen die unteren 64 Bit des Hex- oder Binärliterals ATokenText über High(Int64)? Ein zu großes
/// Literal kürzt dcc auf 64 Bit; an Int64 zugewiesen warnt es dann zusätzlich (W1012, #1372).</summary>
function LowBitsAboveInt64(const ATokenText: string): Boolean;
var
  mText: string;
begin
  Result := False;
  mText := StringReplace(ATokenText, '_', '', [rfReplaceAll]);
  if Length(mText) < 2 then
  begin
    Exit;
  end;
  if mText[1] = '$' then
  begin
    mText := Copy(mText, 2, MaxInt);
    if Length(mText) < 16 then
    begin
      Exit;
    end;
    Result := CharInSet(mText[Length(mText) - 15], ['8'..'9', 'A'..'F', 'a'..'f']);
  end
  else if mText[1] = '%' then
  begin
    mText := Copy(mText, 2, MaxInt);
    Result := (Length(mText) >= 64) and (mText[Length(mText) - 63] = '1');
  end;
end;

/// <summary>Zahl der Werte eines eingebauten ganzzahligen Typs mit mehr als 256 Werten (Word, Integer …) als
/// Text; '' für andere.</summary>
function WideOrdinalValues(const ATypeName: string): string;
begin
  case IndexText(ATypeName, ['Word', 'UInt16', 'SmallInt', 'Int16', 'Integer', 'Int32', 'FixedInt', 'LongInt',
    'Cardinal', 'UInt32', 'FixedUInt', 'LongWord', 'Int64', 'UInt64', 'NativeInt', 'NativeUInt']) of
    0..3:
      Result := '65536';
    4..11:
      Result := '4294967296';
    12..15:
      Result := 'mehr als 4294967296';
  else
    Result := '';
  end;
end;

/// <summary>Kann dieser Knoten einen Überlauf auslösen? Multiplikation, große Zahlen und High/Low.</summary>
function OverflowCandidate(ANode: TSyntaxNode): Boolean;
begin
  case ANode.Kind of
    TSyntaxKind.BinaryExpr:
      Result := ANode.Name = '*';
    TSyntaxKind.Literal:
      Result := Length(ANode.Name) >= 10;
    TSyntaxKind.Identifier:
      Result := MatchText(ANode.Name, ['High', 'Low']);
  else
    Result := False;
  end;
end;

/// <summary>Enthält die Namensliste ANames (A,B) den Namen AName?</summary>
function NamesContain(const ANames, AName: string): Boolean;
var
  mName: string;
begin
  Result := False;
  for mName in ANames.Split([',']) do
  begin
    if SameText(Trim(mName), AName) then
    begin
      Exit(True);
    end;
  end;
end;

/// <summary>Zahl der Werte des Bereichs ALow..AHigh als Text, wenn es mehr als 256 sind; sonst ''.</summary>
function RangeValues(ALow, AHigh: Int64): string;
begin
  Result := '';
  if ALow > AHigh then
  begin
    Exit;
  end;
  // AHigh - ALow kann bei Low(Int64)..High(Int64) überlaufen; deshalb mit der Untergrenze vergleichen.
  if (ALow < 0) and (AHigh > High(Int64) + ALow) then
  begin
    Result := 'mehr als 4294967296';
  end
  else if AHigh - ALow >= 256 then
  begin
    Result := IntToStr(AHigh - ALow + 1);
  end;
end;

procedure TConstantExpressionErrorRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
type
  TKinds = set of TSyntaxKind;
var
  Scope: TTypedScope;
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
    if (ANode.ChildCount <> 2) or not MatchText(ANode.Name, ['div', 'mod']) or
      not ValueOf(ANode[1], Right) or (Right <> 0) or not ValueOf(ANode[0], Left) then
    begin
      Exit;
    end;
    if ANode[1].Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess] then
    begin
      Message := Format('Division durch null in einem konstanten Ausdruck (%s = 0, wie E2098).',
        [Copy(AContext.Text, ANode[1].StartOffset + 1, ANode[1].EndOffset - ANode[1].StartOffset)]);
    end
    else
    begin
      Message := 'Division durch null in einem konstanten Ausdruck (wie E2098).';
    end;
    AReport.Add(NodeRange(ANode), Message, TRuleConfidence.High);
  end;

  /// <summary>Kann der Ausdruck überhaupt überlaufen? Nur mit Multiplikation, großen Zahlen oder High/Low; so
  /// bleiben die meisten Ausdrücke ohne Namensauflösung.</summary>
  function MayOverflow(ANode: TSyntaxNode): Boolean;
  var
    Index: Integer;
    Node: TSyntaxNode;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Result := False;
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if OverflowCandidate(Node) then
        begin
          Exit(True);
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

  procedure CheckOverflow(ANode: TSyntaxNode);
  var
    Value: Int64;
  begin
    if IsExpressionRoot(ANode) and MayOverflow(ANode) and
      (Values.Check(ANode, Value) = TOrdinalStatus.Overflow) then
    begin
      AReport.Add(NodeRange(ANode),
        'Überlauf in einem konstanten Ausdruck: Das Ergebnis passt in keinen Ganzzahltyp (wie E2099).',
        TRuleConfidence.High);
    end;
  end;

  procedure CheckSubrange(ANode: TSyntaxNode);
  var
    Lowest, Highest: Int64;
  begin
    if (ANode.ChildCount = 2) and ValueOf(ANode[0], Lowest) and ValueOf(ANode[1], Highest) and
      (Lowest > Highest) then
    begin
      AReport.Add(NodeRange(ANode), Format('Die Untergrenze %d liegt über der Obergrenze %d (wie E2011).',
        [Lowest, Highest]), TRuleConfidence.High);
    end;
  end;

  /// <summary>Bereich des Typs ATypeName (Typ fester Größe oder Teilbereichstyp, aufgelöst an ANode); ASubrange
  /// sagt, ob es ein Teilbereichstyp ist.</summary>
  function TargetRange(ATypeNode: TSyntaxNode; const ATypeName: string; out ALow, AHigh: Int64;
    out ASubrange: Boolean): Boolean;
  var
    TypeSymbol: TResolvedSymbol;
  begin
    ASubrange := False;
    if IntegerRange(ATypeName, ALow, AHigh) then
    begin
      Exit(True);
    end;
    Result := False;
    if (ATypeNode = nil) or (ATypeName = '') or (Pos('<', ATypeName) > 0) then
    begin
      Exit;
    end;
    TypeSymbol := Resolver.ResolveType(AContext.Tree, FileName, ATypeNode.StartPos);
    Result := TypeSymbol.Found and SubrangeOf(TypeSymbol.Signature, ALow, AHigh);
    ASubrange := Result;
  end;

  /// <summary>Wert außerhalb des Zieltyps: ein Fehler wie E1012 (Delphi 13 bei Teilbereichstypen und bei Werten,
  /// die auch als Zahl mit anderem Vorzeichen nicht passen, #1372), sonst eine Warnung wie W1012.</summary>
  procedure ReportRange(AValueNode: TSyntaxNode; AValue, ALow, AHigh: Int64; const ATypeName: string;
    ASubrange: Boolean);
  begin
    if ASubrange or OutsideIsError(AValue, ATypeName) then
    begin
      AReport.Add(NodeRange(AValueNode), Format('%d liegt außerhalb des Bereichs von %s (%d..%d, wie E1012).',
        [AValue, ATypeName, ALow, AHigh]), TRuleConfidence.High);
    end
    else
    begin
      AReport.AddWithSeverity(NodeRange(AValueNode), Format(
        '%d liegt außerhalb des Bereichs von %s (%d..%d, wie W1012).', [AValue, ATypeName, ALow, AHigh]),
        TRuleSeverity.Warning, nil);
    end;
  end;

  /// <summary>Zu großes Literal an Int64: dcc kürzt es auf 64 Bit und warnt zusätzlich zu E2102 (W1012).</summary>
  procedure CheckTruncatedLiteral(AValueNode: TSyntaxNode; const ATypeName: string);
  var
    mKind: TIntegerKind;
  begin
    if (AValueNode.Kind <> TSyntaxKind.Literal) or not TooLargeLiteral(AValueNode.Name) or
      not LowBitsAboveInt64(AValueNode.Name) then
    begin
      Exit;
    end;
    mKind := IntegerKindOf(ATypeName);
    if (mKind.Bits = 64) and mKind.Signed then
    begin
      AReport.AddWithSeverity(NodeRange(AValueNode), Format(
        '%s passt auf 64 Bit gekürzt nicht in %s (wie W1012).', [AValueNode.Name, ATypeName]),
        TRuleSeverity.Warning, nil);
    end;
  end;

  /// <summary>Typisierte Konstante bzw. initialisierte Variable: Typ und Wert sind Kinder der Deklaration.</summary>
  procedure CheckInitializer(ADecl: TSyntaxNode);
  var
    TypeNode, ValueNode: TSyntaxNode;
    Value, Lowest, Highest: Int64;
    mSubrange: Boolean;
  begin
    if (ADecl.ChildCount < 2) or (ADecl[0].Kind <> TSyntaxKind.TypeReference) or (ADecl[0].ChildCount > 0) then
    begin
      Exit;
    end;
    TypeNode := ADecl[0];
    ValueNode := ADecl[ADecl.ChildCount - 1];
    if ValueNode.Kind = TSyntaxKind.TypeReference then
    begin
      Exit;
    end;
    CheckTruncatedLiteral(ValueNode, TypeNode.Name);
    if not ValueOf(ValueNode, Value) or not TargetRange(TypeNode, TypeNode.Name, Lowest, Highest, mSubrange) then
    begin
      Exit;
    end;
    if (Value < Lowest) or (Value > Highest) then
    begin
      ReportRange(ValueNode, Value, Lowest, Highest, TypeNode.Name, mSubrange);
    end;
  end;

  /// <summary>Zu großes Literal an eine Variable oder ein Feld: dcc kürzt es auf 64 Bit (W1012). True, wenn die
  /// Zuweisung so eine ist.</summary>
  function TruncatedAssignment(ATarget, ASource: TSyntaxNode): Boolean;
  var
    mSymbol, mTypeInfo: TResolvedSymbol;
    mTypeFound: Boolean;
  begin
    Result := (ASource.Kind = TSyntaxKind.Literal) and TooLargeLiteral(ASource.Name) and
      LowBitsAboveInt64(ASource.Name) and
      Resolver.NodeType(AContext.Tree, FileName, ATarget, mSymbol, mTypeInfo, mTypeFound) and
      (mSymbol.SymbolKind in [TIndexSymbolKind.Variable, TIndexSymbolKind.Field]);
    if Result then
    begin
      CheckTruncatedLiteral(ASource, mSymbol.TypeName);
    end;
  end;

  /// <summary>Bereich der Variablen oder des Felds ATarget: ganzzahliger Typ fester Größe oder Teilbereichstyp;
  /// ASubrange sagt, ob es ein Teilbereichstyp ist.</summary>
  function AssignedRange(ATarget: TSyntaxNode; out ATypeName: string; out ALow, AHigh: Int64;
    out ASubrange: Boolean): Boolean;
  var
    mSymbol, mTypeInfo: TResolvedSymbol;
    mTypeFound: Boolean;
  begin
    ATypeName := '';
    ALow := 0;
    AHigh := 0;
    ASubrange := False;
    Result := Resolver.NodeType(AContext.Tree, FileName, ATarget, mSymbol, mTypeInfo, mTypeFound) and
      (mSymbol.SymbolKind in [TIndexSymbolKind.Variable, TIndexSymbolKind.Field]);
    if not Result then
    begin
      Exit;
    end;
    ATypeName := mSymbol.TypeName;
    if IntegerRange(ATypeName, ALow, AHigh) then
    begin
      Exit;
    end;
    ASubrange := mTypeFound and SubrangeOf(mTypeInfo.Signature, ALow, AHigh);
    Result := ASubrange;
    if ASubrange then
    begin
      ATypeName := mTypeInfo.Name;
    end;
  end;

  procedure CheckAssignment(AStatement: TSyntaxNode);
  var
    mValue, mLow, mHigh: Int64;
    mTypeName: string;
    mSubrange: Boolean;
  begin
    if (AStatement.ChildCount <> 2) or
      not (AStatement[0].Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) or
      TruncatedAssignment(AStatement[0], AStatement[1]) then
    begin
      Exit;
    end;
    if not (AStatement[1].Kind in [TSyntaxKind.Literal, TSyntaxKind.UnaryExpr, TSyntaxKind.BinaryExpr,
      TSyntaxKind.ParenExpr, TSyntaxKind.Identifier, TSyntaxKind.MemberAccess, TSyntaxKind.Call]) or
      not ValueOf(AStatement[1], mValue) then
    begin
      Exit;
    end;
    // 0..127 passt in jeden ganzzahligen Typ; Teilbereichstypen prüft die Regel nur ab hier, damit nicht jede
    // Zuweisung einer kleinen Zahl die Namensauflösung braucht.
    if ((mValue < 0) or (mValue > 127)) and AssignedRange(AStatement[0], mTypeName, mLow, mHigh, mSubrange) and
      ((mValue < mLow) or (mValue > mHigh)) then
    begin
      ReportRange(AStatement[1], mValue, mLow, mHigh, mTypeName, mSubrange);
    end;
  end;

  /// <summary>Text des Knotens wie im Quelltext.</summary>
  function NodeText(ANode: TSyntaxNode): string;
  begin
    Result := Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
  end;

  /// <summary>Steht in ANode eine bedingte Direktive ({$IFDEF}, {$ELSE} …)? Dann ist der Inhalt unsicher.</summary>
  function HasConditional(ANode: TSyntaxNode): Boolean;
  var
    mIndex: Integer;
    mName: string;
    mTokens: TArray<TPascalToken>;
  begin
    Result := False;
    mTokens := AContext.Tree.Tokens;
    mIndex := TConstantValues.TokenFrom(mTokens, ANode.StartOffset);
    while (mIndex <= High(mTokens)) and (mTokens[mIndex].Offset < ANode.EndOffset) do
    begin
      if mTokens[mIndex].Kind = TPascalTokenKind.Directive then
      begin
        mName := TPascalLexer.DirectiveName(mTokens[mIndex].Text);
        if StartsText('IF', mName) or StartsText('ELSE', mName) or SameText(mName, 'ENDIF') then
        begin
          Exit(True);
        end;
      end;
      Inc(mIndex);
    end;
  end;

  /// <summary>Knoten der Art AKinds in diesem Baum, der die Zeile von ASymbol umfasst und dessen Namensliste
  /// (A,B) ASymbol.Name enthält; nil für Deklarationen anderer Dateien, ohne Treffer und mit bedingten
  /// Direktiven.</summary>
  function DeclarationOf(const ASymbol: TResolvedSymbol; AKinds: TKinds): TSyntaxNode;
  var
    mIndex, mLine: Integer;
    mNode: TSyntaxNode;
    mPending: TStack<TSyntaxNode>;
  begin
    Result := nil;
    if (ASymbol.Kind <> TResolvedKind.Local) and (ASymbol.FileName <> '') and not SameText(ASymbol.FileName,
      FileName) then
    begin
      Exit;
    end;
    mLine := ASymbol.SelectionRange.StartPos.Line;
    // Iterativ (Bericht M1).
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(AContext.Tree.Root);
      while (mPending.Count > 0) and (Result = nil) do
      begin
        mNode := mPending.Pop;
        if (mNode.StartPos.Line > mLine) or (mNode.EndPos.Line < mLine) then
        begin
          Continue;
        end;
        if (mNode.Kind in AKinds) and NamesContain(mNode.Name, ASymbol.Name) then
        begin
          Result := mNode;
        end;
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          mPending.Push(mNode[mIndex]);
        end;
      end;
    finally
      mPending.Free;
    end;
    if (Result <> nil) and HasConditional(Result) then
    begin
      Result := nil;
    end;
  end;

  /// <summary>Typ hinter dem benannten Typ ATypeNode, wenn er in dieser Datei sicher deklariert ist; sonst nil.</summary>
  function NamedTypeBody(ATypeNode: TSyntaxNode): TSyntaxNode;
  var
    mTypeSymbol: TResolvedSymbol;
    mDecl: TSyntaxNode;
    mIndex: Integer;
  begin
    Result := nil;
    if (ATypeNode.ChildCount > 0) or (Pos('.', ATypeNode.Name) > 0) then
    begin
      Exit;
    end;
    mTypeSymbol := Resolver.ResolveType(AContext.Tree, FileName, ATypeNode.StartPos);
    if not mTypeSymbol.Found or not Scope.DeclarationSure(mTypeSymbol, ATypeNode) then
    begin
      Exit;
    end;
    mDecl := DeclarationOf(mTypeSymbol, [TSyntaxKind.TypeDecl]);
    if mDecl = nil then
    begin
      Exit;
    end;
    for mIndex := 0 to mDecl.ChildCount - 1 do
    begin
      if not (mDecl[mIndex].Kind in [TSyntaxKind.GenericParams, TSyntaxKind.Attribute]) then
      begin
        Exit(mDecl[mIndex]);
      end;
    end;
  end;

  /// <summary>Statisches Array hinter dem Typknoten ATypeNode, auch über einen benannten Typ dieser Datei; nil bei
  /// dynamischen Arrays und anderen Typen.</summary>
  function StaticArrayOf(ATypeNode: TSyntaxNode): TSyntaxNode;
  var
    mType: TSyntaxNode;
  begin
    Result := nil;
    mType := ATypeNode;
    if mType.Kind = TSyntaxKind.TypeReference then
    begin
      mType := NamedTypeBody(mType);
    end;
    // Ein Kind mehr als die Indextypen: der Elementtyp. Ohne Indextyp ist das Array dynamisch.
    if (mType <> nil) and (mType.Kind = TSyntaxKind.ArrayType) and (mType.ChildCount >= 2) then
    begin
      Result := mType;
    end;
  end;

  function InWith(ANode: TSyntaxNode): Boolean;
  var
    mNode: TSyntaxNode;
  begin
    // Ein with-Objekt kann den Namen verdecken.
    mNode := ANode.Parent;
    while (mNode <> nil) and (mNode.Kind <> TSyntaxKind.WithStatement) do
    begin
      mNode := mNode.Parent;
    end;
    Result := mNode <> nil;
  end;

  /// <summary>Ist einer der Indizes von AAccess eine bekannte Konstante?</summary>
  function AnyConstantIndex(AAccess: TSyntaxNode): Boolean;
  var
    mIndex: Integer;
    mValue: Int64;
  begin
    Result := False;
    for mIndex := 1 to AAccess.ChildCount - 1 do
    begin
      if ValueOf(AAccess[mIndex], mValue) then
      begin
        Exit(True);
      end;
    end;
  end;

  /// <summary>Statisches Array, als das ABase in dieser Datei sicher deklariert ist; sonst nil.</summary>
  function IndexedArray(ABase: TSyntaxNode): TSyntaxNode;
  var
    mSymbol: TResolvedSymbol;
    mDecl: TSyntaxNode;
  begin
    Result := nil;
    mSymbol := Resolver.Resolve(AContext.Tree, FileName, ABase.StartPos);
    // Der Baum enthält beide Zweige von {$IFDEF} … {$ELSE}: Die Deklaration muss immer mit der Stelle gelten.
    if not mSymbol.Found or not (mSymbol.SymbolKind in [TIndexSymbolKind.Variable, TIndexSymbolKind.Field,
      TIndexSymbolKind.Constant]) or not Scope.DeclarationSure(mSymbol, ABase) then
    begin
      Exit;
    end;
    mDecl := DeclarationOf(mSymbol, [TSyntaxKind.VarDecl, TSyntaxKind.Field, TSyntaxKind.ConstDecl]);
    if (mDecl <> nil) and (mDecl.ChildCount > 0) then
    begin
      Result := StaticArrayOf(mDecl[0]);
    end;
  end;

  /// <summary>Bekannte Grenzen des Indextyps ABound (Teilbereich).</summary>
  function BoundsOf(ABound: TSyntaxNode; out ALow, AHigh: Int64): Boolean;
  begin
    ALow := 0;
    AHigh := 0;
    Result := (ABound.Kind = TSyntaxKind.SubrangeType) and (ABound.ChildCount = 2) and ValueOf(ABound[0], ALow) and
      ValueOf(ABound[1], AHigh);
  end;

  /// <summary>Meldet die Indizes von AAccess außerhalb der Grenzen von AArray.</summary>
  procedure ReportIndexes(AAccess, AArray: TSyntaxNode);
  var
    mIndex: Integer;
    mValue, mLow, mHigh: Int64;
  begin
    for mIndex := 1 to AAccess.ChildCount - 1 do
    begin
      if mIndex > AArray.ChildCount - 1 then
      begin
        Break;
      end;
      if BoundsOf(AArray[mIndex - 1], mLow, mHigh) and ValueOf(AAccess[mIndex], mValue) and
        ((mValue < mLow) or (mValue > mHigh)) then
      begin
        AReport.Add(NodeRange(AAccess[mIndex]), Format(
          'Index %d liegt außerhalb der Grenzen von %s (%d..%d, wie E1012).', [mValue, AAccess[0].Name, mLow, mHigh]),
          TRuleConfidence.High);
      end;
    end;
  end;

  /// <summary>Konstanter Index außerhalb eines statischen Arrays dieser Datei (wie E1012, #1372).</summary>
  procedure CheckIndex(AAccess: TSyntaxNode);
  var
    mArray: TSyntaxNode;
  begin
    // Erst die Indizes: Meist ist keiner konstant, dann bleibt die Namensauflösung aus.
    if (AAccess.ChildCount < 2) or (AAccess[0].Kind <> TSyntaxKind.Identifier) or not AnyConstantIndex(AAccess) or
      InWith(AAccess) then
    begin
      Exit;
    end;
    mArray := IndexedArray(AAccess[0]);
    if mArray <> nil then
    begin
      ReportIndexes(AAccess, mArray);
    end;
  end;

  /// <summary>Marken der case-Anweisung ACase ohne Bereiche.</summary>
  function CaseLabels(ACase: TSyntaxNode): TArray<TSyntaxNode>;
  var
    mItem: TSyntaxNode;
    mItemIndex, mLabelIndex, mCount: Integer;
  begin
    mCount := 0;
    for mItemIndex := 1 to ACase.ChildCount - 1 do
    begin
      mCount := mCount + ACase[mItemIndex].ChildCount;
    end;
    SetLength(Result, mCount);
    mCount := 0;
    for mItemIndex := 1 to ACase.ChildCount - 1 do
    begin
      mItem := ACase[mItemIndex];
      // Das letzte Kind ist die Anweisung, davor stehen die Marken.
      for mLabelIndex := 0 to mItem.ChildCount - 2 do
      begin
        if (mItem.Kind = TSyntaxKind.CaseItem) and (mItem[mLabelIndex].Kind <> TSyntaxKind.RangeExpr) then
        begin
          Result[mCount] := mItem[mLabelIndex];
          Inc(mCount);
        end;
      end;
    end;
    SetLength(Result, mCount);
  end;

  /// <summary>Liegt eine der Marken außerhalb von 0..127? Nur dann lohnt die Namensauflösung.</summary>
  function AnyWideLabel(const ALabels: TArray<TSyntaxNode>): Boolean;
  var
    mLabel: TSyntaxNode;
    mValue: Int64;
  begin
    Result := False;
    for mLabel in ALabels do
    begin
      if ValueOf(mLabel, mValue) and ((mValue < 0) or (mValue > 127)) then
      begin
        Exit(True);
      end;
    end;
  end;

  /// <summary>case-Marke außerhalb des ganzzahligen Typs fester Größe des case-Ausdrucks (wie E1012, #1372).
  /// Marken, die als Zahl mit anderem Vorzeichen passen, und Bereiche meldet comparison-always-constant.</summary>
  procedure CheckCaseLabels(ACase: TSyntaxNode);
  var
    mLabels: TArray<TSyntaxNode>;
    mLabel: TSyntaxNode;
    mSymbol, mTypeInfo: TResolvedSymbol;
    mValue, mLow, mHigh: Int64;
  begin
    mLabels := CaseLabels(ACase);
    // Erst die Marken: 0..127 passt in jeden Typ, dann bleibt die Namensauflösung aus. Typ wie in
    // comparison-always-constant: sicher bekannt und eingebaut.
    if not AnyWideLabel(mLabels) or not Scope.SureType(Unwrapped(ACase[0]), mSymbol, mTypeInfo) or
      not (mTypeInfo.Builtin or SameText(mTypeInfo.UnitName, 'System')) or
      not IntegerRange(mTypeInfo.Name, mLow, mHigh) then
    begin
      Exit;
    end;
    for mLabel in mLabels do
    begin
      if ValueOf(mLabel, mValue) and OutsideIsError(mValue, mTypeInfo.Name) then
      begin
        AReport.Add(NodeRange(mLabel), Format('%d liegt außerhalb des Bereichs von %s (%d..%d, wie E1012).',
          [mValue, mTypeInfo.Name, mLow, mHigh]), TRuleConfidence.High);
      end;
    end;
  end;

  /// <summary>Zahl der Werte des benannten Basistyps ABase als Text, wenn es mehr als 256 sind; sonst ''.</summary>
  function NamedSetValues(ABase: TSyntaxNode): string;
  var
    mSymbol, mTypeSymbol: TResolvedSymbol;
    mLow, mHigh: Int64;
  begin
    Result := '';
    mSymbol := Resolver.Resolve(AContext.Tree, FileName, ABase.StartPos);
    if not mSymbol.Found or SameText(mSymbol.UnitName, 'System') then
    begin
      // Eingebaute Typen haben keine Deklaration im Quelltext.
      Exit(WideOrdinalValues(ABase.Name));
    end;
    mTypeSymbol := Resolver.ResolveType(AContext.Tree, FileName, ABase.StartPos);
    if mTypeSymbol.Found and SubrangeOf(mTypeSymbol.Signature, mLow, mHigh) then
    begin
      Result := RangeValues(mLow, mHigh);
    end;
  end;

  /// <summary>Menge über einen Basistyp mit mehr als 256 Werten (wie E2028, #1372).</summary>
  procedure CheckSetSize(ASet: TSyntaxNode);
  var
    mBase: TSyntaxNode;
    mLow, mHigh: Int64;
    mValues: string;
  begin
    if ASet.ChildCount <> 1 then
    begin
      Exit;
    end;
    mBase := ASet[0];
    mValues := '';
    if (mBase.Kind = TSyntaxKind.SubrangeType) and (mBase.ChildCount = 2) and ValueOf(mBase[0], mLow) and
      ValueOf(mBase[1], mHigh) then
    begin
      mValues := RangeValues(mLow, mHigh);
    end
    else if (mBase.Kind = TSyntaxKind.TypeReference) and (mBase.ChildCount = 0) and (Pos('.', mBase.Name) = 0) then
    begin
      mValues := NamedSetValues(mBase);
    end;
    if mValues <> '' then
    begin
      AReport.Add(NodeRange(ASet), Format('%s hat %s Werte; eine Menge darf höchstens 256 Elemente haben (wie E2028).',
        [NodeText(ASet), mValues]), TRuleConfidence.High);
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
          TSyntaxKind.BinaryExpr:
            begin
              CheckDivision(Node);
              CheckOverflow(Node);
            end;
          TSyntaxKind.UnaryExpr:
            CheckOverflow(Node);
          TSyntaxKind.SubrangeType:
            CheckSubrange(Node);
          TSyntaxKind.ConstDecl, TSyntaxKind.VarDecl:
            CheckInitializer(Node);
          TSyntaxKind.AssignStatement:
            CheckAssignment(Node);
          TSyntaxKind.IndexAccess:
            CheckIndex(Node);
          TSyntaxKind.CaseStatement:
            CheckCaseLabels(Node);
          TSyntaxKind.SetType:
            CheckSetSize(Node);
        else
          // Übrige Werte bewusst ohne Wirkung.
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

  /// <summary>Liegt AOffset in einem asm-Block? Zahlen dort prüft asm-invalid (dcc meldet E2113, #1375).</summary>
  function InAsm(AOffset: Integer): Boolean;
  var
    mFound: TSyntaxNode;
  begin
    mFound := AContext.Tree.Root.Search(
      function(ANode: TSyntaxNode): TSyntaxSearchStep
      begin
        if (AOffset < ANode.StartOffset) or (AOffset >= ANode.EndOffset) then
        begin
          Result := TSyntaxSearchStep.Skip;
        end
        else if ANode.Kind = TSyntaxKind.AsmBlock then
        begin
          Result := TSyntaxSearchStep.Found;
        end
        else
        begin
          Result := TSyntaxSearchStep.Descend;
        end;
      end);
    Result := mFound <> nil;
  end;

  /// <summary>Zahlen über 64 Bit (E2102) und Zahlen statt Sichtbarkeiten in {$RTTI} (E2572).</summary>
  procedure CheckTokens;
  var
    mToken: TPascalToken;
    mTokens: TArray<TPascalToken>;
    mPaths: TArray<string>;
    mIndex: Integer;
    mPathsKnown: Boolean;
    mVisibility: string;
  begin
    mTokens := AContext.Tree.Tokens;
    mPathsKnown := False;
    for mIndex := 0 to High(mTokens) do
    begin
      mToken := mTokens[mIndex];
      mVisibility := '';
      if (mToken.Kind = TPascalTokenKind.Number) and TooLargeLiteral(mToken.Text) and not InAsm(mToken.Offset) then
      begin
        AReport.Add(TTextRange.Create(mToken.StartPos, mToken.EndPos),
          Format('Ganzzahlkonstante zu groß: %s passt nicht in 64 Bit (wie E2102).', [mToken.Text]),
          TRuleConfidence.High);
      end
      else if (mToken.Kind = TPascalTokenKind.Directive) and (TPascalLexer.DirectiveName(mToken.Text) = 'RTTI') then
      begin
        mVisibility := InvalidRttiVisibility(mToken.Text);
      end;
      // Nur außerhalb bedingter Zweige: Einen Zweig, den dcc nicht übersetzt, prüft es auch nicht.
      if (mVisibility <> '') and not mPathsKnown then
      begin
        mPaths := TConditionalBranches.Paths(mTokens);
        mPathsKnown := True;
      end;
      if (mVisibility <> '') and (TConditionalBranches.PathAt(mPaths, mIndex) = '') then
      begin
        AReport.Add(TTextRange.Create(mToken.StartPos, mToken.EndPos), Format(
          '%s in {$RTTI} ist keine Menge aus vcPrivate, vcProtected, vcPublic und vcPublished (wie E2572).',
          [mVisibility]), TRuleConfidence.High);
      end;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  CheckTokens;
  Scope := TTypedScope.Create(AContext);
  try
    FileName := Scope.FileName;
    Resolver := Scope.Resolver;
    Values := Scope.Values;
    Visit(AContext.Tree.Root);
  finally
    Scope.Free;
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
  Cache: IRuleDerivedCache;

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
    begin
      Exit;
    end;
    Result := Header.Name;
    Node := Header.Parent;
    while (Node <> nil) and not (Node.Kind in [TSyntaxKind.TypeDecl, TSyntaxKind.RoutineDecl,
      TSyntaxKind.ImplementationSection]) do
    begin
      Node := Node.Parent;
    end;
    if (Node <> nil) and (Node.Kind = TSyntaxKind.TypeDecl) then
    begin
      Result := Node.Name + '.' + Result;
    end;
  end;

  function NamesKey(AParameters: TSyntaxNode): string;
  var
    Index: Integer;
  begin
    Result := '';
    for Index := 0 to AParameters.ChildCount - 1 do
    begin
      if AParameters[Index].Kind = TSyntaxKind.Parameter then
      begin
        Result := Result + LowerCase(AParameters[Index].Name) + ';';
      end;
    end;
  end;

  function FindPaired(ANode, AParameters: TSyntaxNode; const AName, AKey: string): TSyntaxNode;
  var
    Index: Integer;
    Node: TSyntaxNode;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Result := nil;
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if (Node.Kind = TSyntaxKind.Parameters) and (Node <> AParameters) and
          SameText(QualifiedRoutine(Node), AName) and (NamesKey(Node) = AKey) then
        begin
          Exit(Node);
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

  /// <summary>Der zugehörige Kopf in derselben Datei: Deklaration zur Implementierung und umgekehrt.</summary>
  function PairedParameters(AParameters: TSyntaxNode): TSyntaxNode;
  var
    Name: string;
  begin
    Result := nil;
    Name := QualifiedRoutine(AParameters);
    if Name <> '' then
    begin
      Result := FindPaired(AContext.Tree.Root, AParameters, Name, NamesKey(AParameters));
    end;
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
      begin
        Continue;
      end;
      if Pos(';' + LowerCase(Parameter.Name) + ';', ADefaults) > 0 then
      begin
        Back := Back + [NodeText(Parameter)];
      end
      else
      begin
        Front := Front + [NodeText(Parameter)];
      end;
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
    begin
      if AParameters[Index].Kind = TSyntaxKind.Parameter then
      begin
        if First = nil then
        begin
          First := AParameters[Index];
        end;
        Last := AParameters[Index];
      end;
    end;
    Result := First <> nil;
    if Result then
    begin
      ARange := TTextRange.Create(First.StartPos, Last.EndPos);
    end;
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
    begin
      if AParameters[Index].Kind = TSyntaxKind.Parameter then
      begin
        if Pos(',', AParameters[Index].Name) > 0 then
        begin
          Exit;
        end;
        if HasDefault(AParameters[Index]) then
        begin
          Defaults := Defaults + LowerCase(AParameters[Index].Name) + ';';
        end;
      end
      else
      begin
        Exit;
      end;
    end;
    if not ListRange(AParameters, Range) then
    begin
      Exit;
    end;
    Edits := [TTextEdit.Create(Range, Reordered(AParameters, Defaults))];
    Paired := PairedParameters(AParameters);
    if (Paired <> nil) and ListRange(Paired, Range) then
    begin
      Edits := Edits + [TTextEdit.Create(Range, Reordered(Paired, Defaults))];
    end;
    AFix := TRuleFix.Create('Parameter mit Standardwert ans Ende verschieben', Edits);
    Result := True;
  end;

  procedure EnsureResolver;
  begin
    // Erst hier die Namensauflösung: Die meisten Dateien haben keinen Standardwert mit eigenem Typ.
    if Resolver = nil then
    begin
      // Resolver des Laufs (TRuleDerived.Resolver); gehört dem Cache.
      Cache := TRuleDerived.Open(AContext);
      Resolver := TRuleDerived.Resolver(Cache, AContext);
      Resolver.PinTree(AContext.Tree, FileName);
    end;
  end;

  /// <summary>Anzahl der Werte einer Aufzählung "(a, b, c)"; 0, wenn es keine ist.</summary>
  function EnumCount(const ABody: string): Integer;
  begin
    Result := 0;
    if ABody.StartsWith('(') and ABody.EndsWith(')') then
    begin
      Result := Length(ABody.Split([',']));
    end;
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
    begin
      Exit(True);
    end;
    if EnumCount(Base) > 0 then
    begin
      Exit(EnumCount(Base) > 32);
    end;
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
    begin
      Exit;
    end;
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

  /// <summary>A, B: Integer = 0 wird A: Integer = 0; B: Integer = 0.</summary>
  function SeparateDeclarations(AParameter: TSyntaxNode; const ANames: TArray<string>): string;
  var
    mName: string;
  begin
    Result := '';
    for mName in ANames do
    begin
      if Result <> '' then
      begin
        Result := Result + '; ';
      end;
      Result := Result + ModifierText(AParameter) + Trim(mName) + ': ' + TypeAndDefault(AParameter);
    end;
  end;

  /// <summary>Typ ohne Standardwerte: Record oder statisches Array (E2268), Menge über 4 Byte (E2146).</summary>
  procedure CheckDefaultType(AParameter: TSyntaxNode);
  var
    mType: TResolvedSymbol;
  begin
    if not ParameterType(AParameter[0], mType) then
    begin
      Exit;
    end;
    if NoDefaultType(mType) then
    begin
      AReport.Add(NodeRange(AParameter), Format('Parameter vom Typ %s können keinen Standardwert haben ' +
        '(wie E2268).', [AParameter[0].Name]), TRuleConfidence.High);
    end
    else if LargeSetType(mType) then
    begin
      AReport.Add(NodeRange(AParameter), Format('%s ist eine Menge über 4 Byte; Standardwerte gibt es nur ' +
        'für ordinale, Zeiger- und kleine Mengentypen (wie E2146).', [AParameter[0].Name]),
        TRuleConfidence.Medium);
    end;
  end;

  /// <summary>Parameter mit Standardwert: mehrere Namen (E2237), var/out (E2239) und unzulässiger Typ.</summary>
  procedure CheckDefaultParameter(AParameter: TSyntaxNode);
  var
    mNames: TArray<string>;
  begin
    mNames := AParameter.Name.Split([',']);
    if Length(mNames) > 1 then
    begin
      AReport.Add(NodeRange(AParameter), Format('%s: Standardwerte gibt es nur für einzeln deklarierte ' +
        'Parameter (wie E2237).', [StringReplace(AParameter.Name, ',', ', ', [rfReplaceAll])]),
        TRuleConfidence.High, [TRuleFix.Create('Parameter einzeln deklarieren',
        [TTextEdit.Create(NodeRange(AParameter), SeparateDeclarations(AParameter, mNames))])]);
    end;
    if AParameter.Modifier in [TParameterModifier.VarParam, TParameterModifier.OutParam] then
    begin
      AReport.Add(NodeRange(AParameter), Format('%s ist ein %s-Parameter und kann keinen Standardwert haben ' +
        '(wie E2239).', [AParameter.Name, Trim(ModifierText(AParameter))]), TRuleConfidence.High);
    end
    else
    begin
      CheckDefaultType(AParameter);
    end;
  end;

  /// <summary>Parameter ohne Standardwert nach einem mit (E2238); AWithFix hängt die Korrektur an.</summary>
  procedure ReportMissingDefault(AParameters, AParameter: TSyntaxNode; AWithFix: Boolean);
  var
    mFix: TRuleFix;
    mFixes: TArray<TRuleFix>;
  begin
    mFixes := nil;
    if AWithFix and MoveFix(AParameters, mFix) then
    begin
      mFixes := [mFix];
    end;
    AReport.Add(NodeRange(AParameter), Format('%s braucht einen Standardwert, weil ein vorheriger Parameter ' +
      'einen hat (wie E2238).', [StringReplace(AParameter.Name, ',', ', ', [rfReplaceAll])]),
      TRuleConfidence.High, mFixes);
  end;

  procedure CheckParameters(AParameters: TSyntaxNode);
  var
    mIndex: Integer;
    mParameter: TSyntaxNode;
    mSeenDefault, mMoved: Boolean;
  begin
    mSeenDefault := False;
    mMoved := False;
    for mIndex := 0 to AParameters.ChildCount - 1 do
    begin
      mParameter := AParameters[mIndex];
      if mParameter.Kind <> TSyntaxKind.Parameter then
      begin
        Continue;
      end;
      if HasDefault(mParameter) then
      begin
        mSeenDefault := True;
        CheckDefaultParameter(mParameter);
      end
      else if mSeenDefault then
      begin
        // Die Korrektur nur am ersten betroffenen Parameter; sie ordnet die ganze Liste.
        ReportMissingDefault(AParameters, mParameter, not mMoved);
        mMoved := True;
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
        if Node.Kind = TSyntaxKind.Parameters then
        begin
          CheckParameters(Node);
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
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  FileName := AContext.FileName;
  if FileName = '' then
  begin
    FileName := AContext.RelativePath;
  end;
  if FileName = '' then
  begin
    FileName := AContext.UnitName + '.pas';
  end;
  Resolver := nil;
  try
    Visit(AContext.Tree.Root);
  finally
    if Resolver <> nil then
    begin
      Resolver.UnpinTree;
    end;
  end;
end;

procedure RegisterConstantRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TConstantExpressionErrorRule.Create);
  ARegistry.Register(TDefaultParameterInvalidRule.Create);
  ARegistry.Register(TSignedUnsignedMixRule.Create);
  ARegistry.Register(TNarrowingAssignmentRule.Create);
  ARegistry.Register(TTypedConstantModifiedRule.Create);
  ARegistry.Register(TStringLengthLimitRule.Create);
end;

end.
