unit Atlas.Common.Rules.Builtin.Inheritance.Constructors;

// Prüfregel virtual-call-in-constructor (Teil von Atlas.Common.Rules.Builtin.Inheritance, dort registriert): Ein
// Konstruktor ruft eine virtuelle oder dynamische Methode von Self auf (direkt, über nicht virtuelle eigene Methoden
// oder eingebettete Routinen), und ein Nachfahr überschreibt sie so, dass die Überschreibung ein eigenes Feld liest,
// das sein Konstruktor erst nach inherited setzt. Die Überschreibung läuft dann, bevor das Feld steht. Nachfahren
// kommen aus der Unit und über den Index aus anderen Units (deren Rümpfe über ReadFile). Ohne Index meldet die Regel
// nur einen Hinweis mit niedriger Konfidenz, wenn der Aufruf vor inherited steht.

interface

uses
  Atlas.Common.Rules.Contract;

type
  TVirtualCallInConstructorRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Index.Contract,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.Builtin.Inheritance.Ancestry,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen.</summary>
  TConstructorsText = (Title, ReadsField, ViaHelper, BeforeInherited, JumpToOverride);

const
  cTexts: array[TConstructorsText] of TAtlasText = (
    (De: 'Virtuelle Methode im Konstruktor aufgerufen'; En: 'Virtual method called in a constructor'),
    (De: '%s ist virtuell; %s.%s liest %s, das erst nach inherited %s gesetzt wird.';
     En: '%s is virtual; %s.%s reads %s, which is only set after inherited %s.'),
    (De: '%s ruft die virtuelle Methode %s auf; %s.%s liest %s, das erst nach inherited %s gesetzt wird.';
     En: '%s calls the virtual method %s; %s.%s reads %s, which is only set after inherited %s.'),
    (De: '%s ist virtuell und läuft vor inherited; eine Überschreibung sieht die Felder ihrer Klasse noch nicht ' +
       'gesetzt.';
     En: '%s is virtual and runs before inherited; an override does not see the fields of its class set yet.'),
    (De: 'Zur Überschreibung %s.%s springen'; En: 'Go to the override %s.%s'));

{$SCOPEDENUMS OFF}

const
  // Tiefe der Kette über nicht virtuelle Methoden und eingebettete Routinen.
  cMaxDepth = 4;
  // Obergrenzen für Nachfahren und nachgeladene Units je Lauf.
  cMaxDescendants = 64;
  cMaxLoadedUnits = 16;

