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
//           false schaltet den Vergleich mit architecture.baseline ab}
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
//   compareWith, compare). Berichte vergleichen wie atlas.architecture.

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
  Atlas.Common.Architecture.Snapshot;

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

function FlagOf(const AObject: TJSONObject; const AName: string; ADefault: Boolean): Boolean;
var
  Value: TJSONValue;
begin
  Result := ADefault;
  if AObject = nil then
    Exit;
  Value := AObject.GetValue(AName);
  if Value is TJSONBool then
    Result := TJSONBool(Value).AsBoolean;
end;

/// <summary>Pfad aus einer file-URI oder unverändert, wenn AText schon ein Pfad ist.</summary>
function PathOf(const AText: string): string;
begin
  if StartsText('file:', AText) then
    Result := TDocumentUris.ToPath(AText)
  else
    Result := AText;
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
    AFormat := TLspArchitectureFormat.Json
  else if SameText(AText, 'markdown') then
    AFormat := TLspArchitectureFormat.Markdown
  else if SameText(AText, 'html') then
    AFormat := TLspArchitectureFormat.Html
  else if SameText(AText, 'text') then
    AFormat := TLspArchitectureFormat.Text
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
begin
  Result := Default(TArchitectureOverview);
  ARoot := '';
  AEnabled := False;
  FileName := StringOf(AParams, 'uri');
  FileName := PathOf(FileName);
  Scope := StringOf(AParams, 'scope');
  if (Scope <> '') and (Scope <> 'project') and (Scope <> 'projectGroup') then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, '"scope" ist project oder projectGroup');
  if not (Assigned(FSourceFor) and FSourceFor(FileName, Scope, Request, ASettings)) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Kein Projekt geladen');
  AEnabled := ASettings.ArchitectureEnabled;
  if not AEnabled then
    Exit;
  ARoot := Request.Root;
  Request.IncludeLibrary := FlagOf(AParams, 'includeLibraryUnits', Request.IncludeLibrary);
  Result := FService.Overview(Request);
end;

/// <summary>Stand für den Vergleich (#1121): "compareWith", sonst architecture.baseline (außer "compare": false);
/// '' ohne Vergleich. Relativ zum Projekt.</summary>
function BaselineFile(const AParams: TJSONObject; const ARoot: string; const ASettings: TServerSettings): string;
begin
  Result := PathOf(StringOf(AParams, 'compareWith'));
  if (Result = '') and FlagOf(AParams, 'compare', True) then
    Result := ASettings.ArchitectureBaseline;
  Result := TArchitectureComparer.ResolvePath(ARoot, Result);
end;

/// <summary>Abweichungen aus architecture.failOn; unbekannte Namen hat der Parser schon gemeldet.</summary>
function FailOnOf(const ASettings: TServerSettings): TArchitectureFailKinds;
var
  Error: string;
begin
  if not TArchitectureComparer.ParseKinds(ASettings.ArchitectureFailOn, Result, Error) then
    Result := TArchitectureComparer.DefaultFailOn;
end;

function TLspArchitecture.Request(const AParams: TJSONValue): TJSONValue;
var
  Params, Answer: TJSONObject;
  Format: TLspArchitectureFormat;
  Section: TArchitectureSection;
  Overview: TArchitectureOverview;
  Settings: TServerSettings;
  Comparison: TArchitectureComparison;
  Compared: Boolean;
  FailOn: TArchitectureFailKinds;
  Enabled: Boolean;
  UnitName, Data, Root, Baseline, Error: string;
  Value: TJSONValue;
