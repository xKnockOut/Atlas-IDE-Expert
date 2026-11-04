unit Atlas.Common.Architecture.SymbolPath.Calls;

// Aufrufkanten der Pfadsuche zwischen Symbolen (#1117), ausgelagert aus
// Atlas.Common.Architecture.SymbolPath.
//
// - Vorwärts aus dem Rumpf einer Routine über TLspHierarchies.OutgoingCalls
//   (wie get_call_hierarchy).
// - Rückwärts nur aus Units, deren Verwendungsindex (#492) den Namen enthält;
//   ohne Verwendungsindex jede Unit, die die Unit der Routine verwendet.
//   Kandidaten zählen nur mit einer Kante hierher (aus dem Index oder ein
//   Aufruf).
// - Abgebrochene Rückwärtssuchen werden nicht zwischengespeichert.

interface

uses
  System.Generics.Collections,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Architecture.SymbolPath.Nodes,
  Atlas.Common.Architecture.SymbolPath.Graph;

type
  TSymbolPathCalls = class
  private
    FTable: TSymbolPathNodeTable;
    FGraph: TSymbolPathGraph;
    FReadText: TSymbolPathReadText;
    FEnsureUnit: TEnsureUnitFunc;
    FNamespaces: TArray<string>;
    FResolver: TNameResolver;
    FCalls: TDictionary<Integer, TSymbolPathEdges>;
    FCallers: TDictionary<Integer, TArray<Integer>>;
    FStopped: TSymbolPathCancelled;
    function Resolver: TNameResolver;
    function BuildCalls(ANode: Integer; AData: TSymbolPathUnit): TSymbolPathEdges;
    /// <summary>Routinen aus AData mit einer Kante nach ANode, an AResult angehängt.</summary>
    procedure CallersIn(AData: TSymbolPathUnit; ANode: Integer; var AResult: TArray<Integer>);
    function IsStopped: Boolean;
    /// <summary>Alle Units nach Aufrufern von ANode durchsuchen; True, wenn die Suche abgebrochen wurde.</summary>
    function ScanCallers(ANode: Integer; var AResult: TArray<Integer>): Boolean;
  public
    /// <summary>ATable und AGraph gehören dem Aufrufer.</summary>
    constructor Create(ATable: TSymbolPathNodeTable; AGraph: TSymbolPathGraph; const AReadText: TSymbolPathReadText;
      const AEnsureUnit: TEnsureUnitFunc; const ANamespaces: TArray<string>);
    destructor Destroy; override;
    /// <summary>Aufrufkanten aus dem Rumpf der Routine ANode, sortiert.</summary>
    function CallsOf(ANode: Integer): TSymbolPathEdges;
    /// <summary>Routinen, die ANode aufrufen oder eine erlaubte Kante dorthin haben.</summary>
    function CallersOf(ANode: Integer): TArray<Integer>;
    /// <summary>ASource hat eine erlaubte Kante oder einen Aufruf nach ATarget.</summary>
    function Leads(ASource, ATarget: Integer): Boolean;
    /// <summary>Abbruchprüfung der laufenden Suche; nil = nie.</summary>
    property Stopped: TSymbolPathCancelled read FStopped write FStopped;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Lsp.References,
  Atlas.Common.Lsp.Hierarchies;

constructor TSymbolPathCalls.Create(ATable: TSymbolPathNodeTable; AGraph: TSymbolPathGraph;
  const AReadText: TSymbolPathReadText; const AEnsureUnit: TEnsureUnitFunc; const ANamespaces: TArray<string>);
begin
  inherited Create;
  FTable := ATable;
  FGraph := AGraph;
  FReadText := AReadText;
  FEnsureUnit := AEnsureUnit;
  FNamespaces := ANamespaces;
  FCalls := TDictionary<Integer, TSymbolPathEdges>.Create;
  FCallers := TDictionary<Integer, TArray<Integer>>.Create;
