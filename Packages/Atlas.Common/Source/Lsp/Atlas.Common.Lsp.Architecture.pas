unit Atlas.Common.Lsp.Architecture;

// Architekturübersicht (#1118) im LSP-Server.
//
// Anfrage atlas/architecture (nebenläufig im Arbeitsthread):
//   params {"uri": Projekt, Ordner, Datei oder null (Arbeitsbereich der
//           Datei bzw. der einzige), "scope": "project"|"projectGroup"
//           (Vorgabe architecture.scope), "includeLibraryUnits": bool
//           (Vorgabe aus den Einstellungen), "format": "json" (Vorgabe),
//           "markdown", "html" oder "text", "section": overview, central,
//           subsystems, cycles, crossLinks (nur "text"), "unit": Name
//           (nur "text": Steckbrief), "compareWith": gespeicherter Stand
//           (#1121, Pfad oder file-URI, relativ zum Projekt), "compare":
//           false schaltet den Vergleich mit architecture.baseline ab,
//           "resolution": Feinheit γ der Teilsysteme 0,2–5,0 (#1366;
//           Vorgabe architecture.grouping.resolution, nur für diesen Aufruf),
//           "renameSubsystems": true rechnet einmal ohne Angleichung an den
//           vorigen Stand (#1367, Befehl „Teilsysteme neu benennen“)}
//   Antwort {"enabled": true, "root": Projektordner, "format": "json",
//   "data": {…}} mit den Daten aus TArchitectureReport.Json (samt Lage der
//   Karte; Pfade relativ zu "root"), sonst {"enabled": true, "root": …,
//   "format": …, "text": "…"}; {"enabled": false} bei
//   architecture.enabled = false.
//   Vergleich (#1121) mit "compareWith", sonst mit architecture.baseline
//   (außer "compare": false): "json" bekommt "comparison" (Daten aus
//   TArchitectureComparer.Json) und "baseline" (Pfad des Stands),
//   "markdown"/"html" den Abschnitt „Vergleich“, "text" den Text des
//   Vergleichs statt eines Abschnitts. Fehlt der Stand oder ist er nicht
//   lesbar, steht die Meldung in "comparisonError" (die Übersicht kommt
//   trotzdem).
// Befehl atlas.architecture (für das IDE-Fenster): Argumente [uri, Optionen]
//   mit denselben Optionen wie params der Anfrage, Antwort wie oben.
// Befehl atlas.architecture.saveReport: Argumente [uri, Datei, Optionen]
//   schreibt den Bericht nach der Endung (.md Markdown, .html/.htm HTML,
//   .json den Stand für den Vergleich, #1121) und liefert {"file": …,
//   "units": n}; Optionen wie bei der Anfrage (scope, includeLibraryUnits,
//   compareWith, compare, resolution). Berichte vergleichen wie atlas.architecture.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Architecture.Overview,
  Atlas.Common.Architecture.Service,
  Atlas.Common.Architecture.Comparison;

type
  /// <summary>Anfrage und Einstellungen zum Arbeitsbereich von AFileName ('' = der einzige oder erste).
  /// AScope: "project" oder "projectGroup"; bestimmt Files. False, wenn kein Arbeitsbereich passt.</summary>
  TLspArchitectureSourceFunc = reference to function(const AFileName, AScope: string;
    out ARequest: TArchitectureRequest; out ASettings: TServerSettings): Boolean;

  TLspArchitectureFormat = (Json, Markdown, Html, Text);

  TLspArchitecture = class
  public const
    Method = 'atlas/architecture';
    Command = 'atlas.architecture';
    SaveCommand = 'atlas.architecture.saveReport';
  private
    FService: TArchitectureService;
    FSourceFor: TLspArchitectureSourceFunc;
    function OverviewFor(const AParams: TJSONObject; out AEnabled: Boolean; out ARoot: string;
      out ASettings: TServerSettings): TArchitectureOverview;
  public
    /// <summary>AService gehört dem Aufrufer.</summary>
    constructor Create(AService: TArchitectureService; const ASourceFor: TLspArchitectureSourceFunc);
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>Antwort auf atlas/architecture; der Aufrufer übernimmt das Ergebnis.</summary>
    function Request(const AParams: TJSONValue): TJSONValue;
    /// <summary>Befehl atlas.architecture: [uri, Optionen] wie die Anfrage; der Aufrufer übernimmt das Ergebnis.
    /// </summary>
    function Execute(const AArguments: TJSONArray): TJSONValue;
    /// <summary>Befehl atlas.architecture.saveReport; der Aufrufer übernimmt das Ergebnis.</summary>
    function SaveReport(const AArguments: TJSONArray): TJSONValue;
    class function TryParseFormat(const AText: string; out AFormat: TLspArchitectureFormat): Boolean; static;
  end;

