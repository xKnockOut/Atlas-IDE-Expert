unit Atlas.Common.Index.Extractor.InlineRefs;

// Verweise der Rümpfe von inline-Routinen für den Symbolindex (#1017, siehe TIndexSymbol.InlineRefs).
// Ausgelagert aus Atlas.Common.Index.Extractor.

interface

uses
  System.Generics.Collections,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.Extractor.Tokens;

type
  TIndexInlineRefs = class
  private
    FSymbols: TList<TIndexSymbol>;
    FReader: TIndexTokenReader;
    /// <summary>Positionen der Methoden und Routinen in FSymbols je "typ.name" (klein), bis FIndexed
    /// eingetragen. Vorher suchte jede Implementierung alle Symbole ab: quadratisch in der Länge der Unit.
    /// </summary>
    FRoutines: TObjectDictionary<string, TList<Integer>>;
    FIndexed: Integer;
    /// <summary>Positionen der Routinen namens AName in AContainer; nil ohne.</summary>
    function RoutinesNamed(const AName, AContainer: string): TList<Integer>;
    function IsCandidate(ANode: TSyntaxNode): Boolean;
    /// <summary>Typparameter des Typs AContainer (TList&lt;T&gt; → 'T'), '' ohne.</summary>
    function ContainerParams(const AContainer: string): string;
    /// <summary>Deklaration der Implementierung ANode: gleicher Name und Typ, bei Überladungen dieselben
    /// Parametertypen. -1 ohne, -2 bei mehrdeutigen Überladungen ohne Parameterliste in der Implementierung.
    /// </summary>
    function FindDeclaration(ANode: TSyntaxNode; const AName, AContainer: string): Integer;
    /// <summary>Ist die Routine ANode (Deklaration AFound, -1 ohne) inline und nicht virtuell oder extern?</summary>
    function IsInlined(ANode: TSyntaxNode; AFound: Integer): Boolean;
    procedure SetRefs(APosition: Integer; const ARefs: TArray<string>);
    procedure StoreRefs(ANode: TSyntaxNode; const AName: string; AFound: Integer; const ARefs: TArray<string>);
    procedure AddRoutine(ANode: TSyntaxNode);
  public
    constructor Create(ASymbols: TList<TIndexSymbol>; AReader: TIndexTokenReader);
    destructor Destroy; override;
    /// <summary>Trägt InlineRefs an Deklaration und Implementierung der inline-Routinen aus ASection ein.</summary>
    procedure Add(ASection: TSyntaxNode);
    /// <summary>Verweise des Rumpfs ANode einer inline-Routine; nil, wenn die Routine nicht einbettbar ist.
    /// AContainer: Klasse der Methode, '' bei freien Routinen.</summary>
    function RefsOf(ANode: TSyntaxNode; const AContainer, AContainerParams: string): TArray<string>;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Index.Extractor.TypeText;

const
  cNotInlined: array[0..5] of string = ('virtual', 'dynamic', 'override', 'abstract', 'message', 'external');

type
  /// <summary>Sammelt die Verweise eines Routinenrumpfs; die Namen der Unit und des Typs sind bekannt.</summary>
  TInlineRefCollector = class
  private
    FContainer: string;
    FHeader: TSyntaxNode;
    FLocals: TDictionary<string, Boolean>;
    FSeen: TDictionary<string, Boolean>;
    FOwn: TDictionary<string, TIndexSymbol>;
    FMembers: TDictionary<string, TIndexSymbol>;
    FRefs: TList<string>;
    FNodes: TList<TSyntaxNode>;
    FBlocked: Boolean;
    procedure AddRef(const ARef: string);
    function IsKnown(const AKey: string): Boolean;
    procedure Visit(AChild, ARoot: TSyntaxNode);
    procedure WalkBody(ANode: TSyntaxNode);
    procedure MemberRef(AIdent: TSyntaxNode; const AMember: TIndexSymbol);
    procedure OwnRef(AIdent: TSyntaxNode; const ASymbol: TIndexSymbol);
    procedure Identifier(AIdent: TSyntaxNode);
    procedure TypeReference(AType: TSyntaxNode);
  public
    constructor Create(ASymbols: TList<TIndexSymbol>; const AContainer, AContainerParams: string;
      AHeader: TSyntaxNode);
    destructor Destroy; override;
    function Collect(ANode: TSyntaxNode): TArray<string>;
  end;

