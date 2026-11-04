unit Shell.Mcp.ChangeTools;

// Host-Rolle Shell: MCP-Modus (--mcp, #48), Werkzeuge rund um Änderungen: betroffene Tests (#1353),
// Hotspots aus Änderungshäufigkeit (#1354).

interface

uses
  System.SysUtils,
  Atlas.Common.Mcp.Paths,
  Atlas.Common.Mcp.Prompts,
  Atlas.Common.Index.Contract,
  Shell.WorkspaceGroup,
  Shell.Mcp.Context;

/// <summary>get_affected_tests (#1353): betroffene Tests der Änderungen gegenüber einer Basis; das Ergebnis im
/// Format json passt mit "run" direkt in run_tests.tests.</summary>
procedure RegisterAffectedTestsTool(const AContext: TMcpToolContext);
/// <summary>get_hotspots (#1354): derselbe Dienst wie atlas/hotspots und --hotspots.</summary>
procedure RegisterHotspotTools(const AContext: TMcpToolContext);

implementation

uses
  Atlas.Common.Mcp.Server,
  Atlas.Common.Hotspots.Service,
  System.JSON,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Lsp.References,
  Atlas.Common.Lsp.AffectedTests,
  Atlas.Common.Semantics.NameResolver,
  Shell.VcsChanges,
  Atlas.Common.Compiler.Contract,
  Atlas.Common.Hotspots.Contract,
  Atlas.Common.Hotspots.Analysis,
  Atlas.Common.Hotspots.Report,
  Atlas.Common.Lsp.Hotspots,
  Shell.Platform,
  Shell.Bootstrap,
  Shell.AffectedTests,
  Shell.Hotspots;
/// <summary>Basis, includeUncommitted (Vorgabe True) und Tiefe aus den Argumenten von get_affected_tests.</summary>
function AffectedQueryOf(const ARoot: string; const AArguments: TJSONObject): TShellAffectedQuery;
begin
  Result := Default(TShellAffectedQuery);
  Result.WorkingDir := ARoot;
  Result.Base := TMcpServer.OptionalString(AArguments, 'base');
  if (AArguments = nil) or not AArguments.TryGetValue<Boolean>('includeUncommitted', Result.IncludeUncommitted) then
  begin
    Result.IncludeUncommitted := True;
  end;
  if (AArguments = nil) or not AArguments.TryGetValue<Integer>('depth', Result.Depth) then
  begin
    Result.Depth := 0;
  end;
end;

function AffectedReadText: TReferenceReadText;
begin
  Result :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := TShellBootstrap.ReadSourceText(AFileName, AText);
    end;
end;

/// <summary>Dateien und Testprogramme der Gruppe; Treffersicherheit und Zeitlimit wie get_impact.</summary>
function AffectedRequestOf(const AContext: TMcpToolContext; const ASettings: TServerSettings;
  const AReadText: TReferenceReadText): TAffectedRequest;
begin
  Result := Default(TAffectedRequest);
  Result.Files := AContext.Group.AllFiles;
  Result.TestPrograms := TShellAffectedTests.TestPrograms(Result.Files, AReadText);
  Result.Options := AContext.ImpactOptionsFor('');
  // Testunits aus allen Testprogrammen der Gruppe.
  Result.Options.Tests := TShellAffectedTests.TestScope(ASettings.TestUnits.Pattern, Result.TestPrograms, AReadText);
end;

function EnsureUnitOf(AGroup: TShellWorkspaceGroup): TEnsureUnitFunc;
begin
  Result :=
    function(const AUnitName: string): Boolean
    begin
      Result := AGroup.EnsureUnit(AUnitName);
    end;
end;

/// <summary>Betroffene Tests über den Index der Gruppe; Fehler der Versionsverwaltung als EMcpToolError.</summary>
function FindAffected(AGroup: TShellWorkspaceGroup; const ASettings: TServerSettings;
  const AQuery: TShellAffectedQuery; const ARequest: TAffectedRequest; const AReadText: TReferenceReadText):
  TAffectedResult;
var
  mResolver: TNameResolver;
  mProcess: ICompilerProcess;
begin
  // In einer Interface-Variablen: als const-Argument würde das Objekt nie freigegeben.
  mProcess := TProcessRunner.Create;
  mResolver := TNameResolver.Create(AGroup.Index, EnsureUnitOf(AGroup));
  try
    mResolver.Namespaces := AGroup.Main.State.Namespaces;
    try
      Result := TShellAffectedTests.Run(mProcess, ASettings, AQuery,
        TShellAffectedSources.New(mResolver, AGroup.Index, AReadText), ARequest, nil);
    except
      on E: EVcsChanges do
        raise EMcpToolError.Create(E.Message);
    end;
  finally
    mResolver.Free;
  end;
