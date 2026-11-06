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
    function InterfaceHas(const AInterface: TIndexSymbol; const AName: string): Boolean;
    function MapsMethod(const AOwner: TIndexSymbol; const AName: string): Boolean;
    function NameReason(const ASymbol: TIndexSymbol): TConsideredUsedReason;
    function TypeAttributeReason(const AOwner: TIndexSymbol): TConsideredUsedReason;
    function AncestryReason(const ASymbol, AOwner: TIndexSymbol): TConsideredUsedReason;
    function OwnerReason(const ASymbol, AOwner: TIndexSymbol): TConsideredUsedReason;
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
    /// <summary>Erstes Token in ATokens, das bei APosition oder dahinter beginnt; -1 hinter dem letzten.</summary>
    class function TokenIndexAt(const ATokens: TArray<TPascalToken>; const APosition: TTextPosition): Integer; static;
    /// <summary>Namen der Attribute direkt vor der Deklaration an APosition ([A, B('x')] [C]), ohne Endung
    /// Attribute; ATokens sind Code-Tokens ohne Kommentare. Auch für Code-Abfragen (has attribute, #1351).
    /// </summary>
    class function AttributesAt(const ATokens: TArray<TPascalToken>; const APosition: TTextPosition): TArray<string>;
      static;
  end;

implementation

uses
  System.StrUtils,
  System.Math,
  Atlas.Common.Localization.Texts;

const
  /// <summary>Begründungen für den Befund-Hover in beiden Sprachen (#1458); None hat keinen Text.</summary>
  cTexts: array[TConsideredUsedReason.Directive..TConsideredUsedReason.HelperMember] of TAtlasText = (
    (De: 'virtuell, überschrieben oder Message-Handler'; En: 'virtual, overridden or message handler'),
    (De: 'Konstruktor oder Destruktor'; En: 'constructor or destructor'),
    (De: 'Operator'; En: 'operator'),
    (De: 'for-in-Enumerator'; En: 'for-in enumerator'),
    (De: 'Default-Property'; En: 'default property'),
    (De: 'Property mit implements'; En: 'property with implements'),
    (De: 'Mitglied mit Attribut (RTTI)'; En: 'member with attribute (RTTI)'),
    (De: 'Typ mit Attribut aus keepAttributes'; En: 'type with attribute from keepAttributes'),
    (De: 'Name aus keepPatterns'; En: 'name from keepPatterns'),
    (De: 'Testklasse'; En: 'test class'),
    (De: 'setzt eine Interface-Methode um'; En: 'implements an interface method'),
    (De: 'Vorfahr oder Interface nicht im Index'; En: 'ancestor or interface not in the index'),
    (De: 'published Property eines TPersistent-Nachfahren (Streaming)';
     En: 'published property of a TPersistent descendant (streaming)'),
    (De: 'Zugriffsmethode einer Property'; En: 'accessor of a property'),
    (De: 'in exports'; En: 'in exports'),
    (De: 'Mitglied eines Interfaces'; En: 'member of an interface'),
    (De: 'Mitglied eines Helfers'; En: 'member of a helper'));

  cKeptDirectives: array[0..5] of string = ('message', 'virtual', 'dynamic', 'abstract', 'override', 'reintroduce');
  cEnumeratorNames: array[0..2] of string = ('GetEnumerator', 'MoveNext', 'Current');
  cAccessorWords: array[0..4] of string = ('read', 'write', 'stored', 'add', 'remove');
  cMaxChainDepth = 64;

function ShortName(const AName: string): string;
var
  mPosition: Integer;
begin
  Result := AName;
  mPosition := Pos('<', Result);
  if mPosition > 0 then
  begin
    Result := Copy(Result, 1, mPosition - 1);
  end;
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
  mPattern, mName: string;
  P, N, mStarP, mStarN: Integer;
begin
  mPattern := UpperCase(APattern);
  mName := UpperCase(AName);
  P := 1;
  N := 1;
  mStarP := 0;
  mStarN := 0;
  while N <= Length(mName) do
  begin
    if (P <= Length(mPattern)) and ((mPattern[P] = '?') or (mPattern[P] = mName[N])) then
    begin
      Inc(P);
      Inc(N);
    end
    else if (P <= Length(mPattern)) and (mPattern[P] = '*') then
    begin
      mStarP := P;
      mStarN := N;
      Inc(P);
    end
    else if mStarP > 0 then
    begin
      P := mStarP + 1;
      Inc(mStarN);
      N := mStarN;
    end
    else
    begin
      Exit(False);
    end;
  end;
  while (P <= Length(mPattern)) and (mPattern[P] = '*') do
  begin
    Inc(P);
  end;
  Result := P > Length(mPattern);
