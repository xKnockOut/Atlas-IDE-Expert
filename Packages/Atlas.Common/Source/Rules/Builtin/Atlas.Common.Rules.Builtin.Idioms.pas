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
  MoneyAsFloatRuleId = 'money-as-float';
  StringIfChainRuleId = 'string-if-chain';
  PreferCaseRuleId = 'prefer-case';

type
  TMoneyAsFloatRule = class(TInterfacedObject, IRule)
  public const
    DefaultPatterns: array[0..7] of string = ('Betrag', 'Preis', 'Summe', 'Netto', 'Brutto', 'Steuer', 'Amount',
      'Price');
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Letzter Namensteil in CamelCase bzw. nach _: GesamtPreis → Preis, ABetrag → Betrag.</summary>
    class function HeadOf(const AName: string): string; static;
    /// <summary>AName bezeichnet nach APatterns einen Geldbetrag (Mehrzahl eingeschlossen, Sätze ausgenommen).</summary>
    class function IsMoneyName(const AName: string; const APatterns: TArray<string>): Boolean; static;
    /// <summary>AName ist nur über ein mehrdeutiges Muster (Amount, Summe, Sum, Total) ein Geldname.</summary>
    class function IsAmbiguousName(const AName: string; const APatterns: TArray<string>): Boolean; static;
  end;

  TStringIfChainRule = class(TInterfacedObject, IRule)
  public const
    DefaultMin = 4;
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Zahlwort mit großem Anfangsbuchstaben bis zwölf, darüber Ziffern.</summary>
    class function CountWord(ACount: Integer): string; static;
  end;

  TPreferCaseRule = class(TInterfacedObject, IRule)
  public const
    DefaultMin = 4;
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

/// <summary>Registriert die Regeln für das passendere Sprachmittel.</summary>
procedure RegisterIdiomRules(const ARegistry: TRuleRegistry);

implementation

uses
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

/// <summary>Index des ersten Tokens ab AOffset (binäre Suche); Length(ATokens), wenn keiner folgt.</summary>
function TokenAt(const ATokens: TTokens; AOffset: Integer): Integer;
var
  Low, High, Middle: Integer;
begin
  Low := 0;
  High := Length(ATokens);
  while Low < High do
  begin
    Middle := (Low + High) div 2;
    if ATokens[Middle].Offset < AOffset then
    begin
      Low := Middle + 1;
    end
    else
    begin
      High := Middle;
    end;
  end;
  Result := Low;
end;

// Iterativ (Bericht M1).
procedure CollectNodes(ARoot: TSyntaxNode; AList: TList<TSyntaxNode>);
var
  Pending: TStack<TSyntaxNode>;
  Node: TSyntaxNode;
  Index: Integer;
begin
  Pending := TStack<TSyntaxNode>.Create;
  try
    Pending.Push(ARoot);
    while Pending.Count > 0 do
    begin
      Node := Pending.Pop;
      AList.Add(Node);
      for Index := Node.ChildCount - 1 downto 0 do
      begin
        Pending.Push(Node[Index]);
      end;
    end;
  finally
    Pending.Free;
  end;
end;

/// <summary>ARoot und alle Nachfahren in Dokumentreihenfolge.</summary>
function NodesOf(ARoot: TSyntaxNode): TArray<TSyntaxNode>;
var
  List: TList<TSyntaxNode>;
begin
  List := TList<TSyntaxNode>.Create;
  try
    CollectNodes(ARoot, List);
    Result := List.ToArray;
  finally
    List.Free;
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
  Name: string;
begin
  Result := nil;
  for Name in ANode.Name.Split([',']) do
  begin
    if Trim(Name) <> '' then
    begin
      Result := Result + [Trim(Name)];
    end;
  end;
end;

{ TMoneyAsFloatRule }

