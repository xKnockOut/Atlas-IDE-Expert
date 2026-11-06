unit Atlas.Core.Lsp.Session.Requests;

// Anfragen der LSP-Sitzung (aus Atlas.Core.Lsp.Session ausgelagert): Hover, Referenzen, Definitionen,
// Implementierungen, Symbole, Code-Aktionen und Befehle, Formatieren, Auswahlbereiche, Vervollständigung,
// Parameterhilfe und Umbenennen. Der Aufrufer gleicht die Puffer vorher ab (Sync).

interface

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Core.Lsp.Client,
  Atlas.Core.Lsp.Progress,
  Atlas.Core.Hover.Contract,
  Atlas.Core.Lsp.Contract,
  Atlas.Core.Lsp.DataFlow,
  Atlas.Core.Lsp.AccessChains,
  Atlas.Core.Files.WatchedChanges,
  Atlas.Core.Projects.Contract,
  Atlas.Core.InlayHints.Store,
  Atlas.Core.Lsp.TextChanges,
  Atlas.Core.Lsp.WorkspaceEdits,
  Atlas.Core.Lsp.Session.Json,
  Atlas.Core.Lsp.Session.Base;

type
  /// <summary>Anfragen der LSP-Sitzung zu Hover, Orten, Symbolen, Code-Aktionen, Formatieren, Vervollständigung
  /// und Umbenennen; der Aufrufer gleicht die Puffer vorher ab (Sync). Vorfahr von TLspSession.</summary>
  TLspSessionRequests = class(TLspSessionBase)
  public
    /// <summary>Benachrichtigung ohne Antwort, z. B. atlas/compileStarted (#527); übernimmt AParams.</summary>
    procedure Notify(const AMethod: string; AParams: TJSONObject);
    /// <summary>didSave für eine abgeglichene Datei: Der Server prüft dann mit dcc (compiler.onSave, #40).</summary>
    procedure Saved(const AFileName: string);
    /// <summary>workspace/didChangeWatchedFiles für Änderungen außerhalb der IDE (#395).
    /// Geänderte Dateien, die gerade abgeglichen sind, entfallen: Für sie gilt der Editortext.</summary>
    procedure FilesChanged(const AChanges: TArray<TAtlasFileChange>);
    function Hover(const AFileName, AText: string; ALine, ACharacter: Integer): string;
    /// <summary>Hover in Teilen (#442).</summary>
    function HoverParts(const AFileName, AText: string; ALine, ACharacter: Integer): TLspHoverParts;
    /// <summary>Hover mit allen Teilen für den Tooltip (#588): Art, Fundort, Links, Vererbungskette.</summary>
    function HoverData(const AFileName, AText: string; ALine, ACharacter: Integer): TAtlasHoverData;
    /// <summary>Hover an einem Fundort ohne Abgleich: Der Server liest nicht geöffnete Dateien selbst (#588).</summary>
    function HoverDataAt(const AFileName: string; ALine, ACharacter: Integer): TAtlasHoverData;
    /// <summary>Verwendungen des Symbols am Fundort ohne die Deklaration (textDocument/references).</summary>
    function References(const AFileName: string; ALine, ACharacter: Integer): TArray<TLspLocation>;
    /// <summary>Implementierungen des Symbols (textDocument/implementation, #400).</summary>
    function Implementations(const AFileName: string; ALine, ACharacter: Integer): TArray<TLspLocation>;
    /// <summary>Projektweite Symbolsuche (workspace/symbol, #400); unscharf filtert der Server.</summary>
    function WorkspaceSymbols(const AQuery: string; ATimeoutMs: Cardinal): TArray<TAtlasSymbol>;
    /// <summary>Gliederung einer Datei (textDocument/documentSymbol, #503), flach in Dateireihenfolge.</summary>
    function DocumentSymbols(const AFileName: string; ATimeoutMs: Cardinal): TArray<TAtlasSymbol>;
    /// <summary>Unveränderte Antwort von textDocument/documentSymbol samt Atlas-Angaben (Gliederungsfenster,
    /// #537); der Aufrufer gibt sie frei, nil ohne Antwort.</summary>
    function DocumentSymbolTree(const AFileName: string; ATimeoutMs: Cardinal): TJSONValue;
    /// <summary>Code-Aktionen für ARange (textDocument/codeAction, #399), Reihenfolge des Servers.</summary>
    function CodeActions(const AFileName: string; const ARange: TLspRange): TArray<TLspCodeAction>; overload;
    /// <summary>Wie oben mit eigener Wartezeit, etwa für die Glühbirne der Zeilenleiste (#768), die den Editor
    /// nicht bremsen darf.</summary>
    function CodeActions(const AFileName: string; const ARange: TLspRange;
      ATimeoutMs: Cardinal): TArray<TLspCodeAction>; overload;
    /// <summary>workspace/executeCommand mit Argumenten (JSON-Array, '' = keine, #399); ELspClientError bei
    /// Fehler oder Zeitlimit. Ergebnis gehört dem Aufrufer.</summary>
    function RunCommand(const ACommand, AArgumentsJson: string; ATimeoutMs: Cardinal): TJSONValue;
    /// <summary>Anfrage AMethod mit Parametern (JSON-Objekt, '' = keine), abbrechbar über ACancelled (#1351:
    /// atlas/query); ELspClientError bei Fehler, Abbruch oder Zeitlimit. Ergebnis gehört dem Aufrufer.</summary>
    function RunRequest(const AMethod, AParamsJson: string; ATimeoutMs: Cardinal;
      const ACancelled: TFunc<Boolean>): TJSONValue;
    /// <summary>textDocument/onTypeFormatting (#399): Schnellbefehle nach Enter (ACh = #10) und
    /// ///-Gerüste (ACh = '/'). Leer, wenn der Server nichts ändert.</summary>
    function OnTypeFormatting(const AFileName: string; ALine, ACharacter: Integer; const ACh: string;
      const AOptions: TLspFormatOptions; ATimeoutMs: Cardinal): TArray<TLspTextEdit>;
    /// <summary>textDocument/formatting (#43): Änderungen für die ganze Datei; leer, wenn nichts zu tun ist.
    /// ELspClientError bei Fehler oder Zeitlimit.</summary>
    function Formatting(const AFileName: string; ATabSize: Integer; AInsertSpaces: Boolean;
      ATimeoutMs: Cardinal): TArray<TLspTextEdit>; overload;
    /// <summary>textDocument/rangeFormatting (#43): nur die Zeilen von ARange.</summary>
    function Formatting(const AFileName: string; const ARange: TLspRange; ATabSize: Integer; AInsertSpaces: Boolean;
      ATimeoutMs: Cardinal): TArray<TLspTextEdit>; overload;
    /// <summary>Umgebende Bereiche am Fundort, innen zuerst (textDocument/selectionRange, #399).</summary>
    function SelectionRanges(const AFileName: string; ALine, ACharacter: Integer): TArray<TLspRange>;
    /// <summary>textDocument/linkedEditingRange nur für lokale Bezeichner ("atlasLocals", #658): Antwort des
    /// Servers (Aufrufer gibt frei), nil ohne Antwort. Threadsicher wie die übrigen Anfragen.</summary>
    function LinkedLocals(const AFileName: string; ALine, ACharacter: Integer): TJSONValue;
    /// <summary>Typ des Symbols (textDocument/typeDefinition, #399).</summary>
    function TypeDefinition(const AFileName: string; ALine, ACharacter: Integer): TArray<TLspLocation>;
    function Definition(const AFileName, AText: string; ALine, ACharacter: Integer;
      out ALocation: TLspLocation): Boolean;
    /// <summary>textDocument/definition ohne Abgleich (#505): alle Ziele; Sync vorher.</summary>
    function Definitions(const AFileName: string; ALine, ACharacter: Integer): TArray<TLspLocation>;
    /// <summary>textDocument/declaration ohne Abgleich (#505): alle Ziele; Sync vorher.</summary>
    function Declarations(const AFileName: string; ALine, ACharacter: Integer): TArray<TLspLocation>;
    /// <summary>
    /// textDocument/completion ohne Abgleich: Sync vorher im Hauptthread. Darf aus einem
    /// anderen Thread kommen, solange die Sitzung lebt. Liefert die Antwort (CompletionList,
    /// CompletionItem[] oder nil); der Aufrufer gibt sie frei.
    /// </summary>
    function Completion(const AFileName: string; ALine, ACharacter: Integer; ATimeoutMs: Cardinal): TJSONValue;
      overload;
    /// <summary>Wie oben, gestaffelt (#616): AOnPartial bekommt Teilergebnisse (CompletionItem[]) im
    /// Lese-Thread, bevor die Antwort den Rest bringt. ATrigger: Zeichen, nach dem automatisch geöffnet wurde
    /// (context.triggerCharacter, #448); '' bei Strg+Leer.</summary>
    function Completion(const AFileName: string; ALine, ACharacter: Integer; ATimeoutMs: Cardinal;
      const ATrigger: string; const AOnPartial: TLspPartialProc): TJSONValue; overload;
    /// <summary>textDocument/signatureHelp ohne Abgleich, wie Completion.</summary>
    function SignatureHelp(const AFileName: string; ALine, ACharacter: Integer; ATimeoutMs: Cardinal): TJSONValue;
    /// <summary>textDocument/prepareRename (#397): Lässt sich hier umbenennen? APlaceholder ist der
    /// bisherige Name (aus placeholder, sonst aus dem Bereich in AText).</summary>
    function PrepareRename(const AFileName, AText: string; ALine, ACharacter: Integer;
      out APlaceholder: string): Boolean;
    /// <summary>textDocument/rename (#397): WorkspaceEdit des Servers, gehört dem Aufrufer; nil ohne.</summary>
    function Rename(const AFileName: string; ALine, ACharacter: Integer; const ANewName: string;
      ATimeoutMs: Cardinal): TJSONValue;
    /// <summary>completionItem/resolve für AItem (wird übernommen); threadsicher wie Completion.</summary>
    function ResolveCompletion(AItem: TJSONObject; ATimeoutMs: Cardinal): TJSONValue;
  end;

