unit Atlas.Common.Rules.Builtin.Inheritance;

// Klassische Deklarationsfehler bei der Vererbung (#125), alles Varianten von
// W1010, aber schon beim Tippen und mit Korrektur:
//   destroy-without-override            destructor Destroy ohne override
//   component-create-without-override   constructor Create(AOwner: TComponent)
//                                       ohne override in TComponent-Nachfahren
//   hides-virtual                       Methode verdeckt eine virtuelle des Vorfahren
//   virtual-instead-of-override         virtual statt override bei gleicher Signatur
//   shadowed-name                       Parameter oder lokale Variable heißt wie ein Feld, eine
//                                       Property (auch geerbt) oder eine globale Variable der Unit (#934)
//   override-target-missing             override ohne passende virtuelle Methode im Vorfahren (E2137),
//                                       auf eine statische (E2170) oder finale (E2352), Ableiten von
//                                       einer sealed-Klasse (E2353) (#997)
//   abstract-class-instantiated         Create auf einer Klasse mit offenen abstrakten Methoden (W1020)
//                                       oder einer abstract-Klasse (E2402) (#999)
//   inherited-abstract-call             inherited Name(…) auf eine im Vorfahren abstrakte Methode (E2373,
//                                       #1026); die Methode löst TNameResolver samt Überladungen auf
//
// Vorfahren werden zuerst in der Datei, dann im Symbolindex gesucht (auch RTL
// und VCL, soweit eingelesen). Ist ein Vorfahr nicht auflösbar oder mehrdeutig,
// endet die Suche ohne Treffer. Mit reintroduce oder override schweigen alle
// Regeln; eine Überladung (overload) mit anderer Signatur ebenso.

interface

uses
  System.SysUtils,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

type
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
    function FindType(const AName: string; out AType: TSymbolLocation): Boolean;
    function MethodsOf(const AType: TSymbolLocation; const AName: string): TArray<TIndexSymbol>;
  public
    /// <summary>ALocal ist der Index der geprüften Datei (TRuleDerived.UnitIndex, Review P-03).</summary>
    constructor Create(const AIndex: ISymbolIndex; const ALocal: TUnitIndex);
    /// <summary>Name des direkten Vorfahren; TObject ohne Angabe; '' wenn der Typ unbekannt ist.</summary>
    function ParentOf(const ATypeName: string): string;
    /// <summary>Erbt ATypeName (auch über mehrere Stufen) von AAncestor? False, wenn die Kette abbricht.</summary>
    function DescendsFrom(const ATypeName, AAncestor: string): Boolean;
    /// <summary>Deklariert die Klasse ATypeName selbst einen Konstruktor (Datei oder Index, #919)?</summary>
    function HasConstructor(const ATypeName: string): Boolean;
    /// <summary>Nächste gleichnamige Methode in den Vorfahren, falls sie virtuell ist.</summary>
    function InheritedVirtual(const AMethod: TMethodDecl): TInherited;
    /// <summary>Feld oder Property AName in ATypeName oder einem Vorfahren, das dort sichtbar ist (#934).
    /// Bricht die Kette ab, steht in AUnresolved der Vorfahr, der weder in der Datei noch im Index steht.</summary>
    function FindMember(const ATypeName, AName: string; out AMember: TIndexSymbol; out AUnresolved: string): Boolean;
    /// <summary>Vorfahren von ATypeName vom direkten an aufwärts (#997). AComplete: die Kette reicht bis TObject;
    /// AObjectMissing: TObject selbst steht weder in der Datei noch im Index.</summary>
    function Ancestors(const ATypeName: string; out AComplete, AObjectMissing: Boolean): TArray<TSymbolLocation>;
    /// <summary>Klasse AName aus der Datei oder eindeutig aus dem Index (#999).</summary>
    function FindClass(const AName: string; out AType: TSymbolLocation): Boolean;
    /// <summary>Methoden, Konstruktoren und Destruktoren der Klasse AType (#997).</summary>
    function Methods(const AType: TSymbolLocation): TArray<TIndexSymbol>;
    /// <summary>Ist AName in der Datei oder im Index als Typalias deklariert (type TModus = Integer)?</summary>
    function IsTypeAlias(const AName: string): Boolean;
    /// <summary>Ist AName in der Datei oder im Index als eigener Typ deklariert (Klasse, Record, Aufzählung,
    /// Interface), also kein Alias?</summary>
    function IsDeclaredType(const AName: string): Boolean;
    /// <summary>Typ AName jeder Art (Klasse, Record, Interface, Aufzählung, Alias) aus der Datei oder dem Index
    /// (#1001); bei mehreren gleichnamigen der erste.</summary>
    function FindAnyType(const AName: string; out AType: TSymbolLocation): Boolean;
    /// <summary>Felder, Properties, Methoden und Konstruktoren des Typs AType (#1001).</summary>
    function Members(const AType: TSymbolLocation): TArray<TIndexSymbol>;
    /// <summary>Bezeichnen A und B denselben Typ? Synonyme (Longint, Integer) gleich; Typparameter aus
    /// AWildcards und Aliase der Datei oder des Index passen zu allem (#997, #1001).</summary>
    function SameType(const A, B: string; const AWildcards: TArray<string>): Boolean;
    /// <summary>Steht der Typ sicher für sich (eingebaut oder als Klasse, Record, Aufzählung deklariert)?</summary>
    function KnownType(const AName: string): Boolean;
    property Local: TUnitIndex read FLocal;
  end;

  TDestroyWithoutOverrideRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TComponentCreateWithoutOverrideRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  THidesVirtualRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TVirtualInsteadOfOverrideRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TShadowedNameRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TOverrideTargetMissingRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TAbstractClassInstantiatedRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TInheritedAbstractCallRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Trägt der Methodenkopf ASignature die Direktive abstract ("procedure A; virtual; abstract;")?
    /// </summary>
    class function IsAbstractSignature(const ASignature: string): Boolean; static;
  end;

procedure RegisterInheritanceRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.Options,
  Atlas.Common.Rules.Builtin.Unused,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.ClassActions,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Text.Fuzzy;

function TMethodDecl.Has(const ADirective: string): Boolean;
begin
  Result := MatchText(ADirective, Directives);
end;

/// <summary>Typname ohne Unit-Präfix und Typargumente.</summary>
function BareName(const AName: string): string;
begin
  Result := AName;
  if Pos('<', Result) > 0 then
    Result := Copy(Result, 1, Pos('<', Result) - 1);
  Result := Copy(Result, LastDelimiter('.', Result) + 1, MaxInt);
end;

function ContainsLine(const ARange: TTextRange; ALine: Integer): Boolean;
begin
  Result := (ALine >= ARange.StartPos.Line) and (ALine <= ARange.EndPos.Line);
end;

function SameSignature(const A, B: TIndexSymbol): Boolean;
var
  Index: Integer;
begin
  Result := (A.MaxArgs = B.MaxArgs) and (Length(A.ParamTypes) = Length(B.ParamTypes)) and
    SameText(A.TypeName, B.TypeName);
  if Result then
    for Index := 0 to High(A.ParamTypes) do
      if not SameText(BareName(A.ParamTypes[Index]), BareName(B.ParamTypes[Index])) then
        Exit(False);
end;

const
  // Virtuelle Instanzmethoden von TObject, falls System nicht im Index steht.
  ObjectVirtualNames: array[0..9] of string = ('AfterConstruction', 'BeforeDestruction', 'Dispatch',
    'DefaultHandler', 'FreeInstance', 'Destroy', 'SafeCallException', 'ToString', 'Equals', 'GetHashCode');
  // Gleiche Typen unter anderem Namen: Name=Grundname.
  TypeSynonyms: array[0..17] of string = ('longint=integer', 'int32=integer', 'longword=cardinal',
    'uint32=cardinal', 'dword=cardinal', 'unicodestring=string', 'widechar=char', 'pwidechar=pchar',
    'intptr=nativeint', 'uintptr=nativeuint', 'int16=smallint', 'int8=shortint', 'uint8=byte', 'uint16=word',
    'real=double', 'tobject=tobject', 'system.tobject=tobject', 'hresult=hresult');
  // Eingebaute Typen, die sicher kein Alias eines anderen sind.
  BuiltinTypes: array[0..25] of string = ('integer', 'cardinal', 'int64', 'uint64', 'string', 'ansistring',
    'shortstring', 'widestring', 'char', 'ansichar', 'boolean', 'double', 'single', 'extended', 'currency', 'byte',
    'word', 'smallint', 'shortint', 'pointer', 'variant', 'tobject', 'nativeint', 'nativeuint', 'pchar',
    'tdatetime');

function CanonicalType(const AName: string): string;
var
  Pair: string;
begin
  Result := LowerCase(BareName(AName));
  for Pair in TypeSynonyms do
    if StartsStr(Result + '=', Pair) then
      Exit(Copy(Pair, Length(Result) + 2, MaxInt));
end;

{ TAncestry }

constructor TAncestry.Create(const AIndex: ISymbolIndex; const ALocal: TUnitIndex);
begin
  inherited Create;
  FIndex := AIndex;
  FLocal := ALocal;
end;

function TAncestry.FindType(const AName: string; out AType: TSymbolLocation): Boolean;
var
  Symbol: TIndexSymbol;
  Location: TSymbolLocation;
  Found: Boolean;