/// <summary>Namen einer Liste "A, B" bzw. "A,B" in ANames eintragen (klein).</summary>
procedure AddNameList(ANames: TDictionary<string, Boolean>; const AList: string);
var
  mName: string;
begin
  for mName in AList.Split([',']) do
  begin
    if mName.Trim <> '' then
    begin
      ANames.AddOrSetValue(LowerCase(TPascalLexer.PlainName(mName.Trim)), True);
    end;
  end;
end;

/// <summary>Liegt ANode in AOuter (oder ist es selbst)?</summary>
function IsInside(ANode, AOuter: TSyntaxNode): Boolean;
var
  mNode: TSyntaxNode;
begin
  Result := False;
  if AOuter = nil then
  begin
    Exit;
  end;
  mNode := ANode;
  while (mNode <> nil) and not Result do
  begin
    Result := mNode = AOuter;
    mNode := mNode.Parent;
  end;
end;

/// <summary>Wird AIdent als Wert weiter benutzt (A.B, A[i])? Dann braucht der Rumpf die Unit seines Typs.</summary>
function IsDereferenced(AIdent: TSyntaxNode): Boolean;
var
  mParent: TSyntaxNode;
begin
  mParent := AIdent.Parent;
  Result := (mParent <> nil) and (mParent.Kind in [TSyntaxKind.MemberAccess, TSyntaxKind.IndexAccess]) and
    (mParent.ChildCount > 0) and (mParent[0] = AIdent) and (mParent.FindChild(TSyntaxKind.GenericArgs) = nil);
end;

function TypeRefOf(const ASymbol: TIndexSymbol): string;
begin
  Result := ':' + ASymbol.TypeName;
  if ASymbol.TypeArgs <> '' then
  begin
    Result := Result + '<' + ASymbol.TypeArgs + '>';
  end;
end;

/// <summary>Direktiven eines Routinenkopfs in Kleinschreibung.</summary>
function DirectivesOfHeader(AHeader: TSyntaxNode): TArray<string>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to AHeader.ChildCount - 1 do
  begin
    if AHeader[mIndex].Kind = TSyntaxKind.Directive then
    begin
      Result := Result + [LowerCase(AHeader[mIndex].Name)];
    end;
  end;
end;

/// <summary>inline in ADirectives setzt AInline, virtual, extern und Verwandte setzen ASkip.</summary>
procedure ReadInlineDirectives(const ADirectives: TArray<string>; var AInline, ASkip: Boolean);
var
  mDirective: string;
begin
  for mDirective in ADirectives do
  begin
    AInline := AInline or SameText(mDirective, 'inline');
    ASkip := ASkip or (IndexText(mDirective, cNotInlined) >= 0);
  end;
end;

function SameParamTypes(const A, B: TArray<string>): Boolean;
var
  mIndex: Integer;
begin
  Result := Length(A) = Length(B);
  mIndex := 0;
  while Result and (mIndex <= High(A)) do
  begin
    Result := SameText(A[mIndex], B[mIndex]);
    Inc(mIndex);
  end;
end;

/// <summary>Methode oder Routine AName im Typ AContainer?</summary>
function IsSameRoutine(const ASymbol: TIndexSymbol; const AName, AContainer: string): Boolean;
begin
  Result := (ASymbol.Kind in [TIndexSymbolKind.Method, TIndexSymbolKind.Routine]) and
    SameText(ASymbol.Name, AName) and SameText(ASymbol.Container, AContainer);
end;

/// <summary>Teilt "TFoo.Bar" in Typ und Namen; ohne Punkt ist AContainer ''.</summary>
procedure SplitName(const AFullName: string; out AContainer, AName: string);
var
  mDot: Integer;
begin
  AName := AFullName;
  AContainer := '';
  mDot := AFullName.LastIndexOf('.');
  if mDot >= 0 then
  begin
    AContainer := AFullName.Substring(0, mDot);
    AName := AFullName.Substring(mDot + 1);
  end;
end;

{ TInlineRefCollector }

constructor TInlineRefCollector.Create(ASymbols: TList<TIndexSymbol>; const AContainer, AContainerParams: string;
  AHeader: TSyntaxNode);
var
  mSymbol: TIndexSymbol;