implementation

uses
  System.Generics.Collections,
  System.StrUtils,
  System.IOUtils,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Architecture.Layout,
  Atlas.Common.Architecture.Report,
  Atlas.Common.Architecture.Snapshot,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TArchitectureText = (ResolutionIsANumberFrom, ScopeIsProjectOrProjectGroup, NoProjectLoaded, AreNotValidJSON,
    FormatIsJsonMarkdownHtml, SectionIsOverviewCentralSubsystems, TargetFileMissingMdHtml,
    ArchitectureOverviewIsSwitchedOff, ArchitectureData, ComparisonData);

const
  cTexts: array[TArchitectureText] of TAtlasText = (
    (De: '"resolution" ist eine Zahl von 0,2 bis 5,0'; En: '"resolution" is a number from 0.2 to 5.0'),
    (De: '"scope" ist project oder projectGroup'; En: '"scope" is project or projectGroup'),
    (De: 'Kein Projekt geladen'; En: 'No project loaded'),
    (De: ' sind kein gültiges JSON'; En: ' are not valid JSON'),
    (De: '"format" ist json, markdown, html oder text'; En: '"format" is json, markdown, html or text'),
    (De: '"section" ist overview, central, subsystems, cycles oder crossLinks';
     En: '"section" is overview, central, subsystems, cycles or crossLinks'),
    (De: 'Zieldatei fehlt (.md, .html oder .json)'; En: 'Target file missing (.md, .html or .json)'),
    (De: 'Architekturübersicht ist ausgeschaltet (architecture.enabled)';
     En: 'Architecture overview is switched off (architecture.enabled)'),
    (De: 'Architekturdaten'; En: 'Architecture data'),
    (De: 'Vergleichsdaten'; En: 'Comparison data'));

{$SCOPEDENUMS OFF}

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

function FlagOf(const AObject: TJSONObject; const AName: string; ADefault: Boolean): Boolean;
var
  Value: TJSONValue;
begin
  Result := ADefault;
  if AObject = nil then
  begin
    Exit;
  end;
  Value := AObject.GetValue(AName);
  if Value is TJSONBool then
  begin
    Result := TJSONBool(Value).AsBoolean;
  end;
end;

/// <summary>Feinheit γ aus "resolution" (#1366); AFound False ohne Angabe. Außerhalb 0,2–5,0 oder keine Zahl:
/// Fehler InvalidParams.</summary>
function ResolutionOf(const AObject: TJSONObject; out AFound: Boolean): Double;
var
  mValue: TJSONValue;
begin
  Result := 1;
  AFound := False;
  if AObject = nil then
  begin
    Exit;
  end;
  mValue := AObject.GetValue('resolution');
  if mValue = nil then
  begin
    Exit;
  end;
  if not (mValue is TJSONNumber) or not TArchitectureGrouping.ValidResolution(TJSONNumber(mValue).AsDouble) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, cTexts[TArchitectureText.ResolutionIsANumberFrom].Text);
  end;
  AFound := True;
  Result := TJSONNumber(mValue).AsDouble;
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

{ TLspArchitecture }

constructor TLspArchitecture.Create(AService: TArchitectureService; const ASourceFor: TLspArchitectureSourceFunc);
begin
  inherited Create;
  FService := AService;
  FSourceFor := ASourceFor;
end;

