unit Atlas.Common.Lsp.Hotspots;

// Hotspots (#1354) im LSP-Server.
//
// Anfrage atlas/hotspots (nebenläufig im Arbeitsthread):
//   params {"uri": Projekt, Ordner, Datei oder null (Arbeitsbereich der
//           Datei bzw. der einzige), "level": "unit" (Vorgabe) | "method",
//           "months": 1–60 (Vorgabe hotspots.months), "limit": Länge der
//           Listen (Vorgabe: alle bei json, 20 bei text), "format": "json"
//           (Vorgabe), "markdown", "html" oder "text", "section":
//           "hotspots" | "coupling" (nur "text"), "refresh": true rechnet
//           neu, auch wenn ein Ergebnis zum Stand da ist}
//   Antwort {"enabled": true, "vcs": true, "root": Wurzel der Arbeitskopie,
//   "format": "json", "data": {…}} mit den Daten aus THotspotReport.Json,
//   sonst {"enabled": true, "vcs": true, "root": …, "format": …,
//   "text": "…"}; ohne Versionsverwaltung {"enabled": true, "vcs": false,
//   "message": Grund} statt einer leeren Liste; {"enabled": false} bei
//   hotspots.enabled = false.
//   Gerechnet wird im Hintergrund (eigener Thread): git log über ein Jahr und
//   git log -L je Methode dauern länger als das Zeitlimit einer Anfrage
//   (requestTimeoutMs) und dürfen die Warteschlange nicht aufhalten. Solange
//   kein Ergebnis zum Stand (HEAD) da ist, antwortet die Anfrage sofort mit
//   {"enabled": true, "vcs": true, "root": …, "pending": true}; der Client
//   fragt später wieder. Das Ergebnis gilt bis zum nächsten Commit (ohne
//   bekannten Stand nur für die nächste Anfrage); ein Fehler von git bzw.
//   svn kommt einmal als Fehler der Anfrage.
// Befehl atlas.hotspots (für das IDE-Fenster, nebenläufig): Argumente
//   [uri, Optionen] mit denselben Optionen wie params der Anfrage, Antwort
//   wie oben.
// Befehl atlas.hotspots.saveReport (nebenläufig): Argumente [uri, Datei,
//   Optionen] schreibt den Bericht nach der Endung (.md Markdown, .html/.htm
//   HTML, .json die Daten) und liefert {"file": …, "units": n}; das Ergebnis
//   kommt aus derselben Rechnung auf Methodenebene (der Bericht zeigt die
//   Ebene aus den Optionen), ohne fertiges Ergebnis {"pending": true}.

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Hotspots.Contract,
  Atlas.Common.Hotspots.Analysis,
  Atlas.Common.Hotspots.Service;

