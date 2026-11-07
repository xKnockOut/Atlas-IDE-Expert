unit Atlas.Common.Architecture.SymbolPath.Graph;

// Kanten aus dem Index für die Pfadsuche zwischen Symbolen (#1117), ausgelagert
// aus Atlas.Common.Architecture.SymbolPath. Aufrufkanten stehen in
// Atlas.Common.Architecture.SymbolPath.Calls.
//
// - Vorwärts je Knoten: uses (Uses-Graph), contains, inherits, implements
//   (Klasse → Interface, Interface → Umsetzung, ebenso je Methode), hasField,
//   parameter und result über die Typangaben.
// - Typnamen löst die eigene Unit vor den Units der uses-Liste auf (der letzte
//   Eintrag gewinnt); ohne sichtbaren Treffer gelten alle Treffer als
//   erschlossen (#1119).
// - Rückwärts nur Kandidaten, die wirklich eine Kante hierher haben (dieselben
//   Kanten wie vorwärts, gefiltert nach den erlaubten Kantenarten).
// - Bibliotheks-Units sind Start oder Ziel, aber kein Durchgang, außer mit
//   ThroughLibrary.

interface

{$SCOPEDENUMS ON}

uses
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Architecture.UsesGraph,
  Atlas.Common.Architecture.SymbolPath.Nodes;

type
  TSymbolPathGraph = class
  private type
    TTypeTarget = record
      Nodes: TArray<Integer>;
      Inferred: Boolean;
    end;
    TSymbolRef = record
      UnitName: string;
      Index: Integer;
    end;
    TRefList = TList<TSymbolRef>;
  private
    FTable: TSymbolPathNodeTable;
    FGraph: TUsesGraph;
    FTypes: TDictionary<string, TTypeTarget>;
    FImplementers: TDictionary<Integer, TArray<Integer>>;
    FForward: TDictionary<Integer, TSymbolPathEdges>;
    FPredecessors: TDictionary<Integer, TArray<Integer>>;
    FRefs: TObjectDictionary<string, TRefList>;
    FEndpoints: TDictionary<Integer, Boolean>;
    FVia: TSymbolPathEdgeKinds;
    FThroughLibrary: Boolean;
    function ResolveType(AUnit: TSymbolPathUnit; const AName: string): TTypeTarget;
    function InterfacesOf(ANode: Integer): TArray<Integer>;
    function ImplementersOf(ANode: Integer): TArray<Integer>;
    /// <summary>Methode der Klasse AClass, die AName des Interfaces AInterface umsetzt; -1 ohne.</summary>
    function ImplementingMember(AClass, AInterface: Integer; const AName: string): Integer;
    procedure AddTypeEdges(AList: TSymbolPathEdgeList; AUnit: TSymbolPathUnit; const ATypeText: string;
      AKind: TSymbolPathEdgeKind; const ANode: TSymbolPathNode);
    function BuildForward(ANode: Integer): TSymbolPathEdges;
    procedure UsesEdges(const ANode: TSymbolPathNode; AList: TSymbolPathEdgeList);
    procedure UnitEdges(const ANode: TSymbolPathNode; AData: TSymbolPathUnit; AList: TSymbolPathEdgeList);
    procedure StructEdges(ANode: Integer; AData: TSymbolPathUnit; AList: TSymbolPathEdgeList);
    procedure RoutineEdges(ANode: Integer; AData: TSymbolPathUnit; AList: TSymbolPathEdgeList);
    procedure InterfaceMethodEdges(const ANode: TSymbolPathNode; AContainer: Integer; AList: TSymbolPathEdgeList);
    procedure ClassMethodEdges(ANode, AContainer: Integer; AList: TSymbolPathEdgeList);
    procedure BuildRefs;
    procedure AddRef(const AName, AUnitName: string; AIndex: Integer);
    procedure AddUnitRefs(const AItem: TUnitIndex);
    procedure UnitPredecessors(const ANode: TSymbolPathNode; ACandidates: TList<Integer>);
    procedure StructPredecessors(const ANode: TSymbolPathNode; AData: TSymbolPathUnit; ACandidates: TList<Integer>);
    procedure TypeRefPredecessors(const ANode: TSymbolPathNode; ACandidates: TList<Integer>);
    procedure RoutinePredecessors(ANode: Integer; AData: TSymbolPathUnit; ACandidates: TList<Integer>);
    procedure SymbolPredecessors(ANode: Integer; AData: TSymbolPathUnit; ACandidates: TList<Integer>);
    function ConfirmedPredecessors(ANode: Integer; ACandidates: TList<Integer>): TArray<Integer>;
  public
    /// <summary>ATable und AGraph gehören dem Aufrufer.</summary>
    constructor Create(ATable: TSymbolPathNodeTable; AGraph: TUsesGraph);
    destructor Destroy; override;
    /// <summary>Erlaubte Kantenarten, Bibliothek als Durchgang und Start/Ziel der nächsten Suche.</summary>
    procedure Configure(AVia: TSymbolPathEdgeKinds; AThroughLibrary: Boolean; const AEndpoints: TArray<Integer>);
    /// <summary>Alle Kanten aus dem Index (ohne calls), sortiert.</summary>
    function ForwardOf(ANode: Integer): TSymbolPathEdges;
    /// <summary>Knoten mit einer erlaubten Kante nach ANode (ohne calls).</summary>
    function PredecessorsOf(ANode: Integer): TArray<Integer>;
    /// <summary>ASource hat eine erlaubte Kante nach ATarget (ohne calls).</summary>
    function Leads(ASource, ATarget: Integer): Boolean;
    /// <summary>ANode darf durchlaufen werden (keine Bibliothek, außer mit ThroughLibrary oder als Start/Ziel).
    /// </summary>
    function Passable(ANode: Integer): Boolean;
    property Via: TSymbolPathEdgeKinds read FVia;
    property ThroughLibrary: Boolean read FThroughLibrary;
  end;

