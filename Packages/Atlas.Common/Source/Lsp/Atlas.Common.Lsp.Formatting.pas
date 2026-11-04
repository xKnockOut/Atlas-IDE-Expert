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
  Atlas.Common.Editing.SlashCommands,
  Atlas.Common.Editing.Contract;

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
    /// <summary>Einstellungen für AUri: Editor-Optionen aus AParams, .editorconfig und "format".</summary>
    function StyleFor(AParams: TJSONObject; const AUri: string): TFormatStyle;
    /// <summary>Gerüst des Dokumentationskommentars nach "///" (#88) nach AResult.</summary>
    procedure AddDocComment(const ADocument: ITextDocument; const AUri: string; const APosition: TTextPosition;
      const ACancellation: IJsonRpcCancellationToken; AResult: TJSONArray);
    /// <summary>Schnellbefehl der Zeile vor Enter (#293) nach AResult.</summary>
    procedure AddSlashCommand(AParams: TJSONObject; const ADocument: ITextDocument; const AUri: string;
      const APosition: TTextPosition; AResult: TJSONArray);
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

/// <summary>Bearbeitungen AEdits als TextEdit[] nach AResult.</summary>
procedure AddEdits(AResult: TJSONArray; const AEdits: TArray<TRuleEdit>);
var
  mEdit: TRuleEdit;
  mItem: TJSONObject;
begin
  for mEdit in AEdits do
  begin
    mItem := TJSONObject.Create;
    mItem.AddPair('range', TLspPositions.RangeToJson(mEdit.Range));
    mItem.AddPair('newText', mEdit.NewText);
    AResult.AddElement(mItem);
  end;
end;

function TLspFormatting.StyleFor(AParams: TJSONObject; const AUri: string): TFormatStyle;
var
  mConfigured: TFormatStyle;
  mOptions: TJSONValue;
begin
  mConfigured := TFormatStyle.Default;
  if Assigned(FSettingsProvider) then
  begin
    mConfigured := FSettingsProvider(AUri);
  end;
  if not AParams.TryGetValue<TJSONValue>('options', mOptions) then
  begin
    mOptions := nil;
  end;
  Result := Resolve(mOptions, TDocumentUris.ToPath(AUri), mConfigured, FReadFile);
end;

procedure TLspFormatting.AddDocComment(const ADocument: ITextDocument; const AUri: string;
  const APosition: TTextPosition; const ACancellation: IJsonRpcCancellationToken; AResult: TJSONArray);
var
  mCancellation: IPascalCancellation;
  mShared: ISharedSyntaxTree;
  mEdits: TArray<TRuleEdit>;
begin
  // Abgeschaltet: "///" bleibt, wie getippt.
  if Assigned(FDocCommentsFor) and not FDocCommentsFor(AUri) then
  begin
    Exit;
  end;
  // Abbruchsignal an den Parser (Code-Review A-06).
  mCancellation := TRequestCancellation.Create(ACancellation);
  mShared := TSyntaxTreeCache.Get(ADocument, mCancellation);
  // Über einer Methodenimplementierung zwei Bearbeitungen: Gerüst an der Deklaration, "///" weg.
  if TDocComments.AfterSlash(ADocument.Text, mShared.Tree, APosition, mEdits) then
  begin
    AddEdits(AResult, mEdits);
  end;
end;

procedure TLspFormatting.AddSlashCommand(AParams: TJSONObject; const ADocument: ITextDocument; const AUri: string;
  const APosition: TTextPosition; AResult: TJSONArray);
var
  mDisabled: TArray<string>;
  mVersion: string;
  mEdits: TArray<TRuleEdit>;
  mEnvironment: TSlashEnvironment;