begin
  for Symbol in FLocal.Symbols do
    if (Symbol.Kind = TIndexSymbolKind.ClassType) and (Symbol.Container = '') and SameText(Symbol.Name, AName) then
    begin
      AType := Default(TSymbolLocation);
      AType.Symbol := Symbol;
      Exit(True);
    end;
  Result := False;
  if FIndex = nil then
    Exit;
  Found := False;
  for Location in FIndex.FindSymbols(AName) do
  begin
    if (Location.Symbol.Kind <> TIndexSymbolKind.ClassType) or (Location.Symbol.Container <> '') then
      Continue;
    if not Found then
    begin
      AType := Location;
      Found := True;
    end
    // Mehrere gleichnamige Klassen mit verschiedenen Vorfahren: keine Aussage.
    else if (Length(Location.Symbol.Ancestors) > 0) <> (Length(AType.Symbol.Ancestors) > 0) or
      ((Length(AType.Symbol.Ancestors) > 0) and
      not SameText(BareName(Location.Symbol.Ancestors[0]), BareName(AType.Symbol.Ancestors[0]))) then
      Exit(False);
  end;
  Result := Found;
end;

function TAncestry.Methods(const AType: TSymbolLocation): TArray<TIndexSymbol>;
var
  Symbol: TIndexSymbol;
begin
  Result := nil;
  for Symbol in Members(AType) do
    if Symbol.Kind in [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_] then
      Result := Result + [Symbol];
end;

function TAncestry.Members(const AType: TSymbolLocation): TArray<TIndexSymbol>;
var
  Symbols: TArray<TIndexSymbol>;
  Symbol: TIndexSymbol;
  UnitIndex: TUnitIndex;
begin
  Result := nil;
  if AType.FileName = '' then
    Symbols := FLocal.Symbols
  else if (FIndex <> nil) and FIndex.FindFile(AType.FileName, UnitIndex) then
    Symbols := UnitIndex.Symbols
  else
    Exit;
  for Symbol in Symbols do
    if (Symbol.Kind in [TIndexSymbolKind.Field, TIndexSymbolKind.Property_, TIndexSymbolKind.Method,
      TIndexSymbolKind.Constructor_]) and SameText(Symbol.Container, AType.Symbol.Name) and
      ContainsLine(AType.Symbol.Range, Symbol.Range.StartPos.Line) then
      Result := Result + [Symbol];
end;

function TAncestry.FindAnyType(const AName: string; out AType: TSymbolLocation): Boolean;
const
  Kinds = [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType,
    TIndexSymbolKind.InterfaceType, TIndexSymbolKind.EnumType, TIndexSymbolKind.TypeAlias];
var
  Symbol: TIndexSymbol;
  Location: TSymbolLocation;
begin
  for Symbol in FLocal.Symbols do
    if (Symbol.Kind in Kinds) and (Symbol.Container = '') and SameText(Symbol.Name, AName) then
    begin
      AType := Default(TSymbolLocation);
      AType.Symbol := Symbol;
      Exit(True);
    end;
  if FIndex <> nil then
    for Location in FIndex.FindSymbols(AName) do
      if (Location.Symbol.Kind in Kinds) and (Location.Symbol.Container = '') then
      begin
        AType := Location;
        Exit(True);
      end;
  Result := False;
end;

function TAncestry.SameType(const A, B: string; const AWildcards: TArray<string>): Boolean;
begin
  Result := (CanonicalType(A) = CanonicalType(B)) or MatchText(BareName(A), AWildcards) or
    MatchText(BareName(B), AWildcards);
  // Ein Alias der Datei oder des Index kann auf den anderen Typ zeigen: keine Aussage.
  if not Result and (A <> '') and (B <> '') then
    Result := IsTypeAlias(BareName(A)) or IsTypeAlias(BareName(B));
end;

function TAncestry.KnownType(const AName: string): Boolean;
begin
  Result := MatchText(CanonicalType(AName), BuiltinTypes) or IsDeclaredType(BareName(AName));
end;

function TAncestry.MethodsOf(const AType: TSymbolLocation; const AName: string): TArray<TIndexSymbol>;
var
  Symbol: TIndexSymbol;
begin
  Result := nil;
  for Symbol in Methods(AType) do
    if SameText(Symbol.Name, AName) then
      Result := Result + [Symbol];
end;

function TAncestry.Ancestors(const ATypeName: string; out AComplete, AObjectMissing: Boolean): TArray<TSymbolLocation>;
var
  Name: string;
  Location: TSymbolLocation;
  Depth: Integer;
begin
  Result := nil;
  AComplete := False;
  AObjectMissing := False;
  Name := ParentOf(ATypeName);
  Depth := 0;
  while (Name <> '') and (Depth < 64) do
  begin
    if not FindType(Name, Location) then
    begin
      AObjectMissing := SameText(Name, 'TObject');
      AComplete := AObjectMissing;
      Exit;
    end;
    Result := Result + [Location];
    if SameText(Name, 'TObject') then
    begin
      AComplete := True;
      Exit;
    end;
    if Length(Location.Symbol.Ancestors) = 0 then
      Name := 'TObject'
    else
      Name := BareName(Location.Symbol.Ancestors[0]);
    Inc(Depth);
  end;
end;

function TAncestry.FindClass(const AName: string; out AType: TSymbolLocation): Boolean;
begin
  Result := FindType(AName, AType);
end;

function TAncestry.IsDeclaredType(const AName: string): Boolean;
const
  Kinds = [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType,
    TIndexSymbolKind.InterfaceType, TIndexSymbolKind.EnumType];
var
  Symbol: TIndexSymbol;
  Location: TSymbolLocation;
begin
  for Symbol in FLocal.Symbols do
    if (Symbol.Kind in Kinds) and (Symbol.Container = '') and SameText(Symbol.Name, AName) then
      Exit(True);
  if FIndex <> nil then
    for Location in FIndex.FindSymbols(AName) do
      if (Location.Symbol.Kind in Kinds) and (Location.Symbol.Container = '') then
        Exit(True);
  Result := False;
end;

function TAncestry.IsTypeAlias(const AName: string): Boolean;
var
  Symbol: TIndexSymbol;
  Location: TSymbolLocation;
begin
  for Symbol in FLocal.Symbols do
    if (Symbol.Kind = TIndexSymbolKind.TypeAlias) and SameText(Symbol.Name, AName) then
      Exit(True);
  if FIndex <> nil then
    for Location in FIndex.FindSymbols(AName) do
      if Location.Symbol.Kind = TIndexSymbolKind.TypeAlias then
        Exit(True);
  Result := False;
end;

function TAncestry.HasConstructor(const ATypeName: string): Boolean;
var
  Location: TSymbolLocation;
  Symbols: TArray<TIndexSymbol>;
  Symbol: TIndexSymbol;
  UnitIndex: TUnitIndex;
begin
  Result := False;
  if not FindType(ATypeName, Location) then
    Exit;
  if Location.FileName = '' then
    Symbols := FLocal.Symbols
  else if (FIndex <> nil) and FIndex.FindFile(Location.FileName, UnitIndex) then
    Symbols := UnitIndex.Symbols
  else
    Exit;
  for Symbol in Symbols do
    // Der Index führt Destruktoren ebenfalls als Constructor_.
    if (Symbol.Kind = TIndexSymbolKind.Constructor_) and not SameText(Symbol.Name, 'Destroy') and
      SameText(Symbol.Container, Location.Symbol.Name) and
      ContainsLine(Location.Symbol.Range, Symbol.Range.StartPos.Line) then
      Exit(True);
end;

function TAncestry.ParentOf(const ATypeName: string): string;
var
  Location: TSymbolLocation;
begin
  if not FindType(ATypeName, Location) then
    Exit('');
  if Length(Location.Symbol.Ancestors) = 0 then
    Result := 'TObject'
  else
    Result := BareName(Location.Symbol.Ancestors[0]);
end;

function TAncestry.DescendsFrom(const ATypeName, AAncestor: string): Boolean;
var
  Name: string;
  Depth: Integer;
begin
  Name := ParentOf(ATypeName);
  Depth := 0;
  while (Name <> '') and (Depth < 64) do
  begin
    if SameText(Name, AAncestor) then
      Exit(True);
    if SameText(Name, 'TObject') then
      Break;
    Name := ParentOf(Name);
    Inc(Depth);
  end;
  Result := False;
end;

function TAncestry.InheritedVirtual(const AMethod: TMethodDecl): TInherited;
var
  Name: string;
  Location: TSymbolLocation;
  Candidate: TIndexSymbol;
  Depth: Integer;
  Any: Boolean;
begin
  Result := Default(TInherited);
  Name := ParentOf(AMethod.ClassName);
  Depth := 0;
  while (Name <> '') and (Depth < 64) and FindType(Name, Location) do
  begin
    Any := False;
    for Candidate in MethodsOf(Location, AMethod.Symbol.Name) do
    begin
      // Private Methoden fremder Units sieht der Nachfahre nicht.
      if (Location.FileName <> '') and (Candidate.Visibility in [TIndexVisibility.Private,
        TIndexVisibility.StrictPrivate]) then
        Continue;
      Any := True;
      if not Candidate.IsVirtual then
        Continue;
      if not Result.Found or (not Result.SameSignature and SameSignature(Candidate, AMethod.Symbol)) then
      begin
        Result.Found := True;
        Result.TypeName := Location.Symbol.Name;
        Result.Symbol := Candidate;
        Result.SameSignature := SameSignature(Candidate, AMethod.Symbol);
      end;
    end;
    // Die nächste Stufe mit gleichnamiger Methode entscheidet.
    if Any or SameText(Name, 'TObject') then
      Exit;
    Name := ParentOf(Name);
    Inc(Depth);
  end;
end;

{ Hilfen für die Regeln }

function TokenAt(const AContext: TRuleContext; AOffset: Integer; out AToken: TPascalToken): Boolean;
var
  Token: TPascalToken;
