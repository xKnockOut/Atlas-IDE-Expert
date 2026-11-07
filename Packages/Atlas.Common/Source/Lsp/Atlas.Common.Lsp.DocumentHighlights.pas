unit Atlas.Common.Lsp.DocumentHighlights;

// Vorkommen hervorheben (textDocument/documentHighlight): alle Stellen der
// aktuellen Datei, die zur selben Deklaration auflösen wie der Bezeichner
// unter dem Cursor.
//
// Art je Stelle: Write bei Zuweisung (Name := ...), Text bei der
// Deklaration selbst, sonst Read. Geprüft werden nur Bezeichner mit
// gleichem Namen; jeder wird einzeln aufgelöst, damit gleichnamige
// Symbole aus anderen Gültigkeitsbereichen nicht mitmarkiert werden.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Semantics.NameResolver;

type
  {$SCOPEDENUMS ON}
  /// <summary>Werte wie DocumentHighlightKind des LSP.</summary>
  THighlightKind = (Text = 1, Read = 2, Write = 3);
  {$SCOPEDENUMS OFF}

  TDocumentHighlight = record
    Range: TTextRange;
    Kind: THighlightKind;
  end;

  /// <summary>Einstellungen zur Schlüsselworthervorhebung (#307) für eine Datei-URI.</summary>
  THighlightSettingsProvider = reference to function(const AUri: string): THighlightSettings;

  TLspDocumentHighlights = class
  public const
    cMethod = 'textDocument/documentHighlight';
  private
    FStore: IDocumentStore;
    FIndex: ISymbolIndex;
    FEnsureUnit: TEnsureUnitFunc;
    FNamespaces: TArray<string>;
    FSettingsFor: THighlightSettingsProvider;
    function HandleHighlight(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
    /// <summary>Vorkommen des Bezeichners an APosition in ATree der Datei AUri.</summary>
    function IdentifierHighlights(ATree: TSyntaxTree; const AUri: string; const APosition: TTextPosition;
      const ACancellation: IJsonRpcCancellationToken): TArray<TDocumentHighlight>;
  private
    /// <summary>Unter TLspNamespaces gelesen und ersetzt (Code-Review A-03): Die Komposition setzt sie
    /// beim Laden eines Projekts, Anfragen lesen sie in Worker-Threads.</summary>
    function GetNamespaces: TArray<string>;
    procedure SetNamespaces(const AValue: TArray<string>);
  public
    constructor Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
      const AEnsureUnit: TEnsureUnitFunc); overload;
    /// <summary>Wie oben mit AEnsureUnit = nil.</summary>
    constructor Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex); overload;
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>Vorkommen des Symbols an APosition in ATree, in Textreihenfolge.</summary>
    class function Highlights(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const AFileName: string; const APosition: TTextPosition;
      const ACancellation: IJsonRpcCancellationToken): TArray<TDocumentHighlight>; overload; static;
    /// <summary>Wie oben ohne Abbruch (ACancellation = nil).</summary>
    class function Highlights(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const AFileName: string; const APosition: TTextPosition): TArray<TDocumentHighlight>; overload; static;
    property Namespaces: TArray<string> read GetNamespaces write SetNamespaces;
    /// <summary>Ohne Zuweisung gelten die Vorgaben.</summary>
    property SettingsFor: THighlightSettingsProvider read FSettingsFor write FSettingsFor;
  end;

implementation

uses
  Atlas.Common.Lsp.Internals.Namespaces,
  System.Generics.Collections,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Lsp.Definition,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Lsp.Internals.Cancellation,
  Atlas.Common.Lsp.KeywordHighlights,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TDocumentHighlightsText = (FieldsTextDocumentUriAndPosition);

const
  cTexts: array[TDocumentHighlightsText] of TAtlasText = (
    (De: 'Felder "textDocument.uri" und "position" fehlen in ';
     En: 'Fields "textDocument.uri" and "position" missing in '));

{$SCOPEDENUMS OFF}

function CleanName(const AText: string): string;
begin
  // &Begin → Begin
  if (AText <> '') and (AText[1] = '&') then
  begin
    Result := Copy(AText, 2, MaxInt);
  end
  else
  begin
    Result := AText;
  end;
end;

function TokenAt(const ATokens: TArray<TPascalToken>; const APosition: TTextPosition): Integer;
var
  mIndex: Integer;
  mToken: TPascalToken;
