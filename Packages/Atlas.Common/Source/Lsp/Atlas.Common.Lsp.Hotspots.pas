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
  Atlas.Common.Hotspots.Report,
  Atlas.Common.Hotspots.Service;

type
  /// <summary>Anfrage, Einstellungen und Versionsverwaltung zum Arbeitsbereich von AFileName ('' = der einzige oder
  /// erste). False, wenn kein Arbeitsbereich passt. AVcs nil mit AError, wenn keine Versionsverwaltung greift (nur
  /// bei eingeschalteten Hotspots gefragt).</summary>
  TLspHotspotSourceFunc = reference to function(const AFileName: string; out ARequest: THotspotRequest;
    out ASettings: TServerSettings; out AVcs: IHotspotVcs; out AError: string): Boolean;

  TLspHotspotFormat = (Json, Markdown, Html, Text);

  /// <summary>Stand einer Anfrage: Ergebnis, ob eingeschaltet, ob noch in Rechnung, Grund ohne
  /// Versionsverwaltung und Wurzel der Arbeitskopie.</summary>
  TLspHotspotOutcome = record
    Result: THotspotResult;
    Enabled: Boolean;
    Pending: Boolean;
    VcsError: string;
    Root: string;
  end;

  /// <summary>Darstellung einer Anfrage: Format, Abschnitt (nur Text) und Länge der Listen.</summary>
  TLspHotspotView = record
    Format: TLspHotspotFormat;
    Section: THotspotSection;
    Limit: Integer;
  end;

  TLspHotspots = class
  public const
    cMethod = 'atlas/hotspots';
    cCommand = 'atlas.hotspots';
    cSaveCommand = 'atlas.hotspots.saveReport';
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
    function Prepare(const AParams: TJSONObject; var AOutcome: TLspHotspotOutcome; out ARequest: THotspotRequest;
      out AVcs: IHotspotVcs): Boolean;
    procedure TakeOrStart(const AKey: string; const ARequest: THotspotRequest; const AVcs: IHotspotVcs;
      ARefresh, AOnce: Boolean; var AOutcome: TLspHotspotOutcome);
    function ResultFor(const AParams: TJSONObject): TLspHotspotOutcome;
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
  System.Generics.Collections,
  System.StrUtils,
  System.IOUtils,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Localization.Texts,
  Atlas.Text.Json;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  THotspotsText = (LevelIsUnitOrMethod, MonthsIsAWholeNumber, NoProjectLoaded, NoVersionControlFound,
    FormatIsJsonMarkdownHtml, SectionIsHotspotsOrCoupling, LimitIsAWholeNumber, HotspotDataIsNotValid,
    TargetFileMissingMdHtml, HotspotsAreSwitchedOffHotspots);

const
  cTexts: array[THotspotsText] of TAtlasText = (
    (De: '"level" ist unit oder method'; En: '"level" is unit or method'),
    (De: '"months" ist eine ganze Zahl von 1 bis 60'; En: '"months" is a whole number from 1 to 60'),
    (De: 'Kein Projekt geladen'; En: 'No project loaded'),
    (De: 'Keine Versionsverwaltung gefunden'; En: 'No version control found'),
    (De: '"format" ist json, markdown, html oder text'; En: '"format" is json, markdown, html or text'),
    (De: '"section" ist hotspots oder coupling'; En: '"section" is hotspots or coupling'),
    (De: '"limit" ist eine ganze Zahl ab 0'; En: '"limit" is a whole number from 0'),
    (De: 'Hotspot-Daten sind kein gültiges JSON'; En: 'Hotspot data is not valid JSON'),
    (De: 'Zieldatei fehlt (.md, .html oder .json)'; En: 'Target file missing (.md, .html or .json)'),
    (De: 'Hotspots sind ausgeschaltet (hotspots.enabled)'; En: 'Hotspots are switched off (hotspots.enabled)'));

{$SCOPEDENUMS OFF}

/// <summary>Ganze Zahl AName; ADefault ohne Angabe, False bei einem anderen Typ.</summary>
function IntegerOf(const AObject: TJSONObject; const AName: string; ADefault: Integer; out AValue: Integer): Boolean;
var
  mValue: TJSONValue;
