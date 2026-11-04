unit Atlas.Common.Rules.Builtin.TypeRestrictions.Symbols;

// Gemeinsame Hilfen der Regeln generic-declaration-invalid, type-restriction-violated, attribute-usage-invalid und
// typeinfo-invalid: Namen der Deklarationen eines Abschnitts, Symbole des implementation-Teils
// (TImplementationSymbols) und Deklarationen der Datei je Name (TDeclarationNames).

interface

uses
  System.Generics.Collections,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.Inheritance;

const
  // Mitglieder von TObject, die im Rumpf einer Methode ohne Self sichtbar sind (E2506).
  ObjectMemberNames: array[0..33] of string = ('Create', 'Destroy', 'Free', 'DisposeOf', 'Disposed', 'ClassName',
    'ClassNameIs', 'ClassType', 'ClassParent', 'ClassInfo', 'InstanceSize', 'InheritsFrom', 'MethodAddress',
    'MethodName', 'FieldAddress', 'GetInterface', 'GetInterfaceEntry', 'GetInterfaceTable', 'Dispatch',
    'DefaultHandler', 'NewInstance', 'FreeInstance', 'InitInstance', 'CleanupInstance', 'AfterConstruction',
    'BeforeDestruction', 'SafeCallException', 'Equals', 'GetHashCode', 'ToString', 'UnitName', 'UnitScope',
    'QualifiedClassName', 'CheckDisposed');

type
  /// <summary>Symbole des implementation-Teils, die Routinen aus dem interface-Teil nicht verwenden dürfen
  /// (E2506, E2441): Typen, Aufzählungswerte, Konstanten, Variablen und Routinen, die dort und nicht im
  /// interface-Teil deklariert sind.</summary>
  TImplementationSymbols = class
  private
    FContext: TRuleContext;
    FInterface: TSyntaxNode;
    FImplementation: TSyntaxNode;
    FLocal: TArray<string>;
    FAncestry: TAncestry;
    function VisibleMembers(ADecl: TSyntaxNode; out ANames: TArray<string>): Boolean;
  public
    constructor Create(const AContext: TRuleContext);
    destructor Destroy; override;
    /// <summary>Rümpfe auf oberster Ebene des implementation-Teils; leer ohne Symbole des Teils.</summary>
    function Routines: TArray<TSyntaxNode>;
    /// <summary>Klasse, Record oder object aus dem interface-Teil, zu dem der Rumpf ARoutine gehört; nil ohne.</summary>
    function OwnerType(ARoutine: TSyntaxNode): TSyntaxNode;
    /// <summary>Erste Verwendung je Symbol des implementation-Teils im Rumpf ARoutine (ohne eigenen Kopf, with
    /// und Typparameter). ADecl ist der Typ der Methode oder nil; leer, wenn dessen Mitglieder samt Vorfahren
    /// nicht sicher bekannt sind.</summary>
    function UsesIn(ARoutine, ADecl: TSyntaxNode): TArray<TSyntaxNode>;
    property InterfacePart: TSyntaxNode read FInterface;
  end;

  /// <summary>Deklarationen der Datei je Name (klein geschrieben): Variablen und Routinen, die in einem
  /// Attributargument nie konstant sind, und alle übrigen Arten (Konstanten, Typen, Werte …).</summary>
  TDeclarationNames = class
  private
    FVariables: TObjectDictionary<string, TList<TSyntaxNode>>;
    FOthers: TDictionary<string, Boolean>;
    procedure AddVariable(const AName: string; ANode: TSyntaxNode);
    procedure AddOther(const AName: string);
    procedure AddNames(const ANames: string; ANode: TSyntaxNode; AVariable: Boolean);
  public
    constructor Create(ARoot: TSyntaxNode);
    destructor Destroy; override;
    /// <summary>Variablen- bzw. Routinen-Deklarationen zu AName, die nur so in der Datei stehen; nil sonst.</summary>
    function OnlyVariables(const AName: string): TList<TSyntaxNode>;
    /// <summary>Deklariert die Datei AName in irgendeiner Art?</summary>
    function Declared(const AName: string): Boolean;
  end;

