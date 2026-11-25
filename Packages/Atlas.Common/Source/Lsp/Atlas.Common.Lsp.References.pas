unit Atlas.Common.Lsp.References;

// Referenzsuche (textDocument/references, #29): beantwortet die Anfrage über
// TReferences (Atlas.Common.Semantics.References) und nennt die Einstufung je
// Stelle im Feld atlasConfidence.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.InactiveRegions,
  Atlas.Common.Semantics.ReferenceConfidence,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Lsp.Internals.Feature,
  Atlas.Common.Semantics.References;

type
  /// <summary>Einstellungen references.* für die Datei AUri.</summary>
  TReferenceSettingsProvider = reference to function(const AUri: string): TReferenceSettings;

  /// <summary>Dateien des Projekts, die nach Verweisen durchsucht werden.</summary>
  TReferenceFilesProvider = TLspFilesProvider;

  TLspReferences = class(TLspProjectFeature)
  public const
    cMethod = 'textDocument/references';
  private
    FNamespaces: TArray<string>;
    FSettingsFor: TReferenceSettingsProvider;
    function HandleReferences(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
  private
    /// <summary>Unter TLspNamespaces gelesen und ersetzt: Die Komposition setzt sie
    /// beim Laden eines Projekts, Anfragen lesen sie in Worker-Threads.</summary>
    function GetNamespaces: TArray<string>;
    procedure SetNamespaces(const AValue: TArray<string>);
  public
    constructor Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex; const AReadText: TReferenceReadText;
      const AFiles: TReferenceFilesProvider; const AEnsureUnit: TEnsureUnitFunc); overload;
    /// <summary>Wie oben mit AEnsureUnit = nil.</summary>
    constructor Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex; const AReadText: TReferenceReadText;
      const AFiles: TReferenceFilesProvider); overload;
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    property Namespaces: TArray<string> read GetNamespaces write SetNamespaces;
    /// <summary>Einstellungen references.* je Datei; nicht gesetzt: Vorgaben.</summary>
    property SettingsFor: TReferenceSettingsProvider read FSettingsFor write FSettingsFor;
  end;

type
  /// <summary>Datei einer Umbaurechnung mit Text und Baum; den Baum gibt sie nur mit OwnsTree frei (sonst gehört
  /// er dem Dokumentspeicher).</summary>
  TLspSourceFile = class
  public
    FileName: string;
    Text: string;
    Tree: TSyntaxTree;
    OwnsTree: Boolean;
    destructor Destroy; override;
  end;

/// <summary>Baum zu AUri: geöffnet aus dem Speicher (AShared), sonst selbst gelesen (AOwnTree, gehört dem
/// Aufrufer); nil, wenn die Datei nicht lesbar ist.</summary>
function ReferenceTreeOf(const AStore: IDocumentStore; const AReadText: TReferenceReadText; const AUri: string;
  const ACancellation: IPascalCancellation; out AShared: ISharedSyntaxTree; out AOwnTree: TSyntaxTree): TSyntaxTree;

implementation

uses
  Atlas.Common.Lsp.Internals.Namespaces,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Uris,
  Atlas.Common.JsonRpc.Positions,
  Atlas.Common.Lsp.Internals.Cancellation,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TReferencesText = (FieldsTextDocumentUriAndPosition);

const
  cTexts: array[TReferencesText] of TAtlasText = (
    (De: 'Felder "textDocument.uri" und "position" fehlen in ';
     En: 'Fields "textDocument.uri" and "position" missing in '));

{$SCOPEDENUMS OFF}

{ TLspReferences }

constructor TLspReferences.Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
  const AReadText: TReferenceReadText; const AFiles: TReferenceFilesProvider; const AEnsureUnit: TEnsureUnitFunc);
begin
  inherited Create(AStore, AIndex, AReadText, AFiles, AEnsureUnit);
end;

constructor TLspReferences.Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
  const AReadText: TReferenceReadText; const AFiles: TReferenceFilesProvider);
begin
  Create(AStore, AIndex, AReadText, AFiles, nil);
end;

function TLspReferences.GetNamespaces: TArray<string>;
begin
  Result := TLspNamespaces.Read(FNamespaces);
end;

procedure TLspReferences.SetNamespaces(const AValue: TArray<string>);
begin
  TLspNamespaces.Write(FNamespaces, AValue);
