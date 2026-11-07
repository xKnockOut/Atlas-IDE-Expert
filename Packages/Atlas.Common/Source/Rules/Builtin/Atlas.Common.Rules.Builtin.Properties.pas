unit Atlas.Common.Rules.Builtin.Properties;

// Regeln für Property-Deklarationen (#909, Gruppe Compiler vorab):
//   property-accessor-invalid  Hinter read/write steht nichts Passendes
//                              (#1001): Name fehlt in der Klasse und ihren
//                              Vorfahren (E2168) oder ist eine Property
//                              (E2168), Getter oder Setter mit falscher
//                              Signatur (E2008, früher E2234), Setter mit
//                              var-Parameter (E2282), überladene Zugriffsmethode
//                              ohne passende Überladung (E2250, früher E2271),
//                              Klassen-Property mit Instanzmitglied bzw.
//                              nicht statischer Klassenmethode (E2355) und
//                              umgekehrt bei class var und statischer
//                              Klassenmethode (E2356), Feld hinter
//                              einer Array-Property (E2008; Doku: E2174),
//                              Feldselektor über ein Feld, das kein Record ist
//                              (E2459), an einer Klassen-Property (E2459,
//                              #1380), auf ein Mitglied, das kein Feld ist
//                              (E2461), oder auf ein fehlendes Feld (E2562).
//                              Delphi 13 meldet falsche Signaturen und das Feld
//                              hinter einer Array-Property als E2008 (dcc-Lauf
//                              vom 29.10.2026, #1369).
//   default-property-invalid   default falsch (#1073): an einer Property ohne
//                              Index (E2132), zweite default-Property mit
//                              denselben Indextypen oder mit einem anderen
//                              Namen (E2131, #1380; überladene default-
//                              Properties gleichen Namens erlaubt dcc), Obj[I] auf einer
//                              Klasse ohne default-Property in ihrer ganzen
//                              Vorfahrenkette (E2149, Typ über TNameResolver).
//   property-redeclaration-invalid
//                              property Caption; ohne Property im Vorfahren
//                              (#1074, E2147, Korrektur: ähnlichster Name)
//                              oder dort nicht erreichbar (E2233).
//
// Die Regel liest read/write aus den Token der Property und sucht die Namen
// im Index der Datei und über TAncestry in den Vorfahren. Bricht die Kette der
// Vorfahren ab, steht der Name nur in einem inaktiven Zweig oder sieht die
// Klasse ihn nicht (private einer anderen Unit), bleibt sie still; ebenso in
// Klassen, die Include-Dateien einbinden. Typen vergleicht sie nur, wenn beide
// sicher für sich stehen (eingebaut oder als eigener Typ deklariert).
//
// Nicht strenger als dcc (#1328, Minimalfälle PA1–PA6 in Tests/DccFaelle): Eine
// index-Angabe verträgt ein Feld hinter read und write; der Indexparameter des
// Getters bzw. Setters hat den Typ der Indexkonstante (auch eine Aufzählung);
// eine Klassenmethode ohne static taugt als Getter einer Instanz-Property; von
// überladenen Zugriffsmethoden genügt eine passende Überladung.
//
// Korrektur: Folgt der fehlende Name der Konvention F<Name>, Get<Name> oder
// Set<Name>, legt "FName anlegen" bzw. "GetName anlegen" das Mitglied an
// (Erzeuger der Vervollständigung #467, completion.accessorSection).
//
// write-only-property (#978, Gruppe Stil und Metriken): Property mit write,
// aber ohne read. Properties ohne Typ (neu veröffentlicht, read vom Vorfahren)
// und mit einem Attribut aus allowAttributes bleiben außen vor. Korrektur
// "read FName ergänzen", wenn der Typ ein Feld FName gleichen Typs hat.

interface

uses
  System.SysUtils,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  cPropertyAccessorInvalidRuleId = 'property-accessor-invalid';
  cDefaultPropertyInvalidRuleId = 'default-property-invalid';
  cPropertyRedeclarationInvalidRuleId = 'property-redeclaration-invalid';
  cWriteOnlyPropertyRuleId = 'write-only-property';

type
  TPropertyAccessorInvalidRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TDefaultPropertyInvalidRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TPropertyRedeclarationInvalidRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TWriteOnlyPropertyRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

procedure RegisterPropertyRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.StrUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.DirectiveNames,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Rules.Options,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.Builtin.Inheritance,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.ClassActions,
  Atlas.Common.Editing.AccessorCreation,
  Atlas.Text.Fuzzy,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TPropertiesText = (NotRecord, NoField, NotInstanceField, ArrayNeedsMethod, ClassNeedsStatic, ClassVar,
    ClassSelector, Overloaded, NotStatic, ClassInstanceMethod, StaticClassMethod, SetterParam, SetterMismatch,
    GetterMismatch, Undeclared, IsProperty, AccessorTitle, DefaultExists, DefaultSameIndex, DefaultArrayOnly,
    NoDefault, DefaultTitle, NoPropertyMeant, UseName, NoProperty, Unreachable, RedeclaredTitle, AddRead, NoRead,
    WriteOnlyTitle);

const
  cTexts: array[TPropertiesText] of TAtlasText = (
    (De: '%s ist vom Typ %s, keinem Record; ein Feldselektor wie %s.%s geht nur über ein Record-Feld (wie E2459).';
     En: '%s is of type %s, not a record; a field selector like %s.%s works only through a record field (like E2459).'),
    (De: '%s hat kein Feld %s (wie E2562).'; En: '%s has no field %s (like E2562).'),
    (De: '%s.%s ist kein Instanzfeld; hinter dem Punkt muss ein Feld des Records stehen (wie E2461).';
     En: '%s.%s is not an instance field; a field of the record must follow the dot (like E2461).'),
    (De: 'Die Array-Property %s braucht hinter %s eine Methode; %s ist ein Feld (wie E2008).';
     En: 'The array property %s needs a method after %s; %s is a field (like E2008).'),
    (De: 'Die Klassen-Property %s braucht hinter %s eine class var oder eine class-Methode mit static; %s ist ein ' +
      'Instanzfeld (wie E2355).';
     En: 'The class property %s needs a class var or a static class method after %s; %s is an instance field (like ' +
      'E2355).'),
    (De: '%s ist eine class var; die Property %s braucht ein Instanzfeld oder eine Instanzmethode (wie E2356).';
     En: '%s is a class var; the property %s needs an instance field or an instance method (like E2356).'),
    (De: 'Die Klassen-Property %s darf hinter %s keinen Feldselektor haben; %s.%s geht nur an Instanz-Properties ' +
      '(wie E2459).';
     En: 'The class property %s must not have a field selector after %s; %s.%s works only on instance properties ' +
      '(like E2459).'),
    (De: '%s ist überladen, und keine Überladung passt als %s von %s (wie E2250).';
     En: '%s is overloaded, and no overload fits as %s of %s (like E2250).'),
    (De: 'Die Klassen-Property %s braucht eine class-Methode mit static; %s ist nicht static (wie E2355).';
     En: 'The class property %s needs a static class method; %s is not static (like E2355).'),
    (De: 'Die Klassen-Property %s braucht hinter %s eine class var oder eine class-Methode mit static; %s ist eine ' +
      'Instanzmethode (wie E2355).';
     En: 'The class property %s needs a class var or a static class method after %s; %s is an instance method (like ' +
      'E2355).'),
    (De: '%s ist eine statische Klassenmethode; die Property %s braucht ein Instanzfeld oder eine Instanzmethode ' +
      '(wie E2356).';
     En: '%s is a static class method; the property %s needs an instance field or an instance method (like E2356).'),
    (De: 'Der Setter %s nimmt den Wert als %s-Parameter; ein Setter braucht einen Wert- oder const-Parameter (wie ' +
      'E2282).';
     En: 'The setter %s takes the value as %s parameter; a setter needs a value or const parameter (like E2282).'),
    (De: '%s passt nicht als Setter von %s; erwartet wird %s (wie E2008).';
     En: '%s does not fit as setter of %s; expected is %s (like E2008).'),
    (De: '%s passt nicht als Getter von %s; erwartet wird %s (wie E2008).';
     En: '%s does not fit as getter of %s; expected is %s (like E2008).'),
    (De: '%s ist in %s nicht deklariert (wie E2168).'; En: '%s is not declared in %s (like E2168).'),
    (De: '%s ist eine Property; hinter %s gehört ein Feld oder eine Methode (wie E2168).';
     En: '%s is a property; a field or a method belongs after %s (like E2168).'),
    (De: 'Getter oder Setter einer Property ungültig'; En: 'Getter or setter of a property invalid'),
    (De: '%s hat schon die default-Property %s; eine Klasse hat höchstens eine default-Property, überladen nur unter ' +
      'demselben Namen (wie E2131).';
     En: '%s already has the default property %s; a class has at most one default property, overloaded only under ' +
      'the same name (like E2131).'),
    (De: '%s hat schon die default-Property %s mit denselben Indextypen (wie E2131).';
     En: '%s already has the default property %s with the same index types (like E2131).'),
    (De: 'default ist nur an Array-Properties erlaubt (wie E2132).';
     En: 'default is only allowed on array properties (like E2132).'),
    (De: '%s hat keine default-Property; %s[…] braucht eine (wie E2149).';
     En: '%s has no default property; %s[…] needs one (like E2149).'),
    (De: 'default-Property falsch deklariert oder fehlt'; En: 'default property declared incorrectly or missing'),
    (De: '%s hat keine Property %s; gemeint ist %s (wie E2147).';
     En: '%s has no property %s; %s is meant (like E2147).'),
    (De: '%s verwenden'; En: 'Use %s'),
    (De: '%s hat keine Property %s (wie E2147).'; En: '%s has no property %s (like E2147).'),
    (De: 'Die Property %s von %s ist hier nicht erreichbar (wie E2233).';
     En: 'The property %s of %s is not reachable here (like E2233).'),
    (De: 'Neu deklarierte Property fehlt im Vorfahren'; En: 'Newly declared property missing in the ancestor'),
    (De: 'read F%s ergänzen'; En: 'Add read F%s'),
    (De: 'Property %s hat kein read.'; En: 'Property %s has no read.'),
    (De: 'Property mit write, aber ohne read'; En: 'Property with write but without read'));

