unit Atlas.Common.Rules.Builtin.Idioms;

// Regeln für das passendere Sprachmittel (#909, Runde 67):
//   money-as-float   Feld, Variable, Parameter oder Property mit einem Geldnamen
//                    vom Typ Double, Single, Extended oder Real (#1064). Die
//                    Namensteile nennt die Option namePatterns (Vorgabe Betrag,
//                    Preis, Summe, Netto, Brutto, Steuer, Amount, Price);
//                    maßgeblich ist der letzte Teil des Namens in CamelCase
//                    (GesamtPreis, Nettobetrag, FNetto, Preise; nicht
//                    NettoGewicht). Sätze, Faktoren, Raten, Quoten und Anteile
//                    (Steuersatz, PriceFactor) bleiben still, ebenso Prüfsummen.
//                    Mehrdeutige Wörter (Amount, Summe, Sum, Total: Menge bzw.
//                    Summe von irgendetwas) zählen nur mit Geldbezug in Typ bzw.
//                    Routine: ein anderer Geldname, Currency oder Wörter wie Cent,
//                    Euro, Rabatt, Rechnung, Zahlung, Kosten (Lighten(AColor,
//                    AAmount: Double) bleibt still).
//                    Standard aus, niedrige Konfidenz. Korrektur: Typ Currency,
//                    wenn alle Namen der Deklaration Geldbeträge sind; bei
//                    Parametern auch im Kopf der Implementierung, bei Feldern
//                    und Properties auch die Property bzw. das Feld hinter read
//                    und write (sonst E2010). Mit checkRound zusätzlich Round
//                    mit einem Geldbetrag im Argument (Banker's Rounding).
//   string-if-chain  if … else if-Kette, die denselben String (Bezeichner oder
//                    A.B) mit mindestens min Literalen vergleicht (#1066, Vorgabe
//                    4): S = 'x', 'x' = S, SameText(S, 'x'), auch mit or
//                    verknüpft, in mindestens zwei Zweigen. Gezählt werden nur
//                    Vergleiche, die immer mit dem Kopf übersetzt werden
//                    (Pascal.ConditionalBranches).
//                    Standard aus. Korrektur wie #646: case IndexStr(S, [...]) of
//                    bzw. IndexText bei SameText, der Rest der Kette als else,
//                    System.StrUtils im uses; keine Korrektur bei Kommentaren oder
//                    Direktiven in der Kette, doppelten Literalen oder gemischter
//                    Groß-/Kleinschreibung.
//   prefer-case      if … else if-Kette mit mindestens min Zweigen (Vorgabe 4,
//                    der else-Zweig zählt mit), die denselben ordinalen Ausdruck
//                    ohne Seiteneffekte mit Konstanten vergleicht und sich ohne
//                    Bedeutungsänderung als case schreiben lässt (#646; Erkennung
//                    und Korrektur aus Editing.IfCase, Typen über die
//                    Namensauflösung). Standard aus. Keine Meldung bei Direktiven
//                    in der Kette.

interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  cMoneyAsFloatRuleId = 'money-as-float';
  cStringIfChainRuleId = 'string-if-chain';
  cPreferCaseRuleId = 'prefer-case';

type
  TMoneyAsFloatRule = class(TInterfacedObject, IRule)
  public const
    cDefaultPatterns: array[0..7] of string = ('Betrag', 'Preis', 'Summe', 'Netto', 'Brutto', 'Steuer', 'Amount',
      'Price');
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Letzter Namensteil in CamelCase bzw. nach _: GesamtPreis → Preis, ABetrag → Betrag.</summary>
    class function HeadOf(const AName: string): string; static;
    /// <summary>AName bezeichnet nach APatterns einen Geldbetrag (Mehrzahl eingeschlossen, Sätze
    /// ausgenommen).</summary>
    class function IsMoneyName(const AName: string; const APatterns: TArray<string>): Boolean; static;
    /// <summary>AName ist nur über ein mehrdeutiges Muster (Amount, Summe, Sum, Total) ein Geldname.</summary>
    class function IsAmbiguousName(const AName: string; const APatterns: TArray<string>): Boolean; static;
  end;

  TStringIfChainRule = class(TInterfacedObject, IRule)
  public const
    cDefaultMin = 4;
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Zahlwort mit großem Anfangsbuchstaben bis zwölf, darüber Ziffern.</summary>
    class function CountWord(ACount: Integer): string; static;
  end;

  TPreferCaseRule = class(TInterfacedObject, IRule)
  public const
    cDefaultMin = 4;
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

/// <summary>Registriert die Regeln für das passendere Sprachmittel.</summary>
procedure RegisterIdiomRules(const ARegistry: TRuleRegistry);

implementation

uses
  Atlas.Common.Pascal.TokenCursor,
  Atlas.Common.Rules.Derived,
  System.SysUtils,
  System.StrUtils,
  System.Character,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.ConditionalBranches,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Editing.StatementText,
  Atlas.Common.Editing.IfCase,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Rules.Options,
  Atlas.Text.Lines,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TIdiomsText = (MoneyFloatTitle, ChangeToCurrency, MoneyFloat, BankersRounding, StringIfChainTitle, ConvertToCase,
    StringIfChain, IfChainTitle, IfChain, Two, Three, Four, Five, Six, Seven, Eight, Nine, Ten, Eleven, Twelve);

const
  cTexts: array[TIdiomsText] of TAtlasText = (
    (De: 'Geldbetrag als Gleitkommazahl'; En: 'Money amount as floating-point number'),
    (De: 'Typ in Currency ändern'; En: 'Change type to Currency'),
    (De: '%s ist %s; Currency rechnet Cent-Beträge exakt.'; En: '%s is %s; Currency computes cent amounts exactly.'),
    (De: 'Round rundet %s auf die nächste gerade Zahl (2,5 wird 2); Geldbeträge kaufmännisch runden, z. B. mit ' +
      'SimpleRoundTo.';
     En: 'Round rounds %s to the nearest even number (2.5 becomes 2); round money amounts commercially, e.g. with ' +
      'SimpleRoundTo.'),
    (De: 'Lange if-Kette über denselben String'; En: 'Long if chain over the same string'),
    (De: 'In case %s(…) umwandeln'; En: 'Convert to case %s(…)'),
    (De: '%s Vergleiche desselben Strings; case %s(%s, [...]) ist kürzer.';
     En: '%s comparisons of the same string; case %s(%s, [...]) is shorter.'),
    (De: 'if-Kette lässt sich als case schreiben'; En: 'if chain can be written as case'),
    (De: '%s Zweige vergleichen denselben Ausdruck mit Konstanten; als case ist die Kette kürzer.';
     En: '%s branches compare the same expression with constants; as case the chain is shorter.'),
    (De: 'Zwei'; En: 'Two'),
    (De: 'Drei'; En: 'Three'),
    (De: 'Vier'; En: 'Four'),
    (De: 'Fünf'; En: 'Five'),
    (De: 'Sechs'; En: 'Six'),
    (De: 'Sieben'; En: 'Seven'),
    (De: 'Acht'; En: 'Eight'),
    (De: 'Neun'; En: 'Nine'),
    (De: 'Zehn'; En: 'Ten'),
    (De: 'Elf'; En: 'Eleven'),
    (De: 'Zwölf'; En: 'Twelve'));