implementation

uses
  System.SysUtils;

constructor TSymbolPathGraph.Create(ATable: TSymbolPathNodeTable; AGraph: TUsesGraph);
begin
  inherited Create;
  FTable := ATable;
  FGraph := AGraph;
  FTypes := TDictionary<string, TTypeTarget>.Create;
  FImplementers := TDictionary<Integer, TArray<Integer>>.Create;
  FForward := TDictionary<Integer, TSymbolPathEdges>.Create;
  FPredecessors := TDictionary<Integer, TArray<Integer>>.Create;
  FEndpoints := TDictionary<Integer, Boolean>.Create;
end;

destructor TSymbolPathGraph.Destroy;
begin
  FEndpoints.Free;
  FRefs.Free;
  FPredecessors.Free;
  FForward.Free;
  FImplementers.Free;
  FTypes.Free;
  inherited;
end;

procedure TSymbolPathGraph.Configure(AVia: TSymbolPathEdgeKinds; AThroughLibrary: Boolean;
  const AEndpoints: TArray<Integer>);
var
  mNode: Integer;
begin
  FVia := AVia;
  FThroughLibrary := AThroughLibrary;
  FEndpoints.Clear;
  for mNode in AEndpoints do
  begin
    FEndpoints.AddOrSetValue(mNode, True);
  end;
end;

function TSymbolPathGraph.Passable(ANode: Integer): Boolean;
begin
  Result := not FTable.Node(ANode).Library_ or FThroughLibrary or FEndpoints.ContainsKey(ANode);
end;

/// <summary>Stelle des letzten uses-Eintrags von AUnit, der AUnitName trifft (spätere verdecken frühere); -1 ohne.
/// </summary>
function Visible(AUnit: TSymbolPathUnit; const AUnitName: string): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 0 to High(AUnit.UsesNames) do
  begin
    if TSymbolPathNames.UsesMatches(AUnit.UsesNames[mIndex], AUnitName) then
    begin
      Result := mIndex;
    end;
  end;
end;

/// <summary>Typen AName (mit Qualifizierer "Unit.TTyp" bzw. "TAussen.TTyp") im Index; je Unit und qualifiziertem
/// Namen die spätere Deklaration (Vorwärtsdeklaration und vollständige).</summary>
function TypeCandidates(const AIndex: ISymbolIndex; const AName: string): TArray<TSymbolLocation>;
var
  mName, mQualifier, mKey: string;
  mDot, mRank: Integer;
  mLocation: TSymbolLocation;
  mSeen: TDictionary<string, Integer>;
