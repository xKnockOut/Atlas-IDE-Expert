unit BDLsp.Common.Semantics.NameResolver;

// Namensauflösung, Grundstufe: ordnet einem Bezeichner im Quelltext seine
// Deklaration zu.
//
// Reihenfolge für den ersten Namen einer Kette A.B.C:
//   1. Lokale Deklarationen der umgebenden Routinen (innen nach außen):
//      Parameter, Result, lokale var/const/type, verschachtelte Routinen,
//      Inline-Variablen vor der Position.
//   2. Bei Methoden (TFoo.Bar) Self und die Mitglieder von TFoo samt
//      Vorfahren.
//   3. Die eigene Unit (im interface-Teil nur deren interface).
//   4. Units aus uses: implementation-uses, dann interface-uses, jeweils
//      von hinten (die letzte Unit gewinnt), zuletzt System.
//   5. Unit-Namen (auch mit Punkten: System.SysUtils.Foo).
// Jeder weitere Name wird im Typ des vorigen gesucht: Mitglieder einer
// Unit, eines Typs oder des deklarierten Typs einer Variablen, eines
// Feldes, einer Property oder des Ergebnisses einer Funktion; Vorfahren
// werden durchlaufen (Klassen ohne Vorfahr erben von TObject).
//
// Ausbaustufe 2 (#263):
// - Überladungen: Auswahl nach Argumentzahl (Standardparameter zählen
//   nicht mit) und bekannten Argumenttypen; bleiben mehrere gleich gut,
//   liefert ResolveAll alle statt eines falschen.
// - Generics: Typargumente werden an die Typparameter gebunden und in
//   Typen von Mitgliedern und Vorfahren eingesetzt (TList<TKunde>.First
//   ist TKunde, class(TObjectList<TKunde>), Foo<Integer>(...)).
// - Class/Record Helper: Mitglieder des zuletzt sichtbaren Helpers für
//   einen Typ gelten für den Typ und verdecken dessen gleichnamige; auch
//   für eingebaute Typen (string, Integer).
// - with: Bezeichner werden zuerst in den with-Ausdrücken gesucht (innen
//   nach außen); ist ein Typ dort unbekannt, gibt es kein Ergebnis.
// - Inline-Variablen ohne Typ (var X := ..., for var I := ...) erhalten
//   den Typ ihres Ausdrucks.
// - Sichtbarkeit: private/strict private/protected aus anderen Units bzw.
//   Klassen werden ausgeblendet.
// - Ausdrücke als Empfänger: Foo(1).Bar, Liste[i].Bar, (X as TBar).Bar.
// Was nicht sicher auflösbar ist, liefert kein Ergebnis statt eines
// geratenen.

interface

{$SCOPEDENUMS ON}

uses
  System.SysUtils,
  System.Generics.Collections,
  BDLsp.Common.Documents.Contract,
  BDLsp.Common.Pascal.Contract,
  BDLsp.Common.Pascal.SyntaxTree,
  BDLsp.Common.Index.Contract;

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
    /// <summary>Deklarierter Typ (Variablen, Felder, Properties, Parameter, Funktionsergebnis).</summary>
    TypeName: string;
    Ancestors: TArray<string>;
    IsParameter: Boolean;
    /// <summary>Wie im Index (#263).</summary>
    TypeArgs: string;
    AncestorArgs: string;
    TypeParams: string;
    Visibility: TIndexVisibility;
    MinArgs: Integer;
    MaxArgs: Integer;
    ParamTypes: TArray<string>;
    IsDefault: Boolean;
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
  end;

  TEnsureUnitFunc = reference to function(const AUnitName: string): Boolean;

  TNameResolver = class
  private
    FIndex: ISymbolIndex;
    FEnsureUnit: TEnsureUnitFunc;
    FNamespaces: TArray<string>;
    // Pro Aufruf von Resolve
    FTree: TSyntaxTree;
    FCurrent: TUnitIndex;
    FOffset: Integer;
    FInImplementation: Boolean;
    // Mit PinTree vorab ausgewertete Unit eines Baums, für viele Aufrufe auf demselben Baum.
    FPinnedTree: TSyntaxTree;
    FPinnedFile: string;
    FPinnedUnit: TUnitIndex;
    // Je Baum: Helfer je Typname und die Klasse der umgebenden Methode.
    FHelperTree: TSyntaxTree;
    FHelpers: TDictionary<string, TResolvedSymbol>;
    FClassState: Integer;
    FClass: TResolvedSymbol;
    FInferDepth: Integer;
    function FindUnit(const AName: string; out AUnit: TUnitIndex): Boolean;
    function UnitOf(const AResolved: TResolvedSymbol; out AUnit: TUnitIndex): Boolean;
    function ScopeUnits(const AUnit: TUnitIndex; AWithImplementation: Boolean): TArray<string>;
    function FromSymbol(const AUnit: TUnitIndex; const ASymbol: TIndexSymbol): TResolvedSymbol;
    function FromNode(ANode: TSyntaxNode; const AName: string; AKind: TIndexSymbolKind;
      AIsParameter: Boolean): TResolvedSymbol;
    function LookupInUnit(const AUnit: TUnitIndex; const AName: string; AOnlyInterface, AOnlyTypes: Boolean;
      out AResult: TResolvedSymbol; AArity: Integer = -1): Boolean;
    function LookupGlobal(const AUnit: TUnitIndex; const AName: string; AWithImplementation, AOnlyTypes: Boolean;
      out AResult: TResolvedSymbol; AArity: Integer = -1): Boolean;
    function ResolveTypeName(const ATypeName: string; const AFromUnit: TUnitIndex;
      AWithImplementation: Boolean; out AResult: TResolvedSymbol; AArity: Integer = -1): Boolean;
    function ResolveTypeText(const AText: string; const AFromUnit: TUnitIndex; AWithImplementation: Boolean;
      out AResult: TResolvedSymbol): Boolean;
    function QualifyType(const AText: string; const AFromUnit: TUnitIndex; AWithImplementation: Boolean): string;
    function FindMembers(const AType: TResolvedSymbol; const AName: string): TArray<TResolvedSymbol>;
    function UnitRoutines(const ASymbol: TResolvedSymbol): TArray<TResolvedSymbol>;
    function HelperFor(const AType: TResolvedSymbol; out AHelper: TResolvedSymbol): Boolean;
    function IsVisible(const ASymbol: TIndexSymbol; const AOwnerUnit: TUnitIndex; const AOwner: TResolvedSymbol): Boolean;
    function CurrentClass(out AType: TResolvedSymbol): Boolean;
    function DescendsFrom(const AType, AAncestor: TResolvedSymbol): Boolean;
    function DefaultProperty(const AType: TResolvedSymbol; out AResult: TResolvedSymbol): Boolean;
    function ExprCandidates(ANode: TSyntaxNode): TArray<TResolvedSymbol>;
    function ExprSymbol(ANode: TSyntaxNode; out AResult: TResolvedSymbol): Boolean;
    function ArgTypes(ANode: TSyntaxNode; AFirst: Integer): TArray<string>;
    function LookupWith(const AName: string; out AResults: TArray<TResolvedSymbol>; out AStop: Boolean): Boolean;
    function FindReceiver(AEndOffset: Integer): TSyntaxNode;
    function FindCall(ACalleeEnd: Integer): TSyntaxNode;
    function IsForVar(ANode: TSyntaxNode): Boolean;
    function ResolveFirstAll(const ANames: TArray<string>; out AConsumed: Integer;
      out AResults: TArray<TResolvedSymbol>): Boolean;
    function ResolveNames(ATree: TSyntaxTree; const AFileName: string; const ANames: TArray<string>;
      AOffset: Integer; AInherited: Boolean; AReceiver, ACall: TSyntaxNode): TArray<TResolvedSymbol>;
    function ResolveAt(ATree: TSyntaxTree; const AFileName: string; const APosition: TTextPosition): TArray<TResolvedSymbol>;
    function TypeOf(const AResolved: TResolvedSymbol; out AType: TResolvedSymbol): Boolean;
    function FindMember(const AType: TResolvedSymbol; const AName: string; out AResult: TResolvedSymbol): Boolean;
    function AncestorOf(const AType: TResolvedSymbol; out AAncestor: TResolvedSymbol): Boolean;
    function EnclosingRoutines: TArray<TSyntaxNode>;
    function LookupLocal(const AName: string; out AResult: TResolvedSymbol): Boolean;
    function LookupInDeclarations(ANode: TSyntaxNode; const AName: string; out AResult: TResolvedSymbol): Boolean;
    function LookupInlineVars(ANode: TSyntaxNode; const AName: string; out AResult: TResolvedSymbol): Boolean;
    function MethodClass(out AType: TResolvedSymbol): Boolean;
    function ResolveFirst(const ANames: TArray<string>; out AConsumed: Integer; out AResult: TResolvedSymbol): Boolean;
    function TokenIndexAt(const APosition: TTextPosition): Integer;
    procedure Prepare(ATree: TSyntaxTree; const AFileName: string; AOffset: Integer);
    procedure AddCandidate(AList: TList<TResolvedSymbol>; ASeen: TDictionary<string, Boolean>;
      const ASymbol: TResolvedSymbol);
    procedure CollectMembers(const AType: TResolvedSymbol; AList: TList<TResolvedSymbol>;
      ASeen: TDictionary<string, Boolean>);
    procedure CollectUnit(const AUnit: TUnitIndex; AOnlyInterface: Boolean; AList: TList<TResolvedSymbol>;
      ASeen: TDictionary<string, Boolean>);
    procedure CollectDeclarations(ANode: TSyntaxNode; AList: TList<TResolvedSymbol>;
      ASeen: TDictionary<string, Boolean>);
    procedure CollectInlineVars(ANode: TSyntaxNode; AList: TList<TResolvedSymbol>;
      ASeen: TDictionary<string, Boolean>);
  public
    constructor Create(const AIndex: ISymbolIndex; const AEnsureUnit: TEnsureUnitFunc = nil);
    destructor Destroy; override;
    /// <summary>Löst den Bezeichner an APosition auf; bei gleich guten Überladungen die erste.</summary>
    function Resolve(ATree: TSyntaxTree; const AFileName: string; const APosition: TTextPosition): TResolvedSymbol;
    /// <summary>Wie Resolve, aber alle gleich guten Kandidaten, wenn die Überladung nicht eindeutig ist (#263).</summary>
    function ResolveAll(ATree: TSyntaxTree; const AFileName: string; const APosition: TTextPosition): TArray<TResolvedSymbol>;
    /// <summary>Löst die Kette ANames (A.B.C) so auf, wie sie an AOffset stünde.</summary>
    function ResolveChain(ATree: TSyntaxTree; const AFileName: string; const ANames: TArray<string>;
      AOffset: Integer; AInherited: Boolean = False): TResolvedSymbol;
    /// <summary>Typ des Bezeichners an APosition (Aliase verfolgt); Typen liefern sich selbst.</summary>
    function ResolveType(ATree: TSyntaxTree; const AFileName: string; const APosition: TTextPosition): TResolvedSymbol;
    /// <summary>Alle an AOffset ohne Qualifizierung sichtbaren Namen, nächster Gültigkeitsbereich zuerst:
    /// lokale Namen, Mitglieder der eigenen Klasse, eigene Unit, Units aus uses, System.</summary>
    function ScopeCandidates(ATree: TSyntaxTree; const AFileName: string; AOffset: Integer): TArray<TResolvedSymbol>;
    /// <summary>Mitglieder hinter A.B. (samt geerbter) bzw. interface-Symbole, wenn die Kette eine Unit ist.</summary>
    function MemberCandidates(ATree: TSyntaxTree; const AFileName: string; const ANames: TArray<string>;
      AOffset: Integer): TArray<TResolvedSymbol>;
    /// <summary>Kette A.B als Wert und ihr Typ (Aliase verfolgt), z. B. für Postfix-Vorlagen (#188).
    /// False, wenn die Kette nicht auflösbar ist; ATypeFound sagt, ob der Typ bekannt ist.</summary>
    function ChainType(ATree: TSyntaxTree; const AFileName: string; const ANames: TArray<string>;
      AOffset: Integer; out AOwner, AType: TResolvedSymbol; out ATypeFound: Boolean): Boolean;
    /// <summary>Wertet ATree einmal aus und nutzt das für alle folgenden Aufrufe mit demselben Baum,
    /// bis UnpinTree. Der Aufrufer gibt den Baum erst nach UnpinTree frei.</summary>
    procedure PinTree(ATree: TSyntaxTree; const AFileName: string);
    procedure UnpinTree;
    /// <summary>Löst ATypeName so auf, wie er in AFromUnit stünde (z. B. Vorfahren aus dem Index).</summary>
    function ResolveTypeFrom(const AFromUnit: TUnitIndex; const ATypeName: string; out AResult: TResolvedSymbol): Boolean;
    /// <summary>Unit-Namespaces des Projekts (DCC_Namespace) für uses ohne Präfix.</summary>
    property Namespaces: TArray<string> read FNamespaces write FNamespaces;
  end;

