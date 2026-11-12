unit Atlas.Common.Semantics.NameResolver.Symbols;

// Aufgelöste Symbole der Namensauflösung und die Hilfen, die alle Teile von TNameResolver teilen: Typtexte
// (Typargumente, Bindungen, eingebaute Typen, passende Argumente) und Wege durch den Syntaxbaum.

interface

{$SCOPEDENUMS ON}

uses
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract;

type
  TResolvedKind = (None, UnitName, Symbol, Local);

  TResolvedSymbol = record
    Kind: TResolvedKind;
    Name: string;
    /// <summary>Unit der Deklaration (bei Local die eigene Unit).</summary>
    UnitName: string;
    FileName: string;
    Range: TTextRange;
    SelectionRange: TTextRange;
    SymbolKind: TIndexSymbolKind;
    /// <summary>Umgebender Typ bei Mitgliedern.</summary>
    Container: string;
    /// <summary>Bei Mitgliedern (MemberCandidates): 0 = eigener Typ, 1 = direkter Vorfahr usw. (#419).</summary>
    Depth: Integer;
    /// <summary>Mitglied aus einem Class- bzw. Record-Helper (#456).</summary>
    IsHelper: Boolean;
    /// <summary>Namenspositionen weiterer Überladungen in derselben Datei (#425).</summary>
    Overloads: TArray<TTextRange>;
    /// <summary>Parametertypen je Variante (erste zuerst), um Rümpfe nicht als Überladung zu zählen.</summary>
    VariantParams: TArray<string>;
    /// <summary>Deklaration im interface-Abschnitt.</summary>
    InInterface: Boolean;
    /// <summary>Methode mit virtual, dynamic, abstract oder override (#443).</summary>
    IsVirtual: Boolean;
    /// <summary>Bedingung der Deklaration wie im Index (#476); '' = immer.</summary>
    Condition: string;
    /// <summary>Zweig eines varianten Record-Felds wie im Index (#846); '' = keiner.</summary>
    VariantBranch: string;
    /// <summary>Deklarierter Typ (Variablen, Felder, Properties, Parameter, Funktionsergebnis).</summary>
    TypeName: string;
    Ancestors: TArray<string>;
    IsParameter: Boolean;
    /// <summary>Typparameter einer generischen Routine oder ihres Typs im Rumpf (T in TFoo&lt;T&gt;.Bar). Sein Aufbau
    /// ist unbekannt: TypeOf liefert False.</summary>
    IsTypeParameter: Boolean;
    /// <summary>Gleichnamige Deklarationen weiter außen, die dieser Eintrag verdeckt (#488), als Text wie
    /// "Feld TKunde.Total"; nur bei Kandidaten für die Vervollständigung.</summary>
    Hides: TArray<string>;
    /// <summary>Mitglied eines with-Objekts (#481): der Ausdruck des Elements wie im Quelltext ("qryOrders");
    /// '' sonst. Nur bei Kandidaten für die Vervollständigung.</summary>
    WithOrigin: string;
    /// <summary>Bei WithOrigin: verdeckte gleichnamige lokale Namen und Mitglieder von Self (#481), als Text wie
    /// "Self.Name" bzw. "lokale Variable Name".</summary>
    WithShadows: TArray<string>;
    /// <summary>Wie im Index (#263).</summary>
    TypeArgs: string;
    AncestorArgs: TArray<string>;
    TypeParams: string;
    Visibility: TIndexVisibility;
    MinArgs: Integer;
    MaxArgs: Integer;
    ParamTypes: TArray<string>;
    IsDefault: Boolean;
    /// <summary>Kopf der Deklaration wie im Index (#492), bei Properties samt read/write (#491); '' ohne Index.
    /// </summary>
    Signature: string;
    /// <summary>Direktiven wie im Index (#492), z. B. class, static, virtual (#1008); nil bei lokalen Namen.</summary>
    Directives: TArray<string>;
    /// <summary>Gebundene Typparameter als Name=Typ (bei Mitgliedern die des umgebenden Typs).</summary>
    Bindings: TArray<string>;
    /// <summary>Eingebauter Typ ohne Deklaration im Index (string, Integer ...).</summary>
    Builtin: Boolean;
    /// <summary>Ausdruck, aus dem der Typ einer Inline-Variablen ohne Typangabe folgt.</summary>
    Initializer: TSyntaxNode;
    /// <summary>TKunde.Create: der Typ, an dem der Konstruktor aufgerufen wurde (0 oder 1 Eintrag).</summary>
    Constructed: array of TResolvedSymbol;
    function Found: Boolean;
    function IsType: Boolean;
    function QualifiedName: string;
    /// <summary>Vorfahr AIndex samt seinen Typargumenten wie in der Deklaration (IComparer&lt;TKunde&gt;).</summary>
    function AncestorText(AIndex: Integer): string;
    /// <summary>Kurzer Text zu einer verdeckten Deklaration (#488): "lokale Variable X", "Parameter X",
    /// "Feld TKunde.X", "Eigenschaft TKunde.X", "Methode TKunde.X", "Kunde.X".</summary>
    function ShadowText: string;
    /// <summary>Dieses Symbol als Mitglied in Vererbungstiefe ADepth (#419), ggf. aus einem Helper.</summary>
    function AsMember(ADepth: Integer; AIsHelper: Boolean): TResolvedSymbol;
    /// <summary>Gleiche Art, Argumentzahlen und Parametertypen: Deklaration und Rumpf derselben Routine.</summary>
    function SameSignature(const AOther: TResolvedSymbol): Boolean;
    /// <summary>AOuter ist eine andere Deklaration als dieses Symbol, nicht dessen Rumpf in implementation
    /// (#488).</summary>
    function IsOtherDeclaration(const AOuter: TResolvedSymbol): Boolean;
    /// <summary>Kein Ergebnis (Kind None).</summary>
    class function Empty: TResolvedSymbol; static;
    /// <summary>Unit AUnit als Ergebnis (Kind UnitName).</summary>
    class function OfUnit(const AUnit: TUnitIndex): TResolvedSymbol; static;
    /// <summary>Eingebauter Typ ohne Deklaration im Index (string, Integer …) als Ergebnis.</summary>
    class function BuiltinOf(const AName: string): TResolvedSymbol; static;
    /// <summary>Index-Symbol ASymbol aus AUnit als aufgelöstes Symbol (#654).</summary>
    class function FromIndex(const AUnit: TUnitIndex; const ASymbol: TIndexSymbol): TResolvedSymbol; static;
    /// <summary>Hängt ASymbol an AList an, außer Deklaration oder Rumpf derselben Routine steht schon dort; die
    /// Deklaration kommt zuerst.</summary>
    class procedure AddDistinct(var AList: TArray<TResolvedSymbol>; const ASymbol: TResolvedSymbol); static;
  end;

  /// <summary>Vorfilter für Namen von Kandidaten (#616); False = gar nicht erst aufbauen.</summary>
  TCandidateNameFilter = reference to function(const AName: string): Boolean;

  /// <summary>Verweis auf eine gemerkte Unit; gültig, solange der Resolver lebt.</summary>
  PUnitIndex = ^TUnitIndex;

  /// <summary>Typ eines Ausdrucks im Syntaxbaum (TResolverExpressions.ExprSymbol), für die Typen von
  /// Inline-Variablen ohne Typangabe.</summary>
  TResolverInferFunc = reference to function(ANode: TSyntaxNode; out AResult: TResolvedSymbol): Boolean;

  /// <summary>Ergebnis von TNameResolver.ChainType: der Name am Ende der Kette und sein Typ.</summary>
  TResolvedChainType = record
    Owner: TResolvedSymbol;
    TypeInfo: TResolvedSymbol;
    // Typ von Owner bekannt (nicht bei Unit-Namen und unbekannten Typen).
    TypeFound: Boolean;
  end;

  /// <summary>Ergebnis von TNameResolver.WithMember: die with-Anweisung, deren Ausdruck den Namen liefert.
  /// </summary>
  TResolvedWithMember = record
    Statement: TSyntaxNode;
    // Platz des Ausdrucks in Statement; -1 ohne Treffer.
    Element: Integer;
    // Ein with-Ausdruck hat einen unbekannten Typ: Der Name könnte sein Mitglied sein.
    Unknown: Boolean;
  end;

  /// <summary>Typtexte der Namensauflösung: Typargumente, Bindungen, eingebaute Typen und passende Argumente.
  /// </summary>
  TResolverText = class
  public
    /// <summary>Kommagetrennte Liste auf oberster Ebene: 'string, TList&lt;A, B&gt;' → ['string', 'TList&lt;A, B&gt;'].
    /// </summary>
    class function SplitArgs(const AText: string): TArray<string>; static;
    /// <summary>'TList&lt;TKunde&gt;' → 'TList' und 'TKunde'.</summary>
    class procedure SplitGeneric(const AText: string; out ABase, AArgs: string); static;
    /// <summary>Typname samt Typargumenten: 'TList' und 'TKunde' → 'TList&lt;TKunde&gt;'.</summary>
    class function FullType(const ATypeName, ATypeArgs: string): string; static;
    /// <summary>Bindet Typparameter 'T,U' an Typargumente.</summary>
    class function Bind(const AParams: string; const AArgs: TArray<string>): TArray<string>; static;
    /// <summary>Setzt gebundene Typparameter in einen Typtext ein; spätere Bindungen gewinnen.</summary>
    class function Substitute(const AText: string; const ABindings: TArray<string>): string; static;
    /// <summary>Eingebauter Typ ohne Deklaration im Index (string, Integer …), ohne die PChar-Typen.</summary>
    class function IsBuiltinName(const AName: string): Boolean; static;
    /// <summary>Eingebauter Typ ohne Deklaration im Index (string, Integer, PChar …).</summary>
    class function IsBuiltinTypeName(const AName: string): Boolean; static;
    /// <summary>string, UnicodeString, AnsiString, WideString oder ShortString.</summary>
    class function IsStringName(const AName: string): Boolean; static;
    /// <summary>Gleiche Typfamilie (string/UnicodeString, Ganzzahlen ...).</summary>
    class function SameFamily(const A, B: string): Boolean; static;
    /// <summary>Passt ein Argument vom Typ AArg zu einem Parameter vom Typ AParam (#498)? Gleiche Typfamilie,
    /// Char an string, Ganzzahl an Gleitkomma, nil an Zeiger und Klassen, [] an Mengen und offene Arrays; Klassen
    /// ohne Vererbungsprüfung. '' (unbekannt) passt immer.</summary>
    class function ArgumentFits(const AParam, AArg: string): Boolean; static;
    /// <summary>Passt der Zieltyp ATarget eines Helpers (ggf. mit Unit-Präfix) zu AType? string und
    /// UnicodeString gelten als gleich.</summary>
    class function HelperTargets(const ATarget: string; const AType: TResolvedSymbol): Boolean; static;
    /// <summary>Zielklasse aus dem Kopf einer Klassenreferenz ("ExceptClass = class of Exception" ergibt
    /// "Exception"); '' ohne class of.</summary>
    class function ClassRefTarget(const ASignature: string): string; static;
    /// <summary>Sieht AName (auch mit Unit) wie eine Exception-Klasse aus: Exception oder E mit Großbuchstaben?
    /// </summary>
    class function LooksLikeException(const AName: string): Boolean; static;
    /// <summary>Name ohne Unit-Präfix und Typargumente: "Generics.IComparer&lt;T&gt;" → "IComparer".</summary>
    class function BareTypeName(const AText: string): string; static;
    /// <summary>Name ohne Unit-Präfix: "System.TObject" → "TObject".</summary>
    class function LastPart(const AName: string): string; static;
    /// <summary>Ist AName TObject bzw. System.TObject?</summary>
    class function IsObjectRoot(const AName: string): Boolean; static;
  end;

  /// <summary>Wege durch den Syntaxbaum, die mehrere Teile der Namensauflösung brauchen.</summary>
  TResolverNodes = class
  public
    /// <summary>Liegt AOffset in ANode (Anfang und Ende eingeschlossen)?</summary>
    class function Contains(ANode: TSyntaxNode; AOffset: Integer): Boolean; static;
    /// <summary>Erstes Kind von ANode, in dem AOffset liegt; nil ohne.</summary>
    class function ChildAround(ANode: TSyntaxNode; AOffset: Integer): TSyntaxNode; static;
    /// <summary>Legt die Kinder von ANode bis vor das erste, das hinter AOffset beginnt, rückwärts auf APending:
    /// So kommen sie in Quelltextreihenfolge wieder herunter wie in der früheren Rekursion.</summary>
    class procedure PushChildrenBefore(APending: TStack<TSyntaxNode>; ANode: TSyntaxNode; AOffset: Integer); static;
    /// <summary>Legt die Kinder von ANode, die vor AOffset beginnen und nicht vor AOffset enden, rückwärts auf
    /// APending.</summary>
    class procedure PushChildrenAround(APending: TStack<TSyntaxNode>; ANode: TSyntaxNode; AOffset: Integer); static;
    /// <summary>Knoten mit Parametern und Ergebnistyp einer Routine: der Kopf einer benannten Routine,
    /// bei einer anonymen Methode der Knoten selbst; nil ohne Kopf.</summary>
    class function RoutineHeaderOf(ARoutine: TSyntaxNode): TSyntaxNode; static;
    /// <summary>Quelltext von ANode aus den Tokens von ATree, in einer Zeile; Leerraum dazwischen als ein
    /// Leerzeichen.</summary>
    class function NodeSource(ATree: TSyntaxTree; ANode: TSyntaxNode): string; static;
    /// <summary>Art eines Eintrags aus var- bzw. const-Abschnitt: Variable bzw. Konstante.</summary>
    class function DeclarationKind(ANode: TSyntaxNode): TIndexSymbolKind; static;
  end;

