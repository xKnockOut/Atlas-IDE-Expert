unit Atlas.Common.Lsp.Query;

// Code-Abfragen (#1351) im LSP-Server.
//
// Anfrage atlas/query (nebenläufig im Arbeitsthread, $/cancelRequest bricht ab):
//   params {"uri": Datei oder Ordner des Arbeitsbereichs (Einstellungen), "query": Abfrage, "limit": n (0 = ohne
//           Grenze), "fields": weitere Spalten, "format": "json" (Vorgabe), "markdown", "csv" oder "text"}
//   Antwort {"enabled": true, "root": Projektordner, "format": "json", "data": {…}} mit den Daten aus
//   TQueryOutput.Json (Fehler mit Spalte und Vorschlag unter "data.error"), sonst {"enabled": true, "root": …,
//   "format": …, "text": "…"}; {"enabled": false} bei query.enabled = false.
// Anfrage atlas/queryCatalog: params {"uri"} → {"enabled": …, "catalog": {…}} mit Mengen, Feldern, Prädikaten,
//   Schlüsselwörtern und gespeicherten Abfragen für die Vervollständigung im Fenster „Atlas-Abfrage“.
// Befehl atlas.query: Argumente [uri, Optionen] mit denselben Optionen wie params, Antwort wie atlas/query.
//
// Aufrufer und Aufgerufene liefert TLspQuery.Calls über die Aufrufhierarchie (#1119, #1122), damit die Abfrage
// dieselben Zahlen hat wie get_call_hierarchy; die Query-Schicht kennt das LSP nicht.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Query.Contract,
  Atlas.Common.Lsp.References;