const
  FloatTypes: array[0..3] of string = ('Double', 'Single', 'Extended', 'Real');
  // Mehrzahl und Fugen: Preise, Summen, Steuern, Amounts.
  PluralEndings: array[0..6] of string = ('', 'e', 'n', 'en', 's', 'es', 'er');
  // Verhältnisse und Prüfsummen sind keine Beträge, auch wenn ein Geldwort davorsteht.
  RatioWords: array[0..21] of string = ('Satz', 'Saetze', 'Sätze', 'Faktor', 'Faktoren', 'Rate', 'Raten', 'Rates',
    'Quote', 'Quoten', 'Prozent', 'Anteil', 'Anteile', 'Percent', 'Percentage', 'Ratio', 'Ratios', 'Factor',
    'Factors', 'Pruefsumme', 'Prüfsumme', 'Quersumme');
  // Muster, die auch Mengen und Summen beliebiger Werte bezeichnen (Farbanteil, Messwerte).
  AmbiguousWords: array[0..3] of string = ('Amount', 'Summe', 'Sum', 'Total');
  // Wörter, die einen Geldbezug herstellen.
  MoneyContextWords: array[0..30] of string = ('Cent', 'Euro', 'EUR', 'USD', 'Dollar', 'Waehrung', 'Währung',
    'Currency', 'Rabatt', 'Discount', 'Rechnung', 'Invoice', 'Zahlung', 'Payment', 'Kosten', 'Cost', 'Gebuehr',
    'Gebühr', 'Fee', 'Saldo', 'Balance', 'Lohn', 'Gehalt', 'Salary', 'Kasse', 'MwSt', 'Mehrwertsteuer', 'Tax',
    'Konto', 'Umsatz', 'Revenue');

function TMoneyAsFloatRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(MoneyAsFloatRuleId, TRuleSeverity.Hint, cTexts[TIdiomsText.MoneyFloatTitle].Text,
    True);
end;

class function TMoneyAsFloatRule.HeadOf(const AName: string): string;
var
  Index, Start: Integer;
begin
  Start := 1;
  for Index := 2 to Length(AName) do
  begin
    if AName[Index - 1] = '_' then
    begin
      Start := Index;
    end
    else if AName[Index].IsUpper and (AName[Index - 1].IsLower or AName[Index - 1].IsDigit) then
    begin
      Start := Index;
    end
    // ABetrag, FNetto: der letzte Großbuchstabe einer Folge beginnt das nächste Wort.
    else if AName[Index].IsUpper and AName[Index - 1].IsUpper and (Index < Length(AName)) and
      AName[Index + 1].IsLower then
    begin
      Start := Index;
    end;
  end;
  Result := Copy(AName, Start, MaxInt);
  while (Result <> '') and (Result[Length(Result)] = '_') do
  begin
    Delete(Result, Length(Result), 1);
  end;
end;

class function TMoneyAsFloatRule.IsMoneyName(const AName: string; const APatterns: TArray<string>): Boolean;
var
  Head, Pattern, Ending, Word: string;
begin
  Head := HeadOf(AName);
  // Preis2, Betrag_1: Ziffern am Ende zählen nicht zum Wort.
  while (Head <> '') and Head[Length(Head)].IsDigit do
  begin
    Delete(Head, Length(Head), 1);
  end;
  for Word in RatioWords do
  begin
    if EndsText(Word, Head) then
    begin
      Exit(False);
    end;
  end;
  for Pattern in APatterns do
  begin
    if Trim(Pattern) <> '' then
    begin
      for Ending in PluralEndings do
      begin
        if EndsText(Trim(Pattern) + Ending, Head) then
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
  Pattern: string;
begin
  Result := nil;
  for Pattern in APatterns do
  begin
    if not MatchText(Trim(Pattern), AmbiguousWords) then
    begin
      Result := Result + [Pattern];
    end;
  end;
end;

class function TMoneyAsFloatRule.IsAmbiguousName(const AName: string; const APatterns: TArray<string>): Boolean;
begin
  Result := IsMoneyName(AName, APatterns) and not IsMoneyName(AName, UnambiguousPatterns(APatterns));
end;