{$SCOPEDENUMS OFF}

type
  TTokens = TArray<TPascalToken>;

function NodeText(const AContext: TRuleContext; ANode: TSyntaxNode): string;
begin
  Result := Trim(Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset));
end;

function NodeRange(ANode: TSyntaxNode): TTextRange;
begin
  Result := TTextRange.Create(ANode.StartPos, ANode.EndPos);
end;

// Iterativ (Bericht M1).
procedure CollectNodes(ARoot: TSyntaxNode; AList: TList<TSyntaxNode>);
var
  mPending: TStack<TSyntaxNode>;
  mNode: TSyntaxNode;
  mIndex: Integer;
begin
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ARoot);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      AList.Add(mNode);
      for mIndex := mNode.ChildCount - 1 downto 0 do
      begin
        mPending.Push(mNode[mIndex]);
      end;
    end;
  finally
    mPending.Free;
  end;
end;

/// <summary>ARoot und alle Nachfahren in Dokumentreihenfolge.</summary>
function NodesOf(ARoot: TSyntaxNode): TArray<TSyntaxNode>;
var
  mList: TList<TSyntaxNode>;
begin
  mList := TList<TSyntaxNode>.Create;
  try
    CollectNodes(ARoot, mList);
    Result := mList.ToArray;
  finally
    mList.Free;
  end;
end;

/// <summary>Routine mit Rumpf; ohne sind es Deklarationen im interface-Teil, forward und external.</summary>
function HasBody(ARoutine: TSyntaxNode): Boolean;
begin
  Result := (ARoutine <> nil) and (ARoutine.Kind = TSyntaxKind.RoutineDecl) and
    (ARoutine.FindChild(TSyntaxKind.Block) <> nil);
end;

function AncestorOf(ANode: TSyntaxNode; AKind: TSyntaxKind): TSyntaxNode;
begin
  Result := ANode.Parent;
  while (Result <> nil) and (Result.Kind <> AKind) do
  begin
    Result := Result.Parent;
  end;
end;

/// <summary>Namen einer Deklaration "A,B" einzeln und ohne Leerraum.</summary>
function NamesOf(ANode: TSyntaxNode): TArray<string>;
var
  mName: string;
begin
  Result := nil;
  for mName in ANode.Name.Split([',']) do
  begin
    if Trim(mName) <> '' then
    begin
      Result := Result + [Trim(mName)];
    end;
  end;
end;

{ TMoneyAsFloatRule }

const
  cFloatTypes: array[0..3] of string = ('Double', 'Single', 'Extended', 'Real');
  // Mehrzahl und Fugen: Preise, Summen, Steuern, Amounts.
  cPluralEndings: array[0..6] of string = ('', 'e', 'n', 'en', 's', 'es', 'er');
  // Verhältnisse und Prüfsummen sind keine Beträge, auch wenn ein Geldwort davorsteht.
  cRatioWords: array[0..21] of string = ('Satz', 'Saetze', 'Sätze', 'Faktor', 'Faktoren', 'Rate', 'Raten', 'Rates',
    'Quote', 'Quoten', 'Prozent', 'Anteil', 'Anteile', 'Percent', 'Percentage', 'Ratio', 'Ratios', 'Factor',
    'Factors', 'Pruefsumme', 'Prüfsumme', 'Quersumme');
  // Muster, die auch Mengen und Summen beliebiger Werte bezeichnen (Farbanteil, Messwerte).
  cAmbiguousWords: array[0..3] of string = ('Amount', 'Summe', 'Sum', 'Total');
  // Wörter, die einen Geldbezug herstellen.
  cMoneyContextWords: array[0..30] of string = ('Cent', 'Euro', 'EUR', 'USD', 'Dollar', 'Waehrung', 'Währung',
    'Currency', 'Rabatt', 'Discount', 'Rechnung', 'Invoice', 'Zahlung', 'Payment', 'Kosten', 'Cost', 'Gebuehr',
    'Gebühr', 'Fee', 'Saldo', 'Balance', 'Lohn', 'Gehalt', 'Salary', 'Kasse', 'MwSt', 'Mehrwertsteuer', 'Tax',
    'Konto', 'Umsatz', 'Revenue');

function TMoneyAsFloatRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cMoneyAsFloatRuleId, TRuleSeverity.Hint, cTexts[TIdiomsText.MoneyFloatTitle].Text,
    True);
end;

class function TMoneyAsFloatRule.HeadOf(const AName: string): string;
var
  mIndex, mStart: Integer;
begin
  mStart := 1;
  for mIndex := 2 to Length(AName) do
  begin
    if AName[mIndex - 1] = '_' then
    begin
      mStart := mIndex;
    end
    else if AName[mIndex].IsUpper and (AName[mIndex - 1].IsLower or AName[mIndex - 1].IsDigit) then
    begin
      mStart := mIndex;
    end
    // ABetrag, FNetto: der letzte Großbuchstabe einer Folge beginnt das nächste Wort.
    else if AName[mIndex].IsUpper and AName[mIndex - 1].IsUpper and (mIndex < Length(AName)) and
      AName[mIndex + 1].IsLower then
    begin
      mStart := mIndex;
    end;
  end;
  Result := Copy(AName, mStart, MaxInt);
  while (Result <> '') and (Result[Length(Result)] = '_') do
  begin
    Delete(Result, Length(Result), 1);
  end;
end;

class function TMoneyAsFloatRule.IsMoneyName(const AName: string; const APatterns: TArray<string>): Boolean;
var
  mHead, mPattern, mEnding, mWord: string;
begin
  mHead := HeadOf(AName);
  // Preis2, Betrag_1: Ziffern am Ende zählen nicht zum Wort.
  while (mHead <> '') and mHead[Length(mHead)].IsDigit do
  begin
    Delete(mHead, Length(mHead), 1);
  end;
  for mWord in cRatioWords do
  begin
    if EndsText(mWord, mHead) then
    begin
      Exit(False);
    end;
  end;
  for mPattern in APatterns do
  begin
    if Trim(mPattern) <> '' then
    begin
      for mEnding in cPluralEndings do
      begin
        if EndsText(Trim(mPattern) + mEnding, mHead) then
        begin
          Exit(True);
        end;
      end;
    end;
  end;
  Result := False;