implementation

uses
  System.StrUtils,
  System.Math,
  BDLsp.Common.Index.Extractor;

const
  TypeKinds = [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType,
    TIndexSymbolKind.InterfaceType, TIndexSymbolKind.HelperType, TIndexSymbolKind.EnumType,
    TIndexSymbolKind.TypeAlias];
  RoutineKinds = [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_, TIndexSymbolKind.Routine];
  ExpressionKinds = [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess, TSyntaxKind.Call, TSyntaxKind.IndexAccess,
    TSyntaxKind.ParenExpr, TSyntaxKind.Dereference];
  MaxDepth = 32;
  MaxInferDepth = 8;
  // Eingebaute Typen, die nicht als Symbol im Index stehen.
  BuiltinTypes: array[0..27] of string = ('string', 'UnicodeString', 'AnsiString', 'WideString', 'ShortString',
    'Char', 'WideChar', 'AnsiChar', 'Integer', 'Cardinal', 'Int64', 'UInt64', 'NativeInt', 'NativeUInt',
    'Byte', 'Word', 'ShortInt', 'SmallInt', 'LongInt', 'LongWord', 'Boolean', 'Double', 'Single', 'Extended',
    'Currency', 'Real', 'Pointer', 'Variant');
  IntegerTypes: array[0..13] of string = ('Integer', 'Cardinal', 'Int64', 'UInt64', 'NativeInt', 'NativeUInt',
    'Byte', 'Word', 'ShortInt', 'SmallInt', 'LongInt', 'LongWord', 'Int8', 'UInt8');
  FloatTypes: array[0..4] of string = ('Double', 'Single', 'Extended', 'Currency', 'Real');
  StringTypes: array[0..4] of string = ('string', 'UnicodeString', 'AnsiString', 'WideString', 'ShortString');

function NoResult: TResolvedSymbol;
begin
  Result := Default(TResolvedSymbol);
  Result.Kind := TResolvedKind.None;
end;

function Contains(ANode: TSyntaxNode; AOffset: Integer): Boolean;
begin
  Result := (ANode.StartOffset <= AOffset) and (AOffset <= ANode.EndOffset);
end;

function ComparePositions(const A, B: TTextPosition): Integer;
begin
  if A.Line <> B.Line then
    Result := A.Line - B.Line
  else
    Result := A.Character - B.Character;
end;

/// <summary>Kommagetrennte Liste auf oberster Ebene: 'string, TList&lt;A, B&gt;' → ['string', 'TList&lt;A, B&gt;'].</summary>
function SplitArgs(const AText: string): TArray<string>;
var
  Index, Depth, Start: Integer;
begin
  Result := nil;
  if Trim(AText) = '' then
    Exit;
  Depth := 0;
  Start := 1;
  for Index := 1 to Length(AText) + 1 do
    if (Index > Length(AText)) or ((AText[Index] = ',') and (Depth = 0)) then
    begin
      Result := Result + [Trim(Copy(AText, Start, Index - Start))];
      Start := Index + 1;
    end
    else if AText[Index] = '<' then
      Inc(Depth)
    else if AText[Index] = '>' then
      Dec(Depth);
end;

/// <summary>'TList&lt;TKunde&gt;' → 'TList' und 'TKunde'.</summary>
procedure SplitGeneric(const AText: string; out ABase, AArgs: string);
var
  Open: Integer;
begin
  Open := Pos('<', AText);
  if (Open = 0) or (AText[Length(AText)] <> '>') then
  begin
    ABase := Trim(AText);
    AArgs := '';
  end
  else
  begin
    ABase := Trim(Copy(AText, 1, Open - 1));
    AArgs := Copy(AText, Open + 1, Length(AText) - Open - 1);
  end;
end;

function FullType(const ATypeName, ATypeArgs: string): string;
begin
  if ATypeArgs = '' then
    Result := ATypeName
  else
    Result := ATypeName + '<' + ATypeArgs + '>';
end;

/// <summary>Bindet Typparameter 'T,U' an Typargumente.</summary>
function Bind(const AParams: string; const AArgs: TArray<string>): TArray<string>;
var
  Params: TArray<string>;
  Index: Integer;
begin
  Result := nil;
  Params := SplitArgs(AParams);
  for Index := 0 to High(Params) do
    if Index <= High(AArgs) then
      Result := Result + [Params[Index] + '=' + AArgs[Index]];
end;

/// <summary>Setzt gebundene Typparameter in einen Typtext ein; spätere Bindungen gewinnen.</summary>
function Substitute(const AText: string; const ABindings: TArray<string>): string;
var
  Index, Start, Binding, Equal: Integer;
  Word, Replacement: string;
begin
  if Length(ABindings) = 0 then
    Exit(AText);
  Result := '';
  Index := 1;
  while Index <= Length(AText) do
  begin
    if CharInSet(AText[Index], ['A'..'Z', 'a'..'z', '_', '0'..'9', '.']) then
    begin
      Start := Index;
      while (Index <= Length(AText)) and CharInSet(AText[Index], ['A'..'Z', 'a'..'z', '_', '0'..'9', '.']) do
        Inc(Index);
      Word := Copy(AText, Start, Index - Start);
      Replacement := Word;
      for Binding := High(ABindings) downto 0 do
      begin
        Equal := Pos('=', ABindings[Binding]);
        if SameText(Copy(ABindings[Binding], 1, Equal - 1), Word) then
        begin
          Replacement := Copy(ABindings[Binding], Equal + 1, MaxInt);
          Break;
        end;
      end;
      Result := Result + Replacement;
    end
    else
    begin
      Result := Result + AText[Index];
      Inc(Index);
    end;
  end;
end;

function IsBuiltinName(const AName: string): Boolean;
begin
  Result := MatchText(AName, BuiltinTypes) or MatchText(AName, IntegerTypes);
end;

function BuiltinType(const AName: string): TResolvedSymbol;
begin
  Result := NoResult;
  Result.Kind := TResolvedKind.Symbol;
  Result.Name := AName;
  Result.UnitName := 'System';
  Result.SymbolKind := TIndexSymbolKind.RecordType;
  Result.Builtin := True;
end;

/// <summary>Gleiche Typfamilie (string/UnicodeString, Ganzzahlen ...).</summary>
function SameFamily(const A, B: string): Boolean;
begin
  Result := SameText(A, B) or
    (MatchText(A, StringTypes) and MatchText(B, StringTypes)) or
    (MatchText(A, IntegerTypes) and MatchText(B, IntegerTypes));
end;

/// <summary>Passt ein Argument vom Typ AArg zum Parameter vom Typ AParam? '' = unbekannt.</summary>
function ArgFits(const AParam, AArg: string): Boolean;
begin
  if (AParam = '') or (AArg = '') then
    Exit(True);
  if AArg = '[]' then
    Exit(StartsText('array of', AParam) or StartsText('set of', AParam) or (Pos('<', AParam) = 0));
  if StartsText('array of', AParam) then
    Exit(False);
  Result := SameFamily(AParam, AArg) or
    // Ganzzahl an Gleitkomma, Char an string.
    (MatchText(AParam, FloatTypes) and (MatchText(AArg, IntegerTypes) or MatchText(AArg, FloatTypes))) or
    (MatchText(AParam, StringTypes) and SameText(AArg, 'Char')) or
    // Klassen: ohne Vererbungsprüfung als passend werten, nur eingebaute Typen schließen aus.
    (not IsBuiltinName(AParam) and not IsBuiltinName(AArg));
end;

function SameSignature(const A, B: TResolvedSymbol): Boolean;
var
  Index: Integer;
begin
  Result := (A.SymbolKind = B.SymbolKind) and (A.MinArgs = B.MinArgs) and (A.MaxArgs = B.MaxArgs) and
    (Length(A.ParamTypes) = Length(B.ParamTypes));
  if Result then
    for Index := 0 to High(A.ParamTypes) do
      if not SameText(A.ParamTypes[Index], B.ParamTypes[Index]) then
        Exit(False);