end;

procedure TLspReferences.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterConcurrentRequest(cMethod, HandleReferences);
end;

{ TLspSourceFile }

destructor TLspSourceFile.Destroy;
begin
  if OwnsTree then
  begin
    Tree.Free;
  end;
  inherited;
end;

function ReferenceTreeOf(const AStore: IDocumentStore; const AReadText: TReferenceReadText; const AUri: string;
  const ACancellation: IPascalCancellation; out AShared: ISharedSyntaxTree; out AOwnTree: TSyntaxTree): TSyntaxTree;
var
  mDocument: ITextDocument;
  mText: string;
begin
  AShared := nil;
  AOwnTree := nil;
  Result := nil;
  if AStore.TryGet(AUri, mDocument) then
  begin
    AShared := TSyntaxTreeCache.Get(mDocument, ACancellation);
    Result := AShared.Tree;
  end
  // Nicht geöffnete Datei (Verwendungen eines Typs aus dem Atlas-Tooltip, #588): selbst lesen.
  else if Assigned(AReadText) and AReadText(TDocumentUris.ToPath(AUri), mText) then
  begin
    AOwnTree := TSyntaxTreeCache.Parse(mText, ACancellation);
    Result := AOwnTree;
  end;
end;

/// <summary>Antwort auf textDocument/references zu AFound.</summary>
function LocationsJson(const AFound: TArray<TReferenceLocation>): TJSONArray;
var
  mLocation: TReferenceLocation;
  mItem: TJSONObject;
begin
  Result := TJSONArray.Create;
  for mLocation in AFound do
  begin
    mItem := TJSONObject.Create;
    mItem.AddPair('uri', TDocumentUris.FromPath(mLocation.FileName));
    mItem.AddPair('range', TLspPositions.RangeToJson(mLocation.Range));
    // Erweiterung (#1119): sicher oder erschlossen mit Grund; Editoren ohne Kenntnis übergehen das Feld.
    mItem.AddPair('atlasConfidence', mLocation.Confidence.ToJson);
    Result.AddElement(mItem);
  end;
end;

function TLspReferences.HandleReferences(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  mCancellation: IPascalCancellation;
  mUri: string;
  mPositionValue: TJSONValue;
  mIncludeDeclaration: Boolean;
  mTree, mOwnTree: TSyntaxTree;
  mShared: ISharedSyntaxTree;
  mResolver: TNameResolver;
  mFiles: TArray<string>;
  mFound: TArray<TReferenceLocation>;
  mSettings: TReferenceSettings;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', mUri) and
    TJSONObject(AParams).TryGetValue<TJSONValue>('position', mPositionValue)) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams,
      cTexts[TReferencesText.FieldsTextDocumentUriAndPosition].Text + cMethod);
  end;
  if not TJSONObject(AParams).TryGetValue<Boolean>('context.includeDeclaration', mIncludeDeclaration) then
  begin
    mIncludeDeclaration := True;
  end;
  // Erst in einer Variablen halten: Bei Übergabe als const würde das Objekt nie freigegeben.
  mCancellation := TRequestCancellation.Create(ACancellation);
  mTree := ReferenceTreeOf(FStore, FReadText, mUri, mCancellation, mShared, mOwnTree);
  if mTree = nil then
  begin
    Exit(TJSONNull.Create);
  end;
  try
    mFiles := nil;
    if Assigned(FFiles) then
    begin
      mFiles := FFiles();
    end;
    ACancellation.ThrowIfCancellationRequested;
    mSettings := TReferenceSettings.Default;
    if Assigned(FSettingsFor) then
    begin
      mSettings := FSettingsFor(mUri);
    end;
    mResolver := TNameResolver.Create(FIndex, FEnsureUnit);
    try
      mResolver.Namespaces := Namespaces;
      mFound := TReferences.Find(mResolver, FIndex, mTree, TReferenceSearch.Create(TDocumentUris.ToPath(mUri),
        TLspPositions.ReadPosition(mPositionValue), mIncludeDeclaration, mFiles, FReadText), mSettings,
        ACancellation);
    finally
      mResolver.Free;
    end;
  finally
    mOwnTree.Free;
  end;
  Result := LocationsJson(mFound);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.References', cTexts);

end.