{$SCOPEDENUMS OFF}

type
  /// <summary>Ein Zugriff hinter read oder write: Name und Feldselektoren, Token von First bis Last.</summary>
  TPropertyAccessor = record
    IsWrite: Boolean;
    Name: string;
    Selectors: TArray<string>;
    First: Integer;
    Last: Integer;
  end;

  /// <summary>Gelesene Property: Indexparameter, Typtext, index-Angabe und Zugriffe.</summary>
  TPropertyShape = record
    Symbol: TIndexSymbol;
    /// <summary>Indexparameter ohne Klammern wie im Quelltext ("Index: Integer"); '' ohne.</summary>
    IndexText: string;
    /// <summary>Typ wie im Quelltext ("TList&lt;TKunde&gt;"); '' bei einer Property ohne Typ.</summary>
    TypeText: string;
    /// <summary>Die Property hat eine index-Angabe (index 3).</summary>
    HasIndex: Boolean;
    IsClass: Boolean;
    SingleLine: Boolean;
    Accessors: TArray<TPropertyAccessor>;
  end;

/// <summary>Bezeichner oder Schlüsselwort mit Text AWord (ohne Groß-/Kleinschreibung)?</summary>
function IsWord(const AToken: TPascalToken; const AWord: string): Boolean;
begin
  Result := (AToken.Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) and SameText(AToken.Text, AWord);
end;

/// <summary>Index der schließenden Klammer zur öffnenden bei AOpen; 0 ohne.</summary>
function ClosingParen(const ASignature: string; AOpen: Integer): Integer;
var
  mDepth, mIndex: Integer;
begin
  mDepth := 0;
  for mIndex := AOpen to Length(ASignature) do
  begin
    if ASignature[mIndex] = '(' then
    begin
      Inc(mDepth);
    end
    else if (ASignature[mIndex] = ')') and (mDepth = 1) then
    begin
      Exit(mIndex);
    end
    else if ASignature[mIndex] = ')' then
    begin
      Dec(mDepth);
    end;
  end;
  Result := 0;
end;

/// <summary>Parametergruppen ("const A, B: Integer") zwischen den Klammern AOpen und AClose.</summary>
function ParamGroups(const ASignature: string; AOpen, AClose: Integer): TArray<string>;
var
  mDepth, mIndex, mStart: Integer;
  mChar: Char;
begin
  Result := nil;
  mDepth := 0;
  mStart := AOpen + 1;
  for mIndex := AOpen + 1 to AClose do
  begin
    mChar := ASignature[mIndex];
    if CharInSet(mChar, ['(', '[', '<']) then
    begin
      Inc(mDepth);
    end
    else if CharInSet(mChar, [']', '>']) or ((mChar = ')') and (mIndex < AClose)) then
    begin
      Dec(mDepth);
    end
    else if ((mChar = ';') and (mDepth = 0)) or (mIndex = AClose) then
    begin
      Result := Result + [Trim(Copy(ASignature, mStart, mIndex - mStart))];
      mStart := mIndex + 1;
    end;
  end;
end;

/// <summary>Modifizierer einer Parametergruppe ('', const, var, out, constref); ACount: Zahl ihrer Namen.</summary>
function GroupModifier(const AGroup: string; out ACount: Integer): string;
var
  mHead: string;
begin
  mHead := AGroup;
  if Pos(':', mHead) > 0 then
  begin
    mHead := Copy(mHead, 1, Pos(':', mHead) - 1);
  end;
  mHead := Trim(mHead);
  Result := LowerCase(Copy(mHead, 1, Pos(' ', mHead + ' ') - 1));
  if MatchText(Result, ['const', 'var', 'out', 'constref']) then
  begin
    mHead := Trim(Copy(mHead, Length(Result) + 1, MaxInt));
  end
  else
  begin
    Result := '';
  end;
  ACount := Length(mHead.Split([',']));
end;

/// <summary>Modifizierer der Parameter einer Signatur in Reihenfolge ('', const, var, out, constref).</summary>
function ParamModifiers(const ASignature: string): TArray<string>;
var
  mOpen, mClose, mCount, mIndex: Integer;
  mGroup, mModifier: string;
begin
  Result := nil;
  mOpen := Pos('(', ASignature);
  if mOpen = 0 then
  begin
    Exit;
  end;
  mClose := ClosingParen(ASignature, mOpen);
  if mClose = 0 then
  begin
    Exit;
  end;
  for mGroup in ParamGroups(ASignature, mOpen, mClose) do
  begin
    mModifier := GroupModifier(mGroup, mCount);
    for mIndex := 1 to mCount do
    begin
      Result := Result + [mModifier];
    end;
  end;
end;

/// <summary>Quelltext von Token AFrom bis ATo (Code-Token).</summary>
function SourceText(const AText: string; const ATokens: TArray<TPascalToken>; AFrom, ATo: Integer): string;
begin
  Result := Trim(Copy(AText, ATokens[AFrom].Offset + 1, ATokens[ATo].Offset + Length(ATokens[ATo].Text) -
    ATokens[AFrom].Offset));
end;

/// <summary>Wort, das den Typ einer Property beendet (read, write, index, stored, default, nodefault,
/// implements)?</summary>
function IsPropertyWord(const AToken: TPascalToken): Boolean;
begin
  Result := (AToken.Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) and
    MatchText(AToken.Text, ['read', 'write', 'index', 'stored', 'default', 'nodefault', 'implements']);
end;

type
  /// <summary>Zustand beim Lesen einer Property ab dem Token "property".</summary>
  TPropertyParser = record
    Text: string;
    Tokens: TArray<TPascalToken>;
    Index: Integer;
    Depth: Integer;
    /// <summary>Token "[" der Indexparameter; -1 ohne.</summary>
    Bracket: Integer;
    /// <summary>Erstes Token des Typs; -1 vor dem Doppelpunkt.</summary>
    TypeStart: Integer;
    Shape: TPropertyShape;
    procedure Open;
    procedure Close;
    /// <summary>Typtext bis vor Index übernehmen, falls noch keiner steht.</summary>
    procedure EndType;
    procedure ReadAccessor;
    /// <summary>Token bei Index auf Klammertiefe 0; False beim abschließenden Semikolon.</summary>
    function TopLevel: Boolean;
  end;

procedure TPropertyParser.Open;
begin
  if (Depth = 0) and Tokens[Index].IsSymbol('[') and (TypeStart < 0) then
  begin
    Bracket := Index;
  end;
  Inc(Depth);
end;

procedure TPropertyParser.Close;
begin
  Dec(Depth);
  if (Depth = 0) and (Bracket >= 0) and (Shape.IndexText = '') and (Index > Bracket + 1) then
  begin
    Shape.IndexText := SourceText(Text, Tokens, Bracket + 1, Index - 1);
  end;
end;

procedure TPropertyParser.EndType;
begin
  if (TypeStart > 0) and (Shape.TypeText = '') and (Index > TypeStart) then
  begin
    Shape.TypeText := SourceText(Text, Tokens, TypeStart, Index - 1);
  end;
end;

procedure TPropertyParser.ReadAccessor;
var
  mAccessor: TPropertyAccessor;
begin
  mAccessor := Default(TPropertyAccessor);
  mAccessor.IsWrite := IsWord(Tokens[Index], 'write');
  Inc(Index);
  mAccessor.Name := Tokens[Index].Text;
  mAccessor.First := Index;
  while (Index + 2 <= High(Tokens)) and Tokens[Index + 1].IsSymbol('.') and
    (Tokens[Index + 2].Kind = TPascalTokenKind.Identifier) do
  begin
    Inc(Index, 2);
    mAccessor.Selectors := mAccessor.Selectors + [Tokens[Index].Text];
  end;
  mAccessor.Last := Index;
  Shape.Accessors := Shape.Accessors + [mAccessor];
end;

function TPropertyParser.TopLevel: Boolean;
var
  mToken: TPascalToken;
begin
  mToken := Tokens[Index];
  Result := not mToken.IsSymbol(';');
  if not Result then
  begin
    Exit;
  end;
  if mToken.IsSymbol(':') and (TypeStart < 0) then
  begin
    TypeStart := Index + 1;
  end
  else if IsPropertyWord(mToken) then
  begin
    EndType;
    if IsWord(mToken, 'index') then
    begin
      Shape.HasIndex := True;
    end
    else if (IsWord(mToken, 'read') or IsWord(mToken, 'write')) and (Index < High(Tokens)) and
      (Tokens[Index + 1].Kind = TPascalTokenKind.Identifier) then
    begin
      ReadAccessor;
    end;
  end;
end;

