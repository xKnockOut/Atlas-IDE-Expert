unit Atlas.Common.Editing.Formatting.Protocol;

// textDocument/formatting und textDocument/rangeFormatting (#43). Die
// Einstellungen kommen in drei Ebenen: die FormattingOptions des Editors,
// darüber .editorconfig und darüber ausdrücklich gesetzte Werte aus
// "format" in atlas.json. Die Logik liegt in Atlas.Common.Editing.Formatter.
// Mit format.sortUses sortiert das Formatieren der ganzen Datei auch die uses wie
// /sortuses, streicht aber nichts; Formatierungen innerhalb der neu geschriebenen
// uses-Listen entfallen dann.
//
// textDocument/onTypeFormatting führt nach Enter Schnellbefehle wie "/uses Unit"
// über das Register aus (#293, "slashCommands"; #254 "usesCommand" bleibt Alias).
// Den Blockabschluss aus #179 gibt es nicht: Den erledigt die IDE selbst.
// Nach dem dritten "/" über einer Deklaration entsteht das Gerüst des
// Dokumentationskommentars (#88, Atlas.Common.Pascal.DocComments).

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

  /// <summary>Änderungen, die die uses von AContext.Text sortieren, ohne zu streichen; False ohne.</summary>
  TFormattingUsesSortFunc = reference to function(const AContext: TSlashContext;
    out AEdits: TArray<TTextEdit>): Boolean;

  /// <summary>Block "format" aus atlas.json bzw. dem Editor für AUri.</summary>
  TFormatStyleProvider = reference to function(const AUri: string): TFormatStyle;

  TFormattingProtocol = class
  public const
    cMethod = 'textDocument/formatting';
    cRangeMethod = 'textDocument/rangeFormatting';
    cOnTypeMethod = 'textDocument/onTypeFormatting';
  private
    FStore: IDocumentStore;
    FSettingsProvider: TFormatStyleProvider;
    FReadFile: TEditorConfigReadFile;
    FSlashCommandsFor: TSlashCommandsProvider;
    FDelphiVersionFor: TFormattingVersionFunc;
    FDocCommentsFor: TFormattingEnabledFunc;
    FIndex: ISymbolIndex;
    FSlashHost: ISlashHost;
    FSortUses: TFormattingUsesSortFunc;
    /// <summary>Einstellungen für AUri: Editor-Optionen aus AParams, .editorconfig und "format".</summary>
    function StyleFor(AParams: TJSONObject; const AUri: string): TFormatStyle;
    /// <summary>Gerüst des Dokumentationskommentars nach "///" (#88) nach AResult.</summary>
    procedure AddDocComment(const ADocument: ITextDocument; const AUri: string; const APosition: TTextPosition;
      const ACancellation: IJsonRpcCancellationToken; AResult: TJSONArray);
    /// <summary>Schnellbefehl der Zeile vor Enter (#293) nach AResult.</summary>
    procedure AddSlashCommand(AParams: TJSONObject; const ADocument: ITextDocument; const AUri: string;
      const APosition: TTextPosition; const ACancellation: IJsonRpcCancellationToken;
      AResult: TJSONArray);
    /// <summary>Änderungen für die sortierten uses von ADocument (format.sortUses); False ohne.</summary>
    function SortedUses(const ADocument: ITextDocument; const AUri: string; const AStyle: TFormatStyle;
      out AEdits: TArray<TTextEdit>): Boolean;
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
    /// <summary>Projekt und Editor für Schnellbefehle wie /define und /dfm (#301); nil ohne.</summary>
    property SlashHost: ISlashHost read FSlashHost write FSlashHost;
    /// <summary>Sortiert die uses beim Formatieren (format.sortUses); ohne Zuweisung nie.</summary>
    property SortUses: TFormattingUsesSortFunc read FSortUses write FSortUses;
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
  System.Generics.Defaults,
  Atlas.Text.Lines,
  Atlas.Common.Documents.Uris,
  Atlas.Common.JsonRpc.Positions,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Semantics.RequestCancellation,
  Atlas.Common.Editing.Formatter,
  Atlas.Common.Pascal.DocComments,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TFormattingText = (FieldsTextDocumentUriAndPosition, FieldRangeMissingIn, FieldTextDocumentUriMissing);

