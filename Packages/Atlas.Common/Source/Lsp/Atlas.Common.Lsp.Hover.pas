unit Atlas.Common.Lsp.Hover;

// Hover (textDocument/hover): Deklaration und XML-Dokumentation (///) des
// Symbols unter dem Cursor als Markdown.
//
// Den Inhalt sammelt TLspHoverLookup (Atlas.Common.Lsp.Hover.Lookup), die
// Darstellungen liefert THoverInfo (Atlas.Common.Lsp.Hover.Info): als Markdown
// in contents, als Klartext für Clients ohne Markdown und strukturiert mit den
// Fundorten der cref-Verweise in atlas.documentation.
//
// Clients ohne Markdown (RAD Studio meldet hover.contentFormat ["plaintext"])
// bekommen denselben Inhalt als Klartext (#175).
//
// Für den Atlas-Tooltip (#588) kommen Art, Herkunft, Fundort, Typverweise in der
// Deklaration und die Vererbungskette dazu (Atlas.Common.Lsp.HoverTypes). Ist die
// Datei nicht geöffnet, liest der Hover sie selbst: So fragt das Plugin einen
// angeklickten Typ über seinen Fundort ab.
//
// In FieldByName('…'), FindField('…') und ParamByName('…') meldet der Hover
// einen Namen, den die Datenmenge laut Formulardatei nicht kennt, als Hinweis
// „Feld nicht gefunden in qryOrders“ (#461); keine Diagnose.
//
// Begründungen (// WHY: …, #1123) des Symbols bzw. der Unit kommen aus dem
// Index (TLspRationale.OfSymbol) und erscheinen nach der XMLDoc, gefiltert nach
// hints.rationale und hints.rationaleMarkers; im Atlas-Tooltip als Abschnitte
// "rationale" der strukturierten Doku mit anklickbaren ADR- und Issue-Verweisen.
//
// Wird der Name neu zugewiesen (#712), nennt atlas.reassigned das Ziel
// (locals, valueParams …), die Zahl der Zuweisungen und ihre Zeilen; das
// Plugin zeigt das unter der Unterstreichung.

interface

uses
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.Documentation,
  Atlas.Common.Lsp.ConditionalSymbols,
  Atlas.Common.Lsp.Rationale,
  Atlas.Common.Lsp.Hover.Info;

