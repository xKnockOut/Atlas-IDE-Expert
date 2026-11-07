unit Atlas.Common.Lsp.CompletionAttributes;

// Attribute nach "[" (#465, ARG-066): Steht der Cursor auf dem Namen in einer Attributklammer vor einer
// Deklaration (TAttributes.InBracket), bleiben nur Attributklassen (Nachfahren von TCustomAttribute,
// TNameResolver.Queries.AttributeClassOf), gezeigt ohne die Endung Attribute.
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
    cKnownNames: array[0..6] of string = ('Test', 'TestCase', 'TestFixture', 'Setup', 'TearDown', 'JSONName',
      'JSONMarshalled');
    /// <summary>Attribute, die der Compiler selbst kennt.</summary>
    cCompilerNames: array[0..3] of string = ('weak', 'unsafe', 'volatile', 'Ref');
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
  mName: string;
begin
  Result := nil;
  for mName in cKnownNames do
  begin
    Result := Result + [mName + 'Attribute'];
  end;
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
      Result := AResolver.Queries.AttributeClassOf(ASymbol, AttributeClass);
    end;
end;

class function TCompletionAttributes.ParameterText(const ASignature: string): string;
var
  mOpen, mIndex, mDepth: Integer;
begin
  Result := '';
  mOpen := Pos('(', ASignature);
  if mOpen = 0 then
  begin
    Exit;
  end;
  mDepth := 0;
  for mIndex := mOpen to Length(ASignature) do
  begin
    if ASignature[mIndex] = '(' then
    begin
      Inc(mDepth);
    end
    else if ASignature[mIndex] = ')' then
    begin
      Dec(mDepth);
      if mDepth = 0 then
      begin
        Exit(Copy(ASignature, mOpen, mIndex - mOpen + 1));
      end;
    end;
  end;
end;