procedure TMoneyAsFloatRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TTokens;
  Patterns: TArray<string>;
  Nodes: TArray<TSyntaxNode>;
  Declared: TDictionary<string, Boolean>;
  ContextPatterns: TArray<string>;

  // Geldbezug im Typ bzw. in der Routine um ANode: ein anderer Geldname, Currency oder ein Geldwort.
  function HasMoneyContext(ANode: TSyntaxNode; const AName: string): Boolean;
  var
    Scope: TSyntaxNode;
    Index: Integer;
  begin
    Scope := AncestorOf(ANode, TSyntaxKind.TypeDecl);
    if Scope = nil then
    begin
      Scope := AncestorOf(ANode, TSyntaxKind.RoutineDecl);
    end;
    if Scope = nil then
    begin
      Scope := AContext.Tree.Root;
    end;
    Index := TokenAt(Tokens, Scope.StartOffset);
    while (Index <= High(Tokens)) and (Tokens[Index].Offset < Scope.EndOffset) do
    begin
      if (Tokens[Index].Kind = TPascalTokenKind.Identifier) and not SameText(Tokens[Index].Text, AName) and
        IsMoneyName(Tokens[Index].Text, ContextPatterns) then
      begin
        Exit(True);
      end;
      Inc(Index);
    end;
    Result := False;
  end;

  function IsMoney(ANode: TSyntaxNode; const AName: string): Boolean;
  begin
    Result := IsMoneyName(AName, Patterns) and
      (not IsAmbiguousName(AName, Patterns) or HasMoneyContext(ANode, AName));
  end;

  function IsFloat(ATypeRef: TSyntaxNode): Boolean;
  var
    Name: string;
  begin
    if (ATypeRef = nil) or (ATypeRef.ChildCount > 0) then
    begin
      Exit(False);
    end;
    Name := NodeText(AContext, ATypeRef);
    if StartsText('System.', Name) then
    begin
      Name := Copy(Name, Length('System.') + 1, MaxInt);
    end;
    Result := MatchText(Name, FloatTypes);
  end;

  function AllMoney(ANode: TSyntaxNode): Boolean;
  var
    Name: string;
  begin
    for Name in NamesOf(ANode) do
    begin
      if not IsMoney(ANode, Name) then
      begin
        Exit(False);
      end;
    end;
    Result := True;
  end;

  // Token des Namens AName innerhalb von ANode.
  function NameRange(ANode: TSyntaxNode; const AName: string): TTextRange;
  var
    Index: Integer;
  begin
    Index := TokenAt(Tokens, ANode.StartOffset);
    while (Index <= High(Tokens)) and (Tokens[Index].Offset < ANode.EndOffset) do
    begin
      if (Tokens[Index].Kind = TPascalTokenKind.Identifier) and SameText(Tokens[Index].Text, AName) then
      begin
        Exit(TTextRange.Create(Tokens[Index].StartPos, Tokens[Index].EndPos));
      end;
      Inc(Index);
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
    Index: Integer;
    Name: string;
  begin
    ARead := '';
    AWrite := '';
    Index := TokenAt(Tokens, AProperty.StartOffset);
    while (Index < High(Tokens)) and (Tokens[Index].Offset < AProperty.EndOffset) do
    begin
      if MatchText(Tokens[Index].Text, ['read', 'write']) and (Tokens[Index + 1].Kind = TPascalTokenKind.Identifier) then
      begin
        Name := Tokens[Index + 1].Text;
        if (Index + 2 <= High(Tokens)) and (Tokens[Index + 2].Text = '.') then
        begin
          Name := '?';
        end;
        if SameText(Tokens[Index].Text, 'read') then
        begin
          ARead := Name;
        end
        else
        begin
          AWrite := Name;
        end;
      end;
      Inc(Index);
    end;
  end;

  function MemberOf(AType: TSyntaxNode; AKind: TSyntaxKind; const AName: string): TSyntaxNode;
  var
    Index: Integer;
    Name: string;
  begin
    for Index := 0 to AType.ChildCount - 1 do
    begin
      if AType[Index].Kind = AKind then
      begin
        for Name in NamesOf(AType[Index]) do
        begin
          if SameText(Name, AName) then
          begin
            Exit(AType[Index]);
          end;
        end;
      end;
    end;
    Result := nil;
  end;

  // Property: Felder hinter read und write mit ändern; Getter und Setter müssten mitwandern.
  function PropertyEdits(AProperty: TSyntaxNode; out AEdits: TArray<TRuleEdit>): Boolean;
  var
    Owner, Field: TSyntaxNode;
    Read, Write, Name: string;
    Names: TArray<string>;
  begin
    AEdits := [CurrencyEdit(AProperty.FindChild(TSyntaxKind.TypeReference))];
    Owner := AProperty.Parent;
    Accessors(AProperty, Read, Write);
    Names := nil;
    if Read <> '' then
    begin
      Names := Names + [Read];
    end;
    if (Write <> '') and not SameText(Write, Read) then
    begin
      Names := Names + [Write];
    end;
    for Name in Names do
    begin
      if (Name = '?') or (Owner = nil) then
      begin
        Exit(False);
      end;
      Field := MemberOf(Owner, TSyntaxKind.Field, Name);
      if (Field = nil) or (Length(NamesOf(Field)) <> 1) or not IsFloat(Field.FindChild(TSyntaxKind.TypeReference)) then
      begin
        Exit(False);
      end;
      AEdits := AEdits + [CurrencyEdit(Field.FindChild(TSyntaxKind.TypeReference))];
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
    List: TSyntaxNode;
    Index: Integer;
  begin
    Result := nil;
    List := AHeader.FindChild(TSyntaxKind.Parameters);
    if List <> nil then
    begin
      for Index := 0 to List.ChildCount - 1 do
      begin
        if List[Index].Kind = TSyntaxKind.Parameter then
        begin
          Result := Result + [List[Index]];
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
    for mNode in Nodes do
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
    Header, Implementation_: TSyntaxNode;
    Index: Integer;
    Own, Other: TArray<TSyntaxNode>;
    TypeRef: TSyntaxNode;
  begin
    AEdits := [CurrencyEdit(AParameter.FindChild(TSyntaxKind.TypeReference))];
    Header := AncestorOf(AParameter, TSyntaxKind.RoutineHeader);
    // Prozeduraler Typ oder Routine nur mit Rumpf: eine Stelle. Deklaration im Typ, im interface-Teil oder
    // forward: auch der Kopf mit Rumpf.
    if (Header = nil) or HasBody(Header.Parent) or (Header.Parent = nil) or
      ((Header.Parent.Kind <> TSyntaxKind.RoutineDecl) and (AncestorOf(Header, TSyntaxKind.TypeDecl) = nil)) then
    begin
      Exit(True);
    end;
    Implementation_ := ImplementationOf(Header);
    if Implementation_ = nil then
    begin
      Exit(False);
    end;
    Own := ParametersOf(Header);
    Other := ParametersOf(Implementation_);
    if Other = nil then
    begin
      Exit(True);
    end;
    for Index := 0 to High(Own) do
    begin
      if Own[Index] = AParameter then
      begin
        TypeRef := Other[Index].FindChild(TSyntaxKind.TypeReference);
        if not IsFloat(TypeRef) then
        begin
          Exit(False);
        end;
        AEdits := AEdits + [CurrencyEdit(TypeRef)];
      end;
    end;
    Result := True;
  end;

  // Parameter der Implementierung, deren Deklaration schon geprüft wird.
  function RepeatsDeclaration(AParameter: TSyntaxNode): Boolean;
  var
    Header: TSyntaxNode;
  begin
    Header := AncestorOf(AParameter, TSyntaxKind.RoutineHeader);
    Result := (Header <> nil) and HasBody(Header.Parent) and
      ((Pos('.', Header.Name) > 0) or Declared.ContainsKey(LowerCase(Header.Name)));
  end;

  procedure CheckDeclaration(ANode: TSyntaxNode);
  var
    TypeRef: TSyntaxNode;
    Name: string;
    Fixes: TArray<TRuleFix>;
    Edits: TArray<TRuleEdit>;
    Fixable: Boolean;
  begin
    TypeRef := ANode.FindChild(TSyntaxKind.TypeReference);
    if not IsFloat(TypeRef) then
    begin
      Exit;
    end;
    if (ANode.Kind = TSyntaxKind.Parameter) and RepeatsDeclaration(ANode) then
    begin
      Exit;
    end;
    Fixes := nil;
    if AllMoney(ANode) then
    begin
      case ANode.Kind of
        TSyntaxKind.Parameter:
          Fixable := ParameterEdits(ANode, Edits);
        TSyntaxKind.PropertyDecl:
          Fixable := PropertyEdits(ANode, Edits);
        TSyntaxKind.Field:
          Fixable := FieldEdits(ANode, Edits);
      else
        begin
          Edits := [CurrencyEdit(TypeRef)];
          Fixable := True;
        end;
      end;
      if Fixable then
      begin
        Fixes := [TRuleFix.Create(cTexts[TIdiomsText.ChangeToCurrency].Text, Edits)];
      end;
    end;
    for Name in NamesOf(ANode) do
    begin
      if IsMoney(ANode, Name) then
      begin
        AReport.Add(NameRange(ANode, Name), cTexts[TIdiomsText.MoneyFloat].Fmt(
          [Name, NodeText(AContext, TypeRef)]), TRuleConfidence.Low, Fixes);
      end;
    end;
  end;

  // Round(Betrag * 100): Banker's Rounding auf einem Geldbetrag.
  procedure CheckRound(ACall: TSyntaxNode);
  var
    Index: Integer;
    Node: TSyntaxNode;
    List: TList<TSyntaxNode>;
  begin
    if (ACall[0].Kind <> TSyntaxKind.Identifier) or not SameText(ACall[0].Name, 'Round') then
    begin
      Exit;
    end;
    List := TList<TSyntaxNode>.Create;
    try
      for Index := 1 to ACall.ChildCount - 1 do
      begin
        CollectNodes(ACall[Index], List);
      end;
      for Node in List do
      begin
        if (Node.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) and
          not ((Node.Parent <> nil) and (Node.Parent.Kind = TSyntaxKind.Call) and (Node.Parent[0] = Node)) and
          IsMoney(Node, Node.Name) then
        begin
          AReport.Add(NodeRange(ACall[0]), cTexts[TIdiomsText.BankersRounding].Fmt([Node.Name]), TRuleConfidence.Low);
          Exit;
        end;
      end;
    finally
      List.Free;
    end;
  end;