implementation

function RangeToJson(const ARange: TLspRange): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('start', TJSONObject.Create.AddPair('line', TJSONNumber.Create(ARange.StartPos.Line))
    .AddPair('character', TJSONNumber.Create(ARange.StartPos.Character)));
  Result.AddPair('end', TJSONObject.Create.AddPair('line', TJSONNumber.Create(ARange.EndPos.Line))
    .AddPair('character', TJSONNumber.Create(ARange.EndPos.Character)));
end;

function RangeOf(const AValue: TJSONValue; out ARange: TLspRange): Boolean;
var
  Range: TJSONObject;
begin
  ARange := Default(TLspRange);
  Result := (AValue is TJSONObject) and TJSONObject(AValue).TryGetValue<TJSONObject>('range', Range) and
    Range.TryGetValue<Integer>('start.line', ARange.StartPos.Line) and
    Range.TryGetValue<Integer>('start.character', ARange.StartPos.Character) and
    Range.TryGetValue<Integer>('end.line', ARange.EndPos.Line) and
    Range.TryGetValue<Integer>('end.character', ARange.EndPos.Character);
end;

/// <summary>Parameter von formatting und rangeFormatting ohne Bereich.</summary>
function FormattingParams(const AUri: string; ATabSize: Integer; AInsertSpaces: Boolean): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('textDocument', TJSONObject.Create(TJSONPair.Create('uri', AUri)));
  Result.AddPair('options', TJSONObject.Create.AddPair('tabSize', TJSONNumber.Create(ATabSize))
    .AddPair('insertSpaces', TJSONBool.Create(AInsertSpaces)));