type
  /// <summary>Liefert den Text einer Datei; False, wenn sie nicht lesbar ist.</summary>
  THoverReadText = TDocReadText;
  /// <summary>Delphi-Version des Dokuments AUri (z. B. "23.0"); '' = unbekannt.</summary>
  THoverVersionProvider = reference to function(const AUri: string): string;
  /// <summary>Einstellungen der Begründungen für das Dokument AUri (#1123).</summary>
  THoverRationaleProvider = reference to function(const AUri: string): TRationaleOptions;
  /// <summary>Inhalt eines Hovers, siehe Atlas.Common.Lsp.Hover.Info.</summary>
  THoverInfo = Atlas.Common.Lsp.Hover.Info.THoverInfo;
  /// <summary>Namensauflösung, Index und Lesen anderer Dateien für InfoAt.</summary>
  THoverSource = Atlas.Common.Lsp.Hover.Info.THoverSource;

  TLspHover = class
  public const
    Method = 'textDocument/hover';
  private
    FStore: IDocumentStore;
    FIndex: ISymbolIndex;
    FEnsureUnit: TEnsureUnitFunc;
    FReadText: THoverReadText;
    FNamespaces: TArray<string>;
    FVersionProvider: THoverVersionProvider;
    FHintsFor: TDocHintsProvider;
    FSymbolsFor: TConditionalContextFunc;
    FRationaleFor: THoverRationaleProvider;
    FMarkdown: Boolean;
    function HandleHover(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
    function OpenTree(const AUri: string; const ACancellation: IPascalCancellation; out AText: string;
      out AShared: ISharedSyntaxTree; out AOwnTree: TSyntaxTree): TSyntaxTree;
    function AnswerAt(const AUri, AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
      const ACancellation: IJsonRpcCancellationToken): TJSONValue;
    function DirectiveHover(const AUri, AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
      const ADelphiVersion: string; out AMarkdown: string): Boolean;
    function SymbolInfo(const AUri, AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
      const ADelphiVersion: string): THoverInfo;
    procedure ApplySettings(const AUri: string; var AInfo: THoverInfo);
    function InfoAnswer(const AUri: string; const AInfo: THoverInfo): TJSONObject;
  private
    /// <summary>Unter TLspNamespaces gelesen und ersetzt (Code-Review A-03): Die Komposition setzt sie
    /// beim Laden eines Projekts, Anfragen lesen sie in Worker-Threads.</summary>
    function GetNamespaces: TArray<string>;
    procedure SetNamespaces(const AValue: TArray<string>);
  public
    constructor Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex; const AReadText: THoverReadText;
      const AEnsureUnit: TEnsureUnitFunc); overload;
    /// <summary>Wie oben mit AEnsureUnit = nil.</summary>
    constructor Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
      const AReadText: THoverReadText); overload;
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>Hover-Inhalt an APosition; ATreeText ist der Text von ATree.</summary>
    class function InfoAt(const ASource: THoverSource; ATree: TSyntaxTree; const ATreeText, AFileName: string;
      const APosition: TTextPosition; const ADelphiVersion: string): THoverInfo; overload; static;
    /// <summary>Wie oben mit ADelphiVersion = ''.</summary>
    class function InfoAt(const ASource: THoverSource; ATree: TSyntaxTree; const ATreeText, AFileName: string;
      const APosition: TTextPosition): THoverInfo; overload; static;
    /// <summary>False, wenn der Client in initialize nur Klartext für Hover meldet.</summary>
    class function ClientSupportsMarkdown(const AInitializeParams: TJSONObject): Boolean; static;
    /// <summary>„Feld nicht gefunden in qryOrders“ (#461), wenn APosition im Namen eines FieldByName-, FindField-
    /// oder ParamByName-Aufrufs steht, die Formulardatei Namen für die Datenmenge kennt und dieser nicht dabei ist.
    /// </summary>
    class function DataNameHint(const AIndex: ISymbolIndex; const AText, AFileName: string; const APosition: TTextPosition;
      const AReadText: THoverReadText; out AHint: string): Boolean; static;
    /// <summary>Teile des Hovers für den Atlas-Tooltip (#442): Doku strukturiert in documentation (#654) und
    /// als Klartext in documentationText, Hinweis als Klartext.</summary>
    class function AtlasJson(const AInfo: THoverInfo): TJSONObject; static;
    /// <summary>Trägt in AInfo ein, ob der Name an APosition neu zugewiesen wird (#712).</summary>
    class procedure AddReassigned(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName, AText: string;
      const APosition: TTextPosition; var AInfo: THoverInfo); static;
    /// <summary>Antwort als Markdown (Vorgabe) oder als Klartext.</summary>
    property Markdown: Boolean read FMarkdown write FMarkdown;
    property Namespaces: TArray<string> read GetNamespaces write SetNamespaces;
    /// <summary>Für den Release-Namen der DocWiki-Links; ohne Provider gilt die neueste Version.</summary>
    property VersionProvider: THoverVersionProvider read FVersionProvider write FVersionProvider;
    /// <summary>Anzeige von XMLDoc (#654) als atlas.xmlDoc; ohne Provider fehlt das Feld.</summary>
    property HintsFor: TDocHintsProvider read FHintsFor write FHintsFor;
    /// <summary>Symbole des Dokuments und Schalter directives.hover (#102); ohne Provider an, ohne Projekt.
    /// </summary>
    property SymbolsFor: TConditionalContextFunc read FSymbolsFor write FSymbolsFor;
    /// <summary>Begründungen (#1123); ohne Provider die Vorgaben ohne ADR-Ordner.</summary>
    property RationaleFor: THoverRationaleProvider read FRationaleFor write FRationaleFor;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.Diagnostics,
  Atlas.Common.Lsp.Internals.Namespaces,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Lsp.CompilerDirectives,
  Atlas.Common.Lsp.KeywordReference,
  Atlas.Common.Lsp.Hover.Lookup,
  Atlas.Common.Diagnostics.RequestScope,
  Atlas.Common.Lsp.Internals.Cancellation,
  Atlas.Common.Editing.DataFieldNames,
  Atlas.Common.Semantics.Reassigned,
  Atlas.Common.Lsp.Reassigned,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  THoverText = (FieldsTextDocumentUriAndPosition, ParameterNotFoundIn, FieldNotFoundIn);

const
  cTexts: array[THoverText] of TAtlasText = (
    (De: 'Felder "textDocument.uri" und "position" fehlen in ';
     En: 'Fields "textDocument.uri" and "position" missing in '),
    (De: 'Parameter nicht gefunden in %s'; En: 'Parameter not found in %s'),
    (De: 'Feld nicht gefunden in %s'; En: 'Field not found in %s'));

{$SCOPEDENUMS OFF}

const
  cSectionBreak = #10#10'---'#10#10;

