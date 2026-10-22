unit Atlas.Common.Rules.ConsideredUsed;

// Dienst „gilt als verwendet“ (#1102, beschrieben in #64): Mitglieder, die der
// Compiler, die Sprache, das Streaming oder ein Framework aufruft, ohne dass
// der Name im Code steht. Regeln für ungenutzten Code fragen hier, statt eigene
// Ausnahmelisten zu führen; unused-public-member nutzt ihn ganz, toter Code
// (#64), Sichtbarkeit verkleinern (#155) und Sicher löschen (#716) sollen ihn
// unverändert übernehmen.
//
// Gilt als verwendet:
// - message, virtual, dynamic, abstract, override, reintroduce;
// - Konstruktoren, Destruktoren, class constructor/destructor, class operator;
// - GetEnumerator, MoveNext und Current (for-in), default-Array-Properties,
//   Properties mit implements;
// - Mitglieder mit einem Attribut; alle Mitglieder eines Typs mit
//   [TestFixture] oder einem Attribut aus keepAttributes; Namen aus
//   keepPatterns (* und ?, auch als Typ.Name);
// - Methoden, die ein Interface des Typs oder eines Vorfahren umsetzen (auch
//   über die Methodenzuordnung IFoo.Bar = Baz), und alle Mitglieder, solange ein
//   Vorfahr oder Interface nicht im Index steht;
// - published Properties von Nachfahren von TPersistent (Streaming) und alle
//   published Mitglieder von Nachfahren von TTestCase (DUnit ruft sie per RTTI);
// - Zugriffsmethoden einer Property desselben Typs (read, write, stored, add,
//   remove): gemeldet wird höchstens die Property;
// - Routinen aus einer exports-Klausel;
// - Mitglieder von Interfaces und Helfern (Helfer werden über den erweiterten
//   Typ aufgerufen, Interfaces über ihre Umsetzungen).

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.Contract;

type
{$SCOPEDENUMS ON}
  TConsideredUsedReason = (None, Directive, Constructor_, Operator, Enumerator, DefaultProperty, Implements,
    Attribute, KeepAttribute, KeepPattern, TestFixture, InterfaceMethod, UnknownAncestor, Streamed, Accessor,
    Exported, InterfaceMember, HelperMember);
{$SCOPEDENUMS OFF}

  TConsideredUsed = class
  private
    FIndex: ISymbolIndex;
    FUnit: TUnitIndex;
    FTokens: TArray<TPascalToken>;
    FKeepAttributes: TArray<string>;
    FKeepPatterns: TArray<string>;
    FExported: TDictionary<string, Boolean>;
    // Je Typ (Container): Ergebnis der Vorfahrenkette, einmal ermittelt.
    FChains: TDictionary<string, TArray<TIndexSymbol>>;
    FUnknownChains: TDictionary<string, Boolean>;
    function TokenAt(const APosition: TTextPosition): Integer;
    function AttributesBefore(const APosition: TTextPosition): TArray<string>;
    function Owner(const AContainer: string; out AOwner: TIndexSymbol): Boolean;
    function FindType(const AName: string; out AType: TIndexSymbol): Boolean;
    /// <summary>Vorfahren und Interfaces von AOwner bis zur Wurzel; False, wenn einer nicht im Index steht.
    /// </summary>
    function Chain(const AOwner: TIndexSymbol; out AChain: TArray<TIndexSymbol>): Boolean;
    function ChainHas(const AChain: TArray<TIndexSymbol>; const ATypeName: string): Boolean;
    function ImplementsName(const AOwner: TIndexSymbol; const AChain: TArray<TIndexSymbol>;
      const AName: string): Boolean;
    function IsAccessor(const ASymbol: TIndexSymbol): Boolean;
    procedure CollectExports;
  public
    /// <summary>AUnit und ATokens: Unit und Code-Tokens (ohne Kommentare) der Datei, in der die Mitglieder
    /// stehen; AIndex für Vorfahren aus anderen Units (nil: Typen mit fremden Vorfahren gelten als
    /// unbekannt).</summary>
    constructor Create(const AIndex: ISymbolIndex; const AUnit: TUnitIndex; const ATokens: TArray<TPascalToken>;
      const AKeepAttributes, AKeepPatterns: TArray<string>);
    destructor Destroy; override;
    /// <summary>Warum ASymbol (aus AUnit) als verwendet gilt; None = nur Verwendungen im Code zählen.</summary>
    function Reason(const ASymbol: TIndexSymbol): TConsideredUsedReason;
    /// <summary>Kurzer Text zum Grund für Hover und Protokoll, z. B. "überschreibt oder ist virtuell".</summary>
    class function Explain(AReason: TConsideredUsedReason): string; static;
    /// <summary>Passt AName auf das Muster APattern (* beliebig viele, ? genau ein Zeichen, ohne Groß-/
    /// Kleinschreibung)?</summary>
    class function Matches(const APattern, AName: string): Boolean; static;
  end;

