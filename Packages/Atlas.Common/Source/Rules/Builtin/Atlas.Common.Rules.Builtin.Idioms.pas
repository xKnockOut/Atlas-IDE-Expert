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
//                    Standard aus, niedrige Konfidenz. Korrektur: Typ Currency,
//                    wenn alle Namen der Deklaration Geldbeträge sind; bei
//                    Parametern auch im Kopf der Implementierung, bei Feldern
//                    und Properties auch die Property bzw. das Feld hinter read
//                    und write (sonst E2010). Mit checkRound zusätzlich Round
//                    mit einem Geldbetrag im Argument (Banker's Rounding).

interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  MoneyAsFloatRuleId = 'money-as-float';

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
  end;

/// <summary>Registriert die Regeln für das passendere Sprachmittel.</summary>
procedure RegisterIdiomRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Character,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Rules.Options;

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
      Low := Middle + 1
    else
      High := Middle;
  end;
  Result := Low;
end;

procedure CollectNodes(ANode: TSyntaxNode; AList: TList<TSyntaxNode>);
var
  Index: Integer;
begin
  AList.Add(ANode);
  for Index := 0 to ANode.ChildCount - 1 do
    CollectNodes(ANode[Index], AList);
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
    Result := Result.Parent;
end;

/// <summary>Namen einer Deklaration "A,B" einzeln und ohne Leerraum.</summary>
function NamesOf(ANode: TSyntaxNode): TArray<string>;
var
  Name: string;
begin
  Result := nil;
  for Name in ANode.Name.Split([',']) do
    if Trim(Name) <> '' then
      Result := Result + [Trim(Name)];
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

function TMoneyAsFloatRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(MoneyAsFloatRuleId, TRuleSeverity.Hint, 'Geldbetrag als Gleitkommazahl', True);
end;

class function TMoneyAsFloatRule.HeadOf(const AName: string): string;
var
  Index, Start: Integer;
begin
  Start := 1;
  for Index := 2 to Length(AName) do
    if AName[Index - 1] = '_' then
      Start := Index
    else if AName[Index].IsUpper and (AName[Index - 1].IsLower or AName[Index - 1].IsDigit) then
      Start := Index
    // ABetrag, FNetto: der letzte Großbuchstabe einer Folge beginnt das nächste Wort.
    else if AName[Index].IsUpper and AName[Index - 1].IsUpper and (Index < Length(AName)) and
      AName[Index + 1].IsLower then
      Start := Index;
  Result := Copy(AName, Start, MaxInt);
  while (Result <> '') and (Result[Length(Result)] = '_') do
    Delete(Result, Length(Result), 1);
end;

class function TMoneyAsFloatRule.IsMoneyName(const AName: string; const APatterns: TArray<string>): Boolean;
var
  Head, Pattern, Ending, Word: string;
begin
  Head := HeadOf(AName);
  // Preis2, Betrag_1: Ziffern am Ende zählen nicht zum Wort.
  while (Head <> '') and Head[Length(Head)].IsDigit do
    Delete(Head, Length(Head), 1);
  for Word in RatioWords do
    if EndsText(Word, Head) then
      Exit(False);
  for Pattern in APatterns do
    if Trim(Pattern) <> '' then
      for Ending in PluralEndings do
        if EndsText(Trim(Pattern) + Ending, Head) then
          Exit(True);
  Result := False;
end;