end;

/// <summary>Deklaration und Rumpf derselben Routine nur einmal; die Deklaration zuerst.</summary>
procedure AddDistinct(var AList: TArray<TResolvedSymbol>; const ASymbol: TResolvedSymbol);
var
  Existing: TResolvedSymbol;
begin
  for Existing in AList do
    if SameSignature(Existing, ASymbol) then
      Exit;
  AList := AList + [ASymbol];
end;

/// <summary>Wählt Überladungen nach Argumentzahl und -typen; AArgCount &lt; 0 = unbekannt.</summary>
function SelectOverloads(const ACandidates: TArray<TResolvedSymbol>; AArgCount: Integer;
  const AArgTypes: TArray<string>): TArray<TResolvedSymbol>;
var
  Candidate: TResolvedSymbol;
  Fitting: TArray<TResolvedSymbol>;
  Scores: TArray<Integer>;
  Index, Arg, Score, Best: Integer;
begin
  if (AArgCount < 0) or (Length(ACandidates) <= 1) then
    Exit(ACandidates);
  Fitting := nil;
  Scores := nil;
  for Candidate in ACandidates do
  begin
    if (Candidate.SymbolKind in RoutineKinds) and
      ((AArgCount < Candidate.MinArgs) or (AArgCount > Candidate.MaxArgs)) then
      Continue;
    Score := 0;
    for Arg := 0 to Min(AArgCount, Length(Candidate.ParamTypes)) - 1 do
      if Arg <= High(AArgTypes) then
        if not ArgFits(Candidate.ParamTypes[Arg], AArgTypes[Arg]) then
        begin
          Score := -1;
          Break;
        end
        else if (AArgTypes[Arg] <> '') and SameFamily(Candidate.ParamTypes[Arg], AArgTypes[Arg]) then
          Inc(Score);
    if Score < 0 then
      Continue;
    Fitting := Fitting + [Candidate];
    Scores := Scores + [Score];
  end;
  // Passt keine, lieber alle zeigen als eine falsche.
  if Length(Fitting) = 0 then
    Exit(ACandidates);
  Best := MaxIntValue(Scores);
  Result := nil;
  for Index := 0 to High(Fitting) do
    if Scores[Index] = Best then
      Result := Result + [Fitting[Index]];
end;

{ TResolvedSymbol }

function TResolvedSymbol.Found: Boolean;
begin
  Result := Kind <> TResolvedKind.None;
end;

function TResolvedSymbol.IsType: Boolean;
begin
  Result := (Kind in [TResolvedKind.Symbol, TResolvedKind.Local]) and (SymbolKind in TypeKinds);
end;

function TResolvedSymbol.QualifiedName: string;
begin
  if Container = '' then
    Result := Name
  else
    Result := Container + '.' + Name;
end;

{ TNameResolver }

constructor TNameResolver.Create(const AIndex: ISymbolIndex; const AEnsureUnit: TEnsureUnitFunc);
begin
  inherited Create;
  FIndex := AIndex;
  FEnsureUnit := AEnsureUnit;
  FHelpers := TDictionary<string, TResolvedSymbol>.Create;
end;

destructor TNameResolver.Destroy;
begin
  FHelpers.Free;
  inherited;
end;

function TNameResolver.FindUnit(const AName: string; out AUnit: TUnitIndex): Boolean;
var
  Namespace: string;
begin
  if SameText(AName, FCurrent.UnitName) then
  begin
    AUnit := FCurrent;
    Exit(True);
  end;
  if FIndex.FindUnit(AName, AUnit) then
    Exit(True);
  if Assigned(FEnsureUnit) and FEnsureUnit(AName) and FIndex.FindUnit(AName, AUnit) then
    Exit(True);
  // uses SysUtils mit Namespace System → System.SysUtils
  for Namespace in FNamespaces do
    if FIndex.FindUnit(Namespace + '.' + AName, AUnit) or
      (Assigned(FEnsureUnit) and FEnsureUnit(Namespace + '.' + AName) and FIndex.FindUnit(Namespace + '.' + AName, AUnit)) then
      Exit(True);
  Result := False;
end;

function TNameResolver.UnitOf(const AResolved: TResolvedSymbol; out AUnit: TUnitIndex): Boolean;
begin
  if AResolved.Kind = TResolvedKind.Local then
  begin
    AUnit := FCurrent;
    Exit(True);
  end;
  if SameText(AResolved.FileName, FCurrent.FileName) then
  begin
    AUnit := FCurrent;
    Exit(True);
  end;
  Result := FIndex.FindFile(AResolved.FileName, AUnit) or FindUnit(AResolved.UnitName, AUnit);
end;

function TNameResolver.ScopeUnits(const AUnit: TUnitIndex; AWithImplementation: Boolean): TArray<string>;
var
  Names: TList<string>;
  Index: Integer;
begin
  // Höchste Priorität zuerst: letzte uses-Einträge gewinnen.
  Names := TList<string>.Create;
  try
    if AWithImplementation then
      for Index := High(AUnit.ImplementationUses) downto 0 do
        Names.Add(AUnit.ImplementationUses[Index]);
    for Index := High(AUnit.InterfaceUses) downto 0 do
      Names.Add(AUnit.InterfaceUses[Index]);
    if not SameText(AUnit.UnitName, 'System') then
      Names.Add('System');
    Result := Names.ToArray;
  finally
    Names.Free;
  end;
end;

function TNameResolver.FromSymbol(const AUnit: TUnitIndex; const ASymbol: TIndexSymbol): TResolvedSymbol;
begin
  Result := NoResult;
  Result.Kind := TResolvedKind.Symbol;
  Result.Name := ASymbol.Name;
  Result.UnitName := AUnit.UnitName;
  Result.FileName := AUnit.FileName;
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
end;

function TNameResolver.FromNode(ANode: TSyntaxNode; const AName: string; AKind: TIndexSymbolKind;
  AIsParameter: Boolean): TResolvedSymbol;
var
  Index: Integer;
  Token: TPascalToken;
begin
  Result := NoResult;
  Result.Kind := TResolvedKind.Local;
  Result.Name := AName;
  Result.UnitName := FCurrent.UnitName;
  Result.FileName := FCurrent.FileName;
  Result.Range := TTextRange.Create(ANode.StartPos, ANode.EndPos);
  Result.SelectionRange := Result.Range;
  // Auswahl auf den Namen selbst legen.
  for Index := 0 to High(FTree.Tokens) do
  begin
    Token := FTree.Tokens[Index];
    if Token.Offset >= ANode.EndOffset then
      Break;
    if (Token.Offset >= ANode.StartOffset) and (Token.Kind = TPascalTokenKind.Identifier) and
      (SameText(Token.Text, AName) or SameText(Token.Text, '&' + AName)) then
    begin
      Result.SelectionRange := TTextRange.Create(Token.StartPos, Token.EndPos);
      Break;
    end;
  end;
  Result.SymbolKind := AKind;
  Result.TypeName := TIndexExtractor.DeclaredType(ANode);
  if Result.TypeName <> '' then
    Result.TypeArgs := TIndexExtractor.GenericArgsText(TIndexExtractor.DeclaredTypeNode(ANode))
  // var X := TFoo.Create; const C = 5; for var I := 0 ...: Typ aus dem Ausdruck.
  else if (ANode.Kind in [TSyntaxKind.InlineVar, TSyntaxKind.InlineConst, TSyntaxKind.ConstDecl]) and
    (ANode.ChildCount > 0) then
    Result.Initializer := ANode[ANode.ChildCount - 1]
  else if (ANode.Kind = TSyntaxKind.ForStatement) and (ANode.ChildCount > 0) then
    Result.Initializer := ANode[0];
  Result.IsParameter := AIsParameter;
  if AKind in RoutineKinds then
    TIndexExtractor.ParamInfo(ANode, Result.MinArgs, Result.MaxArgs, Result.ParamTypes);
end;

function TNameResolver.LookupInUnit(const AUnit: TUnitIndex; const AName: string;
  AOnlyInterface, AOnlyTypes: Boolean; out AResult: TResolvedSymbol; AArity: Integer): Boolean;
var
  Symbol: TIndexSymbol;
  Pass: Integer;
begin
  // Mit Typargumenten nur generische Typen passender Stelligkeit; ohne zuerst nicht generische.
  for Pass := 0 to 1 do
  begin
    for Symbol in AUnit.Symbols do
    begin
      if not SameText(Symbol.Name, AName) then
        Continue;
      if AOnlyInterface and not Symbol.InInterface then
        Continue;
      if AOnlyTypes and not (Symbol.Kind in TypeKinds) then
        Continue;
      // Unit-Ebene; Enum-Werte sind ohne SCOPEDENUMS auch dort sichtbar.
      if (Symbol.Container <> '') and (Symbol.Kind <> TIndexSymbolKind.EnumMember) then
        Continue;
      if AOnlyTypes and (AArity > 0) and (Length(SplitArgs(Symbol.TypeParams)) <> AArity) then
        Continue;
      if AOnlyTypes and (AArity = 0) and (Pass = 0) and (Symbol.TypeParams <> '') then
        Continue;
      AResult := FromSymbol(AUnit, Symbol);
      Exit(True);
    end;
    if not (AOnlyTypes and (AArity = 0)) then
      Break;
  end;
  Result := False;
end;

function TNameResolver.LookupGlobal(const AUnit: TUnitIndex; const AName: string;
  AWithImplementation, AOnlyTypes: Boolean; out AResult: TResolvedSymbol; AArity: Integer): Boolean;
var
  UnitName: string;
  Used: TUnitIndex;
begin
  if LookupInUnit(AUnit, AName, not AWithImplementation, AOnlyTypes, AResult, AArity) then
    Exit(True);
  for UnitName in ScopeUnits(AUnit, AWithImplementation) do
    if FindUnit(UnitName, Used) and LookupInUnit(Used, AName, True, AOnlyTypes, AResult, AArity) then
      Exit(True);
  Result := False;
end;

function TNameResolver.ResolveTypeName(const ATypeName: string; const AFromUnit: TUnitIndex;
  AWithImplementation: Boolean; out AResult: TResolvedSymbol; AArity: Integer): Boolean;
var
  Dot: Integer;
  Qualifier: TUnitIndex;
