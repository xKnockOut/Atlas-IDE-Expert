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
  cObjectMemberNames: array[0..33] of string = ('Create', 'Destroy', 'Free', 'DisposeOf', 'Disposed', 'ClassName',
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
    /// <summary>Klasse, Record oder object aus dem interface-Teil, zu dem der Rumpf ARoutine gehört; nil
    /// ohne.</summary>
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
  Atlas.Common.Index.Contract,
  Atlas.Common.Rules.Derived;

/// <summary>Typknoten einer Typdeklaration (das erste Kind außer den Typparametern), nil ohne.</summary>
function TypeOfDecl(ADecl: TSyntaxNode): TSyntaxNode;
var
  mIndex: Integer;
begin
  for mIndex := 0 to ADecl.ChildCount - 1 do
  begin
    if ADecl[mIndex].Kind <> TSyntaxKind.GenericParams then
    begin
      Exit(ADecl[mIndex]);
    end;
  end;
  Result := nil;
end;

/// <summary>Namen, die ein Knoten deklariert ("A,B" ergibt beide); leer bei Knoten ohne Deklaration.</summary>
function DeclaredNames(ANode: TSyntaxNode): TArray<string>;
var
  mName: string;
begin
  Result := nil;
  case ANode.Kind of
    TSyntaxKind.Parameter, TSyntaxKind.VarDecl, TSyntaxKind.ConstDecl, TSyntaxKind.TypeDecl, TSyntaxKind.Field,
    TSyntaxKind.PropertyDecl, TSyntaxKind.InlineVar, TSyntaxKind.InlineConst, TSyntaxKind.ForStatement,
    TSyntaxKind.ForInStatement, TSyntaxKind.ExceptionHandler, TSyntaxKind.RoutineHeader:
      for mName in SplitString(ANode.Name, ',') do
      begin
        if Trim(mName) <> '' then
        begin
          Result := Result + [Trim(mName)];
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
  mNames: TArray<string>;
begin
  mNames := nil;
  ANode.Walk(
    function(AChild: TSyntaxNode): Boolean
    begin
      Result := True;
      mNames := mNames + DeclaredNames(AChild);
    end);
  Result := mNames;
end;

/// <summary>Namen, die der Abschnitt ASection auf oberster Ebene deklariert (Typen, Werte der Aufzählungen,
/// Konstanten, Variablen, Routinen ohne Punkt).</summary>
function SectionNames(ASection: TSyntaxNode): TArray<string>;
var
  mIndex, mInner: Integer;
  mChild, mDecl: TSyntaxNode;
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
      TSyntaxKind.TypeSection, TSyntaxKind.ConstSection, TSyntaxKind.VarSection:
        for mInner := 0 to mChild.ChildCount - 1 do
        begin
          mDecl := mChild[mInner];
          Result := Result + DeclaredNames(mDecl);
          if (mDecl.Kind = TSyntaxKind.TypeDecl) and (TypeOfDecl(mDecl) <> nil) and
            (TypeOfDecl(mDecl).Kind = TSyntaxKind.EnumType) then
          begin
            Result := Result + NamesBelow(TypeOfDecl(mDecl));
          end;
        end;
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
  mFound: TSyntaxNode;
begin
  mFound := nil;
  if ASection <> nil then
  begin
    ASection.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        Result := mFound = nil;
        if Result and (ANode.Kind = TSyntaxKind.TypeDecl) and SameText(ANode.Name, AName) and
          (TypeOfDecl(ANode) <> nil) and (TypeOfDecl(ANode).Kind in [TSyntaxKind.ClassType,
          TSyntaxKind.RecordType, TSyntaxKind.ObjectType]) then
        begin
          mFound := ANode;
        end;
      end);
  end;
  Result := mFound;
end;

/// <summary>Letzter Teil eines Namens mit Punkten: "TAussen.TInnen" ergibt "TInnen".</summary>
function LastPart(const AName: string): string;
begin
  Result := Copy(AName, LastDelimiter('.', AName) + 1, MaxInt);
end;

{ TImplementationSymbols }

constructor TImplementationSymbols.Create(const AContext: TRuleContext);
var
  mKnown: TArray<string>;
  mName: string;
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
  mKnown := SectionNames(FInterface);
  for mName in SectionNames(FImplementation) do
  begin
    if not MatchText(mName, mKnown) then
    begin
      FLocal := FLocal + [mName];
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
  mIndex: Integer;
begin
  Result := nil;
  if FLocal = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to FImplementation.ChildCount - 1 do
  begin
    if (FImplementation[mIndex].Kind = TSyntaxKind.RoutineDecl) and
      (FImplementation[mIndex].FindChild(TSyntaxKind.RoutineHeader) <> nil) then
    begin
      Result := Result + [FImplementation[mIndex]];
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
  mOuter: TSyntaxNode;
  mLocation: TSymbolLocation;
  mChain: TArray<TSymbolLocation>;
  mMember: TIndexSymbol;
  mComplete, mObjectMissing: Boolean;
  mName: string;
