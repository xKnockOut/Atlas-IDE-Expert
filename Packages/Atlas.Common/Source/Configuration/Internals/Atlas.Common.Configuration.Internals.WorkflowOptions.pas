unit Atlas.Common.Configuration.Internals.WorkflowOptions;

// Abschnitte von atlas.json zum Arbeitsablauf: tasks (Aufgaben mit Muster),
// issues (Tracker-Verbindungen, Zuordnungen, Abfragen) und vcs
// (Versionsverwaltung mit Zuordnungen je Projekt). Die Listen gehen als Text
// an das Plugin; der Server prüft nur und meldet.

interface

uses
  Atlas.Common.Configuration.Internals.Reader;

/// <summary>Abschnitte dieser Unit.</summary>
function WorkflowSections: TArray<TConfigurationSection>;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Internals.JsonTree,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TWorkflowOptionsText = (ThereAlreadyIsAMapping, SeverityMapMustBeAnObject, AllowedAreErrorWarningAnd,
    RegexMustNotBeEmpty, AllowedAreDccPwshMsbuild, MatcherMustBeAName, ArgsMustBeAList, TimeoutSecMustBeAWhole,
    AllowedAreCheckBuildTest, AllowedAreOffWarnAnd, TheTaskAlreadyExists, InATask, TasksMustBeAList, ATaskIsAnObject,
    StatesMustBeAList, AStateInStatesIs, LanguageIsDeOrEn, TheConnectionAlreadyExists, InAConnection,
    ConnectionsMustBeAList, AConnectionIsAnObject, InAMapping, MappingWithoutMatchPathOf, ProjectsMustBeAList,
    AMappingIsAnObject, TheQueryAlreadyExists, InAQuery, QueriesMustBeAList, AQueryIsAnObject, AllowedAreAutoGitSvn,
    ABranchNameContainsNo, VcsProjectsMustBeA, AMappingIsAnObject2, VcsTimeoutSecondsMustBeA,
    InThePatternAllowedRegex, EnvMustBeAnObject, TaskWithoutName, OnlyHttpsAddressesWithoutUser,
    ConnectionWithoutName, QueryWithoutName, UnknownEntry, CustomPatternWithoutRegex, TaskWithoutCommand,
    ConnectionWithoutProvider, ConnectionWithoutUrl, MappingWithoutConnection, QueryWithoutQuery,
    PathsMustBeAList, GitHubStateTargetIs);