begin
  Result := False;
  if ATypeName = '' then
    Exit;
  // Unit.Typ
  Dot := LastDelimiter('.', ATypeName);
  if Dot > 0 then
  begin
    if FindUnit(Copy(ATypeName, 1, Dot - 1), Qualifier) then
      Exit(LookupInUnit(Qualifier, Copy(ATypeName, Dot + 1, MaxInt), not SameText(Qualifier.FileName, FCurrent.FileName),
        True, AResult, AArity));
    Exit;
  end;
  Result := LookupGlobal(AFromUnit, ATypeName, AWithImplementation, True, AResult, AArity);
end;

function TNameResolver.ResolveTypeText(const AText: string; const AFromUnit: TUnitIndex;
  AWithImplementation: Boolean; out AResult: TResolvedSymbol): Boolean;
var
  Base, Args: string;
  ArgList: TArray<string>;
  Index: Integer;
begin
  SplitGeneric(AText, Base, Args);
  ArgList := SplitArgs(Args);
  Result := ResolveTypeName(Base, AFromUnit, AWithImplementation, AResult, Length(ArgList));
  if not Result then
  begin
    if (Args = '') and IsBuiltinName(Base) then
    begin
      AResult := BuiltinType(Base);
      Result := True;
    end;
    Exit;
  end;
  if Length(ArgList) > 0 then
  begin
    // Typargumente gelten dort, wo sie stehen: vor dem Einsetzen in fremden Units qualifizieren.
    for Index := 0 to High(ArgList) do
      ArgList[Index] := QualifyType(ArgList[Index], AFromUnit, AWithImplementation);
    AResult.Bindings := Bind(AResult.TypeParams, ArgList);
  end;
end;

function TNameResolver.QualifyType(const AText: string; const AFromUnit: TUnitIndex;
  AWithImplementation: Boolean): string;
var
  Base, Args: string;
  ArgList: TArray<string>;
  Resolved: TResolvedSymbol;
  Index: Integer;
begin
  SplitGeneric(AText, Base, Args);
  ArgList := SplitArgs(Args);
  Result := Base;
  if (Pos('.', Base) = 0) and ResolveTypeName(Base, AFromUnit, AWithImplementation, Resolved, Length(ArgList)) and
    (Resolved.Kind = TResolvedKind.Symbol) and (Resolved.Container = '') then
    Result := Resolved.UnitName + '.' + Resolved.Name;
  if Length(ArgList) > 0 then
  begin
    for Index := 0 to High(ArgList) do
      ArgList[Index] := QualifyType(ArgList[Index], AFromUnit, AWithImplementation);
    Result := Result + '<' + string.Join(',', ArgList) + '>';
  end;
end;

function TNameResolver.TypeOf(const AResolved: TResolvedSymbol; out AType: TResolvedSymbol): Boolean;
var
  Current, Next, Value: TResolvedSymbol;
  FromUnit: TUnitIndex;
  Depth: Integer;
  WithImplementation: Boolean;
  SavedOffset: Integer;
begin
  Result := False;
  // Typen sind ihr eigener Typ; Aliase werden verfolgt.
  if AResolved.IsType then
    Current := AResolved
  else if Length(AResolved.Constructed) > 0 then
    Current := AResolved.Constructed[0]
  else if (AResolved.SymbolKind = TIndexSymbolKind.Constructor_) and (AResolved.Container <> '') then
  begin
    // TFoo.Create liefert ein TFoo.
    if not UnitOf(AResolved, FromUnit) or
      not ResolveTypeName(AResolved.Container, FromUnit, SameText(FromUnit.FileName, FCurrent.FileName), Current) then
      Exit;
    Current.Bindings := AResolved.Bindings;
  end
  else if AResolved.TypeName = '' then
  begin
    // Inline-Variable ohne Typangabe: Typ des Ausdrucks.
    if (AResolved.Initializer = nil) or (FInferDepth >= MaxInferDepth) or (FTree = nil) then
      Exit;
    SavedOffset := FOffset;
    Inc(FInferDepth);
    try
      FOffset := AResolved.Initializer.StartOffset;
      if not ExprSymbol(AResolved.Initializer, Value) or not TypeOf(Value, Current) then
        Exit;
    finally
      Dec(FInferDepth);
      FOffset := SavedOffset;
    end;
  end
  else
  begin
    if not UnitOf(AResolved, FromUnit) then
      Exit;
    WithImplementation := (AResolved.Kind = TResolvedKind.Local) or
      (SameText(FromUnit.FileName, FCurrent.FileName) and FInImplementation);
    if not ResolveTypeText(Substitute(FullType(AResolved.TypeName, AResolved.TypeArgs), AResolved.Bindings),
      FromUnit, WithImplementation, Current) then
      Exit;
  end;
  Depth := 0;
  while not Current.Builtin and (Current.SymbolKind = TIndexSymbolKind.TypeAlias) and (Current.TypeName <> '') and
    (Depth < MaxDepth) do
  begin
    // Eigene Variable: der out-Parameter würde Current.TypeName vor dem Aufruf leeren.
    if not UnitOf(Current, FromUnit) or
      not ResolveTypeText(Substitute(FullType(Current.TypeName, Current.TypeArgs), Current.Bindings), FromUnit,
        SameText(FromUnit.FileName, FCurrent.FileName), Next) then
      Exit;
    Current := Next;
    Inc(Depth);
  end;
  AType := Current;
  Result := True;
end;

function TNameResolver.AncestorOf(const AType: TResolvedSymbol; out AAncestor: TResolvedSymbol): Boolean;
var
  FromUnit: TUnitIndex;
  Name: string;
begin
  Result := False;
  if AType.Builtin or not UnitOf(AType, FromUnit) then
    Exit;
  if Length(AType.Ancestors) > 0 then
    Name := Substitute(FullType(AType.Ancestors[0], AType.AncestorArgs), AType.Bindings)
  else if (AType.SymbolKind = TIndexSymbolKind.ClassType) and not SameText(AType.Name, 'TObject') then
    Name := 'TObject'
  else if (AType.SymbolKind = TIndexSymbolKind.InterfaceType) and not SameText(AType.Name, 'IInterface') then
    Name := 'IInterface'
  else
    Exit;
  // Helfer: der "Vorfahr" ist der erweiterte Typ, nicht der Elterntyp.
  if AType.SymbolKind = TIndexSymbolKind.HelperType then
    Exit;
  Result := ResolveTypeText(Name, FromUnit, SameText(FromUnit.FileName, FCurrent.FileName), AAncestor) and
    not AAncestor.Builtin and not SameText(AAncestor.QualifiedName, AType.QualifiedName);
end;

function TNameResolver.CurrentClass(out AType: TResolvedSymbol): Boolean;
begin
  // Einmal je Prepare: Klasse der umgebenden Methode.
  if FClassState = 0 then
  begin
    if (FTree <> nil) and MethodClass(FClass) then
      FClassState := 2
    else
      FClassState := 1;
  end;
  AType := FClass;
  Result := FClassState = 2;
end;

function TNameResolver.DescendsFrom(const AType, AAncestor: TResolvedSymbol): Boolean;
var
  Current, Next: TResolvedSymbol;
  Depth: Integer;
begin
  Current := AType;
  for Depth := 0 to MaxDepth do
  begin
    if SameText(Current.QualifiedName, AAncestor.QualifiedName) and SameText(Current.UnitName, AAncestor.UnitName) then
      Exit(True);
    if not AncestorOf(Current, Next) then
      Exit(False);
    Current := Next;
  end;
  Result := False;
end;

function TNameResolver.IsVisible(const ASymbol: TIndexSymbol; const AOwnerUnit: TUnitIndex;
  const AOwner: TResolvedSymbol): Boolean;
var
  SameUnit: Boolean;
  Own: TResolvedSymbol;
begin
  SameUnit := SameText(AOwnerUnit.FileName, FCurrent.FileName);
  // Aus anderen Units sind nur Deklarationen im interface sichtbar, keine Rümpfe.
  if not SameUnit and not ASymbol.InInterface then
    Exit(False);
  case ASymbol.Visibility of
    TIndexVisibility.Private:
      Result := SameUnit;
    TIndexVisibility.StrictPrivate:
      Result := SameUnit and CurrentClass(Own) and SameText(Own.QualifiedName, AOwner.QualifiedName);
    TIndexVisibility.Protected:
      Result := SameUnit or (CurrentClass(Own) and DescendsFrom(Own, AOwner));
    TIndexVisibility.StrictProtected:
      Result := CurrentClass(Own) and DescendsFrom(Own, AOwner);
  else
    Result := True;
  end;
end;

function TNameResolver.HelperFor(const AType: TResolvedSymbol; out AHelper: TResolvedSymbol): Boolean;
var
  Key, Target, UnitName: string;
  Units: TList<TUnitIndex>;
  Used: TUnitIndex;
  Symbol: TIndexSymbol;
  Found: Boolean;
  Candidate: TResolvedSymbol;

  function Matches(const AName: string): Boolean;
  var
    Dot: Integer;
  begin
    Dot := LastDelimiter('.', AName);
    Result := SameText(Copy(AName, Dot + 1, MaxInt), Target) or
      (MatchText(Target, ['string', 'UnicodeString']) and MatchText(Copy(AName, Dot + 1, MaxInt), ['string', 'UnicodeString']));
  end;

begin
  Target := AType.Name;
  Key := UpperCase(AType.UnitName + '.' + AType.QualifiedName);
  if FHelpers.TryGetValue(Key, AHelper) then
    Exit(AHelper.Found);
  AHelper := NoResult;
  // Nur der zuletzt sichtbare Helfer wirkt: eigene Unit, dann uses von hinten; in einer Unit der letzte.
  Units := TList<TUnitIndex>.Create;
  try
    Units.Add(FCurrent);
    for UnitName in ScopeUnits(FCurrent, FInImplementation) do
      if FindUnit(UnitName, Used) then
        Units.Add(Used);
    for Used in Units do
    begin
      Found := False;
      for Symbol in Used.Symbols do
        if (Symbol.Kind = TIndexSymbolKind.HelperType) and (Symbol.Container = '') and (Length(Symbol.Ancestors) > 0) and
          Matches(Symbol.Ancestors[Length(Symbol.Ancestors) - 1]) and
          (Symbol.InInterface or SameText(Used.FileName, FCurrent.FileName)) then
        begin
          Candidate := FromSymbol(Used, Symbol);
          Found := True;
        end;
      if Found then
      begin
        AHelper := Candidate;
        Break;
      end;
    end;
  finally
    Units.Free;
  end;
  FHelpers.AddOrSetValue(Key, AHelper);
  Result := AHelper.Found;