begin
  for mIndex := 0 to High(ATokens) do
  begin
    mToken := ATokens[mIndex];
    if (mToken.StartPos.Line > APosition.Line) or
      ((mToken.StartPos.Line = APosition.Line) and (mToken.StartPos.Character > APosition.Character)) then
    begin
      Break;
    end;
    // Cursor auf oder direkt hinter dem Bezeichner.
    if (mToken.Kind = TPascalTokenKind.Identifier) and (mToken.EndPos.Line = APosition.Line) and
      (APosition.Character <= mToken.EndPos.Character) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

function SameTarget(const A, B: TDefinitionTarget): Boolean;
begin
  Result := SameText(A.FileName, B.FileName) and (A.SelectionRange.StartPos = B.SelectionRange.StartPos);
end;

/// <summary>Index des nächsten Tokens nach AIndex, das kein Kommentar und keine Direktive ist.</summary>
function NextCodeToken(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex + 1;
  while (Result <= High(ATokens)) and (ATokens[Result].Kind in [TPascalTokenKind.Comment,
    TPascalTokenKind.Directive]) do
  begin
    Inc(Result);
  end;
end;

/// <summary>Art des Vorkommens ATokens[AIndex] von AWanted: Deklaration, Zuweisung oder Lesen.</summary>
function KindAt(const ATokens: TArray<TPascalToken>; AIndex: Integer; const AWanted: TDefinitionTarget;
  const AFileName: string): THighlightKind;
var
  mNext: Integer;
begin
  if SameText(AWanted.FileName, AFileName) and (AWanted.SelectionRange.StartPos = ATokens[AIndex].StartPos) then
  begin
    Exit(THighlightKind.Text);
  end;
  Result := THighlightKind.Read;
  mNext := NextCodeToken(ATokens, AIndex);
  if (mNext <= High(ATokens)) and (ATokens[mNext].Kind = TPascalTokenKind.Symbol) and (ATokens[mNext].Text = ':=') then
  begin
    Result := THighlightKind.Write;
  end;
end;

/// <summary>Zusammengehörige Schlüsselwörter als Vorkommen der Art Text.</summary>
function KeywordFound(const ARanges: TArray<TTextRange>): TArray<TDocumentHighlight>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(ARanges));
  for mIndex := 0 to High(ARanges) do
  begin
    Result[mIndex].Range := ARanges[mIndex];
    Result[mIndex].Kind := THighlightKind.Text;
  end;
end;

function HighlightsJson(const AFound: TArray<TDocumentHighlight>): TJSONArray;
var
  mHighlight: TDocumentHighlight;
  mItem: TJSONObject;
begin
  Result := TJSONArray.Create;
  for mHighlight in AFound do
  begin
    mItem := TJSONObject.Create;
    mItem.AddPair('range', TLspPositions.RangeToJson(mHighlight.Range));
    mItem.AddPair('kind', TJSONNumber.Create(Ord(mHighlight.Kind)));
    Result.AddElement(mItem);
  end;
end;

{ TLspDocumentHighlights }

function TLspDocumentHighlights.GetNamespaces: TArray<string>;
begin
  Result := TLspNamespaces.Read(FNamespaces);
end;

procedure TLspDocumentHighlights.SetNamespaces(const AValue: TArray<string>);
begin
  TLspNamespaces.Write(FNamespaces, AValue);
end;

constructor TLspDocumentHighlights.Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex);
begin
  Create(AStore, AIndex, nil);
end;

constructor TLspDocumentHighlights.Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
  const AEnsureUnit: TEnsureUnitFunc);
begin
  inherited Create;
  FStore := AStore;
  FIndex := AIndex;
  FEnsureUnit := AEnsureUnit;
end;

procedure TLspDocumentHighlights.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterConcurrentRequest(cMethod, HandleHighlight);
end;

class function TLspDocumentHighlights.Highlights(AResolver: TNameResolver; const AIndex: ISymbolIndex;
  ATree: TSyntaxTree; const AFileName: string; const APosition: TTextPosition): TArray<TDocumentHighlight>;
begin
  Result := Highlights(AResolver, AIndex, ATree, AFileName, APosition, nil);
end;

class function TLspDocumentHighlights.Highlights(AResolver: TNameResolver; const AIndex: ISymbolIndex;
  ATree: TSyntaxTree; const AFileName: string; const APosition: TTextPosition;
  const ACancellation: IJsonRpcCancellationToken): TArray<TDocumentHighlight>;