const
  cTypeKinds = [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType,
    TIndexSymbolKind.InterfaceType, TIndexSymbolKind.HelperType, TIndexSymbolKind.EnumType,
    TIndexSymbolKind.TypeAlias];
  cRoutineKinds = [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_, TIndexSymbolKind.Routine];
  cExpressionKinds = [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess, TSyntaxKind.Call, TSyntaxKind.IndexAccess,
    TSyntaxKind.ParenExpr, TSyntaxKind.Dereference];
  /// <summary>Höchstzahl der Schritte durch Vorfahren, Aliase und verschachtelte Helfer.</summary>
  cMaxDepth = 32;
  /// <summary>Höchste Schachtelung beim Ableiten der Typen von Inline-Variablen.</summary>
  cMaxInferDepth = 8;
  /// <summary>AArity für LookupInUnit/LookupGlobal: nur Typen ohne Typparameter (-1 = beliebig, 0 = ohne
  /// Typargumente).</summary>
  cNonGenericArity = -2;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Localization.Texts;

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TSymbolsText = (Field, PropertyText);

const
  cTexts: array[TSymbolsText] of TAtlasText = (
    (De: 'Feld '; En: 'field '),
    (De: 'Eigenschaft '; En: 'property '));

const
  // Eingebaute Typen, die nicht als Symbol im Index stehen.
  // OleVariant wie Variant: Ohne Eintrag hatte eine Variable vom Typ OleVariant keinen Typ (#1373).
  cBuiltinTypes: array[0..28] of string = ('string', 'UnicodeString', 'AnsiString', 'WideString', 'ShortString',
    'Char', 'WideChar', 'AnsiChar', 'Integer', 'Cardinal', 'Int64', 'UInt64', 'NativeInt', 'NativeUInt',
    'Byte', 'Word', 'ShortInt', 'SmallInt', 'LongInt', 'LongWord', 'Boolean', 'Double', 'Single', 'Extended',
    'Currency', 'Real', 'Pointer', 'Variant', 'OleVariant');
  cIntegerTypes: array[0..13] of string = ('Integer', 'Cardinal', 'Int64', 'UInt64', 'NativeInt', 'NativeUInt',
    'Byte', 'Word', 'ShortInt', 'SmallInt', 'LongInt', 'LongWord', 'Int8', 'UInt8');
  cFloatTypes: array[0..4] of string = ('Double', 'Single', 'Extended', 'Currency', 'Real');
  cStringTypes: array[0..4] of string = ('string', 'UnicodeString', 'AnsiString', 'WideString', 'ShortString');
  cCharTypes: array[0..2] of string = ('Char', 'WideChar', 'AnsiChar');
  /// <summary>Nehmen ein String-Literal und nil an (#498).</summary>
  cPCharTypes: array[0..2] of string = ('PChar', 'PWideChar', 'PAnsiChar');
  cWordChars = ['A'..'Z', 'a'..'z', '_', '0'..'9', '.'];