end;

class function TConsideredUsed.Explain(AReason: TConsideredUsedReason): string;
begin
  Result := '';
  if AReason <> TConsideredUsedReason.None then
  begin
    Result := cTexts[AReason].Text;
  end;
end;

function TConsideredUsed.TokenAt(const APosition: TTextPosition): Integer;
begin
  Result := TokenIndexAt(FTokens, APosition);
end;

class function TConsideredUsed.TokenIndexAt(const ATokens: TArray<TPascalToken>;
  const APosition: TTextPosition): Integer;
var
  mLow, mHigh_, mMiddle: Integer;
begin
  mLow := 0;
  mHigh_ := Length(ATokens);
  while mLow < mHigh_ do
  begin
    mMiddle := (mLow + mHigh_) div 2;
    if (ATokens[mMiddle].StartPos.Line < APosition.Line) or ((ATokens[mMiddle].StartPos.Line = APosition.Line) and
      (ATokens[mMiddle].StartPos.Character < APosition.Character)) then
    begin
      mLow := mMiddle + 1;
    end
    else
    begin
      mHigh_ := mMiddle;
    end;
  end;
  Result := mLow;
  if Result > High(ATokens) then
  begin
    Result := -1;
  end;
end;

function TConsideredUsed.AttributesBefore(const APosition: TTextPosition): TArray<string>;
begin
  Result := AttributesAt(FTokens, APosition);
end;

/// <summary>Eine Attributgruppe [A, B('x')] rückwärts ab AAt (auf "]"); AAt steht danach auf "[". Der erste
/// Bezeichner nach [ oder , ist der Name, ohne die Endung Attribute.</summary>
procedure ReadAttributeGroup(const ATokens: TArray<TPascalToken>; var AAt: Integer; var ANames: TArray<string>);
var
  mDepth: Integer;
  mName: string;
begin
  mDepth := 0;
  while AAt >= 0 do
  begin
    if ATokens[AAt].IsSymbol(']') then
    begin
      Inc(mDepth);
    end
    else if ATokens[AAt].IsSymbol('[') then
    begin
      Dec(mDepth);
      if mDepth = 0 then
      begin
        Exit;
      end;
    end
    else if (mDepth = 1) and (ATokens[AAt].Kind = TPascalTokenKind.Identifier) and (AAt > 0) and
      (ATokens[AAt - 1].IsSymbol('[') or ATokens[AAt - 1].IsSymbol(',')) then
    begin
      mName := ATokens[AAt].Text;
      if EndsText('Attribute', mName) and (Length(mName) > Length('Attribute')) then
      begin
        mName := Copy(mName, 1, Length(mName) - Length('Attribute'));
      end;
      ANames := ANames + [mName];
    end;
    Dec(AAt);
  end;
end;

class function TConsideredUsed.AttributesAt(const ATokens: TArray<TPascalToken>;
  const APosition: TTextPosition): TArray<string>;
var
  mAt: Integer;
begin
  Result := nil;
  mAt := TokenIndexAt(ATokens, APosition) - 1;
  // Rückwärts über [A, B('x')] [C] direkt vor der Deklaration.
  while (mAt >= 0) and ATokens[mAt].IsSymbol(']') do
  begin
    ReadAttributeGroup(ATokens, mAt, Result);
    Dec(mAt);
  end;
end;

function TConsideredUsed.Owner(const AContainer: string; out AOwner: TIndexSymbol): Boolean;
var
  mSymbol: TIndexSymbol;
begin
  for mSymbol in FUnit.Symbols do
  begin
    if (mSymbol.Kind in [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType,
      TIndexSymbolKind.InterfaceType, TIndexSymbolKind.HelperType]) and SameText(mSymbol.QualifiedName, AContainer) then
    begin
      AOwner := mSymbol;
      Exit(True);
    end;
  end;
  AOwner := Default(TIndexSymbol);
  Result := False;
end;

