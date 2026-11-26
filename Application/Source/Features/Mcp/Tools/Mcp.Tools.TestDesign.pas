unit Mcp.Tools.TestDesign;

// Host-Rolle Core: MCP-Modus (--mcp, #48), Mutanten einer Unit (get_mutants, #1460) und Grenzfälle einer Routine als
// Testfälle (suggest_test_cases, #2173).

interface

uses
  Mcp.Tools.Context;

/// <summary>Meldet get_mutants an.</summary>
procedure AddGetMutants(const AContext: TMcpToolContext);
/// <summary>Meldet suggest_test_cases an.</summary>
procedure AddSuggestTestCases(const AContext: TMcpToolContext);

implementation

uses
  System.SysUtils,
  // Inline-Funktionen von TJSONArray (H2443).
  System.Generics.Collections,
  System.IOUtils,
  System.JSON,
  Mcp.Server,
  Atlas.Text.Json,
  Atlas.Common.Mutation.Contract,
  Atlas.Common.Mutation.Report,
  Mcp.Contract.BoundaryCases,
  Atlas.Common.Localization.RequestTexts,
  Atlas.Common.Localization.Texts;

type
{$SCOPEDENUMS ON}
  TMcpTestDesignText = (GetMutantsTool, GetMutantsFile, GetMutantsRoutine, GetMutantsOperators, GetMutantsFirstLine,
    GetMutantsLastLine, GetMutantsFormat, UnknownOperators, SourceUnreadable, SuggestTool, SuggestFile,
    SuggestRoutine, SuggestLine, SuggestMax, SuggestFormat, SuggestNoRoutine);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TMcpTestDesignText] of TAtlasText = (
    (De: 'Mutanten einer Unit für Mutationstests (#1460): kleine Fehler, die die DUnitX-Tests bemerken sollten ' +
    '(Vergleich < und <=, = und <>, and und or, not entfernen, + und -, +1 entfernen, True und False, 0 und 1, ' +
    'Anweisung entfernen, Exit(x) durch Exit(Default(Typ))). Erzeugt aus dem Syntaxbaum, nur in aktiven Zweigen, ' +
    'ohne Assert, Protokollaufrufe und Zeilen mit // atlas-ignore: mutation. Baut und testet nicht: Je Mutant ' +
    'die Datei ändern, das Testprojekt bauen (build_project) und die Tests laufen lassen (run_tests); bleiben alle ' +
    'grün, fehlt an der Stelle ein Test. Dieselben Mutanten wie --mutate.';
    En: 'Mutants of a unit for mutation testing (#1460): small faults the DUnitX tests should notice (comparison ' +
    '< and <=, = and <>, and and or, remove not, + and -, remove +1, True and False, 0 and 1, remove statement, ' +
    'Exit(x) by Exit(Default(Type))). Generated from the syntax tree, only in active branches, without Assert, ' +
    'logging calls and lines with // atlas-ignore: mutation. Does not build or test: for each mutant change the ' +
    'file, build the test project (build_project) and run the tests (run_tests); if all stay green, a test is ' +
    'missing at that place. The same mutants as --mutate.'),
    (De: 'Pfad der Unit (relativ zum Projekt oder absolut)';
    En: 'Path of the unit (relative to the project or absolute)'),
    (De: 'Nur diese Routine: "TFoo.Bar" oder "Bar"; leer = alle'; En: 'Only this routine: "TFoo.Bar" or "Bar"; ' +
    'empty = all'),
    (De: 'Nur diese Operatoren: boundary, equality, logical, not, arithmetic, increment, boolean, number, ' +
    'statement, exit; leer = alle';
    En: 'Only these operators: boundary, equality, logical, not, arithmetic, increment, boolean, number, ' +
    'statement, exit; empty = all'),
    (De: 'Nur Stellen ab dieser Zeile (ab 1)'; En: 'Only places from this line on (from 1)'),
    (De: 'Nur Stellen bis zu dieser Zeile'; En: 'Only places up to this line'),
    (De: 'markdown (Vorgabe), json (mit Offsets für eigene Änderungen) oder diff (je Mutant ein Patch)';
    En: 'markdown (default), json (with offsets for own changes) or diff (one patch per mutant)'),
    (De: 'Unbekannte Operatoren: %s'; En: 'Unknown operators: %s'),
    (De: '%s ist nicht lesbar'; En: '%s is not readable'),
    (De: 'Grenzfälle einer Routine als Testfälle (#2173): aus den Bedingungen über ihre Parameter (Vergleich mit ' +
    'einer Konstanten, case-Marken, in [...], SameText/StartsText/Pos, Length, nil, Boolean) je Bedingung Werte ' +
    'knapp davor, darauf und dahinter, mit Grund und Zeile; je Fall weicht ein Parameter ab, die übrigen stehen ' +
    'auf einem neutralen Wert. Werte in der Schreibweise von DUnitX-[TestCase]; nil-Fälle passen in kein ' +
    '[TestCase]. Felder und Funktionsaufrufe liefern nichts. Lesend; erzeugt keinen Test.';
    En: 'Boundary cases of a routine as test cases (#2173): from the conditions on its parameters (comparison ' +
    'with a constant, case labels, in [...], SameText/StartsText/Pos, Length, nil, Boolean) values just before, ' +
    'on and after each condition, with reason and line; in each case one parameter deviates, the others stay ' +
    'on a neutral value. Values in DUnitX [TestCase] notation; nil cases fit no [TestCase]. Fields and ' +
    'function calls yield nothing. Read-only; creates no test.'),
    (De: 'Pfad der Unit (relativ zum Projekt oder absolut)';
    En: 'Path of the unit (relative to the project or absolute)'),
    (De: 'Routine: "TFoo.Bar" oder "Bar"; statt line'; En: 'Routine: "TFoo.Bar" or "Bar"; instead of line'),
    (De: 'Zeile (ab 1) irgendwo in der Routine; statt routine'; En: 'Line (from 1) anywhere in the routine; ' +
    'instead of routine'),
    (De: 'Höchstens so viele Fälle; Vorgabe 20, 1 bis 200'; En: 'At most this many cases; default 20, 1 to 200'),
    (De: 'markdown (Vorgabe) oder json'; En: 'markdown (default) or json'),
    (De: 'Keine Routine mit Rumpf in %s (routine oder line angeben)';
    En: 'No routine with a body in %s (give routine or line)'));