type
  /// <summary>Einstellungen und Projektordner zum Arbeitsbereich von AFileName ('' = der einzige oder erste);
  /// False, wenn keiner passt.</summary>
  TLspQuerySettingsFunc = reference to function(const AFileName: string; out ASettings: TServerSettings;
    out ARoot: string): Boolean;

  TLspQuery = class
  public const
    Method = 'atlas/query';
    CatalogMethod = 'atlas/queryCatalog';
    Command = 'atlas.query';
  private
    FQueries: ICodeQueries;
    FSettingsFor: TLspQuerySettingsFunc;
    function Answer(const AParams: TJSONObject; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
  public
    constructor Create(const AQueries: ICodeQueries; const ASettingsFor: TLspQuerySettingsFunc);
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>Antwort auf atlas/query; der Aufrufer übernimmt das Ergebnis.</summary>
    function Request(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
    /// <summary>Antwort auf atlas/queryCatalog; der Aufrufer übernimmt das Ergebnis.</summary>
    function Catalog(const AParams: TJSONValue): TJSONValue;
    /// <summary>Befehl atlas.query: [uri, Optionen]; der Aufrufer übernimmt das Ergebnis.</summary>
    function Execute(const AArguments: TJSONArray): TJSONValue;
    /// <summary>Aufrufer (AIncoming) bzw. Aufgerufene eines Symbols über die Aufrufhierarchie: eingehende mit den
    /// erschlossenen Treffern nach ASettings (#1119), ausgehende mit Aufrufen über Interface oder virtuelle Methode
    /// als erschlossen (#1122).</summary>
    class function Calls(const AIndex: ISymbolIndex; const AEnsureUnit: TEnsureUnitFunc;
      const ANamespaces, AFiles: TArray<string>; const AReadText: TReferenceReadText;
      const ASettings: TReferenceSettings): TQueryCallsFunc; static;
    /// <summary>Datenquelle einer Abfrage über AFiles mit Calls wie oben; ein Weg für LSP-Server, MCP und --check,
    /// damit alle dieselben Zahlen liefern.</summary>
    class function Source(const AIndex: ISymbolIndex; const AEnsureUnit: TEnsureUnitFunc; const ARoot: string;
      const AFiles, ANamespaces: TArray<string>; const AReadText: TReferenceReadText;
      const AReferences: TReferenceSettings): TQuerySource; static;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.ReferenceConfidence,
  Atlas.Common.Lsp.Hierarchies,
  Atlas.Common.Query.Output;

function StringOf(const AObject: TJSONObject; const AName: string): string;
var
  mValue: TJSONValue;
begin
  Result := '';
  if AObject = nil then
    Exit;
  mValue := AObject.GetValue(AName);
  if mValue is TJSONString then
    Result := Trim(mValue.Value);
end;

function PathOf(const AText: string): string;
begin
  if StartsText('file:', AText) then
    Result := TDocumentUris.ToPath(AText)
  else
    Result := AText;
end;

function ParamsOf(const AParams: TJSONValue): TJSONObject;
begin
  if AParams is TJSONObject then
    Result := TJSONObject(AParams)
  else
    Result := nil;
end;

function CancelOf(const ACancellation: IJsonRpcCancellationToken): TQueryCancelled;
begin
  if ACancellation = nil then
    Exit(nil);
  Result :=
    function: Boolean
    begin
      Result := ACancellation.IsCancellationRequested;
    end;
end;

function QualifiedOf(const AItem: THierarchyItem): string;
begin
  if AItem.Container <> '' then
    Result := AItem.Container + '.' + AItem.Name
  else
    Result := AItem.Name;
end;

/// <summary>TQueryReadText über AReadText; eigene Routine, damit die Methodenreferenz nur AReadText festhält.
/// </summary>
function QueryReadTextOf(const AReadText: TReferenceReadText): TQueryReadText;
begin
  Result :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := AReadText(AFileName, AText);
    end;
end;

{ TLspQuery }

constructor TLspQuery.Create(const AQueries: ICodeQueries; const ASettingsFor: TLspQuerySettingsFunc);
begin
  inherited Create;
  FQueries := AQueries;
  FSettingsFor := ASettingsFor;
end;

procedure TLspQuery.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  // Aufrufer über die Referenzsuche können Sekunden dauern: nebenläufig, abbrechbar.
  ADispatcher.RegisterConcurrentRequest(Method,
    function(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue
    begin
      Result := Request(AParams, ACancellation);
    end);
  ADispatcher.RegisterConcurrentRequest(CatalogMethod,
    function(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue
    begin
      Result := Catalog(AParams);
    end);
end;

function TLspQuery.Answer(const AParams: TJSONObject; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  mSettings: TServerSettings;
  mRoot, mFormatText, mQuery: string;
  mFormat: TQueryOutputFormat;
  mRequest: TQueryRequest;
  mResult: TQueryResult;
  mAnswer: TJSONObject;
  mFields: TJSONArray;
  mValue: TJSONValue;
  mLimit: Integer;
begin
  mFormatText := StringOf(AParams, 'format');
  if not TQueryOutput.TryParseFormat(mFormatText, TQueryOutputFormat.Json, mFormat) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, '"format" ist json, markdown, csv oder text');
  if not (Assigned(FSettingsFor) and FSettingsFor(PathOf(StringOf(AParams, 'uri')), mSettings, mRoot)) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Kein Projekt geladen');
  mAnswer := TJSONObject.Create;
  try
    mAnswer.AddPair('enabled', TJSONBool.Create(mSettings.QueryEnabled));
    if mSettings.QueryEnabled then
    begin
      mQuery := StringOf(AParams, 'query');
      if mQuery = '' then
        raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, '"query" fehlt');
      mLimit := 0;
      if AParams <> nil then
        AParams.TryGetValue<Integer>('limit', mLimit);
      mRequest := TQueryRequest.Create(mQuery, mLimit);
      if (AParams <> nil) and AParams.TryGetValue<TJSONArray>('fields', mFields) then
        for mValue in mFields do
          if mValue is TJSONString then
            mRequest.Fields := mRequest.Fields + [mValue.Value];
      mRequest.Cancelled := CancelOf(ACancellation);
      mResult := FQueries.Execute(mRequest);
      if (ACancellation <> nil) and ACancellation.IsCancellationRequested then
        ACancellation.ThrowIfCancellationRequested;
      mAnswer.AddPair('root', mRoot);
      if mFormat = TQueryOutputFormat.Json then
      begin
        mValue := TJSONObject.ParseJSONValue(TQueryOutput.Json(mResult));
        if mValue = nil then
          raise EJsonRpcError.Create(TJsonRpcErrorCode.InternalError, 'Abfrageergebnis ist kein gültiges JSON');
        mAnswer.AddPair('format', 'json');
        mAnswer.AddPair('data', mValue);
      end
      else
      begin
        mAnswer.AddPair('format', LowerCase(mFormatText));
        mAnswer.AddPair('text', TQueryOutput.Render(mResult, mFormat));
      end;
    end;
    Result := mAnswer;
    mAnswer := nil;
  finally
    mAnswer.Free;
  end;
end;

function TLspQuery.Request(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
begin
  Result := Answer(ParamsOf(AParams), ACancellation);
end;

function TLspQuery.Catalog(const AParams: TJSONValue): TJSONValue;
var
  mSettings: TServerSettings;
  mRoot: string;
  mAnswer: TJSONObject;
  mValue: TJSONValue;
begin
  if not (Assigned(FSettingsFor) and FSettingsFor(PathOf(StringOf(ParamsOf(AParams), 'uri')), mSettings, mRoot)) then
    mSettings := TServerSettings.Default;
  mAnswer := TJSONObject.Create;
  try
    mAnswer.AddPair('enabled', TJSONBool.Create(mSettings.QueryEnabled));
    if mSettings.QueryEnabled then
    begin
      mValue := TJSONObject.ParseJSONValue(TQueryOutput.CatalogJson(mSettings.Queries));
      if mValue = nil then
        raise EJsonRpcError.Create(TJsonRpcErrorCode.InternalError, 'Katalog ist kein gültiges JSON');
      mAnswer.AddPair('catalog', mValue);
    end;
    Result := mAnswer;
    mAnswer := nil;
  finally
    mAnswer.Free;
  end;
end;

function TLspQuery.Execute(const AArguments: TJSONArray): TJSONValue;
var
  mParams: TJSONObject;
  mPair: TJSONPair;
begin
  mParams := TJSONObject.Create;
  try
    if (AArguments <> nil) and (AArguments.Count > 0) and (AArguments.Items[0] is TJSONString) then
      mParams.AddPair('uri', AArguments.Items[0].Value);
    if (AArguments <> nil) and (AArguments.Count > 1) and (AArguments.Items[1] is TJSONObject) then
      for mPair in TJSONObject(AArguments.Items[1]) do
        if mPair.JsonString.Value <> 'uri' then
          mParams.AddPair(mPair.JsonString.Value, TJSONValue(mPair.JsonValue.Clone));
    Result := Answer(mParams, nil);
  finally
    mParams.Free;
  end;
end;

class function TLspQuery.Calls(const AIndex: ISymbolIndex; const AEnsureUnit: TEnsureUnitFunc;
  const ANamespaces, AFiles: TArray<string>; const AReadText: TReferenceReadText;
  const ASettings: TReferenceSettings): TQueryCallsFunc;
begin
  Result :=
    function(const ALocation: TSymbolLocation; AIncoming: Boolean): TArray<TQueryCall>
    var
      mResolver: TNameResolver;
      mItem: THierarchyItem;
      mCalls: TArray<THierarchyCall>;
      mCall: THierarchyCall;
      mEntry: TQueryCall;
    begin
      mItem := TLspHierarchies.ItemOf(ALocation.UnitName, ALocation.FileName, ALocation.Symbol);
      mResolver := TNameResolver.Create(AIndex, AEnsureUnit);
      try
        mResolver.Namespaces := ANamespaces;
        if AIncoming then
          mCalls := TLspHierarchies.IncomingCalls(mResolver, AIndex, mItem, AFiles, AReadText, ASettings, nil)
        else
          mCalls := TLspHierarchies.OutgoingCalls(mResolver, AIndex, mItem, AReadText, nil);
      finally
        mResolver.Free;
      end;
      Result := nil;
      for mCall in mCalls do
      begin
        mEntry := Default(TQueryCall);
        mEntry.Name := QualifiedOf(mCall.Item);
        mEntry.UnitName := mCall.Item.UnitName;
        mEntry.FileName := mCall.Item.FileName;
        if AIncoming then
        begin
          mEntry.Inferred := not mCall.Confidence.IsSure;
          mEntry.Reason := mCall.Confidence.ReasonName;
        end
        else
        begin
          mEntry.Inferred := mCall.Dispatch <> TReferenceReason.None;
          mEntry.Reason := TReferenceConfidence.NameOfReason(mCall.Dispatch);
        end;
        Result := Result + [mEntry];
      end;
    end;
end;

class function TLspQuery.Source(const AIndex: ISymbolIndex; const AEnsureUnit: TEnsureUnitFunc; const ARoot: string;
  const AFiles, ANamespaces: TArray<string>; const AReadText: TReferenceReadText;
  const AReferences: TReferenceSettings): TQuerySource;
begin
  Result := Default(TQuerySource);
  Result.Index := AIndex;
  Result.Root := ARoot;
  Result.Files := AFiles;
  Result.Namespaces := ANamespaces;
  Result.ReadText := QueryReadTextOf(AReadText);
  Result.Calls := Calls(AIndex, AEnsureUnit, ANamespaces, AFiles, AReadText, AReferences);
end;

end.