begin
  if AParams is TJSONObject then
    Params := TJSONObject(AParams)
  else
    Params := nil;
  if not TryParseFormat(StringOf(Params, 'format'), Format) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, '"format" ist json, markdown, html oder text');
  if not TArchitectureReport.ParseSection(StringOf(Params, 'section'), Section) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
      '"section" ist overview, central, subsystems, cycles oder crossLinks');
  Overview := OverviewFor(Params, Enabled, Root, Settings);
  Compared := False;
  Baseline := '';
  Error := '';
  FailOn := [];
  if Enabled then
  begin
    Baseline := BaselineFile(Params, Root, Settings);
    FailOn := FailOnOf(Settings);
    if Baseline <> '' then
      Compared := TArchitectureComparer.CompareWithFile(Baseline, Overview, Comparison, Error);
  end;
  Answer := TJSONObject.Create;
  try
    Answer.AddPair('enabled', TJSONBool.Create(Enabled));
    // Nur in der Antwort, nicht in den Berichtsdaten: Ein weitergegebener Bericht nennt keine lokalen Pfade.
    if Enabled then
      Answer.AddPair('root', Root);
    if Compared then
      Answer.AddPair('baseline', Baseline)
    else if Error <> '' then
      Answer.AddPair('comparisonError', Error);
    if Enabled then
      case Format of
        TLspArchitectureFormat.Json:
          begin
            Data := TArchitectureReport.Json(Overview, TArchitectureLayouter.Compute(Overview));
            Value := TJSONObject.ParseJSONValue(Data);
            if Value = nil then
              raise EJsonRpcError.Create(TJsonRpcErrorCode.InternalError, 'Architekturdaten sind kein gültiges JSON');
            Answer.AddPair('format', 'json');
            Answer.AddPair('data', Value);
            if Compared then
            begin
              Value := TJSONObject.ParseJSONValue(TArchitectureComparer.Json(Comparison, FailOn));
              if Value = nil then
                raise EJsonRpcError.Create(TJsonRpcErrorCode.InternalError, 'Vergleichsdaten sind kein gültiges JSON');
              Answer.AddPair('comparison', Value);
            end;
          end;
        TLspArchitectureFormat.Markdown:
          begin
            Answer.AddPair('format', 'markdown');
            if Compared then
              Answer.AddPair('text', TArchitectureReport.Markdown(Overview, Comparison))
            else
              Answer.AddPair('text', TArchitectureReport.Markdown(Overview));
          end;
        TLspArchitectureFormat.Html:
          begin
            Answer.AddPair('format', 'html');
            if Compared then
              Answer.AddPair('text', TArchitectureReport.Html(Overview, Comparison, FailOn))
            else
              Answer.AddPair('text', TArchitectureReport.Html(Overview));
          end;
        TLspArchitectureFormat.Text:
          begin
            Answer.AddPair('format', 'text');
            UnitName := StringOf(Params, 'unit');
            if UnitName <> '' then
              Answer.AddPair('text', TArchitectureReport.UnitText(Overview, UnitName))
            else if Compared then
              Answer.AddPair('text', TArchitectureComparer.Text(Comparison, FailOn, TArchitectureReport.TextLimit))
            else
              Answer.AddPair('text', TArchitectureReport.Text(Overview, Section, TArchitectureReport.TextLimit));
          end;
      end;
    Result := Answer;
    Answer := nil;
  finally
    Answer.Free;
  end;
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
      Params.AddPair('uri', AArguments.Items[0].Value);
    if (AArguments <> nil) and (AArguments.Count > 1) and (AArguments.Items[1] is TJSONObject) then
    begin
      Options := TJSONObject(AArguments.Items[1]);
      for Pair in Options do
        if Pair.JsonString.Value <> 'uri' then
          Params.AddPair(Pair.JsonString.Value, TJSONValue(Pair.JsonValue.Clone));
    end;
    Result := Request(Params);
  finally
    Params.Free;
  end;
end;

function TLspArchitecture.SaveReport(const AArguments: TJSONArray): TJSONValue;
var
  Params, Options: TJSONObject;
  Target, Root, Baseline, Error, Extension: string;
  Overview: TArchitectureOverview;
  Settings: TServerSettings;
  Comparison: TArchitectureComparison;
  Enabled, Compared: Boolean;
  Answer: TJSONObject;
  Name: string;
begin
  Params := TJSONObject.Create;
  try
    if (AArguments <> nil) and (AArguments.Count > 0) and (AArguments.Items[0] is TJSONString) then
      Params.AddPair('uri', AArguments.Items[0].Value);
    Target := '';
    if (AArguments <> nil) and (AArguments.Count > 1) and (AArguments.Items[1] is TJSONString) then
      Target := PathOf(AArguments.Items[1].Value);
    if Target = '' then
      raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Zieldatei fehlt (.md, .html oder .json)');
    if (AArguments <> nil) and (AArguments.Count > 2) and (AArguments.Items[2] is TJSONObject) then
    begin
      Options := TJSONObject(AArguments.Items[2]);
      for Name in TArray<string>.Create('scope', 'compareWith') do
        if StringOf(Options, Name) <> '' then
          Params.AddPair(Name, StringOf(Options, Name));
      for Name in TArray<string>.Create('includeLibraryUnits', 'compare') do
        if Options.GetValue(Name) is TJSONBool then
          Params.AddPair(Name, TJSONBool.Create(FlagOf(Options, Name, False)));
    end;
    Overview := OverviewFor(Params, Enabled, Root, Settings);
    Baseline := '';
    if Enabled then
      Baseline := BaselineFile(Params, Root, Settings);
  finally
    Params.Free;
  end;
  if not Enabled then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidRequest, 'Architekturübersicht ist ausgeschaltet ' +
      '(architecture.enabled)');
  Extension := LowerCase(ExtractFileExt(Target));
  Answer := TJSONObject.Create;
  try
    if Extension = '.json' then
      // Stand für den Vergleich (#1121): stabil sortiert, bei gleichem Stand byteweise gleich.
      TArchitectureSnapshots.Save(Target, TArchitectureSnapshots.FromOverview(Overview))
    else
    begin
      Compared := (Baseline <> '') and TArchitectureComparer.CompareWithFile(Baseline, Overview, Comparison, Error);
      if (Baseline <> '') and not Compared then
        Answer.AddPair('comparisonError', Error);
      ForceDirectories(ExtractFileDir(Target));
      // UTF-8 ohne BOM wie --architecture; Browser und Markdown-Leser brauchen keins.
      if Compared then
        TFile.WriteAllBytes(Target, TEncoding.UTF8.GetBytes(TArchitectureReport.ForFile(Overview, Target, Comparison,
          FailOnOf(Settings))))
      else
        TFile.WriteAllBytes(Target, TEncoding.UTF8.GetBytes(TArchitectureReport.ForFile(Overview, Target)));
    end;
    Answer.AddPair('file', Target);
    Answer.AddPair('units', TJSONNumber.Create(Length(Overview.Units)));
    Result := Answer;
    Answer := nil;
  finally
    Answer.Free;
  end;
end;

end.
