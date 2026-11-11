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
//                     des Ausdrucks (wie W1018; einzelne Marken, die dcc als
//                     Fehler E1012 meldet, meldet constant-expression-error,
//                     #1372). Die Konstante rechnet
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
  cComparisonAlwaysConstantRuleId = 'comparison-always-constant';
  cConstantInitializerMismatchRuleId = 'constant-initializer-mismatch';
  cCaseSelectorNotOrdinalRuleId = 'case-selector-not-ordinal';
  cSuspiciousStringPointerCastRuleId = 'suspicious-string-pointer-cast';

type
  TComparisonAlwaysConstantRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Ergebnis von "X AOperator AValue" für X im Bereich ALow..AHigh: 1 immer wahr, 0 immer falsch,
    /// -1 abhängig von X. AOperator ist = &lt;&gt; &lt; &lt;= &gt; &gt;=.</summary>
    class function Outcome(const AOperator: string; AValue, ALow, AHigh: Int64): Integer; overload; static;
    /// <summary>Wie oben; AHighKnown False: Die Obergrenze liegt über High(Int64) (UInt64, #1324), kein Wert
    /// erreicht sie.</summary>
    class function Outcome(const AOperator: string; AValue, ALow, AHigh: Int64; AHighKnown: Boolean): Integer;
      overload; static;
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
  Atlas.Common.Pascal.TokenCursor,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Semantics.ConstantValues,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Rules.TypedScope,
  Atlas.Common.Rules.Builtin.Constants,
  Atlas.Common.Editing.EnumTables,
  Atlas.Text.Lines,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TTypedExpressionsText = (AlwaysTitle, NeverEnds, NeverRuns, NeverNegativeTrue, NeverNegativeFalse, AlwaysTrue,
    AlwaysFalse, OutOfRange, InitTitle, FieldOrder, SortFields, AddPlaceholders, CountMismatch, ValueOne, ValueMany,
    EntryOne, EntryMany, OrdinalTitle, ToCaseIndexStr, CaseOrdinal, ForOrdinal, AParameter, AVariable, AField,
    AProperty, ATypedConstant, NotConstant, CaseLabel, ArrayBound, PointerTitle, DeclareString, WideGarbage,
    AnsiFirstOnly, ConvertTo, UsePointerType, LikeE2072, MissingOne, MissingMany, MissingMore);

const
  cTexts: array[TTypedExpressionsText] of TAtlasText = (
    (De: 'Vergleich immer wahr oder immer falsch'; En: 'Comparison always true or always false'),
    (De: ', die Schleife endet nie'; En: ', the loop never ends'),
    (De: ', die Schleife läuft nie'; En: ', the loop never runs'),
    (De: '%s ist nie negativ; %s ist immer wahr%s (dcc meldet das nicht).';
     En: '%s is never negative; %s is always true%s (dcc does not report this).'),
    (De: '%s ist nie negativ; %s ist immer falsch%s (dcc meldet das nicht).';
     En: '%s is never negative; %s is always false%s (dcc does not report this).'),
    (De: '%s ist %s; %s ist immer wahr%s (wie W1022).'; En: '%s is %s; %s is always true%s (like W1022).'),
    (De: '%s ist %s; %s ist immer falsch%s (wie W1021).'; En: '%s is %s; %s is always false%s (like W1021).'),
    (De: '%s liegt außerhalb des Bereichs von %s; der Zweig wird nie ausgeführt (wie W1018).';
     En: '%s lies outside the range of %s; the branch is never executed (like W1018).'),
    (De: 'Initialisierung einer Konstanten passt nicht'; En: 'Initialization of a constant does not fit'),
    (De: '%s steht in %s vor %s; die Felder müssen in der Reihenfolge der Deklaration stehen (wie E2083).';
     En: '%s is in %s before %s; the fields must be in the order of declaration (like E2083).'),
    (De: 'Felder in die Reihenfolge der Deklaration bringen'; En: 'Put the fields in the order of declaration'),
    (De: 'Fehlende Einträge mit Platzhalter ergänzen'; En: 'Add missing entries with placeholder'),
    (De: '%s hat %s, die Konstante %s'; En: '%s has %s, the constant %s'),
    (De: 'Wert'; En: 'value'),
    (De: 'Werte'; En: 'values'),
    (De: 'Eintrag'; En: 'entry'),
    (De: 'Einträge'; En: 'entries'),
    (De: 'case oder for über einen nicht ordinalen Typ'; En: 'case or for over a non-ordinal type'),
    (De: 'In case IndexStr(…) of umwandeln'; En: 'Convert to case IndexStr(…) of'),
    (De: 'case braucht einen ordinalen Typ; %s ist %s (wie E2001).';
     En: 'case needs an ordinal type; %s is %s (like E2001).'),
    (De: 'for braucht eine ordinale Zählvariable; %s ist %s (wie E2032).';
     En: 'for needs an ordinal counter variable; %s is %s (like E2032).'),
    (De: 'ein Parameter'; En: 'a parameter'),
    (De: 'eine Variable'; En: 'a variable'),
    (De: 'ein Feld'; En: 'a field'),
    (De: 'eine Property'; En: 'a property'),
    (De: 'eine typisierte Konstante'; En: 'a typed constant'),
    (De: '%s %s ist %s, keine Konstante (wie E2026).'; En: '%s %s is %s, not a constant (like E2026).'),
    (De: 'Die case-Marke'; En: 'The case label'),
    (De: 'Die Arraygrenze'; En: 'The array bound'),
    (De: 'Zeiger und Zeichenbreite eines Strings passen nicht zusammen';
     En: 'Pointer and character width of a string do not match'),
    (De: '%s als string deklarieren'; En: 'Declare %s as string'),
    (De: '%s zeigt auf WideChar, %s ist %s; die API liest Datenmüll (wie W1044).';
     En: '%s points to WideChar, %s is %s; the API reads garbage (like W1044).'),
    (De: '%s zeigt auf AnsiChar, %s ist %s; die API liest nur das erste Zeichen (wie W1044).';
     En: '%s points to AnsiChar, %s is %s; the API reads only the first character (like W1044).'),
    (De: 'In %s umwandeln: %s(%s(…))'; En: 'Convert to %s: %s(%s(…))'),
    (De: 'Passenden Zeigertyp verwenden: %s'; En: 'Use matching pointer type: %s'),
    (De: ' (wie E2072).'; En: ' (like E2072).'),
    (De: '; %s fehlt'; En: '; %s is missing'),
    (De: '; %s fehlen'; En: '; %s are missing'),
    (De: '; %s … fehlen'; En: '; %s … are missing'));

{$SCOPEDENUMS OFF}

{ TComparisonAlwaysConstantRule }

function TComparisonAlwaysConstantRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cComparisonAlwaysConstantRuleId, TRuleSeverity.Warning,
    cTexts[TTypedExpressionsText.AlwaysTitle].Text);
end;

class function TComparisonAlwaysConstantRule.Outcome(const AOperator: string; AValue, ALow, AHigh: Int64): Integer;
begin
  Result := Outcome(AOperator, AValue, ALow, AHigh, True);
end;

class function TComparisonAlwaysConstantRule.Outcome(const AOperator: string; AValue, ALow, AHigh: Int64;
  AHighKnown: Boolean): Integer;
var
  mAbove, mAtHigh, mBelow, mAtLow, mTrue, mFalse: Boolean;
begin
  // Ohne bekannte Obergrenze liegt kein Int64-Wert auf oder über ihr.
  mAbove := AHighKnown and (AValue > AHigh);
  mAtHigh := AHighKnown and (AValue >= AHigh);
  mBelow := AValue < ALow;
  mAtLow := AValue <= ALow;
  mTrue := False;
  mFalse := False;
  case IndexStr(AOperator, ['=', '<>', '<', '<=', '>', '>=']) of
    0:
      mFalse := mBelow or mAbove;
    1:
      mTrue := mBelow or mAbove;
    2:
      begin
        mTrue := mAbove;
        mFalse := mAtLow;
      end;
    3:
      begin
        mTrue := mAtHigh;
        mFalse := mBelow;
      end;
    4:
      begin
        mTrue := mBelow;
        mFalse := mAtHigh;
      end;
    5:
      begin
        mTrue := mAtLow;
        mFalse := mAbove;
      end;
  else
    // Andere Operatoren: kein Urteil.
  end;
  Result := -1;
  if mTrue then
  begin
    Result := 1;
  end
  else if mFalse then
  begin
    Result := 0;
  end;