type
  /// <summary>Eine Unit mit Baum und Symbolen: die geprüfte oder eine über den Index nachgeladene.</summary>
  TConstructorUnit = class
  public
    Tree: TSyntaxTree;
    OwnsTree: Boolean;
    Local: Boolean;
    Symbols: TArray<TIndexSymbol>;
    destructor Destroy; override;
    function MemberSymbols(const AClass: string; AKind: TIndexSymbolKind): TArray<TIndexSymbol>;
    function Body(const AQualifiedName: string): TSyntaxNode;
  end;

  /// <summary>Ein Nachfahr der Klasse mit der Unit, in der er steht.</summary>
  TDescendant = record
    ClassName: string;
    UnitData: TConstructorUnit;
  end;

  /// <summary>Gefundener Fall: Nachfahr, Überschreibung, gelesenes Feld, Name des geerbten Konstruktors.</summary>
  TFieldRead = record
    Found: Boolean;
    ClassName: string;
    FieldName: string;
    InheritedName: string;
    Override_: TSyntaxNode;
    Local: Boolean;
  end;

  /// <summary>Stand der Kette eines Konstruktors: geprüfte Klasse, Routine (Konstruktor oder eingebettete bzw.
  /// nicht virtuelle Methode), Offset von inherited, Tiefe, erste Hilfsroutine und oberster Aufruf.</summary>
  TCallChain = record
    ClassName: string;
    Routine: TSyntaxNode;
    InheritedOffset: Integer;
    Depth: Integer;
    Helper: string;
    TopCall: TSyntaxNode;
    function Deeper(ARoutine: TSyntaxNode; const AName: string; ATopCall: TSyntaxNode): TCallChain;
  end;

  /// <summary>Ein Lauf von TVirtualCallInConstructorRule über eine Unit.</summary>
  TConstructorScan = class
  private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FAncestry: TAncestry;
    FLocal: TConstructorUnit;
    FUnits: TObjectDictionary<string, TConstructorUnit>;
    FDescendants: TDictionary<string, TArray<TDescendant>>;
    // Gemeldete Aufrufe (Offset und Name) und geprüfte Konstruktorrümpfe (#Offset).
    FReported: TDictionary<string, Boolean>;
    function FindMethod(const AClass, AName: string; out AMethod: TIndexSymbol): Boolean;
    function LoadUnit(const AFileName: string): TConstructorUnit;
    function LocalDescendants(const AClass: string): TArray<TDescendant>;
    function InCheckedUnit(const ALocation: TSymbolLocation): Boolean;
    procedure AddForeign(const ALocation: TSymbolLocation; var ADescendants: TArray<TDescendant>);
    procedure AddIndexDescendants(const AClass: string; var ADescendants: TArray<TDescendant>);
    function DescendantsOf(const AClass: string): TArray<TDescendant>;
    function FindFieldRead(const AClass, AMethod: string): TFieldRead;
    function CheckOverride(const ADescendant: TDescendant; const AMethod: string): TFieldRead;
    procedure Visit(const AChain: TCallChain; ABody: TSyntaxNode);
    procedure FollowBody(const AChain: TCallChain; ARoutine: TSyntaxNode; const AName: string; ATopCall: TSyntaxNode);
    function IsLocalName(const AChain: TCallChain; const AName: string; ATopCall: TSyntaxNode): Boolean;
    procedure CheckVirtual(const AChain: TCallChain; const AName: string; ATopCall: TSyntaxNode);
    procedure CheckCall(const AChain: TCallChain; ACallee: TSyntaxNode);
    procedure Report(const AMethod, AHelper: string; ATopCall: TSyntaxNode; const ARead: TFieldRead);
    procedure CheckConstructor(const AClass: string; AConstructor: TSyntaxNode);
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    destructor Destroy; override;
    procedure Run;
  end;

function HasDirective(const ASymbol: TIndexSymbol; const ADirective: string): Boolean;
var
  mDirective: string;
begin
  Result := False;
  for mDirective in ASymbol.Directives do
  begin
    Result := Result or SameText(mDirective, ADirective);
  end;
end;

// Der Rumpf einer Routine (Block), nil ohne.
function BlockOf(ARoutine: TSyntaxNode): TSyntaxNode;
begin
  Result := nil;
  if ARoutine <> nil then
  begin
    Result := ARoutine.FindChild(TSyntaxKind.Block);
  end;
end;

// Name des gerufenen Mitglieds von Self an ACallee (M bzw. Self.M), sonst ''.
function SelfMember(ACallee: TSyntaxNode): string;
begin
  Result := '';
  if ACallee.Kind = TSyntaxKind.Identifier then
  begin
    Result := ACallee.Name;
  end
  else if (ACallee.Kind = TSyntaxKind.MemberAccess) and (ACallee.ChildCount > 0) and
    (ACallee[0].Kind = TSyntaxKind.Identifier) and SameText(ACallee[0].Name, 'Self') then
  begin
    Result := ACallee.Name;
  end;
end;

// Offset des ersten geerbten Aufrufs im Rumpf (ohne eingebettete Routinen und anonyme Methoden); MaxInt ohne.
function InheritedOffset(ABody: TSyntaxNode; out AName: string): Integer;
var
  mFound: TSyntaxNode;
begin
  Result := MaxInt;
  AName := '';
  if ABody = nil then
  begin
    Exit;
  end;
  mFound := ABody.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if ANode.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod] then
      begin
        Result := TSyntaxSearchStep.Skip;
      end
      else if ANode.Kind = TSyntaxKind.InheritedExpr then
      begin
        Result := TSyntaxSearchStep.Found;
      end;
    end);
  if mFound <> nil then
  begin
    Result := mFound.StartOffset;
    AName := mFound.Name;
  end;
end;