/// <summary>Antwort mit AMarkdown als Inhalt.</summary>
function MarkdownAnswer(const AMarkdown: string): TJSONObject;
var
  mContents: TJSONObject;
begin
  mContents := TJSONObject.Create;
  mContents.AddPair('kind', 'markdown');
  mContents.AddPair('value', AMarkdown);
  Result := TJSONObject.Create;
  Result.AddPair('contents', mContents);
end;

/// <summary>Bedingtes Symbol an APosition und Wert der Bedingung mit Teilwerten (#847), Bedingung zuerst.</summary>
function SymbolHover(const AText: string; const APosition: TTextPosition; const ASymbols: TConditionalContext;
  out AMarkdown: string): Boolean;
var
  mCondition: string;
begin
  Result := TConditionalSymbols.Hover(AText, APosition, ASymbols, AMarkdown);
  if TConditionalSymbols.ConditionHover(AText, APosition, ASymbols, mCondition) then
  begin
    if Result then
    begin
      AMarkdown := mCondition + cSectionBreak + AMarkdown;
    end
    else
    begin
      AMarkdown := mCondition;
    end;
    Result := True;
  end;
end;

/// <summary>Werte von textDocument.uri und position; Fehler der Anfrage, wenn eins fehlt.</summary>
procedure ReadParams(const AParams: TJSONValue; out AUri: string; out APosition: TTextPosition);
var
  mPosition: TJSONValue;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', AUri) and
    TJSONObject(AParams).TryGetValue<TJSONValue>('position', mPosition)) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
      cTexts[THoverText.FieldsTextDocumentUriAndPosition].Text + TLspHover.Method);
  end;
  APosition := TLspPositions.ReadPosition(mPosition);
end;

{ TLspHover }

function TLspHover.GetNamespaces: TArray<string>;
begin
  Result := TLspNamespaces.Read(FNamespaces);
end;

procedure TLspHover.SetNamespaces(const AValue: TArray<string>);
begin
  TLspNamespaces.Write(FNamespaces, AValue);
end;

constructor TLspHover.Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
  const AReadText: THoverReadText);
begin
  Create(AStore, AIndex, AReadText, nil);
end;

constructor TLspHover.Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
  const AReadText: THoverReadText; const AEnsureUnit: TEnsureUnitFunc);
begin
  inherited Create;
  FStore := AStore;
  FIndex := AIndex;
  FReadText := AReadText;
  FEnsureUnit := AEnsureUnit;
  FMarkdown := True;
end;

procedure TLspHover.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterConcurrentRequest(Method, HandleHover);
end;

class function TLspHover.ClientSupportsMarkdown(const AInitializeParams: TJSONObject): Boolean;
var
  mFormats: TJSONArray;
  mItem: TJSONValue;
begin
  // Ohne Angabe bleibt es bei Markdown, wie bisher.
  if (AInitializeParams = nil) or
    not AInitializeParams.TryGetValue<TJSONArray>('capabilities.textDocument.hover.contentFormat', mFormats) or
    (mFormats.Count = 0) then
  begin
    Exit(True);
  end;
  for mItem in mFormats do
  begin
    if SameText(mItem.Value, 'markdown') then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TLspHover.InfoAt(const ASource: THoverSource; ATree: TSyntaxTree; const ATreeText,
  AFileName: string; const APosition: TTextPosition): THoverInfo;
begin
  Result := InfoAt(ASource, ATree, ATreeText, AFileName, APosition, '');
end;

class function TLspHover.InfoAt(const ASource: THoverSource; ATree: TSyntaxTree; const ATreeText,
  AFileName: string; const APosition: TTextPosition; const ADelphiVersion: string): THoverInfo;
begin
  Result := TLspHoverLookup.InfoAt(ASource, ATree, ATreeText, AFileName, APosition, ADelphiVersion);
end;

class function TLspHover.AtlasJson(const AInfo: THoverInfo): TJSONObject;
begin
  Result := AInfo.ToAtlasJson;
end;

class procedure TLspHover.AddReassigned(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName,
  AText: string; const APosition: TTextPosition; var AInfo: THoverInfo);
var
  mSymbol: TReassignedSymbol;
begin
  if not TReassigned.SymbolAt(TLspReassigned.Analyze(AResolver, ATree, AFileName, AText), APosition, mSymbol) or
    not mSymbol.IsReassigned then
  begin
    Exit;
  end;
  AInfo.ReassignedTarget := TReassigned.TargetNames[mSymbol.Target];
  AInfo.ReassignedWrites := mSymbol.WriteCount;
  AInfo.ReassignedLines := mSymbol.WriteLines;
end;

