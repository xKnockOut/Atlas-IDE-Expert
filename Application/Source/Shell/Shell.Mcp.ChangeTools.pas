unit Shell.Mcp.ChangeTools;

// Host-Rolle Shell: MCP-Modus (--mcp, #48), Werkzeuge rund um Änderungen: betroffene Tests (#1353),
// Hotspots aus Änderungshäufigkeit (#1354).

interface

uses
  System.SysUtils,
  Atlas.Common.Mcp.Paths,
  Shell.Mcp.Context;

/// <summary>get_affected_tests (#1353): betroffene Tests der Änderungen gegenüber einer Basis; das Ergebnis im
/// Format json passt mit "run" direkt in run_tests.tests.</summary>
procedure RegisterAffectedTestsTool(const AContext: TMcpToolContext);
/// <summary>get_hotspots (#1354): derselbe Dienst wie atlas/hotspots und --hotspots.</summary>
procedure RegisterHotspotTools(const AContext: TMcpToolContext);

implementation

uses
  Shell.WorkspaceGroup,
  Atlas.Common.Mcp.Server,
  Atlas.Common.Hotspots.Service,
  System.JSON,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Lsp.References,
  Atlas.Common.Lsp.AffectedTests.Report,
  Atlas.Common.Lsp.AffectedTests.Contract,
  Atlas.Common.Semantics.NameResolver,
  Shell.VersionControlChanges,
  Atlas.Common.Compiler.Contract,
  Atlas.Common.Hotspots.Contract,
  Atlas.Common.Hotspots.Analysis,
  Atlas.Common.Hotspots.Report,
  Atlas.Common.Lsp.Hotspots,
  Shell.Platform,
  Shell.Bootstrap,
  Shell.AffectedTests,
  Shell.Hotspots,
  Atlas.Common.Localization.Texts,
  Shell.Texts;

