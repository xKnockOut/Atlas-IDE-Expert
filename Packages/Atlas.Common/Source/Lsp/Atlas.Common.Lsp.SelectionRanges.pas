unit Atlas.Common.Lsp.SelectionRanges;

// Intelligente Auswahl für textDocument/selectionRange: Zu jeder Position
// die Kette der umgebenden Bereiche von innen nach außen, z. B. Bezeichner →
// Ausdruck → Anweisung → begin/end-Block → Methode → Klasse → Abschnitt → Datei.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree;

type
  TLspSelectionRanges = class
  public const
    Method = 'textDocument/selectionRange';
  private
    FStore: IDocumentStore;
    function HandleSelectionRange(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
  public
    constructor Create(const AStore: IDocumentStore);
    /// <summary>Registriert die Anfrage am Dispatcher.</summary>
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>Bereiche um AOffset, der innerste zuerst, ohne Doppelte.</summary>
    class function RangesAt(ATree: TSyntaxTree; AOffset: Integer): TArray<TTextRange>; static;
    /// <summary>SelectionRange des LSP mit parent-Kette. Der Aufrufer übernimmt das Objekt.</summary>
    class function ToJson(const ARanges: TArray<TTextRange>): TJSONObject; static;
  end;

implementation

uses
  System.Generics.Collections,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Lsp.Internals.Cancellation,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TSelectionRangesText = (FieldsTextDocumentUriAndPositions);

const
  cTexts: array[TSelectionRangesText] of TAtlasText = (
    (De: 'Felder "textDocument.uri" und "positions" fehlen in ';
     En: 'Fields "textDocument.uri" and "positions" missing in '));

{$SCOPEDENUMS OFF}

// Erstes Kind, das den Bereich AStart..AEnd umschließt, sonst nil.
function ChildAround(ANode: TSyntaxNode; AStart, AEnd: Integer): TSyntaxNode;
var
  Index: Integer;
begin
  for Index := 0 to ANode.ChildCount - 1 do
  begin
    if (ANode[Index].StartOffset <= AStart) and (AEnd <= ANode[Index].EndOffset) then
    begin
      Exit(ANode[Index]);
    end;
  end;
  Result := nil;
end;

procedure AddRange(var ARanges: TArray<TTextRange>; const ARange: TTextRange);
begin
  // Gleiche Bereiche hintereinander (z. B. Anweisung und ihr einziger Ausdruck) nur einmal.
  if (Length(ARanges) > 0) and (ARanges[High(ARanges)].StartPos = ARange.StartPos) and
    (ARanges[High(ARanges)].EndPos = ARange.EndPos) then
  begin
    Exit;
  end;
  ARanges := ARanges + [ARange];
end;

{ TLspSelectionRanges }

constructor TLspSelectionRanges.Create(const AStore: IDocumentStore);
begin
  inherited Create;
  FStore := AStore;
end;

procedure TLspSelectionRanges.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  // Nebenläufig: Parsen großer Dateien blockiert die Nachrichtenschleife nicht.
  ADispatcher.RegisterConcurrentRequest(Method, HandleSelectionRange);
end;

/// <summary>Token unter dem Cursor AOffset, auch Kommentare und Strings. Zwischen zwei Token gewinnt das rechte,
/// außer es ist ein Satzzeichen wie ";".</summary>
function TokenAt(ATree: TSyntaxTree; AOffset: Integer; out ABest: TPascalToken): Boolean;
var
  mToken: TPascalToken;
begin
  ABest := Default(TPascalToken);
  Result := False;
  for mToken in ATree.Tokens do
  begin
    if mToken.Offset > AOffset then
    begin
      Break;
    end;
    if AOffset < mToken.Offset + Length(mToken.Text) then
    begin
      if not (Result and (mToken.Kind = TPascalTokenKind.Symbol) and (ABest.Kind <> TPascalTokenKind.Symbol)) then
      begin
        ABest := mToken;
      end;
      Exit(True);
    end;
    if AOffset = mToken.Offset + Length(mToken.Text) then
    begin
      ABest := mToken;
      Result := True;
    end;
  end;
end;

/// <summary>Pfad von der Wurzel zum innersten Knoten, der AStart bis AEnd umschließt.</summary>
function PathTo(ATree: TSyntaxTree; AStart, AEnd: Integer): TArray<TSyntaxNode>;
var
  mPath: TList<TSyntaxNode>;
  mNode: TSyntaxNode;
begin
  mPath := TList<TSyntaxNode>.Create;
  try
    mNode := ATree.Root;
    while mNode <> nil do
    begin
      mPath.Add(mNode);
      mNode := ChildAround(mNode, AStart, AEnd);
    end;
    Result := mPath.ToArray;
  finally
    mPath.Free;
  end;
end;

class function TLspSelectionRanges.RangesAt(ATree: TSyntaxTree; AOffset: Integer): TArray<TTextRange>;
var
  mBest: TPascalToken;
  mPath: TArray<TSyntaxNode>;
  mNode: TSyntaxNode;
  mIndex, mInnerStart, mInnerEnd: Integer;
begin
  Result := nil;
  mInnerStart := AOffset;
  mInnerEnd := AOffset;
  // Innerster Bereich: das Token unter dem Cursor.
  if TokenAt(ATree, AOffset, mBest) then
  begin
    AddRange(Result, TTextRange.Create(mBest.StartPos, mBest.EndPos));
    mInnerStart := mBest.Offset;
    mInnerEnd := mBest.Offset + Length(mBest.Text);
  end;
  mPath := PathTo(ATree, mInnerStart, mInnerEnd);
  for mIndex := High(mPath) downto 0 do
  begin
    mNode := mPath[mIndex];
    // Jeder Bereich muss den inneren umschließen (z. B. nicht bei Cursor vor dem ersten Token).
    if (mNode.StartOffset <= mInnerStart) and (mNode.EndOffset >= mInnerEnd) then
    begin
      AddRange(Result, TTextRange.Create(mNode.StartPos, mNode.EndPos));
      mInnerStart := mNode.StartOffset;
      mInnerEnd := mNode.EndOffset;
    end;
  end;
end;

class function TLspSelectionRanges.ToJson(const ARanges: TArray<TTextRange>): TJSONObject;
var
  Index: Integer;
  Item: TJSONObject;
begin
  Result := nil;
  for Index := High(ARanges) downto 0 do
  begin
    Item := TJSONObject.Create;
    Item.AddPair('range', TLspPositions.RangeToJson(ARanges[Index]));
    if Result <> nil then
    begin
      Item.AddPair('parent', Result);
    end;
    Result := Item;
  end;
end;

function TLspSelectionRanges.HandleSelectionRange(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  Cancellation: IPascalCancellation;
  Uri: string;
  Positions: TJSONArray;
  Position: TJSONValue;
  Document: ITextDocument;
  Tree: TSyntaxTree;
  Shared: ISharedSyntaxTree;
  Item: TJSONObject;
  Offset: Integer;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', Uri) and
    TJSONObject(AParams).TryGetValue<TJSONArray>('positions', Positions)) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
      cTexts[TSelectionRangesText.FieldsTextDocumentUriAndPositions].Text + Method);
  end;
  if not FStore.TryGet(Uri, Document) then
  begin
    Exit(TJSONNull.Create);
  end;
  // Erst in einer Variablen halten: Bei Übergabe als const würde das Objekt nie freigegeben.
  Cancellation := TRequestCancellation.Create(ACancellation);
  Shared := TSyntaxTreeCache.Get(Document, Cancellation);
  Tree := Shared.Tree;
  ACancellation.ThrowIfCancellationRequested;
  Result := TJSONArray.Create;
  try
    for Position in Positions do
    begin
      Offset := Document.OffsetAt(TLspPositions.ReadPosition(Position));
      Item := ToJson(RangesAt(Tree, Offset));
      // Die Antwort braucht je Position ein Element; ohne Bereich die Position selbst.
      if Item = nil then
      begin
        Item := TJSONObject.Create;
        Item.AddPair('range', TLspPositions.RangeToJson(TTextRange.Create(Document.PositionAt(Offset),
          Document.PositionAt(Offset))));
      end;
      TJSONArray(Result).AddElement(Item);
    end;
  except
    Result.Free;
    raise;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.SelectionRanges', cTexts);

end.
