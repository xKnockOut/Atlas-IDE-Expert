unit Atlas.Common.Lsp.Completion;

// Code-Vervollständigung (textDocument/completion), Grundstufe:
//   - nach "A.B." die Mitglieder des Typs von A.B samt geerbter, bei Units deren interface-Symbole,
//   - in uses die bekannten Units,
//   - sonst alle sichtbaren Namen (lokal, eigene Klasse, eigene Unit, Units aus uses).
// Ausgewählt wird unscharf (#229, TFuzzyMatch: Teilfolgen, Kürzel, Wortanfänge) oder mit
// completion.matching = prefix nur nach dem Anfang. Unscharf sortiert die Punktzahl,
// bei Gleichstand der nächste Gültigkeitsbereich; isIncomplete lässt den Editor bei
// jedem Tastendruck neu fragen, filterText verhindert, dass er Treffer verwirft.
// Ab zwei getippten Zeichen kommen Symbole aus noch nicht eingebundenen Units dazu (#180),
// Projekt-Units vor Bibliotheken; additionalTextEdits trägt die Unit beim Annehmen ins uses ein.
// Typauflösung mit Überladungen, Generics, Class Helpern, with, var X := … und Sichtbarkeit liefert der
// NameResolver (#263); private und strict private fremder Klassen bzw. Units und protected außerhalb von
// Nachfahren erscheinen nicht.
//
// Kontexte ohne Typauflösung (#31):
//   - nach "inherited " nur Methoden und Konstruktoren der Vorfahren,
//   - nach "class(", "is", "is not", "as" und nach ":" in Deklarationen (auch inline var) nur Typen,
//   - in "property Name: T read/write " nur Felder und Methoden mit passender Signatur (PropertyItems),
//   - nach "override " im Klassenrumpf die überschreibbaren Methoden der Vorfahren (OverrideItems),
//   - Schlüsselwörter passend zur Stelle (Anweisung, Deklaration, Klassenrumpf), sobald etwas getippt ist.
// In Kommentaren und Strings (auch mehrzeiligen ''' ab Delphi 12) wird nichts vorgeschlagen.
//
// Geschwindigkeit (#616): Ist schon etwas getippt, baut der Resolver nur Kandidaten, deren Name passt
// (NameFilter). isIncomplete kommt nur, wenn die Liste wirklich unvollständig ist (gekürzt, oder Importe
// fehlen noch, weil zu wenig getippt ist); sonst filtert der Editor selbst weiter. Schickt der Client einen
// partialResultToken, kommen die Einträge gestaffelt: eigener Gültigkeitsbereich, Units aus uses, zuletzt
// Importe aus nicht eingebundenen Units ($/progress mit CompletionItem[], der Rest in der Antwort).
//
// Postfix-Vorlagen (#188): Hinter "Ausdruck." kommen nach den Mitgliedern Kürzel wie for, tryf,
// ifa und fmt, die den Ausdruck ersetzen (textEdit ab Ausdrucksbeginn, filterText "Ausdruck.Kürzel"),
// sofern der Typ bekannt ist und passt.
//
// Die Fälle der Anfrage stehen in Atlas.Common.Lsp.Completion.Cases, die allgemeine Liste in
// Atlas.Common.Lsp.Completion.Lists, Rückrufe und Schalter in Atlas.Common.Lsp.Completion.Hooks.

interface

{$SCOPEDENUMS ON}

uses
  System.JSON,
  System.Diagnostics,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.Internals.FormCache,
  Atlas.Common.Lsp.CompletionRequest,
  Atlas.Common.Lsp.CompletionCollector,
  Atlas.Common.Lsp.Completion.Names,
  Atlas.Common.Lsp.Completion.Postfix,
  Atlas.Common.Lsp.Completion.Hooks,
  Atlas.Common.Lsp.Completion.Cases;