begin
  for Token in AContext.Tree.Tokens do
    if Token.Offset = AOffset then
    begin
      AToken := Token;
      Exit(True);
    end;
  Result := False;
end;

/// <summary>Position hinter dem letzten Token vor AEndOffset.</summary>
function EndPosition(const AContext: TRuleContext; AEndOffset: Integer; out APosition: TTextPosition): Boolean;
var
  Token: TPascalToken;
begin
  Result := False;
  for Token in AContext.Tree.Tokens do
  begin
    if Token.Offset >= AEndOffset then
      Break;
    if Token.Offset + Length(Token.Text) = AEndOffset then
    begin
      APosition := Token.EndPos;
      Result := True;
    end;
  end;
end;

/// <summary>Korrektur, die " ADirective;" hinter den Methodenkopf setzt.</summary>
function AppendDirective(const AContext: TRuleContext; const AMethod: TMethodDecl; const ADirective: string;
  out AFix: TRuleFix): Boolean;
var
  Position: TTextPosition;
begin
  Result := EndPosition(AContext, AMethod.Header.EndOffset, Position);
  if Result then
    AFix := TRuleFix.Create(Format('"%s" ergänzen', [ADirective]),
      [TRuleEdit.Create(TTextRange.Create(Position, Position), ' ' + ADirective + ';')]);
end;

/// <summary>Methodendeklarationen aller Klassen der Datei.</summary>
function ClassMethods(const AContext: TRuleContext; AAncestry: TAncestry): TArray<TMethodDecl>;
var
  Methods: TList<TMethodDecl>;

  procedure Visit(ANode: TSyntaxNode);
  var
    Index, Inner: Integer;
    Body, Header: TSyntaxNode;
    Method: TMethodDecl;
    Token: TPascalToken;
    Symbol: TIndexSymbol;
  begin
    if ANode.Kind = TSyntaxKind.TypeDecl then
    begin
      Body := ANode.FindChild(TSyntaxKind.ClassType);
      if Body <> nil then
        for Index := 0 to Body.ChildCount - 1 do
        begin
          Header := Body[Index];
          if Header.Kind <> TSyntaxKind.RoutineHeader then
            Continue;
          Method := Default(TMethodDecl);
          Method.ClassName := ANode.Name;
          Method.Header := Header;
          if TokenAt(AContext, Header.StartOffset, Token) then
            Method.Keyword := LowerCase(Token.Text);
          for Inner := 0 to Header.ChildCount - 1 do
            if Header[Inner].Kind = TSyntaxKind.Directive then
              Method.Directives := Method.Directives + [LowerCase(Header[Inner].Name)];
          // class procedure/static: keine virtuellen Instanzmethoden.
          if (Method.Keyword = 'class') or Method.Has('static') or Method.Has('message') then
            Continue;
          for Symbol in AAncestry.Local.Symbols do
            if (Symbol.Kind in [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_]) and
              SameText(Symbol.Container, ANode.Name) and (Symbol.Range.StartPos = Header.StartPos) then
            begin
              Method.Symbol := Symbol;
              Methods.Add(Method);
              Break;
            end;
        end;
    end;
    for Index := 0 to ANode.ChildCount - 1 do
      Visit(ANode[Index]);
  end;

begin
  Methods := TList<TMethodDecl>.Create;
  try
    Visit(AContext.Tree.Root);
    Result := Methods.ToArray;
  finally
    Methods.Free;
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
  Method: TMethodDecl;
  Cache: IRuleDerivedCache;
begin
  AAncestry := nil;
  AMethods := nil;
  if AContext.Tree = nil then
    Exit(False);
  // Den Index der Datei teilt der Lauf mit den anderen Regeln (Review P-03).
  Cache := TRuleDerived.Open(AContext);
  AAncestry := TAncestry.Create(AContext.Index, TRuleDerived.UnitIndex(Cache, AContext));
  for Method in ClassMethods(AContext, AAncestry) do
    if not Settled(Method) then
      AMethods := AMethods + [Method];
  Result := True;
end;

{ TDestroyWithoutOverrideRule }

function TDestroyWithoutOverrideRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('destroy-without-override', TRuleSeverity.Warning,
    'destructor Destroy ohne override');
end;

procedure TDestroyWithoutOverrideRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
const
  Message = 'Destroy ohne override: Free ruft diesen Destruktor nicht auf';
var
  Ancestry: TAncestry;
  Methods: TArray<TMethodDecl>;
  Method: TMethodDecl;
  Fix: TRuleFix;
begin
  if not Prepare(AContext, Ancestry, Methods) then
    Exit;
  try
    for Method in Methods do
    begin
      // Mit virtual meldet virtual-instead-of-override.
      if not IsDestroy(Method) or Method.Has('virtual') or Method.Has('dynamic') then
        Continue;
      if AppendDirective(AContext, Method, 'override', Fix) then
        AReport.Add(Method.Symbol.SelectionRange, Message, [Fix])
      else
        AReport.Add(Method.Symbol.SelectionRange, Message);
    end;
  finally
    Ancestry.Free;
  end;
end;

{ TComponentCreateWithoutOverrideRule }

function TComponentCreateWithoutOverrideRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('component-create-without-override', TRuleSeverity.Warning,
    'constructor Create(AOwner: TComponent) ohne override in einer Komponente');
end;

procedure TComponentCreateWithoutOverrideRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
const
  Message = 'Create(AOwner: TComponent) ohne override: beim Laden aus der DFM wird dieser Konstruktor ' +
    'nicht aufgerufen';
var
  Ancestry: TAncestry;
  Methods: TArray<TMethodDecl>;
  Method: TMethodDecl;
  Fix: TRuleFix;
begin
  if not Prepare(AContext, Ancestry, Methods) then
    Exit;
  try
    for Method in Methods do
    begin
      if not IsComponentCreate(Method) or Method.Has('virtual') or Method.Has('dynamic') or
        not Ancestry.DescendsFrom(Method.ClassName, 'TComponent') then
        Continue;
      if AppendDirective(AContext, Method, 'override', Fix) then
        AReport.Add(Method.Symbol.SelectionRange, Message, [Fix])
      else
        AReport.Add(Method.Symbol.SelectionRange, Message);
    end;
  finally
    Ancestry.Free;
  end;
end;

{ THidesVirtualRule }

function THidesVirtualRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('hides-virtual', TRuleSeverity.Warning,
    'Methode verdeckt eine virtuelle Methode des Vorfahren');
end;

procedure THidesVirtualRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Ancestry: TAncestry;
  Methods: TArray<TMethodDecl>;
  Method: TMethodDecl;
  Found: TInherited;
  Fixes: TArray<TRuleFix>;
  Fix: TRuleFix;
  Confidence: TRuleConfidence;
  IsVirtual: Boolean;
begin
  if not Prepare(AContext, Ancestry, Methods) then
    Exit;
  try
    for Method in Methods do
    begin
      // Destroy und Create(TComponent) haben eigene Regeln.
      if IsDestroy(Method) or IsComponentCreate(Method) then
        Continue;
      Found := Ancestry.InheritedVirtual(Method);
      if not Found.Found then
        Continue;
      IsVirtual := Method.Has('virtual') or Method.Has('dynamic');
      // virtual bei gleicher Signatur prüft virtual-instead-of-override; eine Überladung
      // mit anderer Signatur verdeckt nichts.
      if (IsVirtual and Found.SameSignature) or (Method.Has('overload') and not Found.SameSignature) then
        Continue;
      Fixes := nil;
      if Found.SameSignature and AppendDirective(AContext, Method, 'override', Fix) then
      begin
        Fix.Alternative := True;
        Fixes := Fixes + [Fix];
      end;
      if AppendDirective(AContext, Method, 'reintroduce', Fix) then
      begin
        Fix.Alternative := True;
        Fixes := Fixes + [Fix];
      end;
      if Found.SameSignature then
        Confidence := TRuleConfidence.High
      else
        Confidence := TRuleConfidence.Medium;
      AReport.Add(Method.Symbol.SelectionRange, Format('"%s" verdeckt die virtuelle Methode %s.%s; override ' +
        'oder reintroduce angeben', [Method.Symbol.Name, Found.TypeName, Found.Symbol.Name]), Confidence, Fixes);
    end;
  finally
    Ancestry.Free;
  end;
end;

{ TVirtualInsteadOfOverrideRule }

function TVirtualInsteadOfOverrideRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('virtual-instead-of-override', TRuleSeverity.Warning,
    'virtual im Nachfahren statt override');
end;

/// <summary>Token der Direktive virtual bzw. dynamic im Kopf.</summary>
function VirtualToken(const AContext: TRuleContext; const AMethod: TMethodDecl; out AToken: TPascalToken): Boolean;
var
  Index: Integer;
  Directive: TSyntaxNode;
begin
  for Index := 0 to AMethod.Header.ChildCount - 1 do
  begin
    Directive := AMethod.Header[Index];
    if (Directive.Kind = TSyntaxKind.Directive) and MatchText(Directive.Name, ['virtual', 'dynamic']) and
      TokenAt(AContext, Directive.StartOffset, AToken) then
      Exit(True);
  end;
  Result := False;
end;

procedure TVirtualInsteadOfOverrideRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Ancestry: TAncestry;
  Methods: TArray<TMethodDecl>;
  Method: TMethodDecl;
  Found: TInherited;
  Token: TPascalToken;
  Message: string;