end;

/// <summary>Operator mit vertauschten Seiten: 0 &lt; X ist X &gt; 0.</summary>
function Mirrored(const AOperator: string): string;
begin
  Result := AOperator;
  if AOperator = '<' then
  begin
    Result := '>';
  end
  else if AOperator = '>' then
  begin
    Result := '<';
  end
  else if AOperator = '<=' then
  begin
    Result := '>=';
  end
  else if AOperator = '>=' then
  begin
    Result := '<=';
  end;
end;

procedure TComparisonAlwaysConstantRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mScope: TTypedScope;

  /// <summary>Wertebereich von ANode, wenn sein Typ sicher ein eingebauter Ganzzahltyp ist.</summary>
  function IntegerOperand(ANode: TSyntaxNode; out ATypeName: string; out ALow, AHigh: Int64): Boolean;
  var
    mSymbol, mTypeInfo: TResolvedSymbol;
  begin
    Result := mScope.SureType(ANode, mSymbol, mTypeInfo) and (mTypeInfo.Builtin or SameText(mTypeInfo.UnitName,
      'System')) and TConstantValues.IntegerRange(mTypeInfo.Name, ALow, AHigh);
    if Result then
    begin
      ATypeName := mTypeInfo.Name;
    end;
  end;

  /// <summary>", die Schleife endet nie" bzw. "läuft nie", wenn ANode die ganze Bedingung einer Schleife ist.
  /// </summary>
  function LoopNote(ANode: TSyntaxNode; AAlways: Boolean): string;
  var
    mNode: TSyntaxNode;
  begin
    Result := '';
    mNode := ANode;
    while (mNode.Parent <> nil) and (mNode.Parent.Kind = TSyntaxKind.ParenExpr) do
    begin
      mNode := mNode.Parent;
    end;
    if mNode.Parent = nil then
    begin
      Exit;
    end;
    if (mNode.Parent.Kind = TSyntaxKind.WhileStatement) and (mNode.Parent[0] = mNode) then
    begin
      if AAlways then
      begin
        Result := cTexts[TTypedExpressionsText.NeverEnds].Text;
      end
      else
      begin
        Result := cTexts[TTypedExpressionsText.NeverRuns].Text;
      end;
    end
    else if (mNode.Parent.Kind = TSyntaxKind.RepeatStatement) and
      (mNode.Parent[mNode.Parent.ChildCount - 1] = mNode) and
      not AAlways then
    begin
      Result := cTexts[TTypedExpressionsText.NeverEnds].Text;
    end;
  end;

  /// <summary>Ist ANode ein Aufruf von Length aus System (nie negativ)?</summary>
  function IsLengthCall(ANode: TSyntaxNode): Boolean;
  var
    mCallee: TResolvedSymbol;
  begin
    Result := (ANode <> nil) and (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount = 2) and
      (ANode[0].Kind = TSyntaxKind.Identifier) and SameText(ANode[0].Name, 'Length');
    if not Result then
    begin
      Exit;
    end;
    // Eine eigene Funktion Length kann negativ werden.
    mCallee := mScope.Resolver.Resolve(AContext.Tree, mScope.FileName, ANode[0].StartPos);
    Result := not mCallee.Found or SameText(mCallee.UnitName, 'System');
  end;

  /// <summary>Operand und Wert eines Vergleichs mit einer Konstanten; AOperation gilt danach mit dem Operanden
  /// links.</summary>
  function ConstantSide(ANode: TSyntaxNode; out AOperand: TSyntaxNode; out AValue: Int64;
    out AOperation: string): Boolean;
  begin
    Result := True;
    AOperation := ANode.Name;
    if mScope.Values.EvaluateNode(Unwrapped(ANode[1]), AValue) then
    begin
      AOperand := Unwrapped(ANode[0]);
    end
    else if mScope.Values.EvaluateNode(Unwrapped(ANode[0]), AValue) then
    begin
      AOperand := Unwrapped(ANode[1]);
      AOperation := Mirrored(AOperation);
    end
    else
    begin
      Result := False;
    end;
  end;

  procedure ReportLength(ANode, AOperand: TSyntaxNode; AVerdict: Integer);
  var
    mNote: string;
  begin
    mNote := LoopNote(ANode, AVerdict = 1);
    if AVerdict = 1 then
    begin
      AReport.Add(TTextRange.Create(ANode.StartPos, ANode.EndPos),
        cTexts[TTypedExpressionsText.NeverNegativeTrue].Fmt([mScope.Text(AOperand), mScope.Text(ANode),
        mNote]), TRuleConfidence.High);
    end
    else
    begin
      AReport.Add(TTextRange.Create(ANode.StartPos, ANode.EndPos),
        cTexts[TTypedExpressionsText.NeverNegativeFalse].Fmt([mScope.Text(AOperand), mScope.Text(ANode),
        mNote]), TRuleConfidence.High);
    end;
  end;

  procedure ReportRange(ANode, AOperand: TSyntaxNode; const ATypeName: string; AVerdict: Integer);
  var
    mNote: string;
  begin
    mNote := LoopNote(ANode, AVerdict = 1);
    if AVerdict = 1 then
    begin
      AReport.Add(TTextRange.Create(ANode.StartPos, ANode.EndPos), cTexts[TTypedExpressionsText.AlwaysTrue].Fmt(
        [mScope.Text(AOperand), ATypeName, mScope.Text(ANode), mNote]), TRuleConfidence.High);
    end
    else
    begin
      AReport.Add(TTextRange.Create(ANode.StartPos, ANode.EndPos), cTexts[TTypedExpressionsText.AlwaysFalse].Fmt(
        [mScope.Text(AOperand), ATypeName, mScope.Text(ANode), mNote]), TRuleConfidence.High);
    end;
  end;

  procedure CheckComparison(ANode: TSyntaxNode);
  var
    mOperand: TSyntaxNode;
    mValue, mLow, mHigh: Int64;
    mOperation, mTypeName: string;
    mVerdict: Integer;
  begin
    if (ANode.ChildCount <> 2) or not ConstantSide(ANode, mOperand, mValue, mOperation) then
    begin
      Exit;
    end;
    if IsLengthCall(mOperand) then
    begin
      mVerdict := Outcome(mOperation, mValue, 0, High(Int64));
      if mVerdict >= 0 then
      begin
        ReportLength(ANode, mOperand, mVerdict);
      end;
      Exit;
    end;
    if not IntegerOperand(mOperand, mTypeName, mLow, mHigh) then
    begin
      Exit;
    end;
    // UInt64, NativeUInt und LongWord (64 Bit je Plattform) reichen über High(Int64) hinaus (#1324).
    mVerdict := Outcome(mOperation, mValue, mLow, mHigh, not MatchText(mTypeName, ['UInt64', 'NativeUInt',
      'LongWord']));
    if mVerdict >= 0 then
    begin
      ReportRange(ANode, mOperand, mTypeName, mVerdict);
    end;
  end;

  procedure CheckCase(ANode: TSyntaxNode);
  var
    mItem, mLabeled: TSyntaxNode;
    mItemIndex, mLabelIndex: Integer;
    mLowValue, mHighValue, mFirst, mLast: Int64;
    mTypeName: string;
    mOutside: Boolean;
  begin
    if (ANode.ChildCount = 0) or not IntegerOperand(Unwrapped(ANode[0]), mTypeName, mLowValue, mHighValue) then
    begin
      Exit;
    end;
    for mItemIndex := 1 to ANode.ChildCount - 1 do
    begin
      mItem := ANode[mItemIndex];
      if mItem.Kind <> TSyntaxKind.CaseItem then
      begin
        Continue;
      end;
      // Das letzte Kind ist die Anweisung, davor stehen die Marken.
      for mLabelIndex := 0 to mItem.ChildCount - 2 do
      begin
        mLabeled := mItem[mLabelIndex];
        if (mLabeled.Kind = TSyntaxKind.RangeExpr) and (mLabeled.ChildCount = 2) then
        begin
          mOutside := mScope.Values.EvaluateNode(mLabeled[0], mFirst) and
            mScope.Values.EvaluateNode(mLabeled[1], mLast) and
            (mFirst <= mLast) and ((mLast < mLowValue) or (mFirst > mHighValue));
        end
        else
        begin
          // Einzelne Marken, die auch als Zahl mit anderem Vorzeichen nicht passen, sind für dcc ein Fehler; sie
          // meldet constant-expression-error (wie E1012, #1372).
          mOutside := mScope.Values.EvaluateNode(mLabeled, mFirst) and
            ((mFirst < mLowValue) or (mFirst > mHighValue)) and
            not TConstantExpressionErrorRule.OutsideIsError(mFirst, mTypeName);
        end;
        if mOutside then
        begin
          AReport.Add(TTextRange.Create(mLabeled.StartPos, mLabeled.EndPos),
            cTexts[TTypedExpressionsText.OutOfRange].Fmt(
            [mScope.Text(mLabeled), mTypeName]), TRuleConfidence.High);
        end;
      end;
    end;
  end;

  procedure Visit(ARoot: TSyntaxNode);
  var
    mIndex: Integer;
    mNode: TSyntaxNode;
    mPending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ARoot);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if (mNode.Kind = TSyntaxKind.BinaryExpr) and MatchStr(mNode.Name, ['=', '<>', '<', '<=', '>', '>=']) then
        begin
          CheckComparison(mNode);
        end
        else if mNode.Kind = TSyntaxKind.CaseStatement then
        begin
          CheckCase(mNode);
        end;
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          mPending.Push(mNode[mIndex]);
        end;
      end;
    finally
      mPending.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mScope := TTypedScope.Create(AContext);
  try
    Visit(AContext.Tree.Root);
  finally
    mScope.Free;
  end;
