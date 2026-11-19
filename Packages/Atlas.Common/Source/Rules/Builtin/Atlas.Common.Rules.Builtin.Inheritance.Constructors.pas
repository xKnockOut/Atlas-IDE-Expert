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
    function DescendantsOf(const AClass: string): TArray<TDescendant>;
    function FindFieldRead(const AClass, AMethod: string): TFieldRead;
    function CheckOverride(const ADescendant: TDescendant; const AMethod: string): TFieldRead;
    procedure Visit(const AClass: string; AConstructor, ABody: TSyntaxNode; AInheritedOffset, ADepth: Integer;
      const AHelper: string; ATopCall: TSyntaxNode);
    procedure CheckCall(const AClass: string; AConstructor, ACallee: TSyntaxNode; AInheritedOffset, ADepth: Integer;
      const AHelper: string; ATopCall: TSyntaxNode);
    procedure Report(const AMethod, AHelper: string; ATopCall: TSyntaxNode; const ARead: TFieldRead);
    procedure CheckConstructor(const AClass: string; AConstructor: TSyntaxNode);
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    destructor Destroy; override;
    procedure Run;
  end;

function ClassPartOf(const AName: string): string;
var
  mDot: Integer;
begin
  mDot := LastDelimiter('.', AName);
  Result := Copy(AName, 1, mDot - 1);
end;

function MethodPartOf(const AName: string): string;
begin
  Result := Copy(AName, LastDelimiter('.', AName) + 1, MaxInt);
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

// Prüft der Rumpf das Feld auf nil (Assigned(F), F <> nil, F = nil)?
function ChecksNil(ABody: TSyntaxNode; const AField: string): Boolean;
begin
  Result := ABody.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount = 2) and (ANode[0].Kind = TSyntaxKind.Identifier) and
        SameText(ANode[0].Name, 'Assigned') and SameText(FieldAt(ANode[1]), AField) then
      begin
        Result := TSyntaxSearchStep.Found;
      end
      else if (ANode.Kind = TSyntaxKind.BinaryExpr) and ((ANode.Name = '=') or (ANode.Name = '<>')) and
        (ANode.ChildCount = 2) and ((SameText(FieldAt(ANode[0]), AField) and IsNilNode(ANode[1])) or
        (SameText(FieldAt(ANode[1]), AField) and IsNilNode(ANode[0]))) then
      begin
        Result := TSyntaxSearchStep.Found;
      end;
    end) <> nil;
end;

// Liest der Rumpf das Feld (nicht nur als Ziel einer Zuweisung oder in FreeAndNil bzw. F.Free)?
function ReadsField(ABody: TSyntaxNode; const AField: string): Boolean;
begin
  Result := ABody.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    var
      mParent: TSyntaxNode;
    begin
      Result := TSyntaxSearchStep.Descend;
      if ANode.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod] then
      begin
        Exit(TSyntaxSearchStep.Skip);
      end;
      if not SameText(FieldAt(ANode), AField) or ((ANode.Kind = TSyntaxKind.Identifier) and (ANode.Parent <> nil) and
        (ANode.Parent.Kind = TSyntaxKind.MemberAccess) and (ANode.Parent[0] <> ANode)) then
      begin
        Exit;
      end;
      mParent := ANode.Parent;
      if (mParent <> nil) and (mParent.Kind = TSyntaxKind.AssignStatement) and (mParent[0] = ANode) then
      begin
        Exit(TSyntaxSearchStep.Skip);
      end;
      if (mParent <> nil) and (mParent.Kind = TSyntaxKind.Call) and (mParent[0].Kind = TSyntaxKind.Identifier) and
        SameText(mParent[0].Name, 'FreeAndNil') then
      begin
        Exit(TSyntaxSearchStep.Skip);
      end;
      if (mParent <> nil) and (mParent.Kind = TSyntaxKind.MemberAccess) and SameText(mParent.Name, 'Free') then
      begin
        Exit(TSyntaxSearchStep.Skip);
      end;
      Result := TSyntaxSearchStep.Found;
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