begin
  if not Prepare(AContext, Ancestry, Methods) then
    Exit;
  try
    for Method in Methods do
    begin
      if not Method.Has('virtual') and not Method.Has('dynamic') then
        Continue;
      // TObject.Destroy ist immer virtuell, auch wenn TObject nicht im Index steht.
      if not IsDestroy(Method) then
      begin
        Found := Ancestry.InheritedVirtual(Method);
        if not Found.Found or not Found.SameSignature then
          Continue;
      end;
      Message := Format('"%s" ist im Vorfahren schon virtuell; override statt %s verwenden',
        [Method.Symbol.Name, IfThen(Method.Has('virtual'), 'virtual', 'dynamic')]);
      if VirtualToken(AContext, Method, Token) then
        AReport.Add(Method.Symbol.SelectionRange, Message, [TRuleFix.Create(Format('%s durch override ersetzen',
          [Token.Text]), [TRuleEdit.Create(TTextRange.Create(Token.StartPos, Token.EndPos), 'override')])])
      else
        AReport.Add(Method.Symbol.SelectionRange, Message);
    end;
  finally
    Ancestry.Free;
  end;
end;

{ TShadowedNameRule }

const
  ShadowDefaultIgnore: array[0..1] of string = ('Sender', 'Value');
  // Ohne VCL im Index: Mitglieder von TComponent bzw. TControl, wenn die Kette an einer dieser Klassen abbricht.
  ComponentClasses: array[0..1] of string = ('TComponent', 'TDataModule');
  ComponentMembers: array[0..5] of string = ('Name', 'Tag', 'Owner', 'ComponentCount', 'ComponentIndex',
    'Components');
  ControlClasses: array[0..14] of string = ('TControl', 'TWinControl', 'TCustomControl', 'TGraphicControl', 'TForm',
    'TCustomForm', 'TFrame', 'TCustomFrame', 'TScrollingWinControl', 'TPanel', 'TCustomPanel', 'TScrollBox',
    'TPageControl', 'TTabSheet', 'TGroupBox');
  ControlMembers: array[0..20] of string = ('Left', 'Top', 'Width', 'Height', 'Caption', 'Text', 'Hint', 'Visible',
    'Enabled', 'Color', 'Font', 'Parent', 'Align', 'Anchors', 'Cursor', 'ShowHint', 'PopupMenu', 'ClientWidth',
    'ClientHeight', 'Action', 'Constraints');

function TAncestry.FindMember(const ATypeName, AName: string; out AMember: TIndexSymbol;
  out AUnresolved: string): Boolean;
var
  Name: string;
  Location: TSymbolLocation;
  Symbols: TArray<TIndexSymbol>;
  Symbol: TIndexSymbol;
  UnitIndex: TUnitIndex;
  Depth: Integer;
  Visible: Boolean;
begin
  AMember := Default(TIndexSymbol);
  AUnresolved := '';
  Name := ATypeName;
  Depth := 0;
  while (Name <> '') and (Depth < 64) do
  begin
    if not FindType(Name, Location) then
    begin
      AUnresolved := Name;
      Exit(False);
    end;
    if Location.FileName = '' then
      Symbols := FLocal.Symbols
    else if (FIndex <> nil) and FIndex.FindFile(Location.FileName, UnitIndex) then
      Symbols := UnitIndex.Symbols
    else
      Symbols := nil;
    for Symbol in Symbols do
      if (Symbol.Kind in [TIndexSymbolKind.Field, TIndexSymbolKind.Property_]) and
        SameText(Symbol.Container, Location.Symbol.Name) and SameText(Symbol.Name, AName) and
        ContainsLine(Location.Symbol.Range, Symbol.Range.StartPos.Line) then
      begin
        // private ist nur in derselben Unit sichtbar, strict private nur in der Klasse selbst.
        Visible := (Depth = 0) or ((Location.FileName = '') and (Symbol.Visibility <> TIndexVisibility.StrictPrivate)) or
          not (Symbol.Visibility in [TIndexVisibility.Private, TIndexVisibility.StrictPrivate]);
        if Visible then
        begin
          AMember := Symbol;
          Exit(True);
        end;
      end;
    if Length(Location.Symbol.Ancestors) = 0 then
      Break;
    Name := BareName(Location.Symbol.Ancestors[0]);
    Inc(Depth);
  end;
  Result := False;
end;

function TShadowedNameRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('shadowed-name', TRuleSeverity.Hint,
    'Lokaler Name verdeckt Feld, Property oder globale Variable');
end;

procedure TShadowedNameRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Ancestry: TAncestry;
  Ignore: TArray<string>;
  Tokens: TArray<TPascalToken>;

  function SplitNames(const ANames: string): TArray<string>;
  var
    Name: string;
  begin
    Result := nil;
    for Name in SplitString(ANames, ',') do
      if Trim(Name) <> '' then
        Result := Result + [Trim(Name)];
  end;

  // Bezeichner-Token AName in ANode, die nicht hinter einem Punkt stehen (Self.Caption bleibt).
  function NameTokens(ANode: TSyntaxNode; const AName: string): TArray<Integer>;
  var
    Index, Previous: Integer;
  begin
    Result := nil;
    for Index := 0 to High(Tokens) do
    begin
      if Tokens[Index].Offset >= ANode.EndOffset then
        Break;
      if (Tokens[Index].Offset < ANode.StartOffset) or
        not (Tokens[Index].Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) or
        not SameText(Tokens[Index].Text, AName) then
        Continue;
      Previous := Index - 1;
      while (Previous >= 0) and (Tokens[Previous].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
        Dec(Previous);
      if (Previous >= 0) and Tokens[Previous].IsSymbol('.') then
        Continue;
      Result := Result + [Index];
    end;
  end;

  function TokenRange(AIndex: Integer): TTextRange;
  begin
    Result := TTextRange.Create(Tokens[AIndex].StartPos, Tokens[AIndex].EndPos);
  end;

  function Assigned_(ANode: TSyntaxNode; const AName: string): Boolean;
  var
    Index: Integer;
  begin
    if (ANode.Kind = TSyntaxKind.AssignStatement) and (ANode.ChildCount = 2) and
      (ANode[0].Kind = TSyntaxKind.Identifier) and SameText(ANode[0].Name, AName) then
      Exit(True);
    for Index := 0 to ANode.ChildCount - 1 do
      if Assigned_(ANode[Index], AName) then
        Exit(True);
    Result := False;
  end;

  // Deklaration der Methode in der Klasse: Kopf mit gleichem Namen und demselben Parameter an derselben Stelle.
  function DeclarationHeader(const AClassName, AMethod, AParam: string; AParamIndex: Integer): TSyntaxNode;

    function Search(ANode: TSyntaxNode; AInClass: Boolean): TSyntaxNode;
    var
      Index, Position: Integer;
      Params: TSyntaxNode;
      Name: string;
    begin
      Result := nil;
      if ANode.Kind = TSyntaxKind.TypeDecl then
        AInClass := SameText(ANode.Name, AClassName);
      if AInClass and (ANode.Kind = TSyntaxKind.RoutineHeader) and SameText(ANode.Name, AMethod) then
      begin
        Params := ANode.FindChild(TSyntaxKind.Parameters);
        Position := 0;
        if Params <> nil then
          for Index := 0 to Params.ChildCount - 1 do
            if Params[Index].Kind = TSyntaxKind.Parameter then
              for Name in SplitNames(Params[Index].Name) do
              begin
                if (Position = AParamIndex) and SameText(Name, AParam) then
                  Exit(ANode);
                Inc(Position);
              end;
        Exit;
      end;
      if ANode.Kind in [TSyntaxKind.ImplementationSection, TSyntaxKind.RoutineDecl] then
        Exit;
      for Index := 0 to ANode.ChildCount - 1 do
      begin
        Result := Search(ANode[Index], AInClass);
        if Result <> nil then
          Exit;
      end;
    end;

  begin
    Result := Search(AContext.Tree.Root, False);
  end;

  // Globale Variable der Unit vor ARoutine.
  function GlobalVariable(ARoutine: TSyntaxNode; const AName: string): Boolean;
  var
    Symbol: TIndexSymbol;
  begin
    for Symbol in Ancestry.Local.Symbols do
      if (Symbol.Kind = TIndexSymbolKind.Variable) and (Symbol.Container = '') and SameText(Symbol.Name, AName) and
        (Symbol.Range.StartPos.Line < ARoutine.StartPos.Line) then
        Exit(True);
    Result := False;
  end;

  procedure CheckName(ARoutine: TSyntaxNode; const AClassName, AName: string; AIsParameter: Boolean;
    ADeclaration: TSyntaxNode; AParamIndex: Integer);
  var
    Member: TIndexSymbol;
    Unresolved, What, Kind, NewName, Message, Pattern: string;
    Found: Boolean;
    Header: TSyntaxNode;
    Positions: TArray<Integer>;
    Index: Integer;
    Edits: TArray<TRuleEdit>;
    Fixes: TArray<TRuleFix>;
  begin
    for Pattern in Ignore do
      if MatchesWildcard(AName, Pattern) then
        Exit;
    Found := False;
    Kind := '';
    if AClassName <> '' then
    begin
      Found := Ancestry.FindMember(AClassName, AName, Member, Unresolved);
      if Found then
      begin
        if Member.Kind = TIndexSymbolKind.Field then
          Kind := 'das Feld ' + AClassName + '.' + Member.Name
        else
          Kind := 'die Property ' + AClassName + '.' + Member.Name;
      end
      else if (MatchText(Unresolved, ComponentClasses) or MatchText(Unresolved, ControlClasses)) and
        MatchText(AName, ComponentMembers) then
      begin
        Found := True;
        Kind := 'die Property ' + AClassName + '.' + AName;
      end
      else if MatchText(Unresolved, ControlClasses) and MatchText(AName, ControlMembers) then
      begin
        Found := True;
        Kind := 'die Property ' + AClassName + '.' + AName;
      end;
    end;
    if not Found and GlobalVariable(ARoutine, AName) then
    begin
      Found := True;
      Kind := 'die globale Variable ' + AName;
    end;
    if not Found then
      Exit;
    if AIsParameter then
      What := 'Parameter'
    else
      What := 'Lokale Variable';
    Message := Format('%s %s verdeckt %s', [What, AName, Kind]);
    if Assigned_(ARoutine, AName) then
    begin
      if AIsParameter then
        Message := Message + '; die Zuweisung ändert nur den Parameter.'
      else
        Message := Message + '; die Zuweisung ändert nur die lokale Variable.';
    end
    else
      Message := Message + '.';
    // Umbenennen: AName für Parameter, LName für lokale Variablen; alle Vorkommen in der Routine.
    if AIsParameter then
      NewName := 'A' + AName
    else
      NewName := 'L' + AName;
    Fixes := nil;
    Positions := NameTokens(ARoutine, AName);
    Header := nil;
    if AIsParameter and (AClassName <> '') then
      Header := DeclarationHeader(AClassName, Copy(ARoutine.Name, LastDelimiter('.', ARoutine.Name) + 1, MaxInt),
        AName, AParamIndex);
    if (NameTokens(ARoutine, NewName) = nil) and ((Header = nil) or (NameTokens(Header, NewName) = nil)) then
    begin
      Edits := nil;
      for Index in Positions do
        Edits := Edits + [TRuleEdit.Create(TokenRange(Index), NewName)];
      if Header <> nil then
        for Index in NameTokens(Header, AName) do
          Edits := Edits + [TRuleEdit.Create(TokenRange(Index), NewName)];
      Fixes := [TRuleFix.Create(Format('In %s umbenennen', [NewName]), Edits)];
    end;
    for Index in NameTokens(ADeclaration, AName) do
    begin
      AReport.Add(TokenRange(Index), Message, TRuleConfidence.High, Fixes);
      Exit;
    end;
  end;

  procedure CheckRoutine(ARoutine: TSyntaxNode; const AClassName: string);
  var
    Header, Params, Child: TSyntaxNode;
    Index, Inner, Position: Integer;
    Name, ClassName: string;
    HasSender: Boolean;

    procedure CheckInline(ANode: TSyntaxNode);
    var
      Item: Integer;
      InlineName: string;
    begin
      if ANode.Kind = TSyntaxKind.InlineVar then
        for InlineName in SplitNames(ANode.Name) do
          CheckName(ARoutine, ClassName, InlineName, False, ANode, -1);
      if ANode.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod] then
        Exit;
      for Item := 0 to ANode.ChildCount - 1 do
        CheckInline(ANode[Item]);
    end;

  begin
    ClassName := AClassName;
    if (ClassName = '') and (Pos('.', ARoutine.Name) > 0) then
    begin
      ClassName := Copy(ARoutine.Name, 1, LastDelimiter('.', ARoutine.Name) - 1);
      ClassName := Copy(ClassName, LastDelimiter('.', ClassName) + 1, MaxInt);
    end;
    Header := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
    Params := nil;
    if Header <> nil then
      Params := Header.FindChild(TSyntaxKind.Parameters);
    // Ereignis-Handler (mit Sender): die Signatur gibt der Ereignistyp vor, z. B. FormClose(…; var Action).
    HasSender := False;
    if Params <> nil then
      for Index := 0 to Params.ChildCount - 1 do
        if Params[Index].Kind = TSyntaxKind.Parameter then
          for Name in SplitNames(Params[Index].Name) do
            HasSender := HasSender or SameText(Name, 'Sender');
    if (Params <> nil) and not HasSender then
    begin
      Position := 0;
      for Index := 0 to Params.ChildCount - 1 do
        if Params[Index].Kind = TSyntaxKind.Parameter then
          for Name in SplitNames(Params[Index].Name) do
          begin
            CheckName(ARoutine, ClassName, Name, True, Params[Index], Position);
            Inc(Position);
          end;
    end;
    for Index := 0 to ARoutine.ChildCount - 1 do
    begin
      Child := ARoutine[Index];
      if Child.Kind = TSyntaxKind.VarSection then
      begin
        for Inner := 0 to Child.ChildCount - 1 do
          if Child[Inner].Kind = TSyntaxKind.VarDecl then
            for Name in SplitNames(Child[Inner].Name) do
              CheckName(ARoutine, ClassName, Name, False, Child[Inner], -1);
      end
      else if Child.Kind = TSyntaxKind.Block then
        CheckInline(Child)
      else if Child.Kind = TSyntaxKind.RoutineDecl then
        CheckRoutine(Child, ClassName);
    end;
  end;

  procedure Visit(ANode: TSyntaxNode);
  var
    Index: Integer;
  begin
    if ANode.Kind = TSyntaxKind.RoutineDecl then
    begin
      CheckRoutine(ANode, '');
      Exit;
    end;
    for Index := 0 to ANode.ChildCount - 1 do
      Visit(ANode[Index]);
  end;