type
{$SCOPEDENUMS ON}
  TMcpChangeText = (GetAffectedTestsTool, GetAffectedTestsBase, GetAffectedTestsIncludeUncommitted,
    GetAffectedTestsDepth, GetAffectedTestsFormat, GetHotspotsTool, GetHotspotsLevel, GetHotspotsLimit,
    GetHotspotsMonths, GetHotspotsSection, GetHotspotsFormat, AllNeeded, NoneAffected, LimitInvalid, HotspotsOff,
    NoHotspots);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TMcpChangeText] of TAtlasText = (
    (De: 'Betroffene Tests einer Änderung (#1353): aus dem Unterschied zur Basis (Git oder SVN wie --changed) die ' +
    'geänderten Routinen, Typen und Konstanten bestimmen, ihre Auswirkungen bis zur Tiefe verfolgen (wie ' +
    'get_impact) und die DUnitX-Testmethoden nennen, die sie erreichen, je mit Grund. Sind mehr als 80 % ' +
    'einer Fixture betroffen, die ganze Fixture. "run" im Format json passt direkt in run_tests.tests; "all" ' +
    'heißt, dass alle Tests nötig sind (Grund in "reason").';
    En: 'Affected tests of a change (#1353): from the difference to the base (Git or SVN like --changed) ' +
    'determine the changed routines, types and constants, follow their impact up to the depth (like ' +
    'get_impact) and name the DUnitX test methods that reach them, each with a reason. If more than 80 % of ' +
    'a fixture is affected, the whole fixture. "run" in format json fits directly into run_tests.tests; ' +
    '"all" means that all tests are needed (reason in "reason").'),
    (De: 'Git-Ref (Merge-Base mit HEAD) bzw. SVN-Revision; leer = main bzw. BASE';
    En: 'Git ref (merge base with HEAD) or SVN revision; empty = main or BASE'),
    (De: 'Index, Arbeitsverzeichnis und neue Dateien mitzählen'; En: 'Count the index, working tree and new files'),
    (De: 'Ebenen; leer = tests.affectedDepth'; En: 'Levels; empty = tests.affectedDepth'),
    (De: 'text (Vorgabe), json oder dunitx (Argument --run:… für die Test-EXE)';
    En: 'text (default), json or dunitx (argument --run:… for the test EXE)'),
    (De: 'Hotspots (#1354): Units bzw. Methoden, die im Zeitraum oft geändert wurden und zugleich komplex sind ' +
    '(Wert = normierte Änderungen × normierte kognitive Komplexität), mit Änderungen, Autoren, Zeilen, Trend ' +
    'der Komplexität und letzter Änderung aus Git bzw. SVN (vcs.provider). Mit section "coupling" die ' +
    'Änderungskopplung: Dateien, die fast immer zusammen geändert werden, ohne uses-Kante zwischen ihnen. ' +
    'Zeitraum und Mindestzahl gemeinsamer Commits aus hotspots.* in atlas.json. Lesend.';
    En: 'Hotspots (#1354): units or methods that changed often in the period and are complex at the same time ' +
    '(score = normalized changes × normalized cognitive complexity), with changes, authors, lines, ' +
    'complexity trend and last change from Git or SVN (vcs.provider). With section "coupling" the change ' +
    'coupling: files that are almost always changed together without a uses edge between them. Period and ' +
    'minimum number of shared commits from hotspots.* in atlas.json. Read-only.'),
    (De: 'Ebene; Vorgabe unit'; En: 'Level; default unit'),
    (De: 'Länge der Liste; Vorgabe 20'; En: 'Length of the list; default 20'),
    (De: 'Zeitraum in Monaten; Vorgabe hotspots.months (12)'; En: 'Period in months; default hotspots.months (12)'),
    (De: 'Abschnitt; Vorgabe hotspots'; En: 'Section; default hotspots'),
    (De: 'text (Vorgabe), markdown oder json'; En: 'text (default), markdown or json'),
    (De: 'Alle Tests nötig: %s'; En: 'All tests needed: %s'),
    (De: 'Keine betroffenen Tests gegenüber %s.'; En: 'No affected tests compared with %s.'),
    (De: '"limit" ist eine ganze Zahl ab 1'; En: '"limit" is a whole number from 1'),
    (De: 'Hotspots sind ausgeschaltet (hotspots.enabled)'; En: 'Hotspots are turned off (hotspots.enabled)'),
    (De: 'Keine Hotspots: %s. Hotspots brauchen ein Git-Repository oder eine SVN-Arbeitskopie.';
    En: 'No hotspots: %s. Hotspots need a Git repository or an SVN working copy.'));

/// <summary>Basis, includeUncommitted (Vorgabe True) und Tiefe aus den Argumenten von get_affected_tests.</summary>
function AffectedQueryOf(const ARoot: string; const AArguments: TJSONObject): TShellAffectedQuery;
begin
  Result := Default(TShellAffectedQuery);
  Result.WorkingDir := ARoot;
  Result.Base := TMcpArgs.OptionalString(AArguments, 'base');
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
    Result := cTexts[TMcpChangeText.AllNeeded].Fmt([AFound.AllReason]);
  end
  else if Length(AFound.Tests) = 0 then
  begin
    Result := cTexts[TMcpChangeText.NoneAffected].Fmt([AFound.Base]);
  end
  else if not TAffectedReport.DUnitXArgument(AFound, Result) then
  begin
    Result := cTexts[TMcpChangeText.AllNeeded].Fmt([TShellAffectedTests.TooManyForRun]);
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
  if not TAffectedReport.TryParseFormat(TMcpArgs.OptionalString(AArguments, 'format'), mFormat) then
  begin
    raise EMcpToolError.Create(TShellTexts.Choice('format', ['text', 'json', 'dunitx']));
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
    Result := TAffectedReport.Render(mFound, mFormat);
  end;
end;

