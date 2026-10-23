unit Atlas.Common.Lsp.CompletionAttributes;

// Attribute nach "[" (#465, ARG-066): Steht der Cursor auf dem Namen in einer Attributklammer vor einer
// Deklaration (TAttributes.InBracket), bleiben nur Attributklassen (Nachfahren von TCustomAttribute,
// TNameResolver.AttributeClassOf), gezeigt ohne die Endung Attribute.
// - Bekannte Attribute zuerst, in dieser Reihenfolge: DUnitX (Test, TestCase, TestFixture, Setup, TearDown),
//   JSONName, JSONMarshalled und die Compiler-Attribute weak, unsafe, volatile, Ref; die übrigen danach wie
//   gesammelt. Die Compiler-Attribute haben keine Klasse und kommen immer dazu, wenn sie zum Getippten passen.
// - Detail: Parameter des Konstruktors ("(const AName: string)"), ohne eigenen Konstruktor die Unit.
// - Aus einer nicht eingebundenen Unit mit uses-Eintrag (#180); dieselbe Klasse über mehrere Units (DUnitX
//   reicht TestAttribute aus DUnitX.Attributes über einen Alias in DUnitX.TestFramework weiter) nur einmal:
//   eingebunden vor Alias vor Original.
// - Abschaltbar mit completion.attributes; dann gilt die gewöhnliche Liste.

interface

uses
  System.SysUtils,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.CompletionRequest,
  Atlas.Common.Lsp.CompletionCollector;

type
  TCompletionAttributes = class
  public const
    /// <summary>Bekannte Attribute in der Reihenfolge der Liste; die Klassen heißen NameAttribute.</summary>
    KnownNames: array[0..6] of string = ('Test', 'TestCase', 'TestFixture', 'Setup', 'TearDown', 'JSONName',
      'JSONMarshalled');
    /// <summary>Attribute, die der Compiler selbst kennt.</summary>
    CompilerNames: array[0..3] of string = ('weak', 'unsafe', 'volatile', 'Ref');
  public
    /// <summary>Klassennamen der bekannten Attribute (TestAttribute …), für den uses-Eintrag schon ohne Eingabe.
    /// </summary>
    class function KnownClassNames: TArray<string>; static;
    /// <summary>Steht der Name hinter dem Token ALast in einer Attributklammer?</summary>
    class function SiteAt(const ATokens: TArray<TPascalToken>; ALast: Integer): Boolean; static;
    /// <summary>Vorfilter für den Sammler: nur Attributklassen (vor dem Kürzen auf die Höchstzahl).</summary>
    class function Admit(AResolver: TNameResolver): TCompletionAdmitFunc; static;
    /// <summary>Parameterliste aus einem Kopf ("constructor Create(const A: string);" → "(const A: string)");
    /// '' ohne Klammern.</summary>
    class function ParameterText(const ASignature: string): string; static;
    /// <summary>Nur Attributklassen, umbenannt und sortiert (siehe oben), dazu die Compiler-Attribute.</summary>
    class function Apply(ARequest: TCompletionRequest; const AContext: TCompletionContext;
      const AItems: TArray<TCompletionItem>): TArray<TCompletionItem>; static;
  end;

implementation

uses
  System.StrUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.Attributes,
  Atlas.Common.Lsp.FuzzyMatch,
  Atlas.Common.Lsp.CompletionGenerics;

{ TCompletionAttributes }

class function TCompletionAttributes.KnownClassNames: TArray<string>;
var
  Name: string;
begin
  Result := nil;
  for Name in KnownNames do
    Result := Result + [Name + 'Attribute'];
end;

class function TCompletionAttributes.SiteAt(const ATokens: TArray<TPascalToken>; ALast: Integer): Boolean;
begin
  Result := TAttributes.InBracket(ATokens, ALast);
end;

class function TCompletionAttributes.Admit(AResolver: TNameResolver): TCompletionAdmitFunc;
begin
  Result :=
    function(const ASymbol: TResolvedSymbol): Boolean
    var
      AttributeClass: TResolvedSymbol;
    begin
      Result := AResolver.AttributeClassOf(ASymbol, AttributeClass);
    end;
end;

class function TCompletionAttributes.ParameterText(const ASignature: string): string;
var
  Open, Index, Depth: Integer;
begin
  Result := '';
  Open := Pos('(', ASignature);
  if Open = 0 then
    Exit;
  Depth := 0;
  for Index := Open to Length(ASignature) do
    if ASignature[Index] = '(' then
      Inc(Depth)
    else if ASignature[Index] = ')' then
    begin
      Dec(Depth);
      if Depth = 0 then
        Exit(Copy(ASignature, Open, Index - Open + 1));
    end;
end;

