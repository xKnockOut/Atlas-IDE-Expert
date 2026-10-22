unit Atlas.Common.Rules.Builtin.Inheritance;

// Klassische Deklarationsfehler bei der Vererbung (#125), alles Varianten von
// W1010, aber schon beim Tippen und mit Korrektur:
//   destroy-without-override            destructor Destroy ohne override
//   component-create-without-override   constructor Create(AOwner: TComponent)
//                                       ohne override in TComponent-Nachfahren
//   hides-virtual                       Methode verdeckt eine virtuelle des Vorfahren
//   virtual-instead-of-override         virtual statt override bei gleicher Signatur
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

procedure RegisterInheritanceRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Rules.Derived;

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

function TAncestry.MethodsOf(const AType: TSymbolLocation; const AName: string): TArray<TIndexSymbol>;
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
    if (Symbol.Kind in [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_]) and
      SameText(Symbol.Container, AType.Symbol.Name) and SameText(Symbol.Name, AName) and
      ContainsLine(AType.Symbol.Range, Symbol.Range.StartPos.Line) then
      Result := Result + [Symbol];
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

procedure RegisterInheritanceRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TDestroyWithoutOverrideRule.Create);
  ARegistry.Register(TComponentCreateWithoutOverrideRule.Create);
  ARegistry.Register(THidesVirtualRule.Create);
  ARegistry.Register(TVirtualInsteadOfOverrideRule.Create);
end;

end.