/// <summary>Property ab dem Token "property" an AStart lesen (ATokens ohne Kommentare); False ohne Namen.</summary>
function ParseProperty(const AText: string; const ATokens: TArray<TPascalToken>; AStart: Integer;
  out AShape: TPropertyShape): Boolean;
var
  mParser: TPropertyParser;
  mToken: TPascalToken;
begin
  AShape := Default(TPropertyShape);
  Result := (AStart + 1 <= High(ATokens)) and (ATokens[AStart + 1].Kind = TPascalTokenKind.Identifier);
  if not Result then
  begin
    Exit;
  end;
  mParser := Default(TPropertyParser);
  mParser.Text := AText;
  mParser.Tokens := ATokens;
  mParser.Index := AStart + 2;
  mParser.Bracket := -1;
  mParser.TypeStart := -1;
  while mParser.Index <= High(ATokens) do
  begin
    mToken := ATokens[mParser.Index];
    if mToken.IsSymbol('[') or mToken.IsSymbol('(') then
    begin
      mParser.Open;
    end
    else if mToken.IsSymbol(']') or mToken.IsSymbol(')') then
    begin
      mParser.Close;
    end
    else if (mParser.Depth = 0) and not mParser.TopLevel then
    begin
      Break;
    end;
    Inc(mParser.Index);
  end;
  if mParser.Index <= High(ATokens) then
  begin
    mParser.EndType;
  end;
  AShape := mParser.Shape;
  AShape.SingleLine := (mParser.Index <= High(ATokens)) and
    (ATokens[mParser.Index].StartPos.Line = ATokens[AStart].StartPos.Line);
end;

/// <summary>Bindet der Typ AType Include-Dateien ein (Direktive in seinem Bereich)? Dann kennt die Datei nicht
/// alle Mitglieder.</summary>
function TypeHasInclude(const ATokens: TArray<TPascalToken>; const AType: TIndexSymbol): Boolean;
var
  mToken: TPascalToken;
  mName: string;
begin
  for mToken in ATokens do
  begin
    if (mToken.Kind = TPascalTokenKind.Directive) and (mToken.StartPos.Line >= AType.Range.StartPos.Line) and
      (mToken.StartPos.Line <= AType.Range.EndPos.Line) then
    begin
      mName := TDirectiveNames.LeadingName(TDirectiveNames.Body(mToken.Text));
      if SameText(mName, 'I') or SameText(mName, 'INCLUDE') then
      begin
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

/// <summary>Typparameter der Klasse und ihrer Vorfahren: Sie passen zu jedem Typ.</summary>
function Wildcards(const AChain: TArray<TSymbolLocation>): TArray<string>;
var
  mLocation: TSymbolLocation;
  mName: string;
begin
  Result := nil;
  for mLocation in AChain do
  begin
    for mName in mLocation.Symbol.TypeParams.Split([',']) do
    begin
      if Trim(mName) <> '' then
      begin
        Result := Result + [Trim(mName)];
      end;
    end;
  end;
end;

/// <summary>'read' bzw. 'write'.</summary>
function ClauseOf(const AAccessor: TPropertyAccessor): string;
begin
  if AAccessor.IsWrite then
  begin
    Result := 'write';
  end
  else
  begin
    Result := 'read';
  end;
end;

type
{$SCOPEDENUMS ON}
  /// <summary>Ergebnis der Suche nach einem Mitglied: fehlt, gefunden, nur in einem inaktiven Zweig.</summary>
  TMemberLookup = (Missing, Found, Unknown);
{$SCOPEDENUMS OFF}

  /// <summary>Ein Lauf von property-accessor-invalid über eine Datei; FShape, FChain, FComplete und FWildcards
  /// beschreiben die gerade geprüfte Property.</summary>
  TAccessorScan = class
  private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FCache: IRuleDerivedCache;
    FTokens: TArray<TPascalToken>;
    FAncestry: TAncestry;
    FActions: TClassActionContext;
    FShape: TPropertyShape;
    FChain: TArray<TSymbolLocation>;
    FComplete: Boolean;
    FWildcards: TArray<string>;
    function Range(const AAccessor: TPropertyAccessor): TTextRange;
    procedure Add(const AAccessor: TPropertyAccessor; const AMessage: string);
    /// <summary>Sieht die Klasse ASymbol auf der Stufe ALevel nicht (strict private, private einer anderen Unit)?
    /// </summary>
    function IsHidden(ALevel: Integer; const ASymbol: TIndexSymbol): Boolean;
    /// <summary>Mitglieder namens AName auf der Stufe ALevel nach AFound; AAny: es gibt dort eines. False, wenn
    /// eines nur in einem inaktiven Zweig steht.</summary>
    function LevelMembers(ALevel: Integer; const AName: string; var AFound: TArray<TIndexSymbol>;
      out AAny: Boolean): Boolean;
    /// <summary>Mitglieder namens AName auf der nächsten Stufe der Kette, die es dort gibt. False, wenn keine
    /// Aussage möglich ist (Kette bricht ab, nur in inaktivem Zweig, für die Klasse unsichtbar).</summary>
    function Lookup(const AName: string; out AFound: TArray<TIndexSymbol>): Boolean;
    /// <summary>Korrektur "F/Get/SetName anlegen", wenn der fehlende Name der Konvention folgt.</summary>
    function CreateFixes(const AAccessor: TPropertyAccessor): TArray<TRuleFix>;
    /// <summary>Erwarteter Kopf der Zugriffsmethode, z. B. "function GetName(Index: Integer): string".</summary>
    function Expected(const AAccessor: TPropertyAccessor): string;
    /// <summary>Gleicher Typ oder einer der beiden nicht sicher bekannt?</summary>
    function SameOrOpen(const A, B: string): Boolean;
    /// <summary>Passt die Methode AMethod als Getter bzw. Setter? Typen zählen nur, wenn beide sicher sind.</summary>
    function Fits(const AAccessor: TPropertyAccessor; const AMethod: TIndexSymbol): Boolean;
    /// <summary>Record-Typ hinter dem Feld AField; False ohne sichere Aussage.</summary>
    function FieldType(const AField: TIndexSymbol; out ALocation: TSymbolLocation): Boolean;
    function FindMember(const ALocation: TSymbolLocation; const AName: string; out AHit: TIndexSymbol): TMemberLookup;
    /// <summary>Selektor ASelector hinter APath (Feld AField) prüfen; True: weiter mit dem Feld AHit, sonst Ende
    /// mit oder ohne Meldung.</summary>
    function SelectorStep(const AAccessor: TPropertyAccessor; const APath, ASelector: string;
      const AField: TIndexSymbol; out AHit: TIndexSymbol): Boolean;
    /// <summary>Feldselektoren ab dem Feld AField prüfen und einen Fehler melden.</summary>
    procedure CheckSelectors(const AAccessor: TPropertyAccessor; const AField: TIndexSymbol);
    procedure CheckField(const AAccessor: TPropertyAccessor; const AField: TIndexSymbol);
    /// <summary>Wählt bei Überladungen die passende nach AMethod; False, wenn keine passt (mit Meldung) oder das
    /// ohne Typ offen ist.</summary>
    function FittingOverload(const AAccessor: TPropertyAccessor; const AFound: TArray<TIndexSymbol>;
      var AMethod: TIndexSymbol): Boolean;
    /// <summary>Meldet Klassen- gegen Instanzmethode (E2355, E2356); True mit Meldung.</summary>
    function ReportsClassMismatch(const AAccessor: TPropertyAccessor; const AMethod: TIndexSymbol): Boolean;
    /// <summary>Meldet einen Setter mit var- oder out-Parameter (E2282); True mit Meldung.</summary>
    function ReportsVarSetter(const AAccessor: TPropertyAccessor; const AMethod: TIndexSymbol): Boolean;
    procedure CheckMethod(const AAccessor: TPropertyAccessor; const AMethod: TIndexSymbol);
    procedure CheckAccessor(const AAccessor: TPropertyAccessor);
    /// <summary>Index-Symbol der Property am Token AStart nach FShape.Symbol; False ohne bzw. inaktiv.</summary>
    function FindSymbol(AStart: Integer): Boolean;
    /// <summary>Typ der Property, sofern in dieser Datei und ohne Include-Dateien.</summary>
    function FindOwner(out AOwner: TSymbolLocation): Boolean;
    procedure CheckProperty(AStart: Integer);
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    destructor Destroy; override;
    procedure Run;
  end;

constructor TAccessorScan.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
  FCache := TRuleDerived.Open(AContext);
  FTokens := TRuleDerived.CodeTokens(FCache, AContext);
  FAncestry := TAncestry.Create(AContext.Index, TRuleDerived.UnitIndex(FCache, AContext));
  FActions := TClassActionContext.Default;
  FActions.Index := AContext.Index;
  FActions.Namespaces := AContext.Namespaces;
  FActions.DelphiVersion := AContext.DelphiVersion;
  FActions.Style := AContext.Formatting;
end;

destructor TAccessorScan.Destroy;
begin
  FAncestry.Free;
  inherited;
end;

function TAccessorScan.Range(const AAccessor: TPropertyAccessor): TTextRange;
begin
  Result := TTextRange.Create(FTokens[AAccessor.First].StartPos, FTokens[AAccessor.Last].EndPos);
end;

procedure TAccessorScan.Add(const AAccessor: TPropertyAccessor; const AMessage: string);
begin
  FReport.Add(Range(AAccessor), AMessage, TRuleConfidence.High);
end;