const
  cTexts: array[TFormattingText] of TAtlasText = (
    (De: 'Felder "textDocument.uri" und "position" fehlen'; En: 'Fields "textDocument.uri" and "position" missing'),
    (De: 'Feld "range" fehlt in '; En: 'Field "range" missing in '),
    (De: 'Feld "textDocument.uri" fehlt'; En: 'Field "textDocument.uri" missing'));

{$SCOPEDENUMS OFF}

{ TFormattingProtocol }

constructor TFormattingProtocol.Create(const AStore: IDocumentStore; const ASettingsProvider: TFormatStyleProvider;
  const AReadFile: TEditorConfigReadFile);
begin
  inherited Create;
  FStore := AStore;
  FSettingsProvider := ASettingsProvider;
  FReadFile := AReadFile;
end;

function TFormattingProtocol.StyleFor(AParams: TJSONObject; const AUri: string): TFormatStyle;
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
  Result := TFormatStyles.Resolve(mOptions, TDocumentUris.ToPath(AUri), mConfigured, FReadFile);
end;

function TFormattingProtocol.HandleOnType(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  mUri, mCharacter: string;
  mDocument: ITextDocument;
  mPositionValue: TJSONValue;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', mUri) and
    TJSONObject(AParams).TryGetValue<TJSONValue>('position', mPositionValue)) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams,
      cTexts[TFormattingText.FieldsTextDocumentUriAndPosition].Text);
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
      AddSlashCommand(TJSONObject(AParams), mDocument, mUri, TLspPositions.ReadPosition(mPositionValue), ACancellation,
        TJSONArray(Result));
    end;
  except
    Result.Free;
    raise;
  end;
end;

/// <summary>Bearbeitungen AEdits als TextEdit[] nach AResult.</summary>
procedure AddEdits(AResult: TJSONArray; const AEdits: TArray<TTextEdit>);
var
  mEdit: TTextEdit;
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

procedure TFormattingProtocol.AddDocComment(const ADocument: ITextDocument; const AUri: string;
  const APosition: TTextPosition; const ACancellation: IJsonRpcCancellationToken; AResult: TJSONArray);
var
  mCancellation: IPascalCancellation;
  mShared: ISharedSyntaxTree;
  mEdits: TArray<TTextEdit>;
begin
  // Abgeschaltet: "///" bleibt, wie getippt.
  if Assigned(FDocCommentsFor) and not FDocCommentsFor(AUri) then
  begin
    Exit;
  end;
  // Abbruchsignal an den Parser.
  mCancellation := TRequestCancellation.Create(ACancellation);
  mShared := TSyntaxTreeCache.Get(ADocument, mCancellation);
  // Über einer Methodenimplementierung zwei Bearbeitungen: Gerüst an der Deklaration, "///" weg.
  if TDocComments.AfterSlash(ADocument.Text, mShared.Tree, APosition, mEdits) then
  begin
    AddEdits(AResult, mEdits);
  end;
end;

procedure TFormattingProtocol.AddSlashCommand(AParams: TJSONObject; const ADocument: ITextDocument; const AUri: string;
  const APosition: TTextPosition; const ACancellation: IJsonRpcCancellationToken; AResult: TJSONArray);
var
  mDisabled: TArray<string>;
  mVersion: string;
  mEdits: TArray<TTextEdit>;
  mEnvironment: TSlashEnvironment;
begin
  mDisabled := nil;
  mVersion := '';
  if Assigned(FDelphiVersionFor) then
  begin
    mVersion := FDelphiVersionFor(AUri);
  end;
  // Abgebrochen (Watchdog, $/cancelRequest): keine Schnellbefehle mehr ausführen, die Projekt und Platte ändern
  //.
  ACancellation.ThrowIfCancellationRequested;
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

