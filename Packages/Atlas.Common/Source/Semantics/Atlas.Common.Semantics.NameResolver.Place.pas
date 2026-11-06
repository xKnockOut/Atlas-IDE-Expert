unit Atlas.Common.Semantics.NameResolver.Place;

// Stelle der Namensauflösung: Baum, Position, aktuelle Unit und Abschnitt (interface bzw. implementation),
// dazu die mit PinTree vorab ausgewerteten Bäume und die Wege vom Cursor nach außen (umgebende Routinen,
// with-Anweisungen, Property-Deklaration). Alle Teile von TNameResolver lesen hier, wo sie gerade suchen.

interface

uses
  System.Generics.Collections,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.Contract;

type
  TResolverPlace = class
  private type
    /// <summary>Mit PinTree vorab ausgewerteter Baum (Code-Review P-01/P-02).</summary>
    TPin = record
      Tree: TSyntaxTree;
      FileName: string;
      /// <summary>Nur aus dem Baum, wie TIndexExtractor.Extract (ohne Include-Symbole).</summary>
      Extracted: TUnitIndex;
      /// <summary>Wie TreeUnit: mit den Symbolen der Include-Dateien und Namenstabelle.</summary>
      Merged: TUnitIndex;
      /// <summary>Zahl der noch offenen PinTree-Aufrufe für diesen Baum.</summary>
      Depth: Integer;
    end;
    /// <summary>Ein offener PinTree-Aufruf; UnpinTree löst den zuletzt gesetzten.</summary>
    TPinCall = record
      Tree: TSyntaxTree;
      FileName: string;
    end;
  private
    FIndex: ISymbolIndex;
    // Auswertung des geprüften Baums, geteilt mit den anderen Resolvern des Laufs (#1322); nil = selbst auswerten.
    FTreeUnits: ITreeUnits;
    FTree: TSyntaxTree;
    FCurrent: TUnitIndex;
    // Woher FCurrent stammt: Platz in FPins und Baum; -1 = anders gesetzt (TreeUnit, …From). MoveTo lässt
    // FCurrent dann stehen, statt die Unit je Aufruf neu zu kopieren.
    FCurrentPin: Integer;
    FCurrentTree: TSyntaxTree;
    FOffset: Integer;
    FInImplementation: Boolean;
    FInferDepth: Integer;
    // Mit PinTree vorab ausgewertete Bäume als Stapel (verschachtelt, LIFO), für viele Aufrufe auf
    // demselben Baum.
    FPins: TList<TPin>;
    FPinCalls: TList<TPinCall>;
    // Baum, an dem die baumbezogenen Zwischenspeicher hängen (Helfer, Vorfahren), und Zähler, der bei jedem
    // Wechsel dieses Baums steigt; MoveCount steigt bei jedem Ortswechsel.
    FCacheTree: TSyntaxTree;
    FCacheEpoch: Integer;
    FMoveCount: Integer;
    /// <summary>Position von (ATree, AFileName) in FPins; -1, wenn nicht gepinnt.</summary>
    function PinnedIndex(ATree: TSyntaxTree; const AFileName: string): Integer;
    /// <summary>Unit aus dem Baum samt der Symbole ihrer $I-Dateien aus dem Index (#500).</summary>
    function TreeUnit(ATree: TSyntaxTree; const AFileName: string): TUnitIndex;
    /// <summary>AExtracted samt der Symbole ihrer $I-Dateien aus dem Index (#500), mit Namenstabelle.</summary>
    function MergedUnit(const AExtracted: TUnitIndex; const AFileName: string): TUnitIndex;
    /// <summary>Setzt FCurrent auf die Unit von ATree, aus dem Pin, wenn es einen gibt.</summary>
    procedure TakeUnit(ATree: TSyntaxTree; const AFileName: string);
  public
    constructor Create(const AIndex: ISymbolIndex; const ATreeUnits: ITreeUnits);
    destructor Destroy; override;
    /// <summary>Bereitet die Auflösung an AOffset in ATree vor: Baum, Position, Unit und Abschnitt.</summary>
    procedure MoveTo(ATree: TSyntaxTree; const AFileName: string; AOffset: Integer);
    /// <summary>Auflösung so, wie sie in AUnit stünde, ohne Baum (ResolveTypeFrom und Verwandte).</summary>
    procedure MoveToUnit(const AUnit: TUnitIndex);
    /// <summary>Wertet ATree einmal aus und nutzt das für alle folgenden Aufrufe mit demselben Baum, bis
    /// UnpinTree (siehe TNameResolver.PinTree).</summary>
    procedure PinTree(ATree: TSyntaxTree; const AFileName: string);
    /// <summary>Löst das zuletzt gesetzte PinTree; ohne gepinnten Baum wirkungslos.</summary>
    procedure UnpinTree;
    /// <summary>Unit-Index nur aus ATree (ohne Include-Symbole), wie TIndexExtractor.Extract; bei gepinntem
    /// Baum ohne neue Auswertung.</summary>
    function ExtractedUnit(ATree: TSyntaxTree; const AFileName: string): TUnitIndex;
    /// <summary>Routinen um die Stelle, innerste zuerst; anonyme Methoden zählen mit.</summary>
    function EnclosingRoutines: TArray<TSyntaxNode>;
    /// <summary>with-Anweisungen, in deren Rumpf die Stelle liegt, innerste zuerst.</summary>
    function EnclosingWiths: TArray<TSyntaxNode>;
    /// <summary>Qualifizierter Name des Typs, wenn die Stelle in einer Property-Deklaration steht; sonst ''.
    /// </summary>
    function PropertyClassName: string;
    /// <summary>Liegt ein Knoten in der aktuellen Unit (gleiche Datei)?</summary>
    function IsCurrentFile(const AFileName: string): Boolean;
    property Index: ISymbolIndex read FIndex;
    property Tree: TSyntaxTree read FTree write FTree;
    property Current: TUnitIndex read FCurrent;
    property Offset: Integer read FOffset write FOffset;
    property InImplementation: Boolean read FInImplementation;
    /// <summary>Schachtelung beim Ableiten von Typen aus Ausdrücken; MoveTo setzt sie zurück.</summary>
    property InferDepth: Integer read FInferDepth write FInferDepth;
    /// <summary>Steigt, wenn die baumbezogenen Zwischenspeicher (Helfer, Vorfahren) nicht mehr gelten.</summary>
    property CacheEpoch: Integer read FCacheEpoch;
    /// <summary>Steigt bei jedem MoveTo und MoveToUnit: Die Klasse der umgebenden Methode gilt dann neu.</summary>
    property MoveCount: Integer read FMoveCount;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Semantics.TreeUnits,
  Atlas.Common.Semantics.NameResolver.Symbols;