// Name des Felds an ANode (F oder Self.F), sonst ''.
function FieldAt(ANode: TSyntaxNode): string;
begin
  Result := '';
  if ANode.Kind = TSyntaxKind.Identifier then
  begin
    Result := ANode.Name;
  end
  else if (ANode.Kind = TSyntaxKind.MemberAccess) and (ANode.ChildCount > 0) and
    (ANode[0].Kind = TSyntaxKind.Identifier) and SameText(ANode[0].Name, 'Self') then
  begin
    Result := ANode.Name;
  end;
end;

function IsNilNode(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.Literal]) and SameText(ANode.Name, 'nil');
end;

// Assigned(AField)?
function IsAssignedOf(ANode: TSyntaxNode; const AField: string): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount = 2) and (ANode[0].Kind = TSyntaxKind.Identifier) and
    SameText(ANode[0].Name, 'Assigned') and SameText(FieldAt(ANode[1]), AField);
end;

function ComparesWithNil(AField, ANil: TSyntaxNode; const AName: string): Boolean;
begin
  Result := SameText(FieldAt(AField), AName) and IsNilNode(ANil);
end;

// AField = nil, AField <> nil (auch nil links)?
function IsNilComparison(ANode: TSyntaxNode; const AField: string): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.BinaryExpr) and ((ANode.Name = '=') or (ANode.Name = '<>')) and
    (ANode.ChildCount = 2);
  if Result then
  begin
    Result := ComparesWithNil(ANode[0], ANode[1], AField) or ComparesWithNil(ANode[1], ANode[0], AField);
  end;
end;

// Prüft der Rumpf das Feld auf nil (Assigned(F), F <> nil, F = nil)?
function ChecksNil(ABody: TSyntaxNode; const AField: string): Boolean;
begin
  Result := ABody.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if IsAssignedOf(ANode, AField) or IsNilComparison(ANode, AField) then
      begin
        Result := TSyntaxSearchStep.Found;
      end;
    end) <> nil;
end;

// Ist ANode ein Bezeichner rechts in X.Name (also nicht das Feld von Self)?
function IsMemberNameOfOther(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.Identifier) and (ANode.Parent <> nil) and
    (ANode.Parent.Kind = TSyntaxKind.MemberAccess) and (ANode.Parent[0] <> ANode);
end;

// Steht das Feld an ANode nur als Ziel einer Zuweisung oder in FreeAndNil(F) bzw. F.Free?
function IsWriteOrFree(ANode: TSyntaxNode): Boolean;
var
  mParent: TSyntaxNode;
begin
  mParent := ANode.Parent;
  if mParent = nil then
  begin
    Exit(False);
  end;
  if mParent.Kind = TSyntaxKind.AssignStatement then
  begin
    Exit(mParent[0] = ANode);
  end;
  if mParent.Kind = TSyntaxKind.Call then
  begin
    Exit((mParent[0].Kind = TSyntaxKind.Identifier) and SameText(mParent[0].Name, 'FreeAndNil'));
  end;
  Result := (mParent.Kind = TSyntaxKind.MemberAccess) and SameText(mParent.Name, 'Free');
end;

// Liest der Rumpf das Feld (nicht nur als Ziel einer Zuweisung oder in FreeAndNil bzw. F.Free)?
function ReadsField(ABody: TSyntaxNode; const AField: string): Boolean;
begin
  Result := ABody.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if ANode.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod] then
      begin
        Result := TSyntaxSearchStep.Skip;
      end
      else if SameText(FieldAt(ANode), AField) and not IsMemberNameOfOther(ANode) then
      begin
        if IsWriteOrFree(ANode) then
        begin
          Result := TSyntaxSearchStep.Skip;
        end
        else
        begin
          Result := TSyntaxSearchStep.Found;
        end;
      end;
    end) <> nil;
end;

// Weist der Rumpf das Feld nach AAfter zu (F := … bzw. Self.F := …)?
function AssignsFieldAfter(ABody: TSyntaxNode; const AField: string; AAfter: Integer): Boolean;
begin
  Result := ABody.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if ANode.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod] then
      begin
        Result := TSyntaxSearchStep.Skip;
      end
      else if (ANode.Kind = TSyntaxKind.AssignStatement) and (ANode.ChildCount = 2) and
        (ANode.StartOffset > AAfter) and SameText(FieldAt(ANode[0]), AField) then
      begin
        Result := TSyntaxSearchStep.Found;
      end;
    end) <> nil;
