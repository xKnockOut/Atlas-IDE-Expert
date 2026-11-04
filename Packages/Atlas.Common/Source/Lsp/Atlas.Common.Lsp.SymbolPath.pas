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
  System.Generics.Collections,
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
  begin
    Exit;
  end;
  Value := AObject.GetValue(AName);
  if Value is TJSONString then
  begin
    Result := Trim(Value.Value);
  end;
end;

/// <summary>Pfad aus einer file-URI oder unverändert, wenn AText schon ein Pfad ist.</summary>
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

/// <summary>Wert AName aus AParams; nil ohne Parameter oder Feld.</summary>
function ParamValue(const AParams: TJSONObject; const AName: string): TJSONValue;
begin
  Result := nil;
  if AParams <> nil then
  begin
    Result := AParams.GetValue(AName);
  end;
end;

/// <summary>Liest "via" (Kantenarten und library) in ARequest.</summary>
procedure ReadVia(AValue: TJSONArray; var ARequest: TSymbolPathRequest);
var
  mItem: TJSONValue;
  mKind: TSymbolPathEdgeKind;
  mLibrary: Boolean;
begin
  ARequest.Via := [];
  for mItem in AValue do
  begin
    if not (mItem is TJSONString) or not TSymbolPathSearch.TryParseEdge(mItem.Value, mKind, mLibrary) then
    begin
      raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, '"via" kennt uses, inherits, implements, ' +
        'hasField, parameter, result, calls, contains und library');
    end;
    if mLibrary then
    begin
      ARequest.ThroughLibrary := True;
    end
    else
    begin
      Include(ARequest.Via, mKind);
    end;
  end;
  // Nur "library": alle Kantenarten, Bibliothek als Durchgang.
  if ARequest.Via = [] then
  begin
    ARequest.Via := AllSymbolPathEdges;
  end;
end;

/// <summary>"maxSteps" zwischen 1 und TSymbolPathRequest.MaxStepsLimit.</summary>
function ReadMaxSteps(AValue: TJSONNumber): Integer;
begin
  Result := AValue.AsInt;
  if (Result < 1) or (Result > TSymbolPathRequest.MaxStepsLimit) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, Format('"maxSteps" liegt zwischen 1 und %d',
      [TSymbolPathRequest.MaxStepsLimit]));
  end;
end;

class function TLspSymbolPath.ReadRequest(const AParams: TJSONObject): TSymbolPathRequest;
var
  mValue: TJSONValue;
begin
  Result := TSymbolPathRequest.Default;
  Result.From := StringOf(AParams, 'from');
  Result.To_ := StringOf(AParams, 'to');
  if (Result.From = '') or (Result.To_ = '') then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, '"from" und "to" sind nötig');
  end;
  mValue := ParamValue(AParams, 'via');
  if mValue is TJSONArray then
  begin
    ReadVia(TJSONArray(mValue), Result);
  end;
  mValue := ParamValue(AParams, 'maxSteps');
  if mValue is TJSONNumber then
  begin
    Result.MaxSteps := ReadMaxSteps(TJSONNumber(mValue));
  end;
  mValue := ParamValue(AParams, 'all');
  if mValue is TJSONBool then
  begin
    Result.All := TJSONBool(mValue).AsBoolean;
  end;
end;

/// <summary>Quellen der Pfadsuche über den Graphen des Dienstes.</summary>
function SourcesOf(const AIndex: ISymbolIndex; AGraphs: TUsesGraphService; ALocator: TUsesLocator;
  const AReadText: TSymbolPathReadText; const AEnsureUnit: TEnsureUnitFunc;
  const ANamespaces: TArray<string>): TSymbolPathSources;
begin
  Result := Default(TSymbolPathSources);
  Result.Index := AIndex;
  Result.Graphs := AGraphs;
  Result.Locator := ALocator;
  Result.ReadText := AReadText;
  Result.EnsureUnit := AEnsureUnit;
  Result.Namespaces := ANamespaces;
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
  begin
    Params := TJSONObject(AParams);
  end
  else
  begin
    Params := nil;
  end;
  if not (Assigned(FSourceFor) and FSourceFor(PathOf(StringOf(Params, 'uri')), Settings, Namespaces)) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Kein Projekt geladen');
  end;
  Answer := TJSONObject.Create;
  try
    Answer.AddPair('enabled', TJSONBool.Create(Settings.Navigation.SymbolPath));
    if Settings.Navigation.SymbolPath then
    begin
      Search := ReadRequest(Params);
      Search.TimeoutMs := Settings.RequestTimeoutMs div 5 * 4;
      // Namensräume des Projekts: neuer Graph nur, wenn sie sich ändern.
      if string.Join(',', FGraphs.Options.Namespaces) <> string.Join(',', Namespaces) then
      begin
        FGraphs.SetOptions(GraphOptions(Namespaces));
      end;
      Token := ACancellation;
      Found := TSymbolPathSearch.Run(SourcesOf(FIndex, FGraphs, FLocator, FReadText, FEnsureUnit, Namespaces),
        Search,
        function: Boolean
        begin
          Result := (Token <> nil) and Token.IsCancellationRequested;
        end);
      Data := TSymbolPathSearch.ToJson(Found);
      try
        for Pair in Data do
        begin
          Answer.AddPair(Pair.JsonString.Value, TJSONValue(Pair.JsonValue.Clone));
        end;
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
    begin
      Params.AddPair('uri', AArguments.Items[0].Value);
    end;
    if (AArguments <> nil) and (AArguments.Count > 1) and (AArguments.Items[1] is TJSONObject) then
    begin
      Options := TJSONObject(AArguments.Items[1]);
      for Pair in Options do
      begin
        if Pair.JsonString.Value <> 'uri' then
        begin
          Params.AddPair(Pair.JsonString.Value, TJSONValue(Pair.JsonValue.Clone));
        end;
      end;
    end;
    // Befehle laufen ohne eigenes Token-Argument: Abbruch über die laufende Anfrage (A-06).
    Result := Request(Params, TJsonRpcCurrentRequest.Token);
  finally
    Params.Free;
  end;
end;

end.