begin
  Result := nil;
  mName := AName;
  mQualifier := '';
  mDot := LastDelimiter('.', mName);
  if mDot > 0 then
  begin
    mQualifier := Copy(mName, 1, mDot - 1);
    mName := Copy(mName, mDot + 1, MaxInt);
  end;
  mSeen := TDictionary<string, Integer>.Create;
  try
    for mLocation in AIndex.FindSymbols(mName) do
    begin
      if not (mLocation.Symbol.Kind in cSymbolPathTypeKinds) or ((mQualifier <> '') and
        not SameText(mLocation.Symbol.Container, TSymbolPathNames.LastSegment(mQualifier)) and
        not TSymbolPathNames.UsesMatches(mQualifier, mLocation.UnitName)) then
      begin
        Continue;
      end;
      mKey := LowerCase(mLocation.UnitName + '|' + mLocation.Symbol.QualifiedName);
      if not mSeen.TryGetValue(mKey, mRank) then
      begin
        mSeen.Add(mKey, Length(Result));
        Result := Result + [mLocation];
      end
      else if Result[mRank].Symbol.SelectionRange.StartPos.Line < mLocation.Symbol.SelectionRange.StartPos.Line then
      begin
        Result[mRank] := mLocation;
      end;
    end;
  finally
    mSeen.Free;
  end;
end;

/// <summary>Sichtbarster Treffer: die eigene Unit vor den Units der uses-Liste (die letzte gewinnt); -1, wenn
/// keiner sichtbar ist.</summary>
function VisibleCandidate(AUnit: TSymbolPathUnit; const ACandidates: TArray<TSymbolLocation>): Integer;
var
  mIndex, mRank, mBestRank: Integer;
begin
  Result := -1;
  mBestRank := -1;
  for mIndex := 0 to High(ACandidates) do
  begin
    if SameText(ACandidates[mIndex].UnitName, AUnit.Data.UnitName) then
    begin
      mRank := MaxInt;
    end
    else
    begin
      mRank := Visible(AUnit, ACandidates[mIndex].UnitName);
    end;
    if mRank > mBestRank then
    begin
      mBestRank := mRank;
      Result := mIndex;
    end;
  end;
end;

function TSymbolPathGraph.ResolveType(AUnit: TSymbolPathUnit; const AName: string): TTypeTarget;
var
  mKey: string;
  mCandidates: TArray<TSymbolLocation>;
  mBest, mNode: Integer;
  mLocation: TSymbolLocation;
begin
  mKey := LowerCase(AUnit.Data.UnitName) + '|' + LowerCase(AName);
  if FTypes.TryGetValue(mKey, Result) then
  begin
    Exit;
  end;
  Result := Default(TTypeTarget);
  mCandidates := TypeCandidates(FTable.Index, AName);
  mBest := VisibleCandidate(AUnit, mCandidates);
  if (mBest < 0) and (Length(mCandidates) = 1) then
  begin
    mBest := 0;
  end;
  if mBest >= 0 then
  begin
    mNode := FTable.NodeOf(mCandidates[mBest]);
    if mNode >= 0 then
    begin
      Result.Nodes := [mNode];
    end;
  end
  else
  begin
    // Ohne sichtbaren Treffer erschlossen (#1119).
    Result.Inferred := Length(mCandidates) > 0;
    for mLocation in mCandidates do
    begin
      mNode := FTable.NodeOf(mLocation);
      if mNode >= 0 then
      begin
        Result.Nodes := Result.Nodes + [mNode];
      end;
    end;
  end;
  FTypes.Add(mKey, Result);
end;

function TSymbolPathGraph.InterfacesOf(ANode: Integer): TArray<Integer>;
var
  mAncestor: string;
  mData: TSymbolPathUnit;
  mNode: Integer;
begin
  Result := nil;
  mData := FTable.NodeUnit(ANode);
  if mData = nil then
  begin
    Exit;
  end;
  for mAncestor in FTable.Node(ANode).Symbol.Ancestors do
  begin
    for mNode in ResolveType(mData, mAncestor).Nodes do
    begin
      if FTable.Node(mNode).Symbol.Kind = TIndexSymbolKind.InterfaceType then
      begin
        Result := Result + [mNode];
      end;
    end;
  end;