end;

// Lokale Namen einer Routine (Variablen, Konstanten, Parameter), die ein Feld verdecken.
function DeclaresLocal(ARoutine: TSyntaxNode; const AName: string): Boolean;
begin
  Result := ARoutine.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    var
      mName: string;
    begin
      Result := TSyntaxSearchStep.Descend;
      if (ANode <> ARoutine) and (ANode.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod]) then
      begin
        Exit(TSyntaxSearchStep.Skip);
      end;
      if ANode.Kind in [TSyntaxKind.VarDecl, TSyntaxKind.InlineVar, TSyntaxKind.Parameter, TSyntaxKind.ConstDecl] then
      begin
        for mName in SplitString(ANode.Name, ',') do
        begin
          if SameText(Trim(mName), AName) then
          begin
            Exit(TSyntaxSearchStep.Found);
          end;
        end;
      end;
    end) <> nil;
end;

// Eingebettete Routine AName von ARoutine, nil ohne.
function NestedRoutine(ARoutine: TSyntaxNode; const AName: string): TSyntaxNode;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to ARoutine.ChildCount - 1 do
  begin
    if (ARoutine[mIndex].Kind = TSyntaxKind.RoutineDecl) and SameText(ARoutine[mIndex].Name, AName) then
    begin
      Exit(ARoutine[mIndex]);
    end;
  end;
end;

// Überschreibt der Nachfahr AMethod (override)?
function OverridesMethod(const ADescendant: TDescendant; const AMethod: string): Boolean;
var
  mSymbol: TIndexSymbol;
begin
  Result := False;
  for mSymbol in ADescendant.UnitData.MemberSymbols(ADescendant.ClassName, TIndexSymbolKind.Method) do
  begin
    Result := Result or (SameText(mSymbol.Name, AMethod) and HasDirective(mSymbol, 'override'));
  end;
end;

// Setzt ein Konstruktor des Nachfahren das Feld erst nach inherited? AInherited: Name des geerbten Konstruktors.
function SetAfterInherited(const ADescendant: TDescendant; const AField: string; out AInherited: string): Boolean;
var
  mConstructor: TIndexSymbol;
  mBody: TSyntaxNode;
  mAfter: Integer;
begin
  AInherited := '';
  for mConstructor in ADescendant.UnitData.MemberSymbols(ADescendant.ClassName, TIndexSymbolKind.Constructor_) do
  begin
    mBody := nil;
    if not StartsText('class ', mConstructor.Signature) then
    begin
      mBody := BlockOf(ADescendant.UnitData.Body(ADescendant.ClassName + '.' + mConstructor.Name));
    end;
    if mBody = nil then
    begin
      Continue;
    end;
    mAfter := InheritedOffset(mBody, AInherited);
    if (mAfter < MaxInt) and AssignsFieldAfter(mBody, AField, mAfter) then
    begin
      if AInherited = '' then
      begin
        AInherited := mConstructor.Name;
      end;
      Exit(True);
    end;
  end;
  Result := False;
end;

{ TCallChain }

function TCallChain.Deeper(ARoutine: TSyntaxNode; const AName: string; ATopCall: TSyntaxNode): TCallChain;
begin
  Result := Self;
  Result.Routine := ARoutine;
  Result.Depth := Depth + 1;
  if Result.Helper = '' then
  begin
    Result.Helper := AName;
  end;
  Result.TopCall := ATopCall;
end;

{ TConstructorUnit }

destructor TConstructorUnit.Destroy;
begin
  if OwnsTree then
  begin
    Tree.Free;
  end;
  Symbols := nil;
  inherited;
end;

function TConstructorUnit.MemberSymbols(const AClass: string; AKind: TIndexSymbolKind): TArray<TIndexSymbol>;
var
  mSymbol: TIndexSymbol;
begin
  Result := nil;
  for mSymbol in Symbols do
  begin
    if (mSymbol.Kind = AKind) and SameText(mSymbol.Container, AClass) then
    begin
      Result := Result + [mSymbol];
    end;
  end;
