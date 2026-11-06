unit Atlas.Common.Lsp.DocumentLinks;

// Anklickbare Verweise (textDocument/documentLink, #25): Include- und
// Ressourcendateien, URLs und Dateinamen in Strings. Die Suche liegt in
// Editing.DocumentLinks; hier nur Protokoll und Umwandlung in URIs.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Editing.DocumentLinks;

type
  /// <summary>Zusätzliche Suchpfade für Include-Dateien des Dokuments AUri. Hintergrund-Thread.</summary>
  TSearchPathsProvider = reference to function(const AUri: string): TArray<string>;

  TLspDocumentLinks = class
  public const
    cMethod = 'textDocument/documentLink';
  private
    FStore: IDocumentStore;
    FSearchPaths: TSearchPathsProvider;
    FFileExists: TFileExistsFunc;
    function HandleLinks(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
  public
    /// <summary>Ohne AFileExists wird auf der Platte nachgesehen.</summary>
    constructor Create(const AStore: IDocumentStore; const ASearchPaths: TSearchPathsProvider;
      const AFileExists: TFileExistsFunc); overload;
    /// <summary>Wie oben mit AFileExists = nil.</summary>
    constructor Create(const AStore: IDocumentStore; const ASearchPaths: TSearchPathsProvider); overload;
    /// <summary>Wie oben ohne Suchpfade (ASearchPaths = nil, AFileExists = nil).</summary>
    constructor Create(const AStore: IDocumentStore); overload;
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    class function Capability: TJSONObject; static;
    /// <summary>Ein Verweis als LSP-DocumentLink. Der Aufrufer übernimmt das Objekt.</summary>
    class function LinkToJson(const ALink: TDocumentLink): TJSONObject; static;
  end;

implementation

uses
  System.Generics.Collections,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TDocumentLinksText = (FieldTextDocumentUriMissingIn);

const
  cTexts: array[TDocumentLinksText] of TAtlasText = (
    (De: 'Feld "textDocument.uri" fehlt in '; En: 'Field "textDocument.uri" missing in '));

{$SCOPEDENUMS OFF}

constructor TLspDocumentLinks.Create(const AStore: IDocumentStore; const ASearchPaths: TSearchPathsProvider);
begin
  Create(AStore, ASearchPaths, nil);
end;

constructor TLspDocumentLinks.Create(const AStore: IDocumentStore);
begin
  Create(AStore, nil, nil);
end;

constructor TLspDocumentLinks.Create(const AStore: IDocumentStore; const ASearchPaths: TSearchPathsProvider;
  const AFileExists: TFileExistsFunc);
begin
  inherited Create;
  FStore := AStore;
  FSearchPaths := ASearchPaths;
  FFileExists := AFileExists;
  if not Assigned(FFileExists) then
  begin
    FFileExists :=
      function(const AFileName: string): Boolean
      begin
        Result := FileExists(AFileName);
      end;
  end;
end;

procedure TLspDocumentLinks.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterConcurrentRequest(cMethod, HandleLinks);
end;

class function TLspDocumentLinks.Capability: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('resolveProvider', TJSONBool.Create(False));
end;

class function TLspDocumentLinks.LinkToJson(const ALink: TDocumentLink): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('range', TLspPositions.RangeToJson(ALink.Range));
  if ALink.IsUrl then
  begin
    Result.AddPair('target', ALink.Target);
  end
  else
  begin
    Result.AddPair('target', TDocumentUris.FromPath(ALink.Target));
    Result.AddPair('tooltip', ALink.Target);
  end;
end;

function TLspDocumentLinks.HandleLinks(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  mUri: string;
  mDocument: ITextDocument;
  mSearchPaths: TArray<string>;
  mLink: TDocumentLink;
  mLinks: TArray<TDocumentLink>;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', mUri)) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams,
      cTexts[TDocumentLinksText.FieldTextDocumentUriMissingIn].Text + cMethod);
  end;
  if not FStore.TryGet(mUri, mDocument) then
  begin
    Exit(TJSONNull.Create);
  end;
  mSearchPaths := nil;
  if Assigned(FSearchPaths) then
  begin
    mSearchPaths := FSearchPaths(mUri);
  end;
  mLinks := TDocumentLinks.Find(mDocument.Text, TDocumentUris.ToPath(mUri), mSearchPaths, FFileExists);
  ACancellation.ThrowIfCancellationRequested;
  // Ergebnis erst nach der Suche anlegen, damit ein Abbruch nichts verliert.
  Result := TJSONArray.Create;
  for mLink in mLinks do
  begin
    TJSONArray(Result).AddElement(LinkToJson(mLink));
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.DocumentLinks', cTexts);

end.