end;

/// <summary>ANode steht in ANodes.</summary>
function ContainsNode(ANode: Integer; const ANodes: TArray<Integer>): Boolean;
var
  mNode: Integer;
begin
  for mNode in ANodes do
  begin
    if mNode = ANode then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TSymbolPathGraph.ImplementersOf(ANode: Integer): TArray<Integer>;
var
  mLocation: TSymbolLocation;
  mNode: Integer;
begin
  if FImplementers.TryGetValue(ANode, Result) then
  begin
    Exit;
  end;
  Result := nil;
  for mLocation in FTable.Index.Descendants(FTable.Node(ANode).Symbol.Name) do
  begin
    if mLocation.Symbol.Kind <> TIndexSymbolKind.ClassType then
    begin
      Continue;
    end;
    mNode := FTable.NodeOf(mLocation);
    if (mNode >= 0) and ContainsNode(ANode, InterfacesOf(mNode)) then
    begin
      Result := Result + [mNode];
    end;
  end;
  FImplementers.Add(ANode, Result);
end;

/// <summary>Methodenzuordnung "IFoo.Bar=Baz" für AName des Interfaces AInterface: Baz; '' ohne.</summary>
function ResolvedName(const AResolutions: TArray<string>; const AInterface, AName: string): string;
var
  mResolution, mLeft, mPrefix: string;
  mSeparator: Integer;
begin
  for mResolution in AResolutions do
  begin
    mSeparator := Pos('=', mResolution);
    if mSeparator = 0 then
    begin
      Continue;
    end;
    mLeft := Trim(Copy(mResolution, 1, mSeparator - 1));
    mPrefix := Copy(mLeft, 1, LastDelimiter('.', mLeft) - 1);
    if SameText(TSymbolPathNames.LastSegment(mLeft), AName) and
      SameText(TSymbolPathNames.LastSegment(mPrefix), AInterface) then
    begin
      Exit(Trim(Copy(mResolution, mSeparator + 1, MaxInt)));
    end;
  end;
  Result := '';
end;

function TSymbolPathGraph.ImplementingMember(AClass, AInterface: Integer; const AName: string): Integer;
var
  mResolved: string;
begin
  // Methodenzuordnung IFoo.Bar=Baz geht vor dem gleichnamigen Mitglied.
  mResolved := ResolvedName(FTable.Node(AClass).Symbol.Resolutions, FTable.Node(AInterface).Symbol.Name, AName);
  if mResolved <> '' then
  begin
    Exit(FTable.MemberNamed(AClass, mResolved));
  end;
  Result := FTable.MemberNamed(AClass, AName);
end;

procedure TSymbolPathGraph.AddTypeEdges(AList: TSymbolPathEdgeList; AUnit: TSymbolPathUnit; const ATypeText: string;
  AKind: TSymbolPathEdgeKind; const ANode: TSymbolPathNode);
var
  mName: string;
  mTarget: TTypeTarget;
  mNode: Integer;
begin
  for mName in TSymbolPathNames.TypeNamesIn(ATypeText) do
  begin
    mTarget := ResolveType(AUnit, mName);
    for mNode in mTarget.Nodes do
    begin
      AList.Add(mNode, AKind, mTarget.Inferred, ANode.FileName, ANode.Symbol.SelectionRange.StartPos);
    end;
  end;
end;

procedure TSymbolPathGraph.UsesEdges(const ANode: TSymbolPathNode; AList: TSymbolPathEdgeList);
var
  mGraphNode, mItem: Integer;
  mUses: TUsesEdge;
  mEdge: TSymbolPathEdge;