/// <summary>Kennungen aus "operators": Liste oder Text mit Kommas; nil = alle.</summary>
function OperatorIdsOf(const AArguments: TJSONObject): TArray<string>;
begin
  Result := nil;
  if AArguments = nil then
  begin
    Exit;
  end;
  if AArguments.GetValue('operators') is TJSONArray then
  begin
    Result := TJsonRead.Strings(AArguments, 'operators');
  end
  else
  begin
    Result := TMcpArgs.OptionalString(AArguments, 'operators').Split([',', ';']);
  end;
end;

/// <summary>Zeile ab 1 aus AName als Zeile ab 0; -1 ohne Angabe.</summary>
function LineOf(const AArguments: TJSONObject; const AName: string): Integer;
begin
  Result := TJsonRead.Int(AArguments, AName);
  if Result > 0 then
  begin
    Dec(Result);
  end
  else
  begin
    Result := -1;
  end;
end;

function ToolGetMutants(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
var
  mFileName, mText: string;
  mFormat: TMutationOutputFormat;
  mOptions: TMutationOptions;
  mIds, mUnknown: TArray<string>;
begin
  mFileName := AContext.Guard.Resolve(TMcpArgs.RequiredString(AArguments, 'file'));
  if not TMutationReport.TryParseFormat(TMcpArgs.OptionalString(AArguments, 'format'), mFormat) then
  begin
    raise EMcpToolError.Create(TRequestTexts.Choice('format', ['markdown', 'json', 'diff']));
  end;
  mOptions := TMutationOptions.Default;
  mOptions.Routine := Trim(TMcpArgs.OptionalString(AArguments, 'routine'));
  mOptions.FirstLine := LineOf(AArguments, 'firstLine');
  mOptions.LastLine := LineOf(AArguments, 'lastLine');
  mIds := OperatorIdsOf(AArguments);
  if Length(mIds) > 0 then
  begin
    mOptions.Operators := TMutation.ParseOperators(mIds, mUnknown);
    if Length(mUnknown) > 0 then
    begin
      raise EMcpToolError.Create(cTexts[TMcpTestDesignText.UnknownOperators].Fmt([string.Join(', ', mUnknown)]));
    end;
  end;
  if not ReadSourceText(mFileName, mText) then
  begin
    raise EMcpToolError.Create(cTexts[TMcpTestDesignText.SourceUnreadable].Fmt([mFileName]));
  end;
  // Aktive Zweige wie beim Prüfen: Symbole des Projekts, zu dem die Datei gehört.
  mOptions.Defines := AContext.CheckSource(mFileName).Defines;
  Result := TMutationReport.Render(ExtractRelativePath(IncludeTrailingPathDelimiter(AContext.Root), mFileName)
    .Replace('\', '/'), mText, mOptions, mFormat);
end;

procedure AddGetMutants(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool('get_mutants', cTexts[TMcpTestDesignText.GetMutantsTool].Text,
    SchemaWith('{"type":"object","properties":{' +
      '"file":{"type":"string","description":%s},' +
      '"routine":{"type":"string","description":%s},' +
      '"operators":{"type":"array","items":{"type":"string","enum":["boundary","equality","logical","not",' +
      '"arithmetic","increment","boolean","number","statement","exit"]},"description":%s},' +
      '"firstLine":{"type":"integer","minimum":1,"description":%s},' +
      '"lastLine":{"type":"integer","minimum":1,"description":%s},' +
      '"format":{"type":"string","enum":["markdown","json","diff"],"description":%s}},"required":["file"]}',
      [cTexts[TMcpTestDesignText.GetMutantsFile].Text,
      cTexts[TMcpTestDesignText.GetMutantsRoutine].Text,
      cTexts[TMcpTestDesignText.GetMutantsOperators].Text,
      cTexts[TMcpTestDesignText.GetMutantsFirstLine].Text,
      cTexts[TMcpTestDesignText.GetMutantsLastLine].Text,
      cTexts[TMcpTestDesignText.GetMutantsFormat].Text]),
    ContextTool(AContext, ToolGetMutants));
end;

function ToolSuggestTestCases(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
var
  mFileName, mText, mFormat: string;
  mRequest: TMcpBoundaryRequest;
begin
  mFileName := AContext.Guard.Resolve(TMcpArgs.RequiredString(AArguments, 'file'));
  mFormat := LowerCase(Trim(TMcpArgs.OptionalString(AArguments, 'format')));
  if (mFormat <> '') and (mFormat <> 'markdown') and (mFormat <> 'json') then
  begin
    raise EMcpToolError.Create(TRequestTexts.Choice('format', ['markdown', 'json']));
  end;
  if not ReadSourceText(mFileName, mText) then
  begin
    raise EMcpToolError.Create(cTexts[TMcpTestDesignText.SourceUnreadable].Fmt([mFileName]));
  end;
  mRequest := Default(TMcpBoundaryRequest);
  if not AArguments.TryGetValue<Integer>('maxCases', mRequest.Max) then
  begin
    mRequest.Max := 0;
  end;
  mRequest.FileName := ExtractRelativePath(IncludeTrailingPathDelimiter(AContext.Root), mFileName)
    .Replace('\', '/');
  mRequest.Line := LineOf(AArguments, 'line');
  mRequest.Routine := TMcpArgs.OptionalString(AArguments, 'routine');
  mRequest.Json := mFormat = 'json';
  if not AContext.Adapters.BoundaryCases.Report(mText, mRequest, Result) then
  begin
    raise EMcpToolError.Create(cTexts[TMcpTestDesignText.SuggestNoRoutine].Fmt([mRequest.FileName]));
  end;
end;

procedure AddSuggestTestCases(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool('suggest_test_cases', cTexts[TMcpTestDesignText.SuggestTool].Text,
    SchemaWith('{"type":"object","properties":{' +
      '"file":{"type":"string","description":%s},' +
      '"routine":{"type":"string","description":%s},' +
      '"line":{"type":"integer","minimum":1,"description":%s},' +
      '"maxCases":{"type":"integer","minimum":1,"maximum":200,"description":%s},' +
      '"format":{"type":"string","enum":["markdown","json"],"description":%s}},"required":["file"]}',
      [cTexts[TMcpTestDesignText.SuggestFile].Text,
      cTexts[TMcpTestDesignText.SuggestRoutine].Text,
      cTexts[TMcpTestDesignText.SuggestLine].Text,
      cTexts[TMcpTestDesignText.SuggestMax].Text,
      cTexts[TMcpTestDesignText.SuggestFormat].Text]),
    ContextTool(AContext, ToolSuggestTestCases));
end;

initialization
  TAtlasTextTables.Add('Mcp.Tools.TestDesign', cTexts);

end.