constructor TResolverPlace.Create(const AIndex: ISymbolIndex; const ATreeUnits: ITreeUnits);
begin
  inherited Create;
  FIndex := AIndex;
  FTreeUnits := ATreeUnits;
  FCurrentPin := -1;
  FPins := TList<TPin>.Create;
  FPinCalls := TList<TPinCall>.Create;
end;

destructor TResolverPlace.Destroy;
begin
  FPinCalls.Free;
  FPins.Free;
  inherited;
end;

function TResolverPlace.PinnedIndex(ATree: TSyntaxTree; const AFileName: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := FPins.Count - 1 downto 0 do
  begin
    if (FPins[mIndex].Tree = ATree) and SameText(FPins[mIndex].FileName, AFileName) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

function TResolverPlace.TreeUnit(ATree: TSyntaxTree; const AFileName: string): TUnitIndex;
begin
  if (FTreeUnits <> nil) and FTreeUnits.Holds(ATree) then
  begin
    Result := FTreeUnits.Merged(FIndex, AFileName);
  end
  else
  begin
    Result := MergedUnit(TTreeExtracts.ForTree(ATree).Extracted(AFileName), AFileName);
  end;
end;

function TResolverPlace.MergedUnit(const AExtracted: TUnitIndex; const AFileName: string): TUnitIndex;
begin
  Result := TTreeUnits.Merge(FIndex, AExtracted, AFileName);
end;

procedure TResolverPlace.TakeUnit(ATree: TSyntaxTree; const AFileName: string);
var
  mPinIndex: Integer;
begin
  mPinIndex := PinnedIndex(ATree, AFileName);
  // Jeder Aufruf von Resolve/NodeType kommt hierher: FCurrent nur neu setzen, wenn Baum oder Pin wechseln. Vorher
  // kopierte jeder Aufruf den Pin samt zwei TUnitIndex (FPins[…]) und dann die Unit (laut Stichproben teuer).
  if mPinIndex < 0 then
  begin
    FCurrent := TreeUnit(ATree, AFileName);
    FCurrentPin := -1;
  end
  else if (mPinIndex <> FCurrentPin) or (ATree <> FCurrentTree) then
  begin
    FCurrent := FPins.List[mPinIndex].Merged;
    FCurrentPin := mPinIndex;
    FCurrentTree := ATree;
  end;
end;

procedure TResolverPlace.MoveTo(ATree: TSyntaxTree; const AFileName: string; AOffset: Integer);
var
  mSection: TSyntaxNode;
begin
  FTree := ATree;
  FOffset := AOffset;
  FInferDepth := 0;
  Inc(FMoveCount);
  TakeUnit(ATree, AFileName);
  // Helfer hängen an der Unit und ihren uses; je Baum neu bestimmen.
  if ATree <> FCacheTree then
  begin
    Inc(FCacheEpoch);
    FCacheTree := ATree;
  end;
  mSection := ATree.Root.FindChild(TSyntaxKind.InterfaceSection);
  // Programme haben keinen interface-Teil: alles ist "implementation".
  FInImplementation := (mSection = nil) or not TResolverNodes.Contains(mSection, AOffset);
end;

procedure TResolverPlace.MoveToUnit(const AUnit: TUnitIndex);
begin
  FTree := nil;
  FOffset := 0;
  FCurrent := AUnit;
  FCurrentPin := -1;
  FInImplementation := True;
  Inc(FMoveCount);
  // Helfer- und Vorfahren-Cache bleiben (Code-Review P-17): Ihre Schlüssel enthalten Unit und Abschnitt.
end;

procedure TResolverPlace.PinTree(ATree: TSyntaxTree; const AFileName: string);
var
  mPin: TPin;
  mCall: TPinCall;
  mPinIndex: Integer;
begin
  // Verschachtelt (Code-Review P-01/P-02): Handle pinnt, Collect pinnt denselben Baum erneut, Find pinnt
  // Fremdbäume. Derselbe Baum zählt nur hoch und wird nicht erneut ausgewertet.
  mCall.Tree := ATree;
  mCall.FileName := AFileName;
  FPinCalls.Add(mCall);
  mPinIndex := PinnedIndex(ATree, AFileName);
  if mPinIndex >= 0 then
  begin
    // Im Array zählen statt den Pin samt zwei TUnitIndex hin und her zu kopieren (jede Regel pinnt erneut).
    Inc(FPins.List[mPinIndex].Depth);
    Exit;
  end;
  mPin := Default(TPin);
  mPin.Tree := ATree;
  mPin.FileName := AFileName;
  if (FTreeUnits <> nil) and FTreeUnits.Holds(ATree) then
  begin
    mPin.Extracted := FTreeUnits.Extracted(AFileName);
    mPin.Merged := FTreeUnits.Merged(FIndex, AFileName);
  end
  else
  begin
    mPin.Extracted := TTreeExtracts.ForTree(ATree).Extracted(AFileName);
    mPin.Merged := MergedUnit(mPin.Extracted, AFileName);
  end;
  mPin.Depth := 1;
  FPins.Add(mPin);
end;

procedure TResolverPlace.UnpinTree;
var
  mPin: TPin;
  mCall: TPinCall;
  mPinIndex: Integer;
begin
  if FPinCalls.Count = 0 then
  begin
    Exit;
  end;
  mCall := FPinCalls[FPinCalls.Count - 1];
  FPinCalls.Delete(FPinCalls.Count - 1);
  mPinIndex := PinnedIndex(mCall.Tree, mCall.FileName);
  if mPinIndex < 0 then
  begin
    Exit;
  end;
  Dec(FPins.List[mPinIndex].Depth);
  if FPins.List[mPinIndex].Depth > 0 then
  begin
    Exit;
  end;
  mPin := FPins[mPinIndex];
  FPins.Delete(mPinIndex);
  // Die Plätze dahinter rücken auf: MoveTo setzt FCurrent beim nächsten Mal neu.
  FCurrentPin := -1;
  // Der Aufrufer gibt den Baum danach frei: keine Bezüge behalten, die eine wiederverwendete Adresse
  // treffen könnten. Ohne FCacheTree leert das nächste MoveTo die baumbezogenen Caches.
  if FCacheTree = mPin.Tree then
  begin
    FCacheTree := nil;
  end;
  if FTree = mPin.Tree then
  begin
    FTree := nil;
  end;
end;

function TResolverPlace.ExtractedUnit(ATree: TSyntaxTree; const AFileName: string): TUnitIndex;
var
  mPinIndex: Integer;
begin
  mPinIndex := PinnedIndex(ATree, AFileName);
  if mPinIndex >= 0 then
  begin
    Result := FPins[mPinIndex].Extracted;
  end
  else if (FTreeUnits <> nil) and FTreeUnits.Holds(ATree) then
  begin
    Result := FTreeUnits.Extracted(AFileName);
  end
  else
  begin
    Result := TTreeExtracts.ForTree(ATree).Extracted(AFileName);
  end;
end;

function TResolverPlace.EnclosingRoutines: TArray<TSyntaxNode>;
var
  mPath: TList<TSyntaxNode>;
  mNode: TSyntaxNode;
begin
  // Innerste Routine zuerst; anonyme Methoden zählen mit, ihre Parameter und lokalen Variablen
  // verdecken gleichnamige Felder wie die einer benannten Routine.
  mPath := TList<TSyntaxNode>.Create;
  try
    mNode := TResolverNodes.ChildAround(FTree.Root, FOffset);
    while mNode <> nil do
    begin
      if mNode.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod] then
      begin
        mPath.Insert(0, mNode);
      end;
      mNode := TResolverNodes.ChildAround(mNode, FOffset);
    end;
    Result := mPath.ToArray;
  finally
    mPath.Free;
  end;