/// <summary>Ersatz für AWord aus den Bindungen Name=Typ; die letzte passende gewinnt, sonst AWord.</summary>
function BoundType(const AWord: string; const ABindings: TArray<string>): string;
var
  mBinding, mEqual: Integer;
begin
  Result := AWord;
  for mBinding := High(ABindings) downto 0 do
  begin
    mEqual := Pos('=', ABindings[mBinding]);
    if SameText(Copy(ABindings[mBinding], 1, mEqual - 1), AWord) then
    begin
      Exit(Copy(ABindings[mBinding], mEqual + 1, MaxInt));
    end;
  end;
end;

/// <summary>Passt AArg zu AParam, wenn keine Sonderregel greift: gleiche Familie, Ganzzahl an Gleitkomma, Char an
/// string, Klassen ohne Vererbungsprüfung.</summary>
function ConvertibleArgument(const AParam, AArg: string): Boolean;
begin
  Result := TResolverText.SameFamily(AParam, AArg) or
    // Ganzzahl an Gleitkomma, Char an string.
    (MatchText(AParam, cFloatTypes) and (MatchText(AArg, cIntegerTypes) or MatchText(AArg, cFloatTypes))) or
    (MatchText(AParam, cStringTypes) and MatchText(AArg, cCharTypes)) or
    // Klassen: ohne Vererbungsprüfung als passend werten, nur eingebaute Typen schließen aus.
    (not TResolverText.IsBuiltinName(AParam) and not TResolverText.IsBuiltinName(AArg));
