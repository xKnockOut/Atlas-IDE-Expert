unit Atlas.Common.Rules.Builtin.Inheritance.Ancestry;

// Grundlage der Vererbungsregeln (Atlas.Common.Rules.Builtin.Inheritance und ihre Teilunits): TAncestry löst
// Vorfahren über die Datei und den Index auf, dazu die gemeinsamen Hilfen der Regeln (Methoden der Datei,
// Korrekturen für Direktiven und Anweisungen).

interface

uses
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Derived;

type
  /// <summary>Bereich ganzer Zeilen als Offsets ab 0: Anfang und Ende samt Zeilenumbruch.</summary>
  TLineSpan = record
    Start: Integer;
    Finish: Integer;
  end;

  /// <summary>Eine Methodendeklaration einer Klasse der geprüften Datei.</summary>
  TMethodDecl = record
    ClassName: string;
    Header: TSyntaxNode;
    Symbol: TIndexSymbol;
    /// <summary>procedure, function, constructor, destructor (klein).</summary>
    Keyword: string;
    Directives: TArray<string>;
    function Has(const ADirective: string): Boolean;
  end;

  /// <summary>Gefundene virtuelle Methode eines Vorfahren.</summary>
  TInherited = record
    Found: Boolean;
    TypeName: string;
    Symbol: TIndexSymbol;
    SameSignature: Boolean;
  end;

  /// <summary>Löst Vorfahren über die Datei und den Index auf; auch für die Komponentenregeln (#55).</summary>
  TAncestry = class
  private
    FIndex: ISymbolIndex;
    FLocal: TUnitIndex;
    // Symbole je Datei aus dem Index (FindFile kopierte je Abfrage den ganzen TUnitIndex) und Mitglieder je Typ
    // (vorher je Abfrage über alle Symbole der Unit, jedes als Kopie): Regeln fragen dieselben Klassen oft.
    FUnitSymbols: TDictionary<string, TArray<TIndexSymbol>>;
    FMembers: TDictionary<string, TArray<TIndexSymbol>>;
    /// <summary>Felder und Properties je Typ und Name (Schlüssel Typ #0 Name in Großbuchstaben): Indizes in
    /// MemberList, aufsteigend. FindMember suchte sonst je Name linear über alle Mitglieder; eine Klasse mit
    /// 1.000 Methoden machte shadowed-name quadratisch.</summary>
    FFieldsByName: TDictionary<string, TArray<Integer>>;
    /// <summary>Typen, deren Felder und Properties schon in FFieldsByName stehen.</summary>
    FFieldsIndexed: TDictionary<string, Boolean>;
    /// <summary>Methoden und Konstruktoren dieser Datei je Anfang (Zeile:Spalte): Indizes in FLocal.Symbols,
    /// aufsteigend; erst bei Bedarf angelegt. Je Methodendeklaration über alle Symbole gesucht war das quadratisch.
    /// </summary>
    FLocalMethodsAt: TDictionary<string, TArray<Integer>>;
    /// <summary>Legt FLocalMethodsAt an, falls es noch fehlt.</summary>
    procedure IndexLocalMethods;
    /// <summary>Symbole der Datei AFileName ('' = diese Datei); False, wenn der Index sie nicht kennt.</summary>
    function SymbolsOf(const AFileName: string; out ASymbols: TArray<TIndexSymbol>): Boolean;
    /// <summary>Felder, Properties, Methoden, Konstruktoren und Destruktoren von AType, je Typ einmal gesucht.
    /// </summary>
    function MemberList(const AType: TSymbolLocation): TArray<TIndexSymbol>;
    /// <summary>Indizes der Felder und Properties namens AName in MemberList(AType), aufsteigend.</summary>
    function FieldsNamed(const AType: TSymbolLocation; const AName: string): TArray<Integer>;
    function FindType(const AName: string; out AType: TSymbolLocation): Boolean;
    /// <summary>Klasse AName mit AArity Typparametern (#1326: THorseChannel und THorseChannel&lt;T&gt; sind zwei
    /// Typen); AArity &lt; 0 = Zahl unbekannt, jede passt.</summary>
    function FindTypeOf(const AName: string; AArity: Integer; out AType: TSymbolLocation): Boolean;
    /// <summary>Direkter Vorfahr von AType, mit der Zahl seiner Typargumente aufgelöst; TObject ohne Angabe.
    /// AName: sein Name ohne Unit und Typargumente.</summary>
    function ParentLocation(const AType: TSymbolLocation; out AName: string; out AParent: TSymbolLocation): Boolean;
    /// <summary>Ist der Treffer aus dem Index von dieser Datei aus sichtbar? Typen aus dem implementation-Teil
    /// anderer Units nicht (sonst wurde TFrame einer fremden Unit zum Vorfahren von VCL-Frames).</summary>
    function Reachable(const ALocation: TSymbolLocation): Boolean;
    function MethodsOf(const AType: TSymbolLocation; const AName: string): TArray<TIndexSymbol>;
  public
    /// <summary>ALocal ist der Index der geprüften Datei (TRuleDerived.UnitIndex).</summary>
    constructor Create(const AIndex: ISymbolIndex; const ALocal: TUnitIndex);
    destructor Destroy; override;
    /// <summary>Name des direkten Vorfahren; TObject ohne Angabe; '' wenn der Typ unbekannt ist.</summary>
    function ParentOf(const ATypeName: string): string;
    /// <summary>Erbt ATypeName (auch über mehrere Stufen) von AAncestor? False, wenn die Kette abbricht.</summary>
    function DescendsFrom(const ATypeName, AAncestor: string): Boolean;
    /// <summary>Deklariert die Klasse ATypeName selbst einen Konstruktor (Datei oder Index, #919)?</summary>
    function HasConstructor(const ATypeName: string): Boolean;
    /// <summary>Nächste gleichnamige Methode in den Vorfahren, falls sie virtuell ist.</summary>
    function InheritedVirtual(const AMethod: TMethodDecl): TInherited;
    /// <summary>Methode oder Konstruktor der Klasse ATypeName in dieser Datei, der bei APos beginnt.</summary>
    function LocalMethodAt(const ATypeName: string; const APos: TTextPosition; out ASymbol: TIndexSymbol): Boolean;
    /// <summary>Feld oder Property AName in ATypeName oder einem Vorfahren, das dort sichtbar ist (#934).
    /// Bricht die Kette ab, steht in AUnresolved der Vorfahr, der weder in der Datei noch im Index steht.</summary>
    function FindMember(const ATypeName, AName: string; out AMember: TIndexSymbol; out AUnresolved: string): Boolean;
      overload;
    /// <summary>Wie oben; AUnitName nennt die Unit der Klasse, die das Mitglied deklariert ('' für diese Datei).
    /// </summary>
    function FindMember(const ATypeName, AName: string; out AMember: TIndexSymbol; out AUnresolved,
      AUnitName: string): Boolean; overload;
    /// <summary>Vorfahren von ATypeName vom direkten an aufwärts (#997). AComplete: die Kette reicht bis TObject;
    /// AObjectMissing: TObject selbst steht weder in der Datei noch im Index.</summary>
    function Ancestors(const ATypeName: string; out AComplete, AObjectMissing: Boolean): TArray<TSymbolLocation>;
      overload;
    /// <summary>Wie oben ab dem schon gefundenen Typ AType (#1326): Bei gleichnamigen Typen mit und ohne
    /// Typparameter gilt so der richtige.</summary>
    function Ancestors(const AType: TSymbolLocation; out AComplete, AObjectMissing: Boolean): TArray<TSymbolLocation>;
      overload;
    /// <summary>Klasse dieser Datei, in deren Rumpf das Mitglied AMember steht (#1326); False ohne.</summary>
    function OwnerOf(const AMember: TIndexSymbol; out AType: TSymbolLocation): Boolean;
    /// <summary>Klasse AName aus der Datei oder eindeutig aus dem Index (#999).</summary>
    function FindClass(const AName: string; out AType: TSymbolLocation): Boolean;
    /// <summary>Methoden, Konstruktoren und Destruktoren der Klasse AType (#997).</summary>
    function Methods(const AType: TSymbolLocation): TArray<TIndexSymbol>;
    /// <summary>Abstrakte Methoden von AType und seinen Vorfahren, die keine nähere Stufe neu deklariert; AOwners
    /// nennt je Methode die Klasse (W1020, #1380). Überladungen unterscheidet die Zahl der Parameter. Bricht die
    /// Kette ab, fehlen nur die Methoden jenseits der Lücke.</summary>
    function OpenAbstractMethods(const AType: TSymbolLocation; out AOwners: TArray<string>): TArray<TIndexSymbol>;
    /// <summary>Ist AName in der Datei oder im Index als Typalias deklariert (type TModus = Integer)?</summary>
    function IsTypeAlias(const AName: string): Boolean;
    /// <summary>Ist AName in der Datei oder im Index als eigener Typ deklariert (Klasse, Record, Aufzählung,
    /// Interface), also kein Alias?</summary>
    function IsDeclaredType(const AName: string): Boolean;
    /// <summary>Typ AName jeder Art (Klasse, Record, Interface, Aufzählung, Alias) aus der Datei oder dem Index
    /// (#1001); bei mehreren gleichnamigen der erste.</summary>
    function FindAnyType(const AName: string; out AType: TSymbolLocation): Boolean;
    /// <summary>In AOwner dieser Unit geschachtelter Typ AName; geht vor gleichnamigen Typen anderer Units.</summary>
    function FindNestedType(const AOwner, AName: string; out AType: TSymbolLocation): Boolean;
    /// <summary>Felder, Properties, Methoden und Konstruktoren des Typs AType (#1001).</summary>
    function Members(const AType: TSymbolLocation): TArray<TIndexSymbol>;
    /// <summary>Bezeichnen A und B denselben Typ? Synonyme (Longint, Integer) gleich; Typparameter aus
    /// AWildcards und Aliase der Datei oder des Index passen zu allem (#997, #1001).</summary>
    function SameType(const A, B: string; const AWildcards: TArray<string>): Boolean;
    /// <summary>Steht der Typ sicher für sich (eingebaut oder als Klasse, Record, Aufzählung deklariert)?</summary>
    function KnownType(const AName: string): Boolean;
    property Local: TUnitIndex read FLocal;
  end;