function TAccessorScan.IsHidden(ALevel: Integer; const ASymbol: TIndexSymbol): Boolean;
begin
  // strict private sieht kein Nachfahre, private nur einer in derselben Unit.
  Result := (ALevel > 0) and ((ASymbol.Visibility = TIndexVisibility.StrictPrivate) or
    ((FChain[ALevel].FileName <> '') and (ASymbol.Visibility = TIndexVisibility.Private)));
end;

function TAccessorScan.LevelMembers(ALevel: Integer; const AName: string; var AFound: TArray<TIndexSymbol>;
  out AAny: Boolean): Boolean;
var
  mSymbol: TIndexSymbol;
begin
  AAny := False;
  for mSymbol in FAncestry.Members(FChain[ALevel]) do
  begin
    if not SameText(mSymbol.Name, AName) then
    begin
      Continue;
    end;
    AAny := True;
    if mSymbol.Unavailable then
    begin
      Exit(False);
    end;
    if not IsHidden(ALevel, mSymbol) then
    begin
      AFound := AFound + [mSymbol];
    end;
  end;
  Result := True;
end;

function TAccessorScan.Lookup(const AName: string; out AFound: TArray<TIndexSymbol>): Boolean;
var
  mLevel: Integer;
  mAny: Boolean;
begin
  AFound := nil;
  for mLevel := 0 to High(FChain) do
  begin
    if not LevelMembers(mLevel, AName, AFound, mAny) then
    begin
      Exit(False);
    end;
    if mAny then
    begin
      Exit(AFound <> nil);
    end;
  end;
  Result := FComplete;
end;

function TAccessorScan.CreateFixes(const AAccessor: TPropertyAccessor): TArray<TRuleFix>;
var
  mPlan: TAccessorPlan;
  mAction: TCodeAction;
begin
  Result := nil;
  if (AAccessor.Selectors <> nil) or FShape.IsClass or not FShape.SingleLine or (FShape.TypeText = '') then
  begin
    Exit;
  end;
  mPlan := Default(TAccessorPlan);
  mPlan.PropertyName := FShape.Symbol.Name;
  mPlan.PropertyType := FShape.TypeText;
  mPlan.IndexParameters := FShape.IndexText;
  if FShape.HasIndex then
  begin
    if mPlan.IndexParameters <> '' then
    begin
      mPlan.IndexParameters := mPlan.IndexParameters + '; ';
    end;
    mPlan.IndexParameters := mPlan.IndexParameters + 'AIndex: Integer';
  end;
  mPlan.MethodSection := 'private';
  if FContext.AccessorsProtected then
  begin
    mPlan.MethodSection := 'protected';
  end;
  if SameText(AAccessor.Name, mPlan.FieldName) and (mPlan.IndexParameters = '') then
  begin
    mPlan.Kind := TAccessorKind.Field;
  end
  else if not AAccessor.IsWrite and SameText(AAccessor.Name, 'Get' + mPlan.PropertyName) then
  begin
    mPlan.Kind := TAccessorKind.Getter;
  end
  else if AAccessor.IsWrite and SameText(AAccessor.Name, 'Set' + mPlan.PropertyName) then
  begin
    mPlan.Kind := TAccessorKind.Setter;
  end
  else
  begin
    Exit;
  end;
  if TClassActions.CreateAccessor(FContext.Text, FTokens[AAccessor.First].StartPos.Line, mPlan, FActions,
    mAction) then
  begin
    Result := [TRuleFix.Create(mAction.Title, mAction.Edits)];
  end;
end;

function TAccessorScan.Expected(const AAccessor: TPropertyAccessor): string;
var
  mParams: string;
begin
  mParams := FShape.IndexText;
  if FShape.HasIndex then
  begin
    if mParams <> '' then
    begin
      mParams := mParams + '; ';
    end;
    mParams := mParams + 'AIndex: Integer';
  end;
  if AAccessor.IsWrite then
  begin
    if mParams <> '' then
    begin
      mParams := mParams + '; ';
    end;
    Result := Format('procedure %s(%sconst Value: %s)', [AAccessor.Name, mParams, FShape.TypeText]);
  end
  else if mParams <> '' then
  begin
    Result := Format('function %s(%s): %s', [AAccessor.Name, mParams, FShape.TypeText]);
  end
  else
  begin
    Result := Format('function %s: %s', [AAccessor.Name, FShape.TypeText]);
  end;
  if FShape.IsClass then
  begin
    Result := 'class ' + Result + '; static';
  end;
end;

function TAccessorScan.SameOrOpen(const A, B: string): Boolean;
begin
  Result := FAncestry.SameType(A, B, FWildcards) or (A = '') or (B = '') or not FAncestry.KnownType(A) or
    not FAncestry.KnownType(B);
end;

function TAccessorScan.Fits(const AAccessor: TPropertyAccessor; const AMethod: TIndexSymbol): Boolean;
var
  mWanted: TArray<string>;
  mIndex: Integer;
  mKeyword: string;
begin
  mWanted := Copy(FShape.Symbol.ParamTypes);
  // Der Indexparameter hat den Typ der Indexkonstante (index aZwei: Aufzählung, PA4); '' passt zu jedem Typ.
  if FShape.HasIndex then
  begin
    mWanted := mWanted + [''];
  end;
  if AAccessor.IsWrite then
  begin
    mWanted := mWanted + [FShape.Symbol.TypeName];
  end;
  mKeyword := LowerCase(AMethod.Signature);
  if StartsStr('class ', mKeyword) then
  begin
    mKeyword := Trim(Copy(mKeyword, 7, MaxInt));
  end;
  if AAccessor.IsWrite then
  begin
    Result := StartsStr('procedure', mKeyword);
  end
  else
  begin
    Result := StartsStr('function', mKeyword);
  end;
  Result := Result and (AMethod.MaxArgs = Length(mWanted)) and (Length(AMethod.ParamTypes) = Length(mWanted));
  for mIndex := 0 to High(mWanted) do
  begin
    Result := Result and SameOrOpen(mWanted[mIndex], AMethod.ParamTypes[mIndex]);
  end;
  if Result and not AAccessor.IsWrite then
  begin
    Result := SameOrOpen(FShape.Symbol.TypeName, AMethod.TypeName);
  end;
end;

function TAccessorScan.FieldType(const AField: TIndexSymbol; out ALocation: TSymbolLocation): Boolean;
var
  mName: string;
begin
  mName := Copy(AField.TypeName, LastDelimiter('.', AField.TypeName) + 1, MaxInt);
  // Geschachtelte Typen der eigenen Klasse zuerst: private type TParts = record neben einer Klasse TParts anderswo.
  Result := (AField.TypeName <> '') and (AField.TypeArgs = '') and
    (FAncestry.FindNestedType(AField.Container, mName, ALocation) or FAncestry.FindAnyType(mName, ALocation)) and
    (ALocation.Symbol.Kind <> TIndexSymbolKind.TypeAlias);
end;

function TAccessorScan.FindMember(const ALocation: TSymbolLocation; const AName: string;
  out AHit: TIndexSymbol): TMemberLookup;
var
  mMember: TIndexSymbol;
begin
  AHit := Default(TIndexSymbol);
  for mMember in FAncestry.Members(ALocation) do
  begin
    if SameText(mMember.Name, AName) then
    begin
      AHit := mMember;
      if mMember.Unavailable then
      begin
        Exit(TMemberLookup.Unknown);
      end;
      Exit(TMemberLookup.Found);
    end;
  end;
  Result := TMemberLookup.Missing;
end;

function TAccessorScan.SelectorStep(const AAccessor: TPropertyAccessor; const APath, ASelector: string;
  const AField: TIndexSymbol; out AHit: TIndexSymbol): Boolean;
var
  mLocation: TSymbolLocation;
  mLookup: TMemberLookup;
begin
  Result := False;
  AHit := Default(TIndexSymbol);
  if not FieldType(AField, mLocation) then
  begin
    Exit;
  end;
  if mLocation.Symbol.Kind <> TIndexSymbolKind.RecordType then
  begin
    Add(AAccessor, cTexts[TPropertiesText.NotRecord].Fmt([APath, AField.TypeName, APath, ASelector]));
    Exit;
  end;
  mLookup := FindMember(mLocation, ASelector, AHit);
  if mLookup = TMemberLookup.Missing then
  begin
    Add(AAccessor, cTexts[TPropertiesText.NoField].Fmt([mLocation.Symbol.Name, ASelector]));
  end
  else if (mLookup = TMemberLookup.Found) and ((AHit.Kind <> TIndexSymbolKind.Field) or AHit.HasDirective('class'))
    then
  begin
    Add(AAccessor, cTexts[TPropertiesText.NotInstanceField].Fmt([mLocation.Symbol.Name, AHit.Name]));
  end
  else
  begin
    Result := mLookup = TMemberLookup.Found;
  end;
end;

procedure TAccessorScan.CheckSelectors(const AAccessor: TPropertyAccessor; const AField: TIndexSymbol);
var
  mCurrent, mHit: TIndexSymbol;
  mPath: string;
  mIndex: Integer;
begin
  mCurrent := AField;
  mPath := AAccessor.Name;
  mIndex := 0;
  while (mIndex <= High(AAccessor.Selectors)) and SelectorStep(AAccessor, mPath, AAccessor.Selectors[mIndex],
    mCurrent, mHit) do
  begin
    mCurrent := mHit;
    mPath := mPath + '.' + AAccessor.Selectors[mIndex];
    Inc(mIndex);
  end;
end;

