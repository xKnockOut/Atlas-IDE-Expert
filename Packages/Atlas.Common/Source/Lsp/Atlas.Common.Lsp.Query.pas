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
  /// <summary>Eingaben einer Abfrage-Datenquelle (TLspQuery.Source).</summary>
  TLspQueryInput = record
    Index: ISymbolIndex;
    EnsureUnit: TEnsureUnitFunc;
    /// <summary>Projektordner für die Spalte "Datei".</summary>
    Root: string;
    Files: TArray<string>;
    Namespaces: TArray<string>;
    ReadText: TReferenceReadText;
  end;

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
    /// <summary>Datenquelle einer Abfrage über AInput.Files mit Calls wie oben; ein Weg für LSP-Server, MCP und
    /// --check, damit alle dieselben Zahlen liefern.</summary>
    class function Source(const AInput: TLspQueryInput; const AReferences: TReferenceSettings): TQuerySource;
      static;
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
  begin
    Exit;
  end;
  mValue := AObject.GetValue(AName);
  if mValue is TJSONString then
  begin
    Result := Trim(mValue.Value);
  end;
end;

function PathOf(const AText: string): string;
begin
  if StartsText('file:', AText) then
  begin
    Result := TDocumentUris.ToPath(AText);
  end
  else
  begin
    Result := AText;
  end;
end;

function ParamsOf(const AParams: TJSONValue): TJSONObject;
begin
  if AParams is TJSONObject then
  begin
    Result := TJSONObject(AParams);
  end
  else
  begin
    Result := nil;
  end;
end;

function CancelOf(const ACancellation: IJsonRpcCancellationToken): TQueryCancelled;
begin
  if ACancellation = nil then
  begin
    Exit(nil);
  end;
  Result :=
    function: Boolean
    begin
      Result := ACancellation.IsCancellationRequested;
    end;
end;

function QualifiedOf(const AItem: THierarchyItem): string;
begin
  if AItem.Container <> '' then
  begin
    Result := AItem.Container + '.' + AItem.Name;
  end
  else
  begin
    Result := AItem.Name;
  end;
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

/// <summary>Abfrage aus AParams: query, limit und fields; EJsonRpcError ohne query.</summary>
function RequestOf(const AParams: TJSONObject; const ACancellation: IJsonRpcCancellationToken): TQueryRequest;
var
  mQuery: string;
  mLimit: Integer;
  mFields: TJSONArray;
  mValue: TJSONValue;
begin
  mQuery := StringOf(AParams, 'query');
  if mQuery = '' then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, '"query" fehlt');
  end;
  mLimit := 0;
  if AParams <> nil then
  begin
    AParams.TryGetValue<Integer>('limit', mLimit);
  end;
  if not ((AParams <> nil) and AParams.TryGetValue<TJSONArray>('fields', mFields)) then
  begin
    mFields := nil;
  end;
  Result := TQueryRequest.Create(mQuery, mLimit);
  if mFields <> nil then
  begin
    for mValue in mFields do
    begin
      if mValue is TJSONString then
      begin
        Result.Fields := Result.Fields + [mValue.Value];
      end;
    end;
  end;
  Result.Cancelled := CancelOf(ACancellation);
end;

/// <summary>Ergebnis AResult im Format AFormat (Text AFormatText) in AAnswer.</summary>
procedure AddResult(AAnswer: TJSONObject; const AResult: TQueryResult; AFormat: TQueryOutputFormat;
  const AFormatText: string);
var
  mValue: TJSONValue;
begin
  if AFormat <> TQueryOutputFormat.Json then
  begin
    AAnswer.AddPair('format', LowerCase(AFormatText));
    AAnswer.AddPair('text', TQueryOutput.Render(AResult, AFormat));
    Exit;
  end;
  mValue := TJSONObject.ParseJSONValue(TQueryOutput.Json(AResult));
  if mValue = nil then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InternalError, 'Abfrageergebnis ist kein gültiges JSON');
  end;
  AAnswer.AddPair('format', 'json');
  AAnswer.AddPair('data', mValue);
end;

function TLspQuery.Answer(const AParams: TJSONObject; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  mSettings: TServerSettings;
  mRoot, mFormatText: string;
  mFormat: TQueryOutputFormat;
  mResult: TQueryResult;
  mAnswer: TJSONObject;
begin
  mFormatText := StringOf(AParams, 'format');
  if not TQueryOutput.TryParseFormat(mFormatText, TQueryOutputFormat.Json, mFormat) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, '"format" ist json, markdown, csv oder text');
  end;
  if not (Assigned(FSettingsFor) and FSettingsFor(PathOf(StringOf(AParams, 'uri')), mSettings, mRoot)) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Kein Projekt geladen');
  end;
  mAnswer := TJSONObject.Create;
  try
    mAnswer.AddPair('enabled', TJSONBool.Create(mSettings.QueryEnabled));
    if mSettings.QueryEnabled then
    begin
      mResult := FQueries.Execute(RequestOf(AParams, ACancellation));
      if (ACancellation <> nil) and ACancellation.IsCancellationRequested then
      begin
        ACancellation.ThrowIfCancellationRequested;
      end;
      mAnswer.AddPair('root', mRoot);
      AddResult(mAnswer, mResult, mFormat, mFormatText);
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
  begin
    mSettings := TServerSettings.Default;
  end;
  mAnswer := TJSONObject.Create;
  try
    mAnswer.AddPair('enabled', TJSONBool.Create(mSettings.QueryEnabled));
    if mSettings.QueryEnabled then
    begin
      mValue := TJSONObject.ParseJSONValue(TQueryOutput.CatalogJson(mSettings.Queries));
      if mValue = nil then
      begin
        raise EJsonRpcError.Create(TJsonRpcErrorCode.InternalError, 'Katalog ist kein gültiges JSON');
      end;
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
    begin
      mParams.AddPair('uri', AArguments.Items[0].Value);
    end;
    if (AArguments <> nil) and (AArguments.Count > 1) and (AArguments.Items[1] is TJSONObject) then
    begin
      for mPair in TJSONObject(AArguments.Items[1]) do
      begin
        if mPair.JsonString.Value <> 'uri' then
        begin
          mParams.AddPair(mPair.JsonString.Value, TJSONValue(mPair.JsonValue.Clone));
        end;
      end;
    end;
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
        begin
          mCalls := TLspHierarchies.IncomingCalls(mResolver, AIndex, mItem, AFiles, AReadText, ASettings, nil);
        end
        else
        begin
          mCalls := TLspHierarchies.OutgoingCalls(mResolver, AIndex, mItem, AReadText, nil);
        end;
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

class function TLspQuery.Source(const AInput: TLspQueryInput; const AReferences: TReferenceSettings): TQuerySource;
begin
  Result := Default(TQuerySource);
  Result.Index := AInput.Index;
  Result.Root := AInput.Root;
  Result.Files := AInput.Files;
  Result.Namespaces := AInput.Namespaces;
  Result.ReadText := QueryReadTextOf(AInput.ReadText);
  Result.Calls := Calls(AInput.Index, AInput.EnsureUnit, AInput.Namespaces, AInput.Files, AInput.ReadText,
    AReferences);
end;

end.