end;

/// <summary>APatterns ohne die mehrdeutigen Wörter.</summary>
function UnambiguousPatterns(const APatterns: TArray<string>): TArray<string>;
var
  mPattern: string;
begin
  Result := nil;
  for mPattern in APatterns do
  begin
    if not MatchText(Trim(mPattern), cAmbiguousWords) then
    begin
      Result := Result + [mPattern];
    end;
  end;
end;

class function TMoneyAsFloatRule.IsAmbiguousName(const AName: string; const APatterns: TArray<string>): Boolean;
begin
  Result := IsMoneyName(AName, APatterns) and not IsMoneyName(AName, UnambiguousPatterns(APatterns));
end;

procedure TMoneyAsFloatRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TTokens;
  mPatterns: TArray<string>;
  mNodes: TArray<TSyntaxNode>;
  mDeclared: TDictionary<string, Boolean>;
  mContextPatterns: TArray<string>;

  // Geldbezug im Typ bzw. in der Routine um ANode: ein anderer Geldname, Currency oder ein Geldwort.
  function HasMoneyContext(ANode: TSyntaxNode; const AName: string): Boolean;
  var
    mScope: TSyntaxNode;
    mIndex: Integer;
  begin
    mScope := AncestorOf(ANode, TSyntaxKind.TypeDecl);
    if mScope = nil then
    begin
      mScope := AncestorOf(ANode, TSyntaxKind.RoutineDecl);
    end;
    if mScope = nil then
    begin
      mScope := AContext.Tree.Root;
    end;
    mIndex := TokenFrom(mTokens, mScope.StartOffset);
    while (mIndex <= High(mTokens)) and (mTokens[mIndex].Offset < mScope.EndOffset) do
    begin
      if (mTokens[mIndex].Kind = TPascalTokenKind.Identifier) and not SameText(mTokens[mIndex].Text, AName) and
        IsMoneyName(mTokens[mIndex].Text, mContextPatterns) then
      begin
        Exit(True);
      end;
      Inc(mIndex);
    end;
    Result := False;
  end;

  function IsMoney(ANode: TSyntaxNode; const AName: string): Boolean;
  begin
    Result := IsMoneyName(AName, mPatterns) and
      (not IsAmbiguousName(AName, mPatterns) or HasMoneyContext(ANode, AName));
  end;

  function IsFloat(ATypeRef: TSyntaxNode): Boolean;
  var
    mName: string;
  begin
    if (ATypeRef = nil) or (ATypeRef.ChildCount > 0) then
    begin
      Exit(False);
    end;
    mName := NodeText(AContext, ATypeRef);
    if StartsText('System.', mName) then
    begin
      mName := Copy(mName, Length('System.') + 1, MaxInt);
    end;
    Result := MatchText(mName, cFloatTypes);
  end;

  function AllMoney(ANode: TSyntaxNode): Boolean;
  var
    mName: string;
  begin
    for mName in NamesOf(ANode) do
    begin
      if not IsMoney(ANode, mName) then
      begin
        Exit(False);
      end;
    end;
    Result := True;
  end;

  // Token des Namens AName innerhalb von ANode.
  function NameRange(ANode: TSyntaxNode; const AName: string): TTextRange;
  var
    mIndex: Integer;
  begin
    mIndex := TokenFrom(mTokens, ANode.StartOffset);
    while (mIndex <= High(mTokens)) and (mTokens[mIndex].Offset < ANode.EndOffset) do
    begin
      if (mTokens[mIndex].Kind = TPascalTokenKind.Identifier) and SameText(mTokens[mIndex].Text, AName) then
      begin
        Exit(TTextRange.Create(mTokens[mIndex].StartPos, mTokens[mIndex].EndPos));
      end;
      Inc(mIndex);
    end;
    Result := NodeRange(ANode);
  end;

  function CurrencyEdit(ATypeRef: TSyntaxNode): TRuleEdit;
  begin
    Result := TRuleEdit.Create(NodeRange(ATypeRef), 'Currency');
  end;

  // Namen hinter read und write einer Property; '' für fehlende, '?' für Punkte (Record-Feld).
  procedure Accessors(AProperty: TSyntaxNode; out ARead, AWrite: string);
  var
    mIndex: Integer;
    mName: string;
  begin
    ARead := '';
    AWrite := '';
    mIndex := TokenFrom(mTokens, AProperty.StartOffset);
    while (mIndex < High(mTokens)) and (mTokens[mIndex].Offset < AProperty.EndOffset) do
    begin
      if MatchText(mTokens[mIndex].Text, ['read', 'write']) and (mTokens[mIndex + 1].Kind = TPascalTokenKind.Identifier) then
      begin
        mName := mTokens[mIndex + 1].Text;
        if (mIndex + 2 <= High(mTokens)) and (mTokens[mIndex + 2].Text = '.') then
        begin
          mName := '?';
        end;
        if SameText(mTokens[mIndex].Text, 'read') then
        begin
          ARead := mName;
        end
        else
        begin
          AWrite := mName;
        end;
      end;
      Inc(mIndex);
    end;
  end;

  function MemberOf(AType: TSyntaxNode; AKind: TSyntaxKind; const AName: string): TSyntaxNode;
  var
    mIndex: Integer;
    mName: string;
  begin
    for mIndex := 0 to AType.ChildCount - 1 do
    begin
      if AType[mIndex].Kind = AKind then
      begin
        for mName in NamesOf(AType[mIndex]) do
        begin
          if SameText(mName, AName) then
          begin
            Exit(AType[mIndex]);
          end;
        end;
      end;
    end;
    Result := nil;
  end;

  // Property: Felder hinter read und write mit ändern; Getter und Setter müssten mitwandern.
  function PropertyEdits(AProperty: TSyntaxNode; out AEdits: TArray<TRuleEdit>): Boolean;
  var
    mOwner, mField: TSyntaxNode;
    mRead, mWrite, mName: string;
    mNames: TArray<string>;
  begin
    AEdits := [CurrencyEdit(AProperty.FindChild(TSyntaxKind.TypeReference))];
    mOwner := AProperty.Parent;
    Accessors(AProperty, mRead, mWrite);
    mNames := nil;
    if mRead <> '' then
    begin
      mNames := mNames + [mRead];
    end;
    if (mWrite <> '') and not SameText(mWrite, mRead) then
    begin
      mNames := mNames + [mWrite];
    end;
    for mName in mNames do
    begin
      if (mName = '?') or (mOwner = nil) then
      begin
        Exit(False);
      end;
      mField := MemberOf(mOwner, TSyntaxKind.Field, mName);
      if (mField = nil) or (Length(NamesOf(mField)) <> 1) or
        not IsFloat(mField.FindChild(TSyntaxKind.TypeReference)) then
      begin
        Exit(False);
      end;
      AEdits := AEdits + [CurrencyEdit(mField.FindChild(TSyntaxKind.TypeReference))];
    end;
    Result := True;
  end;

  // Property AMember zum Feld AField: mit ändern (AEdits), wenn sie nur das Feld liest und schreibt; False, wenn
  // sie keinen Gleitkommatyp hat oder der andere Zugriff eine Methode oder ein anderes Feld ist.
  function PropertyEdit(AMember, AField: TSyntaxNode; var AEdits: TArray<TRuleEdit>): Boolean;
  var
    mRead, mWrite: string;
  begin
    Result := True;
    if AMember.Kind <> TSyntaxKind.PropertyDecl then
    begin
      Exit;
    end;
    Accessors(AMember, mRead, mWrite);
    if not SameText(mRead, AField.Name) and not SameText(mWrite, AField.Name) then
    begin
      Exit;
    end;
    Result := IsFloat(AMember.FindChild(TSyntaxKind.TypeReference)) and ((mRead = '') or
      SameText(mRead, AField.Name)) and ((mWrite = '') or SameText(mWrite, AField.Name));
    if Result then
    begin
      AEdits := AEdits + [CurrencyEdit(AMember.FindChild(TSyntaxKind.TypeReference))];
    end;
  end;

  // Feld: Properties, die es lesen oder schreiben, mit ändern.
  function FieldEdits(AField: TSyntaxNode; out AEdits: TArray<TRuleEdit>): Boolean;
  var
    mOwner: TSyntaxNode;
    mIndex: Integer;
  begin
    AEdits := [CurrencyEdit(AField.FindChild(TSyntaxKind.TypeReference))];
    Result := True;
    mOwner := AField.Parent;
    mIndex := 0;
    while Result and (mOwner <> nil) and (mIndex < mOwner.ChildCount) do
    begin
      Result := PropertyEdit(mOwner[mIndex], AField, AEdits);
      Inc(mIndex);
    end;
  end;

  function ParametersOf(AHeader: TSyntaxNode): TArray<TSyntaxNode>;
  var
    mList: TSyntaxNode;
    mIndex: Integer;
  begin
    Result := nil;
    mList := AHeader.FindChild(TSyntaxKind.Parameters);
    if mList <> nil then
    begin
      for mIndex := 0 to mList.ChildCount - 1 do
      begin
        if mList[mIndex].Kind = TSyntaxKind.Parameter then
        begin
          Result := Result + [mList[mIndex]];
        end;
      end;
    end;
  end;

  // Haben AOwn und AOther dieselben Parameternamen in derselben Reihenfolge?
  function SameParameters(const AOwn, AOther: TArray<TSyntaxNode>): Boolean;
  var
    mIndex: Integer;
  begin
    Result := Length(AOther) = Length(AOwn);
    mIndex := 0;
    while Result and (mIndex <= High(AOwn)) do
    begin
      Result := SameText(AOwn[mIndex].Name, AOther[mIndex].Name);
      Inc(mIndex);
    end;
  end;

  // Kopf von ANode, wenn ANode die Implementierung AName mit den Parametern AOwn ist; sonst nil. Ohne
  // Parameterliste wiederholt die Implementierung nichts.
  function ImplementingHeader(ANode: TSyntaxNode; const AName: string; const AOwn: TArray<TSyntaxNode>): TSyntaxNode;
  var
    mOther: TArray<TSyntaxNode>;
  begin
    Result := nil;
    if HasBody(ANode) and SameText(ANode.Name, AName) then
    begin
      Result := ANode.FindChild(TSyntaxKind.RoutineHeader);
    end;
    if Result <> nil then
    begin
      mOther := ParametersOf(Result);
      if (mOther <> nil) and not SameParameters(AOwn, mOther) then
      begin
        Result := nil;
      end;
    end;
  end;

  // Kopf der Implementierung zu einer Deklaration AHeader (Methode im Typ oder Routine im interface).
  function ImplementationOf(AHeader: TSyntaxNode): TSyntaxNode;
  var
    mTypeDecl, mNode: TSyntaxNode;
    mName: string;
    mOwn: TArray<TSyntaxNode>;
  begin
    Result := nil;
    mName := AHeader.Name;
    mTypeDecl := AncestorOf(AHeader, TSyntaxKind.TypeDecl);
    if mTypeDecl <> nil then
    begin
      if Pos('<', mTypeDecl.Name) > 0 then
      begin
        Exit;
      end;
      mName := mTypeDecl.Name + '.' + mName;
    end;
    mOwn := ParametersOf(AHeader);
    for mNode in mNodes do
    begin
      Result := ImplementingHeader(mNode, mName, mOwn);
      if Result <> nil then
      begin
        Exit;
      end;
    end;
  end;

  // Parameter: auch im Kopf der Implementierung ändern.
  function ParameterEdits(AParameter: TSyntaxNode; out AEdits: TArray<TRuleEdit>): Boolean;
  var
    mHeader, mImplementation_: TSyntaxNode;
    mIndex: Integer;
    mOwn, mOther: TArray<TSyntaxNode>;
    mTypeRef: TSyntaxNode;
  begin
    AEdits := [CurrencyEdit(AParameter.FindChild(TSyntaxKind.TypeReference))];
    mHeader := AncestorOf(AParameter, TSyntaxKind.RoutineHeader);
    // Prozeduraler Typ oder Routine nur mit Rumpf: eine Stelle. Deklaration im Typ, im interface-Teil oder
    // forward: auch der Kopf mit Rumpf.
    if (mHeader = nil) or HasBody(mHeader.Parent) or (mHeader.Parent = nil) or
      ((mHeader.Parent.Kind <> TSyntaxKind.RoutineDecl) and (AncestorOf(mHeader, TSyntaxKind.TypeDecl) = nil)) then
    begin
      Exit(True);
    end;
    mImplementation_ := ImplementationOf(mHeader);
    if mImplementation_ = nil then
    begin
      Exit(False);
    end;
    mOwn := ParametersOf(mHeader);
    mOther := ParametersOf(mImplementation_);
    if mOther = nil then
    begin
      Exit(True);
    end;
    for mIndex := 0 to High(mOwn) do
    begin
      if mOwn[mIndex] = AParameter then
      begin
        mTypeRef := mOther[mIndex].FindChild(TSyntaxKind.TypeReference);
        if not IsFloat(mTypeRef) then
        begin
          Exit(False);
        end;
        AEdits := AEdits + [CurrencyEdit(mTypeRef)];
      end;
    end;
    Result := True;
  end;

  // Parameter der Implementierung, deren Deklaration schon geprüft wird.
  function RepeatsDeclaration(AParameter: TSyntaxNode): Boolean;
  var
    mHeader: TSyntaxNode;
  begin
    mHeader := AncestorOf(AParameter, TSyntaxKind.RoutineHeader);
    Result := (mHeader <> nil) and HasBody(mHeader.Parent) and
      ((Pos('.', mHeader.Name) > 0) or mDeclared.ContainsKey(LowerCase(mHeader.Name)));
  end;

  procedure CheckDeclaration(ANode: TSyntaxNode);
  var
    mTypeRef: TSyntaxNode;
    mName: string;
    mFixes: TArray<TRuleFix>;
    mEdits: TArray<TRuleEdit>;
    mFixable: Boolean;
  begin
    mTypeRef := ANode.FindChild(TSyntaxKind.TypeReference);
    if not IsFloat(mTypeRef) then
    begin
      Exit;
    end;
    if (ANode.Kind = TSyntaxKind.Parameter) and RepeatsDeclaration(ANode) then
    begin
      Exit;
    end;
    mFixes := nil;
    if AllMoney(ANode) then
    begin
      case ANode.Kind of
        TSyntaxKind.Parameter:
          mFixable := ParameterEdits(ANode, mEdits);
        TSyntaxKind.PropertyDecl:
          mFixable := PropertyEdits(ANode, mEdits);
        TSyntaxKind.Field:
          mFixable := FieldEdits(ANode, mEdits);
      else
        begin
          mEdits := [CurrencyEdit(mTypeRef)];
          mFixable := True;
        end;
      end;
      if mFixable then
      begin
        mFixes := [TRuleFix.Create(cTexts[TIdiomsText.ChangeToCurrency].Text, mEdits)];
      end;
    end;
    for mName in NamesOf(ANode) do
    begin
      if IsMoney(ANode, mName) then
      begin
        AReport.Add(NameRange(ANode, mName), cTexts[TIdiomsText.MoneyFloat].Fmt(
          [mName, NodeText(AContext, mTypeRef)]), TRuleConfidence.Low, mFixes);
      end;
    end;
  end;

  // Round(Betrag * 100): Banker's Rounding auf einem Geldbetrag.
  procedure CheckRound(ACall: TSyntaxNode);
  var
    mIndex: Integer;
    mNode: TSyntaxNode;
    mList: TList<TSyntaxNode>;
  begin
    if (ACall[0].Kind <> TSyntaxKind.Identifier) or not SameText(ACall[0].Name, 'Round') then
    begin
      Exit;
    end;
    mList := TList<TSyntaxNode>.Create;
    try
      for mIndex := 1 to ACall.ChildCount - 1 do
      begin
        CollectNodes(ACall[mIndex], mList);
      end;
      for mNode in mList do
      begin
        if (mNode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) and
          not ((mNode.Parent <> nil) and (mNode.Parent.Kind = TSyntaxKind.Call) and (mNode.Parent[0] = mNode)) and
          IsMoney(mNode, mNode.Name) then
        begin
          AReport.Add(NodeRange(ACall[0]), cTexts[TIdiomsText.BankersRounding].Fmt([mNode.Name]), TRuleConfidence.Low);
          Exit;
        end;
      end;
    finally
      mList.Free;
    end;
  end;