begin
  if FGraph = nil then
  begin
    Exit;
  end;
  mGraphNode := FGraph.IndexOf(ANode.UnitName);
  if mGraphNode < 0 then
  begin
    Exit;
  end;
  for mItem := 0 to High(FGraph.Node(mGraphNode).Outgoing) do
  begin
    mUses := FGraph.Node(mGraphNode).Outgoing[mItem];
    if not FGraph.Node(mUses.Target).Active then
    begin
      Continue;
    end;
    mEdge := Default(TSymbolPathEdge);
    mEdge.Target := FTable.UnitNode(FGraph.Node(mUses.Target).UnitName);
    mEdge.Kind := TSymbolPathEdgeKind.Uses_;
    mEdge.FileName := ANode.FileName;
    mEdge.HasUsesEdge := True;
    mEdge.UsesEdge := mUses;
    // Reihenfolge im Quelltext wie TUsesGraph.Path.
    mEdge.SortKey := Format('%.6d', [mItem]);
    AList.Add(mEdge);
  end;
end;

procedure TSymbolPathGraph.UnitEdges(const ANode: TSymbolPathNode; AData: TSymbolPathUnit;
  AList: TSymbolPathEdgeList);
var
  mIndex: Integer;
begin
  UsesEdges(ANode, AList);
  for mIndex in AData.MembersOf('') do
  begin
    AList.Add(FTable.SymbolNode(AData, mIndex), TSymbolPathEdgeKind.Contains, False,
      AData.Data.SymbolFile(AData.Data.Symbols[mIndex]), AData.Data.Symbols[mIndex].SelectionRange.StartPos);
  end;
end;

procedure TSymbolPathGraph.StructEdges(ANode: Integer; AData: TSymbolPathUnit; AList: TSymbolPathEdgeList);
var
  mNode: TSymbolPathNode;
  mAncestor: string;
  mResolved: TTypeTarget;
  mTarget, mIndex: Integer;
  mImplementers: TArray<Integer>;
  mMember: TIndexSymbol;
  mKind: TSymbolPathEdgeKind;
begin
  mNode := FTable.Node(ANode);
  for mAncestor in mNode.Symbol.Ancestors do
  begin
    mResolved := ResolveType(AData, mAncestor);
    for mTarget in mResolved.Nodes do
    begin
      mKind := TSymbolPathEdgeKind.Inherits;
      if (FTable.Node(mTarget).Symbol.Kind = TIndexSymbolKind.InterfaceType) and
        (mNode.Symbol.Kind <> TIndexSymbolKind.InterfaceType) then
      begin
        mKind := TSymbolPathEdgeKind.Implements;
      end;
      AList.Add(mTarget, mKind, mResolved.Inferred, mNode.FileName, mNode.Symbol.SelectionRange.StartPos);
    end;
  end;
  if mNode.Symbol.Kind = TIndexSymbolKind.InterfaceType then
  begin
    mImplementers := ImplementersOf(ANode);
    for mTarget in mImplementers do
    begin
      AList.AddReverse(mTarget, Length(mImplementers) > 1);
    end;
  end;
  for mIndex in AData.MembersOf(mNode.Symbol.Name) do
  begin
    mMember := AData.Data.Symbols[mIndex];
    AList.Add(FTable.SymbolNode(AData, mIndex), TSymbolPathEdgeKind.Contains, False, AData.Data.SymbolFile(mMember),
      mMember.SelectionRange.StartPos);
    if mMember.Kind in [TIndexSymbolKind.Field, TIndexSymbolKind.Property_] then
    begin
      AddTypeEdges(AList, AData, mMember.TypeName + ' ' + mMember.TypeArgs, TSymbolPathEdgeKind.HasField,
        FTable.Node(FTable.SymbolNode(AData, mIndex)));
    end;
  end;
end;

procedure TSymbolPathGraph.InterfaceMethodEdges(const ANode: TSymbolPathNode; AContainer: Integer;
  AList: TSymbolPathEdgeList);
var
  mMatches: TArray<Integer>;
  mTarget, mIndex: Integer;
begin
  // Interface-Methode → Methoden der umsetzenden Klassen; mehrere Umsetzungen sind erschlossen.
  mMatches := nil;
  for mTarget in ImplementersOf(AContainer) do
  begin
    mIndex := ImplementingMember(mTarget, AContainer, ANode.Symbol.Name);
    if mIndex >= 0 then
    begin
      mMatches := mMatches + [mIndex];
    end;
  end;
  for mTarget in mMatches do
  begin
    AList.AddReverse(mTarget, Length(mMatches) > 1);
  end;
end;