var
  Node: TSyntaxNode;
  Defaults: TArray<string>;
  Pattern: string;
  RoundCheck: Boolean;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  Defaults := nil;
  for Pattern in DefaultPatterns do
  begin
    Defaults := Defaults + [Pattern];
  end;
  Patterns := TRuleOptions.Strings(AContext.Options, 'namePatterns', Defaults);
  ContextPatterns := UnambiguousPatterns(Patterns);
  for Pattern in MoneyContextWords do
  begin
    ContextPatterns := ContextPatterns + [Pattern];
  end;
  RoundCheck := TRuleOptions.Bool(AContext.Options, 'checkRound', False);
  Tokens := AContext.Tree.Tokens;
  Nodes := NodesOf(AContext.Tree.Root);
  Declared := TDictionary<string, Boolean>.Create;
  try
    // Routinen mit Deklaration im interface-Teil bzw. forward: Parameter dort prüfen.
    for Node in Nodes do
    begin
      if (Node.Kind = TSyntaxKind.RoutineDecl) and not HasBody(Node) and
        (AncestorOf(Node, TSyntaxKind.TypeDecl) = nil) then
      begin
        Declared.AddOrSetValue(LowerCase(Node.Name), True);
      end;
    end;
    for Node in Nodes do
      case Node.Kind of
        TSyntaxKind.Field, TSyntaxKind.VarDecl, TSyntaxKind.Parameter, TSyntaxKind.PropertyDecl,
        TSyntaxKind.InlineVar:
          CheckDeclaration(Node);
        TSyntaxKind.Call:
          if RoundCheck and (Node.ChildCount > 1) then
          begin
            CheckRound(Node);
          end;
      else
        // Übrige Werte bewusst ohne Wirkung.
      end;
  finally
    Declared.Free;
  end;