// Alle Nachfahren der Klasse (auch über mehrere Stufen): aus der Unit und über den Index aus anderen Units.
function TConstructorScan.DescendantsOf(const AClass: string): TArray<TDescendant>;
var
  mPending: TQueue<string>;
  mSeen: TDictionary<string, Boolean>;
  mName: string;
  mSymbol: TIndexSymbol;
  mLocation: TSymbolLocation;
  mDescendant: TDescendant;
begin
  if FDescendants.TryGetValue(AnsiUpperCase(AClass), Result) then
  begin
    Exit;
  end;
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
  if FContext.Index <> nil then
  begin
    mPending := TQueue<string>.Create;
    mSeen := TDictionary<string, Boolean>.Create;
    try
      mPending.Enqueue(AClass);
      mSeen.Add(AnsiUpperCase(AClass), True);
      while (mPending.Count > 0) and (Length(Result) < cMaxDescendants) do
      begin
        mName := mPending.Dequeue;
        for mLocation in FContext.Index.Descendants(mName) do
        begin
          if mSeen.ContainsKey(AnsiUpperCase(mLocation.Symbol.Name)) then
          begin
            Continue;
          end;
          mSeen.Add(AnsiUpperCase(mLocation.Symbol.Name), True);
          mPending.Enqueue(mLocation.Symbol.Name);
          // Nachfahren der geprüften Unit kommen schon aus ihrem Baum.
          if SameText(mLocation.UnitName, FAncestry.Local.UnitName) or ((FContext.FileName <> '') and
            SameText(mLocation.FileName, FContext.FileName)) then
          begin
            Continue;
          end;
          mDescendant.ClassName := mLocation.Symbol.Name;
          mDescendant.UnitData := LoadUnit(mLocation.FileName);
          if mDescendant.UnitData <> nil then
          begin
            Result := Result + [mDescendant];
          end;
        end;
      end;
    finally
      mSeen.Free;
      mPending.Free;
    end;
  end;
  FDescendants.Add(AnsiUpperCase(AClass), Result);
end;

// Überschreibt der Nachfahr AMethod und liest dort ein eigenes Feld, das sein Konstruktor erst nach inherited setzt?
function TConstructorScan.CheckOverride(const ADescendant: TDescendant; const AMethod: string): TFieldRead;
var
  mSymbol, mField, mConstructor: TIndexSymbol;
  mOverride, mBody, mConstructorBody: TSyntaxNode;
  mOverrides: Boolean;
  mAfter: Integer;
  mInherited: string;
begin
  Result := Default(TFieldRead);
  mOverrides := False;
  for mSymbol in ADescendant.UnitData.MemberSymbols(ADescendant.ClassName, TIndexSymbolKind.Method) do
  begin
    mOverrides := mOverrides or (SameText(mSymbol.Name, AMethod) and HasDirective(mSymbol, 'override'));
  end;
  if not mOverrides then
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
    if DeclaresLocal(mOverride, mField.Name) or ChecksNil(mBody, mField.Name) or not ReadsField(mBody, mField.Name)
    then
    begin
      Continue;
    end;
    for mConstructor in ADescendant.UnitData.MemberSymbols(ADescendant.ClassName, TIndexSymbolKind.Constructor_) do
    begin
      if StartsText('class ', mConstructor.Signature) then
      begin
        Continue;
      end;
      mConstructorBody := BlockOf(ADescendant.UnitData.Body(ADescendant.ClassName + '.' + mConstructor.Name));
      if mConstructorBody = nil then
      begin
        Continue;
      end;
      mAfter := InheritedOffset(mConstructorBody, mInherited);
      if (mAfter < MaxInt) and AssignsFieldAfter(mConstructorBody, mField.Name, mAfter) then
      begin
        Result.Found := True;
        Result.ClassName := ADescendant.ClassName;
        Result.FieldName := mField.Name;
        Result.InheritedName := mInherited;
        if Result.InheritedName = '' then
        begin
          Result.InheritedName := mConstructor.Name;
        end;
        Result.Override_ := mOverride;
        Result.Local := ADescendant.UnitData.Local;
        Exit;
      end;
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