procedure TAccessorScan.CheckField(const AAccessor: TPropertyAccessor; const AField: TIndexSymbol);
var
  mClause: string;
begin
  mClause := ClauseOf(AAccessor);
  // Mit index-Angabe nimmt dcc ein Feld hinter read und write an (PA1–PA3, mORMot2, SynEdit).
  if FShape.Symbol.MaxArgs > 0 then
  begin
    Add(AAccessor, cTexts[TPropertiesText.ArrayNeedsMethod].Fmt([FShape.Symbol.Name, mClause, AField.Name]));
  end
  else if FShape.IsClass and not AField.HasDirective('class') then
  begin
    Add(AAccessor, cTexts[TPropertiesText.ClassNeedsStatic].Fmt([FShape.Symbol.Name, mClause, AField.Name]));
  end
  else if not FShape.IsClass and AField.HasDirective('class') then
  begin
    Add(AAccessor, cTexts[TPropertiesText.ClassVar].Fmt([AField.Name, FShape.Symbol.Name]));
  end
  // Klassen-Properties lesen und schreiben nur ganze class vars (Cm.E2459, #1380).
  else if FShape.IsClass and (AAccessor.Selectors <> nil) then
  begin
    Add(AAccessor, cTexts[TPropertiesText.ClassSelector].Fmt([FShape.Symbol.Name, mClause, AField.Name,
      string.Join('.', AAccessor.Selectors)]));
  end
  else
  begin
    CheckSelectors(AAccessor, AField);
  end;
end;

function TAccessorScan.FittingOverload(const AAccessor: TPropertyAccessor; const AFound: TArray<TIndexSymbol>;
  var AMethod: TIndexSymbol): Boolean;
var
  mCandidate: TIndexSymbol;
  mRole: string;
begin
  // Von Überladungen nimmt dcc die passende (PA6, Graphics32); ohne Typ der Property ist das offen.
  if Length(AFound) <= 1 then
  begin
    Exit(True);
  end;
  Result := False;
  if FShape.TypeText = '' then
  begin
    Exit;
  end;
  for mCandidate in AFound do
  begin
    if Fits(AAccessor, mCandidate) then
    begin
      AMethod := mCandidate;
      Exit(True);
    end;
  end;
  mRole := 'Getter';
  if AAccessor.IsWrite then
  begin
    mRole := 'Setter';
  end;
  // Delphi 13 meldet E2250 (PG3, #1382).
  Add(AAccessor, cTexts[TPropertiesText.Overloaded].Fmt([AMethod.Name, mRole, FShape.Symbol.Name]));
end;

function TAccessorScan.ReportsClassMismatch(const AAccessor: TPropertyAccessor; const AMethod: TIndexSymbol): Boolean;
var
  mClass, mStatic: Boolean;
begin
  mClass := AMethod.HasDirective('class');
  mStatic := AMethod.HasDirective('static');
  Result := FShape.IsClass and not (mClass and mStatic);
  if Result and mClass then
  begin
    Add(AAccessor, cTexts[TPropertiesText.NotStatic].Fmt([FShape.Symbol.Name, AMethod.Name]));
  end
  else if Result then
  begin
    Add(AAccessor, cTexts[TPropertiesText.ClassInstanceMethod].Fmt([FShape.Symbol.Name, ClauseOf(AAccessor),
      AMethod.Name]));
  end
  // Eine Klassenmethode ohne static taugt als Getter einer Instanz-Property (PA5, HtmlViewer, Graphics32);
  // eine statische hat kein Self.
  else if not FShape.IsClass and mClass and mStatic then
  begin
    Result := True;
    Add(AAccessor, cTexts[TPropertiesText.StaticClassMethod].Fmt([AMethod.Name, FShape.Symbol.Name]));
  end;
end;

function TAccessorScan.ReportsVarSetter(const AAccessor: TPropertyAccessor; const AMethod: TIndexSymbol): Boolean;
var
  mModifiers: TArray<string>;
  mModifier: string;
begin
  Result := False;
  if not AAccessor.IsWrite then
  begin
    Exit;
  end;
  mModifiers := ParamModifiers(AMethod.Signature);
  if mModifiers = nil then
  begin
    Exit;
  end;
  mModifier := mModifiers[High(mModifiers)];
  Result := MatchText(mModifier, ['var', 'out']);
  if Result then
  begin
    Add(AAccessor, cTexts[TPropertiesText.SetterParam].Fmt([AMethod.Name, mModifier]));
  end;
end;

procedure TAccessorScan.CheckMethod(const AAccessor: TPropertyAccessor; const AMethod: TIndexSymbol);
begin
  // Ohne Typ übernimmt die Property Typ und Indexparameter vom Vorfahren.
  if ReportsClassMismatch(AAccessor, AMethod) or ReportsVarSetter(AAccessor, AMethod) or
    (FShape.TypeText = '') or Fits(AAccessor, AMethod) then
  begin
    Exit;
  end;
  // Delphi 13 meldet die falsche Signatur als E2008 (Fall Cm.E2234, PG2, #1382).
  if AAccessor.IsWrite then
  begin
    Add(AAccessor, cTexts[TPropertiesText.SetterMismatch].Fmt([AMethod.Name, FShape.Symbol.Name, Expected(AAccessor)]));
  end
  else
  begin
    Add(AAccessor, cTexts[TPropertiesText.GetterMismatch].Fmt([AMethod.Name, FShape.Symbol.Name, Expected(AAccessor)]));
  end;
end;

procedure TAccessorScan.CheckAccessor(const AAccessor: TPropertyAccessor);
var
  mFound: TArray<TIndexSymbol>;
  mSymbol: TIndexSymbol;
begin
  if not Lookup(AAccessor.Name, mFound) then
  begin
    Exit;
  end;
  if mFound = nil then
  begin
    FReport.Add(Range(AAccessor), cTexts[TPropertiesText.Undeclared].Fmt([AAccessor.Name,
      FChain[0].Symbol.Name]), TRuleConfidence.High, CreateFixes(AAccessor));
    Exit;
  end;
  mSymbol := mFound[0];
  if mSymbol.Kind = TIndexSymbolKind.Property_ then
  begin
    Add(AAccessor, cTexts[TPropertiesText.IsProperty].Fmt([mSymbol.Name, ClauseOf(AAccessor)]));
  end
  else if mSymbol.Kind = TIndexSymbolKind.Field then
  begin
    CheckField(AAccessor, mSymbol);
  end
  // Methode (ein Konstruktor ist nie ein passender Getter oder Setter).
  else if (AAccessor.Selectors = nil) and FittingOverload(AAccessor, mFound, mSymbol) then
  begin
    CheckMethod(AAccessor, mSymbol);
  end;
end;

function TAccessorScan.FindSymbol(AStart: Integer): Boolean;
var
  mSymbol: TIndexSymbol;
  mAt: TTextPosition;
begin
  mAt := FTokens[AStart].StartPos;
  for mSymbol in FAncestry.Local.Symbols do
  begin
    if (mSymbol.Kind = TIndexSymbolKind.Property_) and (mSymbol.Container <> '') and
      (mSymbol.Range.StartPos.Line = mAt.Line) and (mSymbol.Range.StartPos.Character = mAt.Character) then
    begin
      FShape.Symbol := mSymbol;
      Exit(not mSymbol.Unavailable);
    end;
  end;
  Result := False;
end;

function TAccessorScan.FindOwner(out AOwner: TSymbolLocation): Boolean;
begin
  Result := FAncestry.FindAnyType(FShape.Symbol.Container, AOwner) and (AOwner.FileName = '') and
    (AOwner.Symbol.Kind in [TIndexSymbolKind.ClassType, TIndexSymbolKind.RecordType, TIndexSymbolKind.ObjectType])
    and not TypeHasInclude(FContext.Tree.Tokens, AOwner.Symbol);
end;

procedure TAccessorScan.CheckProperty(AStart: Integer);
var
  mOwner: TSymbolLocation;
  mObjectMissing: Boolean;
  mAccessor: TPropertyAccessor;
begin
  if not ParseProperty(FContext.Text, FTokens, AStart, FShape) or (FShape.Accessors = nil) or
    not FindSymbol(AStart) then
  begin
    Exit;
  end;
  FShape.IsClass := FShape.Symbol.HasDirective('class');
  if not FindOwner(mOwner) then
  begin
    Exit;
  end;
  FChain := [mOwner];
  FComplete := True;
  if mOwner.Symbol.Kind = TIndexSymbolKind.ClassType then
  begin
    FChain := FChain + FAncestry.Ancestors(mOwner.Symbol.Name, FComplete, mObjectMissing);
  end;
  FWildcards := Wildcards(FChain);
  for mAccessor in FShape.Accessors do
  begin
    CheckAccessor(mAccessor);
  end;
end;

procedure TAccessorScan.Run;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(FTokens) do
  begin
    if IsWord(FTokens[mIndex], 'property') then
    begin
      CheckProperty(mIndex);
    end;
  end;
end;

{ TPropertyAccessorInvalidRule }

function TPropertyAccessorInvalidRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cPropertyAccessorInvalidRuleId, TRuleSeverity.Error,
    cTexts[TPropertiesText.AccessorTitle].Text);
end;

procedure TPropertyAccessorInvalidRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mScan: TAccessorScan;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  mScan := TAccessorScan.Create(AContext, AReport);
  try
    mScan.Run;
  finally
    mScan.Free;
  end;
end;