var
  Cache: IRuleDerivedCache;
  Defaults: TArray<string>;
  Name: string;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  Defaults := nil;
  for Name in ShadowDefaultIgnore do
    Defaults := Defaults + [Name];
  Ignore := TRuleOptions.Strings(AContext.Options, 'ignore', Defaults);
  Tokens := AContext.Tree.Tokens;
  Cache := TRuleDerived.Open(AContext);
  Ancestry := TAncestry.Create(AContext.Index, TRuleDerived.UnitIndex(Cache, AContext));
  try
    Visit(AContext.Tree.Root);
  finally
    Ancestry.Free;
  end;
end;

{ TOverrideTargetMissingRule }

type
  /// <summary>Gleichnamige Methode eines Vorfahren für override-target-missing (#997).</summary>
  TOverrideCandidate = record
    TypeName: string;
    Symbol: TIndexSymbol;
    /// <summary>procedure, function, constructor oder destructor aus der Signatur.</summary>
    Keyword: string;
    /// <summary>Kopf ab dem Namen ohne Direktiven, z. B. "Ausfuehren(const Modus: TModus)".</summary>
    Head: string;
  end;

  /// <summary>Vergleich zweier Köpfe: gleich, nur Typen anders, anders gebaut.</summary>
  TOverrideMatch = (Same, OtherTypes, Different);

/// <summary>Schlüsselwort und Kopf ab dem Namen aus einer Signatur wie "procedure Foo(A: Integer); virtual;".
/// </summary>
function SplitSignature(const ASignature: string; out AKeyword, AHead: string): Boolean;
var
  Text: string;
  Index, Depth: Integer;
begin
  Text := Trim(ASignature);
  AKeyword := LowerCase(Copy(Text, 1, Pos(' ', Text + ' ') - 1));
  AHead := '';
  Result := MatchText(AKeyword, ['procedure', 'function', 'constructor', 'destructor']);
  if not Result then
    Exit;
  Text := Trim(Copy(Text, Length(AKeyword) + 1, MaxInt));
  Depth := 0;
  for Index := 1 to Length(Text) do
    case Text[Index] of
      '(', '[':
        Inc(Depth);
      ')', ']':
        Dec(Depth);
      ';':
        if Depth = 0 then
        begin
          AHead := Trim(Copy(Text, 1, Index - 1));
          Exit;
        end;
    end;
  AHead := Text;
end;

/// <summary>Kopf ohne Standardwerte der Parameter, für den Rumpf.</summary>
function WithoutDefaults(const AHead: string): string;
var
  Index, Depth: Integer;
  Skipping: Boolean;
  Quoted: Boolean;