procedure TSymbolPathGraph.ClassMethodEdges(ANode, AContainer: Integer; AList: TSymbolPathEdgeList);
var
  mNode: TSymbolPathNode;
  mTarget, mIndex: Integer;
begin
  mNode := FTable.Node(ANode);
  for mTarget in InterfacesOf(AContainer) do
  begin
    // Klassenmethode → Interface-Methode, die sie umsetzt.
    mIndex := FTable.MemberNamed(mTarget, mNode.Symbol.Name);
    if (mIndex >= 0) and (ImplementingMember(AContainer, mTarget, FTable.Node(mIndex).Symbol.Name) = ANode) then
    begin
      AList.Add(mIndex, TSymbolPathEdgeKind.Implements, False, mNode.FileName, mNode.Symbol.SelectionRange.StartPos);
    end;
  end;
end;

procedure TSymbolPathGraph.RoutineEdges(ANode: Integer; AData: TSymbolPathUnit; AList: TSymbolPathEdgeList);
var
  mNode: TSymbolPathNode;
  mParamType: string;
  mContainer: Integer;
begin
  mNode := FTable.Node(ANode);
  for mParamType in mNode.Symbol.ParamTypes do
  begin
    AddTypeEdges(AList, AData, mParamType, TSymbolPathEdgeKind.Parameter, mNode);
  end;
  if mNode.Symbol.TypeName <> '' then
  begin
    AddTypeEdges(AList, AData, mNode.Symbol.TypeName + ' ' + mNode.Symbol.TypeArgs, TSymbolPathEdgeKind.Result_,
      mNode);
  end;
  mContainer := FTable.ContainerNode(AData, mNode.Symbol);
  if mContainer < 0 then
  begin
    Exit;
  end;
  if FTable.Node(mContainer).Symbol.Kind = TIndexSymbolKind.InterfaceType then
  begin
    InterfaceMethodEdges(mNode, mContainer, AList);
  end
  else
  begin
    ClassMethodEdges(ANode, mContainer, AList);
  end;
end;

function TSymbolPathGraph.BuildForward(ANode: Integer): TSymbolPathEdges;
var
  mList: TSymbolPathEdgeList;
  mNode: TSymbolPathNode;
  mData: TSymbolPathUnit;
begin
  mNode := FTable.Node(ANode);
  mData := FTable.UnitFor(mNode.UnitName);
  if mData = nil then
  begin
    Exit(nil);
  end;
  mList := TSymbolPathEdgeList.Create(FTable);
  try
    if mNode.IsUnit then
    begin
      UnitEdges(mNode, mData, mList);
    end
    else
    begin
      if mNode.Symbol.Kind in cSymbolPathStructKinds then
      begin
        StructEdges(ANode, mData, mList);
      end;
      if mNode.Symbol.Kind in cSymbolPathValueKinds then
      begin
        AddTypeEdges(mList, mData, mNode.Symbol.TypeName + ' ' + mNode.Symbol.TypeArgs, TSymbolPathEdgeKind.HasField,
          mNode);
      end;
      if mNode.Symbol.Kind in cSymbolPathRoutineKinds then
      begin
        RoutineEdges(ANode, mData, mList);
      end;
    end;
    Result := mList.ToArray;
  finally
    mList.Free;
  end;
end;

function TSymbolPathGraph.ForwardOf(ANode: Integer): TSymbolPathEdges;
begin
  if not FForward.TryGetValue(ANode, Result) then
  begin
    Result := BuildForward(ANode);
    FForward.Add(ANode, Result);
  end;
end;

function TSymbolPathGraph.Leads(ASource, ATarget: Integer): Boolean;
var
  mEdge: TSymbolPathEdge;
begin
  for mEdge in ForwardOf(ASource) do
  begin
    if (mEdge.Target = ATarget) and (mEdge.Kind in FVia) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TSymbolPathGraph.AddRef(const AName, AUnitName: string; AIndex: Integer);
var
  mKey: string;
  mList: TRefList;
  mRef: TSymbolRef;
begin
  mKey := UpperCase(TSymbolPathNames.LastSegment(AName));
  if not FRefs.TryGetValue(mKey, mList) then
  begin
    mList := TRefList.Create;
    FRefs.Add(mKey, mList);
  end;
  mRef.UnitName := AUnitName;
  mRef.Index := AIndex;
  mList.Add(mRef);