end;

function TResolverPlace.EnclosingWiths: TArray<TSyntaxNode>;
var
  mNode: TSyntaxNode;
begin
  Result := nil;
  if FTree = nil then
  begin
    Exit;
  end;
  mNode := TResolverNodes.ChildAround(FTree.Root, FOffset);
  while mNode <> nil do
  begin
    if (mNode.Kind = TSyntaxKind.WithStatement) and (mNode.ChildCount >= 2) and
      TResolverNodes.Contains(mNode[mNode.ChildCount - 1], FOffset) then
    begin
      Result := [mNode] + Result;
    end;
    mNode := TResolverNodes.ChildAround(mNode, FOffset);
  end;
end;

function TResolverPlace.PropertyClassName: string;
var
  mNode, mInner: TSyntaxNode;
  mIndex: Integer;
begin
  Result := '';
  mNode := FTree.Root;
  // Rümpfe enthalten keine Property-Deklarationen.
  while (mNode <> nil) and not (mNode.Kind in [TSyntaxKind.Block, TSyntaxKind.RoutineDecl]) do
  begin
    if mNode.Kind = TSyntaxKind.PropertyDecl then
    begin
      Exit(mNode.EnclosingTypeName);
    end;
    mInner := nil;
    for mIndex := 0 to mNode.ChildCount - 1 do
    begin
      if TResolverNodes.Contains(mNode[mIndex], FOffset) then
      begin
        mInner := mNode[mIndex];
      end;
    end;
    mNode := mInner;
  end;
end;

function TResolverPlace.IsCurrentFile(const AFileName: string): Boolean;
begin
  Result := SameText(AFileName, FCurrent.FileName);
end;

end.