procedure TConstructorScan.CheckCall(const AClass: string; AConstructor, ACallee: TSyntaxNode;
  AInheritedOffset, ADepth: Integer; const AHelper: string; ATopCall: TSyntaxNode);
var
  mName, mKey, mHelper: string;
  mMember: TIndexSymbol;
  mNested, mTop: TSyntaxNode;
  mRead: TFieldRead;
  mIndex: Integer;
begin
  mName := SelfMember(ACallee);
  if mName = '' then
  begin
    Exit;
  end;
  mTop := ATopCall;
  if mTop = nil then
  begin
    mTop := ACallee;
  end;
  mHelper := AHelper;
  // Eingebettete Routine des Konstruktors (Identifier ohne Self).
  if ACallee.Kind = TSyntaxKind.Identifier then
  begin
    for mIndex := 0 to AConstructor.ChildCount - 1 do
    begin
      mNested := AConstructor[mIndex];
      if (mNested.Kind = TSyntaxKind.RoutineDecl) and SameText(mNested.Name, mName) then
      begin
        if ADepth < cMaxDepth then
        begin
          if mHelper = '' then
          begin
            mHelper := mName;
          end;
          Visit(AClass, mNested, BlockOf(mNested), AInheritedOffset, ADepth + 1, mHelper, mTop);
        end;
        Exit;
      end;
    end;
    if DeclaresLocal(AConstructor, mName) then
    begin
      Exit;
    end;
  end;
  if not FindMethod(AClass, mName, mMember) or (mMember.Kind <> TIndexSymbolKind.Method) then
  begin
    Exit;
  end;
  if mMember.IsVirtual then
  begin
    mKey := IntToStr(mTop.StartOffset) + #0 + AnsiUpperCase(mName);
    if FReported.ContainsKey(mKey) then
    begin
      Exit;
    end;
    FReported.Add(mKey, True);
    mRead := FindFieldRead(AClass, mName);
    if mRead.Found then
    begin
      Report(mName, mHelper, mTop, mRead);
    end
    else if (FContext.Index = nil) and (mTop.StartOffset < AInheritedOffset) and (AInheritedOffset < MaxInt) then
    begin
      FReport.Add(TTextRange.Create(mTop.StartPos, mTop.EndPos),
        cTexts[TConstructorsText.BeforeInherited].Fmt([mName]), TRuleConfidence.Low);
    end;
  end
  else if ADepth < cMaxDepth then
  begin
    // Nicht virtuelle eigene Methode: ihr Rumpf in dieser Unit gehört zur Kette.
    mNested := FLocal.Body(mMember.Container + '.' + mName);
    if mNested <> nil then
    begin
      if mHelper = '' then
      begin
        mHelper := mName;
      end;
      Visit(AClass, mNested, BlockOf(mNested), AInheritedOffset, ADepth + 1, mHelper, mTop);
    end;
  end;
end;

// Aufrufe im Rumpf: Anweisungen M; bzw. Self.M; und Aufrufe M(…) in Ausdrücken.
procedure TConstructorScan.Visit(const AClass: string; AConstructor, ABody: TSyntaxNode;
  AInheritedOffset, ADepth: Integer; const AHelper: string; ATopCall: TSyntaxNode);
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
      CheckCall(AClass, AConstructor, mCallee, AInheritedOffset, ADepth, AHelper, ATopCall);
    end;
  finally
    mCallees.Free;
  end;
end;

procedure TConstructorScan.CheckConstructor(const AClass: string; AConstructor: TSyntaxNode);
var
  mBody: TSyntaxNode;
  mInherited: string;
begin
  mBody := BlockOf(AConstructor);
  if mBody <> nil then
  begin
    Visit(AClass, AConstructor, mBody, InheritedOffset(mBody, mInherited), 0, '', nil);
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