end;

{ TStringIfChainRule }

const
  CountWords: array[2..12] of TIdiomsText = (TIdiomsText.Two, TIdiomsText.Three, TIdiomsText.Four, TIdiomsText.Five,
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
  Result := TRuleDescriptor.Create(StringIfChainRuleId, TRuleSeverity.Hint, cTexts[TIdiomsText.StringIfChainTitle].Text,
    True);
end;

class function TStringIfChainRule.CountWord(ACount: Integer): string;
begin
  if (ACount >= Low(CountWords)) and (ACount <= High(CountWords)) then
  begin
    Result := cTexts[CountWords[ACount]].Text;
  end
  else
  begin
    Result := IntToStr(ACount);
  end;
end;

function UsesEdit(const AContext: TRuleContext; const ATokens: TTokens; AOffset: Integer;
  const AUnitName: string; out AEdit: TTextEdit): Boolean;
var
  Used: TArray<string>;
  Short: string;
begin
  Used := TUsesClauses.UsedUnits(ATokens);
  Short := Copy(AUnitName, LastDelimiter('.', AUnitName) + 1, MaxInt);
  if TUsesClauses.IsUsed(Used, AUnitName, AContext.Namespaces) or TUsesClauses.IsUsed(Used, Short, nil) then
  begin
    Exit(False);
  end;
  Result := TUsesClauses.AddUnit(ATokens, AOffset, AUnitName, TTextLines.LineBreakOf(AContext.Text), AEdit);
end;

/// <summary>Nur Bezeichner und Punkte: S, Self.FBefehl, Edit1.Text. Iterativ (Bericht M1).</summary>
function IsSubject(ANode: TSyntaxNode): Boolean;
var
  Node: TSyntaxNode;
begin
  Node := ANode;
  while (Node.Kind = TSyntaxKind.MemberAccess) and (Node.ChildCount = 1) do
  begin
    Node := Node[0];
  end;
  Result := Node.Kind = TSyntaxKind.Identifier;
end;

function IsStringLiteral(const AContext: TRuleContext; ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.Literal) and StartsStr('''', NodeText(AContext, ANode));
end;

procedure TStringIfChainRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TTokens;
  Paths: TArray<string>;
  LineBreak: string;
  Lines: TArray<string>;

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
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
  begin
    Result := False;
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ACondition);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if Node.Kind = TSyntaxKind.ParenExpr then
        begin
          if Node.ChildCount <> 1 then
          begin
            Exit;
          end;
          Pending.Push(Node[0]);
        end
        else if (Node.Kind = TSyntaxKind.BinaryExpr) and SameText(Node.Name, 'or') and (Node.ChildCount = 2) then
        begin
          Pending.Push(Node[1]);
          Pending.Push(Node[0]);
        end
        else if not Comparison(Node, ASubject, ALiterals, ASensitive) then
        begin
          Exit;
        end;
      end;
    finally
      Pending.Free;
    end;
    Result := True;
  end;

  function SubjectOf(AIf: TSyntaxNode): string;
  var
    Literals: TArray<string>;
    Sensitive: Integer;
  begin
    Result := '';
    Literals := nil;
    Sensitive := 0;
    if (AIf.Kind <> TSyntaxKind.IfStatement) or (AIf.ChildCount < 2) or
      not Comparisons(AIf[0], Result, Literals, Sensitive) then
    begin
      Result := '';
    end;
  end;

  function PathOf(ANode: TSyntaxNode): string;
  begin
    Result := TConditionalBranches.PathAt(Paths, TokenAt(Tokens, ANode.StartOffset));
  end;

  function LineOf(ALine: Integer): string;
  begin
    Result := '';
    if (ALine >= 0) and (ALine <= High(Lines)) then
    begin
      Result := Lines[ALine];
    end;
  end;

  // Text von ANode, Folgezeilen um die Einrückung seiner ersten Zeile auf AIndent verschoben.
  function Reindented(ANode: TSyntaxNode; const AIndent: string): string;
  var
    Parts: TArray<string>;
    Base, Index: Integer;
    Line: string;
  begin
    Parts := NodeText(AContext, ANode).Replace(#13#10, #10).Split([#10]);
    Base := Length(TTextLines.IndentOf(LineOf(ANode.StartPos.Line)));
    Result := AIndent + Parts[0];
    for Index := 1 to High(Parts) do
    begin
      Line := Parts[Index];
      if Length(TTextLines.IndentOf(Line)) >= Base then
      begin
        Line := Copy(Line, Base + 1, MaxInt);
      end
      else
      begin
        Line := TrimLeft(Line);
      end;
      Result := Result + LineBreak + AIndent + Line;
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
    mIndex := TokenAt(Tokens, AHead.StartOffset);
    while Result and (mIndex <= High(Tokens)) and (Tokens[mIndex].Offset < AHead.EndOffset) do
    begin
      Result := (Tokens[mIndex].Kind <> TPascalTokenKind.Directive) and
        ((Tokens[mIndex].Kind <> TPascalTokenKind.Comment) or InBranches(Tokens[mIndex].Offset, ABranches, AElse));
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
      Result := LineBreak + AIndent + '  ' + mLabels + ': ' + NodeText(AContext, ABranch.Statement) + ';';
    end
    else
    begin
      Result := LineBreak + AIndent + '  ' + mLabels + ':' + LineBreak +
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
      mText := mText + LineBreak + mIndent + 'else' + LineBreak + Reindented(AElse, mIndent + '  ') + ';';
    end;
    mText := mText + LineBreak + mIndent + 'end';
    mEdits := [TRuleEdit.Create(NodeRange(AHead), mText)];
    if UsesEdit(AContext, Tokens, AHead.StartOffset, 'System.StrUtils', mExtra) then
    begin
      mEdits := mEdits + [mExtra];
    end;
    AFix := TRuleFix.Create(cTexts[TIdiomsText.ConvertToCase].Fmt([mFunction]), mEdits);
  end;

  procedure CheckChain(AHead: TSyntaxNode; AMin: Integer);
  var
    Subject, HeadPath: string;
    Current: TSyntaxNode;
    Branches: TArray<TChainBranch>;
    Branch: TChainBranch;
    Sensitive, Count: Integer;
    SamePath: Boolean;
    Fixes: TArray<TRuleFix>;
    One: TRuleFix;
  begin
    Subject := '';
    Sensitive := 0;
    Branches := nil;
    Current := AHead;
    HeadPath := PathOf(AHead);
    Count := 0;
    SamePath := True;
    while (Current <> nil) and (Current.Kind = TSyntaxKind.IfStatement) and (Current.ChildCount >= 2) do
    begin
      Branch := Default(TChainBranch);
      Branch.Condition := Current[0];
      if not Comparisons(Current[0], Subject, Branch.Literals, Sensitive) then
      begin
        Break;
      end;
      Branch.Statement := Current[1];
      Branches := Branches + [Branch];
      // Nur Vergleiche, die immer mit dem Kopf übersetzt werden.
      if TConditionalBranches.Implies(HeadPath, PathOf(Current[0])) then
      begin
        Inc(Count, Length(Branch.Literals));
      end;
      if PathOf(Current[0]) <> HeadPath then
      begin
        SamePath := False;
      end;
      if Current.ChildCount > 2 then
      begin
        Current := Current[2];
      end
      else
      begin
        Current := nil;
      end;
    end;
    // Ein einzelnes if mit or ist keine Kette (dafür MatchStr).
    if (Count < AMin) or (Length(Branches) < 2) then
    begin
      Exit;
    end;
    Fixes := nil;
    if SamePath and (Sensitive <> 3) and Fix(AHead, Subject, Branches, Current, Sensitive = 1, One) then
    begin
      Fixes := [One];
    end;
    AReport.Add(TTextRange.Create(AHead.StartPos, AHead[0].EndPos),
      cTexts[TIdiomsText.StringIfChain].Fmt([CountWord(Count),
      IfThen(Sensitive = 2, 'IndexText', 'IndexStr'), Subject]), TRuleConfidence.High, Fixes);
  end;

  // Fortsetzung einer Kette über denselben String: der Kopf meldet sie.
  function ContinuesChain(ANode: TSyntaxNode): Boolean;
  begin
    Result := (ANode.Parent <> nil) and (ANode.Parent.Kind = TSyntaxKind.IfStatement) and
      (ANode.Parent.ChildCount > 2) and (ANode.Parent[2] = ANode);
    Result := Result and (SubjectOf(ANode) <> '') and SameText(SubjectOf(ANode.Parent), SubjectOf(ANode));
  end;

var
  Node: TSyntaxNode;
  Min: Integer;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  Min := TRuleOptions.Int(AContext.Options, 'min', DefaultMin);
  if Min < 2 then
  begin
    Min := DefaultMin;
  end;
  Tokens := AContext.Tree.Tokens;
  Paths := TConditionalBranches.Paths(Tokens);
  LineBreak := TTextLines.LineBreakOf(AContext.Text);
  Lines := TTextLines.SplitLines(AContext.Text);
  for Node in NodesOf(AContext.Tree.Root) do
  begin
    if (Node.Kind = TSyntaxKind.IfStatement) and (Node.ChildCount >= 2) then
    begin
      if not ContinuesChain(Node) and (SubjectOf(Node) <> '') then
      begin
        CheckChain(Node, Min);
      end;
    end;
  end;
end;

{ TPreferCaseRule }

function TPreferCaseRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(PreferCaseRuleId, TRuleSeverity.Hint, cTexts[TIdiomsText.IfChainTitle].Text,
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
  mIndex := TokenAt(ATokens, ANode.StartOffset);
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
  mMin := TRuleOptions.Int(AContext.Options, 'min', DefaultMin);
  if mMin < 2 then
  begin
    mMin := DefaultMin;
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