type
  // Typen der Vervollständigung stehen in Atlas.Common.Lsp.CompletionRequest und den
  // Completion-Units; hier weiter unter ihrem Namen, damit Aufrufer ohne Änderung übersetzen.
  TCompletionContextKind = Atlas.Common.Lsp.CompletionRequest.TCompletionContextKind;
  TCompletionContext = Atlas.Common.Lsp.CompletionRequest.TCompletionContext;
  TCompletionItem = Atlas.Common.Lsp.CompletionRequest.TCompletionItem;
  TCompletionItems = Atlas.Common.Lsp.CompletionRequest.TCompletionItems;
  TCompletionReadText = Atlas.Common.Lsp.CompletionRequest.TCompletionReadText;
  TCompletionRequest = Atlas.Common.Lsp.CompletionRequest.TCompletionRequest;
  TPostfixOptions = Atlas.Common.Lsp.Completion.Postfix.TPostfixOptions;
  TCompletionNamingFunc = Atlas.Common.Lsp.Completion.Names.TCompletionNamingFunc;
  TCompletionNotifyProc = Atlas.Common.Lsp.Completion.Hooks.TCompletionNotifyProc;
  TCompletionLogProc = Atlas.Common.Lsp.Completion.Hooks.TCompletionLogProc;
  TCompletionHooks = Atlas.Common.Lsp.Completion.Hooks.TCompletionHooks;

  TLspCompletion = class
  public const
    cMethod = 'textDocument/completion';
    cResolveMethod = 'completionItem/resolve';
    /// <summary>Eigene Postfix-Vorlagen vom Plugin (#188).</summary>
    cPostfixTemplatesMethod = 'atlas/postfixTemplates';
    cMaxItems = cCompletionMaxItems;
    /// <summary>Höchstzahl der Vorschläge aus nicht eingebundenen Units.</summary>
    cMaxImportItems = cCompletionMaxImportItems;
  private
    FStore: IDocumentStore;
    FIndex: ISymbolIndex;
    FEnsureUnit: TEnsureUnitFunc;
    FHooks: TCompletionHooks;
    // Zuletzt für completionItem/resolve gelesene Datei (#616): Beim Blättern in der Liste fragt Atlas oft
    // nacheinander Symbole derselben großen Bibliotheks-Unit nach.
    FCacheLock: TObject;
    FCacheFile: string;
    FCacheStamp: TDateTime;
    FCacheText: string;
    // Auszüge der Formulardateien; eigene Sperre.
    FForms: TFormSnapshotCache;
    // Fälle von textDocument/completion in fester Reihenfolge: ohne und mit Syntaxbaum.
    FTextCases: TArray<TCompletionCase>;
    FTreeCases: TArray<TCompletionCase>;
    procedure HandlePostfixTemplates(const AParams: TJSONValue);
    function ReadCached(const AFileName: string; out AText: string): Boolean;
    function Handle(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
    /// <summary>Antwort für ADocument an APosition; AParams (darf nil sein) liefert Auslöser und
    /// partialResultToken.</summary>
    function CompleteDocument(const ADocument: ITextDocument; const AUri: string; const APosition: TTextPosition;
      const AParams: TJSONObject; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
    /// <summary>Antwort im Aufbau mit Formularen, Rückrufen und partialResultToken aus AParams (darf nil sein).
    /// </summary>
    function NewAnswer(const AParams: TJSONObject; const ACancellation: IJsonRpcCancellationToken):
      TCompletionAnswer;
    /// <summary>Die Fälle mit Baum und Resolver und die Liste daraus; ARequest hat den Baum schon.</summary>
    function TreeAnswer(ARequest: TCompletionRequest; AAnswer: TCompletionAnswer;
      const AWatch: TStopwatch): TJSONValue;
    function HandleResolve(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
  public
    constructor Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
      const AEnsureUnit: TEnsureUnitFunc); overload;
    /// <summary>Wie oben mit AEnsureUnit = nil.</summary>
    constructor Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex); overload;
    destructor Destroy; override;
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>CompletionList für eine Momentaufnahme außerhalb des Dokumentspeichers, etwa mit eingefügtem
    /// Ausdruck (#538); ohne Auslöser und ohne Staffelung.</summary>
    function Complete(const ADocument: ITextDocument; const AUri: string; const APosition: TTextPosition;
      const ACancellation: IJsonRpcCancellationToken): TJSONValue;
    /// <summary>completionProvider mit Punkt als Auslöser.</summary>
    class function Capability: TJSONObject; static;
    /// <summary>Meldet der Client textDocument.completion.completionItem.snippetSupport?</summary>
    class function ClientSupportsSnippets(const AInitializeParams: TJSONObject): Boolean; static;
    /// <summary>CompletionList des LSP. Der Aufrufer übernimmt das Objekt.</summary>
    class function ToJson(const AItems: TCompletionItems): TJSONObject; overload; static;
    /// <summary>CompletionItem[]; AFirstSort: sortText des ersten Eintrags (bei Teilergebnissen fortlaufend).</summary>
    class function ToJson(const AItems: TArray<TCompletionItem>; AFirstSort: Integer): TJSONArray; overload; static;
    /// <summary>Rückrufe und Schalter, die die Komposition setzt (Einstellungen je Dokument, Lesen, Melden,
    /// Namensräume, eigene Postfix-Vorlagen).</summary>
    property Hooks: TCompletionHooks read FHooks;
  end;

implementation

uses
  Atlas.Common.Lsp.Completion.Forms,
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Lsp.Documentation,
  Atlas.Common.Lsp.CompletionJson,
  Atlas.Common.Lsp.CompletionSyntax,
  Atlas.Common.Lsp.Internals.Cancellation,
  Atlas.Common.Lsp.Completion.Details,
  Atlas.Common.Diagnostics.RequestScope,
  Atlas.Common.Localization.Texts;

type
  /// <summary>Texte der Vervollständigung in beiden Sprachen (#1458).</summary>
  TCompletionText = (MissingPosition, MissingItem, Timing);

const
  cTexts: array[TCompletionText] of TAtlasText = (
    (De: 'Felder "textDocument.uri" und "position" fehlen'; En: 'Fields "textDocument.uri" and "position" missing'),
    (De: 'CompletionItem fehlt in '; En: 'CompletionItem missing in '),
    (De: 'completion: %d Einträge (%d vorab), unvollständig %s, Baum %d ms, gesamt %d ms';
     En: 'completion: %d items (%d in advance), incomplete %s, tree %d ms, total %d ms'));

/// <summary>Gebundene Typparameter (#450) aus data.bindings von AData.</summary>
function BindingsOf(AData: TJSONObject): TArray<string>;
var
  mBinding: TJSONValue;
begin
  Result := nil;
  if AData.GetValue('bindings') is TJSONArray then
  begin
    for mBinding in TJSONArray(AData.GetValue('bindings')) do
    begin
      Result := Result + [mBinding.Value];
    end;
  end;
end;

/// <summary>Datei und Position aus data von AItem; False ohne.</summary>
function SymbolOf(AItem: TJSONObject; out AData: TJSONObject; out AFileName: string;
  out APosition: TTextPosition): Boolean;
begin
  AData := nil;
  APosition := TTextPosition.Create(0, 0);
  Result := AItem.GetValue('data') is TJSONObject;
  if Result then
  begin
    AData := TJSONObject(AItem.GetValue('data'));
    Result := AData.TryGetValue<string>('file', AFileName) and AData.TryGetValue<Integer>('line', APosition.Line)
      and AData.TryGetValue<Integer>('character', APosition.Character);
  end;
end;

{ TLspCompletion }

constructor TLspCompletion.Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex);
begin
  Create(AStore, AIndex, nil);