end;

{ TResolvedSymbol }

function TResolvedSymbol.Found: Boolean;
begin
  Result := Kind <> TResolvedKind.None;
end;

function TResolvedSymbol.IsType: Boolean;
begin
  Result := (Kind in [TResolvedKind.Symbol, TResolvedKind.Local]) and (SymbolKind in cTypeKinds);
end;

function TResolvedSymbol.QualifiedName: string;
begin
  if Container = '' then
  begin
    Result := Name;
  end
  else
  begin
    Result := Container + '.' + Name;
  end;
end;

function TResolvedSymbol.AncestorText(AIndex: Integer): string;
begin
  Result := Ancestors[AIndex];
  if AIndex <= High(AncestorArgs) then
  begin
    Result := TResolverText.FullType(Result, AncestorArgs[AIndex]);
  end;
end;

function TResolvedSymbol.ShadowText: string;
begin
  if Kind = TResolvedKind.Local then
  begin
    if IsParameter then
    begin
      Result := 'Parameter ' + Name;
    end
    else
    begin
      Result := 'lokale Variable ' + Name;
    end;
  end
  else if Container <> '' then
  begin
    case SymbolKind of
      TIndexSymbolKind.Field: Result := cTexts[TSymbolsText.Field].Text;
      TIndexSymbolKind.Property_: Result := cTexts[TSymbolsText.PropertyText].Text;
      TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_: Result := 'Methode ';
    else
      Result := '';
    end;
    Result := Result + Container + '.' + Name;
  end
  else if UnitName <> '' then
  begin
    Result := UnitName + '.' + Name;
  end
  else
  begin
    Result := Name;
  end;