/// <summary>Rang eines bekannten Attributs (0 …), -1 sonst.</summary>
function KnownRank(const AName: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(TCompletionAttributes.cKnownNames) do
  begin
    if SameText(AName, TCompletionAttributes.cKnownNames[mIndex]) then
    begin
      Exit(mIndex);
    end;
  end;
  for mIndex := 0 to High(TCompletionAttributes.cCompilerNames) do
  begin
    if SameText(AName, TCompletionAttributes.cCompilerNames[mIndex]) then
    begin
      Exit(Length(TCompletionAttributes.cKnownNames) + mIndex);
    end;
  end;
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

/// <summary>Bekannte nach ihrem Rang, dann die übrigen in der gesammelten Reihenfolge; Order macht es eindeutig.
/// </summary>
function CompareEntries(const A, B: TAttributeEntry): Integer;
begin
  if (A.Rank >= 0) <> (B.Rank >= 0) then
  begin
    Result := 1;
    if A.Rank >= 0 then
    begin
      Result := -1;
    end;
  end
  else if (A.Rank >= 0) and (A.Rank <> B.Rank) then
  begin
    Result := A.Rank - B.Rank;
  end
  else
  begin
    Result := A.Order - B.Order;
  end;
end;

/// <summary>Vorzug eines Eintrags (siehe TAttributeEntry.Preference).</summary>
function PreferenceOf(const AItem: TCompletionItem; const ASymbol: TResolvedSymbol): Integer;
begin
  Result := 0;
  if Length(AItem.AdditionalEdits) = 0 then
  begin
    Exit;
  end;
  Result := 2;
  if ASymbol.SymbolKind = TIndexSymbolKind.TypeAlias then
  begin
    Result := 1;
  end;
end;

/// <summary>Detail eines Attributs: Parameter des eigenen Konstruktors, sonst die Unit der Klasse.</summary>
function DetailOf(ARequest: TCompletionRequest; const AAttributeClass: TResolvedSymbol): string;
var
  mCtor: TResolvedSymbol;
begin
  Result := '';
  if ARequest.Resolver.DeclaredMember(AAttributeClass, 'Create', mCtor) and
    not SameText(mCtor.Container, 'TCustomAttribute') and not SameText(mCtor.Container, 'TObject') then
  begin
    Result := TCompletionAttributes.ParameterText(mCtor.Signature);
  end;
  if Result = '' then
  begin
    Result := AAttributeClass.UnitName;
  end;
end;

type
  /// <summary>Sammelt die Attribut-Einträge einer Anfrage, eine Klasse nur einmal.</summary>
  TAttributeList = class
  private
    FRequest: TCompletionRequest;
    FPrefix: string;
    FUnits: TDictionary<string, TUnitIndex>;
    FByKey: TDictionary<string, Integer>;
    FEntries: TList<TAttributeEntry>;
    FOrder: Integer;
    function Matches(const AName: string): Boolean;
    procedure Keep(var AEntry: TAttributeEntry);
  public
    constructor Create(ARequest: TCompletionRequest; const APrefix: string);
    destructor Destroy; override;
    procedure AddItem(const AItem: TCompletionItem);
    procedure AddCompilerNames;
    function Items: TArray<TCompletionItem>;
  end;

constructor TAttributeList.Create(ARequest: TCompletionRequest; const APrefix: string);
begin
  inherited Create;
  FRequest := ARequest;
  FPrefix := APrefix;
  FUnits := TDictionary<string, TUnitIndex>.Create;
  FByKey := TDictionary<string, Integer>.Create;
  FEntries := TList<TAttributeEntry>.Create;
end;

destructor TAttributeList.Destroy;
begin
  FEntries.Free;
  FByKey.Free;
  FUnits.Free;
  inherited;
end;

function TAttributeList.Matches(const AName: string): Boolean;
begin
  Result := MatchScore(AName, FPrefix, FRequest.Matching) <> TFuzzyMatch.cNoMatch;
end;

procedure TAttributeList.Keep(var AEntry: TAttributeEntry);
var
  mExisting: Integer;
begin
  AEntry.Rank := KnownRank(AEntry.Item.Name);
  AEntry.Order := FOrder;
  Inc(FOrder);
  if AEntry.Key = '' then
  begin
    FEntries.Add(AEntry);
  end
  else if not FByKey.TryGetValue(AEntry.Key, mExisting) then
  begin
    FByKey.Add(AEntry.Key, FEntries.Count);
    FEntries.Add(AEntry);
  end
  else if AEntry.Preference < FEntries[mExisting].Preference then
  begin
    AEntry.Order := FEntries[mExisting].Order;
    FEntries[mExisting] := AEntry;
  end;
end;

procedure TAttributeList.AddItem(const AItem: TCompletionItem);
var
  mSymbol, mAttributeClass: TResolvedSymbol;
  mName: string;
  mEntry: TAttributeEntry;
begin
  if not TCompletionGenerics.ItemSymbol(FRequest, FUnits, AItem, mSymbol) or
    not FRequest.Resolver.Queries.AttributeClassOf(mSymbol, mAttributeClass) then
  begin
    Exit;
  end;
  mName := TAttributes.ShortName(AItem.Name);
  if not Matches(mName) then
  begin
    Exit;
  end;
  mEntry := Default(TAttributeEntry);
  mEntry.Item := AItem;
  mEntry.Item.Name := mName;
  mEntry.Item.FilterText := mName;
  mEntry.Item.InsertText := mName;
  mEntry.Item.Attribute := True;
  mEntry.Item.Detail := DetailOf(FRequest, mAttributeClass);
  mEntry.Key := UpperCase(mAttributeClass.UnitName + '.' + mAttributeClass.QualifiedName);
  mEntry.Preference := PreferenceOf(AItem, mSymbol);
  Keep(mEntry);
end;

procedure TAttributeList.AddCompilerNames;
var
  mName: string;
  mEntry: TAttributeEntry;
begin
  // Compiler-Attribute ohne Klasse.
  for mName in TCompletionAttributes.cCompilerNames do
  begin
    if Matches(mName) then
    begin
      mEntry := Default(TAttributeEntry);
      mEntry.Item.Name := mName;
      mEntry.Item.Detail := 'Compiler';
      mEntry.Item.Kind := cKindKeyword;
      mEntry.Item.Attribute := True;
      Keep(mEntry);
    end;
  end;
end;

function TAttributeList.Items: TArray<TCompletionItem>;
var
  mSorted: TArray<TAttributeEntry>;
  mIndex: Integer;
begin
  mSorted := FEntries.ToArray;
  TArray.Sort<TAttributeEntry>(mSorted, TComparer<TAttributeEntry>.Construct(
    function(const A, B: TAttributeEntry): Integer
    begin
      Result := CompareEntries(A, B);
    end));
  SetLength(Result, Length(mSorted));
  for mIndex := 0 to High(mSorted) do
  begin
    Result[mIndex] := mSorted[mIndex].Item;
  end;
end;

class function TCompletionAttributes.Apply(ARequest: TCompletionRequest; const AContext: TCompletionContext;
  const AItems: TArray<TCompletionItem>): TArray<TCompletionItem>;
var
  mList: TAttributeList;
  mItem: TCompletionItem;
begin
  mList := TAttributeList.Create(ARequest, AContext.Prefix);
  try
    for mItem in AItems do
    begin
      mList.AddItem(mItem);
    end;
    mList.AddCompilerNames;
    Result := mList.Items;
  finally
    mList.Free;
  end;
end;

end.