const
  // Virtuelle Instanzmethoden von TObject, falls System nicht im Index steht.
  cObjectVirtualNames: array[0..9] of string = ('AfterConstruction', 'BeforeDestruction', 'Dispatch',
    'DefaultHandler', 'FreeInstance', 'Destroy', 'SafeCallException', 'ToString', 'Equals', 'GetHashCode');

/// <summary>Typname ohne Unit-Präfix und Typargumente.</summary>
function BareName(const AName: string): string;
/// <summary>Liegt die Zeile ALine im Bereich ARange?</summary>
function ContainsLine(const ARange: TTextRange; ALine: Integer): Boolean;
/// <summary>Gleiche Parameter (Zahl, Typen ohne Unit) und gleiches Ergebnis?</summary>
function SameSignature(const A, B: TIndexSymbol): Boolean;
/// <summary>Token am Offset AOffset; False ohne.</summary>
function TokenAt(const AContext: TRuleContext; AOffset: Integer; out AToken: TPascalToken): Boolean;
/// <summary>Korrektur, die " ADirective;" hinter den Methodenkopf setzt.</summary>
function AppendDirective(const AContext: TRuleContext; const AMethod: TMethodDecl; const ADirective: string;
  out AFix: TRuleFix): Boolean;
/// <summary>Erweitert [AStart, AEnd) (Offsets ab 0) auf ganze Zeilen samt Zeilenumbruch, wenn davor und dahinter
/// auf der Zeile nur Leerraum steht; sonst False. ADocComments: darüberstehende ///-Zeilen gehören dazu.
/// ABlankAfter: Steht über dem Bereich eine Leerzeile, fällt auch eine Leerzeile dahinter weg.</summary>
function WholeLineSpan(const AText: string; AStart, AEnd: Integer; ADocComments, ABlankAfter: Boolean;
  out ASpan: TLineSpan): Boolean;
/// <summary>Korrektur, die die Anweisung AStatement samt Semikolon entfernt, allein auf der Zeile die ganze Zeile.
/// </summary>
function RemoveStatementFix(const ACache: IRuleDerivedCache; const AContext: TRuleContext; AStatement: TSyntaxNode;
  const ATitle: string): TRuleFix;
/// <summary>Methodendeklarationen aller Klassen der Datei.</summary>
function ClassMethods(const AContext: TRuleContext; AAncestry: TAncestry): TArray<TMethodDecl>;
/// <summary>destructor Destroy ohne Parameter?</summary>
function IsDestroy(const AMethod: TMethodDecl): Boolean;
/// <summary>constructor Create(AOwner: TComponent)?</summary>
function IsComponentCreate(const AMethod: TMethodDecl): Boolean;
/// <summary>Wird das Verdecken bereits bewusst angezeigt oder gelöst?</summary>
function Settled(const AMethod: TMethodDecl): Boolean;
/// <summary>Methoden der Datei ohne override/reintroduce; False ohne Syntaxbaum.
/// AAncestry gehört dem Aufrufer.</summary>
function Prepare(const AContext: TRuleContext; out AAncestry: TAncestry; out AMethods: TArray<TMethodDecl>): Boolean;
/// <summary>Ein Mitglied ASymbol der Stufe ALocation ist für Nachfahren unsichtbar: strict private, oder private in
/// einer anderen Unit.</summary>
function InvisibleToDescendant(const ALocation: TSymbolLocation; const ASymbol: TIndexSymbol): Boolean;
/// <summary>Dateiname der geprüften Datei für den Namensauflöser: FileName, sonst RelativePath, sonst
/// Unitname.pas.</summary>
function ResolverFileName(const AContext: TRuleContext): string;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.ClassActions,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TInheritanceAncestryText = (AddName);