end;

destructor TSymbolPathCalls.Destroy;
begin
  FCallers.Free;
  FCalls.Free;
  FResolver.Free;
  inherited;
end;

function TSymbolPathCalls.IsStopped: Boolean;
begin
  Result := Assigned(FStopped) and FStopped();
end;

function TSymbolPathCalls.Resolver: TNameResolver;
begin
  if FResolver = nil then
  begin
    FResolver := TNameResolver.Create(FTable.Index, FEnsureUnit);
    FResolver.Namespaces := FNamespaces;
  end;
  Result := FResolver;
end;

/// <summary>Eintrag der Aufrufhierarchie für die Routine ANode aus AData.</summary>
function HierarchyItemOf(const ANode: TSymbolPathNode; AData: TSymbolPathUnit): THierarchyItem;
begin
  Result := Default(THierarchyItem);
  Result.Name := ANode.Symbol.Name;
  Result.Container := ANode.Symbol.Container;
  Result.SymbolKind := ANode.Symbol.Kind;
  Result.UnitName := ANode.UnitName;
  // Der Rumpf steht in der Datei der Unit, auch wenn die Deklaration aus einer Include-Datei kommt.
  Result.FileName := AData.Data.FileName;
  Result.Range := ANode.Symbol.Range;
  Result.SelectionRange := ANode.Symbol.SelectionRange;
end;

/// <summary>Leser für OutgoingCalls; als typisierte Variable, weil OutgoingCalls überladen ist.</summary>
function ReaderOf(const AReadText: TSymbolPathReadText): TReferenceReadText;
begin
  Result :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := AReadText(AFileName, AText);
    end;
end;

/// <summary>Knoten der aufgerufenen Routine ACall; -1 ohne.</summary>
function CalleeNode(ATable: TSymbolPathNodeTable; const ACall: THierarchyCall): Integer;
var
  mCalleeUnit: TSymbolPathUnit;
  mLocation: TSymbolLocation;
begin
  Result := -1;
  mCalleeUnit := ATable.UnitFor(ACall.Item.UnitName);
  if mCalleeUnit = nil then
  begin
    Exit;
  end;
  mLocation.UnitName := mCalleeUnit.Data.UnitName;
  mLocation.FileName := mCalleeUnit.Data.FileName;
  mLocation.Symbol := Default(TIndexSymbol);
  mLocation.Symbol.Name := ACall.Item.Name;
  mLocation.Symbol.Container := ACall.Item.Container;
  mLocation.Symbol.SelectionRange := ACall.Item.SelectionRange;
  Result := ATable.NodeOf(mLocation);
end;

function TSymbolPathCalls.BuildCalls(ANode: Integer; AData: TSymbolPathUnit): TSymbolPathEdges;
var
  mItem: THierarchyItem;
  mCall: THierarchyCall;
  mList: TSymbolPathEdgeList;
  mTarget: Integer;
begin
  mItem := HierarchyItemOf(FTable.Node(ANode), AData);
  mList := TSymbolPathEdgeList.Create(FTable);
  try
    for mCall in TLspHierarchies.OutgoingCalls(Resolver, mItem, ReaderOf(FReadText)) do
    begin
      mTarget := CalleeNode(FTable, mCall);
      if (mTarget >= 0) and (mTarget <> ANode) and (Length(mCall.Ranges) > 0) then
      begin
        mList.Add(mTarget, TSymbolPathEdgeKind.Calls, False, mItem.FileName, mCall.Ranges[0].StartPos);
      end;
    end;
    Result := mList.ToArray;
  finally
    mList.Free;
  end;
end;

function TSymbolPathCalls.CallsOf(ANode: Integer): TSymbolPathEdges;
var
  mNode: TSymbolPathNode;
  mData: TSymbolPathUnit;