implementation

uses
  System.StrUtils;

const
  KeptDirectives: array[0..5] of string = ('message', 'virtual', 'dynamic', 'abstract', 'override', 'reintroduce');
  EnumeratorNames: array[0..2] of string = ('GetEnumerator', 'MoveNext', 'Current');
  AccessorWords: array[0..4] of string = ('read', 'write', 'stored', 'add', 'remove');
  MaxChainDepth = 64;

function ShortName(const AName: string): string;
var
  Position: Integer;
begin
  Result := AName;
  Position := Pos('<', Result);
  if Position > 0 then
    Result := Copy(Result, 1, Position - 1);
  Result := Copy(Result, LastDelimiter('.', Result) + 1, MaxInt);
end;

{ TConsideredUsed }

constructor TConsideredUsed.Create(const AIndex: ISymbolIndex; const AUnit: TUnitIndex;
  const ATokens: TArray<TPascalToken>; const AKeepAttributes, AKeepPatterns: TArray<string>);
begin
  inherited Create;
  FIndex := AIndex;
  FUnit := AUnit;
  FTokens := ATokens;
  FKeepAttributes := AKeepAttributes;
  FKeepPatterns := AKeepPatterns;
  FExported := TDictionary<string, Boolean>.Create;
  FChains := TDictionary<string, TArray<TIndexSymbol>>.Create;
  FUnknownChains := TDictionary<string, Boolean>.Create;
  CollectExports;
end;

destructor TConsideredUsed.Destroy;
begin
  FExported.Free;
  FChains.Free;
  FUnknownChains.Free;
  inherited;
end;

class function TConsideredUsed.Matches(const APattern, AName: string): Boolean;
var
  Pattern, Name: string;
  P, N, StarP, StarN: Integer;
begin
  Pattern := UpperCase(APattern);
  Name := UpperCase(AName);
  P := 1;
  N := 1;
  StarP := 0;
  StarN := 0;
  while N <= Length(Name) do
  begin
    if (P <= Length(Pattern)) and ((Pattern[P] = '?') or (Pattern[P] = Name[N])) then
    begin
      Inc(P);
      Inc(N);
    end
    else if (P <= Length(Pattern)) and (Pattern[P] = '*') then
    begin
      StarP := P;
      StarN := N;
      Inc(P);
    end
    else if StarP > 0 then
    begin
      P := StarP + 1;
      Inc(StarN);
      N := StarN;
    end
    else
      Exit(False);
  end;
  while (P <= Length(Pattern)) and (Pattern[P] = '*') do
    Inc(P);
  Result := P > Length(Pattern);
end;

class function TConsideredUsed.Explain(AReason: TConsideredUsedReason): string;
begin
  case AReason of
    TConsideredUsedReason.Directive:
      Result := 'virtuell, überschrieben oder Message-Handler';
    TConsideredUsedReason.Constructor_:
      Result := 'Konstruktor oder Destruktor';
    TConsideredUsedReason.Operator:
      Result := 'Operator';
    TConsideredUsedReason.Enumerator:
      Result := 'for-in-Enumerator';
    TConsideredUsedReason.DefaultProperty:
      Result := 'Default-Property';
    TConsideredUsedReason.Implements:
      Result := 'Property mit implements';
    TConsideredUsedReason.Attribute:
      Result := 'Mitglied mit Attribut (RTTI)';
    TConsideredUsedReason.KeepAttribute:
      Result := 'Typ mit Attribut aus keepAttributes';
    TConsideredUsedReason.KeepPattern:
      Result := 'Name aus keepPatterns';
    TConsideredUsedReason.TestFixture:
      Result := 'Testklasse';
    TConsideredUsedReason.InterfaceMethod:
      Result := 'setzt eine Interface-Methode um';
    TConsideredUsedReason.UnknownAncestor:
      Result := 'Vorfahr oder Interface nicht im Index';
    TConsideredUsedReason.Streamed:
      Result := 'published Property eines TPersistent-Nachfahren (Streaming)';
    TConsideredUsedReason.Accessor:
      Result := 'Zugriffsmethode einer Property';
    TConsideredUsedReason.Exported:
      Result := 'in exports';
    TConsideredUsedReason.InterfaceMember:
      Result := 'Mitglied eines Interfaces';
    TConsideredUsedReason.HelperMember:
      Result := 'Mitglied eines Helfers';
  else
    Result := '';
  end;