procedure TLspArchitecture.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  // Bei einigen tausend Units dauert die Rechnung Sekundenbruchteile: nebenläufig, damit Editoranfragen nicht
  // warten.
  ADispatcher.RegisterConcurrentRequest(Method,
    function(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue
    begin
      Result := Request(AParams);
    end);
end;

class function TLspArchitecture.TryParseFormat(const AText: string; out AFormat: TLspArchitectureFormat): Boolean;
begin
  Result := True;
  if (AText = '') or SameText(AText, 'json') then
  begin
    AFormat := TLspArchitectureFormat.Json;
  end
  else if SameText(AText, 'markdown') then
  begin
    AFormat := TLspArchitectureFormat.Markdown;
  end
  else if SameText(AText, 'html') then
  begin
    AFormat := TLspArchitectureFormat.Html;
  end
  else if SameText(AText, 'text') then
  begin
    AFormat := TLspArchitectureFormat.Text;
  end
  else
  begin
    AFormat := TLspArchitectureFormat.Json;
    Result := False;
  end;
end;

function TLspArchitecture.OverviewFor(const AParams: TJSONObject; out AEnabled: Boolean; out ARoot: string;
  out ASettings: TServerSettings): TArchitectureOverview;
var
  FileName, Scope: string;
  Request: TArchitectureRequest;
  mResolution: Double;
  mFound: Boolean;
begin
  Result := Default(TArchitectureOverview);
  ARoot := '';
  AEnabled := False;
  FileName := StringOf(AParams, 'uri');
  FileName := PathOf(FileName);
  Scope := StringOf(AParams, 'scope');
  if (Scope <> '') and (Scope <> 'project') and (Scope <> 'projectGroup') then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
      cTexts[TArchitectureText.ScopeIsProjectOrProjectGroup].Text);
  end;
  mResolution := ResolutionOf(AParams, mFound);
  if not (Assigned(FSourceFor) and FSourceFor(FileName, Scope, Request, ASettings)) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, cTexts[TArchitectureText.NoProjectLoaded].Text);
  end;
  AEnabled := ASettings.ArchitectureEnabled;
  if not AEnabled then
  begin
    Exit;
  end;
  ARoot := Request.Root;
  Request.IncludeLibrary := FlagOf(AParams, 'includeLibraryUnits', Request.IncludeLibrary);
  // Nur für diesen Aufruf; die Einstellung bleibt (#1366).
  if mFound then
  begin
    Request.Grouping.Resolution := mResolution;
  end;
  Request.Rename := FlagOf(AParams, 'renameSubsystems', False);
  Result := FService.Overview(Request);
end;

/// <summary>Stand für den Vergleich (#1121): "compareWith", sonst architecture.baseline (außer "compare": false);
/// '' ohne Vergleich. Relativ zum Projekt.</summary>
function BaselineFile(const AParams: TJSONObject; const ARoot: string; const ASettings: TServerSettings): string;
begin
  Result := PathOf(StringOf(AParams, 'compareWith'));
  if (Result = '') and FlagOf(AParams, 'compare', True) then
  begin
    Result := ASettings.ArchitectureBaseline;
  end;
  Result := TArchitectureComparer.ResolvePath(ARoot, Result);
end;

/// <summary>Abweichungen aus architecture.failOn; unbekannte Namen hat der Parser schon gemeldet.</summary>
function FailOnOf(const ASettings: TServerSettings): TArchitectureFailKinds;
var
  Error: string;
begin
  if not TArchitectureComparer.ParseKinds(ASettings.ArchitectureFailOn, Result, Error) then
  begin
    Result := TArchitectureComparer.DefaultFailOn;
  end;
end;

type
  /// <summary>Übersicht samt Baseline und Vergleich einer Anfrage.</summary>
  TArchitectureState = record
    Overview: TArchitectureOverview;
    Enabled: Boolean;
    Root: string;
    Settings: TServerSettings;
    /// <summary>Datei der Baseline; '' ohne Vergleich.</summary>
    Baseline: string;
    FailOn: TArchitectureFailKinds;
    Compared: Boolean;
    Comparison: TArchitectureComparison;
    /// <summary>Grund, wenn der Vergleich mit der Baseline nicht ging.</summary>
    Error: string;
  end;

const
  cFormatNames: array[TLspArchitectureFormat] of string = ('json', 'markdown', 'html', 'text');

function StateFor(AOwner: TLspArchitecture; const AParams: TJSONObject): TArchitectureState;
begin
  Result := Default(TArchitectureState);
  Result.Overview := AOwner.OverviewFor(AParams, Result.Enabled, Result.Root, Result.Settings);
  if Result.Enabled then
  begin
    Result.Baseline := BaselineFile(AParams, Result.Root, Result.Settings);
    Result.FailOn := FailOnOf(Result.Settings);
  end;
end;

procedure Compare(var AState: TArchitectureState);
begin
  if AState.Baseline <> '' then
  begin
    AState.Compared := TArchitectureComparer.CompareWithFile(AState.Baseline, AState.Overview, AState.Comparison,
      AState.Error);
  end;