end;

/// <summary>TextEdit[] einer Antwort; gibt AResponse frei.</summary>
function TextEditsOf(AResponse: TJSONValue): TArray<TLspTextEdit>;
var
  Item: TJSONValue;
  Edit: TLspTextEdit;
begin
  Result := nil;
  try
    if AResponse is TJSONArray then
    begin
      for Item in TJSONArray(AResponse) do
      begin
        if TLspTextEdit.FromJson(Item, Edit) then
        begin
          Result := Result + [Edit];
        end;
      end;
    end;
  finally
    AResponse.Free;
  end;
end;

/// <summary>Orte der Antwort auf textDocument/references mit Sicherheit; Einträge ohne Datei fallen weg.</summary>
function ReferenceLocationsOf(const AResponse: TJSONValue): TArray<TLspLocation>;
var
  Item: TJSONValue;
  Location: TLspLocation;
begin
  Result := nil;
  if not (AResponse is TJSONArray) then
  begin
    Exit;
  end;
  for Item in TJSONArray(AResponse) do
  begin
    if not (Item is TJSONObject) then
    begin
      Continue;
    end;
    Location.FileName := TLspSessionJson.UriToPath(TJSONObject(Item).GetValue<string>('uri', ''));
    Location.Line := TJSONObject(Item).GetValue<Integer>('range.start.line', 0);
    Location.Character := TJSONObject(Item).GetValue<Integer>('range.start.character', 0);
    Location.Confidence := TAtlasConfidence.FromJson(Item);
    if Location.FileName <> '' then
    begin
      Result := Result + [Location];
    end;
  end;
