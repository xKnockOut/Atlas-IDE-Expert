unit Atlas.Common.Lsp.LinkedEditing;

// Gleichzeitiges Bearbeiten (textDocument/linkedEditingRange, #39): Steht der
// Cursor auf dem Namen einer Methode oder Routine, ändern sich Deklaration und
// Implementierung in derselben Datei gemeinsam.
//
// Verknüpft werden genau zwei Stellen mit gleichem Typ, Namen und Art. Bei
// Überladungen ist die Zuordnung nicht eindeutig; dann liefert der Server nichts.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree;

type
  TLspLinkedEditing = class
  public const
    Method = 'textDocument/linkedEditingRange';
    /// <summary>Gültige Bezeichner, damit der Client die Verknüpfung bei anderen Zeichen löst.</summary>
    WordPattern = '[A-Za-z_][A-Za-z0-9_]*';
  private
    FStore: IDocumentStore;
    function HandleLinkedEditing(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
  public
    constructor Create(const AStore: IDocumentStore);
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>Namensbereiche von Deklaration und Implementierung zum Namen an APosition; sonst leer.</summary>
    class function Ranges(ATree: TSyntaxTree; const AFileName: string;
      const APosition: TTextPosition): TArray<TTextRange>; static;
    /// <summary>Antwort im Format des LSP; null ohne Bereiche.</summary>
    class function ToJson(const ARanges: TArray<TTextRange>): TJSONValue; static;
  end;

implementation

uses
  Atlas.Common.Documents.Uris,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Lsp.Internals.Cancellation;

const
  RoutineKinds = [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_, TIndexSymbolKind.Routine];

function Contains(const ARange: TTextRange; const APosition: TTextPosition): Boolean;
begin
  Result := (APosition.Line = ARange.StartPos.Line) and (APosition.Line = ARange.EndPos.Line) and
    (APosition.Character >= ARange.StartPos.Character) and (APosition.Character <= ARange.EndPos.Character);
end;

{ TLspLinkedEditing }

constructor TLspLinkedEditing.Create(const AStore: IDocumentStore);
begin
  inherited Create;
  FStore := AStore;
end;

procedure TLspLinkedEditing.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterConcurrentRequest(Method, HandleLinkedEditing);
end;

class function TLspLinkedEditing.Ranges(ATree: TSyntaxTree; const AFileName: string;
  const APosition: TTextPosition): TArray<TTextRange>;
var
  UnitIndex: TUnitIndex;
  Symbol, Target: TIndexSymbol;
begin
  Result := nil;
  UnitIndex := TIndexExtractor.Extract(ATree, AFileName);
  Target := Default(TIndexSymbol);
  for Symbol in UnitIndex.Symbols do
    if (Symbol.Kind in RoutineKinds) and Contains(Symbol.SelectionRange, APosition) then
    begin
      Target := Symbol;
      Break;
    end;
  if Target.Name = '' then
    Exit;
  for Symbol in UnitIndex.Symbols do
    if (Symbol.Kind = Target.Kind) and SameText(Symbol.Name, Target.Name) and
      SameText(Symbol.Container, Target.Container) then
      Result := Result + [Symbol.SelectionRange];
  if Length(Result) <> 2 then
    Result := nil;
end;

class function TLspLinkedEditing.ToJson(const ARanges: TArray<TTextRange>): TJSONValue;
var
  Items: TJSONArray;
  Range: TTextRange;
  Answer: TJSONObject;
begin
  if Length(ARanges) = 0 then
    Exit(TJSONNull.Create);
  Answer := TJSONObject.Create;
  Items := TJSONArray.Create;
  Answer.AddPair('ranges', Items);
  for Range in ARanges do
    Items.AddElement(TLspPositions.RangeToJson(Range));
  Answer.AddPair('wordPattern', WordPattern);
  Result := Answer;
end;

function TLspLinkedEditing.HandleLinkedEditing(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  Cancellation: IPascalCancellation;
  Uri: string;
  PositionValue: TJSONValue;
  Document: ITextDocument;
  Tree: TSyntaxTree;
  Shared: ISharedSyntaxTree;
  Found: TArray<TTextRange>;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', Uri) and
    TJSONObject(AParams).TryGetValue<TJSONValue>('position', PositionValue)) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
      'Felder "textDocument.uri" und "position" fehlen in ' + Method);
  if not FStore.TryGet(Uri, Document) then
    Exit(TJSONNull.Create);
  // Erst in einer Variablen halten: Bei Übergabe als const würde das Objekt nie freigegeben.
  Cancellation := TRequestCancellation.Create(ACancellation);
  Shared := TSyntaxTreeCache.Get(Document, Cancellation);
  Tree := Shared.Tree;
  ACancellation.ThrowIfCancellationRequested;
  Found := Ranges(Tree, TDocumentUris.ToPath(Uri), TLspPositions.ReadPosition(PositionValue));
  Result := ToJson(Found);
end;

end.
