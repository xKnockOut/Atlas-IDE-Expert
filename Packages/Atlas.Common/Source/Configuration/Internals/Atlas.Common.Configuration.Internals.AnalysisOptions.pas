unit Atlas.Common.Configuration.Internals.AnalysisOptions;

// Abschnitte von atlas.json zur Analyse: index, architecture (mit grouping),
// query, ruleChecks, queries (gespeicherte Abfragen) und hotspots.

interface

uses
  Atlas.Common.Configuration.Internals.Reader;

/// <summary>Abschnitte dieser Unit.</summary>
function AnalysisSections: TArray<TConfigurationSection>;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Internals.JsonTree,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TAnalysisOptionsText = (IndexCacheMaxAgeDaysMustBeA, IndexCacheMaxMbMustBeA, IndexExcludeMustBeA,
    ArchitectureGroupingMustBeA, ArchitectureGroupingFoundationsMustBe, ArchitectureScopeMustBeProject,
    ArchitectureCentralUnitsMustBeA, ArchitectureExcludeMustBeA, ArchitectureFailOnMustBeA, TheNameOfAQuery,
    UnknownEntryInASaved, ASavedQueryMustBe, ASavedQueryNeedsName, QueriesMustBeAList, QueryAppearsTwiceTheFirst,
    HotspotsMonthsMustBeA, HotspotsCouplingMinCommitsMustBe, ArchitectureFailOnUnknownDeviationAllowed,
    UnknownSeverityAllowedOffHint, QueryNeedsQuery, RangeResolution, RangeMaxShare, RangeMinCohesion);

const
  cTexts: array[TAnalysisOptionsText] of TAtlasText = (
    (De: '"index.cacheMaxAgeDays" muss eine ganze Zahl von 0 bis 3650 sein';
     En: '"index.cacheMaxAgeDays" must be a whole number from 0 to 3650'),
    (De: '"index.cacheMaxMb" muss eine ganze Zahl von 0 bis 1048576 sein';
     En: '"index.cacheMaxMb" must be a whole number from 0 to 1048576'),
    (De: '"index.exclude" muss eine Liste von Mustern sein'; En: '"index.exclude" must be a list of patterns'),
    (De: '"architecture.grouping.%s" muss eine Zahl von %s sein';
     En: '"architecture.grouping.%s" must be a number from %s'),
    (De: '"architecture.grouping.foundations" muss "group", "attach" oder "separate" sein';
     En: '"architecture.grouping.foundations" must be "group", "attach" or "separate"'),
    (De: '"architecture.scope" muss "project" oder "projectGroup" sein';
     En: '"architecture.scope" must be "project" or "projectGroup"'),
    (De: '"architecture.centralUnits" muss eine ganze Zahl von 5 bis 100 sein';
     En: '"architecture.centralUnits" must be a whole number from 5 to 100'),
    (De: '"architecture.exclude" muss eine Liste von Mustern sein';
     En: '"architecture.exclude" must be a list of patterns'),
    (De: '"architecture.failOn" muss eine Liste aus newCycle, newCrossLink, subsystemChange und centralGrowth sein';
     En: '"architecture.failOn" must be a list of newCycle, newCrossLink, subsystemChange and centralGrowth'),
    (De: 'Der Name einer Abfrage besteht aus Buchstaben, Ziffern, "-", "_" und "."';
     En: 'The name of a query consists of letters, digits, "-", "_" and "."'),
    (De: 'Unbekannte Angabe "%s" in einer gespeicherten Abfrage'; En: 'Unknown entry "%s" in a saved query'),
    (De: 'Eine gespeicherte Abfrage muss ein Objekt sein: { "name": …, "query": … }';
     En: 'A saved query must be an object: { "name": …, "query": … }'),
    (De: 'Eine gespeicherte Abfrage braucht "name"'; En: 'A saved query needs "name"'),
    (De: '"queries" muss eine Liste von Abfragen sein'; En: '"queries" must be a list of queries'),
    (De: 'Abfrage "%s" ist doppelt; es gilt die erste'; En: 'Query "%s" appears twice; the first one applies'),
    (De: '"hotspots.months" muss eine ganze Zahl von 1 bis 60 sein';
     En: '"hotspots.months" must be a whole number from 1 to 60'),
    (De: '"hotspots.coupling.minCommits" muss eine ganze Zahl von 2 bis 1000 sein';
     En: '"hotspots.coupling.minCommits" must be a whole number from 2 to 1000'),
    (De: '"architecture.failOn": unbekannte Abweichung "%s" (erlaubt: newCycle, newCrossLink, subsystemChange, ' +
      'centralGrowth)';
     En: '"architecture.failOn": unknown deviation "%s" (allowed: newCycle, newCrossLink, subsystemChange, ' +
      'centralGrowth)'),
    (De: 'Unbekannter Schweregrad "%s"; erlaubt: off, hint, info, warning, error';
     En: 'Unknown severity "%s"; allowed: off, hint, info, warning, error'),
    (De: 'Abfrage "%s" braucht "query"'; En: 'Query "%s" needs "query"'),
    (De: '0,2 bis 5,0'; En: '0.2 to 5.0'),
    (De: '0 bis 0,9'; En: '0 to 0.9'),
    (De: '0 bis 1'; En: '0 to 1'));