end;

function TResolvedSymbol.AsMember(ADepth: Integer; AIsHelper: Boolean): TResolvedSymbol;
begin
  Result := Self;
  Result.Depth := ADepth;
  Result.IsHelper := AIsHelper;
end;

function TResolvedSymbol.SameSignature(const AOther: TResolvedSymbol): Boolean;
var
  mIndex: Integer;
begin
  Result := (SymbolKind = AOther.SymbolKind) and (MinArgs = AOther.MinArgs) and (MaxArgs = AOther.MaxArgs) and
    (Length(ParamTypes) = Length(AOther.ParamTypes));
  if Result then
  begin
    for mIndex := 0 to High(ParamTypes) do
    begin
      if not SameText(ParamTypes[mIndex], AOther.ParamTypes[mIndex]) then
      begin
        Exit(False);
      end;
    end;
  end;
end;

function TResolvedSymbol.IsOtherDeclaration(const AOuter: TResolvedSymbol): Boolean;
begin
  if (Kind = TResolvedKind.Local) and (AOuter.Kind = TResolvedKind.Local) then
  begin
    Result := not (SelectionRange.StartPos = AOuter.SelectionRange.StartPos);
  end
  else
  begin
    Result := (Kind <> AOuter.Kind) or not SameText(Container, AOuter.Container) or
      not SameText(FileName, AOuter.FileName);
  end;
end;

class function TResolvedSymbol.Empty: TResolvedSymbol;
begin
  Result := Default(TResolvedSymbol);
  Result.Kind := TResolvedKind.None;
end;

class function TResolvedSymbol.OfUnit(const AUnit: TUnitIndex): TResolvedSymbol;
begin
  Result := Empty;
  Result.Kind := TResolvedKind.UnitName;
  Result.Name := AUnit.UnitName;
  Result.UnitName := AUnit.UnitName;
  Result.FileName := AUnit.FileName;
end;

class function TResolvedSymbol.BuiltinOf(const AName: string): TResolvedSymbol;
begin
  Result := Empty;
  Result.Kind := TResolvedKind.Symbol;
  Result.Name := AName;
  Result.UnitName := 'System';
  Result.SymbolKind := TIndexSymbolKind.RecordType;
  Result.Builtin := True;
end;

