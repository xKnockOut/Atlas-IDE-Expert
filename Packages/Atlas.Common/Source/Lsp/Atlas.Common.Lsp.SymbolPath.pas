unit Atlas.Common.Lsp.SymbolPath;

// Weg zwischen zwei Symbolen oder Units (#1117) im LSP-Server.
//
// Anfrage atlas/symbolPath (nebenläufig im Arbeitsthread):
//   params {"uri": Datei oder Projekt (wählt den Arbeitsbereich), "from",
//           "to": Name wie bei find_symbol oder Unit, "via": ["uses",
//           "calls", …, "library"] (Vorgabe alle Kantenarten, Bibliothek
//           kein Durchgang), "maxSteps": 1–16 (Vorgabe 8), "all": bool}
//   Antwort {"enabled": true, …} mit den Feldern aus TSymbolPathSearch.ToJson
//   (Zeilen und Spalten ab 0, Dateien als Pfad), {"enabled": false} bei
//   navigation.symbolPath = false.
// Befehl atlas.symbolPath (für das Plugin): Argumente [uri, Optionen] mit
//   denselben Feldern wie params, Antwort wie oben.
// Zeitlimit: vier Fünftel von requestTimeoutMs, damit die Antwort „abgebrochen“
// vor dem Watchdog kommt; $/cancelRequest bricht ebenfalls ab.
// Der Uses-Graph enthält hier auch die Bibliotheks-Units (Ziel oder Start);
// er gehört diesem Dienst und folgt dem Index.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Index.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Architecture.UsesLocator,
  Atlas.Common.Architecture.UsesService,
  Atlas.Common.Architecture.SymbolPath;

type
  /// <summary>Einstellungen und Namensräume zum Arbeitsbereich von AFileName ('' = der einzige oder erste);
  /// False, wenn kein Arbeitsbereich passt.</summary>
  TLspSymbolPathSourceFunc = reference to function(const AFileName: string; out ASettings: TServerSettings;
    out ANamespaces: TArray<string>): Boolean;

  TLspSymbolPath = class
  public const
    Method = 'atlas/symbolPath';
    Command = 'atlas.symbolPath';
  private
    FIndex: ISymbolIndex;
    FGraphs: TUsesGraphService;
    FLocator: TUsesLocator;
    FReadText: TSymbolPathReadText;
    FEnsureUnit: TEnsureUnitFunc;
    FSourceFor: TLspSymbolPathSourceFunc;
  public
    constructor Create(const AIndex: ISymbolIndex; const AReadText: TSymbolPathReadText;
      const ADefines: TUsesDefinesFunc; const AEnsureUnit: TEnsureUnitFunc; const ASourceFor: TLspSymbolPathSourceFunc);
    destructor Destroy; override;
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>Antwort auf atlas/symbolPath; der Aufrufer übernimmt das Ergebnis.</summary>
    function Request(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
    /// <summary>Befehl atlas.symbolPath: [uri, Optionen]; der Aufrufer übernimmt das Ergebnis.</summary>
    function Execute(const AArguments: TJSONArray): TJSONValue;
    /// <summary>from, to, via, maxSteps und all aus AParams; EJsonRpcError bei ungültigen Werten.</summary>
    class function ReadRequest(const AParams: TJSONObject): TSymbolPathRequest; static;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Common.Documents.Uris,
  Atlas.Common.JsonRpc.CurrentRequest,
  Atlas.Common.Architecture.UsesGraph;

function StringOf(const AObject: TJSONObject; const AName: string): string;
var
  Value: TJSONValue;
begin
  Result := '';
  if AObject = nil then
    Exit;
  Value := AObject.GetValue(AName);
  if Value is TJSONString then
    Result := Trim(Value.Value);
end;

/// <summary>Pfad aus einer file-URI oder unverändert, wenn AText schon ein Pfad ist.</summary>
function PathOf(const AText: string): string;
begin
  if StartsText('file:', AText) then
    Result := TDocumentUris.ToPath(AText)
  else
    Result := AText;
end;

/// <summary>Uses-Graph mit Bibliotheks-Units: Sie sind Start oder Ziel eines Wegs.</summary>
function GraphOptions(const ANamespaces: TArray<string>): TUsesGraphOptions;
begin
  Result := TUsesGraphOptions.Default;
  Result.IncludeLibrary := True;
  Result.Namespaces := ANamespaces;
end;

{ TLspSymbolPath }

constructor TLspSymbolPath.Create(const AIndex: ISymbolIndex; const AReadText: TSymbolPathReadText;
  const ADefines: TUsesDefinesFunc; const AEnsureUnit: TEnsureUnitFunc; const ASourceFor: TLspSymbolPathSourceFunc);
var
  ReadText: TSymbolPathReadText;
begin
  inherited Create;
  FIndex := AIndex;
  FReadText := AReadText;
  FEnsureUnit := AEnsureUnit;
  FSourceFor := ASourceFor;
  FGraphs := TUsesGraphService.Create(AIndex, GraphOptions(nil));
  ReadText := AReadText;
  FLocator := TUsesLocator.Create(
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := Assigned(ReadText) and ReadText(AFileName, AText);
    end, ADefines);
end;

destructor TLspSymbolPath.Destroy;
begin
  FLocator.Free;
  FGraphs.Free;
  inherited;
end;

procedure TLspSymbolPath.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterConcurrentRequest(Method,
    function(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue
    begin
      Result := Request(AParams, ACancellation);
    end);
end;

class function TLspSymbolPath.ReadRequest(const AParams: TJSONObject): TSymbolPathRequest;
var
  Value, Item: TJSONValue;
  Kind: TSymbolPathEdgeKind;
  Library_: Boolean;
  Steps: Integer;
begin
  Result := TSymbolPathRequest.Default;
  Result.From := StringOf(AParams, 'from');
  Result.To_ := StringOf(AParams, 'to');
  if (Result.From = '') or (Result.To_ = '') then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, '"from" und "to" sind nötig');
  Value := nil;
  if AParams <> nil then
    Value := AParams.GetValue('via');
  if Value is TJSONArray then
  begin
    Result.Via := [];
    for Item in TJSONArray(Value) do
    begin
      if not (Item is TJSONString) or not TSymbolPathSearch.TryParseEdge(Item.Value, Kind, Library_) then
        raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, '"via" kennt uses, inherits, implements, ' +
          'hasField, parameter, result, calls, contains und library');
      if Library_ then
        Result.ThroughLibrary := True
      else
        Include(Result.Via, Kind);
    end;
    // Nur "library": alle Kantenarten, Bibliothek als Durchgang.
    if Result.Via = [] then
      Result.Via := AllSymbolPathEdges;
  end;
  if AParams <> nil then
    Value := AParams.GetValue('maxSteps')
  else
    Value := nil;
  if Value is TJSONNumber then
  begin
    Steps := TJSONNumber(Value).AsInt;
    if (Steps < 1) or (Steps > TSymbolPathRequest.MaxStepsLimit) then
      raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, Format('"maxSteps" liegt zwischen 1 und %d',
        [TSymbolPathRequest.MaxStepsLimit]));
    Result.MaxSteps := Steps;
  end;
  if AParams <> nil then
    Value := AParams.GetValue('all')
  else
    Value := nil;
  if Value is TJSONBool then
    Result.All := TJSONBool(Value).AsBoolean;