end;

function TLspSessionRequests.References(const AFileName: string; ALine, ACharacter: Integer): TArray<TLspLocation>;
var
  Params: TJSONObject;
  Context: TJSONObject;
  Response: TJSONValue;
begin
  Params := PositionParams(AFileName, ALine, ACharacter);
  Context := TJSONObject.Create;
  Context.AddPair('includeDeclaration', TJSONBool.Create(False));
  Params.AddPair('context', Context);
  // Die Suche geht über das ganze Projekt; dafür mehr Zeit als für einen Hover.
  Response := FClient.Request('textDocument/references', Params, FTimeoutMs * 10);
  try
    Result := ReferenceLocationsOf(Response);
  finally
    Response.Free;
  end;
end;

{ TLspSessionRequests }

procedure TLspSessionRequests.Notify(const AMethod: string; AParams: TJSONObject);
begin
  FClient.Notify(AMethod, AParams);
end;

procedure TLspSessionRequests.Saved(const AFileName: string);
begin
  if not IsSynced(AFileName) then
  begin
    Exit;
  end;
  FClient.Notify('textDocument/didSave', TJSONObject.Create(TJSONPair.Create('textDocument',
    TJSONObject.Create(TJSONPair.Create('uri', PathToUri(AFileName))))));
end;

procedure TLspSessionRequests.FilesChanged(const AChanges: TArray<TAtlasFileChange>);
var
  Change: TAtlasFileChange;
  Items: TJSONArray;
  Item: TJSONObject;
begin
  Items := TJSONArray.Create;
  for Change in AChanges do
  begin
    if (Change.Kind = TAtlasFileChangeKind.Changed) and IsSynced(Change.FileName) then
    begin
      Continue;
    end;
    Item := TJSONObject.Create;
    Item.AddPair('uri', PathToUri(Change.FileName));
    Item.AddPair('type', TJSONNumber.Create(Ord(Change.Kind)));
    Items.AddElement(Item);
  end;
  if Items.Count = 0 then
  begin
    Items.Free;
    Exit;
  end;
  FClient.Notify('workspace/didChangeWatchedFiles', TJSONObject.Create(TJSONPair.Create('changes', Items)));