end;

constructor TLspCompletion.Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
  const AEnsureUnit: TEnsureUnitFunc);
begin
  inherited Create;
  FStore := AStore;
  FIndex := AIndex;
  FEnsureUnit := AEnsureUnit;
  FHooks := TCompletionHooks.Create;
  FCacheLock := TObject.Create;
  FForms := TFormSnapshotCache.Create;
  FTextCases := TCompletionCases.TextCases;
  FTreeCases := TCompletionCases.TreeCases;
end;

destructor TLspCompletion.Destroy;
begin
  FForms.Free;
  FCacheLock.Free;
  FHooks.Free;
  inherited;
end;

function TLspCompletion.ReadCached(const AFileName: string; out AText: string): Boolean;
var
  mDocument: ITextDocument;
  mStamp: TDateTime;
begin
  // Geöffnete Dateien immer im Stand des Editors; sonst gilt der Zwischenspeicher, solange die Datei
  // unverändert ist.
  if ((FStore <> nil) and FStore.TryGet(TDocumentUris.FromPath(AFileName), mDocument)) or
    not FileAge(AFileName, mStamp) then
  begin
    Exit(FHooks.ReadText(AFileName, AText));
  end;
  System.TMonitor.Enter(FCacheLock);
  try
    if SameText(FCacheFile, AFileName) and (FCacheStamp = mStamp) then
    begin
      AText := FCacheText;
      Exit(True);
    end;
  finally
    System.TMonitor.Exit(FCacheLock);
  end;
  Result := FHooks.ReadText(AFileName, AText);
  if Result then
  begin
    System.TMonitor.Enter(FCacheLock);
    try
      FCacheFile := AFileName;
      FCacheStamp := mStamp;
      FCacheText := AText;
    finally
      System.TMonitor.Exit(FCacheLock);
    end;
  end;