/// <summary>Property mit default-Angabe in einem Typ, aktiv?</summary>
function IsDefaultProperty(const ASymbol: TIndexSymbol): Boolean;
begin
  Result := (ASymbol.Kind = TIndexSymbolKind.Property_) and ASymbol.IsDefault and (ASymbol.Container <> '') and
    not ASymbol.Unavailable;
end;

/// <summary>Zwei default-Properties desselben Typs mit Typ und ohne Bedingung: vergleichbar?</summary>
function Comparable(const AEarlier, ASymbol: TIndexSymbol): Boolean;
begin
  Result := SameText(AEarlier.Container, ASymbol.Container) and (ASymbol.TypeName <> '') and
    (AEarlier.TypeName <> '') and (AEarlier.Condition = '') and (ASymbol.Condition = '');
end;

type
  /// <summary>Ein Lauf von default-property-invalid über eine Datei.</summary>
  TDefaultPropertyScan = class
  private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FCache: IRuleDerivedCache;
    FTokens: TArray<TPascalToken>;
    FAncestry: TAncestry;
    FResolver: TNameResolver;
    FFileName: string;
    /// <summary>Token "default" hinter dem Semikolon der Property ASymbol; -1 ohne.</summary>
    function DefaultToken(const ASymbol: TIndexSymbol): Integer;
    function SameIndexTypes(const A, B: TIndexSymbol): Boolean;
    /// <summary>Meldet E2131, wenn ASymbol mit der früheren default-Property AEarlier kollidiert.</summary>
    function ReportsConflict(const ARange: TTextRange; const AEarlier, ASymbol: TIndexSymbol): Boolean;
    procedure CheckDeclaration(const ASymbol: TIndexSymbol; var ASeen: TArray<TIndexSymbol>);
    /// <summary>E2132 (default an einer Property ohne Index) und E2131 (zweite default-Property mit gleichen
    /// Indextypen) aus dem Index der Datei.</summary>
    procedure CheckDeclarations;
    function ChainHasDefault(const AChain: TArray<TSymbolLocation>): Boolean;
    /// <summary>Könnte ein Class-Helper der Datei die default-Property für einen Typ der Kette liefern?</summary>
    function HelperMayProvide(const AChain: TArray<TSymbolLocation>): Boolean;
    /// <summary>Hat die Klasse ATypeName (oder ein Vorfahr) eine default-Property? False ohne sichere Aussage.
    /// </summary>
    function LacksDefault(const ATypeName: string): Boolean;
    /// <summary>E2149: Obj[I] auf einer Klasse ohne default-Property.</summary>
    procedure CheckAccess(ANode: TSyntaxNode);
    procedure VisitBodies;
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    destructor Destroy; override;
    procedure Run;
  end;

constructor TDefaultPropertyScan.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
  FCache := TRuleDerived.Open(AContext);
  FTokens := TRuleDerived.CodeTokens(FCache, AContext);
  FFileName := AContext.FileName;
  if FFileName = '' then
  begin
    FFileName := AContext.RelativePath;
  end;
  if FFileName = '' then
  begin
    FFileName := AContext.UnitName + '.pas';
  end;
  FAncestry := TAncestry.Create(AContext.Index, TRuleDerived.UnitIndex(FCache, AContext));
end;

destructor TDefaultPropertyScan.Destroy;
begin
  FAncestry.Free;
  inherited;
end;

function TDefaultPropertyScan.DefaultToken(const ASymbol: TIndexSymbol): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(FTokens) - 1 do
  begin
    if (FTokens[mIndex].StartPos.Line >= ASymbol.Range.StartPos.Line) and
      (FTokens[mIndex].StartPos.Line <= ASymbol.Range.EndPos.Line) and FTokens[mIndex].IsSymbol(';') and
      IsWord(FTokens[mIndex + 1], 'default') then
    begin
      Exit(mIndex + 1);
    end;
  end;
  Result := -1;
end;

function TDefaultPropertyScan.SameIndexTypes(const A, B: TIndexSymbol): Boolean;
var
  mIndex: Integer;
begin
  Result := Length(A.ParamTypes) = Length(B.ParamTypes);
  mIndex := 0;
  while Result and (mIndex <= High(A.ParamTypes)) do
  begin
    Result := FAncestry.SameType(A.ParamTypes[mIndex], B.ParamTypes[mIndex], nil);
    Inc(mIndex);
  end;
end;

function TDefaultPropertyScan.ReportsConflict(const ARange: TTextRange; const AEarlier,
  ASymbol: TIndexSymbol): Boolean;
begin
  Result := Comparable(AEarlier, ASymbol);
  if not Result then
  begin
    Exit;
  end;
  // Überladene default-Properties gleichen Namens unterscheiden sich in den Indextypen; zwei verschiedene Namen
  // lässt dcc nie zu (Cm.E2131, #1380).
  if not SameText(AEarlier.Name, ASymbol.Name) then
  begin
    FReport.Add(ARange, cTexts[TPropertiesText.DefaultExists].Fmt([ASymbol.Container, AEarlier.Name]),
      TRuleConfidence.High);
  end
  else if SameIndexTypes(AEarlier, ASymbol) then
  begin
    FReport.Add(ARange, cTexts[TPropertiesText.DefaultSameIndex].Fmt(
      [ASymbol.Container, AEarlier.Name]), TRuleConfidence.High);
  end
  else
  begin
    Result := False;
  end;
end;

procedure TDefaultPropertyScan.CheckDeclaration(const ASymbol: TIndexSymbol; var ASeen: TArray<TIndexSymbol>);
var
  mToken: Integer;
  mRange: TTextRange;
  mEarlier: TIndexSymbol;
begin
  mToken := DefaultToken(ASymbol);
  if mToken < 0 then
  begin
    Exit;
  end;
  mRange := TTextRange.Create(FTokens[mToken].StartPos, FTokens[mToken].EndPos);
  // Ohne Typ übernimmt eine Neudeklaration (property Items; default;) die Indexparameter des Vorfahren.
  if (ASymbol.MaxArgs = 0) and (ASymbol.TypeName <> '') then
  begin
    FReport.Add(mRange, cTexts[TPropertiesText.DefaultArrayOnly].Text, TRuleConfidence.High);
    Exit;
  end;
  for mEarlier in ASeen do
  begin
    if ReportsConflict(mRange, mEarlier, ASymbol) then
    begin
      Break;
    end;
  end;
  ASeen := ASeen + [ASymbol];
end;

procedure TDefaultPropertyScan.CheckDeclarations;
var
  mSymbol: TIndexSymbol;
  mSeen: TArray<TIndexSymbol>;
begin
  mSeen := nil;
  for mSymbol in FAncestry.Local.Symbols do
  begin
    if IsDefaultProperty(mSymbol) then
    begin
      CheckDeclaration(mSymbol, mSeen);
    end;
  end;
end;

function TDefaultPropertyScan.ChainHasDefault(const AChain: TArray<TSymbolLocation>): Boolean;
var
  mLocation: TSymbolLocation;
  mMember: TIndexSymbol;
begin
  for mLocation in AChain do
  begin
    for mMember in FAncestry.Members(mLocation) do
    begin
      if (mMember.Kind = TIndexSymbolKind.Property_) and mMember.IsDefault then
      begin
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

/// <summary>Nennt die Signatur des Helpers AHelper einen Typ der Kette AChain?</summary>
function HelperNames(const AHelper: TIndexSymbol; const AChain: TArray<TSymbolLocation>): Boolean;
var
  mLocation: TSymbolLocation;
begin
  for mLocation in AChain do
  begin
    if ContainsText(' ' + AHelper.Signature + ' ', ' ' + mLocation.Symbol.Name + ' ') or
      ContainsText(AHelper.Signature, ' ' + mLocation.Symbol.Name + ')') then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TDefaultPropertyScan.HelperMayProvide(const AChain: TArray<TSymbolLocation>): Boolean;
var
  mSymbol: TIndexSymbol;
begin
  for mSymbol in FAncestry.Local.Symbols do
  begin
    if (mSymbol.Kind = TIndexSymbolKind.HelperType) and HelperNames(mSymbol, AChain) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TDefaultPropertyScan.LacksDefault(const ATypeName: string): Boolean;
var
  mOwn: TSymbolLocation;
  mChain: TArray<TSymbolLocation>;
  mComplete, mObjectMissing: Boolean;
begin
  Result := False;
  if not FAncestry.FindClass(ATypeName, mOwn) or (mOwn.Symbol.Kind <> TIndexSymbolKind.ClassType) then
  begin
    Exit;
  end;
  mChain := [mOwn] + FAncestry.Ancestors(mOwn.Symbol.Name, mComplete, mObjectMissing);
  Result := mComplete and not ChainHasDefault(mChain) and not HelperMayProvide(mChain);
end;

procedure TDefaultPropertyScan.CheckAccess(ANode: TSyntaxNode);
var
  mBase: TSyntaxNode;
  mSymbol, mTypeInfo: TResolvedSymbol;
  mTypeFound: Boolean;