end;

function TLspSessionRequests.Hover(const AFileName, AText: string; ALine, ACharacter: Integer): string;
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

function TLspSessionRequests.HoverParts(const AFileName, AText: string; ALine, ACharacter: Integer): TLspHoverParts;
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

function TLspSessionRequests.HoverData(const AFileName, AText: string; ALine, ACharacter: Integer): TAtlasHoverData;
begin
  Sync(AFileName, AText);
  Result := HoverDataAt(AFileName, ALine, ACharacter);
end;

function TLspSessionRequests.HoverDataAt(const AFileName: string; ALine, ACharacter: Integer): TAtlasHoverData;
var
  Response: TJSONValue;
begin
  Response := FClient.Request('textDocument/hover', PositionParams(AFileName, ALine, ACharacter), FTimeoutMs);
  try
    Result := TAtlasHoverData.FromHover(Response);
  finally
    Response.Free;
  end;
end;

function TLspSessionRequests.Implementations(const AFileName: string; ALine, ACharacter: Integer): TArray<TLspLocation>;
var
  Response: TJSONValue;
begin
  Response := FClient.Request('textDocument/implementation', PositionParams(AFileName, ALine, ACharacter),
    FTimeoutMs * 10);
  try
    Result := LocationsOf(Response);
  finally
    Response.Free;
  end;
end;

function TLspSessionRequests.CodeActions(const AFileName: string; const ARange: TLspRange): TArray<TLspCodeAction>;
begin
  Result := CodeActions(AFileName, ARange, FTimeoutMs * 2);
end;

function TLspSessionRequests.CodeActions(const AFileName: string; const ARange: TLspRange;
  ATimeoutMs: Cardinal): TArray<TLspCodeAction>;
var
  Params, Context: TJSONObject;
  Response, Item: TJSONValue;
  Action: TLspCodeAction;
begin
  Result := nil;
  Context := TJSONObject.Create;
  // Die Befunde der Regeln ermittelt der Server selbst; 1 = ausdrücklich aufgerufen.
  Context.AddPair('diagnostics', TJSONArray.Create);
  Context.AddPair('triggerKind', TJSONNumber.Create(1));
  Params := TJSONObject.Create;
  Params.AddPair('textDocument', TJSONObject.Create(TJSONPair.Create('uri', PathToUri(AFileName))));
  Params.AddPair('range', RangeToJson(ARange));
  Params.AddPair('context', Context);
  Response := FClient.Request('textDocument/codeAction', Params, ATimeoutMs);
  try
    if Response is TJSONArray then
    begin
      for Item in TJSONArray(Response) do
      begin
        if TLspCodeAction.FromJson(Item, Action) then
        begin
          Result := Result + [Action];
        end;
      end;
    end;
  finally
    Response.Free;
  end;
end;

function TLspSessionRequests.RunCommand(const ACommand, AArgumentsJson: string; ATimeoutMs: Cardinal): TJSONValue;
var
  Arguments: TJSONValue;
begin
  Arguments := nil;
  if Trim(AArgumentsJson) <> '' then
  begin
    Arguments := TJSONObject.ParseJSONValue(AArgumentsJson);
  end;
  if not (Arguments is TJSONArray) then
  begin
    Arguments.Free;
    Arguments := TJSONArray.Create;
  end;
  Result := FClient.Request('workspace/executeCommand',
    TJSONObject.Create.AddPair('command', ACommand).AddPair('arguments', Arguments), ATimeoutMs);
end;

function TLspSessionRequests.RunRequest(const AMethod, AParamsJson: string; ATimeoutMs: Cardinal;
  const ACancelled: TFunc<Boolean>): TJSONValue;
var
  mParams: TJSONValue;