end;

/// <summary>Typangaben einer Deklaration: Typ samt Typargumenten und bei Routinen die Parametertypen.</summary>
function TypeTexts(const ASymbol: TIndexSymbol): TArray<string>;
begin
  Result := [ASymbol.TypeName + ' ' + ASymbol.TypeArgs];
  if ASymbol.Kind in cSymbolPathRoutineKinds then
  begin
    Result := Result + ASymbol.ParamTypes;
  end;
end;

procedure TSymbolPathGraph.AddUnitRefs(const AItem: TUnitIndex);
var
  mIndex: Integer;
  mText, mName: string;
begin
  for mIndex := 0 to High(AItem.Symbols) do
  begin
    if not (AItem.Symbols[mIndex].Kind in cSymbolPathValueKinds + cSymbolPathRoutineKinds) then
    begin
      Continue;
    end;
    for mText in TypeTexts(AItem.Symbols[mIndex]) do
    begin
      for mName in TSymbolPathNames.TypeNamesIn(mText) do
      begin
        AddRef(mName, AItem.UnitName, mIndex);
      end;
    end;
  end;
end;

procedure TSymbolPathGraph.BuildRefs;
var
  mItem: TUnitIndex;
  mScope: TDictionary<string, Boolean>;
  mEndpoint: Integer;
begin
  FRefs := TObjectDictionary<string, TRefList>.Create([doOwnsValues]);
  // Bibliotheks-Units nur als Durchgang mit ThroughLibrary; Start und Ziel immer.
  mScope := TDictionary<string, Boolean>.Create;
  try
    for mEndpoint in FEndpoints.Keys do
    begin
      mScope.AddOrSetValue(LowerCase(FTable.Node(mEndpoint).UnitName), True);
    end;
    for mItem in FTable.Index.Units do
    begin
      if not mItem.Library_ or FThroughLibrary or mScope.ContainsKey(LowerCase(mItem.UnitName)) then
      begin
        AddUnitRefs(mItem);
      end;
    end;
  finally
    mScope.Free;
  end;
end;

procedure TSymbolPathGraph.UnitPredecessors(const ANode: TSymbolPathNode; ACandidates: TList<Integer>);
var
  mGraphNode, mSource: Integer;
begin
  if FGraph = nil then
  begin
    Exit;
  end;
  mGraphNode := FGraph.IndexOf(ANode.UnitName);
  if mGraphNode < 0 then
  begin
    Exit;
  end;
  for mSource in FGraph.DirectDependents(mGraphNode, cAllUsesSections) do
  begin
    ACandidates.Add(FTable.UnitNode(FGraph.Node(mSource).UnitName));
  end;
end;

procedure TSymbolPathGraph.StructPredecessors(const ANode: TSymbolPathNode; AData: TSymbolPathUnit;
  ACandidates: TList<Integer>);
var
  mLocation: TSymbolLocation;
  mAncestor: string;
  mCandidate: Integer;
begin
  // inherits und implements Klasse → Interface
  for mLocation in FTable.Index.Descendants(ANode.Symbol.Name) do
  begin
    ACandidates.Add(FTable.NodeOf(mLocation));
  end;
  // implements Interface → Klasse: die Interfaces dieser Klasse
  for mAncestor in ANode.Symbol.Ancestors do
  begin
    for mCandidate in ResolveType(AData, mAncestor).Nodes do
    begin
      ACandidates.Add(mCandidate);
    end;
  end;
end;

procedure TSymbolPathGraph.TypeRefPredecessors(const ANode: TSymbolPathNode; ACandidates: TList<Integer>);
var
  mRefs: TRefList;
  mRef: TSymbolRef;
  mRefUnit: TSymbolPathUnit;
  mCandidate: Integer;