begin
  Result := '';
  Depth := 0;
  Skipping := False;
  Quoted := False;
  for Index := 1 to Length(AHead) do
  begin
    if AHead[Index] = '''' then
      Quoted := not Quoted;
    if not Quoted then
      case AHead[Index] of
        '(', '[':
          Inc(Depth);
        ')', ']':
          begin
            Dec(Depth);
            if Depth = 0 then
              Skipping := False;
          end;
        ';':
          if Depth = 1 then
            Skipping := False;
        '=':
          if Depth = 1 then
            Skipping := True;
      end;
    if not Skipping then
      Result := Result + AHead[Index];
  end;
  Result := StringReplace(Result, ' ;', ';', [rfReplaceAll]);
  Result := StringReplace(Result, ' )', ')', [rfReplaceAll]);
end;

function TOverrideTargetMissingRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('override-target-missing', TRuleSeverity.Error,
    'override ohne passende virtuelle Methode im Vorfahren');
end;

procedure TOverrideTargetMissingRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Cache: IRuleDerivedCache;
  Ancestry: TAncestry;
  Tokens: TArray<TPascalToken>;

  function Wildcards(const AClassName: string; const AChain: TArray<TSymbolLocation>): TArray<string>;
  var
    Location: TSymbolLocation;
    Symbol: TIndexSymbol;
    Name: string;
  begin
    Result := nil;
    for Location in AChain do
      for Name in SplitString(Location.Symbol.TypeParams, ',') do
        if Trim(Name) <> '' then
          Result := Result + [Trim(Name)];
    for Symbol in Ancestry.Local.Symbols do
      if (Symbol.Kind = TIndexSymbolKind.ClassType) and SameText(Symbol.Name, AClassName) then
        for Name in SplitString(Symbol.TypeParams, ',') do
          if Trim(Name) <> '' then
            Result := Result + [Trim(Name)];
  end;

  /// <summary>Wie Compare; ACertain: alle abweichenden Typen stehen sicher für sich.</summary>
  function CompareTypes(const AMethod: TMethodDecl; const ACandidate: TOverrideCandidate;
    const AWildcards: TArray<string>; out ACertain: Boolean): TOverrideMatch;
  var
    Index: Integer;

    procedure Differ(const A, B: string);
    begin
      Result := TOverrideMatch.OtherTypes;
      ACertain := ACertain and Ancestry.KnownType(A) and Ancestry.KnownType(B);
    end;

  begin
    ACertain := True;
    if (ACandidate.Keyword <> AMethod.Keyword) or (AMethod.Symbol.MaxArgs <> ACandidate.Symbol.MaxArgs) or
      (Length(AMethod.Symbol.ParamTypes) <> Length(ACandidate.Symbol.ParamTypes)) or
      ((AMethod.Symbol.TypeName = '') <> (ACandidate.Symbol.TypeName = '')) then
      Exit(TOverrideMatch.Different);
    Result := TOverrideMatch.Same;
    for Index := 0 to High(AMethod.Symbol.ParamTypes) do
      if (AMethod.Symbol.ParamTypes[Index] = '') <> (ACandidate.Symbol.ParamTypes[Index] = '') then
        Exit(TOverrideMatch.Different)
      else if not Ancestry.SameType(AMethod.Symbol.ParamTypes[Index], ACandidate.Symbol.ParamTypes[Index],
        AWildcards) then
        Differ(AMethod.Symbol.ParamTypes[Index], ACandidate.Symbol.ParamTypes[Index]);
    if not Ancestry.SameType(AMethod.Symbol.TypeName, ACandidate.Symbol.TypeName, AWildcards) then
      Differ(AMethod.Symbol.TypeName, ACandidate.Symbol.TypeName);
  end;

  function Compare(const AMethod: TMethodDecl; const ACandidate: TOverrideCandidate;
    const AWildcards: TArray<string>): TOverrideMatch;
  var
    Certain: Boolean;
  begin
    Result := CompareTypes(AMethod, ACandidate, AWildcards, Certain);
  end;

  /// <summary>Gleichnamige, im Nachfahren sichtbare Methoden der Vorfahren, der nächste zuerst.</summary>
  function Candidates(const AChain: TArray<TSymbolLocation>; const AName: string): TArray<TOverrideCandidate>;
  var
    Location: TSymbolLocation;
    Symbol: TIndexSymbol;
    Item: TOverrideCandidate;
  begin
    Result := nil;
    for Location in AChain do
      for Symbol in Ancestry.Methods(Location) do
      begin
        if (AName <> '') and not SameText(Symbol.Name, AName) then
          Continue;
        // strict private sieht kein Nachfahre, private nur einer in derselben Unit.
        if (Symbol.Visibility = TIndexVisibility.StrictPrivate) or ((Location.FileName <> '') and
          (Symbol.Visibility = TIndexVisibility.Private)) then
          Continue;
        if StartsText('class ', Symbol.Signature) then
          Continue;
        Item.TypeName := Location.Symbol.Name;
        Item.Symbol := Symbol;
        if not SplitSignature(Symbol.Signature, Item.Keyword, Item.Head) then
          Continue;
        Result := Result + [Item];
      end;
  end;

  /// <summary>Index des Tokens, das bei AOffset beginnt; -1 ohne.</summary>
  function TokenIndex(AOffset: Integer): Integer;
  var
    Index: Integer;
  begin
    for Index := 0 to High(Tokens) do
      if Tokens[Index].Offset = AOffset then
        Exit(Index);
    Result := -1;
  end;

  /// <summary>Erstes ";" auf Klammertiefe 0 ab dem Token AFrom; -1 ohne.</summary>
  function HeadEnd(AFrom: Integer): Integer;
  var
    Index, Depth: Integer;
  begin
    Depth := 0;
    for Index := AFrom to High(Tokens) do
      if (Tokens[Index].Kind = TPascalTokenKind.Symbol) and ((Tokens[Index].Text = '(') or
        (Tokens[Index].Text = '[')) then
        Inc(Depth)
      else if (Tokens[Index].Kind = TPascalTokenKind.Symbol) and ((Tokens[Index].Text = ')') or
        (Tokens[Index].Text = ']')) then
        Dec(Depth)
      else if (Depth = 0) and (Tokens[Index].Kind = TPascalTokenKind.Symbol) and (Tokens[Index].Text = ';') then
        Exit(Index);
    Result := -1;
  end;

  /// <summary>Kopf des einzigen Rumpfs AClassName.AName: Index des Schlüsselworts; -1 ohne oder bei mehreren.
  /// </summary>
  function BodyStart(const AClassName, AName: string): Integer;
  var
    Index: Integer;
  begin
    Result := -1;
    for Index := 1 to High(Tokens) - 2 do
      if (Tokens[Index].Kind = TPascalTokenKind.Identifier) and SameText(Tokens[Index].Text, AClassName) and
        (Tokens[Index + 1].Text = '.') and SameText(Tokens[Index + 2].Text, AName) and
        (Tokens[Index - 1].Kind = TPascalTokenKind.Keyword) and MatchText(Tokens[Index - 1].Text, ['procedure',
        'function', 'constructor', 'destructor']) then
      begin
        if Result >= 0 then
          Exit(-1);
        Result := Index - 1;
      end;
  end;

  /// <summary>Übernimmt Schlüsselwort und Kopf von ACandidate in Deklaration und, wenn eindeutig, Rumpf.</summary>
  function AdoptFix(const AMethod: TMethodDecl; const ACandidate: TOverrideCandidate; out AFix: TRuleFix): Boolean;
  var
    First, Last, Body, BodyLast: Integer;
    Edits: TArray<TRuleEdit>;
  begin
    AFix := Default(TRuleFix);
    First := TokenIndex(AMethod.Header.StartOffset);
    Result := First >= 0;
    if not Result then
      Exit;
    Last := HeadEnd(First);
    Result := Last > First;
    if not Result then
      Exit;
    Edits := [TRuleEdit.Create(TTextRange.Create(Tokens[First].StartPos, Tokens[Last].StartPos),
      ACandidate.Keyword + ' ' + ACandidate.Head)];
    Body := BodyStart(AMethod.ClassName, AMethod.Symbol.Name);
    if Body > Last then
    begin
      BodyLast := HeadEnd(Body);
      if BodyLast > Body then
        Edits := Edits + [TRuleEdit.Create(TTextRange.Create(Tokens[Body].StartPos, Tokens[BodyLast].StartPos),
          ACandidate.Keyword + ' ' + AMethod.ClassName + '.' + WithoutDefaults(ACandidate.Head))];
    end;
    AFix := TRuleFix.Create(Format('Signatur von %s.%s übernehmen', [ACandidate.TypeName, ACandidate.Symbol.Name]),
      Edits);
  end;

  function OwnHead(const AMethod: TMethodDecl): string;
  var
    Types: TArray<string>;
    Index: Integer;
  begin
    SetLength(Types, Length(AMethod.Symbol.ParamTypes));
    for Index := 0 to High(Types) do
      Types[Index] := AMethod.Symbol.ParamTypes[Index];
    Result := AMethod.Symbol.Name + '(' + string.Join(', ', Types) + ')';
    if AMethod.Symbol.TypeName <> '' then
      Result := Result + ': ' + AMethod.Symbol.TypeName;
  end;

  procedure CheckMethod(const AMethod: TMethodDecl);
  var
    Chain: TArray<TSymbolLocation>;
    Complete, ObjectMissing, Generic: Boolean;
    Found, Virtuals: TArray<TOverrideCandidate>;
    Candidate, Best: TOverrideCandidate;
    Match, BestMatch: TOverrideMatch;
    Certain, BestCertain: Boolean;
    Names: TArray<string>;
    Typo: string;
    Fix: TRuleFix;
    Confidence: TRuleConfidence;
    Fixes: TArray<TRuleFix>;
    Any: Boolean;
  begin
    Chain := Ancestry.Ancestors(AMethod.ClassName, Complete, ObjectMissing);
    Names := Wildcards(AMethod.ClassName, Chain);
    Found := Candidates(Chain, AMethod.Symbol.Name);
    // Die nächste virtuelle Methode mit gleichem Kopf ist das Ziel.
    for Candidate in Found do
      if Candidate.Symbol.IsVirtual and (Compare(AMethod, Candidate, Names) = TOverrideMatch.Same) then
      begin
        if Candidate.Symbol.HasDirective('final') then
          AReport.Add(AMethod.Symbol.SelectionRange, Format('%s.%s ist final und lässt sich nicht überschreiben ' +
            '(wie E2352).', [Candidate.TypeName, Candidate.Symbol.Name]), TRuleConfidence.High);
        Exit;
      end;
    if ObjectMissing and MatchText(AMethod.Symbol.Name, ObjectVirtualNames) then
      Exit;
    if not Complete then
      Exit;
    for Candidate in Found do
      if Compare(AMethod, Candidate, Names) = TOverrideMatch.Same then
      begin
        AReport.Add(AMethod.Symbol.SelectionRange, Format('%s.%s ist nicht virtuell; override braucht virtual ' +
          'oder dynamic im Vorfahren (wie E2170).', [Candidate.TypeName, Candidate.Symbol.Name]),
          TRuleConfidence.High);
        Exit;
      end;
    // Virtuelle Methode gleichen Namens mit anderem Kopf: die ähnlichste der nächsten Stufe.
    Any := False;
    Best := Default(TOverrideCandidate);
    BestMatch := TOverrideMatch.Different;
    BestCertain := True;
    for Candidate in Found do
      if Candidate.Symbol.IsVirtual then
      begin
        Match := CompareTypes(AMethod, Candidate, Names, Certain);
        if not Any or (Match < BestMatch) then
        begin
          Best := Candidate;
          BestMatch := Match;
          BestCertain := Certain;
          Any := True;
        end;
      end;
    Generic := Names <> nil;
    if Any then
    begin
      Confidence := TRuleConfidence.High;
      // Nur andere Typen: sicher nur, wenn keiner ein unbekannter Alias sein kann.
      if (BestMatch = TOverrideMatch.OtherTypes) and not BestCertain then
        Confidence := TRuleConfidence.Medium;
      Fixes := nil;
      if not Generic and AdoptFix(AMethod, Best, Fix) then
        Fixes := [Fix];
      AReport.Add(AMethod.Symbol.SelectionRange, Format('%s hat kein virtuelles %s; dort heißt es %s (wie E2137).',
        [Best.TypeName, OwnHead(AMethod), Best.Head]), Confidence, Fixes);
      Exit;
    end;
    // Kein gleichnamiger Kandidat: Tippfehler im Namen (Destory)?
    Virtuals := nil;
    Names := nil;
    for Candidate in Candidates(Chain, '') do
      if Candidate.Symbol.IsVirtual and (Candidate.Keyword = AMethod.Keyword) then
      begin
        Virtuals := Virtuals + [Candidate];
        Names := Names + [Candidate.Symbol.Name];
      end;
    if ObjectMissing then
      for Typo in ObjectVirtualNames do
        Names := Names + [Typo];
    Typo := TTextFuzzy.Closest(AMethod.Symbol.Name, Names);
    Fixes := nil;
    for Candidate in Virtuals do
      if (Typo <> '') and SameText(Candidate.Symbol.Name, Typo) and not Generic and (Fixes = nil) and
        AdoptFix(AMethod, Candidate, Fix) then
        Fixes := [Fix];
    if (Typo <> '') and (Fixes = nil) and SameText(Typo, 'Destroy') and (AMethod.Keyword = 'destructor') then
    begin
      Candidate := Default(TOverrideCandidate);
      Candidate.TypeName := 'TObject';
      Candidate.Symbol.Name := 'Destroy';
      Candidate.Keyword := 'destructor';
      Candidate.Head := 'Destroy';
      if AdoptFix(AMethod, Candidate, Fix) then
        Fixes := [Fix];
    end;
    if Typo <> '' then
      AReport.Add(AMethod.Symbol.SelectionRange, Format('Kein Vorfahr von %s hat ein virtuelles %s; gemeint ist ' +
        'wohl %s (wie E2137).', [AMethod.ClassName, AMethod.Symbol.Name, Typo]), TRuleConfidence.High, Fixes)
    else
      AReport.Add(AMethod.Symbol.SelectionRange, Format('Kein Vorfahr von %s hat ein virtuelles %s (wie E2137).',
        [AMethod.ClassName, AMethod.Symbol.Name]), TRuleConfidence.High);
  end;

  /// <summary>E2353: Vorfahr mit sealed in der Signatur ("TBasis = class sealed").</summary>
  procedure CheckSealed;
  var
    Symbol: TIndexSymbol;
    Chain: TArray<TSymbolLocation>;
    Complete, ObjectMissing: Boolean;
    Words: TArray<string>;
    Index: Integer;
  begin
    for Symbol in Ancestry.Local.Symbols do
    begin
      if (Symbol.Kind <> TIndexSymbolKind.ClassType) or (Symbol.Container <> '') or (Symbol.Ancestors = nil) then
        Continue;
      Chain := Ancestry.Ancestors(Symbol.Name, Complete, ObjectMissing);
      if Chain = nil then
        Continue;
      Words := LowerCase(Chain[0].Symbol.Signature).Split([' ', '(', ')', '<', '>', '=', ';'],
        TStringSplitOptions.ExcludeEmpty);
      for Index := 0 to High(Words) - 1 do
        if (Words[Index] = 'class') and ((Words[Index + 1] = 'sealed') or ((Words[Index + 1] = 'abstract') and
          (Index + 2 <= High(Words)) and (Words[Index + 2] = 'sealed'))) then
        begin
          AReport.Add(Symbol.SelectionRange, Format('%s ist sealed; davon lässt sich nicht ableiten (wie E2353).',
            [Chain[0].Symbol.Name]), TRuleConfidence.High);
          Break;
        end;
    end;
  end;

var
  Method: TMethodDecl;
begin
  if AContext.Tree = nil then
    Exit;
  Tokens := AContext.Tree.Tokens;
  Cache := TRuleDerived.Open(AContext);
  Ancestry := TAncestry.Create(AContext.Index, TRuleDerived.UnitIndex(Cache, AContext));
  try
    for Method in ClassMethods(AContext, Ancestry) do
      if Method.Has('override') then
        CheckMethod(Method);
    CheckSealed;
  finally
    Ancestry.Free;
  end;
end;

{ TAbstractClassInstantiatedRule }

function TAbstractClassInstantiatedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('abstract-class-instantiated', TRuleSeverity.Warning,
    'Instanz einer Klasse mit abstrakten Methoden');
end;

/// <summary>Steht abstract in der Signatur einer Klasse ("TForm = class abstract(TBasis)")?</summary>
function IsAbstractClass(const ASymbol: TIndexSymbol): Boolean;
var
  Words: TArray<string>;
  Index: Integer;
begin
  Words := LowerCase(ASymbol.Signature).Split([' ', '(', ')', '<', '>', '=', ';'], TStringSplitOptions.ExcludeEmpty);
  for Index := 0 to High(Words) - 1 do
    if (Words[Index] = 'class') and (Words[Index + 1] = 'abstract') then
      Exit(True);
  Result := False;
end;

procedure TAbstractClassInstantiatedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
const
  MaxNamed = 5;
var
  Cache: IRuleDerivedCache;
  Ancestry: TAncestry;
  Tokens: TArray<TPascalToken>;
  Actions: TClassActionContext;

  /// <summary>Abstrakte Methoden von AType und seinen Vorfahren, die keine nähere Stufe neu deklariert.</summary>
  function OpenMethods(const AType: TSymbolLocation; out AOwners: TArray<string>): TArray<TIndexSymbol>;
  var
    Chain: TArray<TSymbolLocation>;
    Location: TSymbolLocation;
    Symbol: TIndexSymbol;
    Seen, Level: TArray<string>;
    Key: string;
    Complete, ObjectMissing: Boolean;
  begin
    Result := nil;
    AOwners := nil;
    Seen := nil;
    Chain := [AType] + Ancestry.Ancestors(AType.Symbol.Name, Complete, ObjectMissing);
    for Location in Chain do
    begin
      Level := nil;
      for Symbol in Ancestry.Methods(Location) do
      begin
        // Überladungen unterscheidet die Zahl der Parameter; gleich viele gelten als dieselbe Methode.
        Key := LowerCase(Symbol.Name) + '/' + IntToStr(Symbol.MaxArgs);
        if Symbol.HasDirective('abstract') and (IndexText(Key, Seen) < 0) then
        begin
          Result := Result + [Symbol];
          AOwners := AOwners + [Location.Symbol.Name];
        end;
        Level := Level + [Key];
      end;
      Seen := Seen + Level;
    end;
  end;

  /// <summary>Klassenname vor ".Create" an Token AIndex (dem Punkt); -1 ohne.</summary>
  function ClassBefore(ADot: Integer): Integer;
  var
    Index, Depth: Integer;
  begin
    Index := ADot - 1;
    // TListe<T>.Create
    if (Index >= 0) and (Tokens[Index].Text = '>') then
    begin
      Depth := 0;
      while Index >= 0 do
      begin
        if Tokens[Index].Text = '>' then
          Inc(Depth)
        else if Tokens[Index].Text = '<' then
        begin
          Dec(Depth);
          if Depth = 0 then
            Break;
        end;
        Dec(Index);
      end;
      Dec(Index);
    end;
    Result := -1;
    if (Index < 0) or (Tokens[Index].Kind <> TPascalTokenKind.Identifier) then
      Exit;
    // constructor TForm.Create: der Kopf eines Rumpfs.
    if (Index > 0) and (Tokens[Index - 1].Kind = TPascalTokenKind.Keyword) and MatchText(Tokens[Index - 1].Text,
      ['constructor', 'procedure', 'function', 'destructor']) then
      Exit;
    Result := Index;
  end;

  procedure CheckCall(AName, ACreate: Integer);
  var
    Location: TSymbolLocation;
    Open: TArray<TIndexSymbol>;
    Owners, Names: TArray<string>;
    Index: Integer;
    Range: TTextRange;
    Fixes: TArray<TRuleFix>;
    Action: TCodeAction;
    Listed: string;
  begin
    if not Ancestry.FindClass(Tokens[AName].Text, Location) then
      Exit;
    Range := TTextRange.Create(Tokens[AName].StartPos, Tokens[ACreate].EndPos);
    if IsAbstractClass(Location.Symbol) then
    begin
      AReport.Add(Range, Format('%s ist als abstract deklariert; davon lässt sich keine Instanz erzeugen ' +
        '(wie E2402).', [Location.Symbol.Name]), TRuleConfidence.High);
      Exit;
    end;
    Open := OpenMethods(Location, Owners);
    if Open = nil then
      Exit;
    Names := nil;
    Fixes := nil;
    for Index := 0 to High(Open) do
    begin
      if Length(Names) < MaxNamed then
        if SameText(Owners[Index], Location.Symbol.Name) then
          Names := Names + [Open[Index].Name]
        else
          Names := Names + [Owners[Index] + '.' + Open[Index].Name];
      // Geerbte abstrakte Methoden einer Klasse dieser Datei: dort überschreiben.
      if (Location.FileName = '') and not SameText(Owners[Index], Location.Symbol.Name) and
        TClassActions.OverrideMethod(AContext.Text, Location.Symbol.Range.StartPos.Line, Open[Index].Name, Actions,
        Action) then
        Fixes := Fixes + [TRuleFix.Create(Format('%s in %s überschreiben', [Open[Index].Name,
          Location.Symbol.Name]), Action.Edits)];
    end;
    for Index := 1 to High(Fixes) do
      Fixes[Index].Alternative := True;
    Listed := string.Join(', ', Names);
    if Length(Open) > MaxNamed then
      Listed := Listed + Format(' und %d weitere', [Length(Open) - MaxNamed]);
    if Length(Open) = 1 then
      AReport.Add(Range, Format('%s hat die abstrakte Methode %s; der Aufruf löst EAbstractError aus (wie W1020).',
        [Location.Symbol.Name, Listed]), TRuleConfidence.High, Fixes)
    else
      AReport.Add(Range, Format('%s hat die abstrakten Methoden %s; ihr Aufruf löst EAbstractError aus ' +
        '(wie W1020).', [Location.Symbol.Name, Listed]), TRuleConfidence.High, Fixes);
  end;

var
  Index, Name: Integer;
begin
  if AContext.Tree = nil then
    Exit;
  Cache := TRuleDerived.Open(AContext);
  Tokens := TRuleDerived.CodeTokens(Cache, AContext);
  Ancestry := TAncestry.Create(AContext.Index, TRuleDerived.UnitIndex(Cache, AContext));
  try
    Actions := TClassActionContext.Default;
    Actions.Index := AContext.Index;
    Actions.Namespaces := AContext.Namespaces;
    Actions.DelphiVersion := AContext.DelphiVersion;
    Actions.Style := AContext.Formatting;
    for Index := 1 to High(Tokens) do
      if (Tokens[Index].Kind = TPascalTokenKind.Identifier) and SameText(Tokens[Index].Text, 'Create') and
        (Tokens[Index - 1].Text = '.') then
      begin
        Name := ClassBefore(Index - 1);
        if Name >= 0 then
          CheckCall(Name, Index);
      end;
  finally
    Ancestry.Free;
  end;
end;

{ TInheritedAbstractCallRule }

function TInheritedAbstractCallRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('inherited-abstract-call', TRuleSeverity.Error,
    'inherited ruft eine abstrakte Methode auf');
end;

class function TInheritedAbstractCallRule.IsAbstractSignature(const ASignature: string): Boolean;
var
  Parts: TArray<string>;
  Index, Depth, Position: Integer;
  Text: string;
begin
  // Parameterliste ausblenden: ein Parameter "abstract: Boolean" wäre keine Direktive.
  Text := '';
  Depth := 0;
  for Position := 1 to Length(ASignature) do
    if ASignature[Position] = '(' then
      Inc(Depth)
    else if ASignature[Position] = ')' then
      Dec(Depth)
    else if Depth = 0 then
      Text := Text + ASignature[Position];
  Parts := Text.Split([';']);
  // Der erste Teil ist der Kopf selbst, die Direktiven folgen hinter Semikolons.
  for Index := 1 to High(Parts) do
    if SameText(Trim(Parts[Index]), 'abstract') then
      Exit(True);
  Result := False;
end;

procedure TInheritedAbstractCallRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Cache: IRuleDerivedCache;
  Tokens: TArray<TPascalToken>;
  Resolver: TNameResolver;
  FileName: string;
  Calls: TDictionary<Integer, TSyntaxNode>;

  /// <summary>Anweisung, die nur aus dem inherited-Aufruf besteht und in einem begin…end steht; sonst nil.
  /// </summary>
  function OwnStatement(AExpr: TSyntaxNode): TSyntaxNode;
  var
    Node: TSyntaxNode;
  begin
    Result := nil;
    Node := AExpr.Parent;
    if (Node <> nil) and (Node.Kind = TSyntaxKind.Call) and (Node.ChildCount > 0) and (Node[0] = AExpr) then
      Node := Node.Parent;
    if (Node <> nil) and (Node.Kind = TSyntaxKind.CallStatement) and (Node.Parent <> nil) and
      (Node.Parent.Kind = TSyntaxKind.Block) then
      Result := Node;
  end;

  /// <summary>Korrektur „Aufruf entfernen“: die Anweisung samt Semikolon, allein auf der Zeile die ganze Zeile.
  /// </summary>
  function RemoveFix(AStatement: TSyntaxNode): TRuleFix;
  var
    StartOffset, EndOffset, LineStart, LineEnd: Integer;
    Text: string;
  begin
    Text := AContext.Text;
    StartOffset := AStatement.StartOffset;
    EndOffset := AStatement.EndOffset;
    while (EndOffset < Length(Text)) and CharInSet(Text[EndOffset + 1], [' ', #9]) do
      Inc(EndOffset);
    if (EndOffset < Length(Text)) and (Text[EndOffset + 1] = ';') then
      Inc(EndOffset)
    else
      EndOffset := AStatement.EndOffset;
    LineStart := StartOffset;
    while (LineStart > 0) and CharInSet(Text[LineStart], [' ', #9]) do
      Dec(LineStart);
    LineEnd := EndOffset;
    while (LineEnd < Length(Text)) and CharInSet(Text[LineEnd + 1], [' ', #9]) do
      Inc(LineEnd);
    // Allein auf der Zeile: die Zeile samt Zeilenumbruch entfernen.
    if ((LineStart = 0) or CharInSet(Text[LineStart], [#10, #13])) and
      ((LineEnd = Length(Text)) or CharInSet(Text[LineEnd + 1], [#10, #13])) then
    begin
      StartOffset := LineStart;
      EndOffset := LineEnd;
      if (EndOffset < Length(Text)) and (Text[EndOffset + 1] = #13) then
        Inc(EndOffset);
      if (EndOffset < Length(Text)) and (Text[EndOffset + 1] = #10) then
        Inc(EndOffset);
    end;
    Result := TRuleFix.Create('Aufruf entfernen', [TRuleEdit.Create(TRuleDerived.OffsetRange(Cache, AContext,
      StartOffset, EndOffset), '')]);
  end;

  procedure CheckCall(AExpr: TSyntaxNode; ANameToken: Integer);
  var
    Candidates: TArray<TResolvedSymbol>;
    Candidate: TResolvedSymbol;
    Statement: TSyntaxNode;
    Fixes: TArray<TRuleFix>;
  begin
    Candidates := Resolver.ResolveAll(AContext.Tree, FileName, Tokens[ANameToken].StartPos);
    if Candidates = nil then
      Exit;
    // Nur wenn jede passende Überladung abstrakt ist; sonst wählt der Compiler womöglich eine andere.
    for Candidate in Candidates do
      if not (Candidate.SymbolKind in [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_]) or
        (Candidate.Condition <> '') or not IsAbstractSignature(Candidate.Signature) then
        Exit;
    Fixes := nil;
    Statement := OwnStatement(AExpr);
    if Statement <> nil then
      Fixes := [RemoveFix(Statement)];
    AReport.Add(TTextRange.Create(AExpr.StartPos, AExpr.EndPos), Format('%s.%s ist abstrakt; der Aufruf über ' +
      'inherited ist nicht erlaubt (wie E2373).', [Candidates[0].Container, Candidates[0].Name]),
      TRuleConfidence.High, Fixes);
  end;

var
  Index: Integer;
  Node: TSyntaxNode;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  Cache := TRuleDerived.Open(AContext);
  Tokens := TRuleDerived.CodeTokens(Cache, AContext);
  Calls := TDictionary<Integer, TSyntaxNode>.Create;
  try
    // inherited mit Namen; ein bloßes inherited; übergeht der Compiler bei abstrakten Methoden still.
    AContext.Tree.Root.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        if (ANode.Kind = TSyntaxKind.InheritedExpr) and (ANode.Name <> '') then
          Calls.AddOrSetValue(ANode.StartOffset, ANode);
        Result := True;
      end);
    if Calls.Count = 0 then
      Exit;
    FileName := AContext.FileName;
    if FileName = '' then
      FileName := AContext.RelativePath;
    if FileName = '' then
      FileName := AContext.UnitName + '.pas';
    Resolver := TNameResolver.Create(AContext.Index, AContext.EnsureUnit);
    try
      Resolver.Namespaces := AContext.Namespaces;
      Resolver.PinTree(AContext.Tree, FileName);
      try
        for Index := 0 to High(Tokens) - 1 do
          if Calls.TryGetValue(Tokens[Index].Offset, Node) and
            (Tokens[Index + 1].Kind = TPascalTokenKind.Identifier) then
            CheckCall(Node, Index + 1);
      finally
        Resolver.UnpinTree;
      end;
    finally
      Resolver.Free;
    end;
  finally
    Calls.Free;
  end;
end;

procedure RegisterInheritanceRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TDestroyWithoutOverrideRule.Create);
  ARegistry.Register(TComponentCreateWithoutOverrideRule.Create);
  ARegistry.Register(THidesVirtualRule.Create);
  ARegistry.Register(TVirtualInsteadOfOverrideRule.Create);
  ARegistry.Register(TShadowedNameRule.Create);
  ARegistry.Register(TOverrideTargetMissingRule.Create);
  ARegistry.Register(TAbstractClassInstantiatedRule.Create);
  ARegistry.Register(TInheritedAbstractCallRule.Create);
end;

end.