begin
  mParams := nil;
  if Trim(AParamsJson) <> '' then
  begin
    mParams := TJSONObject.ParseJSONValue(AParamsJson);
  end;
  if not (mParams is TJSONObject) then
  begin
    mParams.Free;
    mParams := TJSONObject.Create;
  end;
  Result := FClient.RequestCancellable(AMethod, mParams, ATimeoutMs, ACancelled);
end;

function TLspSessionRequests.OnTypeFormatting(const AFileName: string; ALine, ACharacter: Integer;
  const ACh: string; const AOptions: TLspFormatOptions; ATimeoutMs: Cardinal): TArray<TLspTextEdit>;
var
  Params: TJSONObject;
begin
  Params := PositionParams(AFileName, ALine, ACharacter);
  Params.AddPair('ch', ACh);
  Params.AddPair('options', TJSONObject.Create.AddPair('tabSize', TJSONNumber.Create(AOptions.TabSize))
    .AddPair('insertSpaces', TJSONBool.Create(AOptions.InsertSpaces)));
  Result := TextEditsOf(FClient.Request('textDocument/onTypeFormatting', Params, ATimeoutMs));
end;

function TLspSessionRequests.Formatting(const AFileName: string; ATabSize: Integer; AInsertSpaces: Boolean;
  ATimeoutMs: Cardinal): TArray<TLspTextEdit>;
begin
  Result := TextEditsOf(FClient.Request('textDocument/formatting',
    FormattingParams(PathToUri(AFileName), ATabSize, AInsertSpaces), ATimeoutMs));
end;

function TLspSessionRequests.Formatting(const AFileName: string; const ARange: TLspRange; ATabSize: Integer;
  AInsertSpaces: Boolean; ATimeoutMs: Cardinal): TArray<TLspTextEdit>;
var
  Params: TJSONObject;
begin
  Params := FormattingParams(PathToUri(AFileName), ATabSize, AInsertSpaces);
  Params.AddPair('range', RangeToJson(ARange));
  Result := TextEditsOf(FClient.Request('textDocument/rangeFormatting', Params, ATimeoutMs));
end;

function TLspSessionRequests.SelectionRanges(const AFileName: string; ALine, ACharacter: Integer): TArray<TLspRange>;
var
  Params, Position: TJSONObject;
  Positions: TJSONArray;
  Response, Current: TJSONValue;
  Range: TLspRange;
begin
  Result := nil;
  // selectionRange will eine Liste von Positionen statt "position".
  Position := TJSONObject.Create;
  Position.AddPair('line', TJSONNumber.Create(ALine));
  Position.AddPair('character', TJSONNumber.Create(ACharacter));
  Positions := TJSONArray.Create;
  Positions.AddElement(Position);
  Params := TJSONObject.Create;
  Params.AddPair('textDocument', TJSONObject.Create(TJSONPair.Create('uri', PathToUri(AFileName))));
  Params.AddPair('positions', Positions);
  Response := FClient.Request('textDocument/selectionRange', Params, FTimeoutMs);
  try
    if not (Response is TJSONArray) or (TJSONArray(Response).Count = 0) then
    begin
      Exit;
    end;
    Current := TJSONArray(Response).Items[0];
    while RangeOf(Current, Range) do
    begin
      Result := Result + [Range];
      Current := TJSONObject(Current).GetValue('parent');
    end;
  finally
    Response.Free;
  end;
end;

function TLspSessionRequests.LinkedLocals(const AFileName: string; ALine, ACharacter: Integer): TJSONValue;
var
  Params: TJSONObject;
begin
  Params := PositionParams(AFileName, ALine, ACharacter);
  Params.AddPair('atlasLocals', TJSONBool.Create(True));
  Result := FClient.Request('textDocument/linkedEditingRange', Params, FTimeoutMs);
end;

function TLspSessionRequests.TypeDefinition(const AFileName: string; ALine, ACharacter: Integer): TArray<TLspLocation>;
var
  Response: TJSONValue;
