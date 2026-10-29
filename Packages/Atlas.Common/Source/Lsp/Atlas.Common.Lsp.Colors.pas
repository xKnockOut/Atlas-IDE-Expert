unit Atlas.Common.Lsp.Colors;

// Farbvorschau und Farbwähler (textDocument/documentColor und
// textDocument/colorPresentation, #26). Die Suche liegt in Editing.Colors.
// colorPresentation sucht die Fundstelle im aktuellen Text erneut, damit die
// neue Farbe im Ausgangsformat zurückgeschrieben wird.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Editing.Colors;

type
  TLspColors = class
  public const
    ColorMethod = 'textDocument/documentColor';
    PresentationMethod = 'textDocument/colorPresentation';
  private
    FStore: IDocumentStore;
    FSystemColors: TSystemColorProvider;
    function HandleColors(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
    function HandlePresentation(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
  public
    constructor Create(const AStore: IDocumentStore; const ASystemColors: TSystemColorProvider = nil);
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>LSP-Color (Anteile 0 bis 1). Der Aufrufer übernimmt das Objekt.</summary>
    class function ColorToJson(const AColor: TRgbColor): TJSONObject; static;
    /// <summary>Liest eine LSP-Color; False bei fehlenden Feldern.</summary>
    class function TryReadColor(AValue: TJSONValue; out AColor: TRgbColor): Boolean; static;
  end;

implementation

uses
  System.Generics.Collections,
  System.Math,
  Atlas.Common.Lsp.Positions;

constructor TLspColors.Create(const AStore: IDocumentStore; const ASystemColors: TSystemColorProvider);
begin
  inherited Create;
  FStore := AStore;
  FSystemColors := ASystemColors;
end;

procedure TLspColors.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterConcurrentRequest(ColorMethod, HandleColors);
  ADispatcher.RegisterConcurrentRequest(PresentationMethod, HandlePresentation);
end;

class function TLspColors.ColorToJson(const AColor: TRgbColor): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('red', TJSONNumber.Create(AColor.R / 255));
  Result.AddPair('green', TJSONNumber.Create(AColor.G / 255));
  Result.AddPair('blue', TJSONNumber.Create(AColor.B / 255));
  Result.AddPair('alpha', TJSONNumber.Create(1));
end;

function Channel(AValue: Double): Byte;
begin
  Result := Round(EnsureRange(AValue, 0, 1) * 255);
end;

class function TLspColors.TryReadColor(AValue: TJSONValue; out AColor: TRgbColor): Boolean;
var
  Red, Green, Blue: Double;
begin
  Result := (AValue is TJSONObject) and TJSONObject(AValue).TryGetValue<Double>('red', Red) and
    TJSONObject(AValue).TryGetValue<Double>('green', Green) and TJSONObject(AValue).TryGetValue<Double>('blue', Blue);
  if Result then
    AColor := TRgbColor.Create(Channel(Red), Channel(Green), Channel(Blue));
end;

function TLspColors.HandleColors(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  Uri: string;
  Document: ITextDocument;
  Matches: TArray<TColorMatch>;
  Match: TColorMatch;
  Item: TJSONObject;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', Uri)) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Feld "textDocument.uri" fehlt in ' + ColorMethod);
  if not FStore.TryGet(Uri, Document) then
    Exit(TJSONArray.Create);
  Matches := TSourceColors.Find(Document.Text, FSystemColors);
  ACancellation.ThrowIfCancellationRequested;
  Result := TJSONArray.Create;
  for Match in Matches do
  begin
    Item := TJSONObject.Create;
    Item.AddPair('range', TLspPositions.RangeToJson(Match.Range));
    Item.AddPair('color', ColorToJson(Match.Color));
    TJSONArray(Result).AddElement(Item);
  end;
end;

function TLspColors.HandlePresentation(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  Uri: string;
  Document: ITextDocument;
  ColorValue, RangeValue: TJSONValue;
  Color: TRgbColor;
  Range: TTextRange;
  SourceFormat: TColorFormat;
  Match: TColorMatch;
  Presentation: TColorPresentation;
  Item, Edit: TJSONObject;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', Uri) and
    TJSONObject(AParams).TryGetValue<TJSONValue>('color', ColorValue) and
    TJSONObject(AParams).TryGetValue<TJSONValue>('range', RangeValue) and TryReadColor(ColorValue, Color)) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
      'Felder "textDocument.uri", "color" und "range" fehlen in ' + PresentationMethod);
  Range := TLspPositions.ReadRange(RangeValue);
  // Ohne Fundstelle an dieser Stelle gilt Hex als Ausgangsformat.
  SourceFormat := TColorFormat.Hex;
  if FStore.TryGet(Uri, Document) then
    for Match in TSourceColors.Find(Document.Text, FSystemColors) do
      if (Match.Range.StartPos = Range.StartPos) and (Match.Range.EndPos = Range.EndPos) then
        SourceFormat := Match.Format;
  ACancellation.ThrowIfCancellationRequested;
  Result := TJSONArray.Create;
  for Presentation in TSourceColors.Presentations(Color, SourceFormat) do
  begin
    Item := TJSONObject.Create;
    Item.AddPair('label', Presentation.Text);
    Edit := TJSONObject.Create;
    Edit.AddPair('range', TLspPositions.RangeToJson(Range));
    Edit.AddPair('newText', Presentation.Text);
    Item.AddPair('textEdit', Edit);
    TJSONArray(Result).AddElement(Item);
  end;
end;

end.