{$SCOPEDENUMS OFF}

{ index }

procedure ReadCacheMaxAge(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
begin
  AReader.ExpectInteger(AValue, 0, 3650, cTexts[TAnalysisOptionsText.IndexCacheMaxAgeDaysMustBeA].Text,
    ASettings.IndexCacheMaxAgeDays);
end;

procedure ReadCacheMaxMb(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
begin
  AReader.ExpectInteger(AValue, 0, 1048576, cTexts[TAnalysisOptionsText.IndexCacheMaxMbMustBeA].Text,
    ASettings.IndexCacheMaxMb);
end;

procedure ReadIndexExclude(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
var
  mItems: TArray<string>;
begin
  if AReader.ExpectStrings(AValue, 'index.exclude', cTexts[TAnalysisOptionsText.IndexExcludeMustBeA].Text, mItems) then
  begin
    ASettings.IndexExclude := mItems;
  end;
end;

const
  cIndexMembers: array[0..2] of TMemberOption = ((Key: 'cacheMaxAgeDays'; Read: ReadCacheMaxAge),
    (Key: 'cacheMaxMb'; Read: ReadCacheMaxMb), (Key: 'exclude'; Read: ReadIndexExclude));

procedure ReadIndex(AReader: TConfigurationReader; ANode: TJsonNode; var ASettings: TServerSettings);
begin
  AReader.ReadObject(ANode, 'index', [TFlagOption.Create('projectGroup', ASettings.IndexProjectGroup),
    TFlagOption.Create('searchPaths', ASettings.IndexSearchPaths),
    TFlagOption.Create('libraryPaths', ASettings.IndexLibraryPaths),
    TFlagOption.Create('usages', ASettings.IndexUsages),
    TFlagOption.Create('removeOrphans', ASettings.IndexRemoveOrphans)], cIndexMembers, ASettings);
end;

procedure TakeIndex(const ASource: TServerSettings; const AFileText: string; var ATarget: TServerSettings);
begin
  ATarget.IndexProjectGroup := ASource.IndexProjectGroup;
  ATarget.IndexSearchPaths := ASource.IndexSearchPaths;
  ATarget.IndexLibraryPaths := ASource.IndexLibraryPaths;
  ATarget.IndexUsages := ASource.IndexUsages;
  ATarget.IndexExclude := ASource.IndexExclude;
  ATarget.IndexRemoveOrphans := ASource.IndexRemoveOrphans;
  ATarget.IndexCacheMaxAgeDays := ASource.IndexCacheMaxAgeDays;
  ATarget.IndexCacheMaxMb := ASource.IndexCacheMaxMb;
end;

{ architecture.grouping }

type
  /// <summary>Bereich einer Zahl von architecture.grouping; Meldungstext ("0,2 bis 5,0") je Sprache.</summary>
  TFractionRange = record
    Min: Double;
    Max: Double;
    Text: TAnalysisOptionsText;
  end;

const
  cResolutionRange: TFractionRange = (Min: 0.2; Max: 5; Text: TAnalysisOptionsText.RangeResolution);
  cMaxShareRange: TFractionRange = (Min: 0; Max: 0.9; Text: TAnalysisOptionsText.RangeMaxShare);
  cMinCohesionRange: TFractionRange = (Min: 0; Max: 1; Text: TAnalysisOptionsText.RangeMinCohesion);

/// <summary>Zahl im Bereich ARange; sonst Fehler.</summary>
procedure ReadFraction(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  const ARange: TFractionRange; var ANumber: Double);
var
  mNumber: Double;
begin
  if (AValue.Kind = TJsonKind.Number) and TryStrToFloat(AValue.Value, mNumber, TFormatSettings.Invariant) and
    (mNumber >= ARange.Min) and (mNumber <= ARange.Max) then
  begin
    ANumber := mNumber;
  end
  else
  begin
    AReader.ReportNode(AValue, cTexts[TAnalysisOptionsText.ArchitectureGroupingMustBeA].Fmt([AKey,
      cTexts[ARange.Text].Text]));
  end;
end;

procedure ReadResolution(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
begin
  ReadFraction(AReader, AValue, AKey, cResolutionRange, ASettings.ArchitectureGroupingResolution);
end;

procedure ReadMaxShare(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
begin
  ReadFraction(AReader, AValue, AKey, cMaxShareRange, ASettings.ArchitectureGroupingMaxShare);
end;

procedure ReadMinCohesion(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
begin
  ReadFraction(AReader, AValue, AKey, cMinCohesionRange, ASettings.ArchitectureGroupingMinCohesion);
end;

procedure ReadFoundations(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
var
  mIndex: Integer;
begin
  if AReader.ExpectOneOf(AValue, ['group', 'attach', 'separate'],
    cTexts[TAnalysisOptionsText.ArchitectureGroupingFoundationsMustBe].Text, mIndex) then
  begin
    ASettings.ArchitectureGroupingFoundations := AValue.Value;
  end;
end;

const
  cGroupingMembers: array[0..3] of TMemberOption = ((Key: 'resolution'; Read: ReadResolution),
    (Key: 'maxShare'; Read: ReadMaxShare), (Key: 'minCohesion'; Read: ReadMinCohesion),
    (Key: 'foundations'; Read: ReadFoundations));

/// <summary>architecture.grouping: Gruppierung der Teilsysteme (#1366, #1364, #1365, #1367).</summary>
procedure ReadGrouping(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
begin
  AReader.ReadObject(AValue, 'architecture.grouping', [TFlagOption.Create('showResolutionSlider',
    ASettings.ArchitectureGroupingShowResolutionSlider), TFlagOption.Create('keepPrevious',
    ASettings.ArchitectureGroupingKeepPrevious)], cGroupingMembers, ASettings);
end;

{ architecture }

procedure ReadScope(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
var
  mIndex: Integer;
begin
  if AReader.ExpectOneOf(AValue, ['project', 'projectGroup'],
    cTexts[TAnalysisOptionsText.ArchitectureScopeMustBeProject].Text, mIndex) then
  begin
    ASettings.ArchitectureScope := AValue.Value;
  end;
end;

procedure ReadCentralUnits(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
begin
  AReader.ExpectInteger(AValue, 5, 100, cTexts[TAnalysisOptionsText.ArchitectureCentralUnitsMustBeA].Text,
    ASettings.ArchitectureCentralUnits);
end;

procedure ReadArchitectureExclude(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
var
  mItems: TArray<string>;
begin
  if AReader.ExpectStrings(AValue, 'architecture.exclude', cTexts[TAnalysisOptionsText.ArchitectureExcludeMustBeA].Text,
    mItems) then
  begin
    ASettings.ArchitectureExclude := mItems;
  end;
end;

procedure ReadBaseline(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
var
  mText: string;
begin
  if AReader.ExpectString(AValue, 'architecture.baseline', mText) then
  begin
    ASettings.ArchitectureBaseline := Trim(mText);
  end;
end;

procedure ReadFailOn(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
const
  cDeviations: array[0..3] of string = ('newCycle', 'newCrossLink', 'subsystemChange', 'centralGrowth');
var
  mItem: Integer;
  mText: string;
begin
  if AValue.Kind <> TJsonKind.Array_ then
  begin
    AReader.ReportNode(AValue, cTexts[TAnalysisOptionsText.ArchitectureFailOnMustBeA].Text);
    Exit;
  end;
  ASettings.ArchitectureFailOn := nil;
  for mItem := 0 to AValue.Count - 1 do
  begin
    if not AReader.ExpectString(AValue[mItem], 'architecture.failOn', mText) then
    begin
      Continue;
    end;
    if IndexStr(mText, cDeviations) >= 0 then
    begin
      ASettings.ArchitectureFailOn := ASettings.ArchitectureFailOn + [mText];
    end
    else
    begin
      AReader.ReportNode(AValue[mItem], cTexts[TAnalysisOptionsText.ArchitectureFailOnUnknownDeviationAllowed].Fmt([
        mText]));
    end;
  end;
end;

const
  cArchitectureMembers: array[0..5] of TMemberOption = ((Key: 'scope'; Read: ReadScope),
    (Key: 'centralUnits'; Read: ReadCentralUnits), (Key: 'exclude'; Read: ReadArchitectureExclude),
    (Key: 'baseline'; Read: ReadBaseline), (Key: 'failOn'; Read: ReadFailOn), (Key: 'grouping'; Read: ReadGrouping));

procedure ReadArchitecture(AReader: TConfigurationReader; ANode: TJsonNode; var ASettings: TServerSettings);
begin
  AReader.ReadObject(ANode, 'architecture', [TFlagOption.Create('enabled', ASettings.ArchitectureEnabled),
    TFlagOption.Create('includeLibraryUnits', ASettings.ArchitectureIncludeLibraryUnits),
    TFlagOption.Create('explainAssignment', ASettings.ArchitectureExplainAssignment)], cArchitectureMembers,
    ASettings);
end;

procedure TakeArchitecture(const ASource: TServerSettings; const AFileText: string; var ATarget: TServerSettings);
begin
  ATarget.ArchitectureEnabled := ASource.ArchitectureEnabled;
  ATarget.ArchitectureScope := ASource.ArchitectureScope;
  ATarget.ArchitectureIncludeLibraryUnits := ASource.ArchitectureIncludeLibraryUnits;
  ATarget.ArchitectureCentralUnits := ASource.ArchitectureCentralUnits;
  ATarget.ArchitectureExclude := ASource.ArchitectureExclude;
  ATarget.ArchitectureBaseline := ASource.ArchitectureBaseline;
  ATarget.ArchitectureFailOn := ASource.ArchitectureFailOn;
  ATarget.ArchitectureExplainAssignment := ASource.ArchitectureExplainAssignment;
  ATarget.ArchitectureGroupingResolution := ASource.ArchitectureGroupingResolution;
  ATarget.ArchitectureGroupingShowResolutionSlider := ASource.ArchitectureGroupingShowResolutionSlider;
  ATarget.ArchitectureGroupingMaxShare := ASource.ArchitectureGroupingMaxShare;
  ATarget.ArchitectureGroupingMinCohesion := ASource.ArchitectureGroupingMinCohesion;
  ATarget.ArchitectureGroupingFoundations := ASource.ArchitectureGroupingFoundations;
  ATarget.ArchitectureGroupingKeepPrevious := ASource.ArchitectureGroupingKeepPrevious;
end;

{ query, ruleChecks }

procedure ReadQuery(AReader: TConfigurationReader; ANode: TJsonNode; var ASettings: TServerSettings);
begin
  AReader.ReadObject(ANode, 'query', [TFlagOption.Create('enabled', ASettings.QueryEnabled)], [], ASettings);
end;

procedure TakeQuery(const ASource: TServerSettings; const AFileText: string; var ATarget: TServerSettings);
begin
  ATarget.QueryEnabled := ASource.QueryEnabled;
end;

procedure ReadRuleChecks(AReader: TConfigurationReader; ANode: TJsonNode; var ASettings: TServerSettings);
begin
  AReader.ReadObject(ANode, 'ruleChecks', [TFlagOption.Create('enabled', ASettings.RuleChecksEnabled)], [],
    ASettings);
end;

procedure TakeRuleChecks(const ASource: TServerSettings; const AFileText: string; var ATarget: TServerSettings);
begin
  ATarget.RuleChecksEnabled := ASource.RuleChecksEnabled;
end;

{ queries }

/// <summary>Name einer Abfrage: Buchstaben, Ziffern, "-", "_" und ".".</summary>
function IsQueryName(const AName: string): Boolean;
var
  mChar: Char;
begin
  for mChar in AName do
  begin
    if not CharInSet(mChar, ['A'..'Z', 'a'..'z', '0'..'9', '-', '_', '.']) then
    begin
      Exit(False);
    end;
  end;
  Result := True;
end;

procedure ReadQueryName(AReader: TConfigurationReader; AValue: TJsonNode; var AQuery: TSavedQuery);
var
  mText: string;
begin
  if not AReader.ExpectString(AValue, 'name', mText) then
  begin
    Exit;
  end;
  AQuery.Name := Trim(mText);
  if not IsQueryName(AQuery.Name) then
  begin
    AReader.ReportNode(AValue, cTexts[TAnalysisOptionsText.TheNameOfAQuery].Text);
    AQuery.Name := '';
  end;
end;

procedure ReadQueryText(AReader: TConfigurationReader; AValue: TJsonNode; var AQuery: TSavedQuery);
var
  mText: string;
begin
  if AReader.ExpectString(AValue, 'query', mText) then
  begin
    AQuery.Query := Trim(mText);
    AQuery.QueryRange := TTextRange.Create(AReader.PositionAt(AValue.Start + 1 + Length(mText) -
      Length(TrimLeft(mText))), AReader.PositionAt(AValue.Stop));
  end;
end;

procedure ReadQuerySeverity(AReader: TConfigurationReader; AValue: TJsonNode; var AQuery: TSavedQuery);
var
  mText: string;
begin
  if AReader.ExpectString(AValue, 'severity', mText) and (not TryParseRuleSeverity(mText, AQuery.Severity) or
    (AQuery.Severity = TRuleSeverity.Default)) then
  begin
    AReader.ReportNode(AValue, cTexts[TAnalysisOptionsText.UnknownSeverityAllowedOffHint].Fmt([mText]));
    AQuery.Severity := TRuleSeverity.Warning;
  end;
end;

procedure ReadQueryMember(AReader: TConfigurationReader; ANode: TJsonNode; AIndex: Integer;
  var AQuery: TSavedQuery);
var
  mKey: string;
begin
  mKey := ANode.Keys[AIndex];
  if mKey = 'name' then
  begin
    ReadQueryName(AReader, ANode[AIndex], AQuery);
  end
  else if mKey = 'query' then
  begin
    ReadQueryText(AReader, ANode[AIndex], AQuery);
  end
  else if mKey = 'description' then
  begin
    AReader.ExpectString(ANode[AIndex], mKey, AQuery.Description);
  end
  else if mKey = 'failIfAny' then
  begin
    AReader.ExpectBoolean(ANode[AIndex], mKey, AQuery.FailIfAny);
  end
  else if mKey = 'severity' then
  begin
    ReadQuerySeverity(AReader, ANode[AIndex], AQuery);
  end
  else if mKey = 'message' then
  begin
    AReader.ExpectString(ANode[AIndex], mKey, AQuery.Message);
  end
  else
  begin
    AReader.Report(ANode.KeyStarts[AIndex], ANode.KeyStarts[AIndex] + Length(mKey) + 2,
      cTexts[TAnalysisOptionsText.UnknownEntryInASaved].Fmt([mKey]), False);
  end;
end;

function ReadSavedQuery(AReader: TConfigurationReader; ANode: TJsonNode; out AQuery: TSavedQuery): Boolean;
var
  mIndex: Integer;
begin
  AQuery := Default(TSavedQuery);
  AQuery.Severity := TRuleSeverity.Warning;
  if ANode.Kind <> TJsonKind.Object_ then
  begin
    AReader.ReportNode(ANode, cTexts[TAnalysisOptionsText.ASavedQueryMustBe].Text);
    Exit(False);
  end;
  AQuery.Range := TTextRange.Create(AReader.PositionAt(ANode.Start), AReader.PositionAt(ANode.Start + 1));
  for mIndex := 0 to ANode.Count - 1 do
  begin
    ReadQueryMember(AReader, ANode, mIndex, AQuery);
  end;
  if AQuery.Name = '' then
  begin
    AReader.ReportNode(ANode, cTexts[TAnalysisOptionsText.ASavedQueryNeedsName].Text);
  end
  else if AQuery.Query = '' then
  begin
    AReader.ReportNode(ANode, cTexts[TAnalysisOptionsText.QueryNeedsQuery].Fmt([AQuery.Name]));
  end;
  Result := (AQuery.Name <> '') and (AQuery.Query <> '');
end;

function HasQuery(const AQueries: TArray<TSavedQuery>; const AName: string): Boolean;
var
  mQuery: TSavedQuery;
begin
  for mQuery in AQueries do
  begin
    if SameText(mQuery.Name, AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure ReadQueries(AReader: TConfigurationReader; ANode: TJsonNode; var ASettings: TServerSettings);
var
  mIndex: Integer;
  mQuery: TSavedQuery;
begin
  if ANode.Kind <> TJsonKind.Array_ then
  begin
    AReader.ReportNode(ANode, cTexts[TAnalysisOptionsText.QueriesMustBeAList].Text);
    Exit;
  end;
  ASettings.Queries := nil;
  for mIndex := 0 to ANode.Count - 1 do
  begin
    if not ReadSavedQuery(AReader, ANode[mIndex], mQuery) then
    begin
      Continue;
    end;
    // Der Name ist die Kennung der Regel query:<name> und von --query @<name>: zweimal derselbe wäre mehrdeutig.
    if HasQuery(ASettings.Queries, mQuery.Name) then
    begin
      AReader.ReportNode(ANode[mIndex], cTexts[TAnalysisOptionsText.QueryAppearsTwiceTheFirst].Fmt([mQuery.Name]));
    end
    else
    begin
      ASettings.Queries := ASettings.Queries + [mQuery];
    end;
  end;
end;

procedure TakeQueries(const ASource: TServerSettings; const AFileText: string; var ATarget: TServerSettings);
begin
  ATarget.Queries := ASource.Queries;
end;

{ hotspots }

procedure ReadMonths(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
begin
  AReader.ExpectInteger(AValue, 1, 60, cTexts[TAnalysisOptionsText.HotspotsMonthsMustBeA].Text,
    ASettings.HotspotsMonths);
end;

procedure ReadMinCommits(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
begin
  AReader.ExpectInteger(AValue, 2, 1000, cTexts[TAnalysisOptionsText.HotspotsCouplingMinCommitsMustBe].Text,
    ASettings.HotspotsCouplingMinCommits);
end;

const
  cCouplingMembers: array[0..0] of TMemberOption = ((Key: 'minCommits'; Read: ReadMinCommits));

procedure ReadCoupling(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
begin
  AReader.ReadObject(AValue, 'hotspots.coupling', [], cCouplingMembers, ASettings);
end;

const
  cHotspotMembers: array[0..1] of TMemberOption = ((Key: 'months'; Read: ReadMonths),
    (Key: 'coupling'; Read: ReadCoupling));

procedure ReadHotspots(AReader: TConfigurationReader; ANode: TJsonNode; var ASettings: TServerSettings);
begin
  AReader.ReadObject(ANode, 'hotspots', [TFlagOption.Create('enabled', ASettings.HotspotsEnabled)],
    cHotspotMembers, ASettings);
end;

procedure TakeHotspots(const ASource: TServerSettings; const AFileText: string; var ATarget: TServerSettings);
begin
  ATarget.HotspotsEnabled := ASource.HotspotsEnabled;
  ATarget.HotspotsMonths := ASource.HotspotsMonths;
  ATarget.HotspotsCouplingMinCommits := ASource.HotspotsCouplingMinCommits;
end;

const
  cSections: array[0..5] of TConfigurationSection = (
    (Section: 'index'; Read: ReadIndex; Take: TakeIndex),
    (Section: 'architecture'; Read: ReadArchitecture; Take: TakeArchitecture),
    (Section: 'query'; Read: ReadQuery; Take: TakeQuery),
    (Section: 'ruleChecks'; Read: ReadRuleChecks; Take: TakeRuleChecks),
    (Section: 'queries'; Read: ReadQueries; Take: TakeQueries),
    (Section: 'hotspots'; Read: ReadHotspots; Take: TakeHotspots)
  );

function AnalysisSections: TArray<TConfigurationSection>;
begin
  Result := SectionList(cSections);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Configuration.Internals.AnalysisOptions', cTexts);

end.