function TConsideredUsed.FindType(const AName: string; out AType: TIndexSymbol): Boolean;
var
  mShort: string;
  mSymbol: TIndexSymbol;
  mLocation: TSymbolLocation;
begin
  mShort := ShortName(AName);
  // Zuerst die eigene Unit, dann der Index.
  for mSymbol in FUnit.Symbols do
  begin
    if (mSymbol.Kind in [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.InterfaceType,
      TIndexSymbolKind.RecordType]) and SameText(mSymbol.Name, mShort) then
    begin
      AType := mSymbol;
      Exit(True);
    end;
  end;
  if FIndex <> nil then
  begin
    for mLocation in FIndex.FindSymbols(mShort) do
    begin
      if mLocation.Symbol.Kind in [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType,
        TIndexSymbolKind.InterfaceType, TIndexSymbolKind.RecordType] then
      begin
        AType := mLocation.Symbol;
        Exit(True);
      end;
    end;
  end;
  AType := Default(TIndexSymbol);
  Result := False;
end;

function TConsideredUsed.Chain(const AOwner: TIndexSymbol; out AChain: TArray<TIndexSymbol>): Boolean;
var
  mKey, mAncestor: string;
  mPending: TList<TIndexSymbol>;
  mSeen: TDictionary<string, Boolean>;
  mCurrent, mFound: TIndexSymbol;
  mCollected: TArray<TIndexSymbol>;
  mKnown: Boolean;
begin
  mKey := LowerCase(AOwner.QualifiedName);
  if FUnknownChains.ContainsKey(mKey) then
  begin
    AChain := nil;
    Exit(False);
  end;
  if FChains.TryGetValue(mKey, AChain) then
  begin
    Exit(True);
  end;
  mCollected := nil;
  mKnown := True;
  mPending := TList<TIndexSymbol>.Create;
  mSeen := TDictionary<string, Boolean>.Create;
  try
    mPending.Add(AOwner);
    while (mPending.Count > 0) and (Length(mCollected) < cMaxChainDepth) do
    begin
      mCurrent := mPending[0];
      mPending.Delete(0);
      for mAncestor in mCurrent.Ancestors do
      begin
        if mSeen.ContainsKey(LowerCase(ShortName(mAncestor))) then
        begin
          Continue;
        end;
        mSeen.Add(LowerCase(ShortName(mAncestor)), True);
        if not FindType(mAncestor, mFound) then
        begin
          mKnown := False;
          Continue;
        end;
        mCollected := mCollected + [mFound];
        mPending.Add(mFound);
      end;
    end;
  finally
    mPending.Free;
    mSeen.Free;
  end;
  if not mKnown then
  begin
    FUnknownChains.AddOrSetValue(mKey, True);
    AChain := nil;
    Exit(False);
  end;
  FChains.AddOrSetValue(mKey, mCollected);
  AChain := mCollected;
  Result := True;
end;

function TConsideredUsed.ChainHas(const AChain: TArray<TIndexSymbol>; const ATypeName: string): Boolean;
var
  mSymbol: TIndexSymbol;