/// <summary>Rang eines bekannten Attributs (0 …), -1 sonst.</summary>
function KnownRank(const AName: string): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(TCompletionAttributes.KnownNames) do
    if SameText(AName, TCompletionAttributes.KnownNames[Index]) then
      Exit(Index);
  for Index := 0 to High(TCompletionAttributes.CompilerNames) do
    if SameText(AName, TCompletionAttributes.CompilerNames[Index]) then
      Exit(Length(TCompletionAttributes.KnownNames) + Index);
  Result := -1;
end;

type
  TAttributeEntry = record
    Item: TCompletionItem;
    /// <summary>Klasse nach Aliasen, für doppelte Einträge.</summary>
    Key: string;
    /// <summary>Kleiner ist besser: 0 eingebunden, 1 Alias aus anderer Unit, 2 Original aus anderer Unit.</summary>
    Preference: Integer;
    Rank: Integer;
    Order: Integer;
  end;

class function TCompletionAttributes.Apply(ARequest: TCompletionRequest; const AContext: TCompletionContext;
  const AItems: TArray<TCompletionItem>): TArray<TCompletionItem>;
var
  Units: TDictionary<string, TUnitIndex>;
  ByKey: TDictionary<string, Integer>;
  Entries: TList<TAttributeEntry>;
  Item: TCompletionItem;
  Entry: TAttributeEntry;
  Symbol, AttributeClass, Ctor: TResolvedSymbol;
  Name, Params: string;
  Existing, Index, Order: Integer;
  Sorted: TArray<TAttributeEntry>;
begin
  Units := TDictionary<string, TUnitIndex>.Create;
  ByKey := TDictionary<string, Integer>.Create;
  Entries := TList<TAttributeEntry>.Create;
  try
    Order := 0;
    for Item in AItems do
    begin
      if not TCompletionGenerics.ItemSymbol(ARequest, Units, Item, Symbol) or
        not ARequest.Resolver.AttributeClassOf(Symbol, AttributeClass) then
        Continue;
      Name := TAttributes.ShortName(Item.Name);
      if MatchScore(Name, AContext.Prefix, ARequest.Matching) = TFuzzyMatch.NoMatch then
        Continue;
      Entry := Default(TAttributeEntry);
      Entry.Item := Item;
      Entry.Item.Name := Name;
      Entry.Item.FilterText := Name;
      Entry.Item.InsertText := Name;
      Entry.Item.Attribute := True;
      Params := '';
      if ARequest.Resolver.DeclaredMember(AttributeClass, 'Create', Ctor) and
        not SameText(Ctor.Container, 'TCustomAttribute') and not SameText(Ctor.Container, 'TObject') then
        Params := ParameterText(Ctor.Signature);
      if Params <> '' then
        Entry.Item.Detail := Params
      else
        Entry.Item.Detail := AttributeClass.UnitName;
      Entry.Key := UpperCase(AttributeClass.UnitName + '.' + AttributeClass.QualifiedName);
      if Length(Item.AdditionalEdits) = 0 then
        Entry.Preference := 0
      else if Symbol.SymbolKind = TIndexSymbolKind.TypeAlias then
        Entry.Preference := 1
      else
        Entry.Preference := 2;
      Entry.Rank := KnownRank(Name);
      Entry.Order := Order;
      Inc(Order);
      if ByKey.TryGetValue(Entry.Key, Existing) then
      begin
        if Entry.Preference < Entries[Existing].Preference then
        begin
          Entry.Order := Entries[Existing].Order;
          Entries[Existing] := Entry;
        end;
        Continue;
      end;
      ByKey.Add(Entry.Key, Entries.Count);
      Entries.Add(Entry);
    end;
    // Compiler-Attribute ohne Klasse.
    for Name in CompilerNames do
    begin
      if MatchScore(Name, AContext.Prefix, ARequest.Matching) = TFuzzyMatch.NoMatch then
        Continue;
      Entry := Default(TAttributeEntry);
      Entry.Item.Name := Name;
      Entry.Item.Detail := 'Compiler';
      Entry.Item.Kind := KindKeyword;
      Entry.Item.Attribute := True;
      Entry.Rank := KnownRank(Name);
      Entry.Order := Order;
      Inc(Order);
      Entries.Add(Entry);
    end;
    // Bekannte nach ihrem Rang, dann die übrigen in der gesammelten Reihenfolge; Order macht es eindeutig.
    Sorted := Entries.ToArray;
    TArray.Sort<TAttributeEntry>(Sorted, TComparer<TAttributeEntry>.Construct(
      function(const A, B: TAttributeEntry): Integer
      begin
        if (A.Rank >= 0) <> (B.Rank >= 0) then
        begin
          if A.Rank >= 0 then
            Result := -1
          else
            Result := 1;
        end
        else if (A.Rank >= 0) and (A.Rank <> B.Rank) then
          Result := A.Rank - B.Rank
        else
          Result := A.Order - B.Order;
      end));
    SetLength(Result, Length(Sorted));
    for Index := 0 to High(Sorted) do
      Result[Index] := Sorted[Index].Item;
  finally
    Entries.Free;
    ByKey.Free;
    Units.Free;
  end;
end;

end.