begin
  Response := FClient.Request('textDocument/typeDefinition', PositionParams(AFileName, ALine, ACharacter),
    FTimeoutMs * 2);
  try
    Result := LocationsOf(Response);
  finally
    Response.Free;
  end;
end;

function TLspSessionRequests.WorkspaceSymbols(const AQuery: string; ATimeoutMs: Cardinal): TArray<TAtlasSymbol>;
var
  Response, Item: TJSONValue;
  Entry: TJSONObject;
  Symbol: TAtlasSymbol;
  Locations: TArray<TLspLocation>;
  Location: TJSONValue;
begin
  Result := nil;
  Response := FClient.Request('workspace/symbol', TJSONObject.Create(TJSONPair.Create('query', AQuery)), ATimeoutMs);
  try
    if not (Response is TJSONArray) then
    begin
      Exit;
    end;
    for Item in TJSONArray(Response) do
    begin
      if not (Item is TJSONObject) then
      begin
        Continue;
      end;
      Entry := TJSONObject(Item);
      Symbol := Default(TAtlasSymbol);
      Symbol.Name := Entry.GetValue<string>('name', '');
      Symbol.Container := Entry.GetValue<string>('containerName', '');
      Symbol.Kind := Entry.GetValue<Integer>('kind', 0);
      Location := Entry.GetValue('location');
      Locations := LocationsOf(Location);
      if (Symbol.Name = '') or (Length(Locations) = 0) then
      begin
        Continue;
      end;
      Symbol.FileName := Locations[0].FileName;
      Symbol.Line := Locations[0].Line;
      Symbol.Character := Locations[0].Character;
      Result := Result + [Symbol];
    end;
  finally
    Response.Free;
  end;
end;

function TLspSessionRequests.DocumentSymbolTree(const AFileName: string; ATimeoutMs: Cardinal): TJSONValue;
begin
  Result := FClient.Request('textDocument/documentSymbol',
    TJSONObject.Create(TJSONPair.Create('textDocument', TJSONObject.Create(TJSONPair.Create('uri',
    PathToUri(AFileName))))), ATimeoutMs);
end;

function TLspSessionRequests.DocumentSymbols(const AFileName: string; ATimeoutMs: Cardinal): TArray<TAtlasSymbol>;
var
  Response: TJSONValue;
begin
  Response := DocumentSymbolTree(AFileName, ATimeoutMs);
  try
    Result := SymbolsOfDocument(Response, AFileName);
  finally
    Response.Free;
  end;
end;