begin
  mBase := ANode[0];
  if not (mBase.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess, TSyntaxKind.IndexAccess,
    TSyntaxKind.Call]) then
  begin
    Exit;
  end;
  if not FResolver.NodeType(FContext.Tree, FFileName, mBase, mSymbol, mTypeInfo, mTypeFound) or not mTypeFound or
    mSymbol.IsType or (mTypeInfo.SymbolKind <> TIndexSymbolKind.ClassType) or mTypeInfo.Builtin then
  begin
    Exit;
  end;
  // Bei einer Array-Property (Items[I]) ist Base selbst schon der indizierte Zugriff.
  if ((mSymbol.SymbolKind <> TIndexSymbolKind.Property_) or (mSymbol.MaxArgs <= 0) or
    (mBase.Kind = TSyntaxKind.IndexAccess)) and LacksDefault(mTypeInfo.Name) then
  begin
    FReport.Add(TTextRange.Create(ANode.StartPos, ANode.EndPos), cTexts[TPropertiesText.NoDefault].Fmt([mTypeInfo.Name,
      mSymbol.Name]), TRuleConfidence.High);
  end;
end;

procedure TDefaultPropertyScan.VisitBodies;
var
  mStack: TArray<TSyntaxNode>;
  mNode: TSyntaxNode;
  mIndex: Integer;
begin
  mStack := [FContext.Tree.Root];
  while mStack <> nil do
  begin
    mNode := mStack[High(mStack)];
    SetLength(mStack, Length(mStack) - 1);
    if (mNode.Kind = TSyntaxKind.IndexAccess) and (mNode.ChildCount > 1) then
    begin
      CheckAccess(mNode);
    end;
    for mIndex := mNode.ChildCount - 1 downto 0 do
    begin
      mStack := mStack + [mNode[mIndex]];
    end;
  end;
end;

procedure TDefaultPropertyScan.Run;
begin
  CheckDeclarations;
  // Resolver des Laufs (TRuleDerived.Resolver); gehört dem Cache.
  FResolver := TRuleDerived.Resolver(FCache, FContext);
  FResolver.PinTree(FContext.Tree, FFileName);
  try
    VisitBodies;
  finally
    FResolver.UnpinTree;
  end;
end;

{ TDefaultPropertyInvalidRule }

function TDefaultPropertyInvalidRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cDefaultPropertyInvalidRuleId, TRuleSeverity.Error,
    cTexts[TPropertiesText.DefaultTitle].Text);
end;

procedure TDefaultPropertyInvalidRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mScan: TDefaultPropertyScan;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mScan := TDefaultPropertyScan.Create(AContext, AReport);
  try
    mScan.Run;
  finally
    mScan.Free;
  end;
end;

/// <summary>Sieht der Nachfahre den Member ASymbol des Vorfahren auf AType?</summary>
function Visible(const AType: TSymbolLocation; const ASymbol: TIndexSymbol): Boolean;
begin
  Result := (ASymbol.Visibility <> TIndexVisibility.StrictPrivate) and
    ((ASymbol.Visibility <> TIndexVisibility.Private) or (AType.FileName = ''));
end;

/// <summary>Nimmt die sichtbare Property AMember von ALocation in ANames auf (Vorschläge für E2147).</summary>
procedure AddVisibleProperty(const ALocation: TSymbolLocation; const AMember: TIndexSymbol;
  var ANames: TArray<string>);
begin
  if (AMember.Kind = TIndexSymbolKind.Property_) and Visible(ALocation, AMember) and
    not MatchText(AMember.Name, ANames) then
  begin
    ANames := ANames + [AMember.Name];
  end;
end;

/// <summary>Ist AMember (gleichen Namens) eine Property, die der Nachfahre nicht sieht? Merkt den ersten solchen
/// Vorfahren in AHidden. False, wenn sie sichtbar ist oder keine sichere Aussage möglich ist.</summary>
function HiddenProperty(const ALocation: TSymbolLocation; const AMember: TIndexSymbol; var AHidden: string): Boolean;
begin
  // Nur in einem inaktiven Zweig oder kein Property (Feld, Methode): keine sichere Aussage.
  Result := not AMember.Unavailable and (AMember.Kind = TIndexSymbolKind.Property_) and
    not Visible(ALocation, AMember);
  if Result and (AHidden = '') then
  begin
    AHidden := ALocation.Symbol.Name;
  end;
end;

type
  /// <summary>Ein Lauf von property-redeclaration-invalid über eine Datei.</summary>
  TRedeclarationScan = class
  private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FCache: IRuleDerivedCache;
    FAncestry: TAncestry;
    /// <summary>Sucht AName in den Vorfahren AChain. False: keine Meldung (sichtbar gefunden oder keine sichere
    /// Aussage). AHidden: Vorfahr, in dem die Property unsichtbar steht; ANames: sichtbare Properties.</summary>
    function Search(const AChain: TArray<TSymbolLocation>; const AName: string; out AHidden: string;
      out ANames: TArray<string>): Boolean;
    procedure ReportMissing(const AProperty: TIndexSymbol; const AChain: TArray<TSymbolLocation>;
      const ANames: TArray<string>);
    procedure CheckProperty(const AOwner: TIndexSymbol; const AProperty: TIndexSymbol);
    procedure CheckType(const AType: TIndexSymbol);
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    destructor Destroy; override;
    procedure Run;
  end;

constructor TRedeclarationScan.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
  FCache := TRuleDerived.Open(AContext);
  FAncestry := TAncestry.Create(AContext.Index, TRuleDerived.UnitIndex(FCache, AContext));
end;

destructor TRedeclarationScan.Destroy;
begin
  FAncestry.Free;
  inherited;
end;

function TRedeclarationScan.Search(const AChain: TArray<TSymbolLocation>; const AName: string; out AHidden: string;
  out ANames: TArray<string>): Boolean;
var
  mLocation: TSymbolLocation;
  mMember: TIndexSymbol;
begin
  AHidden := '';
  ANames := nil;
  for mLocation in AChain do
  begin
    for mMember in FAncestry.Members(mLocation) do
    begin
      if not SameText(mMember.Name, AName) then
      begin
        AddVisibleProperty(mLocation, mMember, ANames);
      end
      else if not HiddenProperty(mLocation, mMember, AHidden) then
      begin
        Exit(False);
      end;
    end;
  end;
  Result := True;
end;

procedure TRedeclarationScan.ReportMissing(const AProperty: TIndexSymbol; const AChain: TArray<TSymbolLocation>;
  const ANames: TArray<string>);
var
  mAncestor, mClosest: string;
begin
  mAncestor := 'TObject';
  if AChain <> nil then
  begin
    mAncestor := AChain[0].Symbol.Name;
  end;
  mClosest := TTextFuzzy.Closest(AProperty.Name, ANames);
  if mClosest <> '' then
  begin
    FReport.Add(AProperty.SelectionRange, cTexts[TPropertiesText.NoPropertyMeant].Fmt(
      [mAncestor, AProperty.Name, mClosest]), TRuleConfidence.High,
      [TRuleFix.Create(cTexts[TPropertiesText.UseName].Fmt([mClosest]), [TRuleEdit.Create(AProperty.SelectionRange,
        mClosest)])]);
  end
  else
  begin
    FReport.Add(AProperty.SelectionRange, cTexts[TPropertiesText.NoProperty].Fmt([mAncestor,
      AProperty.Name]), TRuleConfidence.High);
  end;
end;

procedure TRedeclarationScan.CheckProperty(const AOwner: TIndexSymbol; const AProperty: TIndexSymbol);
var
  mChain: TArray<TSymbolLocation>;
  mComplete, mObjectMissing: Boolean;
  mHidden: string;
  mNames: TArray<string>;
begin
  mChain := FAncestry.Ancestors(AOwner.Name, mComplete, mObjectMissing);
  if not mComplete or not Search(mChain, AProperty.Name, mHidden, mNames) then
  begin
    Exit;
  end;
  if mHidden <> '' then
  begin
    FReport.Add(AProperty.SelectionRange, cTexts[TPropertiesText.Unreachable].Fmt(
      [AProperty.Name, mHidden]), TRuleConfidence.High);
  end
  else
  begin
    ReportMissing(AProperty, mChain, mNames);
  end;
end;

procedure TRedeclarationScan.CheckType(const AType: TIndexSymbol);
var
  mLocation: TSymbolLocation;
  mMember: TIndexSymbol;
begin
  mLocation := Default(TSymbolLocation);
  mLocation.Symbol := AType;
  // Neudeklaration: property Caption; bzw. property Align default alClient; (ohne Typ und Index).
  for mMember in FAncestry.Members(mLocation) do
  begin
    if (mMember.Kind = TIndexSymbolKind.Property_) and (mMember.TypeName = '') and (mMember.MaxArgs = 0) and
      not mMember.Unavailable and not mMember.HasDirective('class') then
    begin
      CheckProperty(AType, mMember);
    end;
  end;
end;

procedure TRedeclarationScan.Run;
var
  mSymbol: TIndexSymbol;
begin
  for mSymbol in FAncestry.Local.Symbols do
  begin
    if (mSymbol.Kind = TIndexSymbolKind.ClassType) and (mSymbol.Container = '') and not mSymbol.Unavailable and
      not TypeHasInclude(FContext.Tree.Tokens, mSymbol) then
    begin
      CheckType(mSymbol);
    end;
  end;
end;

{ TPropertyRedeclarationInvalidRule }

function TPropertyRedeclarationInvalidRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cPropertyRedeclarationInvalidRuleId, TRuleSeverity.Error,
    cTexts[TPropertiesText.RedeclaredTitle].Text);
end;

procedure TPropertyRedeclarationInvalidRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mScan: TRedeclarationScan;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  mScan := TRedeclarationScan.Create(AContext, AReport);
  try
    mScan.Run;
  finally
    mScan.Free;
  end;
end;