begin
  // hasField, parameter, result: Deklarationen, deren Typangabe den Namen nennt, und ihre Typen
  if FRefs = nil then
  begin
    BuildRefs;
  end;
  if not FRefs.TryGetValue(UpperCase(ANode.Symbol.Name), mRefs) then
  begin
    Exit;
  end;
  for mRef in mRefs do
  begin
    mRefUnit := FTable.UnitFor(mRef.UnitName);
    if mRefUnit = nil then
    begin
      Continue;
    end;
    mCandidate := FTable.SymbolNode(mRefUnit, mRef.Index);
    ACandidates.Add(mCandidate);
    if FTable.Node(mCandidate).Symbol.Kind in [TIndexSymbolKind.Field, TIndexSymbolKind.Property_] then
    begin
      ACandidates.Add(FTable.ContainerNode(mRefUnit, FTable.Node(mCandidate).Symbol));
    end;
  end;
end;

procedure TSymbolPathGraph.RoutinePredecessors(ANode: Integer; AData: TSymbolPathUnit; ACandidates: TList<Integer>);
var
  mEdge: TSymbolPathEdge;
  mContainer, mCandidate: Integer;
begin
  // implements je Methode ist in beide Richtungen angelegt.
  for mEdge in ForwardOf(ANode) do
  begin
    if mEdge.Kind = TSymbolPathEdgeKind.Implements then
    begin
      ACandidates.Add(mEdge.Target);
    end;
  end;
  mContainer := FTable.ContainerNode(AData, FTable.Node(ANode).Symbol);
  if mContainer < 0 then
  begin
    Exit;
  end;
  for mCandidate in InterfacesOf(mContainer) do
  begin
    ACandidates.Add(FTable.MemberNamed(mCandidate, FTable.Node(ANode).Symbol.Name));
  end;
end;

procedure TSymbolPathGraph.SymbolPredecessors(ANode: Integer; AData: TSymbolPathUnit; ACandidates: TList<Integer>);
var
  mNode: TSymbolPathNode;
begin
  mNode := FTable.Node(ANode);
  // contains
  if mNode.Symbol.Container = '' then
  begin
    ACandidates.Add(FTable.UnitNode(mNode.UnitName));
  end
  else
  begin
    ACandidates.Add(FTable.ContainerNode(AData, mNode.Symbol));
  end;
  if mNode.Symbol.Kind in cSymbolPathStructKinds then
  begin
    StructPredecessors(mNode, AData, ACandidates);
  end;
  if mNode.Symbol.Kind in cSymbolPathTypeKinds then
  begin
    TypeRefPredecessors(mNode, ACandidates);
  end;
  if mNode.Symbol.Kind in cSymbolPathRoutineKinds then
  begin
    RoutinePredecessors(ANode, AData, ACandidates);
  end;
end;

function TSymbolPathGraph.ConfirmedPredecessors(ANode: Integer; ACandidates: TList<Integer>): TArray<Integer>;
var
  mSeen: TDictionary<Integer, Boolean>;
  mCandidate: Integer;
begin
  Result := nil;
  mSeen := TDictionary<Integer, Boolean>.Create;
  try
    for mCandidate in ACandidates do
    begin
      if (mCandidate < 0) or (mCandidate = ANode) or mSeen.ContainsKey(mCandidate) then
      begin
        Continue;
      end;
      mSeen.Add(mCandidate, True);
      if Passable(mCandidate) and Leads(mCandidate, ANode) then
      begin
        Result := Result + [mCandidate];
      end;
    end;
  finally
    mSeen.Free;
  end;
end;

function TSymbolPathGraph.PredecessorsOf(ANode: Integer): TArray<Integer>;
var
  mCandidates: TList<Integer>;
  mNode: TSymbolPathNode;
  mData: TSymbolPathUnit;
begin
  if FPredecessors.TryGetValue(ANode, Result) then
  begin
    Exit;
  end;
  mNode := FTable.Node(ANode);
  mData := FTable.UnitFor(mNode.UnitName);
  mCandidates := TList<Integer>.Create;
  try
    if mNode.IsUnit then
    begin
      UnitPredecessors(mNode, mCandidates);
    end
    else if mData <> nil then
    begin
      SymbolPredecessors(ANode, mData, mCandidates);
    end;
    // Nur, was wirklich eine Kante hierher hat (gleiche Kanten wie vorwärts).
    Result := ConfirmedPredecessors(ANode, mCandidates);
  finally
    mCandidates.Free;
  end;
  FPredecessors.Add(ANode, Result);
end;

end.