end;

{ TConstantInitializerMismatchRule }

function TConstantInitializerMismatchRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cConstantInitializerMismatchRuleId, TRuleSeverity.Error,
    cTexts[TTypedExpressionsText.InitTitle].Text);
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
  begin
    Result := '1 ' + AOne;
  end
  else
  begin
    Result := IntToStr(ACount) + ' ' + AMany;
  end;
end;

/// <summary>Erste Stelle, deren Position kleiner ist als die vorige; -1, wenn alle aufsteigen.</summary>
function FirstDisorder(const APositions: TArray<Integer>): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 1 to High(APositions) do
  begin
    if APositions[mIndex] < APositions[mIndex - 1] then
    begin
      Exit(mIndex);
    end;
  end;
end;

/// <summary>Stellen 0..High(APositions), sortiert nach ihrer Position (stabil).</summary>
function DeclarationOrder(const APositions: TArray<Integer>): TArray<Integer>;
var
  mEarlier, mLater, mSwap: Integer;
begin
  Result := nil;
  for mEarlier := 0 to High(APositions) do
  begin
    Result := Result + [mEarlier];
  end;
  for mEarlier := 0 to High(Result) do
  begin
    for mLater := mEarlier + 1 to High(Result) do
    begin
      if APositions[Result[mLater]] < APositions[Result[mEarlier]] then
      begin
        mSwap := Result[mEarlier];
        Result[mEarlier] := Result[mLater];
        Result[mLater] := mSwap;
      end;
    end;
  end;
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
  mScope: TTypedScope;
  mTokens: TArray<TPascalToken>;

  /// <summary>Steht in ANode eine bedingte Direktive ({$IFDEF}, {$ELSE} …)? Dann ist der Inhalt unsicher.
  /// </summary>
  function HasConditional(ANode: TSyntaxNode): Boolean;
  var
    mIndex: Integer;
    mName: string;
  begin
    Result := False;
    mIndex := TokenFrom(mTokens, ANode.StartOffset);
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

  /// <summary>Deklaration (TypeDecl) des Typs ASymbol in diesem Baum; nil in anderen Units, ohne Treffer oder mit
  /// bedingten Direktiven.</summary>
  function TypeDeclOf(const ASymbol: TResolvedSymbol): TSyntaxNode;
  var
    mFound: TSyntaxNode;

    procedure Search(ARoot: TSyntaxNode);
    var
      mIndex: Integer;
      mNode: TSyntaxNode;
      mPending: TStack<TSyntaxNode>;
    begin
      // Iterativ (Bericht M1).
      mPending := TStack<TSyntaxNode>.Create;
      try
        mPending.Push(ARoot);
        while mPending.Count > 0 do
        begin
          mNode := mPending.Pop;
          if (mNode.Kind = TSyntaxKind.TypeDecl) and SameText(mNode.Name, ASymbol.Name) and
            (mNode.StartPos.Line <= ASymbol.SelectionRange.StartPos.Line) and
            (mNode.EndPos.Line >= ASymbol.SelectionRange.StartPos.Line) then
          begin
            mFound := mNode;
            Exit;
          end;
          for mIndex := mNode.ChildCount - 1 downto 0 do
          begin
            mPending.Push(mNode[mIndex]);
          end;
        end;
      finally
        mPending.Free;
      end;
    end;

  begin
    mFound := nil;
    if (ASymbol.Kind = TResolvedKind.Local) or (ASymbol.FileName = '') or SameText(ASymbol.FileName,
      mScope.FileName) then
    begin
      Search(AContext.Tree.Root);
    end;
    if (mFound <> nil) and HasConditional(mFound) then
    begin
      mFound := nil;
    end;
    Result := mFound;
  end;

  /// <summary>Typknoten einer TypeDecl (ohne Typparameter); nil ohne.</summary>
  function DeclaredType(ADecl: TSyntaxNode): TSyntaxNode;
  var
    mIndex: Integer;
  begin
    Result := nil;
    if ADecl = nil then
    begin
      Exit;
    end;
    for mIndex := 0 to ADecl.ChildCount - 1 do
    begin
      if not (ADecl[mIndex].Kind in [TSyntaxKind.GenericParams, TSyntaxKind.Attribute]) then
      begin
        Exit(ADecl[mIndex]);
      end;
    end;
  end;

  /// <summary>Symbol und Typ eines benannten Typs (TypeReference) an seiner Stelle; False, wenn unbekannt oder
  /// nicht immer mit ANode übersetzt.</summary>
  function NamedType(ARef: TSyntaxNode; out ASymbol, AType: TResolvedSymbol): Boolean;
  begin
    AType := Default(TResolvedSymbol);
    Result := False;
    if (ARef.Kind <> TSyntaxKind.TypeReference) or (ARef.ChildCount > 0) or (Pos('.', ARef.Name) > 0) then
    begin
      Exit;
    end;
    ASymbol := mScope.Resolver.Resolve(AContext.Tree, mScope.FileName, ARef.StartPos);
    if not ASymbol.Found or not mScope.DeclarationSure(ASymbol, ARef) then
    begin
      Exit;
    end;
    AType := mScope.Resolver.ResolveType(AContext.Tree, mScope.FileName, ARef.StartPos);
    Result := True;
  end;

  /// <summary>Ist ASymbol in dieser Datei deklariert?</summary>
  function InThisFile(const ASymbol: TResolvedSymbol): Boolean;
  begin
    Result := (ASymbol.Kind = TResolvedKind.Local) or (ASymbol.FileName = '') or SameText(ASymbol.FileName,
      mScope.FileName);
  end;

  /// <summary>Anzahl und Text eines Teilbereichs mit konstanten Grenzen.</summary>
  function SubrangeInfo(ANode: TSyntaxNode; var AInfo: TIndexInfo): Boolean;
  var
    mLow, mHigh: Int64;
  begin
    Result := (ANode.ChildCount = 2) and mScope.Values.EvaluateNode(ANode[0], mLow) and
      mScope.Values.EvaluateNode(ANode[1], mHigh) and (mHigh >= mLow);
    if Result then
    begin
      AInfo.Count := mHigh - mLow + 1;
      AInfo.Text := mScope.Text(ANode);
    end;
  end;

  /// <summary>Namen, Anzahl und Text einer Aufzählung ohne zugewiesene Werte.</summary>
  function EnumInfo(ANode: TSyntaxNode; var AInfo: TIndexInfo): Boolean;
  var
    mIndex: Integer;
  begin
    for mIndex := 0 to ANode.ChildCount - 1 do
    begin
      if ANode[mIndex].Kind <> TSyntaxKind.Identifier then
      begin
        Exit(False);
      end;
      AInfo.Names := AInfo.Names + [ANode[mIndex].Name];
    end;
    AInfo.Count := Length(AInfo.Names);
    AInfo.Text := mScope.Text(ANode);
    Result := AInfo.Count > 0;
  end;

  /// <summary>Ein Schritt über den benannten Typ ANode: True mit ANode = Typknoten seiner Deklaration, wenn dieser
  /// weiter aufzulösen ist; sonst steht in AResult, ob AInfo gefüllt ist.</summary>
  function FollowNamed(var ANode: TSyntaxNode; var AInfo: TIndexInfo; out AResult: Boolean): Boolean;
  var
    mSymbol, mTypeInfo: TResolvedSymbol;
  begin
    Result := False;
    AResult := False;
    if (ANode.ChildCount > 0) or (Pos('.', ANode.Name) > 0) then
    begin
      Exit;
    end;
    mSymbol := mScope.Resolver.Resolve(AContext.Tree, mScope.FileName, ANode.StartPos);
    if not mSymbol.Found or SameText(mSymbol.UnitName, 'System') then
    begin
      // Eingebaute Typen haben keine Deklaration im Quelltext.
      AInfo.Count := BuiltinIndexCount(ANode.Name);
      AInfo.Text := ANode.Name;
      AResult := AInfo.Count > 0;
      Exit;
    end;
    // Typ dieser Datei: Die Extraktion aus dem Baum kennt keine Bedingungen, deshalb die Direktiven in der
    // Deklaration selbst prüfen (TypeDeclOf liefert dann nil).
    if not mScope.DeclarationSure(mSymbol, ANode) or (InThisFile(mSymbol) and (TypeDeclOf(mSymbol) = nil)) then
    begin
      Exit;
    end;
    mTypeInfo := mScope.Resolver.ResolveType(AContext.Tree, mScope.FileName, ANode.StartPos);
    if mTypeInfo.Found and (mTypeInfo.SymbolKind = TIndexSymbolKind.EnumType) then
    begin
      AResult := mScope.Values.EnumMembers(mTypeInfo, AInfo.Names);
      AInfo.Count := Length(AInfo.Names);
      AInfo.Text := ANode.Name;
      Exit;
    end;
    // Teilbereich oder Aufzählung als benannter Typ dieser Datei: TIndex = 1..5.
    ANode := DeclaredType(TypeDeclOf(mSymbol));
    Result := True;
  end;

  function IndexInfo(ANode: TSyntaxNode; out AInfo: TIndexInfo): Boolean;
  var
    mNode: TSyntaxNode;
    mName, mOuterName: string;
    mSeen: TList<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1): benannte Typen dieser Datei (TIndex = TBereich) werden in einer Schleife aufgelöst;
    // die Meldung nennt den äußersten Namen. mSeen schützt vor Zyklen wie TA = TB; TB = TA.
    AInfo := Default(TIndexInfo);
    Result := False;
    mOuterName := '';
    mNode := ANode;
    mSeen := TList<TSyntaxNode>.Create;
    try
      while (mNode <> nil) and not mSeen.Contains(mNode) do
      begin
        mSeen.Add(mNode);
        case mNode.Kind of
          TSyntaxKind.SubrangeType:
            Result := SubrangeInfo(mNode, AInfo);
          TSyntaxKind.EnumType:
            Result := EnumInfo(mNode, AInfo);
          TSyntaxKind.TypeReference:
            begin
              mName := mNode.Name;
              if FollowNamed(mNode, AInfo, Result) then
              begin
                mOuterName := IfThen(mOuterName = '', mName, mOuterName);
                Continue;
              end;
            end;
        else
          // Übrige Werte bewusst ohne Wirkung.
        end;
        Break;
      end;
      if Result and (mOuterName <> '') then
      begin
        AInfo.Text := mOuterName;
      end;
    finally
      mSeen.Free;
    end;
  end;

  /// <summary>Typknoten hinter einem benannten Typ dieser Datei (TNamen = array[…] of string); sonst ANode.
  /// ASymbol und AType sind bei benannten Typen gesetzt.</summary>
  function Expanded(ANode: TSyntaxNode; out ASymbol, AType: TResolvedSymbol): TSyntaxNode;
  var
    mInner: TSyntaxNode;
  begin
    Result := ANode;
    ASymbol := Default(TResolvedSymbol);
    AType := Default(TResolvedSymbol);
    if (ANode = nil) or (ANode.Kind <> TSyntaxKind.TypeReference) or not NamedType(ANode, ASymbol, AType) then
    begin
      Exit;
    end;
    mInner := DeclaredType(TypeDeclOf(ASymbol));
    if (mInner <> nil) and (mInner.Kind in [TSyntaxKind.ArrayType, TSyntaxKind.TypeReference]) and
      (mInner <> ANode) then
    begin
      Result := mInner;
    end;
  end;

  /// <summary>Platzhalter für ein Element vom Typ ANode ('' = keiner).</summary>
  function ElementPlaceholder(ANode: TSyntaxNode): string;
  var
    mSymbol, mTypeInfo: TResolvedSymbol;
  begin
    Result := '';
    if (ANode = nil) or (ANode.Kind <> TSyntaxKind.TypeReference) or (ANode.ChildCount > 0) then
    begin
      Exit;
    end;
    Result := Placeholder(ANode.Name);
    if Result <> '' then
    begin
      Exit;
    end;
    if not NamedType(ANode, mSymbol, mTypeInfo) or not mTypeInfo.Found then
    begin
      Exit;
    end;
    if mTypeInfo.SymbolKind in [TIndexSymbolKind.ClassType, TIndexSymbolKind.InterfaceType] then
    begin
      Result := 'nil';
    end
    else if mTypeInfo.SymbolKind = TIndexSymbolKind.EnumType then
    begin
      Result := 'Low(' + ANode.Name + ')';
    end
    else if mTypeInfo.Builtin then
    begin
      Result := Placeholder(mTypeInfo.Name);
    end;
  end;

  /// <summary>Wie neue Einträge einer Tabelle mit Elementtyp ANode aussehen (#667).</summary>
  function ElementValues(ANode: TSyntaxNode; const AIndexType: string): TEnumTableValues;
  var
    mFiller, mName: string;
    mElement: TEnumTableElement;
  begin
    mName := '';
    if ANode.Kind = TSyntaxKind.TypeReference then
    begin
      mName := ANode.Name;
    end;
    mElement := TEnumTables.ElementOf(mName);
    if mElement = TEnumTableElement.Other then
    begin
      mFiller := ElementPlaceholder(ANode);
      if mFiller = 'nil' then
      begin
        mElement := TEnumTableElement.Pointer_;
      end
      else if StartsStr('Low(', mFiller) then
      begin
        mElement := TEnumTableElement.Enum;
      end;
    end;
    Result := TEnumTableValues.Create(mElement, mName, AIndexType);
  end;

  /// <summary>Text für die fehlenden Einträge ab AGiven: ", ''{stArchiviert}" je Eintrag.</summary>
  function MissingText(const AInfo: TIndexInfo; AGiven: Integer; const APlaceholder: string): string;
  var
    mIndex: Integer;
  begin
    Result := '';
    for mIndex := AGiven to Integer(AInfo.Count) - 1 do
    begin
      Result := Result + ', ' + APlaceholder;
      if mIndex < Length(AInfo.Names) then
      begin
        Result := Result + '{' + AInfo.Names[mIndex] + '}';
      end;
    end;
  end;

  procedure CheckValue(ATypeNode, AValue: TSyntaxNode); forward;

  /// <summary>Felder des Records AType in der Reihenfolge der Deklaration; False bei varianten oder bedingten
  /// Feldern und ohne Felder.</summary>
  function RecordFields(const AType: TResolvedSymbol; out AFields: TArray<string>): Boolean;
  var
    mOwner: TUnitIndex;
    mSymbol: TIndexSymbol;
    mContainer: string;
  begin
    AFields := nil;
    if not mScope.Resolver.DeclaringUnit(AType, mOwner) then
    begin
      Exit(False);
    end;
    mContainer := AType.QualifiedName;
    for mSymbol in mOwner.Symbols do
    begin
      if (mSymbol.Kind = TIndexSymbolKind.Field) and SameText(mSymbol.Container, mContainer) then
      begin
        // Variante Teile und bedingte Felder: Reihenfolge nicht sicher.
        if (mSymbol.VariantBranch <> '') or (mSymbol.Condition <> '') then
        begin
          Exit(False);
        end;
        AFields := AFields + [mSymbol.Name];
      end;
    end;
    Result := AFields <> nil;
  end;

  /// <summary>(X: 1; Y: 2): Kinder abwechselnd Feldname und Wert. AGiven sind die genannten Felder, APositions ihre
  /// Stellen in AFields; False bei unbekannten Feldern.</summary>
  function GivenFields(AValue: TSyntaxNode; const AFields: TArray<string>; out AGiven: TArray<string>;
    out APositions: TArray<Integer>): Boolean;
  var
    mIndex, mField: Integer;
  begin
    AGiven := nil;
    APositions := nil;
    mIndex := 0;
    while mIndex < AValue.ChildCount do
    begin
      mField := -1;
      if AValue[mIndex].Kind = TSyntaxKind.Identifier then
      begin
        mField := IndexText(AValue[mIndex].Name, AFields);
      end;
      if mField < 0 then
      begin
        Exit(False);
      end;
      AGiven := AGiven + [AValue[mIndex].Name];
      APositions := APositions + [mField];
      Inc(mIndex, 2);
    end;
    Result := True;
  end;

  /// <summary>Die Paare in der Reihenfolge der Deklaration, je Paar der Text aus der Datei.</summary>
  function OrderedText(AValue: TSyntaxNode; const APositions: TArray<Integer>): string;
  var
    mOrder: TArray<Integer>;
    mParts: TArray<string>;
    mIndex: Integer;
  begin
    mOrder := DeclarationOrder(APositions);
    mParts := nil;
    for mIndex := 0 to High(mOrder) do
    begin
      mParts := mParts + [Copy(AContext.Text, AValue[mOrder[mIndex] * 2].StartOffset + 1,
        AValue[mOrder[mIndex] * 2 + 1].EndOffset - AValue[mOrder[mIndex] * 2].StartOffset)];
    end;
    Result := string.Join('; ', mParts);
  end;

  procedure CheckRecord(const AType: TResolvedSymbol; AValue: TSyntaxNode);
  var
    mFields, mGiven: TArray<string>;
    mPositions: TArray<Integer>;
    mIndex: Integer;
  begin
    if (AValue.Kind <> TSyntaxKind.ParenExpr) or (AValue.ChildCount = 0) or Odd(AValue.ChildCount) or
      not RecordFields(AType, mFields) or not GivenFields(AValue, mFields, mGiven, mPositions) then
    begin
      Exit;
    end;
    mIndex := FirstDisorder(mPositions);
    if mIndex > 0 then
    begin
      // Korrektur: die Paare in der Reihenfolge der Deklaration.
      AReport.Add(TTextRange.Create(AValue[mIndex * 2].StartPos, AValue[mIndex * 2].EndPos),
        cTexts[TTypedExpressionsText.FieldOrder].Fmt(
        [mGiven[mIndex], AType.Name, mGiven[mIndex - 1]]), TRuleConfidence.High,
        [TRuleFix.Create(cTexts[TTypedExpressionsText.SortFields].Text, [TTextEdit.Create(TTextRange.Create(
        AValue[0].StartPos, AValue[AValue.ChildCount - 1].EndPos), OrderedText(AValue, mPositions))])]);
    end;
    // Werte der Felder: verschachtelte Records und Arrays sind hier nicht bekannt.
  end;

  /// <summary>Namen der fehlenden Werte einer Aufzählung ab AGiven; nach einer sicheren Zuordnung die wirklich
  /// fehlenden (#667).</summary>
  function MissingNames(const AInfo: TIndexInfo; AGiven: Integer; ARepaired: Boolean;
    const ARepair: TEnumTableRepair): TArray<string>;
  var
    mIndex: Integer;
  begin
    if ARepaired and not ARepair.Uncertain then
    begin
      Exit(ARepair.Added);
    end;
    Result := nil;
    for mIndex := AGiven to Integer(Length(AInfo.Names)) - 1 do
    begin
      Result := Result + [AInfo.Names[mIndex]];
    end;
  end;

  /// <summary>"; X fehlt" bzw. "; X, Y fehlen" (höchstens drei Namen).</summary>
  function MissingNote(const ANames: TArray<string>): string;
  begin
    Result := '';
    if Length(ANames) = 1 then
    begin
      Result := cTexts[TTypedExpressionsText.MissingOne].Fmt([ANames[0]]);
    end
    else if Length(ANames) > 3 then
    begin
      Result := cTexts[TTypedExpressionsText.MissingMore].Fmt([string.Join(', ', Copy(ANames, 0, 3))]);
    end
    else if Length(ANames) > 1 then
    begin
      Result := cTexts[TTypedExpressionsText.MissingMany].Fmt([string.Join(', ', ANames)]);
    end;
  end;

  /// <summary>Korrektur, die die fehlenden Einträge mit einem Platzhalter des Elementtyps ergänzt; nil ohne.
  /// </summary>
  function PlaceholderFix(AArray, AValue: TSyntaxNode; const AInfo: TIndexInfo): TArray<TRuleFix>;
  var
    mFiller: string;
    mLast: TSyntaxNode;
  begin
    Result := nil;
    mFiller := ElementPlaceholder(AArray[AArray.ChildCount - 1]);
    if mFiller = '' then
    begin
      Exit;
    end;
    mLast := AValue[AValue.ChildCount - 1];
    Result := [TRuleFix.Create(cTexts[TTypedExpressionsText.AddPlaceholders].Text, [TTextEdit.Create(TTextRange.Create(
      mLast.EndPos, mLast.EndPos), MissingText(AInfo, AValue.ChildCount, mFiller))])];
  end;

  /// <summary>Meldet, dass die Konstante AValue nicht so viele Einträge hat wie die Dimension ADimension.</summary>
  procedure ReportCount(AArray: TSyntaxNode; ADimension: Integer; AValue: TSyntaxNode; const AInfo: TIndexInfo);
  var
    mMessage: string;
    mFixes: TArray<TRuleFix>;
    mRepair: TEnumTableRepair;
    mRepaired, mInnermost: Boolean;
  begin
    mInnermost := ADimension = AArray.ChildCount - 2;
    mMessage := cTexts[TTypedExpressionsText.CountMismatch].Fmt([AInfo.Text, Counted(AInfo.Count,
      cTexts[TTypedExpressionsText.ValueOne].Text, cTexts[TTypedExpressionsText.ValueMany].Text),
      Counted(AValue.ChildCount, cTexts[TTypedExpressionsText.EntryOne].Text,
        cTexts[TTypedExpressionsText.EntryMany].Text)]);
    // Über einer Aufzählung nennt die Zuordnung die wirklich fehlenden Werte, nicht die letzten (#667).
    mRepaired := (Length(AInfo.Names) = AInfo.Count) and mInnermost and
      TEnumTables.Repair(AContext.Text, AContext.Tree, AValue, AInfo.Names,
      ElementValues(AArray[AArray.ChildCount - 1], AInfo.Text), mRepair);
    mMessage := mMessage + MissingNote(MissingNames(AInfo, AValue.ChildCount, mRepaired, mRepair));
    mFixes := nil;
    // Über einer Aufzählung: Einträge an ihrer Stelle ergänzen bzw. entfernen (#667).
    if mRepaired then
    begin
      mFixes := [TRuleFix.Create(mRepair.Title, mRepair.Edits)];
    end
    else if mInnermost and (AInfo.Count > AValue.ChildCount) and (AInfo.Count - AValue.ChildCount <= 64) then
    begin
      mFixes := PlaceholderFix(AArray, AValue, AInfo);
    end;
    AReport.Add(TTextRange.Create(AValue.StartPos, AValue.EndPos), mMessage +
      cTexts[TTypedExpressionsText.LikeE2072].Text, TRuleConfidence.High,
      mFixes);
  end;

  // CheckArray und CheckValue rufen sich gegenseitig auf; die Rekursion bleibt (Bericht M1): jede Ebene ist eine
  // Dimension bzw. ein Elementtyp des deklarierten Arraytyps und ein Klammerpaar der Konstanten, keine Kette.
  procedure CheckArray(AArray: TSyntaxNode; ADimension: Integer; AValue: TSyntaxNode);
  var
    mDimensions, mIndex: Integer;
    mInfo: TIndexInfo;
  begin
    mDimensions := AArray.ChildCount - 1;
    // () setzt alle Elemente auf null, wie bei Records (#1138).
    if (AValue.Kind <> TSyntaxKind.ParenExpr) or (AValue.ChildCount = 0) then
    begin
      Exit;
    end;
    if ADimension >= mDimensions then
    begin
      // Dynamisches Array: keine Länge, aber Elemente prüfen.
      for mIndex := 0 to AValue.ChildCount - 1 do
      begin
        CheckValue(AArray[AArray.ChildCount - 1], AValue[mIndex]);
      end;
      Exit;
    end;
    if not IndexInfo(AArray[ADimension], mInfo) then
    begin
      Exit;
    end;
    if mInfo.Count <> AValue.ChildCount then
    begin
      ReportCount(AArray, ADimension, AValue, mInfo);
      Exit;
    end;
    for mIndex := 0 to AValue.ChildCount - 1 do
    begin
      if ADimension + 1 < mDimensions then
      begin
        CheckArray(AArray, ADimension + 1, AValue[mIndex]);
      end
      else
      begin
        CheckValue(AArray[AArray.ChildCount - 1], AValue[mIndex]);
      end;
    end;
  end;

  procedure CheckValue(ATypeNode, AValue: TSyntaxNode);
  var
    mNode: TSyntaxNode;
    mSymbol, mTypeInfo: TResolvedSymbol;
  begin
    if (ATypeNode = nil) or (AValue = nil) then
    begin
      Exit;
    end;
    mNode := Expanded(ATypeNode, mSymbol, mTypeInfo);
    if mNode.Kind = TSyntaxKind.ArrayType then
    begin
      CheckArray(mNode, 0, AValue);
    end
    else if (mNode.Kind = TSyntaxKind.TypeReference) and mTypeInfo.Found and
      (mTypeInfo.SymbolKind = TIndexSymbolKind.RecordType) and not mTypeInfo.Builtin then
    begin
      CheckRecord(mTypeInfo, AValue);
    end;
  end;

  procedure Visit(ARoot: TSyntaxNode);
  var
    mIndex: Integer;
    mNode: TSyntaxNode;
    mPending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ARoot);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if (mNode.Kind in [TSyntaxKind.ConstDecl, TSyntaxKind.VarDecl]) and (mNode.ChildCount >= 2) and
          (mNode[mNode.ChildCount - 1].Kind = TSyntaxKind.ParenExpr) and not HasConditional(mNode) then
        begin
          CheckValue(mNode[0], mNode[mNode.ChildCount - 1]);
        end;
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          mPending.Push(mNode[mIndex]);
        end;
      end;
    finally
      mPending.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mTokens := AContext.Tree.Tokens;
  mScope := TTypedScope.Create(AContext);
  try
    Visit(AContext.Tree.Root);
  finally
    mScope.Free;
  end;