/// <summary>Typknoten einer Typdeklaration (das erste Kind außer den Typparametern), nil ohne.</summary>
function TypeOfDecl(ADecl: TSyntaxNode): TSyntaxNode;
/// <summary>Namen, die ein Knoten deklariert ("A,B" ergibt beide); leer bei Knoten ohne Deklaration.</summary>
function DeclaredNames(ANode: TSyntaxNode): TArray<string>;
/// <summary>Alle Namen, die unterhalb von ANode deklariert sind.</summary>
function NamesBelow(ANode: TSyntaxNode): TArray<string>;
/// <summary>Namen, die der Abschnitt ASection auf oberster Ebene deklariert (Typen, Werte der Aufzählungen,
/// Konstanten, Variablen, Routinen ohne Punkt).</summary>
function SectionNames(ASection: TSyntaxNode): TArray<string>;
/// <summary>Namen des implementation-Teils, die eine Inline-Routine aus dem interface-Teil verwenden darf: echte
/// Konstanten, Typen samt Aufzählungswerten und Routinen. dcc übersetzt das (mORMot2, Clipper2 in Graphics32; TR1,
/// TR2, TR4, TR8; dcc-Lauf vom 29.10.2026, #1328); E2441 bleibt für Variablen und typisierte Konstanten (TG1,
/// TG4).</summary>
function InlineUsableNames(ASection: TSyntaxNode): TArray<string>;
/// <summary>Erste Typdeklaration AName (Klasse, Record, object) unterhalb von ASection, nil ohne.</summary>
function FindStructDecl(ASection: TSyntaxNode; const AName: string): TSyntaxNode;
/// <summary>Letzter Teil eines Namens mit Punkten: "TAussen.TInnen" ergibt "TInnen".</summary>
function LastPart(const AName: string): string;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Semantics.NameResolver;

/// <summary>Typknoten einer Typdeklaration (das erste Kind außer den Typparametern), nil ohne.</summary>
function TypeOfDecl(ADecl: TSyntaxNode): TSyntaxNode;
var
  Index: Integer;
begin
  for Index := 0 to ADecl.ChildCount - 1 do
  begin
    if ADecl[Index].Kind <> TSyntaxKind.GenericParams then
    begin
      Exit(ADecl[Index]);
    end;
  end;
  Result := nil;
end;

/// <summary>Namen, die ein Knoten deklariert ("A,B" ergibt beide); leer bei Knoten ohne Deklaration.</summary>
function DeclaredNames(ANode: TSyntaxNode): TArray<string>;
var
  Name: string;
begin
  Result := nil;
  case ANode.Kind of
    TSyntaxKind.Parameter, TSyntaxKind.VarDecl, TSyntaxKind.ConstDecl, TSyntaxKind.TypeDecl, TSyntaxKind.Field,
    TSyntaxKind.PropertyDecl, TSyntaxKind.InlineVar, TSyntaxKind.InlineConst, TSyntaxKind.ForStatement,
    TSyntaxKind.ForInStatement, TSyntaxKind.ExceptionHandler, TSyntaxKind.RoutineHeader:
      for Name in SplitString(ANode.Name, ',') do
      begin
        if Trim(Name) <> '' then
        begin
          Result := Result + [Trim(Name)];
        end;
      end;
    TSyntaxKind.Identifier:
      if (ANode.Parent <> nil) and (ANode.Parent.Kind in [TSyntaxKind.GenericParams, TSyntaxKind.EnumType]) then
      begin
        Result := [ANode.Name];
      end;
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

/// <summary>Alle Namen, die unterhalb von ANode deklariert sind.</summary>
function NamesBelow(ANode: TSyntaxNode): TArray<string>;
var
  Names: TArray<string>;
begin
  Names := nil;
  ANode.Walk(
    function(AChild: TSyntaxNode): Boolean
    begin
      Result := True;
      Names := Names + DeclaredNames(AChild);
    end);
  Result := Names;
end;

/// <summary>Namen, die der Abschnitt ASection auf oberster Ebene deklariert (Typen, Werte der Aufzählungen,
/// Konstanten, Variablen, Routinen ohne Punkt).</summary>
function SectionNames(ASection: TSyntaxNode): TArray<string>;
var
  Index, Inner: Integer;
  Child, Decl: TSyntaxNode;