begin
  inherited Create;
  FContainer := AContainer;
  FHeader := AHeader;
  FLocals := TDictionary<string, Boolean>.Create;
  FSeen := TDictionary<string, Boolean>.Create;
  FOwn := TDictionary<string, TIndexSymbol>.Create;
  FMembers := TDictionary<string, TIndexSymbol>.Create;
  FRefs := TList<string>.Create;
  FNodes := TList<TSyntaxNode>.Create;
  for mSymbol in ASymbols do
  begin
    if mSymbol.Container = '' then
    begin
      FOwn.AddOrSetValue(LowerCase(mSymbol.Name), mSymbol);
    end
    else if (AContainer <> '') and SameText(mSymbol.Container, AContainer) and
      not FMembers.ContainsKey(LowerCase(mSymbol.Name)) then
    begin
      FMembers.Add(LowerCase(mSymbol.Name), mSymbol);
    end;
  end;
  FLocals.Add('result', True);
  FLocals.Add('self', True);
  AddNameList(FLocals, AContainerParams);
  if AHeader <> nil then
  begin
    AddNameList(FLocals, TIndexTypeText.TypeParamsOf(AHeader));
  end;
end;

destructor TInlineRefCollector.Destroy;
begin
  FNodes.Free;
  FRefs.Free;
  FMembers.Free;
  FOwn.Free;
  FSeen.Free;
  FLocals.Free;
  inherited;
end;

procedure TInlineRefCollector.AddRef(const ARef: string);
begin
  if (ARef <> '') and not FSeen.ContainsKey(LowerCase(ARef)) then
  begin
    FSeen.Add(LowerCase(ARef), True);
    FRefs.Add(ARef);
  end;
end;

function TInlineRefCollector.IsKnown(const AKey: string): Boolean;
begin
  Result := FLocals.ContainsKey(AKey) or FOwn.ContainsKey(AKey) or
    ((FContainer <> '') and FMembers.ContainsKey(AKey));
end;

procedure TInlineRefCollector.Visit(AChild, ARoot: TSyntaxNode);
begin
  case AChild.Kind of
    TSyntaxKind.Parameter, TSyntaxKind.VarDecl, TSyntaxKind.ConstDecl, TSyntaxKind.InlineVar,
    TSyntaxKind.InlineConst, TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement, TSyntaxKind.TypeDecl:
      AddNameList(FLocals, AChild.Name);
    TSyntaxKind.AsmBlock, TSyntaxKind.WithStatement:
      FBlocked := True;
    TSyntaxKind.RoutineDecl:
      FBlocked := FBlocked or (AChild <> ARoot);
    TSyntaxKind.ArrayType:
      // Offene Array-Parameter verhindern das Einbetten.
      FBlocked := FBlocked or ((AChild.Parent <> nil) and (AChild.Parent.Kind = TSyntaxKind.Parameter));
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
  // Den Kopf (Parameter- und Ergebnistypen) kennt der Aufrufer ohnehin.
  if (AChild.Kind in [TSyntaxKind.Identifier, TSyntaxKind.TypeReference]) and not IsInside(AChild, FHeader) then
  begin
    FNodes.Add(AChild);
  end;
end;

procedure TInlineRefCollector.WalkBody(ANode: TSyntaxNode);
var
  mStack: TStack<TSyntaxNode>;
  mChild: TSyntaxNode;
  mIndex: Integer;
begin
  // Lokale Namen zuerst, damit die Reihenfolge im Rumpf keine Rolle spielt.
  mStack := TStack<TSyntaxNode>.Create;
  try
    mStack.Push(ANode);
    while mStack.Count > 0 do
    begin
      mChild := mStack.Pop;
      Visit(mChild, ANode);
      for mIndex := mChild.ChildCount - 1 downto 0 do
      begin
        mStack.Push(mChild[mIndex]);
      end;
    end;
  finally
    mStack.Free;
  end;
end;

procedure TInlineRefCollector.MemberRef(AIdent: TSyntaxNode; const AMember: TIndexSymbol);
begin
  if AMember.Visibility = TIndexVisibility.StrictPrivate then
  begin
    AddRef('!' + AMember.Name);
  end;
  if IsDereferenced(AIdent) and (AMember.Kind in [TIndexSymbolKind.Field, TIndexSymbolKind.Property_]) and
    (AMember.TypeName <> '') then
  begin
    AddRef(TypeRefOf(AMember));
  end;
end;