class function TLspHover.DataNameHint(const AIndex: ISymbolIndex; const AText, AFileName: string;
  const APosition: TTextPosition; const AReadText: THoverReadText; out AHint: string): Boolean;
var
  mLines: TArray<string>;
  mCall: TDataNameCall;
  mSql: string;
  mNames: TArray<TDataName>;
  mFound: Boolean;
begin
  AHint := '';
  Result := False;
  mLines := AText.Split([#10]);
  if (APosition.Line < 0) or (APosition.Line > High(mLines)) or not Assigned(AReadText) or
    not TDataFieldNames.CallAt(mLines[APosition.Line].TrimRight([#13]), APosition.Character, mCall) or
    (mCall.Content = '') then
  begin
    Exit;
  end;
  mNames := TDataFieldNames.Lookup(TDataLookupSource.Create(AText, AFileName, AIndex,
    function(const AName: string; out AContent: string): Boolean
    begin
      Result := AReadText(AName, AContent);
    end), mCall, mSql, mFound);
  // Ohne bekannte Namen (select * ohne Schema) lässt sich nichts sagen.
  if not mFound or (Length(mNames) = 0) or TDataFieldNames.Contains(mNames, mCall.Content) then
  begin
    Exit;
  end;
  if mCall.Kind = TDataNameKind.Param then
  begin
    AHint := cTexts[THoverText.ParameterNotFoundIn].Fmt([mCall.DisplayName]);
  end
  else
  begin
    AHint := cTexts[THoverText.FieldNotFoundIn].Fmt([mCall.DisplayName]);
  end;
  Result := True;
end;

function TLspHover.OpenTree(const AUri: string; const ACancellation: IPascalCancellation; out AText: string;
  out AShared: ISharedSyntaxTree; out AOwnTree: TSyntaxTree): TSyntaxTree;
var
  mDocument: ITextDocument;
  mWatch: TStopwatch;
begin
  Result := nil;
  AShared := nil;
  AOwnTree := nil;
  if FStore.TryGet(AUri, mDocument) then
  begin
    AText := mDocument.Text;
    // Wartet, wenn ein anderer Thread dieselbe Version gerade parst (#647).
    mWatch := TStopwatch.StartNew;
    AShared := TSyntaxTreeCache.Get(mDocument, ACancellation);
    TRequestDiagnostics.Note('treeMs', Integer(mWatch.ElapsedMilliseconds));
    // Der Baum lebt, solange der Aufrufer AShared hält.
    Result := AShared.Tree;
  end
  // Nicht geöffnete Datei (Typ aus dem Atlas-Tooltip angeklickt, #588): selbst lesen.
  else if Assigned(FReadText) and FReadText(TDocumentUris.ToPath(AUri), AText) then
  begin
    AOwnTree := TSyntaxTreeCache.Parse(AText, ACancellation);
    Result := AOwnTree;
  end;
end;

function TLspHover.DirectiveHover(const AUri, AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
  const ADelphiVersion: string; out AMarkdown: string): Boolean;
var
  mSymbols: TConditionalContext;
  mSymbol: string;
  mHasDirective: Boolean;
begin
  // Compiler-Direktiven wie {$R+} oder {$WARN …} und bedingte Symbole mit Zustand und Herkunft (#102).
  AMarkdown := '';
  mSymbols := TConditionalContext.Default;
  if Assigned(FSymbolsFor) then
  begin
    mSymbols := FSymbolsFor(AUri);
  end;
  Result := False;
  if not mSymbols.HoverEnabled then
  begin
    Exit;
  end;
  Result := SymbolHover(AText, APosition, mSymbols, mSymbol);
  mHasDirective := TCompilerDirectives.HoverAt(ATree, APosition, ADelphiVersion, AMarkdown);
  if Result and mHasDirective then
  begin
    AMarkdown := mSymbol + cSectionBreak + AMarkdown;
  end
  else if Result then
  begin
    AMarkdown := mSymbol;
  end;
  Result := Result or mHasDirective;
end;

procedure TLspHover.ApplySettings(const AUri: string; var AInfo: THoverInfo);
var
  mRationale: TRationaleOptions;
begin
  // published-Mitglieder abschaltbar (hints.publishedMembers, #110).
  if Assigned(FHintsFor) and not FHintsFor(AUri).PublishedMembers then
  begin
    AInfo.Members := '';
    AInfo.PublishedItems := nil;
    AInfo.DefaultProperty := '';
  end;
  // Begründungen nach hints.rationale, hints.rationaleMarkers und hints.adrFolder (#1123).
  mRationale := TRationaleOptions.Default;
  if Assigned(FRationaleFor) then
  begin
    mRationale := FRationaleFor(AUri);
  end;
  AInfo.Rationale := TLspRationale.Select(AInfo.Rationale, mRationale);
  if Length(AInfo.Rationale) > 0 then
  begin
    AInfo.AdrFiles := TLspRationale.AdrFiles(mRationale.AdrFolder);
  end;
end;

function TLspHover.SymbolInfo(const AUri, AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
  const ADelphiVersion: string): THoverInfo;
var
  mResolver: TNameResolver;
begin
  mResolver := TNameResolver.Create(FIndex, FEnsureUnit);
  try
    mResolver.Namespaces := Namespaces;
    Result := InfoAt(THoverSource.Create(mResolver, FIndex, FReadText), ATree, AText, TDocumentUris.ToPath(AUri),
      APosition, ADelphiVersion);
    // Wie oft der Name geschrieben wird, für die Unterstreichung im Plugin (#712).
    if Result.Found then
    begin
      AddReassigned(mResolver, ATree, TDocumentUris.ToPath(AUri), AText, APosition, Result);
    end;
  finally
    mResolver.Free;
  end;
  ApplySettings(AUri, Result);
end;

function TLspHover.InfoAnswer(const AUri: string; const AInfo: THoverInfo): TJSONObject;
var
  mAtlas: TJSONObject;
begin
  if FMarkdown then
  begin
    Result := MarkdownAnswer(AInfo.ToMarkdown);
  end
  else
  begin
    // Klartext als einfacher String und ohne "range", genau wie DelphiLSP
    // antwortet. RAD Studio zeigt den Hover benutzerdefinierter Server trotzdem
    // nicht als Tooltip an; dafür braucht es ein IDE-Plugin (#175).
    Result := TJSONObject.Create;
    Result.AddPair('contents', AInfo.ToPlainText);
  end;
  // Für den Atlas-Tooltip (#442, #588) die Teile einzeln; andere Clients ignorieren das Feld.
  mAtlas := AInfo.ToAtlasJson;
  if Assigned(FHintsFor) then
  begin
    mAtlas.AddPair('xmlDoc', TLspDocumentation.HintsJson(FHintsFor(AUri)));
  end;
  Result.AddPair('atlas', mAtlas);
end;

function TLspHover.AnswerAt(const AUri, AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  mDelphiVersion, mMarkdown: string;
  mInfo: THoverInfo;
begin
  TRequestDiagnostics.Note('syntaxErr', Length(ATree.Diagnostics));
  mDelphiVersion := '';
  if Assigned(FVersionProvider) then
  begin
    mDelphiVersion := FVersionProvider(AUri);
  end;
  ACancellation.ThrowIfCancellationRequested;
  // Direktiven und bedingte Symbole, dann unbekannte Feld- und Parameternamen (#461).
  if DirectiveHover(AUri, AText, ATree, APosition, mDelphiVersion, mMarkdown) or
    DataNameHint(FIndex, AText, TDocumentUris.ToPath(AUri), APosition, FReadText, mMarkdown) then
  begin
    Exit(MarkdownAnswer(mMarkdown));
  end;
  mInfo := SymbolInfo(AUri, AText, ATree, APosition, mDelphiVersion);
  if mInfo.Found then
  begin
    Result := InfoAnswer(AUri, mInfo);
  end
  // Seltene Schlüsselwörter und Direktiven (#187), wenn kein Symbol so heißt.
  else if TKeywordReference.HoverAt(AText, APosition, mDelphiVersion, mMarkdown) then
  begin
    Result := MarkdownAnswer(mMarkdown);
  end
  else
  begin
    TRequestDiagnostics.DefaultReason('noSymbol');
    Result := TJSONNull.Create;
  end;
end;

function TLspHover.HandleHover(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  mCancellation: IPascalCancellation;
  mUri, mText: string;
  mPosition: TTextPosition;
  mTree, mOwnTree: TSyntaxTree;
  mShared: ISharedSyntaxTree;
begin
  ReadParams(AParams, mUri, mPosition);
  // Erst in einer Variablen halten: Bei Übergabe als const würde das Objekt nie freigegeben.
  mCancellation := TRequestCancellation.Create(ACancellation);
  mTree := OpenTree(mUri, mCancellation, mText, mShared, mOwnTree);
  if mTree = nil then
  begin
    TRequestDiagnostics.Reason('documentNotOpen');
    Exit(TJSONNull.Create);
  end;
  try
    Result := AnswerAt(mUri, mText, mTree, mPosition, ACancellation);
  finally
    mOwnTree.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.Hover', cTexts);

end.