end;

function TConstructorUnit.Body(const AQualifiedName: string): TSyntaxNode;
begin
  Result := nil;
  if (Tree = nil) or (Tree.Root = nil) then
  begin
    Exit;
  end;
  Result := Tree.Root.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if ANode.Kind = TSyntaxKind.RoutineDecl then
      begin
        if SameText(ANode.Name, AQualifiedName) and (BlockOf(ANode) <> nil) then
        begin
          Result := TSyntaxSearchStep.Found;
        end
        else
        begin
          Result := TSyntaxSearchStep.Skip;
        end;
      end;
    end);
end;

{ TConstructorScan }

constructor TConstructorScan.Create(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mCache: IRuleDerivedCache;
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
  mCache := TRuleDerived.Open(FContext);
  FAncestry := TAncestry.Create(FContext.Index, TRuleDerived.UnitIndex(mCache, FContext));
  FUnits := TObjectDictionary<string, TConstructorUnit>.Create([doOwnsValues]);
  FDescendants := TDictionary<string, TArray<TDescendant>>.Create;
  FReported := TDictionary<string, Boolean>.Create;
  FLocal := TConstructorUnit.Create;
  FLocal.Tree := FContext.Tree;
  FLocal.Local := True;
  FLocal.Symbols := FAncestry.Local.Symbols;
end;

destructor TConstructorScan.Destroy;
begin
  FReported.Free;
  FDescendants.Free;
  FUnits.Free;
  FLocal.Free;
  FAncestry.Free;
  inherited;
end;

// Methode AName der Klasse oder ihres nächsten Vorfahren, der sie deklariert (Datei, dann Index).
function TConstructorScan.FindMethod(const AClass, AName: string; out AMethod: TIndexSymbol): Boolean;
var
  mName: string;
  mLocation: TSymbolLocation;
  mSymbol: TIndexSymbol;
  mDepth: Integer;
begin
  AMethod := Default(TIndexSymbol);
  mName := AClass;
  for mDepth := 0 to 31 do
  begin
    if (mName = '') or not FAncestry.FindAnyType(mName, mLocation) then
    begin
      Exit(False);
    end;
    for mSymbol in FAncestry.Methods(mLocation) do
    begin
      if SameText(mSymbol.Name, AName) then
      begin
        AMethod := mSymbol;
        Exit(True);
      end;
    end;
    mName := FAncestry.ParentOf(mName);
    if SameText(mName, mLocation.Symbol.Name) then
    begin
      Exit(False);
    end;
  end;
  Result := False;
end;

// Unit eines Nachfahren aus einer anderen Datei: Symbole aus dem Index, Baum über ReadFile; nil, wenn sie sich
// nicht lesen lässt.
function TConstructorScan.LoadUnit(const AFileName: string): TConstructorUnit;
var
  mIndexUnit: TUnitIndex;
  mBytes: TBytes;
  mFormat: TFileFormat;
  mKey: string;
begin
  mKey := AnsiLowerCase(AFileName);
  if FUnits.TryGetValue(mKey, Result) then
  begin
    Exit;
  end;
  Result := nil;
  if (FUnits.Count < cMaxLoadedUnits) and Assigned(FContext.ReadFile) and FContext.Index.FindFile(AFileName,
    mIndexUnit) and FContext.ReadFile(AFileName, mBytes) then
  begin
    Result := TConstructorUnit.Create;
    Result.Symbols := mIndexUnit.Symbols;
    Result.Tree := TSyntaxTreeCache.Parse(TFileEncoding.Decode(mBytes, mFormat));
    Result.OwnsTree := True;
  end;
  FUnits.Add(mKey, Result);
end;

// Nachfahren der Klasse in der geprüften Unit.
function TConstructorScan.LocalDescendants(const AClass: string): TArray<TDescendant>;
var
  mSymbol: TIndexSymbol;
  mDescendant: TDescendant;
begin
  Result := nil;
  for mSymbol in FLocal.Symbols do
  begin
    if (mSymbol.Kind = TIndexSymbolKind.ClassType) and not SameText(mSymbol.Name, AClass) and
      (Length(Result) < cMaxDescendants) and FAncestry.DescendsFrom(mSymbol.Name, AClass) then
    begin
      mDescendant.ClassName := mSymbol.Name;
      mDescendant.UnitData := FLocal;
      Result := Result + [mDescendant];
    end;
  end;
end;

// Steht der Fund des Index in der geprüften Unit? Deren Nachfahren kommen schon aus ihrem Baum.
function TConstructorScan.InCheckedUnit(const ALocation: TSymbolLocation): Boolean;
begin
  Result := SameText(ALocation.UnitName, FAncestry.Local.UnitName) or ((FContext.FileName <> '') and
    SameText(ALocation.FileName, FContext.FileName));
end;

// Nachfahr aus einer anderen Unit anhängen, wenn sie sich lesen lässt.
procedure TConstructorScan.AddForeign(const ALocation: TSymbolLocation; var ADescendants: TArray<TDescendant>);
var
  mDescendant: TDescendant;
begin
  if InCheckedUnit(ALocation) then
  begin
    Exit;
  end;
  mDescendant.ClassName := ALocation.Symbol.Name;
  mDescendant.UnitData := LoadUnit(ALocation.FileName);
  if mDescendant.UnitData <> nil then
  begin
    ADescendants := ADescendants + [mDescendant];
  end;
end;

// Nachfahren über den Index (Breitensuche über alle Stufen).
procedure TConstructorScan.AddIndexDescendants(const AClass: string; var ADescendants: TArray<TDescendant>);
var
  mPending: TQueue<string>;
  mSeen: TDictionary<string, Boolean>;
  mLocation: TSymbolLocation;
begin
  if FContext.Index = nil then
  begin
    Exit;
  end;
  mPending := TQueue<string>.Create;
  mSeen := TDictionary<string, Boolean>.Create;
  try
    mPending.Enqueue(AClass);
    mSeen.Add(AnsiUpperCase(AClass), True);
    while (mPending.Count > 0) and (Length(ADescendants) < cMaxDescendants) do
    begin
      for mLocation in FContext.Index.Descendants(mPending.Dequeue) do
      begin
        if not mSeen.ContainsKey(AnsiUpperCase(mLocation.Symbol.Name)) then
        begin
          mSeen.Add(AnsiUpperCase(mLocation.Symbol.Name), True);
          mPending.Enqueue(mLocation.Symbol.Name);
          AddForeign(mLocation, ADescendants);
        end;
      end;
    end;
  finally
    mSeen.Free;
    mPending.Free;
  end;
end;

// Alle Nachfahren der Klasse (auch über mehrere Stufen): aus der Unit und über den Index aus anderen Units.
function TConstructorScan.DescendantsOf(const AClass: string): TArray<TDescendant>;
begin
  if FDescendants.TryGetValue(AnsiUpperCase(AClass), Result) then
  begin
    Exit;
  end;
  Result := LocalDescendants(AClass);
  AddIndexDescendants(AClass, Result);
  FDescendants.Add(AnsiUpperCase(AClass), Result);
end;

// Überschreibt der Nachfahr AMethod und liest dort ein eigenes Feld, das sein Konstruktor erst nach inherited setzt?
function TConstructorScan.CheckOverride(const ADescendant: TDescendant; const AMethod: string): TFieldRead;
var
  mField: TIndexSymbol;
  mOverride, mBody: TSyntaxNode;
  mInherited: string;
begin
  Result := Default(TFieldRead);
  if not OverridesMethod(ADescendant, AMethod) then
  begin
    Exit;
  end;
  mOverride := ADescendant.UnitData.Body(ADescendant.ClassName + '.' + AMethod);
  mBody := BlockOf(mOverride);
  if mBody = nil then
  begin
    Exit;
  end;
  for mField in ADescendant.UnitData.MemberSymbols(ADescendant.ClassName, TIndexSymbolKind.Field) do
  begin
    if not DeclaresLocal(mOverride, mField.Name) and not ChecksNil(mBody, mField.Name) and
      ReadsField(mBody, mField.Name) and SetAfterInherited(ADescendant, mField.Name, mInherited) then
    begin
      Result.Found := True;
      Result.ClassName := ADescendant.ClassName;
      Result.FieldName := mField.Name;
      Result.InheritedName := mInherited;
      Result.Override_ := mOverride;
      Result.Local := ADescendant.UnitData.Local;
      Exit;
    end;
  end;
end;

function TConstructorScan.FindFieldRead(const AClass, AMethod: string): TFieldRead;
var
  mDescendant: TDescendant;
begin
  Result := Default(TFieldRead);
  for mDescendant in DescendantsOf(AClass) do
  begin
    Result := CheckOverride(mDescendant, AMethod);
    if Result.Found then
    begin
      Exit;
    end;
  end;
end;

procedure TConstructorScan.Report(const AMethod, AHelper: string; ATopCall: TSyntaxNode; const ARead: TFieldRead);
var
  mMessage: string;
  mFixes: TArray<TRuleFix>;
begin
  if AHelper = '' then
  begin
    mMessage := cTexts[TConstructorsText.ReadsField].Fmt([AMethod, ARead.ClassName, AMethod, ARead.FieldName,
      ARead.InheritedName]);
  end
  else
  begin
    mMessage := cTexts[TConstructorsText.ViaHelper].Fmt([AHelper, AMethod, ARead.ClassName, AMethod,
      ARead.FieldName, ARead.InheritedName]);
  end;
  mFixes := nil;
  if ARead.Local then
  begin
    SetLength(mFixes, 1);
    mFixes[0] := TRuleFix.Jump(cTexts[TConstructorsText.JumpToOverride].Fmt([ARead.ClassName, AMethod]),
      ARead.Override_.StartPos);
  end;
  FReport.Add(TTextRange.Create(ATopCall.StartPos, ATopCall.EndPos), mMessage, TRuleConfidence.Medium, mFixes);
end;

// Der Kette in den Rumpf einer eingebetteten oder nicht virtuellen eigenen Methode folgen (bis cMaxDepth).
procedure TConstructorScan.FollowBody(const AChain: TCallChain; ARoutine: TSyntaxNode; const AName: string;
  ATopCall: TSyntaxNode);
begin
  if (ARoutine <> nil) and (AChain.Depth < cMaxDepth) then
  begin
    Visit(AChain.Deeper(ARoutine, AName, ATopCall), BlockOf(ARoutine));
  end;
end;

// Ist AName (ohne Self) eine eingebettete Routine (der dann gefolgt wird) oder ein lokaler Name der Routine?
function TConstructorScan.IsLocalName(const AChain: TCallChain; const AName: string; ATopCall: TSyntaxNode): Boolean;
var
  mNested: TSyntaxNode;
begin
  mNested := NestedRoutine(AChain.Routine, AName);
  if mNested <> nil then
  begin
    FollowBody(AChain, mNested, AName, ATopCall);
    Exit(True);
  end;
  Result := DeclaresLocal(AChain.Routine, AName);
end;

// Aufruf einer virtuellen Methode: melden, wenn ein Nachfahr in der Überschreibung ein noch ungesetztes Feld liest.
procedure TConstructorScan.CheckVirtual(const AChain: TCallChain; const AName: string; ATopCall: TSyntaxNode);
var
  mKey: string;
  mRead: TFieldRead;
begin
  mKey := IntToStr(ATopCall.StartOffset) + #0 + AnsiUpperCase(AName);
  if FReported.ContainsKey(mKey) then
  begin
    Exit;
  end;
  FReported.Add(mKey, True);
  mRead := FindFieldRead(AChain.ClassName, AName);
  if mRead.Found then
  begin
    Report(AName, AChain.Helper, ATopCall, mRead);
  end
  else if (FContext.Index = nil) and (ATopCall.StartOffset < AChain.InheritedOffset) and
    (AChain.InheritedOffset < MaxInt) then
  begin
    FReport.Add(TTextRange.Create(ATopCall.StartPos, ATopCall.EndPos),
      cTexts[TConstructorsText.BeforeInherited].Fmt([AName]), TRuleConfidence.Low);
  end;
end;

procedure TConstructorScan.CheckCall(const AChain: TCallChain; ACallee: TSyntaxNode);
var
  mName: string;
  mMember: TIndexSymbol;
  mTop: TSyntaxNode;
begin
  mName := SelfMember(ACallee);
  mTop := AChain.TopCall;
  if mTop = nil then
  begin
    mTop := ACallee;
  end;
  if (mName = '') or ((ACallee.Kind = TSyntaxKind.Identifier) and IsLocalName(AChain, mName, mTop)) or
    not FindMethod(AChain.ClassName, mName, mMember) or (mMember.Kind <> TIndexSymbolKind.Method) then
  begin
    Exit;
  end;
  if mMember.IsVirtual then
  begin
    CheckVirtual(AChain, mName, mTop);
  end
  else
  begin
    // Nicht virtuelle eigene Methode: ihr Rumpf in dieser Unit gehört zur Kette.
    FollowBody(AChain, FLocal.Body(mMember.Container + '.' + mName), mName, mTop);
  end;
end;

// Aufrufe im Rumpf: Anweisungen M; bzw. Self.M; und Aufrufe M(…) in Ausdrücken.
procedure TConstructorScan.Visit(const AChain: TCallChain; ABody: TSyntaxNode);
var
  mCallees: TList<TSyntaxNode>;
  mCallee: TSyntaxNode;
begin
  if ABody = nil then
  begin
    Exit;
  end;
  mCallees := TList<TSyntaxNode>.Create;
  try
    ABody.Search(
      function(ANode: TSyntaxNode): TSyntaxSearchStep
      begin
        Result := TSyntaxSearchStep.Descend;
        if ANode.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod] then
        begin
          Result := TSyntaxSearchStep.Skip;
        end
        else if (ANode.Kind in [TSyntaxKind.CallStatement, TSyntaxKind.Call]) and (ANode.ChildCount > 0) then
        begin
          if (ANode.Kind = TSyntaxKind.CallStatement) and (ANode[0].Kind = TSyntaxKind.Call) then
          begin
            Exit;
          end;
          mCallees.Add(ANode[0]);
        end;
      end);
    for mCallee in mCallees do
    begin
      CheckCall(AChain, mCallee);
    end;
  finally
    mCallees.Free;
  end;