end;

procedure TLspCompletion.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterConcurrentRequest(cMethod, Handle);
  ADispatcher.RegisterConcurrentRequest(cResolveMethod, HandleResolve);
  ADispatcher.RegisterNotification(cPostfixTemplatesMethod, HandlePostfixTemplates);
end;

procedure TLspCompletion.HandlePostfixTemplates(const AParams: TJSONValue);
begin
  FHooks.SetCustomPostfix(TCompletionPostfix.ParseTemplates(AParams));
end;

class function TLspCompletion.Capability: TJSONObject;
var
  mTriggers: TJSONArray;
begin
  mTriggers := TJSONArray.Create;
  mTriggers.Add('.');
  // {$ startet die Vervollständigung von Direktiven (#102).
  mTriggers.Add('$');
  // "/" am Zeilenanfang listet die Schnellbefehle (#293).
  mTriggers.Add('/');
  Result := TJSONObject.Create;
  Result.AddPair('triggerCharacters', mTriggers);
  // Details für das Detailpanel von Atlas erst für den gewählten Eintrag (#405, #424).
  Result.AddPair('resolveProvider', TJSONBool.Create(True));
end;

class function TLspCompletion.ClientSupportsSnippets(const AInitializeParams: TJSONObject): Boolean;
var
  mValue: Boolean;
begin
  Result := (AInitializeParams <> nil) and AInitializeParams.TryGetValue<Boolean>(
    'capabilities.textDocument.completion.completionItem.snippetSupport', mValue) and mValue;
end;

class function TLspCompletion.ToJson(const AItems: TCompletionItems): TJSONObject;
begin
  Result := CompletionListToJson(AItems.Items, AItems.Incomplete, 0);
end;

class function TLspCompletion.ToJson(const AItems: TArray<TCompletionItem>; AFirstSort: Integer): TJSONArray;
begin
  Result := CompletionItemsToJson(AItems, AFirstSort);
end;

function TLspCompletion.Handle(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  mUri: string;
  mPosition: TJSONValue;
  mDocument: ITextDocument;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', mUri) and
    TJSONObject(AParams).TryGetValue<TJSONValue>('position', mPosition)) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams, cTexts[TCompletionText.MissingPosition].Text);
  end;
  if not FStore.TryGet(mUri, mDocument) then
  begin
    TRequestDiagnostics.Reason('documentNotOpen');
    Exit(TJSONNull.Create);
  end;
  Result := CompleteDocument(mDocument, mUri, TLspPositions.ReadPosition(mPosition), TJSONObject(AParams),
    ACancellation);