type
  /// <summary>Anfrage, Einstellungen und Versionsverwaltung zum Arbeitsbereich von AFileName ('' = der einzige oder
  /// erste). False, wenn kein Arbeitsbereich passt. AVcs nil mit AError, wenn keine Versionsverwaltung greift (nur
  /// bei eingeschalteten Hotspots gefragt).</summary>
  TLspHotspotSourceFunc = reference to function(const AFileName: string; out ARequest: THotspotRequest;
    out ASettings: TServerSettings; out AVcs: IHotspotVcs; out AError: string): Boolean;

  TLspHotspotFormat = (Json, Markdown, Html, Text);

  TLspHotspots = class
  public const
    Method = 'atlas/hotspots';
    Command = 'atlas.hotspots';
    SaveCommand = 'atlas.hotspots.saveReport';
  private
    FService: THotspotService;
    FSourceFor: TLspHotspotSourceFunc;
    /// <summary>Schützt Hintergrundrechnung und fertiges Ergebnis.</summary>
    FJobLock: TObject;
    FWorker: TThread;
    FRunning: Boolean;
    /// <summary>Schlüssel (Art, Wurzel, Stand, Anfrage) des fertigen Ergebnisses; '' = keins.</summary>
    FDoneKey: string;
    FDone: THotspotResult;
    FDoneError: string;
    /// <summary>Fertiges Ergebnis gilt nur für eine Anfrage (Stand unbekannt).</summary>
    FDoneOnce: Boolean;
    FJobs: Integer;
    function JobProc(const AKey: string; const ARequest: THotspotRequest; const AVcs: IHotspotVcs;
      AOnce: Boolean): TProc;
    procedure StartJob(const AKey: string; const ARequest: THotspotRequest; const AVcs: IHotspotVcs;
      AOnce: Boolean);
    function ResultFor(const AParams: TJSONObject; out AEnabled, APending: Boolean; out AVcsError, ARoot: string):
      THotspotResult;
  public
    /// <summary>AService gehört dem Aufrufer.</summary>
    constructor Create(AService: THotspotService; const ASourceFor: TLspHotspotSourceFunc);
    /// <summary>Wartet auf eine laufende Hintergrundrechnung.</summary>
    destructor Destroy; override;
    /// <summary>Wie oft eine Hintergrundrechnung gestartet wurde (Tests).</summary>
    function Jobs: Integer;
    /// <summary>Wartet, bis keine Hintergrundrechnung mehr läuft (Tests, Kommandozeile).</summary>
    procedure WaitIdle;
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>Antwort auf atlas/hotspots; der Aufrufer übernimmt das Ergebnis.</summary>
    function Request(const AParams: TJSONValue): TJSONValue;
    /// <summary>Befehl atlas.hotspots: [uri, Optionen]; der Aufrufer übernimmt das Ergebnis.</summary>
    function Execute(const AArguments: TJSONArray): TJSONValue;
    /// <summary>Befehl atlas.hotspots.saveReport; der Aufrufer übernimmt das Ergebnis.</summary>
    function SaveReport(const AArguments: TJSONArray): TJSONValue;
    class function TryParseFormat(const AText: string; out AFormat: TLspHotspotFormat): Boolean; static;
    /// <summary>Werte aus params bzw. MCP-Argumenten (level, months) in ARequest übernehmen; False mit AError bei
    /// ungültigem Wert.</summary>
    class function ApplyOptions(const AParams: TJSONObject; var ARequest: THotspotRequest;
      out AError: string): Boolean; static;
    /// <summary>Listen des Ergebnisses auf ALimit kürzen (0 = alle).</summary>
    class function Limited(const AResult: THotspotResult; ALimit: Integer): THotspotResult; static;
  end;

implementation

uses
  System.StrUtils,
  System.IOUtils,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Hotspots.Report;

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

/// <summary>Ganze Zahl AName; ADefault ohne Angabe, False bei einem anderen Typ.</summary>
function IntegerOf(const AObject: TJSONObject; const AName: string; ADefault: Integer; out AValue: Integer): Boolean;
var
  mValue: TJSONValue;
begin
  AValue := ADefault;
  Result := True;
  if AObject = nil then
    Exit;
  mValue := AObject.GetValue(AName);
  if mValue = nil then
    Exit;
  Result := (mValue is TJSONNumber) and TryStrToInt(mValue.Value, AValue);
end;

/// <summary>Pfad aus einer file-URI oder unverändert, wenn AText schon ein Pfad ist.</summary>
function PathOf(const AText: string): string;
begin
  if StartsText('file:', AText) then
    Result := TDocumentUris.ToPath(AText)
  else
    Result := AText;
end;

{ TLspHotspots }

constructor TLspHotspots.Create(AService: THotspotService; const ASourceFor: TLspHotspotSourceFunc);
begin
  inherited Create;
  FService := AService;
  FSourceFor := ASourceFor;
  FJobLock := TObject.Create;
end;

destructor TLspHotspots.Destroy;
begin
  WaitIdle;
  FWorker.Free;
  FJobLock.Free;
  inherited Destroy;
end;

function TLspHotspots.Jobs: Integer;
begin
  System.TMonitor.Enter(FJobLock);
  try
    Result := FJobs;
  finally
    System.TMonitor.Exit(FJobLock);
  end;
end;

procedure TLspHotspots.WaitIdle;
var
  mWorker: TThread;
begin
  System.TMonitor.Enter(FJobLock);
  try
    mWorker := FWorker;
  finally
    System.TMonitor.Exit(FJobLock);
  end;
  // Nur dieser Thread startet und gibt Arbeiter frei (unter FJobLock in StartJob); warten ohne Sperre.
  if mWorker <> nil then
    mWorker.WaitFor;