/// <summary>Name einer Attributklasse ohne die Endung Attribute.</summary>
function AttributeName(const AName: string): string;
begin
  Result := AName;
  if EndsText('Attribute', Result) and (Length(Result) > Length('Attribute')) then
  begin
    Result := Copy(Result, 1, Length(Result) - Length('Attribute'));
  end;
end;

/// <summary>Änderung der Klammertiefe rückwärts gelesen: +1 bei "]" und ")", -1 bei "[" und "(".</summary>
function BackwardDepthStep(const AToken: TPascalToken): Integer;
begin
  Result := 0;
  if AToken.IsSymbol(']') or AToken.IsSymbol(')') then
  begin
    Result := 1;
  end
  else if AToken.IsSymbol('[') or AToken.IsSymbol('(') then
  begin
    Result := -1;
  end;
end;

/// <summary>Text ohne Leerzeichen (Typvergleich).</summary>
function WithoutSpaces(const AText: string): string;
begin
  Result := StringReplace(AText, ' ', '', [rfReplaceAll]);
end;

type
  /// <summary>Ein Lauf von write-only-property über eine Datei.</summary>
  TWriteOnlyScan = class
  private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FCache: IRuleDerivedCache;
    FTokens: TArray<TPascalToken>;
    FAllowed: TArray<string>;
    FDeclarations: TArray<TSyntaxNode>;
    function IsAllowed(const AName: string): Boolean;
    /// <summary>Steht am Token AIndex der Name am Anfang eines Attributs (hinter "[" oder ",")?</summary>
    function StartsAttribute(AIndex: Integer): Boolean;
    /// <summary>Geht rückwärts über die Attributgruppe, die bei AIndex mit "]" endet; AIndex steht danach davor.
    /// True, wenn sie ein erlaubtes Attribut nennt.</summary>
    function AllowedInGroup(var AIndex: Integer): Boolean;
    /// <summary>Attribute direkt vor der Property ([Name], [A, B(1)], auch vor class property).</summary>
    function HasAllowedAttribute(AStart: Integer): Boolean;
    /// <summary>Typ (Klasse, Record, Objekt) der Property am Token AStart; nil ohne.</summary>
    function OwnerAt(AStart: Integer): TSyntaxNode;
    /// <summary>Ist AMember ein Feld F&lt;AName&gt; vom Typ ATypeText?</summary>
    function FieldMatches(AMember: TSyntaxNode; const AName, ATypeText: string): Boolean;
    /// <summary>Feld F&lt;Name&gt; mit gleichem Typ im Typ der Property.</summary>
    function FieldFor(AStart: Integer; const AName, ATypeText: string): Boolean;
    procedure CheckProperty(AStart: Integer);
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    procedure Run;
  end;

constructor TWriteOnlyScan.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
  FCache := TRuleDerived.Open(AContext);
  FTokens := TRuleDerived.CodeTokens(FCache, AContext);
  FAllowed := TRuleOptions.Strings(AContext.Options, 'allowAttributes', nil);
end;

function TWriteOnlyScan.IsAllowed(const AName: string): Boolean;
var
  mPattern: string;
begin
  for mPattern in FAllowed do
  begin
    if SameText(AttributeName(AName), AttributeName(mPattern)) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TWriteOnlyScan.StartsAttribute(AIndex: Integer): Boolean;
begin
  Result := (FTokens[AIndex].Kind = TPascalTokenKind.Identifier) and (AIndex > 0) and
    (FTokens[AIndex - 1].IsSymbol('[') or FTokens[AIndex - 1].IsSymbol(','));
end;

function TWriteOnlyScan.AllowedInGroup(var AIndex: Integer): Boolean;
var
  mDepth: Integer;
begin
  Result := False;
  mDepth := 0;
  while not Result and (AIndex >= 0) do
  begin
    mDepth := mDepth + BackwardDepthStep(FTokens[AIndex]);
    // Name am Anfang eines Attributs: hinter "[" oder "," auf Tiefe 1.
    Result := (mDepth = 1) and StartsAttribute(AIndex) and IsAllowed(FTokens[AIndex].Text);
    Dec(AIndex);
    if mDepth = 0 then
    begin
      Break;
    end;
  end;
end;

function TWriteOnlyScan.HasAllowedAttribute(AStart: Integer): Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  mIndex := AStart - 1;
  if (mIndex >= 0) and IsWord(FTokens[mIndex], 'class') then
  begin
    Dec(mIndex);
  end;
  while not Result and (mIndex >= 0) and FTokens[mIndex].IsSymbol(']') do
  begin
    Result := AllowedInGroup(mIndex);
  end;
end;

function TWriteOnlyScan.OwnerAt(AStart: Integer): TSyntaxNode;
var
  mDeclaration: TSyntaxNode;
begin
  Result := nil;
  for mDeclaration in FDeclarations do
  begin
    if (mDeclaration.StartOffset <= FTokens[AStart].Offset) and (mDeclaration.EndOffset > FTokens[AStart].Offset) then
    begin
      Result := mDeclaration.Parent;
    end;
  end;
  if (Result <> nil) and not (Result.Kind in [TSyntaxKind.ClassType, TSyntaxKind.RecordType,
    TSyntaxKind.ObjectType]) then
  begin
    Result := nil;
  end;
end;

function TWriteOnlyScan.FieldMatches(AMember: TSyntaxNode; const AName, ATypeText: string): Boolean;
var
  mName, mTypeText: string;
begin
  Result := False;
  if (AMember.Kind <> TSyntaxKind.Field) or (AMember.ChildCount = 0) then
  begin
    Exit;
  end;
  mTypeText := Trim(Copy(FContext.Text, AMember[0].StartOffset + 1, AMember[0].EndOffset - AMember[0].StartOffset));
  for mName in AMember.Name.Split([',']) do
  begin
    if SameText(Trim(mName), 'F' + AName) and SameText(WithoutSpaces(mTypeText), WithoutSpaces(ATypeText)) then
    begin
      Exit(True);
    end;
  end;
end;

function TWriteOnlyScan.FieldFor(AStart: Integer; const AName, ATypeText: string): Boolean;
var
  mOwner: TSyntaxNode;
  mIndex: Integer;
begin
  Result := False;
  mOwner := OwnerAt(AStart);
  if mOwner = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to mOwner.ChildCount - 1 do
  begin
    if FieldMatches(mOwner[mIndex], AName, ATypeText) then
    begin
      Exit(True);
    end;
  end;
end;

procedure TWriteOnlyScan.CheckProperty(AStart: Integer);
var
  mShape: TPropertyShape;
  mAccessor, mWriter: TPropertyAccessor;
  mHasRead, mHasWrite: Boolean;
  mName: string;
  mFixes: TArray<TRuleFix>;
  mAt: TTextPosition;
begin
  // Ohne Typ wird eine geerbte Property neu veröffentlicht; ihr read kommt vom Vorfahren.
  if not ParseProperty(FContext.Text, FTokens, AStart, mShape) or (mShape.TypeText = '') then
  begin
    Exit;
  end;
  mHasRead := False;
  mHasWrite := False;
  mWriter := Default(TPropertyAccessor);
  for mAccessor in mShape.Accessors do
  begin
    if mAccessor.IsWrite then
    begin
      mHasWrite := True;
      mWriter := mAccessor;
    end
    else
    begin
      mHasRead := True;
    end;
  end;
  if mHasRead or not mHasWrite or HasAllowedAttribute(AStart) then
  begin
    Exit;
  end;
  mName := FTokens[AStart + 1].Text;
  mFixes := nil;
  if FieldFor(AStart, mName, mShape.TypeText) then
  begin
    // Vor dem Wort write einfügen.
    mAt := FTokens[mWriter.First - 1].StartPos;
    mFixes := [TRuleFix.Create(cTexts[TPropertiesText.AddRead].Fmt([mName]),
      [TRuleEdit.Create(TTextRange.Create(mAt, mAt), Format('read F%s ', [mName]))])];
  end;
  FReport.Add(TTextRange.Create(FTokens[AStart + 1].StartPos, FTokens[AStart + 1].EndPos),
    cTexts[TPropertiesText.NoRead].Fmt([mName]), TRuleConfidence.High, mFixes);
end;

procedure TWriteOnlyScan.Run;
var
  mIndex: Integer;
  mFound: TArray<TSyntaxNode>;
begin
  mFound := nil;
  FContext.Tree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      if ANode.Kind = TSyntaxKind.PropertyDecl then
      begin
        mFound := mFound + [ANode];
      end;
      Result := True;
    end);
  FDeclarations := mFound;
  for mIndex := 0 to High(FTokens) - 1 do
  begin
    if IsWord(FTokens[mIndex], 'property') then
    begin
      CheckProperty(mIndex);
    end;
  end;
end;

{ TWriteOnlyPropertyRule }

function TWriteOnlyPropertyRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cWriteOnlyPropertyRuleId, TRuleSeverity.Hint,
    cTexts[TPropertiesText.WriteOnlyTitle].Text);
end;

procedure TWriteOnlyPropertyRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mScan: TWriteOnlyScan;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mScan := TWriteOnlyScan.Create(AContext, AReport);
  try
    mScan.Run;
  finally
    mScan.Free;
  end;
end;

procedure RegisterPropertyRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TPropertyAccessorInvalidRule.Create);
  ARegistry.Register(TDefaultPropertyInvalidRule.Create);
  ARegistry.Register(TPropertyRedeclarationInvalidRule.Create);
  ARegistry.Register(TWriteOnlyPropertyRule.Create);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Properties', cTexts);

end.