begin
  mDisabled := nil;
  mVersion := '';
  if Assigned(FDelphiVersionFor) then
  begin
    mVersion := FDelphiVersionFor(AUri);
  end;
  if Assigned(FSlashCommandsFor) and not FSlashCommandsFor(AUri, mDisabled) then
  begin
    Exit;
  end;
  // Einrückung der Befehle wie beim Formatieren (#43): Editor-Optionen, .editorconfig, "format".
  mEnvironment := TSlashEnvironment.Create(nil, mDisabled, FIndex, mVersion, AUri, FSlashHost).WithStyle(
    StyleFor(AParams, AUri));
  if TSlashCommandRegistry.Shared.AfterEnter(ADocument.Text, APosition, mEnvironment, mEdits) then
  begin
    AddEdits(AResult, mEdits);
  end;
end;

function TLspFormatting.HandleOnType(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  mUri, mCharacter: string;
  mDocument: ITextDocument;
  mPositionValue: TJSONValue;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', mUri) and
    TJSONObject(AParams).TryGetValue<TJSONValue>('position', mPositionValue)) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Felder "textDocument.uri" und "position" fehlen');
  end;
  Result := TJSONArray.Create;
  try
    if not TJSONObject(AParams).TryGetValue<string>('ch', mCharacter) or not FStore.TryGet(mUri, mDocument) then
    begin
      Exit;
    end;
    if mCharacter = '/' then
    begin
      AddDocComment(mDocument, mUri, TLspPositions.ReadPosition(mPositionValue), ACancellation, TJSONArray(Result));
    end
    else if mCharacter = #10 then
    begin
      // Abgebrochen (Watchdog, $/cancelRequest): keine Schnellbefehle mehr ausführen, die Projekt und Platte
      // ändern (A-06).
      ACancellation.ThrowIfCancellationRequested;
      AddSlashCommand(TJSONObject(AParams), mDocument, mUri, TLspPositions.ReadPosition(mPositionValue),
        TJSONArray(Result));
    end;
  except
    Result.Free;
    raise;
  end;
end;

/// <summary>Einstellungen aus den FormattingOptions des Editors (AOptions, nil = keine).</summary>
function EditorStyle(const AOptions: TJSONValue): TFormatStyle;
var
  mSize: Integer;
  mFlag: Boolean;
begin
  Result := TFormatStyle.Default;
  if not (AOptions is TJSONObject) then
  begin
    Exit;
  end;
  if AOptions.TryGetValue<Integer>('tabSize', mSize) and (mSize >= 1) then
  begin
    Result.IndentSize := mSize;
  end;
  if AOptions.TryGetValue<Boolean>('insertSpaces', mFlag) then
  begin
    Result.UseTabs := not mFlag;
  end;
  if AOptions.TryGetValue<Boolean>('trimTrailingWhitespace', mFlag) then
  begin
    Result.TrimTrailingWhitespace := mFlag;
  end;
  if AOptions.TryGetValue<Boolean>('insertFinalNewline', mFlag) then
  begin
    Result.InsertFinalNewline := mFlag;
  end;
end;

/// <summary>Übernimmt Einrückung, Schreibweise und Zeilenende-Leerraum, wenn AConfigured sie ausdrücklich setzt.
/// </summary>
procedure ApplyGivenLayout(var AStyle: TFormatStyle; const AConfigured: TFormatStyle);
begin
  if TFormatKey.IndentSize in AConfigured.Given then
  begin
    AStyle.IndentSize := AConfigured.IndentSize;
  end;
  if TFormatKey.UseTabs in AConfigured.Given then
  begin
    AStyle.UseTabs := AConfigured.UseTabs;
  end;
  if TFormatKey.KeywordCase in AConfigured.Given then
  begin
    AStyle.KeywordCase := AConfigured.KeywordCase;
  end;
  if TFormatKey.TrimTrailingWhitespace in AConfigured.Given then
  begin
    AStyle.TrimTrailingWhitespace := AConfigured.TrimTrailingWhitespace;
  end;
  if TFormatKey.InsertFinalNewline in AConfigured.Given then
  begin
    AStyle.InsertFinalNewline := AConfigured.InsertFinalNewline;
  end;
end;