end;

function TLspCompletion.Complete(const ADocument: ITextDocument; const AUri: string; const APosition: TTextPosition;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
begin
  Result := CompleteDocument(ADocument, AUri, APosition, nil, ACancellation);
end;

function TLspCompletion.NewAnswer(const AParams: TJSONObject; const ACancellation: IJsonRpcCancellationToken):
  TCompletionAnswer;
begin
  Result := TCompletionAnswer.Create;
  Result.Hooks := FHooks;
  Result.Cancellation := ACancellation;
  // Formulare über den Zwischenspeicher der Instanz.
  Result.Forms := TCompletionForms.Cached(FStore, FHooks.ReadText, FForms);
  if Assigned(FHooks.Notify) and (AParams <> nil) and (AParams.GetValue('partialResultToken') is TJSONString) then
  begin
    Result.Token := TJSONString(AParams.GetValue('partialResultToken')).Value;
  end;
end;

function TLspCompletion.CompleteDocument(const ADocument: ITextDocument; const AUri: string;
  const APosition: TTextPosition; const AParams: TJSONObject; const ACancellation: IJsonRpcCancellationToken):
  TJSONValue;
var
  mWatch: TStopwatch;
  mCancellation: IPascalCancellation;
  mTrigger: string;
  mRequest: TCompletionRequest;
  mAnswer: TCompletionAnswer;
  mShared: ISharedSyntaxTree;
begin
  mWatch := TStopwatch.StartNew;
  mCancellation := TRequestCancellation.Create(ACancellation);
  // Eine Anfrage für alle Fälle: Text, Datei, Position und was je Dokument gilt.
  mRequest := TCompletionRequest.Create(ADocument, TDocumentUris.ToPath(AUri), APosition);
  mAnswer := NewAnswer(AParams, ACancellation);
  try
    mRequest.Uri := AUri;
    mRequest.Index := FIndex;
    mRequest.ReadText := FHooks.ReadText;
    if Assigned(FHooks.IdeTypesFor) then
    begin
      mRequest.IdeTypes := FHooks.IdeTypesFor();
    end;
    mTrigger := '';
    if AParams <> nil then
    begin
      AParams.TryGetValue<string>('context.triggerCharacter', mTrigger);
    end;
    mRequest.Trigger := mTrigger;
    if TCompletionCases.Run(FTextCases, mRequest, mAnswer) then
    begin
      Exit(ToJson(mAnswer.Exclusive));
    end;
    mShared := TSyntaxTreeCache.Get(ADocument, mCancellation);
    mRequest.Tree := mShared.Tree;
    ACancellation.ThrowIfCancellationRequested;
    Result := TreeAnswer(mRequest, mAnswer, mWatch);
  finally
    mAnswer.Free;
    mRequest.Free;
  end;
end;

function TLspCompletion.TreeAnswer(ARequest: TCompletionRequest; AAnswer: TCompletionAnswer;
  const AWatch: TStopwatch): TJSONValue;
var
  mParseMs: Int64;
  mResolver: TNameResolver;
  mItems: TArray<TCompletionItem>;
  mCount: Integer;
begin
  mParseMs := AWatch.ElapsedMilliseconds;
  TRequestDiagnostics.Note('treeMs', Integer(mParseMs));
  TRequestDiagnostics.Note('syntaxErr', Length(ARequest.Tree.Diagnostics));
  mResolver := TNameResolver.Create(FIndex, FEnsureUnit);
  try
    mResolver.Namespaces := FHooks.Namespaces;
    ARequest.Resolver := mResolver;
    // Den Baum einmal auswerten für alle Teile der Anfrage.
    mResolver.PinTree(ARequest.Tree, ARequest.FileName);
    try
      ARequest.Settings := FHooks.SettingsOf(ARequest.Uri);
      ARequest.Matching := FHooks.MatchingOf(ARequest.Uri);
      if TCompletionCases.Run(FTreeCases, ARequest, AAnswer) then
      begin
        Exit(ToJson(AAnswer.Exclusive));
      end;
      // Hinweise oben, die vorab gesendeten Einträge nur ohne Staffelung in der Antwort.
      mItems := AAnswer.Hints;
      if AAnswer.Token = '' then
      begin
        mItems := mItems + AAnswer.Prefetched;
      end;
      mItems := mItems + AAnswer.Body + AAnswer.Tail;
      // Vorab als $/progress gesendete Einträge zählen mit (#616).
      mCount := AAnswer.SentCount + Length(mItems);
      Result := CompletionListToJson(mItems, AAnswer.Incomplete, AAnswer.SentCount);
      // Hinweis bei unvollständigem Code (#457): Syntaxfehler vor dem Cursor in der aktuellen Routine.
      if ARequest.Settings.SyntaxNotice then
      begin
        TCompletionSyntax.WriteJson(Result as TJSONObject, TCompletionSyntax.Assess(ARequest.Tree, ARequest.Text,
          ARequest.Position, mCount));
      end;
    finally
      mResolver.UnpinTree;
    end;
  finally
    mResolver.Free;
  end;
  TRequestDiagnostics.ResultCount(mCount);
  if mCount = 0 then
  begin
    TRequestDiagnostics.DefaultReason('noCandidates');
  end;
  if Assigned(FHooks.Log) then
  begin
    FHooks.Log(Format(cTexts[TCompletionText.Timing].Text, [mCount, AAnswer.SentCount,
      BoolToStr(AAnswer.Incomplete, True), mParseMs, AWatch.ElapsedMilliseconds]));
  end;
end;

function TLspCompletion.HandleResolve(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  mItem, mData, mDetails: TJSONObject;
  mDocumentation: TJSONValue;
  mFileName, mText: string;
  mPosition: TTextPosition;
begin
  if not (AParams is TJSONObject) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams, cTexts[TCompletionText.MissingItem].Text +
      cResolveMethod);
  end;
  // Antwort ist der Eintrag selbst, ergänzt um Details; ohne data unverändert.
  mItem := TJSONObject(AParams.Clone);
  Result := mItem;
  if not Assigned(FHooks.ReadText) or not SymbolOf(mItem, mData, mFileName, mPosition) or
    not ReadCached(mFileName, mText) then
  begin
    Exit;
  end;
  mDetails := TCompletionDetails.Details(FIndex, mFileName, mText, mPosition, ReadCached);
  // Gebundene Typparameter (#450): "procedure Add(const Value: T)" wird zu "... Value: TKunde)".
  TCompletionDetails.Bind(mDetails, BindingsOf(mData));
  // Für Atlas (Detailpanel) strukturiert in data.atlas; für andere Clients detail und documentation.
  if mDetails.TryGetValue<string>('declaration', mText) then
  begin
    mItem.RemovePair('detail').Free;
    mItem.AddPair('detail', mText);
  end;
  // Doku als Klartext oder Markdown, je nach documentationFormat des Clients (#31).
  mDocumentation := TCompletionDetails.ResolveDocumentation(mDetails, FHooks.DocumentationMarkdown);
  if mDocumentation <> nil then
  begin
    mItem.AddPair('documentation', mDocumentation);
  end;
  mDetails.RemovePair('documentationMarkdown').Free;
  if Assigned(FHooks.HintsFor) then
  begin
    mDetails.AddPair('xmlDoc', TLspDocumentation.HintsJson(FHooks.HintsFor(TDocumentUris.FromPath(mFileName))));
  end;
  mData.AddPair('atlas', mDetails);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.Completion', cTexts);

end.
