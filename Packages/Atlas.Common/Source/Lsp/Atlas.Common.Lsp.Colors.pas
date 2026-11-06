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
    cColorMethod = 'textDocument/documentColor';
    cPresentationMethod = 'textDocument/colorPresentation';
  private
    FStore: IDocumentStore;
    FSystemColors: TSystemColorProvider;
    function HandleColors(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
    function HandlePresentation(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
  public
    constructor Create(const AStore: IDocumentStore; const ASystemColors: TSystemColorProvider); overload;
    /// <summary>Wie oben mit ASystemColors = nil.</summary>
    constructor Create(const AStore: IDocumentStore); overload;
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
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TColorsText = (FieldTextDocumentUriMissingIn, FieldsTextDocumentUriColorAnd);

const
  cTexts: array[TColorsText] of TAtlasText = (
    (De: 'Feld "textDocument.uri" fehlt in '; En: 'Field "textDocument.uri" missing in '),
    (De: 'Felder "textDocument.uri", "color" und "range" fehlen in ';
     En: 'Fields "textDocument.uri", "color" and "range" missing in '));

{$SCOPEDENUMS OFF}

constructor TLspColors.Create(const AStore: IDocumentStore);
begin
  Create(AStore, nil);
end;

constructor TLspColors.Create(const AStore: IDocumentStore; const ASystemColors: TSystemColorProvider);
begin
  inherited Create;
  FStore := AStore;
  FSystemColors := ASystemColors;
end;

procedure TLspColors.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterConcurrentRequest(cColorMethod, HandleColors);
  ADispatcher.RegisterConcurrentRequest(cPresentationMethod, HandlePresentation);
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
  mRed, mGreen, mBlue: Double;
begin
  Result := (AValue is TJSONObject) and TJSONObject(AValue).TryGetValue<Double>('red', mRed) and
    TJSONObject(AValue).TryGetValue<Double>('green', mGreen) and TJSONObject(AValue).TryGetValue<Double>('blue', mBlue);
  if Result then
  begin
    AColor := TRgbColor.Create(Channel(mRed), Channel(mGreen), Channel(mBlue));
  end;
end;

function TLspColors.HandleColors(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  mUri: string;
  mDocument: ITextDocument;
  mMatches: TArray<TColorMatch>;
  mMatch: TColorMatch;
  mItem: TJSONObject;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', mUri)) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams,
      cTexts[TColorsText.FieldTextDocumentUriMissingIn].Text + cColorMethod);
  end;
  if not FStore.TryGet(mUri, mDocument) then
  begin
    Exit(TJSONArray.Create);
  end;
  mMatches := TSourceColors.Find(mDocument.Text, FSystemColors);
  ACancellation.ThrowIfCancellationRequested;
  Result := TJSONArray.Create;
  for mMatch in mMatches do
  begin
    mItem := TJSONObject.Create;
    mItem.AddPair('range', TLspPositions.RangeToJson(mMatch.Range));
    mItem.AddPair('color', ColorToJson(mMatch.Color));
    TJSONArray(Result).AddElement(mItem);
  end;
end;

function TLspColors.HandlePresentation(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  mUri: string;
  mDocument: ITextDocument;
  mColorValue, mRangeValue: TJSONValue;
  mColor: TRgbColor;
  mRange: TTextRange;
  mSourceFormat: TColorFormat;
  mMatch: TColorMatch;
  mPresentation: TColorPresentation;
  mItem, mEdit: TJSONObject;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', mUri) and
    TJSONObject(AParams).TryGetValue<TJSONValue>('color', mColorValue) and
    TJSONObject(AParams).TryGetValue<TJSONValue>('range', mRangeValue) and TryReadColor(mColorValue, mColor)) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams,
      cTexts[TColorsText.FieldsTextDocumentUriColorAnd].Text + cPresentationMethod);
  end;
  mRange := TLspPositions.ReadRange(mRangeValue);
  // Ohne Fundstelle an dieser Stelle gilt Hex als Ausgangsformat.
  mSourceFormat := TColorFormat.Hex;
  if FStore.TryGet(mUri, mDocument) then
  begin
    for mMatch in TSourceColors.Find(mDocument.Text, FSystemColors) do
    begin
      if (mMatch.Range.StartPos = mRange.StartPos) and (mMatch.Range.EndPos = mRange.EndPos) then
      begin
        mSourceFormat := mMatch.Format;
      end;
    end;
  end;
  ACancellation.ThrowIfCancellationRequested;
  Result := TJSONArray.Create;
  for mPresentation in TSourceColors.Presentations(mColor, mSourceFormat) do
  begin
    mItem := TJSONObject.Create;
    mItem.AddPair('label', mPresentation.Text);
    mEdit := TJSONObject.Create;
    mEdit.AddPair('range', TLspPositions.RangeToJson(mRange));
    mEdit.AddPair('newText', mPresentation.Text);
    mItem.AddPair('textEdit', mEdit);
    TJSONArray(Result).AddElement(mItem);
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.Colors', cTexts);

end.
