unit Argus.Core.Lsp.Session;

// LSP-Sitzung des IDE-Plugins (ADR 0006): initialize, Dokumentabgleich und die
// Anfragen, die die IDE über den Code Insight-Manager stellt.
// Abgleich: Vor jeder Anfrage wird der aktuelle Editortext geschickt, beim
// ersten Mal als didOpen, danach als didChange mit dem ganzen Text, aber nur,
// wenn er sich geändert hat. Positionen sind 0-basiert in UTF-16-Einheiten
// (Delphi-String-Indizes), wie LSP sie erwartet.

interface

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Argus.Core.Lsp.Client;

type
  TLspLocation = record
    FileName: string;
    /// <summary>0-basiert.</summary>
    Line: Integer;
    /// <summary>0-basiert.</summary>
    Character: Integer;
  end;

  /// <summary>Teile eines Hovers für den Argus-Tooltip (#442).</summary>
  TLspHoverParts = record
    Declaration: string;
    UnitName: string;
    Documentation: string;
    Value: string;
    Deprecation: string;
    function Found: Boolean;
    /// <summary>Aus einer Hover-Antwort: das Feld "argus" des Servers, sonst erster Absatz als Deklaration.</summary>
    class function FromHover(const AHover: TJSONValue): TLspHoverParts; static;
  end;

  TLspSession = class
  private type
    TDocumentState = record
      Version: Integer;
      Text: string;
    end;
  private
    FClient: TLspClient;
    FTimeoutMs: Cardinal;
    FDocuments: TDictionary<string, TDocumentState>;
    FInitialized: Boolean;
    function PositionParams(const AFileName: string; ALine, ACharacter: Integer): TJSONObject;
  public
    /// <summary>AClient gehört weiter dem Aufrufer.</summary>
    constructor Create(AClient: TLspClient; ATimeoutMs: Cardinal = 3000);
    destructor Destroy; override;
    class function PathToUri(const APath: string): string; static;
    class function UriToPath(const AUri: string): string; static;
    /// <summary>Text aus contents einer Hover-Antwort: String, MarkupContent oder MarkedString-Liste.</summary>
    class function HoverText(const AHover: TJSONValue): string; static;
    /// <summary>Zeichenindex (0-basiert) zur Editorspalte (1-basiert); Tabs springen zur nächsten Tabulatorposition.</summary>
    class function ColumnToIndex(const ALine: string; AColumn, ATabWidth: Integer): Integer; static;
    procedure Initialize;
    /// <summary>Schickt AText, falls neu oder geändert.</summary>
    procedure Sync(const AFileName, AText: string);
    function Hover(const AFileName, AText: string; ALine, ACharacter: Integer): string;
    /// <summary>Hover in Teilen (#442).</summary>
    function HoverParts(const AFileName, AText: string; ALine, ACharacter: Integer): TLspHoverParts;
    function Definition(const AFileName, AText: string; ALine, ACharacter: Integer;
      out ALocation: TLspLocation): Boolean;
    /// <summary>
    /// textDocument/completion ohne Abgleich: Sync vorher im Hauptthread. Darf aus einem
    /// anderen Thread kommen, solange die Sitzung lebt. Liefert die Antwort (CompletionList,
    /// CompletionItem[] oder nil); der Aufrufer gibt sie frei.
    /// </summary>
    function Completion(const AFileName: string; ALine, ACharacter: Integer; ATimeoutMs: Cardinal): TJSONValue;
    /// <summary>textDocument/signatureHelp ohne Abgleich, wie Completion.</summary>
    function SignatureHelp(const AFileName: string; ALine, ACharacter: Integer; ATimeoutMs: Cardinal): TJSONValue;
    /// <summary>completionItem/resolve für AItem (wird übernommen); threadsicher wie Completion.</summary>
    function ResolveCompletion(AItem: TJSONObject; ATimeoutMs: Cardinal): TJSONValue;
    property Initialized: Boolean read FInitialized;
  end;

implementation

const
  Unreserved = ['A'..'Z', 'a'..'z', '0'..'9', '-', '.', '_', '~', '/'];