end;

/// <summary>Format dunitx: nur das --run-Argument; ohne Argument sagt der Text warum.</summary>
function DUnitXText(const AFound: TAffectedResult): string;
begin
  if AFound.All then
  begin
    Result := 'Alle Tests nötig: ' + AFound.AllReason;
  end
  else if Length(AFound.Tests) = 0 then
  begin
    Result := Format('Keine betroffenen Tests gegenüber %s.', [AFound.Base]);
  end
  else if not TAffectedTests.DUnitXArgument(AFound, Result) then
  begin
    Result := 'Alle Tests nötig: zu viele Tests für ein --run-Argument';
  end;
end;

function ToolGetAffectedTests(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
var
  mSettings: TServerSettings;
  mFormat: TAffectedFormat;
  mReadText: TReferenceReadText;
  mFound: TAffectedResult;
begin
  mSettings := AContext.Group.Main.Configuration.Settings;
  if not mSettings.Tests.Affected then
  begin
    raise EMcpToolError.Create(TShellAffectedTests.OffMessage);
  end;
  if not TAffectedTests.TryParseFormat(TMcpServer.OptionalString(AArguments, 'format'), mFormat) then
  begin
    raise EMcpToolError.Create('"format" ist text, json oder dunitx');
  end;
  mReadText := AffectedReadText();
  mFound := FindAffected(AContext.Group, mSettings, AffectedQueryOf(AContext.Root, AArguments),
    AffectedRequestOf(AContext, mSettings, mReadText), mReadText);
  if mFormat = TAffectedFormat.DUnitX then
  begin
    Result := DUnitXText(mFound);
  end
  else
  begin
    Result := TAffectedTests.Render(mFound, mFormat);
  end;
end;

procedure AddGetAffectedTests(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool('get_affected_tests',
    'Betroffene Tests einer Änderung (#1353): aus dem Unterschied zur Basis (Git oder SVN wie --changed) die ' +
    'geänderten Routinen, Typen und Konstanten bestimmen, ihre Auswirkungen bis zur Tiefe verfolgen (wie ' +
    'get_impact) und die DUnitX-Testmethoden nennen, die sie erreichen, je mit Grund. Sind mehr als 80 % einer ' +
    'Fixture betroffen, die ganze Fixture. "run" im Format json passt direkt in run_tests.tests; "all" heißt, ' +
    'dass alle Tests nötig sind (Grund in "reason").',
    '{"type":"object","properties":{' +
      '"base":{"type":"string","description":"Git-Ref (Merge-Base mit HEAD) bzw. SVN-Revision; leer = main bzw. ' +
        'BASE"},' +
      '"includeUncommitted":{"type":"boolean","default":true,"description":"Index, Arbeitsverzeichnis und neue ' +
        'Dateien mitzählen"},' +
      '"depth":{"type":"integer","minimum":1,"maximum":5,"description":"Ebenen; leer = tests.affectedDepth"},' +
      '"format":{"type":"string","enum":["text","json","dunitx"],"description":"text (Vorgabe), json oder ' +
        'dunitx (Argument --run:… für die Test-EXE)"}}}',
    ContextTool(AContext, ToolGetAffectedTests), TMcpToolKind.Process);
end;


/// <summary>get_affected_tests (#1353): betroffene Tests der Änderungen gegenüber einer Basis; das Ergebnis im
/// Format json passt mit "run" direkt in run_tests.tests.</summary>
procedure RegisterAffectedTestsTool(const AContext: TMcpToolContext);
begin
  AddGetAffectedTests(AContext);
end;
/// <summary>Format von get_hotspots: text, markdown oder json ('' = text).</summary>
function HotspotFormatOf(const AArguments: TJSONObject): string;
begin
  Result := TMcpServer.OptionalString(AArguments, 'format');
  if (Result <> '') and not SameText(Result, 'text') and not SameText(Result, 'markdown') and
    not SameText(Result, 'json') then
  begin
    raise EMcpToolError.Create('"format" ist text, markdown oder json');
  end;
end;

/// <summary>Höchstzahl der Einträge aus limit (Vorgabe THotspotReport.TextLimit).</summary>
function HotspotLimitOf(const AArguments: TJSONObject): Integer;
begin
  if not AArguments.TryGetValue<Integer>('limit', Result) then
  begin
    Result := THotspotReport.TextLimit;
  end;
  if Result < 1 then
  begin
    raise EMcpToolError.Create('"limit" ist eine ganze Zahl ab 1');
  end;
end;

/// <summary>Anfrage aus Einstellungen und Argumenten; Umfang wie get_architecture (architecture.scope).</summary>
function HotspotRequestOf(const AContext: TMcpToolContext; const ASettings: TServerSettings;
  const AArguments: TJSONObject): THotspotRequest;
var
  mError: string;
begin
  Result := THotspotRequest.FromSettings(ASettings);
  if not TLspHotspots.ApplyOptions(AArguments, Result, mError) then
  begin
    raise EMcpToolError.Create(mError);
  end;
  Result.Title := ExtractFileName(AContext.Root);
  Result.Root := AContext.Root;
  Result.Namespaces := AContext.Group.Main.State.Namespaces;
  if ASettings.ArchitectureScope = 'project' then
  begin
    Result.Files := AContext.Group.Main.State.ProjectFiles;
  end
  else
  begin
    Result.Files := AContext.Group.AllFiles;
  end;
  if Length(Result.Files) = 0 then
  begin
    raise EMcpToolError.Create('Kein Projekt geladen');
  end;
end;

/// <summary>Bericht im gewünschten Format; der Text kürzt selbst und nennt die Gesamtzahl ("20 von 431").</summary>
function HotspotText(const AResult: THotspotResult; const AFormat: string; ASection: THotspotSection;
  ALimit: Integer): string;
begin
  if SameText(AFormat, 'json') then
  begin
    Result := THotspotReport.Json(TLspHotspots.Limited(AResult, ALimit));
  end
  else if SameText(AFormat, 'markdown') then
  begin
    Result := THotspotReport.Markdown(TLspHotspots.Limited(AResult, ALimit));
  end
  else
  begin
    Result := THotspotReport.Text(AResult, ASection, ALimit);
  end;
end;

function ToolGetHotspots(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
var
  mSettings: TServerSettings;
  mRequest: THotspotRequest;
  mResult: THotspotResult;
  mSection: THotspotSection;
  mVcs: IHotspotVcs;
  mFormat, mError: string;
  mLimit: Integer;
begin
  mSettings := AContext.Group.Main.Configuration.Settings;
  if not mSettings.HotspotsEnabled then
  begin
    raise EMcpToolError.Create('Hotspots sind ausgeschaltet (hotspots.enabled)');
  end;
  if not THotspotReport.ParseSection(TMcpServer.OptionalString(AArguments, 'section'), mSection) then
  begin
    raise EMcpToolError.Create('"section" ist hotspots oder coupling');
  end;
  mFormat := HotspotFormatOf(AArguments);
  mLimit := HotspotLimitOf(AArguments);
  mRequest := HotspotRequestOf(AContext, mSettings, AArguments);
  // Ohne Versionsverwaltung ein Hinweis statt einer leeren Liste.
  if not TShellHotspotVcs.Detect(AContext.Root, mSettings, mVcs, mError) then
  begin
    Exit('Keine Hotspots: ' + mError + '. Hotspots brauchen ein Git-Repository oder eine SVN-Arbeitskopie.');
  end;
  try
    mResult := AContext.Hotspots.Analyze(mRequest, mVcs);
  except
    on E: EHotspots do
      raise EMcpToolError.Create(E.Message);
  end;
  Result := HotspotText(mResult, mFormat, mSection, mLimit);
end;

procedure AddGetHotspots(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool('get_hotspots',
    'Hotspots (#1354): Units bzw. Methoden, die im Zeitraum oft geändert wurden und zugleich komplex sind ' +
    '(Wert = normierte Änderungen × normierte kognitive Komplexität), mit Änderungen, Autoren, Zeilen, Trend ' +
    'der Komplexität und letzter Änderung aus Git bzw. SVN (vcs.provider). Mit section "coupling" die ' +
    'Änderungskopplung: Dateien, die fast immer zusammen geändert werden, ohne uses-Kante zwischen ihnen. ' +
    'Zeitraum und Mindestzahl gemeinsamer Commits aus hotspots.* in atlas.json. Lesend.',
    '{"type":"object","properties":{' +
      '"level":{"type":"string","enum":["unit","method"],"description":"Ebene; Vorgabe unit"},' +
      '"limit":{"type":"integer","minimum":1,"description":"Länge der Liste; Vorgabe 20"},' +
      '"months":{"type":"integer","minimum":1,"maximum":60,"description":"Zeitraum in Monaten; Vorgabe ' +
        'hotspots.months (12)"},' +
      '"section":{"type":"string","enum":["hotspots","coupling"],"description":"Abschnitt; Vorgabe hotspots"},' +
      '"format":{"type":"string","enum":["text","markdown","json"],"description":"text (Vorgabe), markdown ' +
        'oder json"}}}',
    ContextTool(AContext, ToolGetHotspots));
end;


/// <summary>get_hotspots (#1354): derselbe Dienst wie atlas/hotspots und --hotspots.</summary>
procedure RegisterHotspotTools(const AContext: TMcpToolContext);
begin
  AddGetHotspots(AContext);
end;

end.
