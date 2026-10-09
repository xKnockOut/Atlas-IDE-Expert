unit Argus.Common.Lsp.Formatting;

// textDocument/formatting und textDocument/rangeFormatting (#43). Die
// Einstellungen kommen in drei Ebenen: die FormattingOptions des Editors,
// darüber .editorconfig und darüber ausdrücklich gesetzte Werte aus
// "format" in argus.json. Die Logik liegt in Argus.Common.Editing.Formatter.

interface

uses
  System.SysUtils,
  System.JSON,
  Argus.Common.JsonRpc.Contract,
  Argus.Common.JsonRpc.Dispatcher,
  Argus.Common.Documents.Contract,
  Argus.Common.Configuration.Contract,
  Argus.Common.Editing.EditorConfig;

type
  /// <summary>Block "format" aus argus.json bzw. dem Editor für AUri.</summary>
  TFormatStyleProvider = reference to function(const AUri: string): TFormatStyle;

  TLspFormatting = class
  public const
    Method = 'textDocument/formatting';
    RangeMethod = 'textDocument/rangeFormatting';
  private
    FStore: IDocumentStore;
    FSettingsProvider: TFormatStyleProvider;
    FReadFile: TEditorConfigReadFile;
    function Handle(const AParams: TJSONValue; AWithRange: Boolean): TJSONValue;
    function HandleFormatting(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
    function HandleRangeFormatting(const AParams: TJSONValue;
      const ACancellation: IJsonRpcCancellationToken): TJSONValue;
  public
    constructor Create(const AStore: IDocumentStore; const ASettingsProvider: TFormatStyleProvider;
      const AReadFile: TEditorConfigReadFile);
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>Einstellungen für AFileName aus Editor-Optionen, .editorconfig und AConfigured.</summary>
    class function Resolve(const AOptions: TJSONValue; const AFileName: string; const AConfigured: TFormatStyle;
      const AReadFile: TEditorConfigReadFile): TFormatStyle; static;
  end;

implementation

uses
  Argus.Common.Documents.Uris,
  Argus.Common.Lsp.Positions,
  Argus.Common.Rules.Contract,
  Argus.Common.Pascal.Lexer,
  Argus.Common.Editing.Formatter;

{ TLspFormatting }

constructor TLspFormatting.Create(const AStore: IDocumentStore; const ASettingsProvider: TFormatStyleProvider;
  const AReadFile: TEditorConfigReadFile);
begin
  inherited Create;
  FStore := AStore;
  FSettingsProvider := ASettingsProvider;
  FReadFile := AReadFile;
end;

procedure TLspFormatting.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterConcurrentRequest(Method, HandleFormatting);
  ADispatcher.RegisterConcurrentRequest(RangeMethod, HandleRangeFormatting);
end;

class function TLspFormatting.Resolve(const AOptions: TJSONValue; const AFileName: string;
  const AConfigured: TFormatStyle; const AReadFile: TEditorConfigReadFile): TFormatStyle;
var
  Size: Integer;
  Flag: Boolean;
begin
  Result := TFormatStyle.Default;
  if AOptions is TJSONObject then
  begin
    if AOptions.TryGetValue<Integer>('tabSize', Size) and (Size >= 1) then
      Result.IndentSize := Size;
    if AOptions.TryGetValue<Boolean>('insertSpaces', Flag) then
      Result.UseTabs := not Flag;
    if AOptions.TryGetValue<Boolean>('trimTrailingWhitespace', Flag) then
      Result.TrimTrailingWhitespace := Flag;
    if AOptions.TryGetValue<Boolean>('insertFinalNewline', Flag) then
      Result.InsertFinalNewline := Flag;
  end;
  if Assigned(AReadFile) and (AFileName <> '') then
    Result := TEditorConfig.ForFile(AFileName, AReadFile, Result);
  if TFormatKey.IndentSize in AConfigured.Given then
    Result.IndentSize := AConfigured.IndentSize;
  if TFormatKey.UseTabs in AConfigured.Given then
    Result.UseTabs := AConfigured.UseTabs;
  if TFormatKey.KeywordCase in AConfigured.Given then
    Result.KeywordCase := AConfigured.KeywordCase;
  if TFormatKey.TrimTrailingWhitespace in AConfigured.Given then
    Result.TrimTrailingWhitespace := AConfigured.TrimTrailingWhitespace;
  if TFormatKey.InsertFinalNewline in AConfigured.Given then
    Result.InsertFinalNewline := AConfigured.InsertFinalNewline;
  if TFormatKey.SpaceAroundAssignment in AConfigured.Given then
    Result.SpaceAroundAssignment := AConfigured.SpaceAroundAssignment;
  if TFormatKey.SpaceAfterComma in AConfigured.Given then
    Result.SpaceAfterComma := AConfigured.SpaceAfterComma;
  if TFormatKey.EndOfLine in AConfigured.Given then
    Result.EndOfLine := AConfigured.EndOfLine;
  Result.Given := AConfigured.Given;
end;

function TLspFormatting.Handle(const AParams: TJSONValue; AWithRange: Boolean): TJSONValue;
var
  Uri: string;
  Document: ITextDocument;
  Options, RangeValue: TJSONValue;
  Range: TTextRange;
  Settings, Configured: TFormatStyle;
  Edits: TArray<TRuleEdit>;
  Edit: TRuleEdit;
  Item: TJSONObject;
  FirstLine, LastLine: Integer;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', Uri)) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Feld "textDocument.uri" fehlt');
  if not FStore.TryGet(Uri, Document) then
    Exit(TJSONNull.Create);
  if not TJSONObject(AParams).TryGetValue<TJSONValue>('options', Options) then
    Options := nil;
  if Assigned(FSettingsProvider) then
    Configured := FSettingsProvider(Uri)
  else
    Configured := TFormatStyle.Default;
  Settings := Resolve(Options, TDocumentUris.ToPath(Uri), Configured, FReadFile);
  FirstLine := 0;
  LastLine := -1;
  if AWithRange then
  begin
    if not TJSONObject(AParams).TryGetValue<TJSONValue>('range', RangeValue) then
      raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Feld "range" fehlt in ' + RangeMethod);
    Range := TLspPositions.ReadRange(RangeValue);
    FirstLine := Range.StartPos.Line;
    LastLine := Range.EndPos.Line;
    // Bereich bis zum Anfang einer Zeile: diese Zeile gehört nicht dazu.
    if (Range.EndPos.Character = 0) and (LastLine > FirstLine) then
      Dec(LastLine);
  end;
  Edits := TFormatter.Edits(Document.Text, TPascalLexer.Tokenize(Document.Text), Settings, FirstLine, LastLine);
  Result := TJSONArray.Create;
  for Edit in Edits do
  begin
    Item := TJSONObject.Create;
    Item.AddPair('range', TLspPositions.RangeToJson(Edit.Range));
    Item.AddPair('newText', Edit.NewText);
    TJSONArray(Result).AddElement(Item);
  end;
end;

function TLspFormatting.HandleFormatting(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
begin
  Result := Handle(AParams, False);
end;

function TLspFormatting.HandleRangeFormatting(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
begin
  Result := Handle(AParams, True);
end;

end.