end;

/// <summary>AText als JSON; EJsonRpcError mit AWhat, wenn es keins ist.</summary>
function ParsedJson(const AText, AWhat: string): TJSONValue;
begin
  Result := TJSONObject.ParseJSONValue(AText);
  if Result = nil then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InternalError, AWhat + cTexts[TArchitectureText.AreNotValidJSON].Text);
  end;
end;

procedure AddJsonReport(AAnswer: TJSONObject; const AState: TArchitectureState);
begin
  AAnswer.AddPair('data', ParsedJson(TArchitectureReport.Json(AState.Overview,
    TArchitectureLayouter.Compute(AState.Overview)), cTexts[TArchitectureText.ArchitectureData].Text));
  if AState.Compared then
  begin
    AAnswer.AddPair('comparison', ParsedJson(TArchitectureComparer.Json(AState.Comparison, AState.FailOn),
      cTexts[TArchitectureText.ComparisonData].Text));
  end;
end;

function PlainText(const AParams: TJSONObject; const AState: TArchitectureState;
  ASection: TArchitectureSection): string;
var
  mUnitName: string;
begin
  mUnitName := StringOf(AParams, 'unit');
  if mUnitName <> '' then
  begin
    Result := TArchitectureReport.UnitText(AState.Overview, mUnitName);
  end
  else if AState.Compared then
  begin
    Result := TArchitectureComparer.Text(AState.Comparison, AState.FailOn, TArchitectureReport.TextLimit);
  end
  else
  begin
    Result := TArchitectureReport.Text(AState.Overview, ASection, TArchitectureReport.TextLimit);
  end;
end;

/// <summary>Bericht als Markdown, HTML oder Text.</summary>
function ReportText(AFormat: TLspArchitectureFormat; const AParams: TJSONObject; const AState: TArchitectureState;
  ASection: TArchitectureSection): string;
begin
  case AFormat of
    TLspArchitectureFormat.Markdown:
      if AState.Compared then
      begin
        Result := TArchitectureReport.Markdown(AState.Overview, AState.Comparison);
      end
      else
      begin
        Result := TArchitectureReport.Markdown(AState.Overview);
      end;
    TLspArchitectureFormat.Html:
      if AState.Compared then
      begin
        Result := TArchitectureReport.Html(AState.Overview, AState.Comparison, AState.FailOn);
      end
      else
      begin
        Result := TArchitectureReport.Html(AState.Overview);
      end;
  else
    Result := PlainText(AParams, AState, ASection);
  end;
end;

function AnswerFor(AFormat: TLspArchitectureFormat; const AParams: TJSONObject; const AState: TArchitectureState;
  ASection: TArchitectureSection): TJSONObject;
begin
  Result := TJSONObject.Create;
  try
    Result.AddPair('enabled', TJSONBool.Create(AState.Enabled));
    if not AState.Enabled then
    begin
      Exit;
    end;
    // Nur in der Antwort, nicht in den Berichtsdaten: Ein weitergegebener Bericht nennt keine lokalen Pfade.
    Result.AddPair('root', AState.Root);
    if AState.Compared then
    begin
      Result.AddPair('baseline', AState.Baseline);
    end
    else if AState.Error <> '' then
    begin
      Result.AddPair('comparisonError', AState.Error);
    end;
    Result.AddPair('format', cFormatNames[AFormat]);
    if AFormat = TLspArchitectureFormat.Json then
    begin
      AddJsonReport(Result, AState);
    end
    else
    begin
      Result.AddPair('text', ReportText(AFormat, AParams, AState, ASection));
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TLspArchitecture.Request(const AParams: TJSONValue): TJSONValue;
var
  mParams: TJSONObject;
  mFormat: TLspArchitectureFormat;
  mSection: TArchitectureSection;
  mState: TArchitectureState;
begin
  mParams := nil;
  if AParams is TJSONObject then
  begin
    mParams := TJSONObject(AParams);
  end;
  if not TryParseFormat(StringOf(mParams, 'format'), mFormat) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
      cTexts[TArchitectureText.FormatIsJsonMarkdownHtml].Text);
  end;
  if not TArchitectureReport.ParseSection(StringOf(mParams, 'section'), mSection) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
      cTexts[TArchitectureText.SectionIsOverviewCentralSubsystems].Text);
  end;
  mState := StateFor(Self, mParams);
  Compare(mState);
  Result := AnswerFor(mFormat, mParams, mState, mSection);