var
  mNode: TSyntaxNode;
  mDefaults: TArray<string>;
  mPattern: string;
  mRoundCheck: Boolean;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mDefaults := nil;
  for mPattern in cDefaultPatterns do
  begin
    mDefaults := mDefaults + [mPattern];
  end;
  mPatterns := TRuleOptions.Strings(AContext.Options, 'namePatterns', mDefaults);
  mContextPatterns := UnambiguousPatterns(mPatterns);
  for mPattern in cMoneyContextWords do
  begin
    mContextPatterns := mContextPatterns + [mPattern];
  end;
  mRoundCheck := TRuleOptions.Bool(AContext.Options, 'checkRound', False);
  mTokens := AContext.Tree.Tokens;
  mNodes := NodesOf(AContext.Tree.Root);
  mDeclared := TDictionary<string, Boolean>.Create;
  try
    // Routinen mit Deklaration im interface-Teil bzw. forward: Parameter dort prüfen.
    for mNode in mNodes do
    begin
      if (mNode.Kind = TSyntaxKind.RoutineDecl) and not HasBody(mNode) and
        (AncestorOf(mNode, TSyntaxKind.TypeDecl) = nil) then
      begin
        mDeclared.AddOrSetValue(LowerCase(mNode.Name), True);
      end;
    end;
    for mNode in mNodes do
      case mNode.Kind of
        TSyntaxKind.Field, TSyntaxKind.VarDecl, TSyntaxKind.Parameter, TSyntaxKind.PropertyDecl,
        TSyntaxKind.InlineVar:
          CheckDeclaration(mNode);
        TSyntaxKind.Call:
          if mRoundCheck and (mNode.ChildCount > 1) then
          begin
            CheckRound(mNode);
          end;
      else
        // Übrige Werte bewusst ohne Wirkung.
      end;
  finally
    mDeclared.Free;
  end;