end;

procedure TConstructorScan.CheckConstructor(const AClass: string; AConstructor: TSyntaxNode);
var
  mChain: TCallChain;
  mBody: TSyntaxNode;
  mInherited: string;
begin
  mBody := BlockOf(AConstructor);
  if mBody <> nil then
  begin
    mChain := Default(TCallChain);
    mChain.ClassName := AClass;
    mChain.Routine := AConstructor;
    mChain.InheritedOffset := InheritedOffset(mBody, mInherited);
    Visit(mChain, mBody);
  end;
end;

procedure TConstructorScan.Run;
var
  mSymbol: TIndexSymbol;
  mConstructor: TSyntaxNode;
begin
  for mSymbol in FLocal.Symbols do
  begin
    if (mSymbol.Kind <> TIndexSymbolKind.Constructor_) or (mSymbol.Container = '') or
      StartsText('class ', mSymbol.Signature) then
    begin
      Continue;
    end;
    mConstructor := FLocal.Body(mSymbol.Container + '.' + mSymbol.Name);
    // Deklaration und Implementierung stehen beide unter den Symbolen: jeden Rumpf einmal.
    if (mConstructor <> nil) and not FReported.ContainsKey('#' + IntToStr(mConstructor.StartOffset)) then
    begin
      FReported.Add('#' + IntToStr(mConstructor.StartOffset), True);
      CheckConstructor(mSymbol.Container, mConstructor);
    end;
  end;
end;

{ TVirtualCallInConstructorRule }

function TVirtualCallInConstructorRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('virtual-call-in-constructor', TRuleSeverity.Warning,
    cTexts[TConstructorsText.Title].Text);
end;

procedure TVirtualCallInConstructorRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mScan: TConstructorScan;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or not ContainsText(AContext.Text, 'constructor') then
  begin
    Exit;
  end;
  mScan := TConstructorScan.Create(AContext, AReport);
  try
    mScan.Run;
  finally
    mScan.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Inheritance.Constructors', cTexts);

end.