{ TLspSession }

constructor TLspSession.Create(AClient: TLspClient; ATimeoutMs: Cardinal);
begin
  inherited Create;
  FClient := AClient;
  FTimeoutMs := ATimeoutMs;
  FDocuments := TDictionary<string, TDocumentState>.Create;
end;

destructor TLspSession.Destroy;
begin
  FDocuments.Free;
  inherited;
end;

class function TLspSession.PathToUri(const APath: string): string;
var
  Path: string;
  Bytes: TBytes;
  B: Byte;
  Builder: TStringBuilder;
begin
  Path := StringReplace(APath, '\', '/', [rfReplaceAll]);
  if Path.StartsWith('//') then
    Path := Path.Substring(2)
  else
    Path := '/' + Path;
  Bytes := TEncoding.UTF8.GetBytes(Path);
  Builder := TStringBuilder.Create;
  try
    for B in Bytes do
      if (B < $80) and CharInSet(Char(B), Unreserved) then
        Builder.Append(Char(B))
      else
        Builder.Append('%').Append(IntToHex(B, 2));
    // c:\x → file:///c%3A/x; \\server\share → file://server/share
    Result := 'file://' + Builder.ToString;
  finally
    Builder.Free;
  end;
end;

class function TLspSession.UriToPath(const AUri: string): string;
var
  Rest: string;
  Bytes: TBytes;
  Count, Index, Code: Integer;
  Chunk: TBytes;
begin
  if not AUri.StartsWith('file://', True) then
    Exit('');
  Rest := AUri.Substring(Length('file://'));
  SetLength(Bytes, Length(Rest) * 3);
  Count := 0;
  Index := 1;
  while Index <= Length(Rest) do
  begin
    if (Rest[Index] = '%') and (Index + 2 <= Length(Rest)) then
    begin
      Code := StrToIntDef('$' + Copy(Rest, Index + 1, 2), -1);
      if Code >= 0 then
      begin
        Bytes[Count] := Code;
        Inc(Count);
        Inc(Index, 3);
        Continue;
      end;
    end;
    Chunk := TEncoding.UTF8.GetBytes(Rest[Index]);
    Move(Chunk[0], Bytes[Count], Length(Chunk));
    Inc(Count, Length(Chunk));
    Inc(Index);
  end;
  Result := TEncoding.UTF8.GetString(Bytes, 0, Count);
  if Result.StartsWith('/') then
  begin
    // file:///c:/x → c:\x; file://server/share → \\server\share
    if (Length(Result) >= 3) and (Result[3] = ':') then
      Result := Result.Substring(1)
    else
      Result := '/' + Result;
  end
  else
    Result := '//' + Result;
  Result := StringReplace(Result, '/', '\', [rfReplaceAll]);
end;

class function TLspSession.HoverText(const AHover: TJSONValue): string;
var
  Contents: TJSONValue;
  Item: TJSONValue;
begin
  Result := '';
  if not (AHover is TJSONObject) then
    Exit;
  Contents := TJSONObject(AHover).GetValue('contents');
  if Contents is TJSONString then
    Result := TJSONString(Contents).Value
  else if Contents is TJSONObject then
    Result := TJSONObject(Contents).GetValue<string>('value', '')
  else if Contents is TJSONArray then
    for Item in TJSONArray(Contents) do
    begin
      if Result <> '' then
        Result := Result + sLineBreak;
      if Item is TJSONString then
        Result := Result + TJSONString(Item).Value
      else if Item is TJSONObject then
        Result := Result + TJSONObject(Item).GetValue<string>('value', '');
    end;
end;

class function TLspSession.ColumnToIndex(const ALine: string; AColumn, ATabWidth: Integer): Integer;
var
  Visual: Integer;
begin
  // Spalte 1 = erstes Zeichen. Tabs springen zur nächsten Tabulatorposition.
  Result := 0;
  Visual := 1;
  while (Result < Length(ALine)) and (Visual < AColumn) do
  begin
    if ALine[Result + 1] = #9 then
      Visual := ((Visual - 1) div ATabWidth + 1) * ATabWidth + 1
    else
      Inc(Visual);
    Inc(Result);
  end;
end;

procedure TLspSession.Initialize;
var
  Params, Capabilities, TextDocument, Hover: TJSONObject;
  Formats: TJSONArray;
  Response: TJSONValue;
begin
  Formats := TJSONArray.Create;
  Formats.Add('plaintext');
  Hover := TJSONObject.Create;
  Hover.AddPair('contentFormat', Formats);
  TextDocument := TJSONObject.Create;
  TextDocument.AddPair('hover', Hover);
  // Dokumentation der Vervollständigung als Klartext, keine Snippets (#408).
  TextDocument.AddPair('completion', TJSONObject.Create(TJSONPair.Create('completionItem',
    TJSONObject.Create.AddPair('snippetSupport', TJSONBool.Create(False))
      .AddPair('documentationFormat', TJSONArray.Create.Add('plaintext')))));
  Capabilities := TJSONObject.Create;
  Capabilities.AddPair('textDocument', TextDocument);
  Params := TJSONObject.Create;
  Params.AddPair('processId', TJSONNull.Create);
  Params.AddPair('rootUri', TJSONNull.Create);
  Params.AddPair('clientInfo', TJSONObject.Create(TJSONPair.Create('name', 'Argus IDE Expert')));
  Params.AddPair('capabilities', Capabilities);
  // Ohne Arbeitsbereich leitet der Server ihn aus den geöffneten Dateien ab.
  Response := FClient.Request('initialize', Params, 15000);
  Response.Free;
  FClient.Notify('initialized', TJSONObject.Create);
  FInitialized := True;
end;

procedure TLspSession.Sync(const AFileName, AText: string);
var
  State: TDocumentState;
  Key: string;
  Params, Document, Change: TJSONObject;
  Changes: TJSONArray;
begin
  Key := AnsiLowerCase(AFileName);
  Document := TJSONObject.Create;
  Document.AddPair('uri', PathToUri(AFileName));
  if not FDocuments.TryGetValue(Key, State) then
  begin
    State.Version := 1;
    State.Text := AText;
    FDocuments.Add(Key, State);
    Document.AddPair('languageId', 'delphi');
    Document.AddPair('version', TJSONNumber.Create(State.Version));
    Document.AddPair('text', AText);
    FClient.Notify('textDocument/didOpen', TJSONObject.Create(TJSONPair.Create('textDocument', Document)));
    Exit;
  end;
  if State.Text = AText then
  begin
    Document.Free;
    Exit;
  end;
  Inc(State.Version);
  State.Text := AText;
  FDocuments[Key] := State;
  Document.AddPair('version', TJSONNumber.Create(State.Version));
  Change := TJSONObject.Create;
  Change.AddPair('text', AText);
  Changes := TJSONArray.Create;
  Changes.AddElement(Change);
  Params := TJSONObject.Create;
  Params.AddPair('textDocument', Document);
  Params.AddPair('contentChanges', Changes);
  FClient.Notify('textDocument/didChange', Params);
end;

function TLspSession.PositionParams(const AFileName: string; ALine, ACharacter: Integer): TJSONObject;
var
  Position: TJSONObject;
begin
  Position := TJSONObject.Create;
  Position.AddPair('line', TJSONNumber.Create(ALine));
  Position.AddPair('character', TJSONNumber.Create(ACharacter));
  Result := TJSONObject.Create;
  Result.AddPair('textDocument', TJSONObject.Create(TJSONPair.Create('uri', PathToUri(AFileName))));
  Result.AddPair('position', Position);
end;

function TLspSession.Hover(const AFileName, AText: string; ALine, ACharacter: Integer): string;
var
  Response: TJSONValue;
begin
  Sync(AFileName, AText);
  Response := FClient.Request('textDocument/hover', PositionParams(AFileName, ALine, ACharacter), FTimeoutMs);
  try
    Result := HoverText(Response);
  finally
    Response.Free;
  end;
end;

function TLspSession.HoverParts(const AFileName, AText: string; ALine, ACharacter: Integer): TLspHoverParts;
var
  Response: TJSONValue;
begin
  Sync(AFileName, AText);
  Response := FClient.Request('textDocument/hover', PositionParams(AFileName, ALine, ACharacter), FTimeoutMs);
  try
    Result := TLspHoverParts.FromHover(Response);
  finally
    Response.Free;
  end;
end;

{ TLspHoverParts }

function TLspHoverParts.Found: Boolean;
begin
  Result := Declaration <> '';
end;

class function TLspHoverParts.FromHover(const AHover: TJSONValue): TLspHoverParts;
var
  Parts: TJSONValue;
  Text: string;
  Paragraphs: TArray<string>;
begin
  Result := Default(TLspHoverParts);
  if not (AHover is TJSONObject) then
    Exit;
  Parts := TJSONObject(AHover).GetValue('argus');
  if Parts is TJSONObject then
  begin
    Result.Declaration := TJSONObject(Parts).GetValue<string>('declaration', '');
    Result.UnitName := TJSONObject(Parts).GetValue<string>('unit', '');
    Result.Documentation := TJSONObject(Parts).GetValue<string>('documentation', '');
    Result.Value := TJSONObject(Parts).GetValue<string>('value', '');
    Result.Deprecation := TJSONObject(Parts).GetValue<string>('deprecation', '');
    Exit;
  end;
  // Ältere Server: Klartext, erster Absatz ist die Deklaration, der Rest Doku.
  Text := TLspSession.HoverText(AHover).Replace(#13#10, #10).Trim;
  if Text = '' then
    Exit;
  Paragraphs := Text.Split([#10#10], 2);
  Result.Declaration := Paragraphs[0];
  if Length(Paragraphs) > 1 then
    Result.Documentation := Paragraphs[1];
end;

function TLspSession.Definition(const AFileName, AText: string; ALine, ACharacter: Integer;
  out ALocation: TLspLocation): Boolean;
var
  Response, Item: TJSONValue;
  Location: TJSONObject;
  Uri: string;
  Range: TJSONObject;
begin
  ALocation := Default(TLspLocation);
  Sync(AFileName, AText);
  Response := FClient.Request('textDocument/definition', PositionParams(AFileName, ALine, ACharacter), FTimeoutMs);
  try
    // Location, Location[] oder LocationLink[].
    Item := Response;
    if (Item is TJSONArray) and (TJSONArray(Item).Count > 0) then
      Item := TJSONArray(Item).Items[0];
    if not (Item is TJSONObject) then
      Exit(False);
    Location := TJSONObject(Item);
    if not Location.TryGetValue<string>('uri', Uri) then
      Uri := Location.GetValue<string>('targetUri', '');
    Range := Location.GetValue('range') as TJSONObject;
    if Range = nil then
      Range := Location.GetValue('targetSelectionRange') as TJSONObject;
    if (Uri = '') or (Range = nil) then
      Exit(False);
    ALocation.FileName := UriToPath(Uri);
    ALocation.Line := Range.GetValue<Integer>('start.line', 0);
    ALocation.Character := Range.GetValue<Integer>('start.character', 0);
    Result := ALocation.FileName <> '';
  finally
    Response.Free;
  end;
end;

function TLspSession.Completion(const AFileName: string; ALine, ACharacter: Integer;
  ATimeoutMs: Cardinal): TJSONValue;
begin
  Result := FClient.Request('textDocument/completion', PositionParams(AFileName, ALine, ACharacter), ATimeoutMs);
end;

function TLspSession.SignatureHelp(const AFileName: string; ALine, ACharacter: Integer;
  ATimeoutMs: Cardinal): TJSONValue;
begin
  Result := FClient.Request('textDocument/signatureHelp', PositionParams(AFileName, ALine, ACharacter), ATimeoutMs);
end;

function TLspSession.ResolveCompletion(AItem: TJSONObject; ATimeoutMs: Cardinal): TJSONValue;
begin
  Result := FClient.Request('completionItem/resolve', AItem, ATimeoutMs);
end;

end.