begin
  Result := nil;
  if ASection = nil then
  begin
    Exit;
  end;
  for Index := 0 to ASection.ChildCount - 1 do
  begin
    Child := ASection[Index];
    case Child.Kind of
      TSyntaxKind.TypeSection, TSyntaxKind.ConstSection, TSyntaxKind.VarSection:
        for Inner := 0 to Child.ChildCount - 1 do
        begin
          Decl := Child[Inner];
          Result := Result + DeclaredNames(Decl);
          if (Decl.Kind = TSyntaxKind.TypeDecl) and (TypeOfDecl(Decl) <> nil) and
            (TypeOfDecl(Decl).Kind = TSyntaxKind.EnumType) then
          begin
            Result := Result + NamesBelow(TypeOfDecl(Decl));
          end;
        end;
      TSyntaxKind.RoutineDecl:
        if Pos('.', Child.Name) = 0 then
        begin
          Result := Result + [Child.Name];
        end;
    else
      // Übrige Werte bewusst ohne Wirkung.
    end;
  end;
end;

/// <summary>Namen des implementation-Teils, die eine Inline-Routine aus dem interface-Teil verwenden darf: echte
/// Konstanten, Typen samt Aufzählungswerten und Routinen. dcc übersetzt das (mORMot2, Clipper2 in Graphics32; TR1,
/// TR2, TR4, TR8; dcc-Lauf vom 29.10.2026, #1328); E2441 bleibt für Variablen und typisierte Konstanten (TG1,
/// TG4).</summary>
/// <summary>Namen der echten Konstanten (ohne Typ) eines const-Abschnitts.</summary>
function UntypedConstNames(AConstSection: TSyntaxNode): TArray<string>;
var
  mIndex: Integer;
  mDecl: TSyntaxNode;
begin
  Result := nil;
  for mIndex := 0 to AConstSection.ChildCount - 1 do
  begin
    mDecl := AConstSection[mIndex];
    // Typisierte Konstanten haben Typ und Wert als Kinder.
    if (mDecl.Kind = TSyntaxKind.ConstDecl) and (mDecl.ChildCount < 2) then
    begin
      Result := Result + DeclaredNames(mDecl);
    end;
  end;
end;

/// <summary>Namen der Typen eines type-Abschnitts samt Werten ihrer Aufzählungen.</summary>
function TypeAndEnumNames(ATypeSection: TSyntaxNode): TArray<string>;
var
  mIndex: Integer;
  mDecl, mType: TSyntaxNode;
begin
  Result := nil;
  for mIndex := 0 to ATypeSection.ChildCount - 1 do
  begin
    mDecl := ATypeSection[mIndex];
    if mDecl.Kind <> TSyntaxKind.TypeDecl then
    begin
      Continue;
    end;
    Result := Result + DeclaredNames(mDecl);
    mType := TypeOfDecl(mDecl);
    if (mType <> nil) and (mType.Kind = TSyntaxKind.EnumType) then
    begin
      Result := Result + NamesBelow(mType);
    end;
  end;
end;

function InlineUsableNames(ASection: TSyntaxNode): TArray<string>;
var
  mIndex: Integer;
  mChild: TSyntaxNode;
begin
  Result := nil;
  if ASection = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to ASection.ChildCount - 1 do
  begin
    mChild := ASection[mIndex];
    case mChild.Kind of
      TSyntaxKind.ConstSection:
        Result := Result + UntypedConstNames(mChild);
      TSyntaxKind.TypeSection:
        Result := Result + TypeAndEnumNames(mChild);
      TSyntaxKind.RoutineDecl:
        if Pos('.', mChild.Name) = 0 then
        begin
          Result := Result + [mChild.Name];
        end;
    else
      // Übrige Werte bewusst ohne Wirkung.
    end;
  end;
end;

/// <summary>Erste Typdeklaration AName (Klasse, Record, object) unterhalb von ASection, nil ohne.</summary>
function FindStructDecl(ASection: TSyntaxNode; const AName: string): TSyntaxNode;
var
  Found: TSyntaxNode;
begin
  Found := nil;
  if ASection <> nil then
  begin
    ASection.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        Result := Found = nil;
        if Result and (ANode.Kind = TSyntaxKind.TypeDecl) and SameText(ANode.Name, AName) and
          (TypeOfDecl(ANode) <> nil) and (TypeOfDecl(ANode).Kind in [TSyntaxKind.ClassType,
          TSyntaxKind.RecordType, TSyntaxKind.ObjectType]) then
        begin
          Found := ANode;
        end;
      end);
  end;
  Result := Found;
end;