procedure TMoneyAsFloatRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TTokens;
  Patterns: TArray<string>;
  Nodes: TArray<TSyntaxNode>;
  Declared: TDictionary<string, Boolean>;

  function IsFloat(ATypeRef: TSyntaxNode): Boolean;
  var
    Name: string;
  begin
    if (ATypeRef = nil) or (ATypeRef.ChildCount > 0) then
      Exit(False);
    Name := NodeText(AContext, ATypeRef);
    if StartsText('System.', Name) then
      Name := Copy(Name, Length('System.') + 1, MaxInt);
    Result := MatchText(Name, FloatTypes);
  end;

  function AllMoney(ANode: TSyntaxNode): Boolean;
  var
    Name: string;
  begin
    for Name in NamesOf(ANode) do
      if not IsMoneyName(Name, Patterns) then
        Exit(False);
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
        Exit(TTextRange.Create(Tokens[Index].StartPos, Tokens[Index].EndPos));
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
          Name := '?';
        if SameText(Tokens[Index].Text, 'read') then
          ARead := Name
        else
          AWrite := Name;
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
      if AType[Index].Kind = AKind then
        for Name in NamesOf(AType[Index]) do
          if SameText(Name, AName) then
            Exit(AType[Index]);
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
      Names := Names + [Read];
    if (Write <> '') and not SameText(Write, Read) then
      Names := Names + [Write];
    for Name in Names do
    begin
      if (Name = '?') or (Owner = nil) then
        Exit(False);
      Field := MemberOf(Owner, TSyntaxKind.Field, Name);
      if (Field = nil) or (Length(NamesOf(Field)) <> 1) or not IsFloat(Field.FindChild(TSyntaxKind.TypeReference)) then
        Exit(False);
      AEdits := AEdits + [CurrencyEdit(Field.FindChild(TSyntaxKind.TypeReference))];
    end;
    Result := True;
  end;

  // Feld: Properties, die es lesen oder schreiben, mit ändern.
  function FieldEdits(AField: TSyntaxNode; out AEdits: TArray<TRuleEdit>): Boolean;
  var
    Owner, Member: TSyntaxNode;
    Index: Integer;
    Read, Write: string;
  begin
    AEdits := [CurrencyEdit(AField.FindChild(TSyntaxKind.TypeReference))];
    Owner := AField.Parent;
    if Owner <> nil then
      for Index := 0 to Owner.ChildCount - 1 do
      begin
        Member := Owner[Index];
        if Member.Kind <> TSyntaxKind.PropertyDecl then
          Continue;
        Accessors(Member, Read, Write);
        if not SameText(Read, AField.Name) and not SameText(Write, AField.Name) then
          Continue;
        if not IsFloat(Member.FindChild(TSyntaxKind.TypeReference)) then
          Exit(False);
        // Der andere Zugriff ist eine Methode oder ein anderes Feld: nicht mit ändern.
        if ((Read <> '') and not SameText(Read, AField.Name)) or ((Write <> '') and not SameText(Write, AField.Name)) then
          Exit(False);
        AEdits := AEdits + [CurrencyEdit(Member.FindChild(TSyntaxKind.TypeReference))];
      end;
    Result := True;
  end;

  function ParametersOf(AHeader: TSyntaxNode): TArray<TSyntaxNode>;
  var
    List: TSyntaxNode;
    Index: Integer;
  begin
    Result := nil;
    List := AHeader.FindChild(TSyntaxKind.Parameters);
    if List <> nil then
      for Index := 0 to List.ChildCount - 1 do
        if List[Index].Kind = TSyntaxKind.Parameter then
          Result := Result + [List[Index]];
  end;

  // Kopf der Implementierung zu einer Deklaration AHeader (Methode im Typ oder Routine im interface).
  function ImplementationOf(AHeader: TSyntaxNode): TSyntaxNode;
  var
    TypeDecl, Node, Header: TSyntaxNode;
    Name: string;
    Own, Other: TArray<TSyntaxNode>;
    Index: Integer;
    Same: Boolean;
  begin
    Result := nil;
    Name := AHeader.Name;
    TypeDecl := AncestorOf(AHeader, TSyntaxKind.TypeDecl);
    if TypeDecl <> nil then
    begin
      if Pos('<', TypeDecl.Name) > 0 then
        Exit;
      Name := TypeDecl.Name + '.' + Name;
    end;
    Own := ParametersOf(AHeader);
    for Node in Nodes do
      if HasBody(Node) and SameText(Node.Name, Name) then
      begin
        Header := Node.FindChild(TSyntaxKind.RoutineHeader);
        if Header = nil then
          Continue;
        Other := ParametersOf(Header);
        // Ohne Parameterliste wiederholt die Implementierung nichts.
        if Other = nil then
          Exit(Header);
        Same := Length(Other) = Length(Own);
        for Index := 0 to High(Own) do
          if Same and not SameText(Own[Index].Name, Other[Index].Name) then
            Same := False;
        if Same then
          Exit(Header);
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
    // Prozeduraler Typ oder Routine nur mit Rumpf: eine Stelle.
    if (Header = nil) or HasBody(Header.Parent) then
      Exit(True);
    // Deklaration im Typ, im interface-Teil oder forward: auch der Kopf mit Rumpf.
    if (Header.Parent = nil) or ((Header.Parent.Kind <> TSyntaxKind.RoutineDecl) and
      (AncestorOf(Header, TSyntaxKind.TypeDecl) = nil)) then
      Exit(True);
    Implementation_ := ImplementationOf(Header);
    if Implementation_ = nil then
      Exit(False);
    Own := ParametersOf(Header);
    Other := ParametersOf(Implementation_);
    if Other = nil then
      Exit(True);
    for Index := 0 to High(Own) do
      if Own[Index] = AParameter then
      begin
        TypeRef := Other[Index].FindChild(TSyntaxKind.TypeReference);
        if not IsFloat(TypeRef) then
          Exit(False);
        AEdits := AEdits + [CurrencyEdit(TypeRef)];
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
      Exit;
    if (ANode.Kind = TSyntaxKind.Parameter) and RepeatsDeclaration(ANode) then
      Exit;
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
        Fixes := [TRuleFix.Create('Typ in Currency ändern', Edits)];
    end;
    for Name in NamesOf(ANode) do
      if IsMoneyName(Name, Patterns) then
        AReport.Add(NameRange(ANode, Name), Format('%s ist %s; Currency rechnet Cent-Beträge exakt.',
          [Name, NodeText(AContext, TypeRef)]), TRuleConfidence.Low, Fixes);
  end;

  // Round(Betrag * 100): Banker's Rounding auf einem Geldbetrag.
  procedure CheckRound(ACall: TSyntaxNode);
  var
    Index: Integer;
    Node: TSyntaxNode;
    List: TList<TSyntaxNode>;
  begin
    if (ACall[0].Kind <> TSyntaxKind.Identifier) or not SameText(ACall[0].Name, 'Round') then
      Exit;
    List := TList<TSyntaxNode>.Create;
    try
      for Index := 1 to ACall.ChildCount - 1 do
        CollectNodes(ACall[Index], List);
      for Node in List do
        if (Node.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) and
          not ((Node.Parent <> nil) and (Node.Parent.Kind = TSyntaxKind.Call) and (Node.Parent[0] = Node)) and
          IsMoneyName(Node.Name, Patterns) then
        begin
          AReport.Add(NodeRange(ACall[0]), Format('Round rundet %s auf die nächste gerade Zahl (2,5 wird 2); ' +
            'Geldbeträge kaufmännisch runden, z. B. mit SimpleRoundTo.', [Node.Name]), TRuleConfidence.Low);
          Exit;
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
    Exit;
  Defaults := nil;
  for Pattern in DefaultPatterns do
    Defaults := Defaults + [Pattern];
  Patterns := TRuleOptions.Strings(AContext.Options, 'namePatterns', Defaults);
  RoundCheck := TRuleOptions.Bool(AContext.Options, 'checkRound', False);
  Tokens := AContext.Tree.Tokens;
  Nodes := NodesOf(AContext.Tree.Root);
  Declared := TDictionary<string, Boolean>.Create;
  try
    // Routinen mit Deklaration im interface-Teil bzw. forward: Parameter dort prüfen.
    for Node in Nodes do
      if (Node.Kind = TSyntaxKind.RoutineDecl) and not HasBody(Node) and
        (AncestorOf(Node, TSyntaxKind.TypeDecl) = nil) then
        Declared.AddOrSetValue(LowerCase(Node.Name), True);
    for Node in Nodes do
      case Node.Kind of
        TSyntaxKind.Field, TSyntaxKind.VarDecl, TSyntaxKind.Parameter, TSyntaxKind.PropertyDecl,
        TSyntaxKind.InlineVar:
          CheckDeclaration(Node);
        TSyntaxKind.Call:
          if RoundCheck and (Node.ChildCount > 1) then
            CheckRound(Node);
      end;
  finally
    Declared.Free;
  end;
end;

procedure RegisterIdiomRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TMoneyAsFloatRule.Create);
end;

end.