const
  cTexts: array[TWorkflowOptionsText] of TAtlasText = (
    (De: 'Für diesen Pfad gibt es schon eine Zuordnung'; En: 'There already is a mapping for this path'),
    (De: '"severityMap" muss ein Objekt Wort → error, warning oder info sein';
     En: '"severityMap" must be an object word → error, warning or info'),
    (De: 'Erlaubt sind "error", "warning" und "info"'; En: 'Allowed are "error", "warning" and "info"'),
    (De: '"regex" darf nicht leer sein'; En: '"regex" must not be empty'),
    (De: 'Erlaubt sind "dcc", "pwsh", "msbuild", "generic", "none" oder ein Objekt mit "regex"';
     En: 'Allowed are "dcc", "pwsh", "msbuild", "generic", "none" or an object with "regex"'),
    (De: '"matcher" muss ein Name oder ein Objekt mit "regex" sein';
     En: '"matcher" must be a name or an object with "regex"'),
    (De: '"args" muss eine Liste von Texten sein'; En: '"args" must be a list of texts'),
    (De: '"timeoutSec" muss eine ganze Zahl von 0 bis 86400 sein';
     En: '"timeoutSec" must be a whole number from 0 to 86400'),
    (De: 'Erlaubt sind "check", "build", "test" und "other"'; En: 'Allowed are "check", "build", "test" and "other"'),
    (De: 'Erlaubt sind "off", "warn" und "block"'; En: 'Allowed are "off", "warn" and "block"'),
    (De: 'Die Aufgabe "%s" gibt es schon'; En: 'The task "%s" already exists'),
    (De: 'in einer Aufgabe'; En: 'in a task'),
    (De: '"tasks" muss eine Liste von Aufgaben sein'; En: '"tasks" must be a list of tasks'),
    (De: 'Eine Aufgabe ist ein Objekt mit "name" und "command"'; En: 'A task is an object with "name" and "command"'),
    (De: '"%s" muss eine Liste von Zuständen sein, z. B. ["Zur Prüfung", "Erledigt"]';
     En: '"%s" must be a list of states, e.g. ["In Review", "Done"]'),
    (De: 'Ein Zustand in "%s" ist ein Text'; En: 'A state in "%s" is a text'),
    (De: '"language" ist "de" oder "en"'; En: '"language" is "de" or "en"'),
    (De: 'Die Verbindung "%s" gibt es schon'; En: 'The connection "%s" already exists'),
    (De: 'in einer Verbindung'; En: 'in a connection'),
    (De: '"connections" muss eine Liste von Verbindungen sein'; En: '"connections" must be a list of connections'),
    (De: 'Eine Verbindung ist ein Objekt mit "name", "provider" und "url"';
     En: 'A connection is an object with "name", "provider" and "url"'),
    (De: 'in einer Zuordnung'; En: 'in a mapping'),
    (De: 'Zuordnung ohne "match" (Pfad einer .dproj, .groupproj oder eines Ordners)';
     En: 'Mapping without "match" (path of a .dproj, .groupproj or a folder)'),
    (De: '"projects" muss eine Liste von Zuordnungen sein'; En: '"projects" must be a list of mappings'),
    (De: 'Eine Zuordnung ist ein Objekt mit "match", "connection" und "project"';
     En: 'A mapping is an object with "match", "connection" and "project"'),
    (De: 'Die Abfrage "%s" gibt es schon'; En: 'The query "%s" already exists'),
    (De: 'in einer Abfrage'; En: 'in a query'),
    (De: '"queries" muss eine Liste von Abfragen sein'; En: '"queries" must be a list of queries'),
    (De: 'Eine Abfrage ist ein Objekt mit "name" und "query"'; En: 'A query is an object with "name" and "query"'),
    (De: 'Erlaubt sind "auto", "git", "svn" und "off"'; En: 'Allowed are "auto", "git", "svn" and "off"'),
    (De: 'Ein Branch-Name enthält keine Leerzeichen'; En: 'A branch name contains no spaces'),
    (De: '"vcs.projects" muss eine Liste von Zuordnungen sein'; En: '"vcs.projects" must be a list of mappings'),
    (De: 'Eine Zuordnung ist ein Objekt mit "match", "provider" und "mainBranch"';
     En: 'A mapping is an object with "match", "provider" and "mainBranch"'),
    (De: '"vcs.timeoutSeconds" muss eine ganze Zahl von 1 bis 300 sein';
     En: '"vcs.timeoutSeconds" must be a whole number from 1 to 300'),
    (De: 'im Muster; erlaubt: regex, severity, severityMap';
     En: 'in the pattern; allowed: regex, severity, severityMap'),
    (De: '"env" muss ein Objekt Name → Wert sein'; En: '"env" must be an object name → value'),
    (De: 'Aufgabe ohne "name"'; En: 'Task without "name"'),
    (De: 'Nur https-Adressen ohne Benutzer, z. B. "https://youtrack.firma.de"';
     En: 'Only https addresses without user, e.g. "https://youtrack.example.com"'),
    (De: 'Verbindung ohne "name"'; En: 'Connection without "name"'),
    (De: 'Abfrage ohne "name"'; En: 'Query without "name"'),
    (De: 'Unbekannte Angabe "%s" %s'; En: 'Unknown entry "%s" %s'),
    (De: 'Eigenes Muster ohne "regex"'; En: 'Custom pattern without "regex"'),
    (De: 'Aufgabe ohne "command"'; En: 'Task without "command"'),
    (De: 'Verbindung ohne "provider"'; En: 'Connection without "provider"'),
    (De: 'Verbindung ohne "url"'; En: 'Connection without "url"'),
    (De: 'Zuordnung ohne "connection"'; En: 'Mapping without "connection"'),
    (De: 'Abfrage ohne "query"'; En: 'Query without "query"'),
    (De: '"paths" muss eine Liste von Ordnern sein'; En: '"paths" must be a list of folders'),
    (De: '"githubStateTarget" ist "project" oder "label"'; En: '"githubStateTarget" is "project" or "label"'));

{$SCOPEDENUMS OFF}

const
  cSeverityNames: array[0..2] of string = ('error', 'warning', 'info');
  cProviderNames: array[0..3] of string = ('auto', 'git', 'svn', 'off');

{ Hilfen für Listen von Objekten }

/// <summary>Text ohne Leerraum am Rand, der nicht leer ist?</summary>
function ReadFilled(AReader: TConfigurationReader; AValue: TJsonNode; const AName: string): Boolean;
var
  mText: string;
begin
  Result := AReader.ExpectString(AValue, AName, mText) and (Trim(mText) <> '');
end;

/// <summary>Text aus AValues (genau so geschrieben); sonst Fehler AMessage. Ein Wert, der kein Text ist,
/// meldet ExpectString.</summary>
procedure CheckAllowed(AReader: TConfigurationReader; AValue: TJsonNode; const AName: string;
  const AValues: array of string; const AMessage: string);
var
  mIndex: Integer;
begin
  AReader.ExpectChoice(AValue, AName, AValues, AMessage, mIndex);
end;