end;

function TNameResolver.FindMembers(const AType: TResolvedSymbol; const AName: string): TArray<TResolvedSymbol>;
var
  Current, Ancestor, Helper, Found: TResolvedSymbol;
  OwnerUnit, HelperUnit: TUnitIndex;
  Symbol: TIndexSymbol;
  Depth: Integer;
  TypeName: string;
  Hidden: Boolean;
begin
  Result := nil;
  Current := AType;
  for Depth := 0 to MaxDepth do
  begin
    // Helfer zuerst: ihre Mitglieder verdecken gleichnamige des Typs.
    if HelperFor(Current, Helper) and UnitOf(Helper, HelperUnit) then
    begin
      for Symbol in HelperUnit.Symbols do
        if SameText(Symbol.Container, Helper.QualifiedName) and SameText(Symbol.Name, AName) and
          IsVisible(Symbol, HelperUnit, Helper) then
        begin
          Found := FromSymbol(HelperUnit, Symbol);
          Found.Bindings := Current.Bindings;
          AddDistinct(Result, Found);
        end;
      if Result <> nil then
        Exit;
    end;
    if Current.Builtin or not UnitOf(Current, OwnerUnit) then
      Exit;
    TypeName := Current.QualifiedName;
    Hidden := False;
    // Erste Fundstelle: die Deklaration im Typ steht vor dem Rumpf in implementation.
    for Symbol in OwnerUnit.Symbols do
      if SameText(Symbol.Container, TypeName) and SameText(Symbol.Name, AName) then
      begin
        // Ist die Deklaration unsichtbar, gilt das auch für ihren Rumpf.
        if Hidden or not IsVisible(Symbol, OwnerUnit, Current) then
        begin
          Hidden := True;
          Continue;
        end;
        Found := FromSymbol(OwnerUnit, Symbol);
        Found.Bindings := Current.Bindings;
        AddDistinct(Result, Found);
      end;
    if Result <> nil then
      Exit;
    if not AncestorOf(Current, Ancestor) then
      Exit;
    Current := Ancestor;
  end;
end;

function TNameResolver.FindMember(const AType: TResolvedSymbol; const AName: string;
  out AResult: TResolvedSymbol): Boolean;
var
  Members: TArray<TResolvedSymbol>;
begin
  Members := FindMembers(AType, AName);
  Result := Length(Members) > 0;
  if Result then
    AResult := Members[0];
end;

function TNameResolver.DefaultProperty(const AType: TResolvedSymbol; out AResult: TResolvedSymbol): Boolean;
var
  Current, Ancestor: TResolvedSymbol;
  OwnerUnit: TUnitIndex;
  Symbol: TIndexSymbol;
  Depth: Integer;
begin
  Current := AType;
  for Depth := 0 to MaxDepth do
  begin
    if Current.Builtin or not UnitOf(Current, OwnerUnit) then
      Exit(False);
    for Symbol in OwnerUnit.Symbols do
      if Symbol.IsDefault and (Symbol.Kind = TIndexSymbolKind.Property_) and
        SameText(Symbol.Container, Current.QualifiedName) and IsVisible(Symbol, OwnerUnit, Current) then
      begin
        AResult := FromSymbol(OwnerUnit, Symbol);
        AResult.Bindings := Current.Bindings;
        Exit(True);
      end;
    if not AncestorOf(Current, Ancestor) then
      Exit(False);
    Current := Ancestor;
  end;
  Result := False;
end;

function TNameResolver.UnitRoutines(const ASymbol: TResolvedSymbol): TArray<TResolvedSymbol>;
var
  Owner: TUnitIndex;
  Symbol: TIndexSymbol;
  SameUnit: Boolean;
begin
  // Überladene freie Routinen derselben Unit.
  Result := [ASymbol];
  if (ASymbol.Kind <> TResolvedKind.Symbol) or (ASymbol.SymbolKind <> TIndexSymbolKind.Routine) or
    (ASymbol.Container <> '') or not UnitOf(ASymbol, Owner) then
    Exit;
  SameUnit := SameText(Owner.FileName, FCurrent.FileName);
  for Symbol in Owner.Symbols do
    if (Symbol.Kind = TIndexSymbolKind.Routine) and (Symbol.Container = '') and SameText(Symbol.Name, ASymbol.Name) and
      (SameUnit or Symbol.InInterface) then
      AddDistinct(Result, FromSymbol(Owner, Symbol));
end;

function TNameResolver.EnclosingRoutines: TArray<TSyntaxNode>;
var
  Path: TList<TSyntaxNode>;
  Node: TSyntaxNode;
  Index: Integer;
  Descended: Boolean;
begin
  // Innerste Routine zuerst.
  Path := TList<TSyntaxNode>.Create;
  try
    Node := FTree.Root;
    repeat
      Descended := False;
      for Index := 0 to Node.ChildCount - 1 do
        if Contains(Node[Index], FOffset) then
        begin
          Node := Node[Index];
          if Node.Kind = TSyntaxKind.RoutineDecl then
            Path.Insert(0, Node);
          Descended := True;
          Break;
        end;
    until not Descended;
    Result := Path.ToArray;
  finally
    Path.Free;
  end;
end;

function TNameResolver.LookupInDeclarations(ANode: TSyntaxNode; const AName: string;
  out AResult: TResolvedSymbol): Boolean;
var
  Index: Integer;
  Child: TSyntaxNode;
  Name: string;
  Kind: TIndexSymbolKind;
begin
  for Index := 0 to ANode.ChildCount - 1 do
  begin
    Child := ANode[Index];
    case Child.Kind of
      TSyntaxKind.VarSection, TSyntaxKind.ConstSection, TSyntaxKind.TypeSection:
        if LookupInDeclarations(Child, AName, AResult) then
          Exit(True);
      TSyntaxKind.VarDecl, TSyntaxKind.ConstDecl:
        for Name in Child.Name.Split([',']) do
          if SameText(Name.Trim, AName) then
          begin
            if Child.Kind = TSyntaxKind.VarDecl then
              Kind := TIndexSymbolKind.Variable
            else
              Kind := TIndexSymbolKind.Constant;
            AResult := FromNode(Child, Name.Trim, Kind, False);
            Exit(True);
          end;
      TSyntaxKind.TypeDecl:
        if SameText(Child.Name, AName) then
        begin
          AResult := FromNode(Child, Child.Name, TIndexSymbolKind.TypeAlias, False);
          Exit(True);
        end;
      TSyntaxKind.RoutineDecl:
        if SameText(Child.Name, AName) then
        begin
          AResult := FromNode(Child, Child.Name, TIndexSymbolKind.Routine, False);
          Exit(True);
        end;
    end;
  end;
  Result := False;
end;

function TNameResolver.IsForVar(ANode: TSyntaxNode): Boolean;
var
  Index: Integer;
begin
  // for var I := ...: das Wort nach "for" ist "var".
  Result := False;
  for Index := 0 to High(FTree.Tokens) - 1 do
    if FTree.Tokens[Index].Offset >= ANode.StartOffset then
    begin
      Result := FTree.Tokens[Index].IsKeyword('for') and FTree.Tokens[Index + 1].IsKeyword('var');
      Exit;
    end;
end;

function TNameResolver.LookupInlineVars(ANode: TSyntaxNode; const AName: string;
  out AResult: TResolvedSymbol): Boolean;
var
  Index: Integer;
  Child: TSyntaxNode;
  Name: string;
begin
  // Inline-Variablen gelten ab ihrer Deklaration; verschachtelte Routinen nicht durchsuchen.
  for Index := 0 to ANode.ChildCount - 1 do
  begin
    Child := ANode[Index];
    if Child.StartOffset > FOffset then
      Break;
    if Child.Kind in [TSyntaxKind.InlineVar, TSyntaxKind.InlineConst] then
    begin
      for Name in Child.Name.Split([',']) do
        if SameText(Name.Trim, AName) then
        begin
          AResult := FromNode(Child, Name.Trim, TIndexSymbolKind.Variable, False);
          Exit(True);
        end;
    end
    else if (Child.Kind <> TSyntaxKind.RoutineDecl) and Contains(Child, FOffset) then
    begin
      // for var I := ...: gilt nur in der Schleife.
      if (Child.Kind = TSyntaxKind.ForStatement) and SameText(Child.Name, AName) and IsForVar(Child) then
      begin
        AResult := FromNode(Child, Child.Name, TIndexSymbolKind.Variable, False);
        Exit(True);
      end;
      if LookupInlineVars(Child, AName, AResult) then
        Exit(True);
    end;
  end;
  Result := False;
end;

function TNameResolver.LookupLocal(const AName: string; out AResult: TResolvedSymbol): Boolean;
var
  Routine, Header, Params, Param: TSyntaxNode;
  Index: Integer;
  Name: string;
begin
  for Routine in EnclosingRoutines do
  begin
    if LookupInlineVars(Routine, AName, AResult) then
      Exit(True);
    Header := Routine.FindChild(TSyntaxKind.RoutineHeader);
    if Header <> nil then
    begin
      Params := Header.FindChild(TSyntaxKind.Parameters);
      if Params <> nil then
        for Index := 0 to Params.ChildCount - 1 do
        begin
          Param := Params[Index];
          if Param.Kind <> TSyntaxKind.Parameter then
            Continue;
          for Name in Param.Name.Split([',']) do
            if SameText(Name.Trim, AName) then
            begin
              AResult := FromNode(Param, Name.Trim, TIndexSymbolKind.Variable, True);
              Exit(True);
            end;
        end;
      if SameText(AName, 'Result') and (Header.FindChild(TSyntaxKind.TypeReference) <> nil) then
      begin
        AResult := FromNode(Header, 'Result', TIndexSymbolKind.Variable, False);
        AResult.SelectionRange := AResult.Range;
        Exit(True);
      end;
    end;
    if LookupInDeclarations(Routine, AName, AResult) then
      Exit(True);
  end;
  Result := False;
end;

function TNameResolver.MethodClass(out AType: TResolvedSymbol): Boolean;
var
  Routines: TArray<TSyntaxNode>;
  Name: string;
  Dot: Integer;
begin
  // Äußerste Routine mit Punkt im Namen: procedure TFoo.Bar
  Result := False;
  if FTree = nil then
    Exit;
  Routines := EnclosingRoutines;
  if Length(Routines) = 0 then
    Exit;
  Name := Routines[High(Routines)].Name;
  Dot := LastDelimiter('.', Name);
  if Dot = 0 then
    Exit;
  Result := ResolveTypeName(Copy(Name, 1, Dot - 1), FCurrent, True, AType);