class function TResolvedSymbol.FromIndex(const AUnit: TUnitIndex; const ASymbol: TIndexSymbol): TResolvedSymbol;
begin
  Result := Empty;
  Result.Kind := TResolvedKind.Symbol;
  Result.Name := ASymbol.Name;
  Result.UnitName := AUnit.UnitName;
  Result.FileName := AUnit.SymbolFile(ASymbol);
  Result.Range := ASymbol.Range;
  Result.SelectionRange := ASymbol.SelectionRange;
  Result.SymbolKind := ASymbol.Kind;
  Result.Container := ASymbol.Container;
  Result.TypeName := ASymbol.TypeName;
  Result.Ancestors := ASymbol.Ancestors;
  Result.IsParameter := False;
  Result.TypeArgs := ASymbol.TypeArgs;
  Result.AncestorArgs := ASymbol.AncestorArgs;
  Result.TypeParams := ASymbol.TypeParams;
  Result.Visibility := ASymbol.Visibility;
  Result.MinArgs := ASymbol.MinArgs;
  Result.MaxArgs := ASymbol.MaxArgs;
  Result.ParamTypes := ASymbol.ParamTypes;
  Result.IsDefault := ASymbol.IsDefault;
  Result.Signature := ASymbol.Signature;
  Result.Directives := ASymbol.Directives;
  Result.InInterface := ASymbol.InInterface;
  Result.IsVirtual := ASymbol.IsVirtual;
  Result.Condition := ASymbol.Condition;
  Result.VariantBranch := ASymbol.VariantBranch;
  Result.VariantParams := [String.Join(';', ASymbol.ParamTypes)];
end;

class procedure TResolvedSymbol.AddDistinct(var AList: TArray<TResolvedSymbol>; const ASymbol: TResolvedSymbol);
var
  mExisting: TResolvedSymbol;
begin
  for mExisting in AList do
  begin
    if mExisting.SameSignature(ASymbol) then
    begin
      Exit;
    end;
  end;
  AList := AList + [ASymbol];
end;

{ TResolverText }

class function TResolverText.SplitArgs(const AText: string): TArray<string>;
var
  mIndex, mDepth, mStart: Integer;
begin
  Result := nil;
  if Trim(AText) = '' then
  begin
    Exit;
  end;
  mDepth := 0;
  mStart := 1;
  for mIndex := 1 to Length(AText) + 1 do
  begin
    if (mIndex > Length(AText)) or ((AText[mIndex] = ',') and (mDepth = 0)) then
    begin
      Result := Result + [Trim(Copy(AText, mStart, mIndex - mStart))];
      mStart := mIndex + 1;
    end
    else if AText[mIndex] = '<' then
    begin
      Inc(mDepth);
    end
    else if AText[mIndex] = '>' then
    begin
      Dec(mDepth);
    end;
  end;
end;

class procedure TResolverText.SplitGeneric(const AText: string; out ABase, AArgs: string);
var
  mOpen: Integer;
begin
  mOpen := Pos('<', AText);
  if (mOpen = 0) or (AText[Length(AText)] <> '>') then
  begin
    ABase := Trim(AText);
    AArgs := '';
  end
  else
  begin
    ABase := Trim(Copy(AText, 1, mOpen - 1));
    AArgs := Copy(AText, mOpen + 1, Length(AText) - mOpen - 1);
  end;
end;

class function TResolverText.FullType(const ATypeName, ATypeArgs: string): string;
begin
  if ATypeArgs = '' then
  begin
    Result := ATypeName;
  end
  else
  begin
    Result := ATypeName + '<' + ATypeArgs + '>';
  end;
end;

class function TResolverText.Bind(const AParams: string; const AArgs: TArray<string>): TArray<string>;
var
  mParams: TArray<string>;
  mIndex: Integer;
begin
  Result := nil;
  mParams := SplitArgs(AParams);
  for mIndex := 0 to High(mParams) do
  begin
    if mIndex <= High(AArgs) then
    begin
      Result := Result + [mParams[mIndex] + '=' + AArgs[mIndex]];
    end;
  end;
end;

class function TResolverText.Substitute(const AText: string; const ABindings: TArray<string>): string;
var
  mIndex, mStart: Integer;
begin
  if Length(ABindings) = 0 then
  begin
    Exit(AText);
  end;
  Result := '';
  mIndex := 1;
  while mIndex <= Length(AText) do
  begin
    if CharInSet(AText[mIndex], cWordChars) then
    begin
      mStart := mIndex;
      while (mIndex <= Length(AText)) and CharInSet(AText[mIndex], cWordChars) do
      begin
        Inc(mIndex);
      end;
      Result := Result + BoundType(Copy(AText, mStart, mIndex - mStart), ABindings);
    end
    else
    begin
      Result := Result + AText[mIndex];
      Inc(mIndex);
    end;
  end;
