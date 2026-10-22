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
  Atlas.Common.Rules.Builtin.Unused;

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

procedure RegisterInheritanceRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TDestroyWithoutOverrideRule.Create);
  ARegistry.Register(TComponentCreateWithoutOverrideRule.Create);
  ARegistry.Register(THidesVirtualRule.Create);
  ARegistry.Register(TVirtualInsteadOfOverrideRule.Create);
  ARegistry.Register(TShadowedNameRule.Create);
end;

end.