end;

function TLspHotspots.JobProc(const AKey: string; const ARequest: THotspotRequest; const AVcs: IHotspotVcs;
  AOnce: Boolean): TProc;
var
  mKey: string;
  mRequest: THotspotRequest;
  mVcs: IHotspotVcs;
begin
  // Eigene Routine: Die anonyme Methode fängt nur diese Kopien ein.
  mKey := AKey;
  mRequest := ARequest;
  mVcs := AVcs;
  Result :=
    procedure
    var
      mResult: THotspotResult;
      mError: string;
    begin
      mResult := Default(THotspotResult);
      mError := '';
      try
        mResult := FService.Analyze(mRequest, mVcs);
      except
        on E: Exception do
          mError := E.Message;
      end;
      System.TMonitor.Enter(FJobLock);
      try
        FDoneKey := mKey;
        FDone := mResult;
        FDoneError := mError;
        FDoneOnce := AOnce;
        FRunning := False;
      finally
        System.TMonitor.Exit(FJobLock);
      end;
    end;
end;

procedure TLspHotspots.StartJob(const AKey: string; const ARequest: THotspotRequest; const AVcs: IHotspotVcs;
  AOnce: Boolean);
begin
  // Aufrufer hält FJobLock; der vorige Arbeiter ist fertig (FRunning = False), WaitFor kehrt sofort zurück.
  if FWorker <> nil then
  begin
    FWorker.WaitFor;
    FreeAndNil(FWorker);
  end;
  FRunning := True;
  Inc(FJobs);
  FWorker := TThread.CreateAnonymousThread(JobProc(AKey, ARequest, AVcs, AOnce));
  FWorker.FreeOnTerminate := False;
  FWorker.Start;
end;

procedure TLspHotspots.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  // git log über ein Jahr und git log -L je Methode dauern Sekunden: nebenläufig, damit Editoranfragen nicht warten.
  ADispatcher.RegisterConcurrentRequest(Method,
    function(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue
    begin
      Result := Request(AParams);
    end);
end;

class function TLspHotspots.TryParseFormat(const AText: string; out AFormat: TLspHotspotFormat): Boolean;
begin
  Result := True;
  if (AText = '') or SameText(AText, 'json') then
    AFormat := TLspHotspotFormat.Json
  else if SameText(AText, 'markdown') then
    AFormat := TLspHotspotFormat.Markdown
  else if SameText(AText, 'html') then
    AFormat := TLspHotspotFormat.Html
  else if SameText(AText, 'text') then
    AFormat := TLspHotspotFormat.Text
  else
  begin
    AFormat := TLspHotspotFormat.Json;
    Result := False;
  end;
end;

class function TLspHotspots.ApplyOptions(const AParams: TJSONObject; var ARequest: THotspotRequest;
  out AError: string): Boolean;
var
  mLevel: THotspotLevel;
  mMonths: Integer;
begin
  AError := '';
  if not THotspots.TryLevelOf(StringOf(AParams, 'level'), mLevel) then
  begin
    AError := '"level" ist unit oder method';
    Exit(False);
  end;
  ARequest.Level := mLevel;
  if not IntegerOf(AParams, 'months', ARequest.Options.Months, mMonths) or (mMonths < 1) or (mMonths > 60) then
  begin
    AError := '"months" ist eine ganze Zahl von 1 bis 60';
    Exit(False);
  end;
  ARequest.Options.Months := mMonths;
  Result := True;
end;

class function TLspHotspots.Limited(const AResult: THotspotResult; ALimit: Integer): THotspotResult;
begin
  Result := AResult;
  if ALimit <= 0 then
    Exit;
  if Length(Result.Units) > ALimit then
    Result.Units := Copy(Result.Units, 0, ALimit);
  if Length(Result.Methods) > ALimit then
    Result.Methods := Copy(Result.Methods, 0, ALimit);
  if Length(Result.Coupling) > ALimit then
    Result.Coupling := Copy(Result.Coupling, 0, ALimit);
end;

function TLspHotspots.ResultFor(const AParams: TJSONObject; out AEnabled, APending: Boolean;
  out AVcsError, ARoot: string): THotspotResult;
var
  mRequest: THotspotRequest;
  mSettings: TServerSettings;
  mVcs: IHotspotVcs;
  mError, mHead, mKey: string;
  mRefresh: TJSONValue;
begin
  Result := Default(THotspotResult);
  AEnabled := False;
  APending := False;
  AVcsError := '';
  ARoot := '';
  if not (Assigned(FSourceFor) and FSourceFor(PathOf(StringOf(AParams, 'uri')), mRequest, mSettings, mVcs,
    AVcsError)) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Kein Projekt geladen');
  AEnabled := mSettings.HotspotsEnabled;
  if not AEnabled then
    Exit;
  if not ApplyOptions(AParams, mRequest, mError) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, mError);
  if mVcs = nil then
  begin
    if AVcsError = '' then
      AVcsError := 'Keine Versionsverwaltung gefunden';
    Exit;
  end;
  ARoot := mVcs.Root;
  mHead := mVcs.Head;
  mKey := THotspots.KindName(mVcs.Kind) + #1 + mVcs.Root + #1 + mHead + #1 + mRequest.Key;
  mRefresh := nil;
  if AParams <> nil then
    mRefresh := AParams.GetValue('refresh');
  System.TMonitor.Enter(FJobLock);
  try
    if (mRefresh is TJSONBool) and TJSONBool(mRefresh).AsBoolean and not FRunning and (FDoneKey = mKey) then
      FDoneKey := '';
    if not FRunning and (FDoneKey = mKey) then
    begin
      mError := FDoneError;
      Result := FDone;
      // Ein Fehler kommt einmal, ein Ergebnis ohne Stand gilt nur für diese Anfrage; danach wird neu gerechnet.
      if (mError <> '') or FDoneOnce then
        FDoneKey := '';
      if mError <> '' then
        raise EJsonRpcError.Create(TJsonRpcErrorCode.InternalError, mError);
      Exit;
    end;
    APending := True;
    if not FRunning then
      StartJob(mKey, mRequest, mVcs, mHead = '');
  finally
    System.TMonitor.Exit(FJobLock);
  end;
