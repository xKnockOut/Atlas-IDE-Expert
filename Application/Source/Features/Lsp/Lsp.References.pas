unit Lsp.References;

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
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.InactiveRegions,
  Atlas.Common.Semantics.ReferenceConfidence,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Semantics.Feature,
  Atlas.Common.Semantics.References;

type
  TLspReferences = class(TProjectFeature)
  public const
    cMethod = 'textDocument/references';
  private
    FNamespaces: TArray<string>;
    FSettingsFor: TReferenceSettingsProvider;
    function HandleReferences(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
  private
    /// <summary>Unter TSharedNamespaces gelesen und ersetzt: Die Komposition setzt sie
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

implementation

uses
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Semantics.Namespaces,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Uris,
  Atlas.Common.JsonRpc.Positions,
  Atlas.Common.Semantics.RequestCancellation,
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
  Result := TSharedNamespaces.Read(FNamespaces);
end;

procedure TLspReferences.SetNamespaces(const AValue: TArray<string>);
begin
  TSharedNamespaces.Write(FNamespaces, AValue);
end;

procedure TLspReferences.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterConcurrentRequest(cMethod, HandleReferences);
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
  TAtlasTextTables.Add('Lsp.References', cTexts);

end.