end;

class function TResolverText.IsBuiltinName(const AName: string): Boolean;
begin
  Result := MatchText(AName, cBuiltinTypes) or MatchText(AName, cIntegerTypes);
end;

class function TResolverText.IsBuiltinTypeName(const AName: string): Boolean;
begin
  Result := IsBuiltinName(AName) or MatchText(AName, ['PChar', 'PAnsiChar', 'PWideChar']);
end;

class function TResolverText.IsStringName(const AName: string): Boolean;
begin
  Result := MatchText(AName, cStringTypes);
end;

class function TResolverText.SameFamily(const A, B: string): Boolean;
begin
  Result := SameText(A, B) or
    (MatchText(A, cStringTypes) and MatchText(B, cStringTypes)) or
    (MatchText(A, cCharTypes) and MatchText(B, cCharTypes)) or
    (MatchText(A, cIntegerTypes) and MatchText(B, cIntegerTypes));
end;

class function TResolverText.ArgumentFits(const AParam, AArg: string): Boolean;
begin
  if (AParam = '') or (AArg = '') or SameText(AParam, 'Variant') or SameText(AParam, 'OleVariant') then
  begin
    Result := True;
  end
  // nil (#498): Zeiger, Klassen, Interfaces, Methodenzeiger, dynamische Arrays, aber keine einfachen Typen.
  else if SameText(AArg, 'nil') then
  begin
    Result := SameText(AParam, 'Pointer') or MatchText(AParam, cPCharTypes) or not IsBuiltinName(AParam);
  end
  // String-Literal an PChar.
  else if MatchText(AParam, cPCharTypes) and (MatchText(AArg, cStringTypes) or MatchText(AArg, cCharTypes)) then
  begin
    Result := True;
  end
  else if AArg = '[]' then
  begin
    Result := StartsText('array of', AParam) or StartsText('set of', AParam) or (Pos('<', AParam) = 0);
  end
  else
  begin
    Result := not StartsText('array of', AParam) and ConvertibleArgument(AParam, AArg);
  end;
end;

class function TResolverText.HelperTargets(const ATarget: string; const AType: TResolvedSymbol): Boolean;
var
  mName: string;
begin
  mName := LastPart(ATarget);
  Result := SameText(mName, AType.Name) or
    (MatchText(mName, ['string', 'UnicodeString']) and MatchText(AType.Name, ['string', 'UnicodeString']));
end;

class function TResolverText.ClassRefTarget(const ASignature: string): string;
var
  mWords: TArray<string>;
  mIndex: Integer;