end;

function TConsideredUsed.TokenAt(const APosition: TTextPosition): Integer;
var
  Low, High_, Middle: Integer;
begin
  Low := 0;
  High_ := Length(FTokens);
  while Low < High_ do
  begin
    Middle := (Low + High_) div 2;
    if (FTokens[Middle].StartPos.Line < APosition.Line) or ((FTokens[Middle].StartPos.Line = APosition.Line) and
      (FTokens[Middle].StartPos.Character < APosition.Character)) then
      Low := Middle + 1
    else
      High_ := Middle;
  end;
  Result := Low;
  if Result > High(FTokens) then
    Result := -1;
end;

function TConsideredUsed.AttributesBefore(const APosition: TTextPosition): TArray<string>;
var
  At, Depth: Integer;
  Name: string;
begin
  Result := nil;
  At := TokenAt(APosition) - 1;
  // Rückwärts über [A, B('x')] [C] direkt vor der Deklaration; der erste Bezeichner nach [ oder , ist der Name.
  while (At >= 0) and FTokens[At].IsSymbol(']') do
  begin
    Depth := 0;
    while At >= 0 do
    begin
      if FTokens[At].IsSymbol(']') then
        Inc(Depth)
      else if FTokens[At].IsSymbol('[') then
      begin
        Dec(Depth);
        if Depth = 0 then
          Break;
      end
      else if (Depth = 1) and (FTokens[At].Kind = TPascalTokenKind.Identifier) and (At > 0) and
        (FTokens[At - 1].IsSymbol('[') or FTokens[At - 1].IsSymbol(',')) then
      begin
        Name := FTokens[At].Text;
        if EndsText('Attribute', Name) and (Length(Name) > Length('Attribute')) then
          Name := Copy(Name, 1, Length(Name) - Length('Attribute'));
        Result := Result + [Name];
      end;
      Dec(At);
    end;
    Dec(At);
  end;
end;

function TConsideredUsed.Owner(const AContainer: string; out AOwner: TIndexSymbol): Boolean;
var
  Symbol: TIndexSymbol;
begin
  for Symbol in FUnit.Symbols do
    if (Symbol.Kind in [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType,
      TIndexSymbolKind.InterfaceType, TIndexSymbolKind.HelperType]) and SameText(Symbol.QualifiedName, AContainer) then
    begin
      AOwner := Symbol;
      Exit(True);
    end;
  AOwner := Default(TIndexSymbol);
  Result := False;
end;

function TConsideredUsed.FindType(const AName: string; out AType: TIndexSymbol): Boolean;
var
  Short: string;
  Symbol: TIndexSymbol;
  Location: TSymbolLocation;
begin
  Short := ShortName(AName);
  // Zuerst die eigene Unit, dann der Index.
  for Symbol in FUnit.Symbols do
    if (Symbol.Kind in [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.InterfaceType,
      TIndexSymbolKind.RecordType]) and SameText(Symbol.Name, Short) then
    begin
      AType := Symbol;
      Exit(True);
    end;
  if FIndex <> nil then
    for Location in FIndex.FindSymbols(Short) do
      if Location.Symbol.Kind in [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType,
        TIndexSymbolKind.InterfaceType, TIndexSymbolKind.RecordType] then
      begin
        AType := Location.Symbol;
        Exit(True);
      end;
  AType := Default(TIndexSymbol);
  Result := False;
end;

function TConsideredUsed.Chain(const AOwner: TIndexSymbol; out AChain: TArray<TIndexSymbol>): Boolean;
var
  Key, Ancestor: string;
  Pending: TList<TIndexSymbol>;
  Seen: TDictionary<string, Boolean>;
  Current, Found: TIndexSymbol;
  Collected: TArray<TIndexSymbol>;
  Known: Boolean;