begin
  for mSymbol in AChain do
  begin
    if SameText(mSymbol.Name, ATypeName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TConsideredUsed.InterfaceHas(const AInterface: TIndexSymbol; const AName: string): Boolean;
var
  mMember: TIndexSymbol;
  mLocation: TSymbolLocation;
begin
  if FIndex <> nil then
  begin
    for mLocation in FIndex.FindSymbols(AName) do
    begin
      if SameText(mLocation.Symbol.Container, AInterface.QualifiedName) or
        SameText(mLocation.Symbol.Container, AInterface.Name) then
      begin
        Exit(True);
      end;
    end;
  end;
  // Interface aus der eigenen Unit, die (noch) nicht im Index steht.
  for mMember in FUnit.Symbols do
  begin
    if SameText(mMember.Name, AName) and SameText(mMember.Container, AInterface.QualifiedName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TConsideredUsed.MapsMethod(const AOwner: TIndexSymbol; const AName: string): Boolean;
var
  mAt, mLast: Integer;
begin
  // Methodenzuordnung im Typ: procedure IFoo.Bar = Baz;
  mAt := TokenAt(AOwner.Range.StartPos);
  mLast := TokenAt(AOwner.Range.EndPos);
  if mAt < 0 then
  begin
    Exit(False);
  end;
  if mLast < 0 then
  begin
    mLast := High(FTokens);
  end;
  // Vor dem Namen stehen mindestens IFoo . Bar =.
  mAt := Max(mAt, 3);
  while (mAt <= mLast) and (mAt < High(FTokens)) do
  begin
    if SameText(FTokens[mAt].Text, AName) and FTokens[mAt - 1].IsSymbol('=') and
      (FTokens[mAt - 2].Kind = TPascalTokenKind.Identifier) and FTokens[mAt - 3].IsSymbol('.') then
    begin
      Exit(True);
    end;
    Inc(mAt);
  end;
  Result := False;
end;

function TConsideredUsed.ImplementsName(const AOwner: TIndexSymbol; const AChain: TArray<TIndexSymbol>;
  const AName: string): Boolean;
var
  mSymbol: TIndexSymbol;
begin
  for mSymbol in AChain do
  begin
    if (mSymbol.Kind = TIndexSymbolKind.InterfaceType) and InterfaceHas(mSymbol, AName) then
    begin
      Exit(True);
    end;
  end;
  Result := MapsMethod(AOwner, AName);
end;

function TConsideredUsed.IsAccessor(const ASymbol: TIndexSymbol): Boolean;
var
  mSymbol: TIndexSymbol;
  mWords: TArray<string>;
  mIndex: Integer;
begin
  for mSymbol in FUnit.Symbols do
  begin
    if (mSymbol.Kind = TIndexSymbolKind.Property_) and SameText(mSymbol.Container, ASymbol.Container) then
    begin
      mWords := mSymbol.Signature.Replace(';', ' ').Replace(':', ' ').Split([' '],
        TStringSplitOptions.ExcludeEmpty);
      for mIndex := 0 to High(mWords) - 1 do
      begin
        if (IndexText(mWords[mIndex], cAccessorWords) >= 0) and SameText(mWords[mIndex + 1], ASymbol.Name) then
        begin
          Exit(True);
        end;
      end;
    end;
  end;
  Result := False;
end;

procedure TConsideredUsed.CollectExports;
var
  mIndex: Integer;
  mInExports: Boolean;
begin
  mInExports := False;
  for mIndex := 0 to High(FTokens) do
  begin
    if FTokens[mIndex].IsKeyword('exports') then
    begin
      mInExports := True;
    end
    else if mInExports and FTokens[mIndex].IsSymbol(';') then
    begin
      mInExports := False;
    end
    else if mInExports and (FTokens[mIndex].Kind = TPascalTokenKind.Identifier) and (mIndex > 0) and
      (FTokens[mIndex - 1].IsKeyword('exports') or FTokens[mIndex - 1].IsSymbol(',')) then
    begin
      FExported.AddOrSetValue(LowerCase(FTokens[mIndex].Text), True);
    end;
  end;
end;

function HasKeptDirective(const ASymbol: TIndexSymbol): Boolean;
var
  mDirective: string;
begin
  for mDirective in cKeptDirectives do
  begin
    if ASymbol.HasDirective(mDirective) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Gründe, die schon die Deklaration verrät: Direktiven, Konstruktoren, Operatoren, Enumerator,
/// Default-Property und implements.</summary>
function DeclarationReason(const ASymbol: TIndexSymbol): TConsideredUsedReason;
var
  mSignature: string;
  mProperty: Boolean;
begin
  Result := TConsideredUsedReason.None;
  mSignature := TrimLeft(ASymbol.Signature);
  mProperty := ASymbol.Kind = TIndexSymbolKind.Property_;
  if HasKeptDirective(ASymbol) then
  begin
    Result := TConsideredUsedReason.Directive;
  end
  else if (ASymbol.Kind = TIndexSymbolKind.Constructor_) or StartsText('constructor', mSignature) or
    StartsText('destructor', mSignature) or StartsText('class constructor', mSignature) or
    StartsText('class destructor', mSignature) then
  begin
    Result := TConsideredUsedReason.Constructor_;
  end
  else if StartsText('class operator', mSignature) then
  begin
    Result := TConsideredUsedReason.Operator;
  end
  else if (ASymbol.Container <> '') and (IndexText(ASymbol.Name, cEnumeratorNames) >= 0) then
  begin
    Result := TConsideredUsedReason.Enumerator;
  end
  else if mProperty and ASymbol.IsDefault then
  begin
    Result := TConsideredUsedReason.DefaultProperty;
  end
  else if mProperty and ContainsText(' ' + mSignature + ' ', ' implements ') then
  begin
    Result := TConsideredUsedReason.Implements;
  end;
end;

function TConsideredUsed.NameReason(const ASymbol: TIndexSymbol): TConsideredUsedReason;
var
  mPattern: string;
begin
  if AttributesBefore(ASymbol.Range.StartPos) <> nil then
  begin
    Exit(TConsideredUsedReason.Attribute);
  end;
  for mPattern in FKeepPatterns do
  begin
    if Matches(mPattern, ASymbol.Name) or ((ASymbol.Container <> '') and
      Matches(mPattern, ASymbol.Container + '.' + ASymbol.Name)) then
    begin
      Exit(TConsideredUsedReason.KeepPattern);
    end;
  end;
  Result := TConsideredUsedReason.None;
  if (ASymbol.Container = '') and FExported.ContainsKey(LowerCase(ASymbol.Name)) then
  begin
    Result := TConsideredUsedReason.Exported;
  end;
end;

function TConsideredUsed.TypeAttributeReason(const AOwner: TIndexSymbol): TConsideredUsedReason;
var
  mAttribute: string;
begin
  for mAttribute in AttributesBefore(AOwner.Range.StartPos) do
  begin
    if SameText(mAttribute, 'TestFixture') then
    begin
      Exit(TConsideredUsedReason.TestFixture);
    end;
    if IndexText(mAttribute, FKeepAttributes) >= 0 then
    begin
      Exit(TConsideredUsedReason.KeepAttribute);
    end;
  end;
  Result := TConsideredUsedReason.None;
end;

function TConsideredUsed.AncestryReason(const ASymbol, AOwner: TIndexSymbol): TConsideredUsedReason;
var
  mAncestors: TArray<TIndexSymbol>;
  mPublished: Boolean;
begin
  Result := TConsideredUsedReason.None;
  mPublished := ASymbol.Visibility = TIndexVisibility.Published;
  if not Chain(AOwner, mAncestors) then
  begin
    Result := TConsideredUsedReason.UnknownAncestor;
  end
  else if mPublished and ChainHas(mAncestors, 'TTestCase') then
  begin
    Result := TConsideredUsedReason.TestFixture;
  end
  else if mPublished and (ASymbol.Kind = TIndexSymbolKind.Property_) and ChainHas(mAncestors, 'TPersistent') then
  begin
    Result := TConsideredUsedReason.Streamed;
  end
  else if (ASymbol.Kind = TIndexSymbolKind.Method) and ImplementsName(AOwner, mAncestors, ASymbol.Name) then
  begin
    Result := TConsideredUsedReason.InterfaceMethod;
  end;
end;

function TConsideredUsed.OwnerReason(const ASymbol, AOwner: TIndexSymbol): TConsideredUsedReason;
begin
  if AOwner.Kind = TIndexSymbolKind.InterfaceType then
  begin
    Result := TConsideredUsedReason.InterfaceMember;
  end
  else if AOwner.Kind = TIndexSymbolKind.HelperType then
  begin
    Result := TConsideredUsedReason.HelperMember;
  end
  else
  begin
    Result := TypeAttributeReason(AOwner);
  end;
  if Result <> TConsideredUsedReason.None then
  begin
    Exit;
  end;
  if (ASymbol.Kind = TIndexSymbolKind.Method) and IsAccessor(ASymbol) then
  begin
    Result := TConsideredUsedReason.Accessor;
  end
  else
  begin
    Result := AncestryReason(ASymbol, AOwner);
  end;
end;

function TConsideredUsed.Reason(const ASymbol: TIndexSymbol): TConsideredUsedReason;
var
  mOwner: TIndexSymbol;
begin
  Result := DeclarationReason(ASymbol);
  if Result = TConsideredUsedReason.None then
  begin
    Result := NameReason(ASymbol);
  end;
  if (Result <> TConsideredUsedReason.None) or (ASymbol.Container = '') then
  begin
    Exit;
  end;
  if not Owner(ASymbol.Container, mOwner) then
  begin
    Exit(TConsideredUsedReason.UnknownAncestor);
  end;
  Result := OwnerReason(ASymbol, mOwner);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.ConsideredUsed', cTexts);

end.
