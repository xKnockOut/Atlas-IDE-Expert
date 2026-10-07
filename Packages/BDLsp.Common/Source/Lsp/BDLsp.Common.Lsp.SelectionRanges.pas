unit BDLsp.Common.Lsp.SelectionRanges;

// Intelligente Auswahl für textDocument/selectionRange: Zu jeder Position
// die Kette der umgebenden Bereiche von innen nach außen, z. B. Bezeichner →
// Ausdruck → Anweisung → begin/end-Block → Methode → Klasse → Abschnitt → Datei.

interface

uses
  System.SysUtils,
  System.JSON,
  BDLsp.Common.JsonRpc.Contract,
  BDLsp.Common.JsonRpc.Dispatcher,
  BDLsp.Common.Documents.Contract,
  BDLsp.Common.Pascal.SyntaxTree;

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
  BDLsp.Common.Lsp.Positions,
  BDLsp.Common.Pascal.Contract,
  BDLsp.Common.Pascal.Parser,
  BDLsp.Common.Lsp.Internals.Cancellation;

// Erstes Kind, das den Bereich AStart..AEnd umschließt, sonst nil.
function ChildAround(ANode: TSyntaxNode; AStart, AEnd: Integer): TSyntaxNode;
var
  Index: Integer;
begin
  for Index := 0 to ANode.ChildCount - 1 do
    if (ANode[Index].StartOffset <= AStart) and (AEnd <= ANode[Index].EndOffset) then
      Exit(ANode[Index]);
  Result := nil;
end;

procedure AddRange(var ARanges: TArray<TTextRange>; const ARange: TTextRange);
begin
  // Gleiche Bereiche hintereinander (z. B. Anweisung und ihr einziger Ausdruck) nur einmal.
  if (Length(ARanges) > 0) and (ARanges[High(ARanges)].StartPos = ARange.StartPos) and
    (ARanges[High(ARanges)].EndPos = ARange.EndPos) then
    Exit;
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

class function TLspSelectionRanges.RangesAt(ATree: TSyntaxTree; AOffset: Integer): TArray<TTextRange>;
var
  Token: TPascalToken;
  Best: TPascalToken;
  Found: Boolean;
  Path: TList<TSyntaxNode>;
  Node: TSyntaxNode;
  Index: Integer;
  InnerStart: Integer;
  InnerEnd: Integer;
begin
  Result := nil;
  // Innerster Bereich: das Token unter dem Cursor, auch Kommentare und Strings.
  // Zwischen zwei Token gewinnt das rechte, außer es ist ein Satzzeichen wie ";".
  Best := Default(TPascalToken);
  Found := False;
  for Token in ATree.Tokens do
  begin
    if Token.Offset > AOffset then
      Break;
    if AOffset < Token.Offset + Length(Token.Text) then
    begin
      if not (Found and (Token.Kind = TPascalTokenKind.Symbol) and (Best.Kind <> TPascalTokenKind.Symbol)) then
        Best := Token;
      Found := True;
      Break;
    end;
    if AOffset = Token.Offset + Length(Token.Text) then
    begin
      Best := Token;
      Found := True;
    end;
  end;
  InnerStart := AOffset;
  InnerEnd := AOffset;
  if Found then
  begin
    AddRange(Result, TTextRange.Create(Best.StartPos, Best.EndPos));
    InnerStart := Best.Offset;
    InnerEnd := Best.Offset + Length(Best.Text);
  end;

  // Pfad von der Wurzel zum innersten Knoten, der das Token umschließt.
  Path := TList<TSyntaxNode>.Create;
  try
    Node := ATree.Root;
    while Node <> nil do
    begin
      Path.Add(Node);
      Node := ChildAround(Node, InnerStart, InnerEnd);
    end;
    for Index := Path.Count - 1 downto 0 do
    begin
      Node := Path[Index];
      // Jeder Bereich muss den inneren umschließen (z. B. nicht bei Cursor vor dem ersten Token).
      if (Node.StartOffset > InnerStart) or (Node.EndOffset < InnerEnd) then
        Continue;
      AddRange(Result, TTextRange.Create(Node.StartPos, Node.EndPos));
      InnerStart := Node.StartOffset;
      InnerEnd := Node.EndOffset;
    end;
  finally
    Path.Free;
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
      Item.AddPair('parent', Result);
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
  Item: TJSONObject;
  Offset: Integer;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', Uri) and
    TJSONObject(AParams).TryGetValue<TJSONArray>('positions', Positions)) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
      'Felder "textDocument.uri" und "positions" fehlen in ' + Method);
  if not FStore.TryGet(Uri, Document) then
    Exit(TJSONNull.Create);
  // Erst in einer Variablen halten: Bei Übergabe als const würde das Objekt nie freigegeben.
  Cancellation := TRequestCancellation.Create(ACancellation);
  Tree := TPascalParser.Parse(Document.Text, Cancellation);
  try
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
  finally
    Tree.Free;
  end;
end;

end.