begin
  ANames := nil;
  mOuter := ADecl;
  while mOuter <> nil do
  begin
    if mOuter.Kind = TSyntaxKind.TypeDecl then
    begin
      ANames := ANames + NamesBelow(mOuter);
    end;
    mOuter := mOuter.Parent;
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
  mChain := FAncestry.Ancestors(ADecl.Name, mComplete, mObjectMissing);
  if not mComplete then
  begin
    Exit;
  end;
  for mLocation in mChain do
  begin
    for mMember in FAncestry.Members(mLocation) do
    begin
      ANames := ANames + [mMember.Name];
    end;
  end;
  for mName in cObjectMemberNames do
  begin
    ANames := ANames + [mName];
  end;
  Result := True;
end;

function TImplementationSymbols.UsesIn(ARoutine, ADecl: TSyntaxNode): TArray<TSyntaxNode>;
var
  mKnown, mUsed: TArray<string>;
  mHeader: TSyntaxNode;
  mCandidates: TList<TSyntaxNode>;
  mCandidate: TSyntaxNode;
begin
  Result := nil;
  mKnown := nil;
  if (FLocal = nil) or ((ADecl <> nil) and not VisibleMembers(ADecl, mKnown)) then
  begin
    Exit;
  end;
  mKnown := mKnown + NamesBelow(ARoutine);
  mHeader := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
  mCandidates := TList<TSyntaxNode>.Create;
  try
    ARoutine.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        Result := not (ANode.Kind in [TSyntaxKind.WithStatement, TSyntaxKind.GenericParams]) and (ANode <> mHeader);
        if Result and (ANode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.TypeReference]) and
          (Pos('.', ANode.Name) = 0) then
        begin
          mCandidates.Add(ANode);
        end;
      end);
    mUsed := nil;
    for mCandidate in mCandidates do
    begin
      if MatchText(mCandidate.Name, FLocal) and not MatchText(mCandidate.Name, mKnown) and
        not MatchText(mCandidate.Name, mUsed) then
      begin
        mUsed := mUsed + [mCandidate.Name];
        Result := Result + [mCandidate];
      end;
    end;
  finally
    mCandidates.Free;
  end;
end;


constructor TDeclarationNames.Create(ARoot: TSyntaxNode);
var
  mNodes: TList<TSyntaxNode>;
  mNode: TSyntaxNode;
  mName: string;
  mIndex: Integer;
begin
  inherited Create;
  FVariables := TObjectDictionary<string, TList<TSyntaxNode>>.Create([doOwnsValues]);
  FOthers := TDictionary<string, Boolean>.Create;
  mNodes := TList<TSyntaxNode>.Create;
  try
    ARoot.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        Result := True;
        mNodes.Add(ANode);
      end);
    for mNode in mNodes do
      case mNode.Kind of
        TSyntaxKind.VarDecl, TSyntaxKind.Field:
          AddNames(mNode.Name, mNode, True);
        TSyntaxKind.RoutineHeader:
          begin
            mName := mNode.Name;
            if LastDelimiter('.', mName) > 0 then
            begin
              mName := Copy(mName, LastDelimiter('.', mName) + 1, MaxInt);
            end;
            // Nur Routinen der Unit selbst gelten als sicher; Methoden und lokale Routinen zählen als andere Art.
            AddNames(mName, mNode, (Pos('.', mNode.Name) = 0) and (mNode.Parent <> nil) and
              (mNode.Parent.Kind = TSyntaxKind.RoutineDecl) and (mNode.Parent.Parent <> nil) and
              (mNode.Parent.Parent.Kind in [TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection]));
          end;
        TSyntaxKind.ConstDecl, TSyntaxKind.TypeDecl, TSyntaxKind.Parameter, TSyntaxKind.PropertyDecl,
        TSyntaxKind.InlineVar, TSyntaxKind.InlineConst, TSyntaxKind.UsedUnit, TSyntaxKind.ForStatement,
        TSyntaxKind.ForInStatement:
          AddNames(mNode.Name, mNode, False);
        TSyntaxKind.EnumType:
          for mIndex := 0 to mNode.ChildCount - 1 do
          begin
            AddOther(mNode[mIndex].Name);
          end;
        TSyntaxKind.GenericParams:
          for mIndex := 0 to mNode.ChildCount - 1 do
          begin
            AddOther(mNode[mIndex].Name);
          end;
      else
        // Übrige Werte bewusst ohne Wirkung.
      end;
  finally
    mNodes.Free;
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
  mList: TList<TSyntaxNode>;
begin
  if not FVariables.TryGetValue(LowerCase(AName), mList) then
  begin
    mList := TList<TSyntaxNode>.Create;
    FVariables.Add(LowerCase(AName), mList);
  end;
  mList.Add(ANode);
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
  mName: string;
begin
  for mName in SplitString(ANames, ',') do
  begin
    if Trim(mName) = '' then
    begin
      Continue;
    end
    else if AVariable then
    begin
      AddVariable(Trim(mName), ANode);
    end
    else
    begin
      AddOther(mName);
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