end;

function TLspHotspots.Request(const AParams: TJSONValue): TJSONValue;
var
  mParams, mAnswer: TJSONObject;
  mFormat: TLspHotspotFormat;
  mSection: THotspotSection;
  mResult: THotspotResult;
  mEnabled, mPending: Boolean;
  mVcsError, mRoot: string;
  mLimit: Integer;
  mValue: TJSONValue;
begin
  if AParams is TJSONObject then
    mParams := TJSONObject(AParams)
  else
    mParams := nil;
  if not TryParseFormat(StringOf(mParams, 'format'), mFormat) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, '"format" ist json, markdown, html oder text');
  if not THotspotReport.ParseSection(StringOf(mParams, 'section'), mSection) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, '"section" ist hotspots oder coupling');
  if mFormat = TLspHotspotFormat.Text then
    mLimit := THotspotReport.TextLimit
  else
    mLimit := 0;
  if not IntegerOf(mParams, 'limit', mLimit, mLimit) or (mLimit < 0) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, '"limit" ist eine ganze Zahl ab 0');
  mResult := ResultFor(mParams, mEnabled, mPending, mVcsError, mRoot);
  mAnswer := TJSONObject.Create;
  try
    mAnswer.AddPair('enabled', TJSONBool.Create(mEnabled));
    if mEnabled then
    begin
      mAnswer.AddPair('vcs', TJSONBool.Create(mVcsError = ''));
      if mVcsError <> '' then
        mAnswer.AddPair('message', mVcsError)
      else if mPending then
      begin
        mAnswer.AddPair('root', mRoot);
        mAnswer.AddPair('pending', TJSONBool.Create(True));
      end
      else
      begin
        mAnswer.AddPair('root', mRoot);
        // Der Text kürzt selbst und nennt die Gesamtzahl ("20 von 431").
        if mFormat <> TLspHotspotFormat.Text then
          mResult := Limited(mResult, mLimit);
        case mFormat of
          TLspHotspotFormat.Json:
            begin
              mValue := TJSONObject.ParseJSONValue(THotspotReport.Json(mResult));
              if mValue = nil then
                raise EJsonRpcError.Create(TJsonRpcErrorCode.InternalError, 'Hotspot-Daten sind kein gültiges JSON');
              mAnswer.AddPair('format', 'json');
              mAnswer.AddPair('data', mValue);
            end;
          TLspHotspotFormat.Markdown:
            begin
              mAnswer.AddPair('format', 'markdown');
              mAnswer.AddPair('text', THotspotReport.Markdown(mResult));
            end;
          TLspHotspotFormat.Html:
            begin
              mAnswer.AddPair('format', 'html');
              mAnswer.AddPair('text', THotspotReport.Html(mResult));
            end;
          TLspHotspotFormat.Text:
            begin
              mAnswer.AddPair('format', 'text');
              mAnswer.AddPair('text', THotspotReport.Text(mResult, mSection, mLimit));
            end;
        end;
      end;
    end;
    Result := mAnswer;
    mAnswer := nil;
  finally
    mAnswer.Free;
  end;