/// <summary>Übernimmt Abstände, Zeilenende und Zeilenlänge, wenn AConfigured sie ausdrücklich setzt.</summary>
procedure ApplyGivenSpacing(var AStyle: TFormatStyle; const AConfigured: TFormatStyle);
begin
  if TFormatKey.SpaceAroundAssignment in AConfigured.Given then
  begin
    AStyle.SpaceAroundAssignment := AConfigured.SpaceAroundAssignment;
  end;
  if TFormatKey.SpaceAfterComma in AConfigured.Given then
  begin
    AStyle.SpaceAfterComma := AConfigured.SpaceAfterComma;
  end;
  if TFormatKey.EndOfLine in AConfigured.Given then
  begin
    AStyle.EndOfLine := AConfigured.EndOfLine;
  end;
  if TFormatKey.MaxLineLength in AConfigured.Given then
  begin
    AStyle.MaxLineLength := AConfigured.MaxLineLength;
  end;
end;

class function TLspFormatting.Resolve(const AOptions: TJSONValue; const AFileName: string;
  const AConfigured: TFormatStyle; const AReadFile: TEditorConfigReadFile): TFormatStyle;
begin
  Result := EditorStyle(AOptions);
  if Assigned(AReadFile) and (AFileName <> '') then
  begin
    Result := TEditorConfig.ForFile(AFileName, AReadFile, Result);
  end;
  ApplyGivenLayout(Result, AConfigured);
  ApplyGivenSpacing(Result, AConfigured);
  // Diese Schalter kennt weder der Editor noch .editorconfig (#43).
  Result.Reindent := AConfigured.Reindent;
  Result.BeginPlacement := AConfigured.BeginPlacement;
  Result.ElsePlacement := AConfigured.ElsePlacement;
  Result.AlignAssignments := AConfigured.AlignAssignments;
  Result.AlignDeclarations := AConfigured.AlignDeclarations;
  Result.AlignComments := AConfigured.AlignComments;
  Result.Given := AConfigured.Given;
end;

/// <summary>Zeilen des Felds "range" von rangeFormatting; ein Bereich bis zum Anfang einer Zeile schließt diese
/// Zeile nicht ein.</summary>
procedure RangeLines(AParams: TJSONObject; out AFirstLine, ALastLine: Integer);
var
  mRangeValue: TJSONValue;
  mRange: TTextRange;
begin
  if not AParams.TryGetValue<TJSONValue>('range', mRangeValue) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Feld "range" fehlt in ' +
      TLspFormatting.RangeMethod);
  end;
  mRange := TLspPositions.ReadRange(mRangeValue);
  AFirstLine := mRange.StartPos.Line;
  ALastLine := mRange.EndPos.Line;
  if (mRange.EndPos.Character = 0) and (ALastLine > AFirstLine) then
  begin
    Dec(ALastLine);
  end;
end;

function TLspFormatting.Handle(const AParams: TJSONValue; AWithRange: Boolean;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  mUri: string;
  mDocument: ITextDocument;
  mSettings: TFormatStyle;
  mFirstLine, mLastLine: Integer;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', mUri)) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Feld "textDocument.uri" fehlt');
  end;
  if not FStore.TryGet(mUri, mDocument) then
  begin
    Exit(TJSONNull.Create);
  end;
  mSettings := StyleFor(TJSONObject(AParams), mUri);
  mFirstLine := 0;
  mLastLine := -1;
  if AWithRange then
  begin
    RangeLines(TJSONObject(AParams), mFirstLine, mLastLine);
  end;
  // Die Einstellungen können Dateien lesen (.editorconfig); danach nicht mehr formatieren (A-06).
  ACancellation.ThrowIfCancellationRequested;
  Result := TJSONArray.Create;
  AddEdits(TJSONArray(Result), TFormatter.Edits(mDocument.Text, TPascalLexer.Tokenize(mDocument.Text), mSettings,
    mFirstLine, mLastLine));
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