/// <summary>Letzter Teil eines Namens mit Punkten: "TAussen.TInnen" ergibt "TInnen".</summary>
function LastPart(const AName: string): string;
begin
  Result := Copy(AName, LastDelimiter('.', AName) + 1, MaxInt);
end;

{ TImplementationSymbols }

constructor TImplementationSymbols.Create(const AContext: TRuleContext);
var
  Known: TArray<string>;
  Name: string;
begin
  inherited Create;
  FContext := AContext;
  FInterface := AContext.Tree.Root.FindChild(TSyntaxKind.InterfaceSection);
  FImplementation := AContext.Tree.Root.FindChild(TSyntaxKind.ImplementationSection);
  FLocal := nil;
  if (FInterface = nil) or (FImplementation = nil) then
  begin
    Exit;
  end;
  Known := SectionNames(FInterface);
  for Name in SectionNames(FImplementation) do
  begin
    if not MatchText(Name, Known) then
    begin
      FLocal := FLocal + [Name];
    end;
  end;
end;

destructor TImplementationSymbols.Destroy;
begin
  FAncestry.Free;
  inherited;
end;

function TImplementationSymbols.Routines: TArray<TSyntaxNode>;
var
  Index: Integer;
begin
  Result := nil;
  if FLocal = nil then
  begin
    Exit;
  end;
  for Index := 0 to FImplementation.ChildCount - 1 do
  begin
    if (FImplementation[Index].Kind = TSyntaxKind.RoutineDecl) and
      (FImplementation[Index].FindChild(TSyntaxKind.RoutineHeader) <> nil) then
    begin
      Result := Result + [FImplementation[Index]];
    end;
  end;
end;

function TImplementationSymbols.OwnerType(ARoutine: TSyntaxNode): TSyntaxNode;
begin
  if Pos('.', ARoutine.Name) = 0 then
  begin
    Exit(nil);
  end;
  Result := FindStructDecl(FInterface, LastPart(Copy(ARoutine.Name, 1, LastDelimiter('.', ARoutine.Name) - 1)));
end;

function TImplementationSymbols.VisibleMembers(ADecl: TSyntaxNode; out ANames: TArray<string>): Boolean;
var
  Outer: TSyntaxNode;
  Location: TSymbolLocation;
  Chain: TArray<TSymbolLocation>;
  Member: TIndexSymbol;
  Complete, ObjectMissing: Boolean;
  Name: string;
begin
  ANames := nil;
  Outer := ADecl;
  while Outer <> nil do
  begin
    if Outer.Kind = TSyntaxKind.TypeDecl then
    begin
      ANames := ANames + NamesBelow(Outer);
    end;
    Outer := Outer.Parent;
  end;
  if TypeOfDecl(ADecl).Kind <> TSyntaxKind.ClassType then
  begin
    Exit(True);
  end;
  Result := False;
  if FAncestry = nil then
  begin
    FAncestry := TAncestry.Create(FContext.Index, TRuleDerived.UnitIndex(TRuleDerived.Open(FContext), FContext));
  end;
  Chain := FAncestry.Ancestors(ADecl.Name, Complete, ObjectMissing);
  if not Complete then
  begin
    Exit;
  end;
  for Location in Chain do
  begin
    for Member in FAncestry.Members(Location) do
    begin
      ANames := ANames + [Member.Name];
    end;
  end;
  for Name in ObjectMemberNames do
  begin
    ANames := ANames + [Name];
  end;
  Result := True;
end;

function TImplementationSymbols.UsesIn(ARoutine, ADecl: TSyntaxNode): TArray<TSyntaxNode>;
var
  Known, Used: TArray<string>;
  Header: TSyntaxNode;
  Candidates: TList<TSyntaxNode>;
  Candidate: TSyntaxNode;
begin
  Result := nil;
  Known := nil;
  if (FLocal = nil) or ((ADecl <> nil) and not VisibleMembers(ADecl, Known)) then
  begin
    Exit;
  end;
  Known := Known + NamesBelow(ARoutine);
  Header := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
  Candidates := TList<TSyntaxNode>.Create;
  try
    ARoutine.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        Result := not (ANode.Kind in [TSyntaxKind.WithStatement, TSyntaxKind.GenericParams]) and (ANode <> Header);
        if Result and (ANode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.TypeReference]) and
          (Pos('.', ANode.Name) = 0) then
        begin
          Candidates.Add(ANode);
        end;
      end);
    Used := nil;
    for Candidate in Candidates do
    begin
      if MatchText(Candidate.Name, FLocal) and not MatchText(Candidate.Name, Known) and
        not MatchText(Candidate.Name, Used) then
      begin
        Used := Used + [Candidate.Name];
        Result := Result + [Candidate];
      end;
    end;
  finally
    Candidates.Free;
  end;