begin
  Result := '';
  mWords := ASignature.Replace(';', ' ').Split([' ', #9, #10, #13, '='], TStringSplitOptions.ExcludeEmpty);
  for mIndex := 0 to High(mWords) - 2 do
  begin
    if SameText(mWords[mIndex], 'class') and SameText(mWords[mIndex + 1], 'of') then
    begin
      Exit(mWords[mIndex + 2]);
    end;
  end;
end;

class function TResolverText.LooksLikeException(const AName: string): Boolean;
var
  mPlain: string;
begin
  mPlain := LastPart(AName);
  Result := SameText(mPlain, 'Exception') or ((Length(mPlain) > 1) and (mPlain[1] = 'E') and
    CharInSet(mPlain[2], ['A'..'Z']));
end;

class function TResolverText.BareTypeName(const AText: string): string;
begin
  Result := Trim(AText);
  if Pos('<', Result) > 0 then
  begin
    Result := Copy(Result, 1, Pos('<', Result) - 1);
  end;
  Result := LastPart(Result);
end;

class function TResolverText.LastPart(const AName: string): string;
begin
  Result := Copy(AName, LastDelimiter('.', AName) + 1, MaxInt);
end;

class function TResolverText.IsObjectRoot(const AName: string): Boolean;
begin
  Result := SameText(AName, 'TObject') or SameText(AName, 'System.TObject');
end;

{ TResolverNodes }

class function TResolverNodes.Contains(ANode: TSyntaxNode; AOffset: Integer): Boolean;
begin
  Result := (ANode.StartOffset <= AOffset) and (AOffset <= ANode.EndOffset);
end;

/// <summary>Erstes Kind von ANode, das nicht vor AOffset endet, per Binärsuche über die nach Lage geordneten
/// Kinder; ChildCount, wenn alle vorher enden.</summary>
function FirstEndingAtOrAfter(ANode: TSyntaxNode; AOffset: Integer): Integer;
var
  mLow, mHigh, mMiddle: Integer;
begin
  mLow := 0;
  mHigh := ANode.ChildCount;
  while mLow < mHigh do
  begin
    mMiddle := (mLow + mHigh) div 2;
    if ANode[mMiddle].EndOffset < AOffset then
    begin
      mLow := mMiddle + 1;
    end
    else
    begin
      mHigh := mMiddle;
    end;
  end;
  Result := mLow;
end;

class function TResolverNodes.ChildAround(ANode: TSyntaxNode; AOffset: Integer): TSyntaxNode;
const
  // Bis zu so vielen Kindern linear; darüber binär (eine Unit mit 1.000 Routinen suchte je Namensauflösung
  // linear über alle, die Prüfung wuchs quadratisch).
  cLinearChildren = 16;
var
  mIndex: Integer;
begin
  if ANode.ChildCount > cLinearChildren then
  begin
    // Die Kinder liegen nacheinander und überlappen nicht: Alle vor mIndex enden vor AOffset, das Kind mIndex ist
    // also das erste, das AOffset enthält. Ohne Treffer (AOffset zwischen zwei Kindern) linear wie bisher.
    mIndex := FirstEndingAtOrAfter(ANode, AOffset);
    if (mIndex < ANode.ChildCount) and Contains(ANode[mIndex], AOffset) then
    begin
      Exit(ANode[mIndex]);
    end;
  end;
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    if Contains(ANode[mIndex], AOffset) then
    begin
      Exit(ANode[mIndex]);
    end;
  end;
  Result := nil;
end;

class procedure TResolverNodes.PushChildrenBefore(APending: TStack<TSyntaxNode>; ANode: TSyntaxNode;
  AOffset: Integer);
var
  mCount, mIndex: Integer;
begin
  mCount := 0;
  while (mCount < ANode.ChildCount) and (ANode[mCount].StartOffset <= AOffset) do
  begin
    Inc(mCount);
  end;
  for mIndex := mCount - 1 downto 0 do
  begin
    APending.Push(ANode[mIndex]);
  end;
end;

class procedure TResolverNodes.PushChildrenAround(APending: TStack<TSyntaxNode>; ANode: TSyntaxNode;
  AOffset: Integer);
var
  mIndex: Integer;
  mChild: TSyntaxNode;
begin
  for mIndex := ANode.ChildCount - 1 downto 0 do
  begin
    mChild := ANode[mIndex];
    if (mChild.StartOffset < AOffset) and (AOffset <= mChild.EndOffset) then
    begin
      APending.Push(mChild);
    end;
  end;
end;

class function TResolverNodes.RoutineHeaderOf(ARoutine: TSyntaxNode): TSyntaxNode;
begin
  if ARoutine.Kind = TSyntaxKind.AnonymousMethod then
  begin
    Result := ARoutine;
  end
  else
  begin
    Result := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
  end;
end;

class function TResolverNodes.NodeSource(ATree: TSyntaxTree; ANode: TSyntaxNode): string;
var
  mIndex, mLastEnd: Integer;
begin
  Result := '';
  mLastEnd := -1;
  // Ab dem ersten Token des Knotens statt ab Dateianfang und ohne Kopie je Token (#1323).
  for mIndex := ATree.FirstTokenFrom(ANode.StartOffset) to High(ATree.Tokens) do
  begin
    if ATree.Tokens[mIndex].Offset >= ANode.EndOffset then
    begin
      Break;
    end;
    if ATree.Tokens[mIndex].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive] then
    begin
      Continue;
    end;
    if (mLastEnd >= 0) and (ATree.Tokens[mIndex].Offset > mLastEnd) then
    begin
      Result := Result + ' ';
    end;
    Result := Result + ATree.Tokens[mIndex].Text;
    mLastEnd := ATree.Tokens[mIndex].Offset + Length(ATree.Tokens[mIndex].Text);
  end;
end;

class function TResolverNodes.DeclarationKind(ANode: TSyntaxNode): TIndexSymbolKind;
begin
  if ANode.Kind = TSyntaxKind.VarDecl then
  begin
    Result := TIndexSymbolKind.Variable;
  end
  else
  begin
    Result := TIndexSymbolKind.Constant;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Semantics.NameResolver.Symbols', cTexts);

end.