procedure TInlineRefCollector.OwnRef(AIdent: TSyntaxNode; const ASymbol: TIndexSymbol);
begin
  if IsDereferenced(AIdent) and (ASymbol.Kind in [TIndexSymbolKind.Variable, TIndexSymbolKind.Constant]) and
    (ASymbol.TypeName <> '') then
  begin
    AddRef(TypeRefOf(ASymbol));
  end;
end;

procedure TInlineRefCollector.Identifier(AIdent: TSyntaxNode);
var
  mName, mKey: string;
  mSymbol: TIndexSymbol;
begin
  mName := TPascalLexer.PlainName(AIdent.Name);
  mKey := LowerCase(mName);
  if (mName = '') or FLocals.ContainsKey(mKey) then
  begin
    Exit;
  end;
  if (FContainer <> '') and FMembers.TryGetValue(mKey, mSymbol) then
  begin
    MemberRef(AIdent, mSymbol);
  end
  else if FOwn.TryGetValue(mKey, mSymbol) then
  begin
    OwnRef(AIdent, mSymbol);
  end
  else
  begin
    AddRef(mName);
  end;
end;

procedure TInlineRefCollector.TypeReference(AType: TSyntaxNode);
var
  mName: string;
begin
  mName := TPascalLexer.PlainName(AType.Name);
  if (mName <> '') and not MatchText(mName, ['string', 'const', 'file']) and not IsKnown(LowerCase(mName)) then
  begin
    AddRef(':' + mName);
  end;
end;

function TInlineRefCollector.Collect(ANode: TSyntaxNode): TArray<string>;
var
  mChild: TSyntaxNode;
begin
  Result := nil;
  WalkBody(ANode);
  if FBlocked then
  begin
    Exit;
  end;
  for mChild in FNodes do
  begin
    if mChild.Kind = TSyntaxKind.Identifier then
    begin
      Identifier(mChild);
    end
    else
    begin
      TypeReference(mChild);
    end;
  end;
  Result := FRefs.ToArray;
  // nil heißt „nicht einbettbar“; ohne Verweise bleibt die Routine trotzdem als inline erkennbar (#1381).
  if Length(Result) = 0 then
  begin
    Result := TArray<string>.Create(TIndexSymbol.cInlineWithoutRefs);
  end;
end;

{ TIndexInlineRefs }

constructor TIndexInlineRefs.Create(ASymbols: TList<TIndexSymbol>; AReader: TIndexTokenReader);
begin
  inherited Create;
  FSymbols := ASymbols;
  FReader := AReader;
  FRoutines := TObjectDictionary<string, TList<Integer>>.Create([doOwnsValues]);
end;

destructor TIndexInlineRefs.Destroy;
begin
  FRoutines.Free;
  inherited Destroy;
end;

function RoutineKey(const AName, AContainer: string): string;
begin
  Result := LowerCase(AContainer) + '.' + LowerCase(AName);
end;

function TIndexInlineRefs.RoutinesNamed(const AName, AContainer: string): TList<Integer>;
var
  mSymbol: TIndexSymbol;
  mKey: string;
  mList: TList<Integer>;
begin
  // Neu hinzugekommene Symbole nachtragen; die Positionen bleiben gleich (nur angehängt).
  while FIndexed < FSymbols.Count do
  begin
    mSymbol := FSymbols[FIndexed];
    if mSymbol.Kind in [TIndexSymbolKind.Method, TIndexSymbolKind.Routine] then
    begin
      mKey := RoutineKey(mSymbol.Name, mSymbol.Container);
      if not FRoutines.TryGetValue(mKey, mList) then
      begin
        mList := TList<Integer>.Create;
        FRoutines.Add(mKey, mList);
      end;
      mList.Add(FIndexed);
    end;
    Inc(FIndexed);
  end;
  if not FRoutines.TryGetValue(RoutineKey(AName, AContainer), Result) then
  begin
    Result := nil;
  end;
end;

function TIndexInlineRefs.RefsOf(ANode: TSyntaxNode; const AContainer, AContainerParams: string): TArray<string>;
var
  mCollector: TInlineRefCollector;
begin
  mCollector := TInlineRefCollector.Create(FSymbols, AContainer, AContainerParams,
    ANode.FindChild(TSyntaxKind.RoutineHeader));
  try
    Result := mCollector.Collect(ANode);
  finally
    mCollector.Free;
  end;
end;