end;

{ TStringIfChainRule }

const
  cCountWords: array[2..12] of TIdiomsText = (TIdiomsText.Two, TIdiomsText.Three, TIdiomsText.Four, TIdiomsText.Five,
    TIdiomsText.Six, TIdiomsText.Seven, TIdiomsText.Eight, TIdiomsText.Nine, TIdiomsText.Ten, TIdiomsText.Eleven,
    TIdiomsText.Twelve);

type
  /// <summary>Ein Zweig der Kette: Literale der Bedingung und die Anweisung dahinter.</summary>
  TChainBranch = record
    Literals: TArray<string>;
    Statement: TSyntaxNode;
    Condition: TSyntaxNode;
  end;

function TStringIfChainRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cStringIfChainRuleId, TRuleSeverity.Hint,
    cTexts[TIdiomsText.StringIfChainTitle].Text,
    True);
end;

class function TStringIfChainRule.CountWord(ACount: Integer): string;
begin
  if (ACount >= Low(cCountWords)) and (ACount <= High(cCountWords)) then
  begin
    Result := cTexts[cCountWords[ACount]].Text;
  end
  else
  begin
    Result := IntToStr(ACount);
  end;
end;

function UsesEdit(const AContext: TRuleContext; const ATokens: TTokens; AOffset: Integer;
  const AUnitName: string; out AEdit: TTextEdit): Boolean;
var
  mUsed: TArray<string>;
  mShort: string;