begin
  Key := LowerCase(AOwner.QualifiedName);
  if FUnknownChains.ContainsKey(Key) then
  begin
    AChain := nil;
    Exit(False);
  end;
  if FChains.TryGetValue(Key, AChain) then
    Exit(True);
  Collected := nil;
  Known := True;
  Pending := TList<TIndexSymbol>.Create;
  Seen := TDictionary<string, Boolean>.Create;
  try
    Pending.Add(AOwner);
    while (Pending.Count > 0) and (Length(Collected) < MaxChainDepth) do
    begin
      Current := Pending[0];
      Pending.Delete(0);
      for Ancestor in Current.Ancestors do
      begin
        if Seen.ContainsKey(LowerCase(ShortName(Ancestor))) then
          Continue;
        Seen.Add(LowerCase(ShortName(Ancestor)), True);
        if not FindType(Ancestor, Found) then
        begin
          Known := False;
          Continue;
        end;
        Collected := Collected + [Found];
        Pending.Add(Found);
      end;
    end;
  finally
    Pending.Free;
    Seen.Free;
  end;
  if not Known then
  begin
    FUnknownChains.AddOrSetValue(Key, True);
    AChain := nil;
    Exit(False);
  end;
  FChains.AddOrSetValue(Key, Collected);
  AChain := Collected;
  Result := True;
end;

function TConsideredUsed.ChainHas(const AChain: TArray<TIndexSymbol>; const ATypeName: string): Boolean;
var
  Symbol: TIndexSymbol;
begin
  for Symbol in AChain do
    if SameText(Symbol.Name, ATypeName) then
      Exit(True);
  Result := False;
end;

function TConsideredUsed.ImplementsName(const AOwner: TIndexSymbol; const AChain: TArray<TIndexSymbol>;
  const AName: string): Boolean;
var
  Symbol, Member: TIndexSymbol;
  Location: TSymbolLocation;
  At, Last: Integer;
begin
  for Symbol in AChain do
    if Symbol.Kind = TIndexSymbolKind.InterfaceType then
    begin
      if FIndex <> nil then
        for Location in FIndex.FindSymbols(AName) do
          if SameText(Location.Symbol.Container, Symbol.QualifiedName) or
            SameText(Location.Symbol.Container, Symbol.Name) then
            Exit(True);
      // Interface aus der eigenen Unit, die (noch) nicht im Index steht.
      for Member in FUnit.Symbols do
        if SameText(Member.Name, AName) and SameText(Member.Container, Symbol.QualifiedName) then
          Exit(True);
    end;
  // Methodenzuordnung im Typ: procedure IFoo.Bar = Baz;
  At := TokenAt(AOwner.Range.StartPos);
  Last := TokenAt(AOwner.Range.EndPos);
  if (At < 0) or (Last < 0) then
    Last := High(FTokens);
  while (At >= 0) and (At <= Last) and (At < High(FTokens)) do
  begin
    if (At >= 3) and SameText(FTokens[At].Text, AName) and FTokens[At - 1].IsSymbol('=') and
      (FTokens[At - 2].Kind = TPascalTokenKind.Identifier) and FTokens[At - 3].IsSymbol('.') then
      Exit(True);
    Inc(At);
  end;
  Result := False;
end;

function TConsideredUsed.IsAccessor(const ASymbol: TIndexSymbol): Boolean;
var
  Symbol: TIndexSymbol;
  Words: TArray<string>;
  Index: Integer;
begin
  for Symbol in FUnit.Symbols do
    if (Symbol.Kind = TIndexSymbolKind.Property_) and SameText(Symbol.Container, ASymbol.Container) then
    begin
      Words := Symbol.Signature.Replace(';', ' ').Replace(':', ' ').Split([' '],
        TStringSplitOptions.ExcludeEmpty);
      for Index := 0 to High(Words) - 1 do
        if (IndexText(Words[Index], AccessorWords) >= 0) and SameText(Words[Index + 1], ASymbol.Name) then
          Exit(True);
    end;
  Result := False;
end;

procedure TConsideredUsed.CollectExports;
var
  Index: Integer;
  InExports: Boolean;