function TLspSessionRequests.Definition(const AFileName, AText: string; ALine, ACharacter: Integer;
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
    begin
      Item := TJSONArray(Item).Items[0];
    end;
    if not (Item is TJSONObject) then
    begin
      Exit(False);
    end;
    Location := TJSONObject(Item);
    if not Location.TryGetValue<string>('uri', Uri) then
    begin
      Uri := Location.GetValue<string>('targetUri', '');
    end;
    Range := Location.GetValue('range') as TJSONObject;
    if Range = nil then
    begin
      Range := Location.GetValue('targetSelectionRange') as TJSONObject;
    end;
    if (Uri = '') or (Range = nil) then
    begin
      Exit(False);
    end;
    ALocation.FileName := UriToPath(Uri);
    ALocation.Line := Range.GetValue<Integer>('start.line', 0);
    ALocation.Character := Range.GetValue<Integer>('start.character', 0);
    Result := ALocation.FileName <> '';
  finally
    Response.Free;
  end;
end;

function TLspSessionRequests.Definitions(const AFileName: string; ALine, ACharacter: Integer): TArray<TLspLocation>;
var
  Response: TJSONValue;
begin
  Response := FClient.Request('textDocument/definition', PositionParams(AFileName, ALine, ACharacter), FTimeoutMs);
  try
    Result := LocationsOf(Response);
  finally
    Response.Free;
  end;
end;

function TLspSessionRequests.Declarations(const AFileName: string; ALine, ACharacter: Integer): TArray<TLspLocation>;
var
  Response: TJSONValue;
begin
  Response := FClient.Request('textDocument/declaration', PositionParams(AFileName, ALine, ACharacter), FTimeoutMs);
  try
    Result := LocationsOf(Response);
  finally
    Response.Free;
  end;
end;

function TLspSessionRequests.PrepareRename(const AFileName, AText: string; ALine, ACharacter: Integer;
  out APlaceholder: string): Boolean;
var
  Response: TJSONValue;
  Range: TJSONObject;
  Position: TLspTextPosition;
  StartOffset, EndOffset: Integer;
begin
  APlaceholder := '';
  Sync(AFileName, AText);
  Response := FClient.Request('textDocument/prepareRename', PositionParams(AFileName, ALine, ACharacter), FTimeoutMs);
  try
    // Range, {range, placeholder} oder {defaultBehavior}; null heißt: hier nicht.
    if not (Response is TJSONObject) then
    begin
      Exit(False);
    end;
    if TJSONObject(Response).TryGetValue<string>('placeholder', APlaceholder) then
    begin
      Exit(True);
    end;
    if not TJSONObject(Response).TryGetValue<TJSONObject>('range', Range) then
    begin
      Range := TJSONObject(Response);
    end;
    if Range.TryGetValue<Integer>('start.line', Position.Line) and
      Range.TryGetValue<Integer>('start.character', Position.Character) then
    begin
      StartOffset := TLspTextChanges.OffsetOf(AText, Position);
      Position.Line := Range.GetValue<Integer>('end.line', Position.Line);
      Position.Character := Range.GetValue<Integer>('end.character', Position.Character);
      EndOffset := TLspTextChanges.OffsetOf(AText, Position);
      APlaceholder := Copy(AText, StartOffset + 1, EndOffset - StartOffset);
    end;
    Result := True;
  finally
    Response.Free;
  end;
end;

function TLspSessionRequests.Rename(const AFileName: string; ALine, ACharacter: Integer; const ANewName: string;
  ATimeoutMs: Cardinal): TJSONValue;
var
  Params: TJSONObject;
begin
  Params := PositionParams(AFileName, ALine, ACharacter);
  Params.AddPair('newName', ANewName);
  Result := FClient.Request('textDocument/rename', Params, ATimeoutMs);
end;

function TLspSessionRequests.Completion(const AFileName: string; ALine, ACharacter: Integer;
  ATimeoutMs: Cardinal): TJSONValue;
begin
  Result := FClient.Request('textDocument/completion', PositionParams(AFileName, ALine, ACharacter), ATimeoutMs);
end;

function TLspSessionRequests.Completion(const AFileName: string; ALine, ACharacter: Integer; ATimeoutMs: Cardinal;
  const ATrigger: string; const AOnPartial: TLspPartialProc): TJSONValue;
var
  Params: TJSONObject;
begin
  Params := PositionParams(AFileName, ALine, ACharacter);
  // CompletionContext: triggerKind 2 = TriggerCharacter, 1 = Invoked.
  if ATrigger <> '' then
  begin
    Params.AddPair('context', TJSONObject.Create.AddPair('triggerKind', TJSONNumber.Create(2))
      .AddPair('triggerCharacter', ATrigger));
  end;
  Result := FClient.Request('textDocument/completion', Params, ATimeoutMs, AOnPartial);
end;

function TLspSessionRequests.SignatureHelp(const AFileName: string; ALine, ACharacter: Integer;
  ATimeoutMs: Cardinal): TJSONValue;
begin
  Result := FClient.Request('textDocument/signatureHelp', PositionParams(AFileName, ALine, ACharacter), ATimeoutMs);
end;

function TLspSessionRequests.ResolveCompletion(AItem: TJSONObject; ATimeoutMs: Cardinal): TJSONValue;
begin
  Result := FClient.Request('completionItem/resolve', AItem, ATimeoutMs);
end;

end.