function TIndexInlineRefs.ContainerParams(const AContainer: string): string;
var
  mSymbol: TIndexSymbol;
begin
  Result := '';
  if AContainer = '' then
  begin
    Exit;
  end;
  for mSymbol in FSymbols do
  begin
    if (mSymbol.Kind in [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType,
      TIndexSymbolKind.InterfaceType, TIndexSymbolKind.HelperType]) and
      SameText(mSymbol.QualifiedName, AContainer) then
    begin
      Exit(mSymbol.TypeParams);
    end;
  end;
end;

procedure TIndexInlineRefs.SetRefs(APosition: Integer; const ARefs: TArray<string>);
var
  mSymbol: TIndexSymbol;
begin
  mSymbol := FSymbols[APosition];
  mSymbol.InlineRefs := ARefs;
  FSymbols[APosition] := mSymbol;
end;

function TIndexInlineRefs.IsCandidate(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.RoutineDecl) and (ANode.FindChild(TSyntaxKind.RoutineHeader) <> nil) and
    (ANode.FindChild(TSyntaxKind.Block) <> nil) and not FReader.IsConstructor(ANode);
end;

function TIndexInlineRefs.FindDeclaration(ANode: TSyntaxNode; const AName, AContainer: string): Integer;
var
  mPosition, mMin, mMax: Integer;
  mTypes: TArray<string>;
  mSymbol: TIndexSymbol;
  mCandidates: TList<Integer>;
begin
  Result := -1;
  mCandidates := RoutinesNamed(AName, AContainer);
  if mCandidates = nil then
  begin
    Exit;
  end;
  TIndexTypeText.ParamInfo(ANode.FindChild(TSyntaxKind.RoutineHeader), mMin, mMax, mTypes);
  for mPosition in mCandidates do
  begin
    mSymbol := FSymbols[mPosition];
    if IsSameRoutine(mSymbol, AName, AContainer) and not (mSymbol.Range.StartPos = ANode.StartPos) and
      ((Length(mTypes) = 0) or SameParamTypes(mSymbol.ParamTypes, mTypes)) then
    begin
      if Result >= 0 then
      begin
        // Mehrdeutig (Überladungen ohne Parameterliste in der Implementierung).
        Exit(-2);
      end;
      Result := mPosition;
    end;
  end;
end;

function TIndexInlineRefs.IsInlined(ANode: TSyntaxNode; AFound: Integer): Boolean;
var
  mSkip: Boolean;
begin
  Result := False;
  mSkip := False;
  ReadInlineDirectives(DirectivesOfHeader(ANode.FindChild(TSyntaxKind.RoutineHeader)), Result, mSkip);
  if AFound >= 0 then
  begin
    ReadInlineDirectives(FSymbols[AFound].Directives, Result, mSkip);
  end;
  Result := Result and not mSkip;
end;

procedure TIndexInlineRefs.StoreRefs(ANode: TSyntaxNode; const AName: string; AFound: Integer;
  const ARefs: TArray<string>);
var
  mPosition: Integer;
begin
  if AFound >= 0 then
  begin
    SetRefs(AFound, ARefs);
  end;
  for mPosition := 0 to FSymbols.Count - 1 do
  begin
    if (FSymbols[mPosition].Range.StartPos = ANode.StartPos) and SameText(FSymbols[mPosition].Name, AName) then
    begin
      SetRefs(mPosition, ARefs);
    end;
  end;
end;

procedure TIndexInlineRefs.AddRoutine(ANode: TSyntaxNode);
var
  mName, mContainer: string;
  mFound: Integer;
  mRefs: TArray<string>;
begin
  SplitName(ANode.Name, mContainer, mName);
  mFound := FindDeclaration(ANode, mName, mContainer);
  if (mFound = -2) or not IsInlined(ANode, mFound) then
  begin
    Exit;
  end;
  mRefs := RefsOf(ANode, mContainer, ContainerParams(mContainer));
  if mRefs <> nil then
  begin
    StoreRefs(ANode, mName, mFound, mRefs);
  end;
end;

procedure TIndexInlineRefs.Add(ASection: TSyntaxNode);
var
  mIndex: Integer;
begin
  if ASection = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to ASection.ChildCount - 1 do
  begin
    if IsCandidate(ASection[mIndex]) then
    begin
      AddRoutine(ASection[mIndex]);
    end;
  end;
end;

end.
