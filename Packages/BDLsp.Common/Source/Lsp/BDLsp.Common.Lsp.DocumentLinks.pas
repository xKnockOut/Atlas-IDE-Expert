unit BDLsp.Common.Lsp.DocumentLinks;

// Anklickbare Verweise (textDocument/documentLink, #25): Include- und
// Ressourcendateien, URLs und Dateinamen in Strings. Die Suche liegt in
// Editing.DocumentLinks; hier nur Protokoll und Umwandlung in URIs.

interface

uses
  System.SysUtils,
  System.JSON,
  BDLsp.Common.JsonRpc.Contract,
  BDLsp.Common.JsonRpc.Dispatcher,
  BDLsp.Common.Documents.Contract,
  BDLsp.Common.Editing.DocumentLinks;

type
  /// <summary>Zusätzliche Suchpfade für Include-Dateien des Dokuments AUri. Hintergrund-Thread.</summary>
  TSearchPathsProvider = reference to function(const AUri: string): TArray<string>;

  TLspDocumentLinks = class
  public const
    Method = 'textDocument/documentLink';
  private
    FStore: IDocumentStore;
    FSearchPaths: TSearchPathsProvider;
    FFileExists: TFileExistsFunc;
    function HandleLinks(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
  public
    /// <summary>Ohne AFileExists wird auf der Platte nachgesehen.</summary>
    constructor Create(const AStore: IDocumentStore; const ASearchPaths: TSearchPathsProvider = nil;
      const AFileExists: TFileExistsFunc = nil);
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    class function Capability: TJSONObject; static;
    /// <summary>Ein Verweis als LSP-DocumentLink. Der Aufrufer übernimmt das Objekt.</summary>
    class function LinkToJson(const ALink: TDocumentLink): TJSONObject; static;
  end;

implementation

uses
  BDLsp.Common.Documents.Uris,
  BDLsp.Common.Lsp.Positions;

constructor TLspDocumentLinks.Create(const AStore: IDocumentStore; const ASearchPaths: TSearchPathsProvider;
  const AFileExists: TFileExistsFunc);
begin
  inherited Create;
  FStore := AStore;
  FSearchPaths := ASearchPaths;
  FFileExists := AFileExists;
  if not Assigned(FFileExists) then
    FFileExists :=
      function(const AFileName: string): Boolean
      begin
        Result := FileExists(AFileName);
      end;
end;

procedure TLspDocumentLinks.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterConcurrentRequest(Method, HandleLinks);
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
    Result.AddPair('target', ALink.Target)
  else
  begin
    Result.AddPair('target', TDocumentUris.FromPath(ALink.Target));
    Result.AddPair('tooltip', ALink.Target);
  end;
end;

function TLspDocumentLinks.HandleLinks(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  Uri: string;
  Document: ITextDocument;
  SearchPaths: TArray<string>;
  Link: TDocumentLink;
  Links: TArray<TDocumentLink>;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', Uri)) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Feld "textDocument.uri" fehlt in ' + Method);
  if not FStore.TryGet(Uri, Document) then
    Exit(TJSONNull.Create);
  SearchPaths := nil;
  if Assigned(FSearchPaths) then
    SearchPaths := FSearchPaths(Uri);
  Links := TDocumentLinks.Find(Document.Text, TDocumentUris.ToPath(Uri), SearchPaths, FFileExists);
  ACancellation.ThrowIfCancellationRequested;
  // Ergebnis erst nach der Suche anlegen, damit ein Abbruch nichts verliert.
  Result := TJSONArray.Create;
  for Link in Links do
    TJSONArray(Result).AddElement(LinkToJson(Link));
end;

end.