begin
  AValue := ADefault;
  Result := True;
  if AObject = nil then
  begin
    Exit;
  end;
  mValue := AObject.GetValue(AName);
  if mValue = nil then
  begin
    Exit;
  end;
  Result := (mValue is TJSONNumber) and TryStrToInt(mValue.Value, AValue);
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
  begin
    mWorker.WaitFor;
  end;
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
        // lsp-ignore: catch-all-without-raise -- Fehlergrenze des Hintergrundjobs; Fehler geht ins Ergebnis
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
  ADispatcher.RegisterConcurrentRequest(cMethod,
    function(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue
    begin
      Result := Request(AParams);
    end);
end;

class function TLspHotspots.TryParseFormat(const AText: string; out AFormat: TLspHotspotFormat): Boolean;
begin
  Result := True;
  if (AText = '') or SameText(AText, 'json') then
  begin
    AFormat := TLspHotspotFormat.Json;
  end
  else if SameText(AText, 'markdown') then
  begin
    AFormat := TLspHotspotFormat.Markdown;
  end
  else if SameText(AText, 'html') then
  begin
    AFormat := TLspHotspotFormat.Html;
  end
  else if SameText(AText, 'text') then
  begin
    AFormat := TLspHotspotFormat.Text;
  end
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
  if not THotspots.TryLevelOf(TJsonRead.TrimmedText(AParams, 'level'), mLevel) then
  begin
    AError := cTexts[THotspotsText.LevelIsUnitOrMethod].Text;
    Exit(False);
  end;
  ARequest.Level := mLevel;
  if not IntegerOf(AParams, 'months', ARequest.Options.Months, mMonths) or (mMonths < 1) or (mMonths > 60) then
  begin
    AError := cTexts[THotspotsText.MonthsIsAWholeNumber].Text;
    Exit(False);
  end;
  ARequest.Options.Months := mMonths;
  Result := True;
end;

class function TLspHotspots.Limited(const AResult: THotspotResult; ALimit: Integer): THotspotResult;
begin
  Result := AResult;
  if ALimit <= 0 then
  begin
    Exit;
  end;
  if Length(Result.Units) > ALimit then
  begin
    Result.Units := Copy(Result.Units, 0, ALimit);
  end;
  if Length(Result.Methods) > ALimit then
  begin
    Result.Methods := Copy(Result.Methods, 0, ALimit);
  end;
  if Length(Result.Coupling) > ALimit then
  begin
    Result.Coupling := Copy(Result.Coupling, 0, ALimit);
  end;
end;

/// <summary>Wert von "refresh" in AParams; False ohne Angabe.</summary>
function RefreshOf(const AParams: TJSONObject): Boolean;
var
  mValue: TJSONValue;
begin
  Result := False;
  if AParams <> nil then
  begin
    mValue := AParams.GetValue('refresh');
    Result := (mValue is TJSONBool) and TJSONBool(mValue).AsBoolean;
  end;
end;

function TLspHotspots.Prepare(const AParams: TJSONObject; var AOutcome: TLspHotspotOutcome;
  out ARequest: THotspotRequest; out AVcs: IHotspotVcs): Boolean;
var
  mSettings: TServerSettings;
  mError: string;
begin
  if not (Assigned(FSourceFor) and FSourceFor(PathOf(TJsonRead.TrimmedText(AParams, 'uri')), ARequest, mSettings, AVcs,
    AOutcome.VcsError)) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams, cTexts[THotspotsText.NoProjectLoaded].Text);
  end;
  AOutcome.Enabled := mSettings.HotspotsEnabled;
  Result := False;
  if AOutcome.Enabled then
  begin
    if not ApplyOptions(AParams, ARequest, mError) then
    begin
      raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams, mError);
    end;
    Result := AVcs <> nil;
    if not Result and (AOutcome.VcsError = '') then
    begin
      AOutcome.VcsError := cTexts[THotspotsText.NoVersionControlFound].Text;
    end;
  end;
end;

procedure TLspHotspots.TakeOrStart(const AKey: string; const ARequest: THotspotRequest; const AVcs: IHotspotVcs;
  ARefresh, AOnce: Boolean; var AOutcome: TLspHotspotOutcome);
var
  mError: string;