const
  cTexts: array[TInheritanceAncestryText] of TAtlasText = (
    (De: '"%s" ergänzen'; En: 'Add "%s"'));

{$SCOPEDENUMS OFF}

function TMethodDecl.Has(const ADirective: string): Boolean;
begin
  Result := MatchText(ADirective, Directives);
end;

/// <summary>Typname ohne Unit-Präfix und Typargumente.</summary>
function BareName(const AName: string): string;
begin
  Result := AName;
  if Pos('<', Result) > 0 then
  begin
    Result := Copy(Result, 1, Pos('<', Result) - 1);
  end;
  Result := Copy(Result, LastDelimiter('.', Result) + 1, MaxInt);
end;

function ContainsLine(const ARange: TTextRange; ALine: Integer): Boolean;
begin
  Result := (ALine >= ARange.StartPos.Line) and (ALine <= ARange.EndPos.Line);
end;

function SameSignature(const A, B: TIndexSymbol): Boolean;
var
  mIndex: Integer;
begin
  Result := (A.MaxArgs = B.MaxArgs) and (Length(A.ParamTypes) = Length(B.ParamTypes)) and
    SameText(A.TypeName, B.TypeName);
  if Result then
  begin
    for mIndex := 0 to High(A.ParamTypes) do
    begin
      if not SameText(BareName(A.ParamTypes[mIndex]), BareName(B.ParamTypes[mIndex])) then
      begin
        Exit(False);
      end;
    end;
  end;
end;

const
  // Gleiche Typen unter anderem Namen: Name=Grundname.
  cTypeSynonyms: array[0..17] of string = ('longint=integer', 'int32=integer', 'longword=cardinal',
    'uint32=cardinal', 'dword=cardinal', 'unicodestring=string', 'widechar=char', 'pwidechar=pchar',
    'intptr=nativeint', 'uintptr=nativeuint', 'int16=smallint', 'int8=shortint', 'uint8=byte', 'uint16=word',
    'real=double', 'tobject=tobject', 'system.tobject=tobject', 'hresult=hresult');
  // Eingebaute Typen, die sicher kein Alias eines anderen sind.
  cBuiltinTypes: array[0..25] of string = ('integer', 'cardinal', 'int64', 'uint64', 'string', 'ansistring',
    'shortstring', 'widestring', 'char', 'ansichar', 'boolean', 'double', 'single', 'extended', 'currency', 'byte',
    'word', 'smallint', 'shortint', 'pointer', 'variant', 'tobject', 'nativeint', 'nativeuint', 'pchar',
    'tdatetime');

function CanonicalType(const AName: string): string;
var
  mPair: string;
begin
  Result := LowerCase(BareName(AName));
  for mPair in cTypeSynonyms do
  begin
    if StartsStr(Result + '=', mPair) then
    begin
      Exit(Copy(mPair, Length(Result) + 2, MaxInt));
    end;
  end;
end;

{ TAncestry }

constructor TAncestry.Create(const AIndex: ISymbolIndex; const ALocal: TUnitIndex);
begin
  inherited Create;
  FIndex := AIndex;
  FLocal := ALocal;
  FUnitSymbols := TDictionary<string, TArray<TIndexSymbol>>.Create;
  FMembers := TDictionary<string, TArray<TIndexSymbol>>.Create;
  FFieldsByName := TDictionary<string, TArray<Integer>>.Create;
  FFieldsIndexed := TDictionary<string, Boolean>.Create;
end;

/// <summary>Schlüssel einer Stelle für FLocalMethodsAt.</summary>
function PositionKey(const APos: TTextPosition): string;
begin
  Result := IntToStr(APos.Line) + ':' + IntToStr(APos.Character);
end;

procedure TAncestry.IndexLocalMethods;
var
  mIndex: Integer;
  mKey: string;
  mFound: TArray<Integer>;
begin
  if FLocalMethodsAt <> nil then
  begin
    Exit;
  end;
  FLocalMethodsAt := TDictionary<string, TArray<Integer>>.Create;
  for mIndex := 0 to High(FLocal.Symbols) do
  begin
    if FLocal.Symbols[mIndex].Kind in [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_] then
    begin
      mKey := PositionKey(FLocal.Symbols[mIndex].Range.StartPos);
      if not FLocalMethodsAt.TryGetValue(mKey, mFound) then
      begin
        mFound := nil;
      end;
      FLocalMethodsAt.AddOrSetValue(mKey, mFound + [mIndex]);
    end;
  end;
end;

function TAncestry.LocalMethodAt(const ATypeName: string; const APos: TTextPosition;
  out ASymbol: TIndexSymbol): Boolean;
var
  mIndex: Integer;
  mFound: TArray<Integer>;
begin
  IndexLocalMethods;
  if FLocalMethodsAt.TryGetValue(PositionKey(APos), mFound) then
  begin
    for mIndex in mFound do
    begin
      if SameText(FLocal.Symbols[mIndex].Container, ATypeName) then
      begin
        ASymbol := FLocal.Symbols[mIndex];
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

destructor TAncestry.Destroy;
begin
  FLocalMethodsAt.Free;
  FFieldsIndexed.Free;
  FFieldsByName.Free;
  FMembers.Free;
  FUnitSymbols.Free;
  inherited;
end;

function TAncestry.SymbolsOf(const AFileName: string; out ASymbols: TArray<TIndexSymbol>): Boolean;
var
  mKey: string;
  mUnit: TUnitIndex;
begin
  if AFileName = '' then
  begin
    ASymbols := FLocal.Symbols;
    Exit(True);
  end;
  mKey := AnsiLowerCase(AFileName);
  if FUnitSymbols.TryGetValue(mKey, ASymbols) then
  begin
    Exit(True);
  end;
  Result := (FIndex <> nil) and FIndex.FindFile(AFileName, mUnit);
  if not Result then
  begin
    Exit;
  end;
  ASymbols := mUnit.Symbols;
  FUnitSymbols.Add(mKey, ASymbols);
end;

/// <summary>Schlüssel eines Typs für die Caches von TAncestry.</summary>
function TypeKey(const AType: TSymbolLocation): string;
begin
  Result := AnsiLowerCase(AType.FileName) + '|' + AnsiLowerCase(AType.Symbol.Name) + '|' +
    IntToStr(AType.Symbol.Range.StartPos.Line) + ':' + IntToStr(AType.Symbol.Range.EndPos.Line);
end;

function TAncestry.FieldsNamed(const AType: TSymbolLocation; const AName: string): TArray<Integer>;
var
  mType, mKey: string;
  mMembers: TArray<TIndexSymbol>;
  mIndex: Integer;
  mFound: TArray<Integer>;