end;

function TNameResolver.ResolveFirst(const ANames: TArray<string>; out AConsumed: Integer;
  out AResult: TResolvedSymbol): Boolean;
var
  ClassType: TResolvedSymbol;
  Count: Integer;
  UnitName: string;
  Found: TUnitIndex;
begin
  AConsumed := 1;
  if LookupLocal(ANames[0], AResult) then
    Exit(True);
  if MethodClass(ClassType) then
  begin
    if SameText(ANames[0], 'Self') then
    begin
      AResult := ClassType;
      Exit(True);
    end;
    if FindMember(ClassType, ANames[0], AResult) then
      Exit(True);
  end;
  // Unit-Namen mit Punkten: längstes Präfix zuerst (System.SysUtils.Foo).
  for Count := Length(ANames) - 1 downto 2 do
  begin
    UnitName := string.Join('.', Copy(ANames, 0, Count));
    if FindUnit(UnitName, Found) then
    begin
      AConsumed := Count;
      AResult := NoResult;
      AResult.Kind := TResolvedKind.UnitName;
      AResult.Name := Found.UnitName;
      AResult.UnitName := Found.UnitName;
      AResult.FileName := Found.FileName;
      Exit(True);
    end;
  end;
  if LookupGlobal(FCurrent, ANames[0], FInImplementation, False, AResult) then
    Exit(True);
  if FindUnit(ANames[0], Found) then
  begin
    AResult := NoResult;
    AResult.Kind := TResolvedKind.UnitName;
    AResult.Name := Found.UnitName;
    AResult.UnitName := Found.UnitName;
    AResult.FileName := Found.FileName;
    Exit(True);
  end;
  Result := False;
end;

function TNameResolver.FindReceiver(AEndOffset: Integer): TSyntaxNode;

  function Search(ANode: TSyntaxNode): TSyntaxNode;
  var
    Index: Integer;
    Child: TSyntaxNode;
  begin
    // Äußerster Ausdruck, der genau vor dem Punkt endet.
    if (ANode.Kind in ExpressionKinds) and (ANode.EndOffset = AEndOffset) then
      Exit(ANode);
    for Index := 0 to ANode.ChildCount - 1 do
    begin
      Child := ANode[Index];
      if (Child.StartOffset < AEndOffset) and (AEndOffset <= Child.EndOffset) then
      begin
        Result := Search(Child);
        if Result <> nil then
          Exit;
      end;
    end;
    Result := nil;
  end;

begin
  Result := Search(FTree.Root);
end;

function TNameResolver.FindCall(ACalleeEnd: Integer): TSyntaxNode;

  function Search(ANode: TSyntaxNode): TSyntaxNode;
  var
    Index: Integer;
    Child: TSyntaxNode;
  begin
    if (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount > 0) and (ANode[0].EndOffset = ACalleeEnd) then
      Exit(ANode);
    for Index := 0 to ANode.ChildCount - 1 do
    begin
      Child := ANode[Index];
      if (Child.StartOffset < ACalleeEnd) and (ACalleeEnd <= Child.EndOffset) then
      begin
        Result := Search(Child);
        if Result <> nil then
          Exit;
      end;
    end;
    Result := nil;
  end;

begin
  Result := Search(FTree.Root);
end;

function TNameResolver.ArgTypes(ANode: TSyntaxNode; AFirst: Integer): TArray<string>;
var
  Index: Integer;
  Arg: TSyntaxNode;
  Value, TypeInfo: TResolvedSymbol;
  Text: string;
begin
  Result := nil;
  for Index := AFirst to ANode.ChildCount - 1 do
  begin
    Arg := ANode[Index];
    if Arg.Kind = TSyntaxKind.GenericArgs then
      Continue;
    Text := '';
    if Arg.Kind = TSyntaxKind.SetConstructor then
      Text := '[]'
    else if ExprSymbol(Arg, Value) and TypeOf(Value, TypeInfo) then
      Text := TypeInfo.Name;
    Result := Result + [Text];
  end;
end;

function TNameResolver.ExprCandidates(ANode: TSyntaxNode): TArray<TResolvedSymbol>;
var
  Owner, TypeInfo, Single: TResolvedSymbol;
  OwnerUnit: TUnitIndex;
  Consumed, SavedOffset, Index: Integer;
begin
  Result := nil;
  case ANode.Kind of
    TSyntaxKind.Identifier:
      begin
        SavedOffset := FOffset;
        FOffset := ANode.StartOffset;
        try
          if not ResolveFirstAll([ANode.Name], Consumed, Result) then
            Result := nil;
        finally
          FOffset := SavedOffset;
        end;
      end;
    TSyntaxKind.MemberAccess:
      if (ANode.FindChild(TSyntaxKind.GenericArgs) = nil) and (ANode.ChildCount > 0) then
      begin
        if not ExprSymbol(ANode[0], Owner) then
          Exit;
        if Owner.Kind = TResolvedKind.UnitName then
        begin
          if FindUnit(Owner.UnitName, OwnerUnit) and
            LookupInUnit(OwnerUnit, ANode.Name, not SameText(OwnerUnit.FileName, FCurrent.FileName), False, Single) then
            Result := UnitRoutines(Single);
        end
        else if TypeOf(Owner, TypeInfo) then
        begin
          Result := FindMembers(TypeInfo, ANode.Name);
          // TKunde.Create liefert TKunde, auch wenn Create aus TObject stammt.
          if Owner.IsType then
            for Index := 0 to High(Result) do
              if Result[Index].SymbolKind = TIndexSymbolKind.Constructor_ then
                Result[Index].Constructed := [TypeInfo];
        end;
      end
      else if ExprSymbol(ANode, Single) then
        Result := [Single];
  else
    if ExprSymbol(ANode, Single) then
      Result := [Single];
  end;
end;

function TNameResolver.ExprSymbol(ANode: TSyntaxNode; out AResult: TResolvedSymbol): Boolean;
var
  Candidates: TArray<TResolvedSymbol>;
  Base, TypeInfo, Element: TResolvedSymbol;
  Args: TSyntaxNode;
  Text: string;
  Arguments: TArray<string>;
  FromUnit: TUnitIndex;
  Index: Integer;