/// <summary>Eindeutiger Name (ohne Groß-/Kleinschreibung); True, wenn er nicht leer ist. Ein doppelter Name
/// wird mit ADuplicate (Format mit dem Namen) gemeldet.</summary>
function ReadUniqueName(AReader: TConfigurationReader; AValue: TJsonNode; const ADuplicate: string;
  var ASeen: TArray<string>): Boolean;
var
  mText: string;
begin
  Result := AReader.ExpectString(AValue, 'name', mText) and (Trim(mText) <> '');
  if not Result then
  begin
    Exit;
  end;
  if IndexStr(AnsiLowerCase(Trim(mText)), ASeen) >= 0 then
  begin
    AReader.ReportNode(AValue, Format(ADuplicate, [Trim(mText)]));
  end
  else
  begin
    ASeen := ASeen + [AnsiLowerCase(Trim(mText))];
  end;
end;

/// <summary>Pfad einer Zuordnung wie im Plugin (Atlas.Core.Projects.Matching): ohne Groß-/Kleinschreibung, „/“
/// wie „\“, ohne „\“ am Ende.</summary>
function NormalizedMatch(const AText: string): string;
begin
  Result := AnsiLowerCase(Trim(AText)).Replace('/', '\');
  while Result.EndsWith('\') and (Length(Result) > 2) do
  begin
    Delete(Result, Length(Result), 1);
  end;
end;

/// <summary>"match" einer Zuordnung; True, wenn er nicht leer ist. Ein Pfad, der schon zugeordnet ist, wird
/// gemeldet.</summary>
function ReadUniqueMatch(AReader: TConfigurationReader; AValue: TJsonNode; var ASeen: TArray<string>): Boolean;
var
  mText: string;
begin
  Result := AReader.ExpectString(AValue, 'match', mText) and (Trim(mText) <> '');
  if not Result then
  begin
    Exit;
  end;
  mText := NormalizedMatch(mText);
  if IndexStr(mText, ASeen) >= 0 then
  begin
    AReader.ReportNode(AValue, cTexts[TWorkflowOptionsText.ThereAlreadyIsAMapping].Text);
  end
  else
  begin
    ASeen := ASeen + [mText];
  end;
end;

/// <summary>Warnung "Unbekannte Angabe "Schlüssel" AWhere" am Schlüssel AIndex von AItem.</summary>
procedure ReportUnknownEntry(AReader: TConfigurationReader; AItem: TJsonNode; AIndex: Integer;
  const AWhere: string);
begin
  AReader.Report(AItem.KeyStarts[AIndex], AItem.KeyStarts[AIndex] + Length(AItem.Keys[AIndex]) + 2,
    cTexts[TWorkflowOptionsText.UnknownEntry].Fmt([AItem.Keys[AIndex], AWhere]), False);
end;

/// <summary>Meldet AMessage an AItem, wenn AHas fehlt.</summary>
procedure RequireEntry(AReader: TConfigurationReader; AItem: TJsonNode; AHas: Boolean; const AMessage: string);
begin
  if not AHas then
  begin
    AReader.ReportNode(AItem, AMessage);
  end;
end;

{ tasks }

/// <summary>Severity-Abbildung eines Musters: Wort → error, warning oder info.</summary>
procedure CheckSeverityMap(AReader: TConfigurationReader; AValue: TJsonNode);
var
  mItem: Integer;
begin
  if AValue.Kind <> TJsonKind.Object_ then
  begin
    AReader.ReportNode(AValue, cTexts[TWorkflowOptionsText.SeverityMapMustBeAnObject].Text);
    Exit;
  end;
  for mItem := 0 to AValue.Count - 1 do
  begin
    CheckAllowed(AReader, AValue[mItem], 'severityMap', cSeverityNames,
      cTexts[TWorkflowOptionsText.AllowedAreErrorWarningAnd].Text);
  end;
end;

/// <summary>Glied AIndex eines eigenen Musters; True für ein gültiges "regex".</summary>
function ReadMatcherMember(AReader: TConfigurationReader; ANode: TJsonNode; AIndex: Integer): Boolean;
var
  mKey: string;
  mText: string;
begin
  Result := False;
  mKey := ANode.Keys[AIndex];
  if mKey = 'regex' then
  begin
    Result := AReader.ExpectString(ANode[AIndex], 'regex', mText) and (mText <> '');
    if (ANode[AIndex].Kind = TJsonKind.String_) and (mText = '') then
    begin
      AReader.ReportNode(ANode[AIndex], cTexts[TWorkflowOptionsText.RegexMustNotBeEmpty].Text);
    end;
  end
  else if mKey = 'severity' then
  begin
    CheckAllowed(AReader, ANode[AIndex], 'severity', cSeverityNames,
      cTexts[TWorkflowOptionsText.AllowedAreErrorWarningAnd].Text);
  end
  else if mKey = 'severityMap' then
  begin
    CheckSeverityMap(AReader, ANode[AIndex]);
  end
  else
  begin
    ReportUnknownEntry(AReader, ANode, AIndex, cTexts[TWorkflowOptionsText.InThePatternAllowedRegex].Text);
  end;
end;

procedure ReadTaskMatcher(AReader: TConfigurationReader; ANode: TJsonNode);
var
  mIndex: Integer;
  mHasRegex: Boolean;
begin
  if ANode.Kind = TJsonKind.String_ then
  begin
    if IndexStr(ANode.Value, ['dcc', 'pwsh', 'msbuild', 'generic', 'none']) < 0 then
    begin
      AReader.ReportNode(ANode, cTexts[TWorkflowOptionsText.AllowedAreDccPwshMsbuild].Text);
    end;
    Exit;
  end;
  if ANode.Kind <> TJsonKind.Object_ then
  begin
    AReader.ReportNode(ANode, cTexts[TWorkflowOptionsText.MatcherMustBeAName].Text);
    Exit;
  end;
  mHasRegex := False;
  for mIndex := 0 to ANode.Count - 1 do
  begin
    mHasRegex := ReadMatcherMember(AReader, ANode, mIndex) or mHasRegex;
  end;
  RequireEntry(AReader, ANode, mHasRegex, cTexts[TWorkflowOptionsText.CustomPatternWithoutRegex].Text);
end;

procedure CheckTaskArgs(AReader: TConfigurationReader; AValue: TJsonNode);
var
  mItem: Integer;
  mText: string;
begin
  if AValue.Kind <> TJsonKind.Array_ then
  begin
    AReader.ReportNode(AValue, cTexts[TWorkflowOptionsText.ArgsMustBeAList].Text);
    Exit;
  end;
  for mItem := 0 to AValue.Count - 1 do
  begin
    if AValue[mItem].Kind <> TJsonKind.Number then
    begin
      AReader.ExpectString(AValue[mItem], 'args', mText);
    end;
  end;
end;

procedure CheckTaskEnv(AReader: TConfigurationReader; AValue: TJsonNode);
var
  mItem: Integer;
  mText: string;
begin
  if AValue.Kind <> TJsonKind.Object_ then
  begin
    AReader.ReportNode(AValue, cTexts[TWorkflowOptionsText.EnvMustBeAnObject].Text);
    Exit;
  end;
  for mItem := 0 to AValue.Count - 1 do
  begin
    AReader.ExpectString(AValue[mItem], 'env', mText);
  end;
end;

procedure CheckTaskTimeout(AReader: TConfigurationReader; AValue: TJsonNode);
var
  mSeconds: Integer;
begin
  mSeconds := 0;
  AReader.ExpectInteger(AValue, 0, 86400, cTexts[TWorkflowOptionsText.TimeoutSecMustBeAWhole].Text, mSeconds);
end;

/// <summary>Prüft ein Glied einer Aufgabe außer name und command; False für ein unbekanntes.</summary>
function CheckTaskOption(AReader: TConfigurationReader; const AKey: string; AValue: TJsonNode): Boolean;
var
  mText: string;
begin
  Result := True;
  if MatchStr(AKey, ['cwd', 'key']) then
  begin
    AReader.ExpectString(AValue, AKey, mText);
  end
  else if AKey = 'args' then
  begin
    CheckTaskArgs(AReader, AValue);
  end
  else if AKey = 'env' then
  begin
    CheckTaskEnv(AReader, AValue);
  end
  else if AKey = 'group' then
  begin
    CheckAllowed(AReader, AValue, 'group', ['check', 'build', 'test', 'other'],
      cTexts[TWorkflowOptionsText.AllowedAreCheckBuildTest].Text);
  end
  else if AKey = 'beforeBuild' then
  begin
    CheckAllowed(AReader, AValue, 'beforeBuild', ['off', 'warn', 'block'],
      cTexts[TWorkflowOptionsText.AllowedAreOffWarnAnd].Text);
  end
  else if AKey = 'timeoutSec' then
  begin
    CheckTaskTimeout(AReader, AValue);
  end
  else if AKey = 'matcher' then
  begin
    ReadTaskMatcher(AReader, AValue);
  end
  else
  begin
    Result := False;
  end;
end;

procedure CheckTask(AReader: TConfigurationReader; ATask: TJsonNode; var ANames: TArray<string>);
var
  mInner: Integer;
  mKey: string;
  mHasName, mHasCommand: Boolean;
begin
  mHasName := False;
  mHasCommand := False;
  for mInner := 0 to ATask.Count - 1 do
  begin
    mKey := ATask.Keys[mInner];
    if mKey = 'name' then
    begin
      // Gleicher Name: Die spätere Aufgabe wäre nie erreichbar (Projekt vor global gilt nur zwischen Dateien).
      mHasName := ReadUniqueName(AReader, ATask[mInner], cTexts[TWorkflowOptionsText.TheTaskAlreadyExists].Text,
        ANames) or mHasName;
    end
    else if mKey = 'command' then
    begin
      mHasCommand := ReadFilled(AReader, ATask[mInner], 'command');
    end
    else if not CheckTaskOption(AReader, mKey, ATask[mInner]) then
    begin
      ReportUnknownEntry(AReader, ATask, mInner, cTexts[TWorkflowOptionsText.InATask].Text);
    end;
  end;
  RequireEntry(AReader, ATask, mHasName, cTexts[TWorkflowOptionsText.TaskWithoutName].Text);
  RequireEntry(AReader, ATask, mHasCommand, cTexts[TWorkflowOptionsText.TaskWithoutCommand].Text);
end;

procedure ReadTasks(AReader: TConfigurationReader; ANode: TJsonNode; var ASettings: TServerSettings);
var
  mIndex: Integer;
  mNames: TArray<string>;
begin
  if ANode.Kind <> TJsonKind.Array_ then
  begin
    AReader.ReportNode(ANode, cTexts[TWorkflowOptionsText.TasksMustBeAList].Text);
    Exit;
  end;
  ASettings.Tasks := AReader.NodeText(ANode);
  mNames := nil;
  for mIndex := 0 to ANode.Count - 1 do
  begin
    if ANode[mIndex].Kind = TJsonKind.Object_ then
    begin
      CheckTask(AReader, ANode[mIndex], mNames);
    end
    else
    begin
      AReader.ReportNode(ANode[mIndex], cTexts[TWorkflowOptionsText.ATaskIsAnObject].Text);
    end;
  end;
end;

procedure TakeTasks(const ASource: TServerSettings; const AFileText: string; var ATarget: TServerSettings);
begin
  ATarget.Tasks := ASource.Tasks;
end;

{ issues.connections }

/// <summary>Adresse eines Trackers: nur https, mit Rechner, ohne Benutzer und Leerzeichen (wie
/// TAtlasTrackerTarget im Plugin).</summary>
function IsTrackerUrl(const AUrl: string): Boolean;
var
  mHost: string;
  mSlash: Integer;
begin
  Result := False;
  if not SameText(Copy(AUrl, 1, 8), 'https://') then
  begin
    Exit;
  end;
  mHost := Copy(AUrl, 9, MaxInt);
  mSlash := Pos('/', mHost);
  if mSlash > 0 then
  begin
    mHost := Copy(mHost, 1, mSlash - 1);
  end;
  Result := (mHost <> '') and (Pos('@', mHost) = 0) and (Pos(' ', AUrl) = 0);
end;

/// <summary>"url" einer Verbindung; True, wenn sie ein Text ist.</summary>
function ReadConnectionUrl(AReader: TConfigurationReader; AValue: TJsonNode): Boolean;
var
  mText: string;
begin
  Result := AReader.ExpectString(AValue, 'url', mText);
  // Das Token geht nur über https und nie mit Benutzer in der Adresse an den Tracker.
  if Result and not IsTrackerUrl(Trim(mText)) then
  begin
    AReader.ReportNode(AValue, cTexts[TWorkflowOptionsText.OnlyHttpsAddressesWithoutUser].Text);
  end;
end;

/// <summary>Liste von Zuständen unter AKey (endStates #1266, reviewStates #2126).</summary>
procedure CheckStates(AReader: TConfigurationReader; ANode: TJsonNode; const AKey: string);
var
  mIndex: Integer;
begin
  if ANode.Kind <> TJsonKind.Array_ then
  begin
    AReader.ReportNode(ANode, Format(cTexts[TWorkflowOptionsText.StatesMustBeAList].Text, [AKey]));
    Exit;
  end;
  for mIndex := 0 to ANode.Count - 1 do
  begin
    if ANode[mIndex].Kind <> TJsonKind.String_ then
    begin
      AReader.ReportNode(ANode[mIndex], Format(cTexts[TWorkflowOptionsText.AStateInStatesIs].Text, [AKey]));
    end;
  end;
end;

/// <summary>Prüft ein Glied einer Verbindung außer name, provider und url; False für ein unbekanntes.</summary>
function CheckConnectionOption(AReader: TConfigurationReader; const AKey: string; AValue: TJsonNode): Boolean;
var
  mText: string;
begin
  Result := True;
  if AKey = 'language' then
  begin
    // Sprache der Oberfläche (#1263), vom Plugin bei „Prüfen“ erkannt.
    CheckAllowed(AReader, AValue, 'language', ['de', 'en'], cTexts[TWorkflowOptionsText.LanguageIsDeOrEn].Text);
  end
  // Zustand beim Beginnen und Beenden je Verbindung (#1266).
  else if MatchStr(AKey, ['stateField', 'assigneeField', 'startState', 'githubProject']) then
  begin
    AReader.ExpectString(AValue, AKey, mText);
  end
  // Zustand bei GitHub im Projektfeld oder als Label (#2134).
  else if AKey = 'githubStateTarget' then
  begin
    CheckAllowed(AReader, AValue, AKey, ['project', 'label'], cTexts[TWorkflowOptionsText.GitHubStateTargetIs].Text);
  end
  // Zielzustände beim Beenden (#1266) und Prüfzustände (#2126, #2127).
  else if MatchStr(AKey, ['endStates', 'reviewStates']) then
  begin
    CheckStates(AReader, AValue, AKey);
  end
  else
  begin
    Result := False;
  end;
end;

procedure CheckConnection(AReader: TConfigurationReader; AConnection: TJsonNode; var ANames: TArray<string>);
var
  mInner: Integer;
  mKey: string;
  mHasName, mHasProvider, mHasUrl: Boolean;
begin
  mHasName := False;
  mHasProvider := False;
  mHasUrl := False;
  for mInner := 0 to AConnection.Count - 1 do
  begin
    mKey := AConnection.Keys[mInner];
    if mKey = 'name' then
    begin
      mHasName := ReadUniqueName(AReader, AConnection[mInner],
        cTexts[TWorkflowOptionsText.TheConnectionAlreadyExists].Text, ANames) or
        mHasName;
    end
    else if mKey = 'provider' then
    begin
      mHasProvider := ReadFilled(AReader, AConnection[mInner], 'provider');
    end
    else if mKey = 'url' then
    begin
      mHasUrl := ReadConnectionUrl(AReader, AConnection[mInner]) or mHasUrl;
    end
    else if not CheckConnectionOption(AReader, mKey, AConnection[mInner]) then
    begin
      ReportUnknownEntry(AReader, AConnection, mInner, cTexts[TWorkflowOptionsText.InAConnection].Text);
    end;
  end;
  RequireEntry(AReader, AConnection, mHasName, cTexts[TWorkflowOptionsText.ConnectionWithoutName].Text);
  RequireEntry(AReader, AConnection, mHasProvider, cTexts[TWorkflowOptionsText.ConnectionWithoutProvider].Text);
  RequireEntry(AReader, AConnection, mHasUrl, cTexts[TWorkflowOptionsText.ConnectionWithoutUrl].Text);
end;

procedure ReadConnections(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
var
  mIndex: Integer;
  mNames: TArray<string>;
begin
  if AValue.Kind <> TJsonKind.Array_ then
  begin
    AReader.ReportNode(AValue, cTexts[TWorkflowOptionsText.ConnectionsMustBeAList].Text);
    Exit;
  end;
  ASettings.IssueConnections := AReader.NodeText(AValue);
  mNames := nil;
  for mIndex := 0 to AValue.Count - 1 do
  begin
    if AValue[mIndex].Kind = TJsonKind.Object_ then
    begin
      CheckConnection(AReader, AValue[mIndex], mNames);
    end
    else
    begin
      AReader.ReportNode(AValue[mIndex], cTexts[TWorkflowOptionsText.AConnectionIsAnObject].Text);
    end;
  end;
end;

{ issues.projects }

procedure CheckIssueProject(AReader: TConfigurationReader; AMapping: TJsonNode; var AMatches: TArray<string>);
var
  mInner: Integer;
  mKey, mText: string;
  mPaths: TArray<string>;
  mHasMatch, mHasConnection: Boolean;
begin
  mHasMatch := False;
  mHasConnection := False;
  for mInner := 0 to AMapping.Count - 1 do
  begin
    mKey := AMapping.Keys[mInner];
    if mKey = 'match' then
    begin
      mHasMatch := ReadUniqueMatch(AReader, AMapping[mInner], AMatches) or mHasMatch;
    end
    else if mKey = 'connection' then
    begin
      mHasConnection := ReadFilled(AReader, AMapping[mInner], 'connection');
    end
    else if mKey = 'project' then
    begin
      AReader.ExpectString(AMapping[mInner], 'project', mText);
    end
    else if mKey = 'paths' then
    begin
      // Arbeitskopien des Tracker-Projekts (#1926); der Inhalt gehört dem Plugin.
      AReader.ExpectStrings(AMapping[mInner], 'paths', cTexts[TWorkflowOptionsText.PathsMustBeAList].Text, mPaths);
    end
    else
    begin
      ReportUnknownEntry(AReader, AMapping, mInner, cTexts[TWorkflowOptionsText.InAMapping].Text);
    end;
  end;
  RequireEntry(AReader, AMapping, mHasMatch, cTexts[TWorkflowOptionsText.MappingWithoutMatchPathOf].Text);
  RequireEntry(AReader, AMapping, mHasConnection, cTexts[TWorkflowOptionsText.MappingWithoutConnection].Text);
end;

procedure ReadIssueProjects(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
var
  mIndex: Integer;
  mMatches: TArray<string>;
begin
  if AValue.Kind <> TJsonKind.Array_ then
  begin
    AReader.ReportNode(AValue, cTexts[TWorkflowOptionsText.ProjectsMustBeAList].Text);
    Exit;
  end;
  ASettings.IssueProjects := AReader.NodeText(AValue);
  mMatches := nil;
  for mIndex := 0 to AValue.Count - 1 do
  begin
    if AValue[mIndex].Kind = TJsonKind.Object_ then
    begin
      CheckIssueProject(AReader, AValue[mIndex], mMatches);
    end
    else
    begin
      AReader.ReportNode(AValue[mIndex], cTexts[TWorkflowOptionsText.AMappingIsAnObject].Text);
    end;
  end;
end;

{ issues.queries }

procedure CheckIssueQuery(AReader: TConfigurationReader; AQuery: TJsonNode; var ANames: TArray<string>);
var
  mInner: Integer;
  mKey, mText: string;
  mHasName, mHasQuery: Boolean;
begin
  mHasName := False;
  mHasQuery := False;
  for mInner := 0 to AQuery.Count - 1 do
  begin
    mKey := AQuery.Keys[mInner];
    if mKey = 'name' then
    begin
      // Die Klappliste unterscheidet Namen ohne Groß-/Kleinschreibung.
      mHasName := ReadUniqueName(AReader, AQuery[mInner], cTexts[TWorkflowOptionsText.TheQueryAlreadyExists].Text,
        ANames) or mHasName;
    end
    else if mKey = 'query' then
    begin
      mHasQuery := ReadFilled(AReader, AQuery[mInner], 'query');
    end
    else if MatchStr(mKey, ['connection', 'project']) then
    begin
      AReader.ExpectString(AQuery[mInner], mKey, mText);
    end
    else
    begin
      ReportUnknownEntry(AReader, AQuery, mInner, cTexts[TWorkflowOptionsText.InAQuery].Text);
    end;
  end;
  RequireEntry(AReader, AQuery, mHasName, cTexts[TWorkflowOptionsText.QueryWithoutName].Text);
  RequireEntry(AReader, AQuery, mHasQuery, cTexts[TWorkflowOptionsText.QueryWithoutQuery].Text);
end;

procedure ReadIssueQueries(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
var
  mIndex: Integer;
  mNames: TArray<string>;
begin
  if AValue.Kind <> TJsonKind.Array_ then
  begin
    AReader.ReportNode(AValue, cTexts[TWorkflowOptionsText.QueriesMustBeAList].Text);
    Exit;
  end;
  ASettings.IssueQueries := AReader.NodeText(AValue);
  mNames := nil;
  for mIndex := 0 to AValue.Count - 1 do
  begin
    if AValue[mIndex].Kind = TJsonKind.Object_ then
    begin
      CheckIssueQuery(AReader, AValue[mIndex], mNames);
    end
    else
    begin
      AReader.ReportNode(AValue[mIndex], cTexts[TWorkflowOptionsText.AQueryIsAnObject].Text);
    end;
  end;
end;

const
  cIssueMembers: array[0..2] of TMemberOption = ((Key: 'connections'; Read: ReadConnections),
    (Key: 'projects'; Read: ReadIssueProjects), (Key: 'queries'; Read: ReadIssueQueries));

procedure ReadIssues(AReader: TConfigurationReader; ANode: TJsonNode; var ASettings: TServerSettings);
begin
  AReader.ReadObject(ANode, 'issues', [], cIssueMembers, ASettings);
end;

procedure TakeIssues(const ASource: TServerSettings; const AFileText: string; var ATarget: TServerSettings);
begin
  ATarget.IssueConnections := ASource.IssueConnections;
  ATarget.IssueProjects := ASource.IssueProjects;
  ATarget.IssueQueries := ASource.IssueQueries;
end;

{ vcs }

procedure CheckVcsProject(AReader: TConfigurationReader; AMapping: TJsonNode; var AMatches: TArray<string>);
var
  mInner: Integer;
  mKey, mText: string;
  mHasMatch: Boolean;
begin
  mHasMatch := False;
  for mInner := 0 to AMapping.Count - 1 do
  begin
    mKey := AMapping.Keys[mInner];
    if mKey = 'match' then
    begin
      mHasMatch := ReadUniqueMatch(AReader, AMapping[mInner], AMatches) or mHasMatch;
    end
    else if mKey = 'provider' then
    begin
      CheckAllowed(AReader, AMapping[mInner], 'provider', cProviderNames,
        cTexts[TWorkflowOptionsText.AllowedAreAutoGitSvn].Text);
    end
    else if mKey = 'mainBranch' then
    begin
      if AReader.ExpectString(AMapping[mInner], 'mainBranch', mText) and (Trim(mText).IndexOfAny([' ', #9]) >= 0) then
      begin
        AReader.ReportNode(AMapping[mInner], cTexts[TWorkflowOptionsText.ABranchNameContainsNo].Text);
      end;
    end
    else
    begin
      ReportUnknownEntry(AReader, AMapping, mInner, cTexts[TWorkflowOptionsText.InAMapping].Text);
    end;
  end;
  RequireEntry(AReader, AMapping, mHasMatch, cTexts[TWorkflowOptionsText.MappingWithoutMatchPathOf].Text);
end;

procedure ReadVcsProjects(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
var
  mIndex: Integer;
  mMatches: TArray<string>;
begin
  if AValue.Kind <> TJsonKind.Array_ then
  begin
    AReader.ReportNode(AValue, cTexts[TWorkflowOptionsText.VcsProjectsMustBeA].Text);
    Exit;
  end;
  ASettings.VcsProjects := AReader.NodeText(AValue);
  mMatches := nil;
  for mIndex := 0 to AValue.Count - 1 do
  begin
    if AValue[mIndex].Kind = TJsonKind.Object_ then
    begin
      CheckVcsProject(AReader, AValue[mIndex], mMatches);
    end
    else
    begin
      AReader.ReportNode(AValue[mIndex], cTexts[TWorkflowOptionsText.AMappingIsAnObject2].Text);
    end;
  end;
end;

/// <summary>vcs.git bzw. vcs.svn (#1285): nur "path", leer = automatisch suchen.</summary>
procedure ReadVcsTool(AReader: TConfigurationReader; AValue: TJsonNode; const AName: string; var APath: string);
var
  mIndex: Integer;
begin
  if not AReader.ExpectObject(AValue, 'vcs.' + AName) then
  begin
    Exit;
  end;
  for mIndex := 0 to AValue.Count - 1 do
  begin
    if AValue.Keys[mIndex] = 'path' then
    begin
      AReader.ExpectString(AValue[mIndex], 'path', APath);
    end
    else
    begin
      AReader.ReportUnknown(AValue, mIndex, 'vcs.' + AName);
    end;
  end;
end;

procedure ReadVcsGit(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
begin
  ReadVcsTool(AReader, AValue, AKey, ASettings.VcsGitPath);
end;

procedure ReadVcsSvn(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
begin
  ReadVcsTool(AReader, AValue, AKey, ASettings.VcsSvnPath);
end;

procedure ReadVcsProvider(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
var
  mIndex: Integer;
begin
  if AReader.ExpectChoice(AValue, AKey, cProviderNames, cTexts[TWorkflowOptionsText.AllowedAreAutoGitSvn].Text,
    mIndex) then
  begin
    ASettings.VcsProvider := cProviderNames[mIndex];
  end;
end;

procedure ReadVcsTimeout(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
begin
  AReader.ExpectInteger(AValue, 1, 300, cTexts[TWorkflowOptionsText.VcsTimeoutSecondsMustBeA].Text,
    ASettings.VcsTimeoutSeconds);
end;

const
  cVcsMembers: array[0..4] of TMemberOption = ((Key: 'provider'; Read: ReadVcsProvider),
    (Key: 'git'; Read: ReadVcsGit), (Key: 'svn'; Read: ReadVcsSvn), (Key: 'projects'; Read: ReadVcsProjects),
    (Key: 'timeoutSeconds'; Read: ReadVcsTimeout));

procedure ReadVcs(AReader: TConfigurationReader; ANode: TJsonNode; var ASettings: TServerSettings);
begin
  AReader.ReadObject(ANode, 'vcs', [], cVcsMembers, ASettings);
end;

procedure TakeVcs(const ASource: TServerSettings; const AFileText: string; var ATarget: TServerSettings);
begin
  ATarget.VcsProvider := ASource.VcsProvider;
  ATarget.VcsGitPath := ASource.VcsGitPath;
  ATarget.VcsSvnPath := ASource.VcsSvnPath;
  ATarget.VcsTimeoutSeconds := ASource.VcsTimeoutSeconds;
  ATarget.VcsProjects := ASource.VcsProjects;
end;

const
  cSections: array[0..2] of TConfigurationSection = (
    (Section: 'tasks'; Read: ReadTasks; Take: TakeTasks),
    (Section: 'issues'; Read: ReadIssues; Take: TakeIssues),
    (Section: 'vcs'; Read: ReadVcs; Take: TakeVcs)
  );

function WorkflowSections: TArray<TConfigurationSection>;
begin
  Result := SectionList(cSections);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Configuration.Internals.WorkflowOptions', cTexts);

end.