begin
  mUsed := TUsesClauses.UsedUnits(ATokens);
  mShort := Copy(AUnitName, LastDelimiter('.', AUnitName) + 1, MaxInt);
  if TUsesClauses.IsUsed(mUsed, AUnitName, AContext.Namespaces) or TUsesClauses.IsUsed(mUsed, mShort, nil) then
  begin
    Exit(False);
  end;
  Result := TUsesClauses.AddUnit(ATokens, AOffset, AUnitName, TTextLines.LineBreakOf(AContext.Text), AEdit);
end;

/// <summary>Nur Bezeichner und Punkte: S, Self.FBefehl, Edit1.Text. Iterativ (Bericht M1).</summary>
function IsSubject(ANode: TSyntaxNode): Boolean;
var
  mNode: TSyntaxNode;
begin
  mNode := ANode;
  while (mNode.Kind = TSyntaxKind.MemberAccess) and (mNode.ChildCount = 1) do
  begin
    mNode := mNode[0];
  end;
  Result := mNode.Kind = TSyntaxKind.Identifier;
end;

function IsStringLiteral(const AContext: TRuleContext; ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.Literal) and StartsStr('''', NodeText(AContext, ANode));
end;

procedure TStringIfChainRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TTokens;
  mPaths: TArray<string>;
  mLineBreak: string;
  mLines: TArray<string>;

  function Normalized(ANode: TSyntaxNode): string;
  begin
    Result := StringReplace(NodeText(AContext, ANode), ' ', '', [rfReplaceAll]);
  end;

  // Seiten des Vergleichs ACondition: S = 'x', 'x' = S oder SameText(S, 'x'); AKind: 1 für =, 2 für SameText.
  function ComparedSides(ACondition: TSyntaxNode; out ASubject, ALiteral: TSyntaxNode; out AKind: Integer): Boolean;
  var
    mFirst: Integer;
  begin
    AKind := 0;
    mFirst := 0;
    ASubject := nil;
    ALiteral := nil;
    if (ACondition.Kind = TSyntaxKind.BinaryExpr) and (ACondition.Name = '=') and (ACondition.ChildCount = 2) then
    begin
      AKind := 1;
    end
    else if (ACondition.Kind = TSyntaxKind.Call) and (ACondition.ChildCount = 3) and
      (ACondition[0].Kind = TSyntaxKind.Identifier) and MatchText(ACondition[0].Name, ['SameText', 'AnsiSameText']) then
    begin
      AKind := 2;
      mFirst := 1;
    end;
    Result := AKind <> 0;
    if Result then
    begin
      ASubject := ACondition[mFirst];
      ALiteral := ACondition[mFirst + 1];
      if IsStringLiteral(AContext, ASubject) then
      begin
        ASubject := ACondition[mFirst + 1];
        ALiteral := ACondition[mFirst];
      end;
    end;
  end;

  // Ein einzelner Vergleich S = 'x', 'x' = S oder SameText(S, 'x').
  function Comparison(ACondition: TSyntaxNode; var ASubject: string; var ALiterals: TArray<string>;
    var ASensitive: Integer): Boolean;
  var
    mSubject, mLiteral: TSyntaxNode;
    mKind: Integer;
  begin
    Result := ComparedSides(ACondition, mSubject, mLiteral, mKind);
    if Result then
    begin
      ASensitive := ASensitive or mKind;
    end;
    Result := Result and IsStringLiteral(AContext, mLiteral) and IsSubject(mSubject);
    if Result and (ASubject = '') then
    begin
      ASubject := Normalized(mSubject);
    end;
    Result := Result and SameText(ASubject, Normalized(mSubject));
    if Result then
    begin
      ALiterals := ALiterals + [NodeText(AContext, mLiteral)];
    end;
  end;

  // Vergleiche in ACondition: S = 'x', 'x' = S, SameText(S, 'x'), mit or verknüpft und geklammert.
  // ASensitive: 1 = nur =, 2 = nur SameText, 3 = gemischt. Iterativ (Bericht M1): die Vergleiche der
  // or-Kette von links nach rechts; der erste, der nicht passt, beendet die Suche.
  function Comparisons(ACondition: TSyntaxNode; var ASubject: string; var ALiterals: TArray<string>;
    var ASensitive: Integer): Boolean;
  var
    mPending: TStack<TSyntaxNode>;
    mNode: TSyntaxNode;
  begin
    Result := False;
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ACondition);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if mNode.Kind = TSyntaxKind.ParenExpr then
        begin
          if mNode.ChildCount <> 1 then
          begin
            Exit;
          end;
          mPending.Push(mNode[0]);
        end
        else if (mNode.Kind = TSyntaxKind.BinaryExpr) and SameText(mNode.Name, 'or') and (mNode.ChildCount = 2) then
        begin
          mPending.Push(mNode[1]);
          mPending.Push(mNode[0]);
        end
        else if not Comparison(mNode, ASubject, ALiterals, ASensitive) then
        begin
          Exit;
        end;
      end;
    finally
      mPending.Free;
    end;
    Result := True;
  end;

  function SubjectOf(AIf: TSyntaxNode): string;
  var
    mLiterals: TArray<string>;
    mSensitive: Integer;
  begin
    Result := '';
    mLiterals := nil;
    mSensitive := 0;
    if (AIf.Kind <> TSyntaxKind.IfStatement) or (AIf.ChildCount < 2) or
      not Comparisons(AIf[0], Result, mLiterals, mSensitive) then
    begin
      Result := '';
    end;
  end;

  function PathOf(ANode: TSyntaxNode): string;
  begin
    Result := TConditionalBranches.PathAt(mPaths, TokenFrom(mTokens, ANode.StartOffset));
  end;

  function LineOf(ALine: Integer): string;
  begin
    Result := '';
    if (ALine >= 0) and (ALine <= High(mLines)) then
    begin
      Result := mLines[ALine];
    end;
  end;

  // Text von ANode, Folgezeilen um die Einrückung seiner ersten Zeile auf AIndent verschoben.
  function Reindented(ANode: TSyntaxNode; const AIndent: string): string;
  var
    mParts: TArray<string>;
    mBase, mIndex: Integer;
    mLine: string;
  begin
    mParts := NodeText(AContext, ANode).Replace(#13#10, #10).Split([#10]);
    mBase := Length(TTextLines.IndentOf(LineOf(ANode.StartPos.Line)));
    Result := AIndent + mParts[0];
    for mIndex := 1 to High(mParts) do
    begin
      mLine := mParts[mIndex];
      if Length(TTextLines.IndentOf(mLine)) >= mBase then
      begin
        mLine := Copy(mLine, mBase + 1, MaxInt);
      end
      else
      begin
        mLine := TrimLeft(mLine);
      end;
      Result := Result + mLineBreak + AIndent + mLine;
    end;
  end;

  // Liegt AOffset in einer Anweisung der Zweige oder im else-Teil AElse?
  function InBranches(AOffset: Integer; const ABranches: TArray<TChainBranch>; AElse: TSyntaxNode): Boolean;
  var
    mBranch: TChainBranch;
  begin
    Result := (AElse <> nil) and (AOffset >= AElse.StartOffset) and (AOffset < AElse.EndOffset);
    for mBranch in ABranches do
    begin
      Result := Result or ((AOffset >= mBranch.Statement.StartOffset) and (AOffset < mBranch.Statement.EndOffset));
    end;
  end;

  // Kommentare und Direktiven zwischen den Zweigen gingen verloren.
  function OnlyCode(AHead: TSyntaxNode; const ABranches: TArray<TChainBranch>; AElse: TSyntaxNode): Boolean;
  var
    mIndex: Integer;
  begin
    Result := True;
    mIndex := TokenFrom(mTokens, AHead.StartOffset);
    while Result and (mIndex <= High(mTokens)) and (mTokens[mIndex].Offset < AHead.EndOffset) do
    begin
      Result := (mTokens[mIndex].Kind <> TPascalTokenKind.Directive) and
        ((mTokens[mIndex].Kind <> TPascalTokenKind.Comment) or InBranches(mTokens[mIndex].Offset, ABranches, AElse));
      Inc(mIndex);
    end;
  end;

  // Literale aller Zweige in Reihenfolge; False, wenn ein Zweig keine Anweisung hat oder ein Literal doppelt
  // vorkommt (mit ASensitive unter Beachtung der Groß-/Kleinschreibung).
  function DistinctLiterals(const ABranches: TArray<TChainBranch>; ASensitive: Boolean;
    out ASeen: TArray<string>): Boolean;
  var
    mBranch: TChainBranch;
    mLiteral: string;
  begin
    ASeen := nil;
    Result := True;
    for mBranch in ABranches do
    begin
      Result := Result and (mBranch.Statement <> nil);
      for mLiteral in mBranch.Literals do
      begin
        Result := Result and not ((ASensitive and MatchStr(mLiteral, ASeen)) or
          (not ASensitive and MatchText(mLiteral, ASeen)));
        ASeen := ASeen + [mLiteral];
      end;
    end;
  end;

  // Marken 0, 1, … für die Literale von ABranch; ANumber zählt über die Zweige weiter.
  function CaseLabels(const ABranch: TChainBranch; var ANumber: Integer): string;
  var
    mIndex: Integer;
  begin
    Result := '';
    for mIndex := 0 to High(ABranch.Literals) do
    begin
      if Result <> '' then
      begin
        Result := Result + ', ';
      end;
      Result := Result + IntToStr(ANumber);
      Inc(ANumber);
    end;
  end;

  // Zweig ABranch als Zweig der case-Anweisung mit der Einrückung AIndent.
  function CaseBranch(const ABranch: TChainBranch; const AIndent: string; var ANumber: Integer): string;
  var
    mLabels: string;
  begin
    mLabels := CaseLabels(ABranch, ANumber);
    if ABranch.Statement.StartPos.Line = ABranch.Statement.EndPos.Line then
    begin
      Result := mLineBreak + AIndent + '  ' + mLabels + ': ' + NodeText(AContext, ABranch.Statement) + ';';
    end
    else
    begin
      Result := mLineBreak + AIndent + '  ' + mLabels + ':' + mLineBreak +
        Reindented(ABranch.Statement, AIndent + '    ') + ';';
    end;
  end;

  function Fix(AHead: TSyntaxNode; const ASubject: string; const ABranches: TArray<TChainBranch>;
    AElse: TSyntaxNode; ASensitive: Boolean; out AFix: TRuleFix): Boolean;
  var
    mSeen: TArray<string>;
    mBranch: TChainBranch;
    mIndent, mText, mFunction: string;
    mNumber: Integer;
    mEdits: TArray<TRuleEdit>;
    mExtra: TTextEdit;
  begin
    Result := DistinctLiterals(ABranches, ASensitive, mSeen) and OnlyCode(AHead, ABranches, AElse);
    if not Result then
    begin
      Exit;
    end;
    mFunction := 'IndexText';
    if ASensitive then
    begin
      mFunction := 'IndexStr';
    end;
    mIndent := TTextLines.IndentOf(LineOf(AHead.StartPos.Line));
    mText := 'case ' + mFunction + '(' + ASubject + ', [' + string.Join(', ', mSeen) + ']) of';
    mNumber := 0;
    for mBranch in ABranches do
    begin
      mText := mText + CaseBranch(mBranch, mIndent, mNumber);
    end;
    if AElse <> nil then
    begin
      mText := mText + mLineBreak + mIndent + 'else' + mLineBreak + Reindented(AElse, mIndent + '  ') + ';';
    end;
    mText := mText + mLineBreak + mIndent + 'end';
    mEdits := [TRuleEdit.Create(NodeRange(AHead), mText)];
    if UsesEdit(AContext, mTokens, AHead.StartOffset, 'System.StrUtils', mExtra) then
    begin
      mEdits := mEdits + [mExtra];
    end;
    AFix := TRuleFix.Create(cTexts[TIdiomsText.ConvertToCase].Fmt([mFunction]), mEdits);
  end;

  procedure CheckChain(AHead: TSyntaxNode; AMin: Integer);
  var
    mSubject, mHeadPath: string;
    mCurrent: TSyntaxNode;
    mBranches: TArray<TChainBranch>;
    mBranch: TChainBranch;
    mSensitive, mCount: Integer;
    mSamePath: Boolean;
    mFixes: TArray<TRuleFix>;
    mOne: TRuleFix;
  begin
    mSubject := '';
    mSensitive := 0;
    mBranches := nil;
    mCurrent := AHead;
    mHeadPath := PathOf(AHead);
    mCount := 0;
    mSamePath := True;
    while (mCurrent <> nil) and (mCurrent.Kind = TSyntaxKind.IfStatement) and (mCurrent.ChildCount >= 2) do
    begin
      mBranch := Default(TChainBranch);
      mBranch.Condition := mCurrent[0];
      if not Comparisons(mCurrent[0], mSubject, mBranch.Literals, mSensitive) then
      begin
        Break;
      end;
      mBranch.Statement := mCurrent[1];
      mBranches := mBranches + [mBranch];
      // Nur Vergleiche, die immer mit dem Kopf übersetzt werden.
      if TConditionalBranches.Implies(mHeadPath, PathOf(mCurrent[0])) then
      begin
        Inc(mCount, Length(mBranch.Literals));
      end;
      if PathOf(mCurrent[0]) <> mHeadPath then
      begin
        mSamePath := False;
      end;
      if mCurrent.ChildCount > 2 then
      begin
        mCurrent := mCurrent[2];
      end
      else
      begin
        mCurrent := nil;
      end;
    end;
    // Ein einzelnes if mit or ist keine Kette (dafür MatchStr).
    if (mCount < AMin) or (Length(mBranches) < 2) then
    begin
      Exit;
    end;
    mFixes := nil;
    if mSamePath and (mSensitive <> 3) and Fix(AHead, mSubject, mBranches, mCurrent, mSensitive = 1, mOne) then
    begin
      mFixes := [mOne];
    end;
    AReport.Add(TTextRange.Create(AHead.StartPos, AHead[0].EndPos),
      cTexts[TIdiomsText.StringIfChain].Fmt([CountWord(mCount),
      IfThen(mSensitive = 2, 'IndexText', 'IndexStr'), mSubject]), TRuleConfidence.High, mFixes);
  end;

  // Fortsetzung einer Kette über denselben String: der Kopf meldet sie.
  function ContinuesChain(ANode: TSyntaxNode): Boolean;
  begin
    Result := (ANode.Parent <> nil) and (ANode.Parent.Kind = TSyntaxKind.IfStatement) and
      (ANode.Parent.ChildCount > 2) and (ANode.Parent[2] = ANode);
    Result := Result and (SubjectOf(ANode) <> '') and SameText(SubjectOf(ANode.Parent), SubjectOf(ANode));
  end;

var
  mNode: TSyntaxNode;
  mMin: Integer;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mMin := TRuleOptions.Int(AContext.Options, 'min', cDefaultMin);
  if mMin < 2 then
  begin
    mMin := cDefaultMin;
  end;
  mTokens := AContext.Tree.Tokens;
  mPaths := TConditionalBranches.Paths(mTokens);
  mLineBreak := TTextLines.LineBreakOf(AContext.Text);
  mLines := TTextLines.SplitLines(AContext.Text);
  for mNode in NodesOf(AContext.Tree.Root) do
  begin
    if (mNode.Kind = TSyntaxKind.IfStatement) and (mNode.ChildCount >= 2) then
    begin
      if not ContinuesChain(mNode) and (SubjectOf(mNode) <> '') then
      begin
        CheckChain(mNode, mMin);
      end;
    end;
  end;
end;

{ TPreferCaseRule }

function TPreferCaseRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cPreferCaseRuleId, TRuleSeverity.Hint, cTexts[TIdiomsText.IfChainTitle].Text,
    True);
end;

/// <summary>Dateiname für den Resolver: die Datei, sonst der relative Pfad, sonst der Unitname mit .pas.</summary>
function ResolverFileName(const AContext: TRuleContext): string;
begin
  Result := AContext.FileName;
  if Result = '' then
  begin
    Result := AContext.RelativePath;
  end;
  if Result = '' then
  begin
    Result := AContext.UnitName + '.pas';
  end;
end;

/// <summary>Zweige der if-Kette ab AHead: die AConditions umwandelbaren Bedingungen und ein abschließendes
/// else; 0 ohne umwandelbare Bedingung.</summary>
function BranchCount(AHead: TSyntaxNode; AConditions: Integer): Integer;
var
  mLast: TSyntaxNode;
begin
  Result := AConditions;
  if Result = 0 then
  begin
    Exit;
  end;
  mLast := AHead;
  while (mLast.ChildCount = 3) and (mLast[2].Kind = TSyntaxKind.IfStatement) do
  begin
    mLast := mLast[2];
  end;
  if mLast.ChildCount = 3 then
  begin
    Inc(Result);
  end;
end;

/// <summary>Steht im Bereich von ANode eine Direktive?</summary>
function HasDirectiveIn(const ATokens: TTokens; ANode: TSyntaxNode): Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  mIndex := TokenFrom(ATokens, ANode.StartOffset);
  while not Result and (mIndex <= High(ATokens)) and (ATokens[mIndex].Offset < ANode.EndOffset) do
  begin
    Result := ATokens[mIndex].Kind = TPascalTokenKind.Directive;
    Inc(mIndex);
  end;
end;

procedure TPreferCaseRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mLookup: TIfCaseLookup;
  mLayout: TStatementLayout;
  mTokens: TTokens;
  mMin: Integer;

  procedure CheckHead(ANode: TSyntaxNode);
  var
    mBranches: Integer;
    mConversion: TIfCaseConversion;
    mFixes: TArray<TRuleFix>;
  begin
    if not TIfCase.IsChainHead(ANode) then
    begin
      Exit;
    end;
    mBranches := BranchCount(ANode, TIfCase.ConvertibleConditions(AContext.Text, AContext.Tree, ANode, mLookup));
    if (mBranches < mMin) or HasDirectiveIn(mTokens, ANode) then
    begin
      Exit;
    end;
    mFixes := nil;
    if TIfCase.ToCase(AContext.Text, AContext.Tree, ANode.StartPos, mLookup, mLayout, mConversion) then
    begin
      mFixes := [TRuleFix.Create(mConversion.Title, [mConversion.Edit])];
    end;
    AReport.Add(TTextRange.Create(ANode.StartPos, ANode[0].EndPos),
      cTexts[TIdiomsText.IfChain].Fmt([TStringIfChainRule.CountWord(mBranches)]), TRuleConfidence.High, mFixes);
  end;

var
  mResolver: TNameResolver;
  mCache: IRuleDerivedCache;
  mFileName: string;
  mNode: TSyntaxNode;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mMin := TRuleOptions.Int(AContext.Options, 'min', cDefaultMin);
  if mMin < 2 then
  begin
    mMin := cDefaultMin;
  end;
  mFileName := ResolverFileName(AContext);
  mTokens := AContext.Tree.Tokens;
  mLayout := TStatementLayout.Create('', '  ', TTextLines.LineBreakOf(AContext.Text));
  // Resolver des Laufs (TRuleDerived.Resolver); gehört dem Cache.
  mCache := TRuleDerived.Open(AContext);
  mResolver := TRuleDerived.Resolver(mCache, AContext);
  mResolver.PinTree(AContext.Tree, mFileName);
  try
    mLookup := TIfCaseLookup.FromResolver(mResolver, AContext.Tree, mFileName);
    for mNode in NodesOf(AContext.Tree.Root) do
    begin
      CheckHead(mNode);
    end;
  finally
    mResolver.UnpinTree;
  end;
end;

procedure RegisterIdiomRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TMoneyAsFloatRule.Create);
  ARegistry.Register(TStringIfChainRule.Create);
  ARegistry.Register(TPreferCaseRule.Create);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Idioms', cTexts);

end.