begin
  Result := False;
  if (ANode = nil) or (FInferDepth > MaxInferDepth * 4) then
    Exit;
  Inc(FInferDepth);
  try
    case ANode.Kind of
      TSyntaxKind.Identifier:
        begin
          Candidates := ExprCandidates(ANode);
          Result := Length(Candidates) > 0;
          if Result then
            AResult := Candidates[0];
        end;
      TSyntaxKind.MemberAccess:
        begin
          Args := ANode.FindChild(TSyntaxKind.GenericArgs);
          if (Args <> nil) and (ANode.ChildCount > 0) and (ANode[0] <> Args) then
          begin
            // Foo<Integer>: Typargumente an die Typparameter der Methode binden.
            if not ExprSymbol(ANode[0], AResult) then
              Exit;
            Arguments := nil;
            for Index := 0 to Args.ChildCount - 1 do
              Arguments := Arguments + [QualifyType(TIndexExtractor.TypeText(Args[Index]), FCurrent, FInImplementation)];
            AResult.Bindings := AResult.Bindings + Bind(AResult.TypeParams, Arguments);
            Exit(True);
          end;
          Candidates := ExprCandidates(ANode);
          Result := Length(Candidates) > 0;
          if Result then
            AResult := Candidates[0];
        end;
      TSyntaxKind.Call:
        begin
          if ANode.ChildCount = 0 then
            Exit;
          Candidates := ExprCandidates(ANode[0]);
          if Length(Candidates) = 0 then
            Exit;
          // TFoo(X) ist eine Typumwandlung.
          if Candidates[0].IsType then
          begin
            AResult := Candidates[0];
            Exit(True);
          end;
          Candidates := SelectOverloads(Candidates, ANode.ChildCount - 1, ArgTypes(ANode, 1));
          AResult := Candidates[0];
          Result := True;
        end;
      TSyntaxKind.IndexAccess:
        begin
          if (ANode.ChildCount = 0) or not ExprSymbol(ANode[0], Base) then
            Exit;
          // Liste.Items[i]: die indizierte Property selbst.
          if (Base.SymbolKind = TIndexSymbolKind.Property_) and (Base.MaxArgs > 0) then
          begin
            AResult := Base;
            Exit(True);
          end;
          if not TypeOf(Base, TypeInfo) then
            Exit;
          if DefaultProperty(TypeInfo, AResult) then
            Exit(True);
          if TypeInfo.Builtin and MatchText(TypeInfo.Name, StringTypes) then
          begin
            AResult := BuiltinType('Char');
            Exit(True);
          end;
          // TArray<T>[i]: das Element.
          if SameText(TypeInfo.Name, 'TArray') and (Length(TypeInfo.Bindings) > 0) then
          begin
            Text := TypeInfo.Bindings[0];
            Text := Copy(Text, Pos('=', Text) + 1, MaxInt);
            if UnitOf(TypeInfo, FromUnit) and ResolveTypeText(Text, FromUnit, True, Element) then
            begin
              AResult := Element;
              Exit(True);
            end;
          end;
        end;
      TSyntaxKind.ParenExpr:
        Result := (ANode.ChildCount > 0) and ExprSymbol(ANode[0], AResult);
      TSyntaxKind.BinaryExpr:
        // (X as TBar): der Zieltyp.
        if SameText(ANode.Name, 'as') and (ANode.ChildCount = 2) then
          Result := ExprSymbol(ANode[1], AResult) and AResult.IsType;
      TSyntaxKind.IfExpr:
        Result := (ANode.ChildCount >= 2) and ExprSymbol(ANode[1], AResult);
      TSyntaxKind.Literal:
        begin
          Text := ANode.Name;
          if Text = '' then
            Exit;
          if CharInSet(Text[1], ['''', '#']) then
            AResult := BuiltinType('string')
          else if CharInSet(Text[1], ['0'..'9', '$', '%']) then
          begin
            if (Text[1] <> '$') and ((Pos('.', Text) > 0) or (Pos('E', UpperCase(Text)) > 0)) then
              AResult := BuiltinType('Double')
            else
              AResult := BuiltinType('Integer');
          end
          else
            Exit;
          Result := True;
        end;
    end;
  finally
    Dec(FInferDepth);
  end;
end;

function TNameResolver.LookupWith(const AName: string; out AResults: TArray<TResolvedSymbol>;
  out AStop: Boolean): Boolean;
var
  Withs: TList<TSyntaxNode>;
  Node, WithNode: TSyntaxNode;
  Index: Integer;
  Descended: Boolean;
  Value, TypeInfo: TResolvedSymbol;
  SavedOffset: Integer;
  Known: Boolean;
begin
  Result := False;
  AStop := False;
  AResults := nil;
  if FTree = nil then
    Exit;
  // with-Anweisungen, in deren Rumpf FOffset liegt, innerste zuerst.
  Withs := TList<TSyntaxNode>.Create;
  try
    Node := FTree.Root;
    repeat
      Descended := False;
      for Index := 0 to Node.ChildCount - 1 do
        if Contains(Node[Index], FOffset) then
        begin
          Node := Node[Index];
          if (Node.Kind = TSyntaxKind.WithStatement) and (Node.ChildCount >= 2) and
            Contains(Node[Node.ChildCount - 1], FOffset) then
            Withs.Insert(0, Node);
          Descended := True;
          Break;
        end;
    until not Descended;
    for WithNode in Withs do
      for Index := WithNode.ChildCount - 2 downto 0 do
      begin
        // Den Ausdruck an seiner eigenen Stelle auflösen, außerhalb des with-Rumpfs.
        SavedOffset := FOffset;
        FOffset := WithNode[Index].StartOffset;
        try
          Known := ExprSymbol(WithNode[Index], Value) and TypeOf(Value, TypeInfo);
        finally
          FOffset := SavedOffset;
        end;
        if not Known then
        begin
          // Unbekannter Typ: der Name könnte ein Mitglied sein, also lieber nichts liefern.
          AStop := True;
          Exit;
        end;
        AResults := FindMembers(TypeInfo, AName);
        if Length(AResults) > 0 then
          Exit(True);
      end;
  finally
    Withs.Free;
  end;
end;

function TNameResolver.ResolveFirstAll(const ANames: TArray<string>; out AConsumed: Integer;
  out AResults: TArray<TResolvedSymbol>): Boolean;
var
  First, ClassType: TResolvedSymbol;
  Stop: Boolean;
begin
  AConsumed := 1;
  AResults := nil;
  if LookupWith(ANames[0], AResults, Stop) then
    Exit(True);
  if Stop then
    Exit(False);
  if not ResolveFirst(ANames, AConsumed, First) then
    Exit(False);
  Result := True;
  // Überladungen: Mitglieder der eigenen Klasse oder freie Routinen derselben Unit.
  if (AConsumed = 1) and (First.Kind = TResolvedKind.Symbol) and (First.SymbolKind in RoutineKinds) then
  begin
    if (First.Container <> '') and CurrentClass(ClassType) then
      AResults := FindMembers(ClassType, ANames[0]);
    if Length(AResults) = 0 then
      AResults := UnitRoutines(First);
  end
  else
    AResults := [First];
end;

function TNameResolver.ResolveNames(ATree: TSyntaxTree; const AFileName: string; const ANames: TArray<string>;
  AOffset: Integer; AInherited: Boolean; AReceiver, ACall: TSyntaxNode): TArray<TResolvedSymbol>;
var
  Consumed, Index: Integer;
  Current, TypeInfo, Ancestor, Single: TResolvedSymbol;
  Candidates: TArray<TResolvedSymbol>;
  Owner: TUnitIndex;
begin
  Result := nil;
  if (ATree = nil) or (Length(ANames) = 0) then
    Exit;
  Prepare(ATree, AFileName, AOffset);

  if AReceiver <> nil then
  begin
    // Foo(1).Bar, Liste[i].Bar, (X as TBar).Bar: alle Namen sind Mitglieder.
    if not ExprSymbol(AReceiver, Current) then
      Exit;
    Consumed := 0;
    Candidates := [Current];
  end
  else if AInherited then
  begin
    // inherited Create: im Vorfahren der Klasse der umgebenden Methode suchen.
    if not MethodClass(Current) or not AncestorOf(Current, Ancestor) then
      Exit;
    Candidates := FindMembers(Ancestor, ANames[0]);
    if Length(Candidates) = 0 then
      Exit;
    Current := Candidates[0];
    Consumed := 1;
  end
  else
  begin
    if not ResolveFirstAll(ANames, Consumed, Candidates) or (Length(Candidates) = 0) then
      Exit;
    Current := Candidates[0];
  end;

  for Index := Consumed to High(ANames) do
  begin
    if Current.Kind = TResolvedKind.UnitName then
    begin
      if not FindUnit(Current.UnitName, Owner) or
        not LookupInUnit(Owner, ANames[Index], not SameText(Owner.FileName, FCurrent.FileName), False, Single) then
        Exit;
      Candidates := UnitRoutines(Single);
    end
    else
    begin
      if not TypeOf(Current, TypeInfo) then
        Exit;
      Candidates := FindMembers(TypeInfo, ANames[Index]);
      if Length(Candidates) = 0 then
        Exit;
    end;
    Current := Candidates[0];
  end;
  if ACall <> nil then
    Candidates := SelectOverloads(Candidates, ACall.ChildCount - 1, ArgTypes(ACall, 1));
  // Eingebaute Typen haben keine Deklaration, zu der man springen könnte.
  for Current in Candidates do
    if not Current.Builtin then
      Result := Result + [Current];
end;

function TNameResolver.ResolveChain(ATree: TSyntaxTree; const AFileName: string; const ANames: TArray<string>;
  AOffset: Integer; AInherited: Boolean): TResolvedSymbol;
var
  Results: TArray<TResolvedSymbol>;
begin
  Results := ResolveNames(ATree, AFileName, ANames, AOffset, AInherited, nil, nil);
  if Length(Results) > 0 then
    Result := Results[0]
  else
    Result := NoResult;
end;

procedure TNameResolver.Prepare(ATree: TSyntaxTree; const AFileName: string; AOffset: Integer);
var
  Section: TSyntaxNode;
begin
  FTree := ATree;
  FOffset := AOffset;
  FClassState := 0;
  FInferDepth := 0;
  if (ATree = FPinnedTree) and SameText(AFileName, FPinnedFile) then
    FCurrent := FPinnedUnit
  else
    FCurrent := TIndexExtractor.Extract(ATree, AFileName);
  // Helfer hängen an der Unit und ihren uses; je Baum neu bestimmen.
  if ATree <> FHelperTree then
  begin
    FHelpers.Clear;
    FHelperTree := ATree;
  end;
  Section := ATree.Root.FindChild(TSyntaxKind.InterfaceSection);
  // Programme haben keinen interface-Teil: alles ist "implementation".
  FInImplementation := (Section = nil) or not Contains(Section, AOffset);
end;

procedure TNameResolver.AddCandidate(AList: TList<TResolvedSymbol>; ASeen: TDictionary<string, Boolean>;
  const ASymbol: TResolvedSymbol);
var
  Key: string;
begin
  // Der nächste Gültigkeitsbereich verdeckt gleichnamige weiter außen; Überladungen erscheinen einmal.
  Key := UpperCase(ASymbol.Name);
  if (Key = '') or ASeen.ContainsKey(Key) then
    Exit;
  ASeen.Add(Key, True);
  AList.Add(ASymbol);
end;

procedure TNameResolver.CollectMembers(const AType: TResolvedSymbol; AList: TList<TResolvedSymbol>;
  ASeen: TDictionary<string, Boolean>);
var
  Current, Ancestor, Helper: TResolvedSymbol;
  OwnerUnit, HelperUnit: TUnitIndex;
  Symbol: TIndexSymbol;
  Depth: Integer;
  TypeName: string;
begin
  Current := AType;
  for Depth := 0 to MaxDepth do
  begin
    // Mitglieder des Helfers zuerst (#263), auch für eingebaute Typen.
    if HelperFor(Current, Helper) and UnitOf(Helper, HelperUnit) then
      for Symbol in HelperUnit.Symbols do
        if SameText(Symbol.Container, Helper.QualifiedName) and IsVisible(Symbol, HelperUnit, Helper) then
          AddCandidate(AList, ASeen, FromSymbol(HelperUnit, Symbol));
    if Current.Builtin or not UnitOf(Current, OwnerUnit) then
      Exit;
    TypeName := Current.QualifiedName;
    for Symbol in OwnerUnit.Symbols do
      if SameText(Symbol.Container, TypeName) then
        if IsVisible(Symbol, OwnerUnit, Current) then
          AddCandidate(AList, ASeen, FromSymbol(OwnerUnit, Symbol))
        else
          // Unsichtbare Deklaration: auch ihren Rumpf aus implementation nicht anbieten.
          ASeen.AddOrSetValue(UpperCase(Symbol.Name), True);
    if not AncestorOf(Current, Ancestor) then
      Exit;
    Current := Ancestor;
  end;
end;

procedure TNameResolver.CollectUnit(const AUnit: TUnitIndex; AOnlyInterface: Boolean;
  AList: TList<TResolvedSymbol>; ASeen: TDictionary<string, Boolean>);
var
  Symbol: TIndexSymbol;
begin
  for Symbol in AUnit.Symbols do
  begin
    if AOnlyInterface and not Symbol.InInterface then
      Continue;
    if (Symbol.Container <> '') and (Symbol.Kind <> TIndexSymbolKind.EnumMember) then
      Continue;
    AddCandidate(AList, ASeen, FromSymbol(AUnit, Symbol));
  end;
end;

procedure TNameResolver.CollectDeclarations(ANode: TSyntaxNode; AList: TList<TResolvedSymbol>;
  ASeen: TDictionary<string, Boolean>);
var
  Index: Integer;
  Child: TSyntaxNode;
  Name: string;
  Kind: TIndexSymbolKind;
begin
  for Index := 0 to ANode.ChildCount - 1 do
  begin
    Child := ANode[Index];
    case Child.Kind of
      TSyntaxKind.VarSection, TSyntaxKind.ConstSection, TSyntaxKind.TypeSection:
        CollectDeclarations(Child, AList, ASeen);
      TSyntaxKind.VarDecl, TSyntaxKind.ConstDecl:
        begin
          if Child.Kind = TSyntaxKind.VarDecl then
            Kind := TIndexSymbolKind.Variable
          else
            Kind := TIndexSymbolKind.Constant;
          for Name in Child.Name.Split([',']) do
            AddCandidate(AList, ASeen, FromNode(Child, Name.Trim, Kind, False));
        end;
      TSyntaxKind.TypeDecl:
        AddCandidate(AList, ASeen, FromNode(Child, Child.Name, TIndexSymbolKind.TypeAlias, False));
      TSyntaxKind.RoutineDecl:
        AddCandidate(AList, ASeen, FromNode(Child, Child.Name, TIndexSymbolKind.Routine, False));
    end;
  end;
end;

procedure TNameResolver.CollectInlineVars(ANode: TSyntaxNode; AList: TList<TResolvedSymbol>;
  ASeen: TDictionary<string, Boolean>);
var
  Index: Integer;
  Child: TSyntaxNode;
  Name: string;
begin
  // Wie LookupInlineVars: nur bis zum Cursor, nicht in verschachtelte Routinen.
  for Index := 0 to ANode.ChildCount - 1 do
  begin
    Child := ANode[Index];
    if Child.StartOffset > FOffset then
      Break;
    if Child.Kind in [TSyntaxKind.InlineVar, TSyntaxKind.InlineConst] then
    begin
      if Child.EndOffset <= FOffset then
        for Name in Child.Name.Split([',']) do
          AddCandidate(AList, ASeen, FromNode(Child, Name.Trim, TIndexSymbolKind.Variable, False));
    end
    else if (Child.Kind <> TSyntaxKind.RoutineDecl) and Contains(Child, FOffset) then
      CollectInlineVars(Child, AList, ASeen);
  end;
end;

function TNameResolver.ScopeCandidates(ATree: TSyntaxTree; const AFileName: string;
  AOffset: Integer): TArray<TResolvedSymbol>;
var
  List: TList<TResolvedSymbol>;
  Seen: TDictionary<string, Boolean>;
  Routine, Header, Params, Param: TSyntaxNode;
  Index: Integer;
  Name, UnitName: string;
  ClassType, ResultSymbol: TResolvedSymbol;
  Used: TUnitIndex;
begin
  Result := nil;
  if ATree = nil then
    Exit;
  Prepare(ATree, AFileName, AOffset);
  List := TList<TResolvedSymbol>.Create;
  Seen := TDictionary<string, Boolean>.Create;
  try
    for Routine in EnclosingRoutines do
    begin
      CollectInlineVars(Routine, List, Seen);
      Header := Routine.FindChild(TSyntaxKind.RoutineHeader);
      if Header <> nil then
      begin
        Params := Header.FindChild(TSyntaxKind.Parameters);
        if Params <> nil then
          for Index := 0 to Params.ChildCount - 1 do
          begin
            Param := Params[Index];
            if Param.Kind = TSyntaxKind.Parameter then
              for Name in Param.Name.Split([',']) do
                AddCandidate(List, Seen, FromNode(Param, Name.Trim, TIndexSymbolKind.Variable, True));
          end;
        if Header.FindChild(TSyntaxKind.TypeReference) <> nil then
        begin
          ResultSymbol := FromNode(Header, 'Result', TIndexSymbolKind.Variable, False);
          AddCandidate(List, Seen, ResultSymbol);
        end;
      end;
      CollectDeclarations(Routine, List, Seen);
    end;
    if MethodClass(ClassType) then
    begin
      ResultSymbol := ClassType;
      ResultSymbol.Name := 'Self';
      ResultSymbol.Kind := TResolvedKind.Local;
      ResultSymbol.SymbolKind := TIndexSymbolKind.Variable;
      ResultSymbol.TypeName := ClassType.QualifiedName;
      AddCandidate(List, Seen, ResultSymbol);
      CollectMembers(ClassType, List, Seen);
    end;
    CollectUnit(FCurrent, not FInImplementation, List, Seen);
    for UnitName in ScopeUnits(FCurrent, FInImplementation) do
      if FindUnit(UnitName, Used) then
        CollectUnit(Used, True, List, Seen);
    Result := List.ToArray;
  finally
    Seen.Free;
    List.Free;
  end;
end;

function TNameResolver.MemberCandidates(ATree: TSyntaxTree; const AFileName: string;
  const ANames: TArray<string>; AOffset: Integer): TArray<TResolvedSymbol>;
var
  Owner, TypeInfo: TResolvedSymbol;
  OwnerUnit: TUnitIndex;
  List: TList<TResolvedSymbol>;
  Seen: TDictionary<string, Boolean>;
begin
  Result := nil;
  // ResolveChain bereitet den Zustand (aktuelle Unit, Abschnitt) vor.
  Owner := ResolveChain(ATree, AFileName, ANames, AOffset);
  if not Owner.Found then
    Exit;
  List := TList<TResolvedSymbol>.Create;
  Seen := TDictionary<string, Boolean>.Create;
  try
    if Owner.Kind = TResolvedKind.UnitName then
    begin
      if FindUnit(Owner.UnitName, OwnerUnit) then
        CollectUnit(OwnerUnit, not SameText(OwnerUnit.FileName, FCurrent.FileName), List, Seen);
    end
    else if TypeOf(Owner, TypeInfo) then
      CollectMembers(TypeInfo, List, Seen);
    Result := List.ToArray;
  finally
    Seen.Free;
    List.Free;
  end;
end;

function TNameResolver.ChainType(ATree: TSyntaxTree; const AFileName: string; const ANames: TArray<string>;
  AOffset: Integer; out AOwner, AType: TResolvedSymbol; out ATypeFound: Boolean): Boolean;
begin
  AType := Default(TResolvedSymbol);
  ATypeFound := False;
  AOwner := ResolveChain(ATree, AFileName, ANames, AOffset);
  Result := AOwner.Found;
  if Result and (AOwner.Kind <> TResolvedKind.UnitName) then
    ATypeFound := TypeOf(AOwner, AType);
end;

procedure TNameResolver.PinTree(ATree: TSyntaxTree; const AFileName: string);
begin
  FPinnedTree := ATree;
  FPinnedFile := AFileName;
  FPinnedUnit := TIndexExtractor.Extract(ATree, AFileName);
end;

procedure TNameResolver.UnpinTree;
begin
  FPinnedTree := nil;
  FPinnedFile := '';
  FPinnedUnit := Default(TUnitIndex);
end;

function TNameResolver.ResolveTypeFrom(const AFromUnit: TUnitIndex; const ATypeName: string;
  out AResult: TResolvedSymbol): Boolean;
begin
  FTree := nil;
  FOffset := 0;
  FCurrent := AFromUnit;
  FInImplementation := True;
  FClassState := 0;
  FHelperTree := nil;
  FHelpers.Clear;
  Result := ResolveTypeName(ATypeName, AFromUnit, True, AResult);
end;

function TNameResolver.ResolveType(ATree: TSyntaxTree; const AFileName: string;
  const APosition: TTextPosition): TResolvedSymbol;
var
  Symbol, TypeInfo: TResolvedSymbol;
begin
  // Resolve setzt den Zustand (aktuelle Unit, Abschnitt), den TypeOf braucht.
  Symbol := Resolve(ATree, AFileName, APosition);
  if (Symbol.Kind in [TResolvedKind.Symbol, TResolvedKind.Local]) and TypeOf(Symbol, TypeInfo) and
    not TypeInfo.Builtin then
    Result := TypeInfo
  else
    Result := NoResult;
end;

function TNameResolver.TokenIndexAt(const APosition: TTextPosition): Integer;
var
  Index: Integer;
  Token: TPascalToken;
begin
  for Index := 0 to High(FTree.Tokens) do
  begin
    Token := FTree.Tokens[Index];
    if ComparePositions(Token.StartPos, APosition) > 0 then
      Break;
    // Cursor auf oder direkt hinter dem Bezeichner.
    if (Token.Kind = TPascalTokenKind.Identifier) and (ComparePositions(APosition, Token.EndPos) <= 0) then
      Exit(Index);
  end;
  Result := -1;
end;

function TNameResolver.ResolveAt(ATree: TSyntaxTree; const AFileName: string;
  const APosition: TTextPosition): TArray<TResolvedSymbol>;
var
  Tokens: TArray<TPascalToken>;
  Index, First: Integer;
  Names: TList<string>;
  IsInherited: Boolean;
  Receiver, Call: TSyntaxNode;
  Before: TPascalToken;

  function Clean(const AText: string): string;
  begin
    // &Begin → Begin
    if (AText <> '') and (AText[1] = '&') then
      Result := Copy(AText, 2, MaxInt)
    else
      Result := AText;
  end;

begin
  Result := nil;
  if ATree = nil then
    Exit;
  FTree := ATree;
  Tokens := ATree.Tokens;
  Index := TokenIndexAt(APosition);
  if Index < 0 then
    Exit;
  Names := TList<string>.Create;
  try
    Names.Add(Clean(Tokens[Index].Text));
    First := Index;
    while (First >= 2) and Tokens[First - 1].IsSymbol('.') and
      (Tokens[First - 2].Kind = TPascalTokenKind.Identifier) do
    begin
      Dec(First, 2);
      Names.Insert(0, Clean(Tokens[First].Text));
    end;
    // Foo(1).Bar, A[0].B, (X as TBar).C: Empfänger ist ein Ausdruck (#263).
    Receiver := nil;
    if (First >= 2) and Tokens[First - 1].IsSymbol('.') then
    begin
      Before := Tokens[First - 2];
      Receiver := FindReceiver(Before.Offset + Length(Before.Text));
      if Receiver = nil then
        Exit;
    end;
    // Aufruf mit Klammern: Argumente bestimmen die Überladung.
    Call := nil;
    if (Index < High(Tokens)) and Tokens[Index + 1].IsSymbol('(') then
      Call := FindCall(Tokens[Index].Offset + Length(Tokens[Index].Text));
    IsInherited := (Receiver = nil) and (First >= 1) and Tokens[First - 1].IsKeyword('inherited');
    Result := ResolveNames(ATree, AFileName, Names.ToArray, Tokens[Index].Offset, IsInherited, Receiver, Call);
  finally
    Names.Free;
  end;
end;

function TNameResolver.ResolveAll(ATree: TSyntaxTree; const AFileName: string;
  const APosition: TTextPosition): TArray<TResolvedSymbol>;
begin
  Result := ResolveAt(ATree, AFileName, APosition);
end;

function TNameResolver.Resolve(ATree: TSyntaxTree; const AFileName: string;
  const APosition: TTextPosition): TResolvedSymbol;
var
  Results: TArray<TResolvedSymbol>;
begin
  Results := ResolveAt(ATree, AFileName, APosition);
  if Length(Results) > 0 then
    Result := Results[0]
  else
    Result := NoResult;
end;

end.