function TFormattingProtocol.HandleFormatting(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
begin
  Result := Handle(AParams, False, ACancellation);
end;

function TFormattingProtocol.HandleRangeFormatting(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
begin
  Result := Handle(AParams, True, ACancellation);
end;

procedure TFormattingProtocol.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterConcurrentRequest(cMethod, HandleFormatting);
  ADispatcher.RegisterConcurrentRequest(cRangeMethod, HandleRangeFormatting);
  ADispatcher.RegisterConcurrentRequest(cOnTypeMethod, HandleOnType);
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
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams, cTexts[TFormattingText.FieldRangeMissingIn].Text +
      TFormattingProtocol.cRangeMethod);
  end;
  mRange := TLspPositions.ReadRange(mRangeValue);
  AFirstLine := mRange.StartPos.Line;
  ALastLine := mRange.EndPos.Line;
  if (mRange.EndPos.Character = 0) and (ALastLine > AFirstLine) then
  begin
    Dec(ALastLine);
  end;
end;

/// <summary>Überschneiden sich A und B (auch nur an einer Grenze)?</summary>
function Touches(const A, B: TTextRange): Boolean;
begin
  Result := (TTextPosition.Compare(A.StartPos, B.EndPos) <= 0) and
    (TTextPosition.Compare(B.StartPos, A.EndPos) <= 0);
end;

/// <summary>AFormat ohne die Änderungen, die eine aus AUses berühren, dazu AUses; nach Anfang sortiert.</summary>
function MergeUsesEdits(const AFormat, AUses: TArray<TTextEdit>): TArray<TTextEdit>;
var
  mEdit, mUses: TTextEdit;
  mKeep: Boolean;
  mList: TList<TTextEdit>;
begin
  mList := TList<TTextEdit>.Create;
  try
    for mEdit in AFormat do
    begin
      mKeep := True;
      for mUses in AUses do
      begin
        mKeep := mKeep and not Touches(mEdit.Range, mUses.Range);
      end;
      if mKeep then
      begin
        mList.Add(mEdit);
      end;
    end;
    mList.AddRange(AUses);
    mList.Sort(TComparer<TTextEdit>.Construct(
      function(const A, B: TTextEdit): Integer
      begin
        Result := TTextPosition.Compare(A.Range.StartPos, B.Range.StartPos);
      end));
    Result := mList.ToArray;
  finally
    mList.Free;
  end;
end;

function TFormattingProtocol.SortedUses(const ADocument: ITextDocument; const AUri: string; const AStyle: TFormatStyle;
  out AEdits: TArray<TTextEdit>): Boolean;
var
  mContext: TSlashContext;
begin
  AEdits := nil;
  Result := False;
  if not AStyle.SortUses or not Assigned(FSortUses) then
  begin
    Exit;
  end;
  mContext := Default(TSlashContext);
  mContext.Text := ADocument.Text;
  mContext.Uri := AUri;
  mContext.Index := FIndex;
  mContext.Host := FSlashHost;
  mContext.Style := AStyle;
  Result := FSortUses(mContext, AEdits);
end;

function TFormattingProtocol.Handle(const AParams: TJSONValue; AWithRange: Boolean;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  mUri: string;
  mDocument: ITextDocument;
  mSettings: TFormatStyle;
  mFirstLine, mLastLine: Integer;
  mEdits, mUsesEdits: TArray<TTextEdit>;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', mUri)) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams,
      cTexts[TFormattingText.FieldTextDocumentUriMissing].Text);
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
  // Die Einstellungen können Dateien lesen (.editorconfig); danach nicht mehr formatieren.
  ACancellation.ThrowIfCancellationRequested;
  mEdits := TFormatter.Edits(mDocument.Text, TPascalLexer.Tokenize(mDocument.Text), mSettings, mFirstLine,
    mLastLine);
  // uses nur beim Formatieren der ganzen Datei sortieren, nie streichen.
  if not AWithRange and SortedUses(mDocument, mUri, mSettings, mUsesEdits) then
  begin
    mEdits := MergeUsesEdits(mEdits, mUsesEdits);
  end;
  Result := TJSONArray.Create;
  AddEdits(TJSONArray(Result), mEdits);
end;

class function TFormattingProtocol.OnTypeCapability: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('firstTriggerCharacter', #10);
  Result.AddPair('moreTriggerCharacter', TJSONArray.Create.Add('/'));
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Editing.Formatting.Protocol', cTexts);

end.