var
  mTokens: TArray<TPascalToken>;
  mIndex: Integer;
  mName: string;
  mWanted, mCandidate: TArray<TDefinitionTarget>;
  mHighlight: TDocumentHighlight;
  mFound: TList<TDocumentHighlight>;
begin
  Result := nil;
  mTokens := ATree.Tokens;
  mIndex := TokenAt(mTokens, APosition);
  if mIndex < 0 then
  begin
    Exit;
  end;
  mFound := TList<TDocumentHighlight>.Create;
  // Den Baum einmal auswerten statt je Vorkommen (Code-Review P-01).
  AResolver.PinTree(ATree, AFileName);
  try
    mWanted := TLspDefinition.Targets(AResolver, AIndex, ATree, AFileName, APosition, True);
    if Length(mWanted) = 0 then
    begin
      Exit;
    end;
    mName := CleanName(mTokens[mIndex].Text);
    for mIndex := 0 to High(mTokens) do
    begin
      if (mTokens[mIndex].Kind <> TPascalTokenKind.Identifier) or
        not SameText(CleanName(mTokens[mIndex].Text), mName) then
      begin
        Continue;
      end;
      if ACancellation <> nil then
      begin
        ACancellation.ThrowIfCancellationRequested;
      end;
      mCandidate := TLspDefinition.Targets(AResolver, AIndex, ATree, AFileName, mTokens[mIndex].StartPos, True);
      if (Length(mCandidate) = 0) or not SameTarget(mCandidate[0], mWanted[0]) then
      begin
        Continue;
      end;
      mHighlight.Range := TTextRange.Create(mTokens[mIndex].StartPos, mTokens[mIndex].EndPos);
      mHighlight.Kind := KindAt(mTokens, mIndex, mWanted[0], AFileName);
      // Liste statt Result := Result + [...] (Code-Review P-08).
      mFound.Add(mHighlight);
    end;
    Result := mFound.ToArray;
  finally
    AResolver.UnpinTree;
    mFound.Free;
  end;
end;

function TLspDocumentHighlights.IdentifierHighlights(ATree: TSyntaxTree; const AUri: string;
  const APosition: TTextPosition; const ACancellation: IJsonRpcCancellationToken): TArray<TDocumentHighlight>;
var
  mResolver: TNameResolver;
begin
  mResolver := TNameResolver.Create(FIndex, FEnsureUnit);
  try
    mResolver.Namespaces := Namespaces;
    Result := Highlights(mResolver, FIndex, ATree, TDocumentUris.ToPath(AUri), APosition, ACancellation);
  finally
    mResolver.Free;
  end;
end;

function TLspDocumentHighlights.HandleHighlight(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  mCancellation: IPascalCancellation;
  mUri: string;
  mPositionValue: TJSONValue;
  mDocument: ITextDocument;
  mShared: ISharedSyntaxTree;
  mFound: TArray<TDocumentHighlight>;
  mSettings: THighlightSettings;
  mRanges: TArray<TTextRange>;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', mUri) and
    TJSONObject(AParams).TryGetValue<TJSONValue>('position', mPositionValue)) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams,
      cTexts[TDocumentHighlightsText.FieldsTextDocumentUriAndPosition].Text + cMethod);
  end;
  if not FStore.TryGet(mUri, mDocument) then
  begin
    Exit(TJSONNull.Create);
  end;
  // Erst in einer Variablen halten: Bei Übergabe als const würde das Objekt nie freigegeben.
  mCancellation := TRequestCancellation.Create(ACancellation);
  mShared := TSyntaxTreeCache.Get(mDocument, mCancellation);
  ACancellation.ThrowIfCancellationRequested;
  // Zuerst zusammengehörige Schlüsselwörter (#307), sonst Bezeichner.
  mSettings := THighlightSettings.Default;
  if Assigned(FSettingsFor) then
  begin
    mSettings := FSettingsFor(mUri);
  end;
  if TKeywordHighlights.Find(mShared.Tree, TLspPositions.ReadPosition(mPositionValue), mSettings, mRanges) then
  begin
    mFound := KeywordFound(mRanges);
  end
  else
  begin
    mFound := IdentifierHighlights(mShared.Tree, mUri, TLspPositions.ReadPosition(mPositionValue), ACancellation);
  end;
  Result := HighlightsJson(mFound);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.DocumentHighlights', cTexts);

end.