procedure AddGetAffectedTests(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool('get_affected_tests', cTexts[TMcpChangeText.GetAffectedTestsTool].Text,
    SchemaWith('{"type":"object","properties":{' +
      '"base":{"type":"string","description":%s},' +
      '"includeUncommitted":{"type":"boolean","default":true,"description":%s},' +
      '"depth":{"type":"integer","minimum":1,"maximum":5,"description":%s},' +
      '"format":{"type":"string","enum":["text","json","dunitx"],"description":%s}}}',
      [cTexts[TMcpChangeText.GetAffectedTestsBase].Text,
      cTexts[TMcpChangeText.GetAffectedTestsIncludeUncommitted].Text,
      cTexts[TMcpChangeText.GetAffectedTestsDepth].Text,
      cTexts[TMcpChangeText.GetAffectedTestsFormat].Text]),
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
  Result := TMcpArgs.OptionalString(AArguments, 'format');
  if (Result <> '') and not SameText(Result, 'text') and not SameText(Result, 'markdown') and
    not SameText(Result, 'json') then
  begin
    raise EMcpToolError.Create(TShellTexts.Choice('format', ['text', 'markdown', 'json']));
  end;
end;

/// <summary>Höchstzahl der Einträge aus limit (Vorgabe THotspotReport.cTextLimit).</summary>
function HotspotLimitOf(const AArguments: TJSONObject): Integer;
begin
  if not AArguments.TryGetValue<Integer>('limit', Result) then
  begin
    Result := THotspotReport.cTextLimit;
  end;
  if Result < 1 then
  begin
    raise EMcpToolError.Create(cTexts[TMcpChangeText.LimitInvalid].Text);
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
    raise EMcpToolError.Create(TShellTexts.NoProject);
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
    raise EMcpToolError.Create(cTexts[TMcpChangeText.HotspotsOff].Text);
  end;
  if not THotspotReport.ParseSection(TMcpArgs.OptionalString(AArguments, 'section'), mSection) then
  begin
    raise EMcpToolError.Create(TShellTexts.Choice('section', ['hotspots', 'coupling']));
  end;
  mFormat := HotspotFormatOf(AArguments);
  mLimit := HotspotLimitOf(AArguments);
  mRequest := HotspotRequestOf(AContext, mSettings, AArguments);
  // Ohne Versionsverwaltung ein Hinweis statt einer leeren Liste.
  if not TShellHotspotVcs.Detect(AContext.Root, mSettings, mVcs, mError) then
  begin
    Exit(cTexts[TMcpChangeText.NoHotspots].Fmt([mError]));
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
  AContext.Server.AddTool('get_hotspots', cTexts[TMcpChangeText.GetHotspotsTool].Text,
    SchemaWith('{"type":"object","properties":{' +
      '"level":{"type":"string","enum":["unit","method"],"description":%s},' +
      '"limit":{"type":"integer","minimum":1,"description":%s},' +
      '"months":{"type":"integer","minimum":1,"maximum":60,"description":%s},' +
      '"section":{"type":"string","enum":["hotspots","coupling"],"description":%s},' +
      '"format":{"type":"string","enum":["text","markdown","json"],"description":%s}}}',
      [cTexts[TMcpChangeText.GetHotspotsLevel].Text,
      cTexts[TMcpChangeText.GetHotspotsLimit].Text,
      cTexts[TMcpChangeText.GetHotspotsMonths].Text,
      cTexts[TMcpChangeText.GetHotspotsSection].Text,
      cTexts[TMcpChangeText.GetHotspotsFormat].Text]),
    ContextTool(AContext, ToolGetHotspots));
end;


/// <summary>get_hotspots (#1354): derselbe Dienst wie atlas/hotspots und --hotspots.</summary>
procedure RegisterHotspotTools(const AContext: TMcpToolContext);
begin
  AddGetHotspots(AContext);
end;

initialization
  TAtlasTextTables.Add('Shell.Mcp.ChangeTools', cTexts);

end.