end;

function TLspArchitecture.Execute(const AArguments: TJSONArray): TJSONValue;
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
    Result := Request(Params);
  finally
    Params.Free;
  end;
end;

/// <summary>Optionen von saveReport, die die Übersicht bestimmen, in AParams übernehmen.</summary>
procedure CopySaveOptions(AOptions, AParams: TJSONObject);
var
  mName: string;
begin
  for mName in TArray<string>.Create('scope', 'compareWith') do
  begin
    if StringOf(AOptions, mName) <> '' then
    begin
      AParams.AddPair(mName, StringOf(AOptions, mName));
    end;
  end;
  for mName in TArray<string>.Create('includeLibraryUnits', 'compare') do
  begin
    if AOptions.GetValue(mName) is TJSONBool then
    begin
      AParams.AddPair(mName, TJSONBool.Create(FlagOf(AOptions, mName, False)));
    end;
  end;
  if AOptions.GetValue('resolution') <> nil then
  begin
    AParams.AddPair('resolution', TJSONValue(AOptions.GetValue('resolution').Clone));
  end;
end;

/// <summary>Zieldatei aus den Argumenten [uri, Ziel, Optionen]; EJsonRpcError, wenn sie fehlt.</summary>
function SaveTarget(const AArguments: TJSONArray): string;
begin
  Result := '';
  if (AArguments <> nil) and (AArguments.Count > 1) and (AArguments.Items[1] is TJSONString) then
  begin
    Result := PathOf(AArguments.Items[1].Value);
  end;
  if Result = '' then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, cTexts[TArchitectureText.TargetFileMissingMdHtml].Text);
  end;
end;

/// <summary>Schreibt den Bericht nach ATarget; ein misslungener Vergleich steht in AAnswer.</summary>
procedure WriteReport(const ATarget: string; var AState: TArchitectureState; AAnswer: TJSONObject);
var
  mText: string;
begin
  if SameText(ExtractFileExt(ATarget), '.json') then
  begin
    // Stand für den Vergleich (#1121): stabil sortiert, bei gleichem Stand byteweise gleich.
    TArchitectureSnapshots.Save(ATarget, TArchitectureSnapshots.FromOverview(AState.Overview));
    Exit;
  end;
  Compare(AState);
  if (AState.Baseline <> '') and not AState.Compared then
  begin
    AAnswer.AddPair('comparisonError', AState.Error);
  end;
  if AState.Compared then
  begin
    mText := TArchitectureReport.ForFile(AState.Overview, ATarget, AState.Comparison, AState.FailOn);
  end
  else
  begin
    mText := TArchitectureReport.ForFile(AState.Overview, ATarget);
  end;
  ForceDirectories(ExtractFileDir(ATarget));
  // UTF-8 ohne BOM wie --architecture; Browser und Markdown-Leser brauchen keins.
  TFile.WriteAllBytes(ATarget, TEncoding.UTF8.GetBytes(mText));
end;

function TLspArchitecture.SaveReport(const AArguments: TJSONArray): TJSONValue;
var
  mParams, mAnswer: TJSONObject;
  mTarget: string;
  mState: TArchitectureState;
begin
  mParams := TJSONObject.Create;
  try
    if (AArguments <> nil) and (AArguments.Count > 0) and (AArguments.Items[0] is TJSONString) then
    begin
      mParams.AddPair('uri', AArguments.Items[0].Value);
    end;
    mTarget := SaveTarget(AArguments);
    if (AArguments.Count > 2) and (AArguments.Items[2] is TJSONObject) then
    begin
      CopySaveOptions(TJSONObject(AArguments.Items[2]), mParams);
    end;
    mState := StateFor(Self, mParams);
  finally
    mParams.Free;
  end;
  if not mState.Enabled then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidRequest,
      cTexts[TArchitectureText.ArchitectureOverviewIsSwitchedOff].Text);
  end;
  mAnswer := TJSONObject.Create;
  try
    WriteReport(mTarget, mState, mAnswer);
    mAnswer.AddPair('file', mTarget);
    mAnswer.AddPair('units', TJSONNumber.Create(Length(mState.Overview.Units)));
    Result := mAnswer;
    mAnswer := nil;
  finally
    mAnswer.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.Architecture', cTexts);

end.