begin
  if FCalls.TryGetValue(ANode, Result) then
  begin
    Exit;
  end;
  Result := nil;
  mNode := FTable.Node(ANode);
  mData := FTable.UnitFor(mNode.UnitName);
  if not mNode.IsUnit and (mNode.Symbol.Kind in SymbolPathRoutineKinds) and (mData <> nil) and
    Assigned(FReadText) then
  begin
    Result := BuildCalls(ANode, mData);
  end;
  FCalls.Add(ANode, Result);
end;

function TSymbolPathCalls.Leads(ASource, ATarget: Integer): Boolean;
var
  mEdge: TSymbolPathEdge;
begin
  if FGraph.Leads(ASource, ATarget) then
  begin
    Exit(True);
  end;
  for mEdge in CallsOf(ASource) do
  begin
    if mEdge.Target = ATarget then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function HasUsage(const AUnit: TUnitIndex; const AName: string): Boolean;
var
  mUsage: TIndexUsage;
begin
  for mUsage in AUnit.Usages do
  begin
    if SameText(mUsage.Name, AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>AItem kann die Routine ANode aufrufen. Verwendungsindex (#492) als Vorfilter; ohne ihn jede Unit, die
/// die Unit der Routine verwendet.</summary>
function MayCall(const AItem: TUnitIndex; const ANode: TSymbolPathNode): Boolean;
var
  mName: string;
begin
  if AItem.UsagesIndexed and not AItem.UsagesOffloaded then
  begin
    Exit(HasUsage(AItem, ANode.Symbol.Name));
  end;
  Result := SameText(AItem.UnitName, ANode.UnitName);
  for mName in AItem.InterfaceUses + AItem.ImplementationUses do
  begin
    if TSymbolPathNames.UsesMatches(mName, ANode.UnitName) then
    begin
      Result := True;
    end;
  end;
end;

procedure TSymbolPathCalls.CallersIn(AData: TSymbolPathUnit; ANode: Integer; var AResult: TArray<Integer>);
var
  mIndex, mCandidate: Integer;
begin
  for mIndex := 0 to High(AData.Data.Symbols) do
  begin
    if not (AData.Data.Symbols[mIndex].Kind in SymbolPathRoutineKinds) then
    begin
      Continue;
    end;
    mCandidate := FTable.SymbolNode(AData, mIndex);
    if (mCandidate <> ANode) and FGraph.Passable(mCandidate) and Leads(mCandidate, ANode) then
    begin
      AResult := AResult + [mCandidate];
    end;
  end;
end;

function TSymbolPathCalls.ScanCallers(ANode: Integer; var AResult: TArray<Integer>): Boolean;
var
  mNode: TSymbolPathNode;
  mItem: TUnitIndex;
  mData: TSymbolPathUnit;
begin
  mNode := FTable.Node(ANode);
  for mItem in FTable.Index.Units do
  begin
    if IsStopped then
    begin
      Exit(True);
    end;
    if (mItem.Library_ and not FGraph.ThroughLibrary) or not MayCall(mItem, mNode) then
    begin
      Continue;
    end;
    mData := FTable.UnitFor(mItem.UnitName);
    if mData <> nil then
    begin
      CallersIn(mData, ANode, AResult);
    end;
  end;
  Result := False;
end;

function TSymbolPathCalls.CallersOf(ANode: Integer): TArray<Integer>;
var
  mNode: TSymbolPathNode;
  mStopped: Boolean;
begin
  if FCallers.TryGetValue(ANode, Result) then
  begin
    Exit;
  end;
  Result := nil;
  mNode := FTable.Node(ANode);
  mStopped := False;
  if not mNode.IsUnit and (mNode.Symbol.Kind in SymbolPathRoutineKinds) then
  begin
    mStopped := ScanCallers(ANode, Result);
  end;
  // Abgebrochen: nicht zwischenspeichern, die Liste ist unvollständig.
  if not mStopped then
  begin
    FCallers.Add(ANode, Result);
  end;
end;

end.