end;

/// <summary>params aus [uri, Optionen] bzw. [uri, Datei, Optionen] (AOptionsAt).</summary>
function ParamsOf(const AArguments: TJSONArray; AOptionsAt: Integer): TJSONObject;
var
  mOptions: TJSONObject;
  mPair: TJSONPair;
begin
  Result := TJSONObject.Create;
  try
    if (AArguments <> nil) and (AArguments.Count > 0) and (AArguments.Items[0] is TJSONString) then
      Result.AddPair('uri', AArguments.Items[0].Value);
    if (AArguments <> nil) and (AArguments.Count > AOptionsAt) and (AArguments.Items[AOptionsAt] is TJSONObject) then
    begin
      mOptions := TJSONObject(AArguments.Items[AOptionsAt]);
      for mPair in mOptions do
        if mPair.JsonString.Value <> 'uri' then
          Result.AddPair(mPair.JsonString.Value, TJSONValue(mPair.JsonValue.Clone));
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TLspHotspots.Execute(const AArguments: TJSONArray): TJSONValue;
var
  mParams: TJSONObject;
begin
  mParams := ParamsOf(AArguments, 1);
  try
    Result := Request(mParams);
  finally
    mParams.Free;
  end;
end;

function TLspHotspots.SaveReport(const AArguments: TJSONArray): TJSONValue;
var
  mParams, mAnswer: TJSONObject;
  mTarget, mVcsError, mRoot: string;
  mResult: THotspotResult;
  mEnabled, mPending: Boolean;
  mLevel: THotspotLevel;
begin
  mTarget := '';
  if (AArguments <> nil) and (AArguments.Count > 1) and (AArguments.Items[1] is TJSONString) then
    mTarget := PathOf(AArguments.Items[1].Value);
  if mTarget = '' then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Zieldatei fehlt (.md, .html oder .json)');
  mParams := ParamsOf(AArguments, 2);
  try
    if not THotspots.TryLevelOf(StringOf(mParams, 'level'), mLevel) then
      raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, '"level" ist unit oder method');
    // Dieselbe Rechnung wie das Fenster (Methodenebene enthält die Units); gezeigt wird die gewählte Ebene.
    mParams.RemovePair('level').Free;
    mParams.AddPair('level', THotspots.LevelKey(THotspotLevel.Methods));
    mResult := ResultFor(mParams, mEnabled, mPending, mVcsError, mRoot);
  finally
    mParams.Free;
  end;
  if not mEnabled then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidRequest, 'Hotspots sind ausgeschaltet (hotspots.enabled)');
  if mVcsError <> '' then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidRequest, mVcsError);
  if mPending then
  begin
    mAnswer := TJSONObject.Create;
    mAnswer.AddPair('pending', TJSONBool.Create(True));
    Exit(mAnswer);
  end;
  mResult.Level := mLevel;
  ForceDirectories(ExtractFileDir(mTarget));
  // UTF-8 ohne BOM wie --hotspots; Browser und Markdown-Leser brauchen keins.
  TFile.WriteAllBytes(mTarget, TEncoding.UTF8.GetBytes(THotspotReport.ForFile(mResult, mTarget)));
  mAnswer := TJSONObject.Create;
  mAnswer.AddPair('file', mTarget);
  mAnswer.AddPair('units', TJSONNumber.Create(Length(mResult.Units)));
  Result := mAnswer;
end;

end.