end;

{ TCaseSelectorNotOrdinalRule }

function TCaseSelectorNotOrdinalRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cCaseSelectorNotOrdinalRuleId, TRuleSeverity.Error,
    cTexts[TTypedExpressionsText.OrdinalTitle].Text);
end;

class function TCaseSelectorNotOrdinalRule.NotOrdinal(const ATypeName: string): Boolean;
begin
  Result := MatchText(ATypeName, ['string', 'UnicodeString', 'AnsiString', 'WideString', 'ShortString',
    'RawByteString', 'UTF8String', 'Double', 'Single', 'Extended', 'Real', 'Currency', 'Comp', 'Real48']);
end;

procedure TCaseSelectorNotOrdinalRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mScope: TTypedScope;
  mTokens: TArray<TPascalToken>;

  /// <summary>Name des Typs, wenn ATypeInfo sicher nicht ordinal ist; '' sonst.</summary>
  function NonOrdinalName(const ATypeInfo: TResolvedSymbol): string;
  begin
    Result := '';
    if not ATypeInfo.Found then
    begin
      Exit;
    end;
    if (ATypeInfo.Builtin or SameText(ATypeInfo.UnitName, 'System')) and NotOrdinal(ATypeInfo.Name) then
    begin
      Result := ATypeInfo.Name;
    end
    else if not ATypeInfo.Builtin and (ATypeInfo.SymbolKind in [TIndexSymbolKind.ClassType,
      TIndexSymbolKind.InterfaceType]) then
    begin
      Result := ATypeInfo.Name;
    end;
  end;

  /// <summary>Korrektur case IndexStr(S, ['a', 'b']) of, wenn jede Marke ein String-Literal ist.</summary>
  function IndexStrFix(ACase: TSyntaxNode; const ATypeName: string; out AFix: TRuleFix): Boolean;
  var
    mItemIndex, mLabelIndex, mPosition: Integer;
    mItem, mLabeled, mSelector: TSyntaxNode;
    mLiterals: TArray<string>;
    mEdits: TArray<TTextEdit>;
    mUsesEdit: TTextEdit;
  begin
    Result := False;
    if not MatchText(ATypeName, ['string', 'UnicodeString']) then
    begin
      Exit;
    end;
    mSelector := ACase[0];
    mLiterals := nil;
    mEdits := nil;
    mPosition := 0;
    for mItemIndex := 1 to ACase.ChildCount - 1 do
    begin
      mItem := ACase[mItemIndex];
      if mItem.Kind <> TSyntaxKind.CaseItem then
      begin
        Continue;
      end;
      for mLabelIndex := 0 to mItem.ChildCount - 2 do
      begin
        mLabeled := mItem[mLabelIndex];
        if (mLabeled.Kind <> TSyntaxKind.Literal) or not StartsStr('''', mLabeled.Name) then
        begin
          Exit;
        end;
        mLiterals := mLiterals + [mScope.Text(mLabeled)];
        mEdits := mEdits + [TTextEdit.Create(TTextRange.Create(mLabeled.StartPos, mLabeled.EndPos),
          IntToStr(mPosition))];
        Inc(mPosition);
      end;
    end;
    if mLiterals = nil then
    begin
      Exit;
    end;
    mEdits := [TTextEdit.Create(TTextRange.Create(mSelector.StartPos, mSelector.EndPos), Format('IndexStr(%s, [%s])',
      [mScope.Text(mSelector), string.Join(', ', mLiterals)]))] + mEdits;
    if not TUsesClauses.IsUsed(TUsesClauses.UsedUnits(mTokens), 'System.StrUtils', AContext.Namespaces) then
    begin
      if not TUsesClauses.AddUnit(mTokens, ACase.StartOffset, 'System.StrUtils', TTextLines.LineBreakOf(AContext.Text),
        mUsesEdit) then
      begin
        Exit;
      end;
      mEdits := mEdits + [mUsesEdit];
    end;
    AFix := TRuleFix.Create(cTexts[TTypedExpressionsText.ToCaseIndexStr].Text, mEdits);
    Result := True;
  end;

  procedure CheckCase(ANode: TSyntaxNode);
  var
    mSelector: TSyntaxNode;
    mSymbol, mTypeInfo: TResolvedSymbol;
    mName: string;
    mFix: TRuleFix;
    mFixes: TArray<TRuleFix>;
  begin
    if ANode.ChildCount = 0 then
    begin
      Exit;
    end;
    mSelector := Unwrapped(ANode[0]);
    if not mScope.SureType(mSelector, mSymbol, mTypeInfo) then
    begin
      Exit;
    end;
    mName := NonOrdinalName(mTypeInfo);
    if mName = '' then
    begin
      Exit;
    end;
    mFixes := nil;
    if IndexStrFix(ANode, mName, mFix) then
    begin
      mFixes := [mFix];
    end;
    AReport.Add(TTextRange.Create(ANode[0].StartPos, ANode[0].EndPos),
      cTexts[TTypedExpressionsText.CaseOrdinal].Fmt([mScope.Text(ANode[0]), mName]),
      TRuleConfidence.High, mFixes);
  end;

  /// <summary>Token der Zählvariablen: for [var] I [: Typ] := …, das erste Bezeichner-Token nach for bzw. var.
  /// </summary>
  function ForVariable(ANode: TSyntaxNode; out AVariable: TPascalToken): Boolean;
  var
    mIndex: Integer;
  begin
    mIndex := TokenFrom(mTokens, ANode.StartOffset);
    while (mIndex <= High(mTokens)) and (mTokens[mIndex].Kind <> TPascalTokenKind.Identifier) do
    begin
      Inc(mIndex);
    end;
    Result := (mIndex <= High(mTokens)) and SameText(mTokens[mIndex].Text, ANode.Name);
    if Result then
    begin
      AVariable := mTokens[mIndex];
    end;
  end;

  /// <summary>for var X: Double := …: nicht ordinaler Name des angegebenen Typs ('' bei ordinalem).</summary>
  function InlineTypeName(ANode: TSyntaxNode; out AName: string): Boolean;
  var
    mType: TSyntaxNode;
    mChain: TResolvedChainType;
  begin
    AName := '';
    mType := ANode[0];
    Result := (mType.ChildCount = 0) and (Pos('.', mType.Name) = 0);
    if Result and NotOrdinal(mType.Name) then
    begin
      AName := mType.Name;
    end
    else if Result then
    begin
      Result := mScope.Resolver.ChainType(AContext.Tree, mScope.FileName, [mType.Name], mType.StartOffset, mChain) and
        mChain.TypeFound and mScope.DeclarationSure(mChain.Owner, ANode);
      if Result then
      begin
        AName := NonOrdinalName(mChain.TypeInfo);
      end;
    end;
  end;

  /// <summary>Nicht ordinaler Name des Typs der Zählvariablen AVariable ('' bei ordinalem).</summary>
  function VariableTypeName(ANode: TSyntaxNode; const AVariable: TPascalToken; out AName: string): Boolean;
  var
    mChain: TResolvedChainType;
  begin
    AName := '';
    Result := mScope.Resolver.ChainType(AContext.Tree, mScope.FileName, [ANode.Name], AVariable.Offset, mChain) and
      mChain.TypeFound and not mChain.Owner.IsType;
    Result := Result and mScope.DeclarationSure(mChain.Owner, ANode);
    if Result then
    begin
      AName := NonOrdinalName(mChain.TypeInfo);
    end;
  end;

  procedure CheckFor(ANode: TSyntaxNode);
  var
    mVariable: TPascalToken;
    mName: string;
    mKnown: Boolean;
  begin
    if not ForVariable(ANode, mVariable) then
    begin
      Exit;
    end;
    if (ANode.ChildCount > 0) and (ANode[0].Kind = TSyntaxKind.TypeReference) then
    begin
      mKnown := InlineTypeName(ANode, mName);
    end
    else
    begin
      mKnown := VariableTypeName(ANode, mVariable, mName);
    end;
    if mKnown and (mName <> '') then
    begin
      AReport.Add(TTextRange.Create(mVariable.StartPos, mVariable.EndPos),
        cTexts[TTypedExpressionsText.ForOrdinal].Fmt([ANode.Name, mName]), TRuleConfidence.High);
    end;
  end;

  /// <summary>"eine Variable", "ein Feld" … wenn ASymbol sicher keine echte Konstante ist; '' sonst.</summary>
  function NotConstant(const ASymbol: TResolvedSymbol): string;
  begin
    Result := '';
    if ASymbol.IsParameter then
    begin
      Result := cTexts[TTypedExpressionsText.AParameter].Text;
    end
    else
      case ASymbol.SymbolKind of
        TIndexSymbolKind.Variable:
          Result := cTexts[TTypedExpressionsText.AVariable].Text;
        TIndexSymbolKind.Field:
          Result := cTexts[TTypedExpressionsText.AField].Text;
        TIndexSymbolKind.Property_:
          Result := cTexts[TTypedExpressionsText.AProperty].Text;
        TIndexSymbolKind.Constant:
          if ASymbol.TypeName <> '' then
          begin
            Result := cTexts[TTypedExpressionsText.ATypedConstant].Text;
          end;
      else
        // Übrige Werte bewusst ohne Wirkung.
      end;
  end;

  /// <summary>Meldet AExpr (case-Marke bzw. Arraygrenze), wenn es ein Name für etwas Veränderliches ist.</summary>
  procedure CheckConstant(AExpr: TSyntaxNode; const AWhat: string);
  var
    mSymbol, mTypeInfo: TResolvedSymbol;
    mTypeFound: Boolean;
    mKind: string;
  begin
    if AExpr.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess] then
    begin
      if not mScope.Resolver.NodeType(AContext.Tree, mScope.FileName, AExpr, mSymbol, mTypeInfo, mTypeFound) then
      begin
        Exit;
      end;
    end
    else if (AExpr.Kind = TSyntaxKind.TypeReference) and (AExpr.ChildCount = 0) and (Pos('.', AExpr.Name) = 0) then
    begin
      mSymbol := mScope.Resolver.Resolve(AContext.Tree, mScope.FileName, AExpr.StartPos);
    end
    else
    begin
      Exit;
    end;
    if not mSymbol.Found or (mSymbol.Kind = TResolvedKind.UnitName) or not mScope.DeclarationSure(mSymbol, AExpr) then
    begin
      Exit;
    end;
    mKind := NotConstant(mSymbol);
    if mKind <> '' then
    begin
      AReport.Add(TTextRange.Create(AExpr.StartPos, AExpr.EndPos), cTexts[TTypedExpressionsText.NotConstant].Fmt(
        [AWhat, mScope.Text(AExpr), mKind]), TRuleConfidence.High);
    end;
  end;

  procedure CheckLabels(ANode: TSyntaxNode);
  var
    mItemIndex, mLabelIndex: Integer;
    mItem, mLabeled: TSyntaxNode;
  begin
    for mItemIndex := 1 to ANode.ChildCount - 1 do
    begin
      mItem := ANode[mItemIndex];
      if mItem.Kind <> TSyntaxKind.CaseItem then
      begin
        Continue;
      end;
      for mLabelIndex := 0 to mItem.ChildCount - 2 do
      begin
        mLabeled := mItem[mLabelIndex];
        if (mLabeled.Kind = TSyntaxKind.RangeExpr) and (mLabeled.ChildCount = 2) then
        begin
          CheckConstant(Unwrapped(mLabeled[0]), cTexts[TTypedExpressionsText.CaseLabel].Text);
          CheckConstant(Unwrapped(mLabeled[1]), cTexts[TTypedExpressionsText.CaseLabel].Text);
        end
        else
        begin
          CheckConstant(Unwrapped(mLabeled), cTexts[TTypedExpressionsText.CaseLabel].Text);
        end;
      end;
    end;
  end;

  procedure CheckBounds(AArray: TSyntaxNode);
  var
    mIndex: Integer;
    mBound: TSyntaxNode;
  begin
    for mIndex := 0 to AArray.ChildCount - 2 do
    begin
      mBound := AArray[mIndex];
      if (mBound.Kind = TSyntaxKind.SubrangeType) and (mBound.ChildCount = 2) then
      begin
        CheckConstant(Unwrapped(mBound[0]), cTexts[TTypedExpressionsText.ArrayBound].Text);
        CheckConstant(Unwrapped(mBound[1]), cTexts[TTypedExpressionsText.ArrayBound].Text);
      end;
    end;
  end;

  procedure Visit(ARoot: TSyntaxNode);
  var
    mIndex: Integer;
    mNode: TSyntaxNode;
    mPending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ARoot);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        case mNode.Kind of
          TSyntaxKind.CaseStatement:
            begin
              CheckCase(mNode);
              CheckLabels(mNode);
            end;
          TSyntaxKind.ForStatement:
            CheckFor(mNode);
          TSyntaxKind.ArrayType:
            CheckBounds(mNode);
        else
          // Übrige Werte bewusst ohne Wirkung.
        end;
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          mPending.Push(mNode[mIndex]);
        end;
      end;
    finally
      mPending.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mTokens := AContext.Tree.Tokens;
  mScope := TTypedScope.Create(AContext);
  try
    Visit(AContext.Tree.Root);
  finally
    mScope.Free;
  end;
end;

{ TSuspiciousStringPointerCastRule }

function TSuspiciousStringPointerCastRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cSuspiciousStringPointerCastRuleId, TRuleSeverity.Warning,
    cTexts[TTypedExpressionsText.PointerTitle].Text);
end;

class function TSuspiciousStringPointerCastRule.StringWidth(const ATypeName: string): Integer;
begin
  Result := 0;
  if MatchText(ATypeName, ['AnsiString', 'RawByteString', 'UTF8String']) then
  begin
    Result := 1;
  end
  else if MatchText(ATypeName, ['string', 'UnicodeString', 'WideString']) then
  begin
    Result := 2;
  end;
end;

/// <summary>Zeichenbreite, auf die der Zeigertyp AName zeigt: 2 bei PChar/PWideChar, 1 bei PAnsiChar, sonst 0.
/// </summary>
function CharPointerWidth(const AName: string): Integer;
begin
  Result := 0;
  if MatchText(AName, ['PChar', 'PWideChar']) then
  begin
    Result := 2;
  end
  else if SameText(AName, 'PAnsiChar') then
  begin
    Result := 1;
  end;
end;

procedure TSuspiciousStringPointerCastRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mScope: TTypedScope;
  mTokens: TArray<TPascalToken>;

  /// <summary>Nächstes Token ab AIndex, das kein Kommentar ist; Length(Tokens) am Ende.</summary>
  function NextToken(AIndex: Integer): Integer;
  begin
    Result := AIndex;
    while (Result <= High(mTokens)) and (mTokens[Result].Kind = TPascalTokenKind.Comment) do
    begin
      Inc(Result);
    end;
  end;

  /// <summary>Index des Typ-Tokens hinter "Name:", wenn die Variable ASymbol allein so deklariert ist; -1 sonst.
  /// </summary>
  function DeclaredTypeToken(const ASymbol: TResolvedSymbol): Integer;
  var
    mIndex: Integer;
  begin
    Result := -1;
    mIndex := mScope.TokenAtPosition(ASymbol.SelectionRange.StartPos);
    // Vor dem Namen kein Komma (A, B: AnsiString änderte beide).
    if (mIndex > High(mTokens)) or not SameText(mTokens[mIndex].Text, ASymbol.Name) or
      ((mIndex > 0) and (mTokens[mIndex - 1].Text = ',')) then
    begin
      Exit;
    end;
    mIndex := NextToken(mIndex + 1);
    if (mIndex > High(mTokens)) or (mTokens[mIndex].Text <> ':') then
    begin
      Exit;
    end;
    mIndex := NextToken(mIndex + 1);
    if mIndex <= High(mTokens) then
    begin
      Result := mIndex;
    end;
  end;

  /// <summary>Korrektur "Pfad als string deklarieren": nur für eine Variable dieser Datei, die allein mit
  /// "Name: Typ" deklariert ist, wobei Typ einer der Stringtypen der Breite AWidth ist.</summary>
  function DeclarationFix(const ASymbol: TResolvedSymbol; AWidth: Integer; out AFix: TRuleFix): Boolean;
  var
    mIndex, mNext: Integer;
  begin
    Result := False;
    if ASymbol.IsParameter or (ASymbol.SymbolKind <> TIndexSymbolKind.Variable) or ((ASymbol.Kind <>
      TResolvedKind.Local) and not SameText(ASymbol.FileName, mScope.FileName)) then
    begin
      Exit;
    end;
    mIndex := DeclaredTypeToken(ASymbol);
    if (mIndex < 0) or (mTokens[mIndex].Kind <> TPascalTokenKind.Identifier) or
      (StringWidth(mTokens[mIndex].Text) <> AWidth) then
    begin
      Exit;
    end;
    mNext := NextToken(mIndex + 1);
    if (mNext > High(mTokens)) or not MatchStr(mTokens[mNext].Text, [';', '=', ':=']) then
    begin
      Exit;
    end;
    AFix := TRuleFix.Create(cTexts[TTypedExpressionsText.DeclareString].Fmt([ASymbol.Name]),
      [TTextEdit.Create(TTextRange.Create(mTokens[mIndex].StartPos, mTokens[mIndex].EndPos), 'string')]);
    Result := True;
  end;

  /// <summary>Meldet den Zeiger ANode auf den String AArgument vom Typ ATypeName mit der Zeichenbreite AWidth.
  /// </summary>
  procedure ReportCast(ANode, AArgument: TSyntaxNode; const ASymbol: TResolvedSymbol; const ATypeName: string;
    AWidth: Integer);
  var
    mMessage, mConversion, mOtherPointer: string;
    mFix: TRuleFix;
    mFixes: TArray<TRuleFix>;
  begin
    mFixes := nil;
    if CharPointerWidth(ANode.Name) = 2 then
    begin
      mMessage := cTexts[TTypedExpressionsText.WideGarbage].Fmt([ANode.Name, mScope.Text(AArgument), ATypeName]);
      if DeclarationFix(ASymbol, AWidth, mFix) then
      begin
        mFixes := [mFix];
      end;
      mConversion := 'string';
      mOtherPointer := 'PAnsiChar';
    end
    else
    begin
      mMessage := cTexts[TTypedExpressionsText.AnsiFirstOnly].Fmt([ANode.Name, mScope.Text(AArgument), ATypeName]);
      mConversion := 'AnsiString';
      mOtherPointer := 'PChar';
    end;
    mFix := TRuleFix.Create(cTexts[TTypedExpressionsText.ConvertTo].Fmt([mConversion, ANode.Name, mConversion]),
      [TTextEdit.Create(TTextRange.Create(ANode[1].StartPos, ANode[1].EndPos), Format('%s(%s)', [mConversion,
      mScope.Text(ANode[1])]))]);
    mFix.Alternative := mFixes <> nil;
    mFixes := mFixes + [mFix];
    mFix := TRuleFix.Create(cTexts[TTypedExpressionsText.UsePointerType].Fmt([mOtherPointer]),
      [TTextEdit.Create(TTextRange.Create(ANode[0].StartPos, ANode[0].EndPos), mOtherPointer)]);
    mFix.Alternative := True;
    mFixes := mFixes + [mFix];
    AReport.Add(TTextRange.Create(ANode.StartPos, ANode.EndPos), mMessage, TRuleConfidence.High, mFixes);
  end;

  procedure CheckCast(ANode: TSyntaxNode);
  var
    mArgument: TSyntaxNode;
    mSymbol, mTypeInfo: TResolvedSymbol;
    mPointerWidth, mWidth: Integer;
  begin
    // PChar(X): Callee und genau ein Argument.
    if ANode.ChildCount <> 2 then
    begin
      Exit;
    end;
    mPointerWidth := CharPointerWidth(ANode.Name);
    mArgument := Unwrapped(ANode[1]);
    if (mPointerWidth = 0) or not mScope.SureType(mArgument, mSymbol, mTypeInfo) or
      (not mTypeInfo.Builtin and not SameText(mTypeInfo.UnitName, 'System')) then
    begin
      Exit;
    end;
    mWidth := StringWidth(mTypeInfo.Name);
    if (mWidth <> 0) and (mWidth <> mPointerWidth) then
    begin
      ReportCast(ANode, mArgument, mSymbol, mTypeInfo.Name, mWidth);
    end;
  end;

  procedure Visit(ARoot: TSyntaxNode);
  var
    mIndex: Integer;
    mNode: TSyntaxNode;
    mPending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ARoot);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if mNode.Kind = TSyntaxKind.Call then
        begin
          CheckCast(mNode);
        end;
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          mPending.Push(mNode[mIndex]);
        end;
      end;
    finally
      mPending.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mTokens := AContext.Tree.Tokens;
  mScope := TTypedScope.Create(AContext);
  try
    Visit(AContext.Tree.Root);
  finally
    mScope.Free;
  end;
end;

procedure RegisterTypedExpressionRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TComparisonAlwaysConstantRule.Create);
  ARegistry.Register(TConstantInitializerMismatchRule.Create);
  ARegistry.Register(TCaseSelectorNotOrdinalRule.Create);
  ARegistry.Register(TSuspiciousStringPointerCastRule.Create);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.TypedExpressions', cTexts);

end.