begin
  System.TMonitor.Enter(FJobLock);
  try
    if ARefresh and not FRunning and (FDoneKey = AKey) then
    begin
      FDoneKey := '';
    end;
    AOutcome.Pending := FRunning or (FDoneKey <> AKey);
    if not AOutcome.Pending then
    begin
      mError := FDoneError;
      AOutcome.Result := FDone;
      // Ein Fehler kommt einmal, ein Ergebnis ohne Stand gilt nur für diese Anfrage; danach wird neu gerechnet.
      if (mError <> '') or FDoneOnce then
      begin
        FDoneKey := '';
      end;
      if mError <> '' then
      begin
        raise EJsonRpcError.Create(TJsonRpcErrorCode.cInternalError, mError);
      end;
    end
    else if not FRunning then
    begin
      StartJob(AKey, ARequest, AVcs, AOnce);
    end;
  finally
    System.TMonitor.Exit(FJobLock);
  end;
end;

function TLspHotspots.ResultFor(const AParams: TJSONObject): TLspHotspotOutcome;
var
  mRequest: THotspotRequest;
  mVcs: IHotspotVcs;
  mHead, mKey: string;
begin
  Result := Default(TLspHotspotOutcome);
  if Prepare(AParams, Result, mRequest, mVcs) then
  begin
    Result.Root := mVcs.Root;
    mHead := mVcs.Head;
    mKey := THotspots.KindName(mVcs.Kind) + #1 + mVcs.Root + #1 + mHead + #1 + mRequest.Key;
    TakeOrStart(mKey, mRequest, mVcs, RefreshOf(AParams), mHead = '', Result);
  end;
end;

/// <summary>Format, Abschnitt und Listenlänge aus AParams; Fehler der Anfrage bei ungültigen Werten.</summary>
function ViewOf(const AParams: TJSONObject): TLspHotspotView;
begin
  if not TLspHotspots.TryParseFormat(TJsonRead.TrimmedText(AParams, 'format'), Result.Format) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams, cTexts[THotspotsText.FormatIsJsonMarkdownHtml].Text);
  end;
  if not THotspotReport.ParseSection(TJsonRead.TrimmedText(AParams, 'section'), Result.Section) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams,
      cTexts[THotspotsText.SectionIsHotspotsOrCoupling].Text);
  end;
  Result.Limit := 0;
  if Result.Format = TLspHotspotFormat.Text then
  begin
    Result.Limit := THotspotReport.cTextLimit;
  end;
  if not IntegerOf(AParams, 'limit', Result.Limit, Result.Limit) or (Result.Limit < 0) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams, cTexts[THotspotsText.LimitIsAWholeNumber].Text);
  end;
end;

/// <summary>Fertiges Ergebnis in der gewählten Darstellung an AAnswer anhängen.</summary>
procedure AddReport(AAnswer: TJSONObject; const AResult: THotspotResult; const AView: TLspHotspotView);
var
  mValue: TJSONValue;
begin
  case AView.Format of
    TLspHotspotFormat.Json:
      begin
        mValue := TJSONObject.ParseJSONValue(THotspotReport.Json(AResult));
        if mValue = nil then
        begin
          raise EJsonRpcError.Create(TJsonRpcErrorCode.cInternalError,
            cTexts[THotspotsText.HotspotDataIsNotValid].Text);
        end;
        AAnswer.AddPair('format', 'json');
        AAnswer.AddPair('data', mValue);
      end;
    TLspHotspotFormat.Markdown:
      begin
        AAnswer.AddPair('format', 'markdown');
        AAnswer.AddPair('text', THotspotReport.Markdown(AResult));
      end;
    TLspHotspotFormat.Html:
      begin
        AAnswer.AddPair('format', 'html');
        AAnswer.AddPair('text', THotspotReport.Html(AResult));
      end;
    TLspHotspotFormat.Text:
      begin
        AAnswer.AddPair('format', 'text');
        AAnswer.AddPair('text', THotspotReport.Text(AResult, AView.Section, AView.Limit));
      end;
  end;
end;

/// <summary>Felder der Antwort bei eingeschalteten Hotspots: vcs, dann Grund, pending oder Bericht.</summary>
procedure AddEnabledAnswer(AAnswer: TJSONObject; const AOutcome: TLspHotspotOutcome; const AView: TLspHotspotView);
begin
  AAnswer.AddPair('vcs', TJSONBool.Create(AOutcome.VcsError = ''));
  if AOutcome.VcsError <> '' then
  begin
    AAnswer.AddPair('message', AOutcome.VcsError);
  end
  else if AOutcome.Pending then
  begin
    AAnswer.AddPair('root', AOutcome.Root);
    AAnswer.AddPair('pending', TJSONBool.Create(True));
  end
  else
  begin
    AAnswer.AddPair('root', AOutcome.Root);
    // Der Text kürzt selbst und nennt die Gesamtzahl ("20 von 431").
    if AView.Format = TLspHotspotFormat.Text then
    begin
      AddReport(AAnswer, AOutcome.Result, AView);
    end
    else
    begin
      AddReport(AAnswer, TLspHotspots.Limited(AOutcome.Result, AView.Limit), AView);
    end;
  end;