begin
  InExports := False;
  for Index := 0 to High(FTokens) do
  begin
    if FTokens[Index].IsKeyword('exports') then
      InExports := True
    else if InExports and FTokens[Index].IsSymbol(';') then
      InExports := False
    else if InExports and (FTokens[Index].Kind = TPascalTokenKind.Identifier) and (Index > 0) and
      (FTokens[Index - 1].IsKeyword('exports') or FTokens[Index - 1].IsSymbol(',')) then
      FExported.AddOrSetValue(LowerCase(FTokens[Index].Text), True);
  end;
end;

function TConsideredUsed.Reason(const ASymbol: TIndexSymbol): TConsideredUsedReason;
var
  Directive, Attribute, Pattern, Signature: string;
  OwnerSymbol: TIndexSymbol;
  HasOwner: Boolean;
  Ancestors: TArray<TIndexSymbol>;
begin
  for Directive in KeptDirectives do
    if ASymbol.HasDirective(Directive) then
      Exit(TConsideredUsedReason.Directive);
  Signature := TrimLeft(ASymbol.Signature);
  if (ASymbol.Kind = TIndexSymbolKind.Constructor_) or StartsText('constructor', Signature) or
    StartsText('destructor', Signature) or StartsText('class constructor', Signature) or
    StartsText('class destructor', Signature) then
    Exit(TConsideredUsedReason.Constructor_);
  if StartsText('class operator', Signature) then
    Exit(TConsideredUsedReason.Operator);
  if (ASymbol.Container <> '') and (IndexText(ASymbol.Name, EnumeratorNames) >= 0) then
    Exit(TConsideredUsedReason.Enumerator);
  if (ASymbol.Kind = TIndexSymbolKind.Property_) and ASymbol.IsDefault then
    Exit(TConsideredUsedReason.DefaultProperty);
  if (ASymbol.Kind = TIndexSymbolKind.Property_) and ContainsText(' ' + Signature + ' ', ' implements ') then
    Exit(TConsideredUsedReason.Implements);
  if AttributesBefore(ASymbol.Range.StartPos) <> nil then
    Exit(TConsideredUsedReason.Attribute);
  for Pattern in FKeepPatterns do
    if Matches(Pattern, ASymbol.Name) or ((ASymbol.Container <> '') and
      Matches(Pattern, ASymbol.Container + '.' + ASymbol.Name)) then
      Exit(TConsideredUsedReason.KeepPattern);
  if (ASymbol.Container = '') and FExported.ContainsKey(LowerCase(ASymbol.Name)) then
    Exit(TConsideredUsedReason.Exported);
  if ASymbol.Container = '' then
    Exit(TConsideredUsedReason.None);
  HasOwner := Owner(ASymbol.Container, OwnerSymbol);
  if not HasOwner then
    Exit(TConsideredUsedReason.UnknownAncestor);
  if OwnerSymbol.Kind = TIndexSymbolKind.InterfaceType then
    Exit(TConsideredUsedReason.InterfaceMember);
  if OwnerSymbol.Kind = TIndexSymbolKind.HelperType then
    Exit(TConsideredUsedReason.HelperMember);
  for Attribute in AttributesBefore(OwnerSymbol.Range.StartPos) do
  begin
    if SameText(Attribute, 'TestFixture') then
      Exit(TConsideredUsedReason.TestFixture);
    if IndexText(Attribute, FKeepAttributes) >= 0 then
      Exit(TConsideredUsedReason.KeepAttribute);
  end;
  if (ASymbol.Kind = TIndexSymbolKind.Method) and IsAccessor(ASymbol) then
    Exit(TConsideredUsedReason.Accessor);
  if not Chain(OwnerSymbol, Ancestors) then
    Exit(TConsideredUsedReason.UnknownAncestor);
  if (ASymbol.Visibility = TIndexVisibility.Published) and ChainHas(Ancestors, 'TTestCase') then
    Exit(TConsideredUsedReason.TestFixture);
  if (ASymbol.Visibility = TIndexVisibility.Published) and (ASymbol.Kind = TIndexSymbolKind.Property_) and
    ChainHas(Ancestors, 'TPersistent') then
    Exit(TConsideredUsedReason.Streamed);
  if (ASymbol.Kind = TIndexSymbolKind.Method) and ImplementsName(OwnerSymbol, Ancestors, ASymbol.Name) then
    Exit(TConsideredUsedReason.InterfaceMethod);
  Result := TConsideredUsedReason.None;
end;

end.
