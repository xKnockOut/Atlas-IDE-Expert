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
    cMethod = 'atlas/symbolPath';
    cCommand = 'atlas.symbolPath';
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
  Atlas.Common.Architecture.UsesGraph,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TLspSymbolPathText = (ViaKnowsUsesInheritsImplements, MaxStepsLiesBetween1And, FromAndToAreRequired,
    NoProjectLoaded);

const
  cTexts: array[TLspSymbolPathText] of TAtlasText = (
    (De: '"via" kennt uses, inherits, implements, hasField, parameter, result, calls, contains und library';
     En: '"via" knows uses, inherits, implements, hasField, parameter, result, calls, contains and library'),
    (De: '"maxSteps" liegt zwischen 1 und %d'; En: '"maxSteps" lies between 1 and %d'),
    (De: '"from" und "to" sind nötig'; En: '"from" and "to" are required'),
    (De: 'Kein Projekt geladen'; En: 'No project loaded'));

{$SCOPEDENUMS OFF}

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
  mReadText: TSymbolPathReadText;
begin
  inherited Create;
  FIndex := AIndex;
  FReadText := AReadText;
  FEnsureUnit := AEnsureUnit;
  FSourceFor := ASourceFor;
  FGraphs := TUsesGraphService.Create(AIndex, GraphOptions(nil));
  mReadText := AReadText;
  FLocator := TUsesLocator.Create(
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := Assigned(mReadText) and mReadText(AFileName, AText);
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
  ADispatcher.RegisterConcurrentRequest(cMethod,
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
      raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams,
        cTexts[TLspSymbolPathText.ViaKnowsUsesInheritsImplements].Text);
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
    ARequest.Via := cAllSymbolPathEdges;
  end;
end;

/// <summary>"maxSteps" zwischen 1 und TSymbolPathRequest.cMaxStepsLimit.</summary>
function ReadMaxSteps(AValue: TJSONNumber): Integer;
begin
  Result := AValue.AsInt;
  if (Result < 1) or (Result > TSymbolPathRequest.cMaxStepsLimit) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams,
      cTexts[TLspSymbolPathText.MaxStepsLiesBetween1And].Fmt([TSymbolPathRequest.cMaxStepsLimit]));
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
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams, cTexts[TLspSymbolPathText.FromAndToAreRequired].Text);
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
  mParams, mAnswer: TJSONObject;
  mSettings: TServerSettings;
  mNamespaces: TArray<string>;
  mSearch: TSymbolPathRequest;
  mFound: TSymbolPathResult;
  mPair: TJSONPair;
  mData: TJSONObject;
  mToken: IJsonRpcCancellationToken;
begin
  if AParams is TJSONObject then
  begin
    mParams := TJSONObject(AParams);
  end
  else
  begin
    mParams := nil;
  end;
  if not (Assigned(FSourceFor) and FSourceFor(PathOf(StringOf(mParams, 'uri')), mSettings, mNamespaces)) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams, cTexts[TLspSymbolPathText.NoProjectLoaded].Text);
  end;
  mAnswer := TJSONObject.Create;
  try
    mAnswer.AddPair('enabled', TJSONBool.Create(mSettings.Navigation.SymbolPath));
    if mSettings.Navigation.SymbolPath then
    begin
      mSearch := ReadRequest(mParams);
      mSearch.TimeoutMs := mSettings.RequestTimeoutMs div 5 * 4;
      // Namensräume des Projekts: neuer Graph nur, wenn sie sich ändern.
      if string.Join(',', FGraphs.Options.Namespaces) <> string.Join(',', mNamespaces) then
      begin
        FGraphs.SetOptions(GraphOptions(mNamespaces));
      end;
      mToken := ACancellation;
      mFound := TSymbolPathSearch.Run(SourcesOf(FIndex, FGraphs, FLocator, FReadText, FEnsureUnit, mNamespaces),
        mSearch,
        function: Boolean
        begin
          Result := (mToken <> nil) and mToken.IsCancellationRequested;
        end);
      mData := TSymbolPathSearch.ToJson(mFound);
      try
        for mPair in mData do
        begin
          mAnswer.AddPair(mPair.JsonString.Value, TJSONValue(mPair.JsonValue.Clone));
        end;
      finally
        mData.Free;
      end;
    end;
    Result := mAnswer;
    mAnswer := nil;
  finally
    mAnswer.Free;
  end;
end;

function TLspSymbolPath.Execute(const AArguments: TJSONArray): TJSONValue;
var
  mParams: TJSONObject;
  mOptions: TJSONObject;
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
      mOptions := TJSONObject(AArguments.Items[1]);
      for mPair in mOptions do
      begin
        if mPair.JsonString.Value <> 'uri' then
        begin
          mParams.AddPair(mPair.JsonString.Value, TJSONValue(mPair.JsonValue.Clone));
        end;
      end;
    end;
    // Befehle laufen ohne eigenes Token-Argument: Abbruch über die laufende Anfrage (A-06).
    Result := Request(mParams, TJsonRpcCurrentRequest.Token);
  finally
    mParams.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.SymbolPath', cTexts);

end.