end;

function TLspHotspots.Request(const AParams: TJSONValue): TJSONValue;
var
  mParams, mAnswer: TJSONObject;
  mView: TLspHotspotView;
  mOutcome: TLspHotspotOutcome;
begin
  mParams := nil;
  if AParams is TJSONObject then
  begin
    mParams := TJSONObject(AParams);
  end;
  mView := ViewOf(mParams);
  mOutcome := ResultFor(mParams);
  mAnswer := TJSONObject.Create;
  try
    mAnswer.AddPair('enabled', TJSONBool.Create(mOutcome.Enabled));
    if mOutcome.Enabled then
    begin
      AddEnabledAnswer(mAnswer, mOutcome, mView);
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
    begin
      Result.AddPair('uri', AArguments.Items[0].Value);
    end;
    if (AArguments <> nil) and (AArguments.Count > AOptionsAt) and (AArguments.Items[AOptionsAt] is TJSONObject) then
    begin
      mOptions := TJSONObject(AArguments.Items[AOptionsAt]);
      for mPair in mOptions do
      begin
        if mPair.JsonString.Value <> 'uri' then
        begin
          Result.AddPair(mPair.JsonString.Value, TJSONValue(mPair.JsonValue.Clone));
        end;
      end;
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

/// <summary>Zieldatei aus [uri, Datei, Optionen]; Fehler der Anfrage ohne Datei.</summary>
function TargetOf(const AArguments: TJSONArray): string;
begin
  Result := '';
  if (AArguments <> nil) and (AArguments.Count > 1) and (AArguments.Items[1] is TJSONString) then
  begin
    Result := PathOf(AArguments.Items[1].Value);
  end;
  if Result = '' then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams, cTexts[THotspotsText.TargetFileMissingMdHtml].Text);
  end;
end;

/// <summary>Fehler der Anfrage, wenn sich kein Bericht schreiben lässt (ausgeschaltet, ohne
/// Versionsverwaltung).</summary>
procedure CheckSavable(const AOutcome: TLspHotspotOutcome);
begin
  if not AOutcome.Enabled then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidRequest,
      cTexts[THotspotsText.HotspotsAreSwitchedOffHotspots].Text);
  end;
  if AOutcome.VcsError <> '' then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidRequest, AOutcome.VcsError);
  end;
end;

function TLspHotspots.SaveReport(const AArguments: TJSONArray): TJSONValue;
var
  mParams, mAnswer: TJSONObject;
  mTarget: string;
  mOutcome: TLspHotspotOutcome;
  mLevel: THotspotLevel;
begin
  mTarget := TargetOf(AArguments);
  mParams := ParamsOf(AArguments, 2);
  try
    if not THotspots.TryLevelOf(TJsonRead.TrimmedText(mParams, 'level'), mLevel) then
    begin
      raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams, cTexts[THotspotsText.LevelIsUnitOrMethod].Text);
    end;
    // Dieselbe Rechnung wie das Fenster (Methodenebene enthält die Units); gezeigt wird die gewählte Ebene.
    mParams.RemovePair('level').Free;
    mParams.AddPair('level', THotspots.LevelKey(THotspotLevel.Methods));
    mOutcome := ResultFor(mParams);
  finally
    mParams.Free;
  end;
  CheckSavable(mOutcome);
  if mOutcome.Pending then
  begin
    mAnswer := TJSONObject.Create;
    mAnswer.AddPair('pending', TJSONBool.Create(True));
  end
  else
  begin
    mOutcome.Result.Level := mLevel;
    ForceDirectories(ExtractFileDir(mTarget));
    // UTF-8 ohne BOM wie --hotspots; Browser und Markdown-Leser brauchen keins.
    TFile.WriteAllBytes(mTarget, TEncoding.UTF8.GetBytes(THotspotReport.ForFile(mOutcome.Result, mTarget)));
    mAnswer := TJSONObject.Create;
    mAnswer.AddPair('file', mTarget);
    mAnswer.AddPair('units', TJSONNumber.Create(Length(mOutcome.Result.Units)));
  end;
  Result := mAnswer;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.Hotspots', cTexts);

end.
