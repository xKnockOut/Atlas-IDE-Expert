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
//           (nur "text": Steckbrief)}
//   Antwort {"enabled": true, "format": "json", "data": {…}} mit den Daten
//   aus TArchitectureReport.Json (samt Lage der Karte), sonst
//   {"enabled": true, "format": …, "text": "…"};
//   {"enabled": false} bei architecture.enabled = false.
// Befehl atlas.architecture.saveReport: Argumente [uri, Datei, Optionen]
//   schreibt den Bericht nach der Endung (.md Markdown, .html/.htm HTML) und
//   liefert {"file": …, "units": n}; Optionen wie bei der Anfrage (scope,
//   includeLibraryUnits).

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Architecture.Overview,
  Atlas.Common.Architecture.Service;

type
  /// <summary>Anfrage und Einstellungen zum Arbeitsbereich von AFileName ('' = der einzige oder erste).
  /// AScope: "project" oder "projectGroup"; bestimmt Files. False, wenn kein Arbeitsbereich passt.</summary>
  TLspArchitectureSourceFunc = reference to function(const AFileName, AScope: string;
    out ARequest: TArchitectureRequest; out ASettings: TServerSettings): Boolean;

  TLspArchitectureFormat = (Json, Markdown, Html, Text);

  TLspArchitecture = class
  public const
    Method = 'atlas/architecture';
    SaveCommand = 'atlas.architecture.saveReport';
  private
    FService: TArchitectureService;
    FSourceFor: TLspArchitectureSourceFunc;
    function OverviewFor(const AParams: TJSONObject; out AEnabled: Boolean): TArchitectureOverview;
  public
    /// <summary>AService gehört dem Aufrufer.</summary>
    constructor Create(AService: TArchitectureService; const ASourceFor: TLspArchitectureSourceFunc);
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>Antwort auf atlas/architecture; der Aufrufer übernimmt das Ergebnis.</summary>
    function Request(const AParams: TJSONValue): TJSONValue;
    /// <summary>Befehl atlas.architecture.saveReport; der Aufrufer übernimmt das Ergebnis.</summary>
    function SaveReport(const AArguments: TJSONArray): TJSONValue;
    class function TryParseFormat(const AText: string; out AFormat: TLspArchitectureFormat): Boolean; static;
  end;

implementation

uses
  System.StrUtils,
  System.IOUtils,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Architecture.Layout,
  Atlas.Common.Architecture.Report;

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

function TLspArchitecture.OverviewFor(const AParams: TJSONObject; out AEnabled: Boolean): TArchitectureOverview;
var
  FileName, Scope: string;
  Request: TArchitectureRequest;
  Settings: TServerSettings;
begin
  Result := Default(TArchitectureOverview);
  FileName := StringOf(AParams, 'uri');
  FileName := PathOf(FileName);
  Scope := StringOf(AParams, 'scope');
  if (Scope <> '') and (Scope <> 'project') and (Scope <> 'projectGroup') then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, '"scope" ist project oder projectGroup');
  if not (Assigned(FSourceFor) and FSourceFor(FileName, Scope, Request, Settings)) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Kein Projekt geladen');
  AEnabled := Settings.ArchitectureEnabled;
  if not AEnabled then
    Exit;
  Request.IncludeLibrary := FlagOf(AParams, 'includeLibraryUnits', Request.IncludeLibrary);
  Result := FService.Overview(Request);
end;

function TLspArchitecture.Request(const AParams: TJSONValue): TJSONValue;
var
  Params, Answer: TJSONObject;
  Format: TLspArchitectureFormat;
  Section: TArchitectureSection;
  Overview: TArchitectureOverview;
  Enabled: Boolean;
  UnitName, Data: string;
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
  Overview := OverviewFor(Params, Enabled);
  Answer := TJSONObject.Create;
  try
    Answer.AddPair('enabled', TJSONBool.Create(Enabled));
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
          end;
        TLspArchitectureFormat.Markdown:
          begin
            Answer.AddPair('format', 'markdown');
            Answer.AddPair('text', TArchitectureReport.Markdown(Overview));
          end;
        TLspArchitectureFormat.Html:
          begin
            Answer.AddPair('format', 'html');
            Answer.AddPair('text', TArchitectureReport.Html(Overview));
          end;
        TLspArchitectureFormat.Text:
          begin
            Answer.AddPair('format', 'text');
            UnitName := StringOf(Params, 'unit');
            if UnitName <> '' then
              Answer.AddPair('text', TArchitectureReport.UnitText(Overview, UnitName))
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

function TLspArchitecture.SaveReport(const AArguments: TJSONArray): TJSONValue;
var
  Params: TJSONObject;
  FileName, Target: string;
  Overview: TArchitectureOverview;
  Enabled: Boolean;
  Answer: TJSONObject;
begin
  Params := TJSONObject.Create;
  try
    if (AArguments <> nil) and (AArguments.Count > 0) and (AArguments.Items[0] is TJSONString) then
      Params.AddPair('uri', AArguments.Items[0].Value);
    Target := '';
    if (AArguments <> nil) and (AArguments.Count > 1) and (AArguments.Items[1] is TJSONString) then
      Target := PathOf(AArguments.Items[1].Value);
    if Target = '' then
      raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Zieldatei fehlt (.md oder .html)');
    if (AArguments <> nil) and (AArguments.Count > 2) and (AArguments.Items[2] is TJSONObject) then
    begin
      FileName := StringOf(TJSONObject(AArguments.Items[2]), 'scope');
      if FileName <> '' then
        Params.AddPair('scope', FileName);
      if TJSONObject(AArguments.Items[2]).GetValue('includeLibraryUnits') is TJSONBool then
        Params.AddPair('includeLibraryUnits', TJSONBool.Create(FlagOf(TJSONObject(AArguments.Items[2]),
          'includeLibraryUnits', False)));
    end;
    Overview := OverviewFor(Params, Enabled);
  finally
    Params.Free;
  end;
  if not Enabled then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidRequest, 'Architekturübersicht ist ausgeschaltet ' +
      '(architecture.enabled)');
  ForceDirectories(ExtractFileDir(Target));
  // UTF-8 ohne BOM wie --architecture; Browser und Markdown-Leser brauchen keins.
  TFile.WriteAllBytes(Target, TEncoding.UTF8.GetBytes(TArchitectureReport.ForFile(Overview, Target)));
  Answer := TJSONObject.Create;
  Answer.AddPair('file', Target);
  Answer.AddPair('units', TJSONNumber.Create(Length(Overview.Units)));
  Result := Answer;
end;

end.
