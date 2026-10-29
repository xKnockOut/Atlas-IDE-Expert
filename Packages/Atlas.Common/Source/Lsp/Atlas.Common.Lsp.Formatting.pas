unit Atlas.Common.Lsp.Formatting;

// textDocument/formatting und textDocument/rangeFormatting (#43). Die
// Einstellungen kommen in drei Ebenen: die FormattingOptions des Editors,
// darüber .editorconfig und darüber ausdrücklich gesetzte Werte aus
// "format" in atlas.json. Die Logik liegt in Atlas.Common.Editing.Formatter.
//
// textDocument/onTypeFormatting führt nach Enter Schnellbefehle wie "/uses Unit"
// über das Register aus (#293, "slashCommands"; #254 "usesCommand" bleibt Alias).
// Den Blockabschluss aus #179 gibt es nicht: Den erledigt die IDE selbst.
// Nach dem dritten "/" über einer Deklaration entsteht das Gerüst des
// Dokumentationskommentars (#88, Atlas.Common.Editing.DocComments).

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Editing.EditorConfig,
  Atlas.Common.Editing.SlashCommands;

type
  /// <summary>Delphi-Version (BDS-Nummer) je Dokument; '' = unbekannt.</summary>
  TFormattingVersionFunc = reference to function(const AUri: string): string;

  /// <summary>Eingabehilfe für AUri eingeschaltet, etwa "completeBlocks.docComment" (#88).</summary>
  TFormattingEnabledFunc = reference to function(const AUri: string): Boolean;

  /// <summary>Block "format" aus atlas.json bzw. dem Editor für AUri.</summary>
  TFormatStyleProvider = reference to function(const AUri: string): TFormatStyle;

  TLspFormatting = class
  public const
    Method = 'textDocument/formatting';
    RangeMethod = 'textDocument/rangeFormatting';
    OnTypeMethod = 'textDocument/onTypeFormatting';
  private
    FStore: IDocumentStore;
    FSettingsProvider: TFormatStyleProvider;
    FReadFile: TEditorConfigReadFile;
    FSlashCommandsFor: TSlashCommandsProvider;
    FDelphiVersionFor: TFormattingVersionFunc;
    FDocCommentsFor: TFormattingEnabledFunc;
    FIndex: ISymbolIndex;
    FSlashHost: ISlashHost;
    function HandleOnType(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
    function Handle(const AParams: TJSONValue; AWithRange: Boolean;
      const ACancellation: IJsonRpcCancellationToken): TJSONValue;
    function HandleFormatting(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
    function HandleRangeFormatting(const AParams: TJSONValue;
      const ACancellation: IJsonRpcCancellationToken): TJSONValue;
  public
    constructor Create(const AStore: IDocumentStore; const ASettingsProvider: TFormatStyleProvider;
      const AReadFile: TEditorConfigReadFile);
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>documentOnTypeFormattingProvider: ausgelöst durch Enter und "/" (#88).</summary>
    class function OnTypeCapability: TJSONObject; static;
    /// <summary>Einstellungen für AFileName aus Editor-Optionen, .editorconfig und AConfigured.</summary>
    class function Resolve(const AOptions: TJSONValue; const AFileName: string; const AConfigured: TFormatStyle;
      const AReadFile: TEditorConfigReadFile): TFormatStyle; static;
    /// <summary>Projekt und Editor für Schnellbefehle wie /define und /dfm (#301); nil ohne.</summary>
    property SlashHost: ISlashHost read FSlashHost write FSlashHost;
    /// <summary>Ohne Zuweisung sind alle Schnellbefehle eingeschaltet.</summary>
    property SlashCommandsFor: TSlashCommandsProvider read FSlashCommandsFor write FSlashCommandsFor;
    /// <summary>Delphi-Version je Dokument für versionsabhängige Schnellbefehle (#303); ohne Zuweisung ''.</summary>
    property DelphiVersionFor: TFormattingVersionFunc read FDelphiVersionFor write FDelphiVersionFor;
    /// <summary>"completeBlocks.docComment" (#88); ohne Zuweisung eingeschaltet.</summary>
    property DocCommentsFor: TFormattingEnabledFunc read FDocCommentsFor write FDocCommentsFor;
    /// <summary>Index für Schnellbefehle, die Vorfahren und Interfaces brauchen (#295); nil ohne.</summary>
    property Index: ISymbolIndex read FIndex write FIndex;
  end;

implementation

uses
  System.Generics.Collections,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Lsp.Internals.Cancellation,
  Atlas.Common.Editing.Formatter,
  Atlas.Common.Editing.DocComments;

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
  ADispatcher.RegisterConcurrentRequest(OnTypeMethod, HandleOnType);
end;

class function TLspFormatting.OnTypeCapability: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('firstTriggerCharacter', #10);
  Result.AddPair('moreTriggerCharacter', TJSONArray.Create.Add('/'));
end;

function TLspFormatting.HandleOnType(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  Uri, Character: string;
  Document: ITextDocument;
  PositionValue: TJSONValue;
  Edit: TRuleEdit;
  Edits: TArray<TRuleEdit>;
  Disabled: TArray<string>;
  Item: TJSONObject;
  Version: string;
  Shared: ISharedSyntaxTree;
  Cancellation: IPascalCancellation;
  Configured, Style: TFormatStyle;
  Options: TJSONValue;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', Uri) and
    TJSONObject(AParams).TryGetValue<TJSONValue>('position', PositionValue)) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Felder "textDocument.uri" und "position" fehlen');
  Result := TJSONArray.Create;
  try
    if not TJSONObject(AParams).TryGetValue<string>('ch', Character) or ((Character <> #10) and
      (Character <> '/')) then
      Exit;
    if not FStore.TryGet(Uri, Document) then
      Exit;
    if Character = '/' then
    begin
      // Abgeschaltet: "///" bleibt, wie getippt.
      if Assigned(FDocCommentsFor) and not FDocCommentsFor(Uri) then
        Exit;
      // Abbruchsignal an den Parser (Code-Review A-06).
      Cancellation := TRequestCancellation.Create(ACancellation);
      Shared := TSyntaxTreeCache.Get(Document, Cancellation);
      // Über einer Methodenimplementierung zwei Bearbeitungen: Gerüst an der Deklaration, "///" weg.
      if TDocComments.AfterSlash(Document.Text, Shared.Tree, TLspPositions.ReadPosition(PositionValue), Edits) then
        for Edit in Edits do
        begin
          Item := TJSONObject.Create;
          Item.AddPair('range', TLspPositions.RangeToJson(Edit.Range));
          Item.AddPair('newText', Edit.NewText);
          TJSONArray(Result).AddElement(Item);
        end;
      Exit;
    end;
    Disabled := nil;
    Version := '';
    if Assigned(FDelphiVersionFor) then
      Version := FDelphiVersionFor(Uri);
    // Abgebrochen (Watchdog, $/cancelRequest): keine Schnellbefehle mehr ausführen, die Projekt und Platte
    // ändern (A-06).
    ACancellation.ThrowIfCancellationRequested;
    // Einrückung der Befehle wie beim Formatieren (#43): Editor-Optionen, .editorconfig, "format".
    Configured := TFormatStyle.Default;
    if Assigned(FSettingsProvider) then
      Configured := FSettingsProvider(Uri);
    if not TJSONObject(AParams).TryGetValue<TJSONValue>('options', Options) then
      Options := nil;
    Style := Resolve(Options, TDocumentUris.ToPath(Uri), Configured, FReadFile);
    if (not Assigned(FSlashCommandsFor) or FSlashCommandsFor(Uri, Disabled)) and
      TSlashCommandRegistry.Shared.AfterEnter(Document.Text, TLspPositions.ReadPosition(PositionValue), nil, Disabled,
      FIndex, Version, Uri, FSlashHost, Style, Edits) then
    begin
      for Edit in Edits do
      begin
        Item := TJSONObject.Create;
        Item.AddPair('range', TLspPositions.RangeToJson(Edit.Range));
        Item.AddPair('newText', Edit.NewText);
        TJSONArray(Result).AddElement(Item);
      end;
    end;
  except
    Result.Free;
    raise;
  end;
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
  if TFormatKey.MaxLineLength in AConfigured.Given then
    Result.MaxLineLength := AConfigured.MaxLineLength;
  // Diese Schalter kennt weder der Editor noch .editorconfig (#43).
  Result.Reindent := AConfigured.Reindent;
  Result.BeginPlacement := AConfigured.BeginPlacement;
  Result.ElsePlacement := AConfigured.ElsePlacement;
  Result.AlignAssignments := AConfigured.AlignAssignments;
  Result.AlignDeclarations := AConfigured.AlignDeclarations;
  Result.AlignComments := AConfigured.AlignComments;
  Result.Given := AConfigured.Given;
end;

function TLspFormatting.Handle(const AParams: TJSONValue; AWithRange: Boolean;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
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
  // Die Einstellungen können Dateien lesen (.editorconfig); danach nicht mehr formatieren (A-06).
  ACancellation.ThrowIfCancellationRequested;
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
  Result := Handle(AParams, False, ACancellation);
end;

function TLspFormatting.HandleRangeFormatting(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
begin
  Result := Handle(AParams, True, ACancellation);
end;

end.