end;

function TLspSymbolPath.Request(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  Params, Answer: TJSONObject;
  Settings: TServerSettings;
  Namespaces: TArray<string>;
  Search: TSymbolPathRequest;
  Found: TSymbolPathResult;
  Pair: TJSONPair;
  Data: TJSONObject;
  Token: IJsonRpcCancellationToken;
begin
  if AParams is TJSONObject then
    Params := TJSONObject(AParams)
  else
    Params := nil;
  if not (Assigned(FSourceFor) and FSourceFor(PathOf(StringOf(Params, 'uri')), Settings, Namespaces)) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Kein Projekt geladen');
  Answer := TJSONObject.Create;
  try
    Answer.AddPair('enabled', TJSONBool.Create(Settings.Navigation.SymbolPath));
    if Settings.Navigation.SymbolPath then
    begin
      Search := ReadRequest(Params);
      Search.TimeoutMs := Settings.RequestTimeoutMs div 5 * 4;
      // Namensräume des Projekts: neuer Graph nur, wenn sie sich ändern.
      if string.Join(',', FGraphs.Options.Namespaces) <> string.Join(',', Namespaces) then
        FGraphs.SetOptions(GraphOptions(Namespaces));
      Token := ACancellation;
      Found := TSymbolPathSearch.Run(FIndex, FGraphs, FLocator, FReadText, FEnsureUnit, Namespaces, Search,
        function: Boolean
        begin
          Result := (Token <> nil) and Token.IsCancellationRequested;
        end);
      Data := TSymbolPathSearch.ToJson(Found);
      try
        for Pair in Data do
          Answer.AddPair(Pair.JsonString.Value, TJSONValue(Pair.JsonValue.Clone));
      finally
        Data.Free;
      end;
    end;
    Result := Answer;
    Answer := nil;
  finally
    Answer.Free;
  end;
end;

function TLspSymbolPath.Execute(const AArguments: TJSONArray): TJSONValue;
var
  Params: TJSONObject;
  Options: TJSONObject;
  Pair: TJSONPair;
begin
  Params := TJSONObject.Create;
  try
    if (AArguments <> nil) and (AArguments.Count > 0) and (AArguments.Items[0] is TJSONString) then
      Params.AddPair('uri', AArguments.Items[0].Value);
    if (AArguments <> nil) and (AArguments.Count > 1) and (AArguments.Items[1] is TJSONObject) then
    begin
      Options := TJSONObject(AArguments.Items[1]);
      for Pair in Options do
        if Pair.JsonString.Value <> 'uri' then
          Params.AddPair(Pair.JsonString.Value, TJSONValue(Pair.JsonValue.Clone));
    end;
    // Befehle laufen ohne eigenes Token-Argument: Abbruch über die laufende Anfrage (A-06).
    Result := Request(Params, TJsonRpcCurrentRequest.Token);
  finally
    Params.Free;
  end;
end;

end.