end;


constructor TDeclarationNames.Create(ARoot: TSyntaxNode);
var
  Nodes: TList<TSyntaxNode>;
  Node: TSyntaxNode;
  Name: string;
  Index: Integer;
begin
  inherited Create;
  FVariables := TObjectDictionary<string, TList<TSyntaxNode>>.Create([doOwnsValues]);
  FOthers := TDictionary<string, Boolean>.Create;
  Nodes := TList<TSyntaxNode>.Create;
  try
    ARoot.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        Result := True;
        Nodes.Add(ANode);
      end);
    for Node in Nodes do
      case Node.Kind of
        TSyntaxKind.VarDecl, TSyntaxKind.Field:
          AddNames(Node.Name, Node, True);
        TSyntaxKind.RoutineHeader:
          begin
            Name := Node.Name;
            if LastDelimiter('.', Name) > 0 then
            begin
              Name := Copy(Name, LastDelimiter('.', Name) + 1, MaxInt);
            end;
            // Nur Routinen der Unit selbst gelten als sicher; Methoden und lokale Routinen zählen als andere Art.
            AddNames(Name, Node, (Pos('.', Node.Name) = 0) and (Node.Parent <> nil) and
              (Node.Parent.Kind = TSyntaxKind.RoutineDecl) and (Node.Parent.Parent <> nil) and
              (Node.Parent.Parent.Kind in [TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection]));
          end;
        TSyntaxKind.ConstDecl, TSyntaxKind.TypeDecl, TSyntaxKind.Parameter, TSyntaxKind.PropertyDecl,
        TSyntaxKind.InlineVar, TSyntaxKind.InlineConst, TSyntaxKind.UsedUnit, TSyntaxKind.ForStatement,
        TSyntaxKind.ForInStatement:
          AddNames(Node.Name, Node, False);
        TSyntaxKind.EnumType:
          for Index := 0 to Node.ChildCount - 1 do
          begin
            AddOther(Node[Index].Name);
          end;
        TSyntaxKind.GenericParams:
          for Index := 0 to Node.ChildCount - 1 do
          begin
            AddOther(Node[Index].Name);
          end;
      else
        // Übrige Werte bewusst ohne Wirkung.
      end;
  finally
    Nodes.Free;
  end;
end;

destructor TDeclarationNames.Destroy;
begin
  FVariables.Free;
  FOthers.Free;
  inherited;
end;

procedure TDeclarationNames.AddVariable(const AName: string; ANode: TSyntaxNode);
var
  List: TList<TSyntaxNode>;
begin
  if not FVariables.TryGetValue(LowerCase(AName), List) then
  begin
    List := TList<TSyntaxNode>.Create;
    FVariables.Add(LowerCase(AName), List);
  end;
  List.Add(ANode);
end;

procedure TDeclarationNames.AddOther(const AName: string);
begin
  if Trim(AName) <> '' then
  begin
    FOthers.AddOrSetValue(LowerCase(Trim(AName)), True);
  end;
end;

procedure TDeclarationNames.AddNames(const ANames: string; ANode: TSyntaxNode; AVariable: Boolean);
var
  Name: string;
begin
  for Name in SplitString(ANames, ',') do
  begin
    if Trim(Name) = '' then
    begin
      Continue;
    end
    else if AVariable then
    begin
      AddVariable(Trim(Name), ANode);
    end
    else
    begin
      AddOther(Name);
    end;
  end;
end;

function TDeclarationNames.Declared(const AName: string): Boolean;
begin
  Result := FOthers.ContainsKey(LowerCase(AName)) or FVariables.ContainsKey(LowerCase(AName));
end;

function TDeclarationNames.OnlyVariables(const AName: string): TList<TSyntaxNode>;
begin
  Result := nil;
  if FOthers.ContainsKey(LowerCase(AName)) then
  begin
    Exit;
  end;
  FVariables.TryGetValue(LowerCase(AName), Result);
end;

end.