begin
  mType := TypeKey(AType);
  if not FFieldsIndexed.ContainsKey(mType) then
  begin
    mMembers := MemberList(AType);
    for mIndex := 0 to High(mMembers) do
    begin
      if mMembers[mIndex].Kind in [TIndexSymbolKind.Field, TIndexSymbolKind.Property_] then
      begin
        mKey := mType + #0 + UpperCase(mMembers[mIndex].Name);
        if not FFieldsByName.TryGetValue(mKey, mFound) then
        begin
          mFound := nil;
        end;
        FFieldsByName.AddOrSetValue(mKey, mFound + [mIndex]);
      end;
    end;
    FFieldsIndexed.Add(mType, True);
  end;
  if not FFieldsByName.TryGetValue(mType + #0 + UpperCase(AName), Result) then
  begin
    Result := nil;
  end;
end;

function TAncestry.MemberList(const AType: TSymbolLocation): TArray<TIndexSymbol>;
var
  mKey, mOwner: string;
  mSymbols: TArray<TIndexSymbol>;
  mFound: TList<TIndexSymbol>;
  mIndex: Integer;
begin
  mKey := TypeKey(AType);
  // Member geschachtelter Typen tragen den ganzen Pfad als Container (TAussen.TInnen).
  mOwner := AType.Symbol.Name;
  if AType.Symbol.Container <> '' then
  begin
    mOwner := AType.Symbol.Container + '.' + mOwner;
  end;
  if FMembers.TryGetValue(mKey, Result) then
  begin
    Exit;
  end;
  Result := nil;
  if SymbolsOf(AType.FileName, mSymbols) then
  begin
    mFound := TList<TIndexSymbol>.Create;
    try
      // Über den Index, damit nur die Treffer kopiert werden.
      for mIndex := 0 to High(mSymbols) do
      begin
        if (mSymbols[mIndex].Kind in [TIndexSymbolKind.Field, TIndexSymbolKind.Property_, TIndexSymbolKind.Method,
          TIndexSymbolKind.Constructor_]) and SameText(mSymbols[mIndex].Container, mOwner) and
          ContainsLine(AType.Symbol.Range, mSymbols[mIndex].Range.StartPos.Line) then
        begin
          mFound.Add(mSymbols[mIndex]);
        end;
      end;
      Result := mFound.ToArray;
    finally
      mFound.Free;
    end;
  end;
  FMembers.Add(mKey, Result);
end;

function TAncestry.Reachable(const ALocation: TSymbolLocation): Boolean;
begin
  Result := ALocation.Symbol.InInterface or (ALocation.FileName = '') or SameText(ALocation.FileName, FLocal.FileName);
end;

/// <summary>Zahl der Einträge in einer Liste von Typparametern bzw. -argumenten ("K, V", "string, TList&lt;T&gt;");
/// 0 bei ''.</summary>
function GenericArity(const AList: string): Integer;
var
  mIndex, mDepth: Integer;
begin
  Result := 0;
  if Trim(AList) = '' then
  begin
    Exit;
  end;
  Result := 1;
  mDepth := 0;
  for mIndex := 1 to Length(AList) do
    case AList[mIndex] of
      '<', '(', '[':
        Inc(mDepth);
      '>', ')', ']':
        Dec(mDepth);
      ',':
        if mDepth = 0 then
        begin
          Inc(Result);
        end;
    end;
end;

/// <summary>Zahl der Typargumente in einem Namen wie "TFoo&lt;T, U&gt;"; -1 ohne spitze Klammern (unbekannt: Die
/// Regeln geben Klassen generischer Typen oft ohne Parameter weiter).</summary>
function NameArity(const AName: string): Integer;
var
  mOpen: Integer;
begin
  mOpen := Pos('<', AName);
  if mOpen = 0 then
  begin
    Exit(-1);
  end;
  Result := GenericArity(Copy(AName, mOpen + 1, LastDelimiter('>', AName) - mOpen - 1));
end;

function TAncestry.FindType(const AName: string; out AType: TSymbolLocation): Boolean;
var
  mName: string;
begin
  mName := AName;
  if Pos('<', mName) > 0 then
  begin
    mName := Copy(mName, 1, Pos('<', mName) - 1);
  end;
  Result := FindTypeOf(mName, NameArity(AName), AType);
end;

/// <summary>Klasse AName auf oberster Ebene mit AArity Typparametern (AArity &lt; 0: jede Zahl)?</summary>
function IsClassNamed(const ASymbol: TIndexSymbol; const AName: string; AArity: Integer): Boolean;
begin
  Result := (ASymbol.Kind = TIndexSymbolKind.ClassType) and (ASymbol.Container = '') and SameText(ASymbol.Name, AName);
  Result := Result and ((AArity < 0) or (GenericArity(ASymbol.TypeParams) = AArity));
end;

/// <summary>Haben die gleichnamigen Klassen A und B verschiedene direkte Vorfahren?</summary>
function OtherAncestors(const A, B: TIndexSymbol): Boolean;
begin
  Result := (Length(A.Ancestors) > 0) <> (Length(B.Ancestors) > 0);
  Result := Result or ((Length(B.Ancestors) > 0) and not SameText(BareName(A.Ancestors[0]),
    BareName(B.Ancestors[0])));
end;

function TAncestry.FindTypeOf(const AName: string; AArity: Integer; out AType: TSymbolLocation): Boolean;
var
  mIndex: Integer;
  mLocation: TSymbolLocation;
begin
  // Über den Index: for-in kopierte jedes Symbol der Datei, auch die vielen, die nicht passen.
  for mIndex := 0 to High(FLocal.Symbols) do
  begin
    if IsClassNamed(FLocal.Symbols[mIndex], AName, AArity) then
    begin
      AType := Default(TSymbolLocation);
      AType.Symbol := FLocal.Symbols[mIndex];
      Exit(True);
    end;
  end;
  Result := False;
  if FIndex = nil then
  begin
    Exit;
  end;
  for mLocation in FIndex.FindSymbols(AName) do
  begin
    if not IsClassNamed(mLocation.Symbol, AName, AArity) or not Reachable(mLocation) then
    begin
      Continue;
    end;
    if not Result then
    begin
      AType := mLocation;
      Result := True;
    end
    // Mehrere gleichnamige Klassen mit verschiedenen Vorfahren: keine Aussage.
    else if OtherAncestors(mLocation.Symbol, AType.Symbol) then
    begin
      Exit(False);
    end;
  end;
end;

function TAncestry.Methods(const AType: TSymbolLocation): TArray<TIndexSymbol>;
var
  mSymbol: TIndexSymbol;
begin
  Result := nil;
  for mSymbol in Members(AType) do
  begin
    if mSymbol.Kind in [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_] then
    begin
      Result := Result + [mSymbol];
    end;
  end;
end;

function TAncestry.Members(const AType: TSymbolLocation): TArray<TIndexSymbol>;
begin
  // Eigene Kopie: Aufrufer dürfen das Ergebnis ändern, ohne den Vorrat zu berühren.
  Result := Copy(MemberList(AType));
end;

function TAncestry.FindAnyType(const AName: string; out AType: TSymbolLocation): Boolean;
const
  cKinds = [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType,
    TIndexSymbolKind.InterfaceType, TIndexSymbolKind.EnumType, TIndexSymbolKind.TypeAlias];
var
  mIndex: Integer;
  mLocation: TSymbolLocation;
begin
  for mIndex := 0 to High(FLocal.Symbols) do
  begin
    if (FLocal.Symbols[mIndex].Kind in cKinds) and (FLocal.Symbols[mIndex].Container = '') and
      SameText(FLocal.Symbols[mIndex].Name, AName) then
    begin
      AType := Default(TSymbolLocation);
      AType.Symbol := FLocal.Symbols[mIndex];
      Exit(True);
    end;
  end;
  if FIndex <> nil then
  begin
    for mLocation in FIndex.FindSymbols(AName) do
    begin
      if (mLocation.Symbol.Kind in cKinds) and (mLocation.Symbol.Container = '') and Reachable(mLocation) then
      begin
        AType := mLocation;
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

function TAncestry.FindNestedType(const AOwner, AName: string; out AType: TSymbolLocation): Boolean;
const
  cKinds = [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType,
    TIndexSymbolKind.InterfaceType, TIndexSymbolKind.EnumType, TIndexSymbolKind.TypeAlias];
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(FLocal.Symbols) do
  begin
    if (FLocal.Symbols[mIndex].Kind in cKinds) and SameText(FLocal.Symbols[mIndex].Name, AName) and
      (AOwner <> '') and SameText(FLocal.Symbols[mIndex].Container, AOwner) then
    begin
      AType := Default(TSymbolLocation);
      AType.Symbol := FLocal.Symbols[mIndex];
      Exit(True);
    end;
  end;
  Result := False;
end;

function TAncestry.SameType(const A, B: string; const AWildcards: TArray<string>): Boolean;
begin
  Result := (CanonicalType(A) = CanonicalType(B)) or MatchText(BareName(A), AWildcards) or
    MatchText(BareName(B), AWildcards);
  // Ein Alias der Datei oder des Index kann auf den anderen Typ zeigen: keine Aussage.
  if not Result and (A <> '') and (B <> '') then
  begin
    Result := IsTypeAlias(BareName(A)) or IsTypeAlias(BareName(B));
  end;
end;

function TAncestry.KnownType(const AName: string): Boolean;
begin
  Result := MatchText(CanonicalType(AName), cBuiltinTypes) or IsDeclaredType(BareName(AName));
end;

function TAncestry.OpenAbstractMethods(const AType: TSymbolLocation; out AOwners: TArray<string>):
  TArray<TIndexSymbol>;
var
  mChain: TArray<TSymbolLocation>;
  mLocation: TSymbolLocation;
  mSymbol: TIndexSymbol;
  mSeen, mLevel: TArray<string>;
  mKey: string;
  mComplete, mObjectMissing: Boolean;
begin
  Result := nil;
  AOwners := nil;
  mSeen := nil;
  mChain := [AType] + Ancestors(AType.Symbol.Name, mComplete, mObjectMissing);
  for mLocation in mChain do
  begin
    mLevel := nil;
    for mSymbol in Methods(mLocation) do
    begin
      // Überladungen unterscheidet die Zahl der Parameter; gleich viele gelten als dieselbe Methode.
      mKey := LowerCase(mSymbol.Name) + '/' + IntToStr(mSymbol.MaxArgs);
      if mSymbol.HasDirective('abstract') and (IndexText(mKey, mSeen) < 0) then
      begin
        Result := Result + [mSymbol];
        AOwners := AOwners + [mLocation.Symbol.Name];
      end;
      mLevel := mLevel + [mKey];
    end;
    mSeen := mSeen + mLevel;
  end;
end;

function TAncestry.MethodsOf(const AType: TSymbolLocation; const AName: string): TArray<TIndexSymbol>;
var
  mSymbol: TIndexSymbol;
begin
  Result := nil;
  for mSymbol in Methods(AType) do
  begin
    if SameText(mSymbol.Name, AName) then
    begin
      Result := Result + [mSymbol];
    end;
  end;
end;

function TAncestry.ParentLocation(const AType: TSymbolLocation; out AName: string;
  out AParent: TSymbolLocation): Boolean;
var
  mArity: Integer;
begin
  if Length(AType.Symbol.Ancestors) = 0 then
  begin
    AName := 'TObject';
    mArity := 0;
  end
  else
  begin
    AName := BareName(AType.Symbol.Ancestors[0]);
    // Ohne Typargumente ist der Vorfahr nicht generisch: class(THorseChannel) neben THorseChannel<T>.
    mArity := 0;
    if Length(AType.Symbol.AncestorArgs) > 0 then
    begin
      mArity := GenericArity(AType.Symbol.AncestorArgs[0]);
    end;
  end;
  Result := FindTypeOf(AName, mArity, AParent);
end;

function TAncestry.Ancestors(const ATypeName: string; out AComplete, AObjectMissing: Boolean): TArray<TSymbolLocation>;
var
  mOwn: TSymbolLocation;
begin
  Result := nil;
  AComplete := False;
  AObjectMissing := False;
  if FindType(ATypeName, mOwn) then
  begin
    Result := Ancestors(mOwn, AComplete, AObjectMissing);
  end;
end;

function TAncestry.Ancestors(const AType: TSymbolLocation; out AComplete,
  AObjectMissing: Boolean): TArray<TSymbolLocation>;
var
  mName: string;
  mCurrent, mLocation: TSymbolLocation;
  mDepth: Integer;
begin
  Result := nil;
  AComplete := False;
  AObjectMissing := False;
  mCurrent := AType;
  for mDepth := 0 to 63 do
  begin
    if not ParentLocation(mCurrent, mName, mLocation) then
    begin
      AObjectMissing := SameText(mName, 'TObject');
      AComplete := AObjectMissing;
      Exit;
    end;
    Result := Result + [mLocation];
    if SameText(mName, 'TObject') then
    begin
      AComplete := True;
      Exit;
    end;
    mCurrent := mLocation;
  end;
end;

function TAncestry.OwnerOf(const AMember: TIndexSymbol; out AType: TSymbolLocation): Boolean;
var
  mSymbol: TIndexSymbol;
begin
  for mSymbol in FLocal.Symbols do
  begin
    if (mSymbol.Kind = TIndexSymbolKind.ClassType) and SameText(mSymbol.QualifiedName, AMember.Container) and
      ContainsLine(mSymbol.Range, AMember.Range.StartPos.Line) then
    begin
      AType := Default(TSymbolLocation);
      AType.Symbol := mSymbol;
      Exit(True);
    end;
  end;
  Result := False;
end;

function TAncestry.FindClass(const AName: string; out AType: TSymbolLocation): Boolean;
begin
  Result := FindType(AName, AType);
end;

function TAncestry.IsDeclaredType(const AName: string): Boolean;
const
  cKinds = [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType,
    TIndexSymbolKind.InterfaceType, TIndexSymbolKind.EnumType];
var
  mIndex: Integer;
  mLocation: TSymbolLocation;
begin
  for mIndex := 0 to High(FLocal.Symbols) do
  begin
    if (FLocal.Symbols[mIndex].Kind in cKinds) and (FLocal.Symbols[mIndex].Container = '') and
      SameText(FLocal.Symbols[mIndex].Name, AName) then
    begin
      Exit(True);
    end;
  end;
  if FIndex <> nil then
  begin
    for mLocation in FIndex.FindSymbols(AName) do
    begin
      if (mLocation.Symbol.Kind in cKinds) and (mLocation.Symbol.Container = '') and Reachable(mLocation) then
      begin
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

function TAncestry.IsTypeAlias(const AName: string): Boolean;
var
  mIndex: Integer;
  mLocation: TSymbolLocation;
begin
  for mIndex := 0 to High(FLocal.Symbols) do
  begin
    if (FLocal.Symbols[mIndex].Kind = TIndexSymbolKind.TypeAlias) and SameText(FLocal.Symbols[mIndex].Name, AName) then
    begin
      Exit(True);
    end;
  end;
  if FIndex <> nil then
  begin
    for mLocation in FIndex.FindSymbols(AName) do
    begin
      if (mLocation.Symbol.Kind = TIndexSymbolKind.TypeAlias) and Reachable(mLocation) then
      begin
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

function TAncestry.HasConstructor(const ATypeName: string): Boolean;
var
  mLocation: TSymbolLocation;
  mMembers: TArray<TIndexSymbol>;
  mIndex: Integer;
begin
  Result := False;
  if not FindType(ATypeName, mLocation) then
  begin
    Exit;
  end;
  mMembers := MemberList(mLocation);
  for mIndex := 0 to High(mMembers) do
  begin
    // Der Index führt Destruktoren ebenfalls als Constructor_.
    if (mMembers[mIndex].Kind = TIndexSymbolKind.Constructor_) and not SameText(mMembers[mIndex].Name, 'Destroy') then
    begin
      Exit(True);
    end;
  end;
end;

function TAncestry.ParentOf(const ATypeName: string): string;
var
  mLocation: TSymbolLocation;
begin
  if not FindType(ATypeName, mLocation) then
  begin
    Exit('');
  end;
  if Length(mLocation.Symbol.Ancestors) = 0 then
  begin
    Result := 'TObject';
  end
  else
  begin
    Result := BareName(mLocation.Symbol.Ancestors[0]);
  end;
end;

function TAncestry.DescendsFrom(const ATypeName, AAncestor: string): Boolean;
var
  mName: string;
  mDepth: Integer;
begin
  mName := ParentOf(ATypeName);
  mDepth := 0;
  while (mName <> '') and (mDepth < 64) do
  begin
    if SameText(mName, AAncestor) then
    begin
      Exit(True);
    end;
    if SameText(mName, 'TObject') then
    begin
      Break;
    end;
    mName := ParentOf(mName);
    Inc(mDepth);
  end;
  Result := False;
end;

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

function InvisibleToDescendant(const ALocation: TSymbolLocation; const ASymbol: TIndexSymbol): Boolean;
begin
  Result := (ASymbol.Visibility = TIndexVisibility.StrictPrivate) or ((ALocation.FileName <> '') and
    (ASymbol.Visibility = TIndexVisibility.Private));
end;

/// <summary>Sieht der Nachfahre die Methode ACandidate des Vorfahren ALocation nicht (private einer fremden Unit)?
/// </summary>
function HiddenFromDescendant(const ALocation: TSymbolLocation; const ACandidate: TIndexSymbol): Boolean;
begin
  Result := (ALocation.FileName <> '') and (ACandidate.Visibility in [TIndexVisibility.Private,
    TIndexVisibility.StrictPrivate]);
end;

/// <summary>Übernimmt die virtuelle Methode ACandidate aus ALocation, wenn noch keine gefunden ist oder sie anders
/// als die bisherige dieselbe Signatur wie AMethod hat.</summary>
procedure TakeVirtual(var AResult: TInherited; const ALocation: TSymbolLocation; const ACandidate,
  AMethod: TIndexSymbol);
begin
  if not AResult.Found or (not AResult.SameSignature and SameSignature(ACandidate, AMethod)) then
  begin
    AResult.Found := True;
    AResult.TypeName := ALocation.Symbol.Name;
    AResult.Symbol := ACandidate;
    AResult.SameSignature := SameSignature(ACandidate, AMethod);
  end;
end;

function TAncestry.InheritedVirtual(const AMethod: TMethodDecl): TInherited;
var
  mOwn, mLocation: TSymbolLocation;
  mCandidate: TIndexSymbol;
  mAny, mComplete, mObjectMissing: Boolean;
begin
  Result := Default(TInherited);
  // Die Klasse, in deren Rumpf die Methode steht, nicht nur ihr Name (#1326).
  if not OwnerOf(AMethod.Symbol, mOwn) and not FindType(AMethod.ClassName, mOwn) then
  begin
    Exit;
  end;
  for mLocation in Ancestors(mOwn, mComplete, mObjectMissing) do
  begin
    mAny := False;
    for mCandidate in MethodsOf(mLocation, AMethod.Symbol.Name) do
    begin
      // Private Methoden fremder Units sieht der Nachfahre nicht.
      if HiddenFromDescendant(mLocation, mCandidate) then
      begin
        Continue;
      end;
      mAny := True;
      if mCandidate.IsVirtual then
      begin
        TakeVirtual(Result, mLocation, mCandidate, AMethod.Symbol);
      end;
    end;
    // Die nächste Stufe mit gleichnamiger Methode entscheidet.
    if mAny then
    begin
      Exit;
    end;
  end;
end;

{ Hilfen für die Regeln }

function TokenAt(const AContext: TRuleContext; AOffset: Integer; out AToken: TPascalToken): Boolean;
var
  mToken: TPascalToken;
begin
  for mToken in AContext.Tree.Tokens do
  begin
    if mToken.Offset = AOffset then
    begin
      AToken := mToken;
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Position hinter dem letzten Token vor AEndOffset.</summary>
function EndPosition(const AContext: TRuleContext; AEndOffset: Integer; out APosition: TTextPosition): Boolean;
var
  mToken: TPascalToken;
begin
  Result := False;
  for mToken in AContext.Tree.Tokens do
  begin
    if mToken.Offset >= AEndOffset then
    begin
      Break;
    end;
    if mToken.Offset + Length(mToken.Text) = AEndOffset then
    begin
      APosition := mToken.EndPos;
      Result := True;
    end;
  end;
end;

/// <summary>Korrektur, die " ADirective;" hinter den Methodenkopf setzt.</summary>
function AppendDirective(const AContext: TRuleContext; const AMethod: TMethodDecl; const ADirective: string;
  out AFix: TRuleFix): Boolean;
var
  mPosition: TTextPosition;
begin
  Result := EndPosition(AContext, AMethod.Header.EndOffset, mPosition);
  if Result then
  begin
    AFix := TRuleFix.Create(cTexts[TInheritanceAncestryText.AddName].Fmt([ADirective]),
      [TRuleEdit.Create(TTextRange.Create(mPosition, mPosition), ' ' + ADirective + ';')]);
  end;
end;

/// <summary>Anfang der Zeile vor der Zeile, die bei AOffset beginnt; AContent ist ihr Text.</summary>
function PreviousLine(const AText: string; AOffset: Integer; out AContent: string): Integer;
var
  mEnd: Integer;
begin
  mEnd := AOffset - 1;
  if (mEnd > 0) and (AText[mEnd] = #13) then
  begin
    Dec(mEnd);
  end;
  Result := mEnd;
  while (Result > 0) and not CharInSet(AText[Result], [#10, #13]) do
  begin
    Dec(Result);
  end;
  AContent := Copy(AText, Result + 1, mEnd - Result);
end;

/// <summary>Ende der Zeile, die bei AOffset beginnt, samt Zeilenumbruch; AContent ist ihr Text.</summary>
function LineEndFrom(const AText: string; AOffset: Integer; out AContent: string): Integer;
begin
  Result := AOffset;
  while (Result < Length(AText)) and not CharInSet(AText[Result + 1], [#10, #13]) do
  begin
    Inc(Result);
  end;
  AContent := Copy(AText, AOffset + 1, Result - AOffset);
  if (Result < Length(AText)) and (AText[Result + 1] = #13) then
  begin
    Inc(Result);
  end;
  if (Result < Length(AText)) and (AText[Result + 1] = #10) then
  begin
    Inc(Result);
  end;
end;

/// <summary>Steht vor AStart und hinter AEnd auf der Zeile nur Leerraum? Dann ist ASpan von der Zeile bis vor den
/// Zeilenumbruch hinter AEnd erweitert.</summary>
function OwnLine(const AText: string; AStart, AEnd: Integer; out ASpan: TLineSpan): Boolean;
begin
  ASpan.Start := AStart;
  while (ASpan.Start > 0) and CharInSet(AText[ASpan.Start], [' ', #9]) do
  begin
    Dec(ASpan.Start);
  end;
  ASpan.Finish := AEnd;
  while (ASpan.Finish < Length(AText)) and CharInSet(AText[ASpan.Finish + 1], [' ', #9]) do
  begin
    Inc(ASpan.Finish);
  end;
  Result := ((ASpan.Start = 0) or CharInSet(AText[ASpan.Start], [#10, #13])) and
    ((ASpan.Finish >= Length(AText)) or CharInSet(AText[ASpan.Finish + 1], [#10, #13]));
end;

/// <summary>Anfang der ///-Zeilen direkt über der Zeile, die bei AStart beginnt; AStart ohne.</summary>
function DocCommentStart(const AText: string; AStart: Integer): Integer;
var
  mPrevious: Integer;
  mContent: string;
  mDone: Boolean;
begin
  Result := AStart;
  mDone := False;
  while not mDone and (Result > 0) do
  begin
    mPrevious := PreviousLine(AText, Result, mContent);
    mDone := not StartsStr('///', TrimLeft(mContent));
    if not mDone then
    begin
      Result := mPrevious;
    end;
  end;
end;

function WholeLineSpan(const AText: string; AStart, AEnd: Integer; ADocComments, ABlankAfter: Boolean;
  out ASpan: TLineSpan): Boolean;
var
  mNext: Integer;
  mContent: string;
begin
  Result := OwnLine(AText, AStart, AEnd, ASpan);
  if not Result then
  begin
    Exit;
  end;
  ASpan.Finish := LineEndFrom(AText, ASpan.Finish, mContent);
  if ADocComments then
  begin
    ASpan.Start := DocCommentStart(AText, ASpan.Start);
  end;
  // Die Leerzeile hinter dem Rumpf trennte ihn vom Nächsten; sie geht mit.
  if ABlankAfter and (ASpan.Finish < Length(AText)) then
  begin
    mNext := LineEndFrom(AText, ASpan.Finish, mContent);
    if Trim(mContent) = '' then
    begin
      ASpan.Finish := mNext;
    end;
  end;
end;

/// <summary>Korrektur, die die Anweisung AStatement samt Semikolon entfernt, allein auf der Zeile die ganze Zeile.
/// </summary>
function RemoveStatementFix(const ACache: IRuleDerivedCache; const AContext: TRuleContext; AStatement: TSyntaxNode;
  const ATitle: string): TRuleFix;
var
  mText: string;
  mStart, mEnd: Integer;
  mSpan: TLineSpan;
begin
  mText := AContext.Text;
  mStart := AStatement.StartOffset;
  mEnd := AStatement.EndOffset;
  while (mEnd < Length(mText)) and CharInSet(mText[mEnd + 1], [' ', #9]) do
  begin
    Inc(mEnd);
  end;
  if (mEnd < Length(mText)) and (mText[mEnd + 1] = ';') then
  begin
    Inc(mEnd);
  end
  else
  begin
    mEnd := AStatement.EndOffset;
  end;
  if WholeLineSpan(mText, mStart, mEnd, False, False, mSpan) then
  begin
    mStart := mSpan.Start;
    mEnd := mSpan.Finish;
  end;
  Result := TRuleFix.Create(ATitle, [TRuleEdit.Create(TRuleDerived.OffsetRange(ACache, AContext, mStart, mEnd),
    '')]);
end;

/// <summary>Direktiven des Methodenkopfs AHeader, klein geschrieben.</summary>
function DirectivesOf(AHeader: TSyntaxNode): TArray<string>;
var
  mInner: Integer;
begin
  Result := nil;
  for mInner := 0 to AHeader.ChildCount - 1 do
  begin
    if AHeader[mInner].Kind = TSyntaxKind.Directive then
    begin
      Result := Result + [LowerCase(AHeader[mInner].Name)];
    end;
  end;
end;

/// <summary>Methode AHeader der Klasse ATypeDecl mit Schlüsselwort und Direktiven, noch ohne Symbol.</summary>
function NewMethod(const AContext: TRuleContext; ATypeDecl, AHeader: TSyntaxNode): TMethodDecl;
var
  mToken: TPascalToken;
begin
  Result := Default(TMethodDecl);
  Result.ClassName := ATypeDecl.Name;
  Result.Header := AHeader;
  if TokenAt(AContext, AHeader.StartOffset, mToken) then
  begin
    Result.Keyword := LowerCase(mToken.Text);
  end;
  Result.Directives := DirectivesOf(AHeader);
end;

/// <summary>Symbol der Methode AHeader der Klasse ATypeName im Index der Datei; False ohne.</summary>
function MethodSymbol(AAncestry: TAncestry; const ATypeName: string; AHeader: TSyntaxNode;
  out ASymbol: TIndexSymbol): Boolean;
begin
  Result := AAncestry.LocalMethodAt(ATypeName, AHeader.StartPos, ASymbol);
end;

/// <summary>Methodendeklarationen aller Klassen der Datei.</summary>
function ClassMethods(const AContext: TRuleContext; AAncestry: TAncestry): TArray<TMethodDecl>;
const
  // Nur hier stehen Klassendeklarationen. Anweisungen und Ausdrücke bleiben außen vor: Ihre Bäume
  // können sehr tief sein (lange Verkettungen in erzeugten Units), und jede Ebene kostete Stapel.
  cContainers = [TSyntaxKind.UnitFile, TSyntaxKind.ProgramFile, TSyntaxKind.LibraryFile, TSyntaxKind.PackageFile,
    TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection, TSyntaxKind.TypeSection, TSyntaxKind.TypeDecl,
    TSyntaxKind.ClassType, TSyntaxKind.ObjectType, TSyntaxKind.RecordType, TSyntaxKind.HelperType,
    TSyntaxKind.RoutineDecl];
var
  mMethods: TList<TMethodDecl>;

  // Eigene Routine für die großen Records (TIndexSymbol, TMethodDecl, TPascalToken): Sie liegen nur
  // einmal auf dem Stapel, nicht in jeder Ebene von Visit.
  procedure AddMethods(ATypeDecl: TSyntaxNode);
  var
    mIndex: Integer;
    mBody, mHeader: TSyntaxNode;
    mMethod: TMethodDecl;
  begin
    mBody := ATypeDecl.FindChild(TSyntaxKind.ClassType);
    if mBody = nil then
    begin
      Exit;
    end;
    for mIndex := 0 to mBody.ChildCount - 1 do
    begin
      mHeader := mBody[mIndex];
      if mHeader.Kind <> TSyntaxKind.RoutineHeader then
      begin
        Continue;
      end;
      mMethod := NewMethod(AContext, ATypeDecl, mHeader);
      // class procedure/static: keine virtuellen Instanzmethoden.
      if (mMethod.Keyword <> 'class') and not mMethod.Has('static') and not mMethod.Has('message') and
        MethodSymbol(AAncestry, ATypeDecl.Name, mHeader, mMethod.Symbol) then
      begin
        mMethods.Add(mMethod);
      end;
    end;
  end;

  procedure Visit(ARoot: TSyntaxNode);
  var
    mIndex: Integer;
    mNode: TSyntaxNode;
    mPending: TStack<TSyntaxNode>;
  begin
    // Iterativ (tiefe Bäume sprengen den Stapel nicht).
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ARoot);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if mNode.Kind = TSyntaxKind.TypeDecl then
        begin
          AddMethods(mNode);
        end;
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          if mNode[mIndex].Kind in cContainers then
          begin
            mPending.Push(mNode[mIndex]);
          end;
        end;
      end;
    finally
      mPending.Free;
    end;
  end;

begin
  mMethods := TList<TMethodDecl>.Create;
  try
    Visit(AContext.Tree.Root);
    Result := mMethods.ToArray;
  finally
    mMethods.Free;
  end;
end;

function IsDestroy(const AMethod: TMethodDecl): Boolean;
begin
  Result := (AMethod.Keyword = 'destructor') and SameText(AMethod.Symbol.Name, 'Destroy') and
    (AMethod.Symbol.MaxArgs = 0);
end;

function IsComponentCreate(const AMethod: TMethodDecl): Boolean;
begin
  Result := (AMethod.Keyword = 'constructor') and SameText(AMethod.Symbol.Name, 'Create') and
    (Length(AMethod.Symbol.ParamTypes) = 1) and SameText(BareName(AMethod.Symbol.ParamTypes[0]), 'TComponent');
end;

/// <summary>Wird das Verdecken bereits bewusst angezeigt oder gelöst?</summary>
function Settled(const AMethod: TMethodDecl): Boolean;
begin
  Result := AMethod.Has('override') or AMethod.Has('reintroduce');
end;

/// <summary>Methoden der Datei ohne override/reintroduce; False ohne Syntaxbaum.
/// AAncestry gehört dem Aufrufer.</summary>
function Prepare(const AContext: TRuleContext; out AAncestry: TAncestry; out AMethods: TArray<TMethodDecl>): Boolean;
var
  mMethod: TMethodDecl;
  mCache: IRuleDerivedCache;
begin
  AAncestry := nil;
  AMethods := nil;
  if AContext.Tree = nil then
  begin
    Exit(False);
  end;
  // Den Index der Datei teilt der Lauf mit den anderen Regeln.
  mCache := TRuleDerived.Open(AContext);
  AAncestry := TAncestry.Create(AContext.Index, TRuleDerived.UnitIndex(mCache, AContext));
  for mMethod in ClassMethods(AContext, AAncestry) do
  begin
    if not Settled(mMethod) then
    begin
      AMethods := AMethods + [mMethod];
    end;
  end;
  Result := True;
end;

function TAncestry.FindMember(const ATypeName, AName: string; out AMember: TIndexSymbol;
  out AUnresolved: string): Boolean;
var
  mUnitName: string;
begin
  Result := FindMember(ATypeName, AName, AMember, AUnresolved, mUnitName);
end;

/// <summary>Index des Felds oder der Property in AMembers, das ein Nachfahre ADepth Stufen tiefer sieht:
/// private nur in derselben Unit (ALocal), strict private nur in der Klasse selbst; -1 ohne. ANamed: Indizes der
/// gleichnamigen Felder und Properties (TAncestry.FieldsNamed), aufsteigend.</summary>
function VisibleMember(const AMembers: TArray<TIndexSymbol>; const ANamed: TArray<Integer>; ADepth: Integer;
  ALocal: Boolean): Integer;
var
  mIndex: Integer;
  mMember: TIndexSymbol;
begin
  for mIndex in ANamed do
  begin
    mMember := AMembers[mIndex];
    if (ADepth = 0) or (ALocal and (mMember.Visibility <> TIndexVisibility.StrictPrivate)) or
      not (mMember.Visibility in [TIndexVisibility.Private, TIndexVisibility.StrictPrivate]) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

function TAncestry.FindMember(const ATypeName, AName: string; out AMember: TIndexSymbol; out AUnresolved,
  AUnitName: string): Boolean;
var
  mName: string;
  mLocation: TSymbolLocation;
  mMembers: TArray<TIndexSymbol>;
  mIndex, mDepth: Integer;
begin
  AMember := Default(TIndexSymbol);
  AUnresolved := '';
  AUnitName := '';
  mName := ATypeName;
  mDepth := 0;
  while (mName <> '') and (mDepth < 64) do
  begin
    if not FindType(mName, mLocation) then
    begin
      AUnresolved := mName;
      Exit(False);
    end;
    mMembers := MemberList(mLocation);
    mIndex := VisibleMember(mMembers, FieldsNamed(mLocation, AName), mDepth, mLocation.FileName = '');
    if mIndex >= 0 then
    begin
      AMember := mMembers[mIndex];
      if mLocation.FileName <> '' then
      begin
        AUnitName := mLocation.UnitName;
      end;
      Exit(True);
    end;
    if Length(mLocation.Symbol.Ancestors) = 0 then
    begin
      Break;
    end;
    mName := BareName(mLocation.Symbol.Ancestors[0]);
    Inc(mDepth);
  end;
  Result := False;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Inheritance.Ancestry', cTexts);

end.
