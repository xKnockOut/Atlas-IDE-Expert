unit Atlas.Core.Projects.Summary.Sections;

// Abschnitte "setup" (#759), "tests" (#69), "release" (#533) und "ci" (#763)
// der Projekt-Zusammenfassung (#592), ohne VCL und Open Tools API: Typen,
// Lesen aus und Schreiben nach JSON. Unbekannte Felder bleiben beim Schreiben
// erhalten. Atlas.Core.Projects.Summary gibt die Typen unter gleichem Namen
// weiter; das Format steht dort.

interface

uses
  System.JSON,
  Atlas.Core.CiBuild.Contract;

type
  /// <summary>Fund der Pfadprüfung (#759): fehlende Unit oder Define ohne Quelle.</summary>
  TAtlasSetupFinding = record
    Name: string;
    /// <summary>Datei der ersten Stelle, relativ zum Projektordner.</summary>
    FileName: string;
    /// <summary>Zeile ab 1.</summary>
    Line: Integer;
    /// <summary>Stellen im Projekt.</summary>
    Count: Integer;
    /// <summary>Kein sicherer Fund (Suchpfad mit unbekanntem Makro übersprungen).</summary>
    Uncertain: Boolean;
    /// <summary>Define: ähnliches bekanntes Symbol; Hinweis: Unit im Suchpfad ('' = Package ohne Quelle).</summary>
    Note: string;
    /// <summary>Nur in der Zusammenfassung einer Projektgruppe: Name des Projekts; nicht gespeichert.</summary>
    Project: string;
  end;

  /// <summary>Einrichtung des Projekts für Atlas (#759).</summary>
  TAtlasProjectSetup = record
  public const
    /// <summary>Höchstens so viele Funde je Liste stehen in der Datei.</summary>
    MaxFindings = 50;
  public
    Known: Boolean;
    /// <summary>„Für dieses Projekt nicht mehr fragen“.</summary>
    Dismissed: Boolean;
    DismissedAt: TDateTime;
    /// <summary>„Suchpfade und Defines prüfen“ lief; die übrigen Felder gelten nur dann.</summary>
    Checked: Boolean;
    CheckedAt: TDateTime;
    Files: Integer;
    Unreadable: Integer;
    /// <summary>Alle fehlenden Units bzw. Defines ohne Quelle, auch über MaxFindings hinaus.</summary>
    MissingUnitCount: Integer;
    UndefinedDefineCount: Integer;
    MissingUnits: TArray<TAtlasSetupFinding>;
    UndefinedDefines: TArray<TAtlasSetupFinding>;
    /// <summary>Hinweise zu requires-Packages (#759); kein Fehler.</summary>
    Hints: TArray<TAtlasSetupFinding>;
    /// <summary>Davon unsicher (in MissingUnitCount bzw. UndefinedDefineCount enthalten).</summary>
    UncertainUnitCount: Integer;
    UncertainDefineCount: Integer;
    /// <summary>Unbekannte Makros übersprungener Such- und Bibliothekspfade.</summary>
    SkippedMacros: TArray<string>;
    class function Empty: TAtlasProjectSetup; static;
    /// <summary>Die letzte Prüfung lief und fand nichts Sicheres (unsichere Funde zählen nicht).</summary>
    function PathsClean: Boolean;
  end;

  /// <summary>Fehlgeschlagener Test des letzten Laufs (#69).</summary>
  TAtlasProjectTestFailure = record
    /// <summary>Voller Name aus dem Bericht von DUnitX (Unit.Fixture.Methode[.Fall]).</summary>
    Test: string;
    Message: string;
    /// <summary>Datei des Tests (absolut); '' ohne Fundstelle.</summary>
    FileName: string;
    /// <summary>Zeile ab 1; 0 = ohne.</summary>
    Line: Integer;
  end;

  /// <summary>Letzter DUnitX-Lauf aus der IDE (#69), Grundlage der Karte Tests (#763).</summary>
  TAtlasProjectTests = record
  public const
    /// <summary>Höchstens so viele fehlgeschlagene Tests stehen in der Datei.</summary>
    MaxFailures = 50;
  public
    Known: Boolean;
    /// <summary>Ende des Laufs (UTC).</summary>
    At: TDateTime;
    /// <summary>Testprojekt (.dproj).</summary>
    Project: string;
    Configuration: string;
    Platform: string;
    Passed: Integer;
    Failed: Integer;
    Errors: Integer;
    Skipped: Integer;
    DurationMs: Integer;
    Failures: TArray<TAtlasProjectTestFailure>;
    class function Empty: TAtlasProjectTests; static;
    /// <summary>Namen der gespeicherten fehlgeschlagenen Tests ohne Doppelte, für --run.</summary>
    function FailedTests: TArray<string>;
    function Total: Integer;
  end;

  /// <summary>Letzter erfolgreicher Release-Build einer Konfiguration und Plattform (#533).</summary>
  TAtlasProjectReleaseBuild = record
    Configuration: string;
    Platform: string;
    Version: string;
    /// <summary>Ende des Builds (UTC).</summary>
    At: TDateTime;
  end;

  /// <summary>Release-Build-Wächter (#533): letzte Prüfung und Versionen der Release-Builds.</summary>
  TAtlasProjectRelease = record
  public const
    /// <summary>Höchstens so viele Einträge in "builds" (je Konfiguration und Plattform einer).</summary>
    MaxBuilds = 20;
  public
    Known: Boolean;
    /// <summary>Letzte Prüfung (UTC); 0 = noch keine.</summary>
    CheckedAt: TDateTime;
    Configuration: string;
    Platform: string;
    Findings: Integer;
    /// <summary>Die Prüfung hat den Build abgebrochen (build.gate = block).</summary>
    Blocked: Boolean;
    /// <summary>Regel-IDs der Verstöße ohne Doppelte, z. B. release-debug-define.</summary>
    Rules: TArray<string>;
    Builds: TArray<TAtlasProjectReleaseBuild>;
    class function Empty: TAtlasProjectRelease; static;
    /// <summary>Version des letzten erfolgreichen Release-Builds von AConfiguration/APlatform; '' = keiner.
    /// </summary>
    function VersionOf(const AConfiguration, APlatform: string): string;
    /// <summary>Merkt AVersion für AConfiguration/APlatform (ersetzt den alten Eintrag, neueste zuerst).</summary>
    procedure Remember(const AConfiguration, APlatform, AVersion: string; AAtUtc: TDateTime);
  end;

  /// <summary>Letzter Abruf vom Build-Server (#763).</summary>
  TAtlasProjectCi = record
    Known: Boolean;
    /// <summary>"jenkins".</summary>
    Provider: string;
    /// <summary>TAtlasCiJob.Server, z. B. "https://ci.firma.de".</summary>
    Server: string;
    Job: string;
    /// <summary>Branch des Multibranch-Jobs; '' sonst.</summary>
    Branch: string;
    /// <summary>Letzter Versuch (UTC); 0 = noch keiner.</summary>
    Attempt: TDateTime;
    /// <summary>Fehler des letzten Versuchs; None = gelungen.</summary>
    Error: TAtlasCiFetchError;
    /// <summary>Letzter gelungener Abruf (UTC); 0 = noch keiner. Build gilt für diesen Stand.</summary>
    At: TDateTime;
    Build: TAtlasCiBuild;
    class function Empty: TAtlasProjectCi; static;
    /// <summary>Der Stand gehört zu AJob (Anbieter, Server, Job und Branch gleich).</summary>
    function Matches(const AJob: TAtlasCiJob): Boolean;
    /// <summary>Ein Build ist bekannt.</summary>
    function HasBuild: Boolean;
  end;

  /// <summary>Lesen und Schreiben der Abschnitte; AOriginal ist der Abschnitt der gelesenen Datei (darf nil sein),
  /// seine unbekannten Felder bleiben erhalten.</summary>
  TAtlasSummarySections = class
  public
    /// <summary>Abschnitt "setup"; Empty ohne Abschnitt.</summary>
    class function SetupOf(ASection: TJSONObject): TAtlasProjectSetup; static;
    class function SetupJson(const ASetup: TAtlasProjectSetup; AOriginal: TJSONObject): TJSONObject; static;
    /// <summary>Abschnitt "tests"; Empty ohne Abschnitt.</summary>
    class function TestsOf(ASection: TJSONObject): TAtlasProjectTests; static;
    class function TestsJson(const ATests: TAtlasProjectTests; AOriginal: TJSONObject): TJSONObject; static;
    /// <summary>Abschnitt "release"; Empty ohne Abschnitt.</summary>
    class function ReleaseOf(ASection: TJSONObject): TAtlasProjectRelease; static;
    class function ReleaseJson(const ARelease: TAtlasProjectRelease; AOriginal: TJSONObject): TJSONObject; static;
    /// <summary>Abschnitt "ci"; Empty ohne Abschnitt.</summary>
    class function CiOf(ASection: TJSONObject): TAtlasProjectCi; static;
    class function CiJson(const ACi: TAtlasProjectCi; AOriginal: TJSONObject): TJSONObject; static;
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  Atlas.Core.Projects.Summary.Json;

const
  SetupKeys: array[0..2] of string = ('dismissed', 'dismissedAt', 'paths');
  TestsKeys: array[0..9] of string = ('at', 'project', 'configuration', 'platform', 'passed', 'failed', 'errors',
    'skipped', 'durationMs', 'failures');
  ReleaseKeys: array[0..6] of string = ('checkedAt', 'configuration', 'platform', 'findings', 'blocked', 'rules',
    'builds');
  CiKeys: array[0..14] of string = ('provider', 'server', 'job', 'branch', 'attempt', 'error', 'at', 'number',
    'result', 'started', 'durationMs', 'passed', 'failed', 'skipped', 'failures');
  CiFailureKeys: array[0..1] of string = ('test', 'message');
  ReleaseBuildKeys: array[0..3] of string = ('configuration', 'platform', 'version', 'at');
  PathsKeys: array[0..10] of string = ('at', 'files', 'unreadable', 'missingUnits', 'undefinedDefines', 'units',
    'defines', 'uncertainUnits', 'uncertainDefines', 'skippedMacros', 'hints');

{ TAtlasProjectSetup }

class function TAtlasProjectSetup.Empty: TAtlasProjectSetup;
begin
  Result := Default(TAtlasProjectSetup);
  Result.MissingUnits := nil;
  Result.UndefinedDefines := nil;
end;

function TAtlasProjectSetup.PathsClean: Boolean;
begin
  Result := Checked and (MissingUnitCount <= UncertainUnitCount) and (UndefinedDefineCount <= UncertainDefineCount);
end;

/// <summary>Funde aus einem Array [{"name", "file", "line", "count"}]; Einträge ohne Namen fallen weg.</summary>
function SetupFindingsOf(AValue: TJSONValue): TArray<TAtlasSetupFinding>;
var
  Index: Integer;
  Item: TJSONValue;
  Finding: TAtlasSetupFinding;
begin
  Result := nil;
  if not (AValue is TJSONArray) then
  begin
    Exit;
  end;
  for Index := 0 to TJSONArray(AValue).Count - 1 do
  begin
    Item := TJSONArray(AValue).Items[Index];
    if not (Item is TJSONObject) then
    begin
      Continue;
    end;
    Finding.Name := TextOf(TJSONObject(Item), 'name');
    Finding.FileName := TextOf(TJSONObject(Item), 'file');
    Finding.Line := NumberOf(TJSONObject(Item), 'line', 0);
    Finding.Count := NumberOf(TJSONObject(Item), 'count', 1);
    Finding.Uncertain := FlagOf(TJSONObject(Item), 'uncertain');
    Finding.Note := TextOf(TJSONObject(Item), 'note');
    Finding.Project := '';
    if (Finding.Name <> '') and (Length(Result) < TAtlasProjectSetup.MaxFindings) then
    begin
      Result := Result + [Finding];
    end;
  end;
end;

function SetupFindingsJson(const AFindings: TArray<TAtlasSetupFinding>): TJSONArray;
var
  Index: Integer;
  Item: TJSONObject;
begin
  Result := TJSONArray.Create;
  for Index := 0 to High(AFindings) do
  begin
    if Index >= TAtlasProjectSetup.MaxFindings then
    begin
      Break;
    end;
    Item := TJSONObject.Create;
    Result.AddElement(Item);
    Item.AddPair('name', AFindings[Index].Name);
    if AFindings[Index].FileName <> '' then
    begin
      Item.AddPair('file', AFindings[Index].FileName);
    end;
    if AFindings[Index].Line > 0 then
    begin
      Item.AddPair('line', TJSONNumber.Create(AFindings[Index].Line));
    end;
    Item.AddPair('count', TJSONNumber.Create(AFindings[Index].Count));
    if AFindings[Index].Uncertain then
    begin
      Item.AddPair('uncertain', TJSONBool.Create(True));
    end;
    if AFindings[Index].Note <> '' then
    begin
      Item.AddPair('note', AFindings[Index].Note);
    end;
  end;
end;

/// <summary>Texte aus einem Array von Zeichenketten; anderes (auch Zahlen) fällt weg.</summary>
function TextsOfSetup(AValue: TJSONValue): TArray<string>;
var
  Index: Integer;
  Item: TJSONValue;
begin
  Result := nil;
  if not (AValue is TJSONArray) then
  begin
    Exit;
  end;
  for Index := 0 to TJSONArray(AValue).Count - 1 do
  begin
    Item := TJSONArray(AValue).Items[Index];
    // TJSONNumber erbt von TJSONString.
    if (Item is TJSONString) and not (Item is TJSONNumber) and (Item.Value <> '') then
    begin
      Result := Result + [Item.Value];
    end;
  end;
end;

/// <summary>Abschnitt "setup"; leer ohne Abschnitt.</summary>
class function TAtlasSummarySections.SetupOf(ASection: TJSONObject): TAtlasProjectSetup;
var
  Paths: TJSONObject;
begin
  Result := TAtlasProjectSetup.Empty;
  if ASection = nil then
  begin
    Exit;
  end;
  Result.Known := True;
  Result.Dismissed := FlagOf(ASection, 'dismissed');
  Result.DismissedAt := SummaryTimeOf(TextOf(ASection, 'dismissedAt'));
  Paths := ObjectOf(ASection, 'paths');
  if Paths = nil then
  begin
    Exit;
  end;
  Result.Checked := True;
  Result.CheckedAt := SummaryTimeOf(TextOf(Paths, 'at'));
  Result.Files := NumberOf(Paths, 'files', 0);
  Result.Unreadable := NumberOf(Paths, 'unreadable', 0);
  Result.MissingUnits := SetupFindingsOf(Paths.GetValue('units'));
  Result.UndefinedDefines := SetupFindingsOf(Paths.GetValue('defines'));
  Result.Hints := SetupFindingsOf(Paths.GetValue('hints'));
  // Die Zähler sind nie kleiner als die gespeicherten Funde.
  Result.MissingUnitCount := NumberOf(Paths, 'missingUnits', 0);
  if Result.MissingUnitCount < Length(Result.MissingUnits) then
  begin
    Result.MissingUnitCount := Length(Result.MissingUnits);
  end;
  Result.UndefinedDefineCount := NumberOf(Paths, 'undefinedDefines', 0);
  if Result.UndefinedDefineCount < Length(Result.UndefinedDefines) then
  begin
    Result.UndefinedDefineCount := Length(Result.UndefinedDefines);
  end;
  // Unsichere nie mehr als alle.
  Result.UncertainUnitCount := NumberOf(Paths, 'uncertainUnits', 0);
  if Result.UncertainUnitCount > Result.MissingUnitCount then
  begin
    Result.UncertainUnitCount := Result.MissingUnitCount;
  end;
  Result.UncertainDefineCount := NumberOf(Paths, 'uncertainDefines', 0);
  if Result.UncertainDefineCount > Result.UndefinedDefineCount then
  begin
    Result.UncertainDefineCount := Result.UndefinedDefineCount;
  end;
  Result.SkippedMacros := TextsOfSetup(Paths.GetValue('skippedMacros'));
end;

class function TAtlasSummarySections.SetupJson(const ASetup: TAtlasProjectSetup; AOriginal: TJSONObject): TJSONObject;
var
  Paths: TJSONObject;
  Macros: TJSONArray;
  Macro: string;
begin
  Result := TJSONObject.Create;
  if ASetup.Dismissed then
  begin
    Result.AddPair('dismissed', TJSONBool.Create(True));
    AddTime(Result, 'dismissedAt', ASetup.DismissedAt);
  end;
  if ASetup.Checked then
  begin
    Paths := TJSONObject.Create;
    Result.AddPair('paths', Paths);
    AddTime(Paths, 'at', ASetup.CheckedAt);
    Paths.AddPair('files', TJSONNumber.Create(ASetup.Files));
    Paths.AddPair('unreadable', TJSONNumber.Create(ASetup.Unreadable));
    Paths.AddPair('missingUnits', TJSONNumber.Create(ASetup.MissingUnitCount));
    Paths.AddPair('undefinedDefines', TJSONNumber.Create(ASetup.UndefinedDefineCount));
    if ASetup.UncertainUnitCount > 0 then
    begin
      Paths.AddPair('uncertainUnits', TJSONNumber.Create(ASetup.UncertainUnitCount));
    end;
    if ASetup.UncertainDefineCount > 0 then
    begin
      Paths.AddPair('uncertainDefines', TJSONNumber.Create(ASetup.UncertainDefineCount));
    end;
    if Length(ASetup.SkippedMacros) > 0 then
    begin
      Macros := TJSONArray.Create;
      Paths.AddPair('skippedMacros', Macros);
      for Macro in ASetup.SkippedMacros do
      begin
        Macros.Add(Macro);
      end;
    end;
    Paths.AddPair('units', SetupFindingsJson(ASetup.MissingUnits));
    Paths.AddPair('defines', SetupFindingsJson(ASetup.UndefinedDefines));
    if Length(ASetup.Hints) > 0 then
    begin
      Paths.AddPair('hints', SetupFindingsJson(ASetup.Hints));
    end;
    KeepUnknown(Paths, ObjectOf(AOriginal, 'paths'), PathsKeys);
  end;
  KeepUnknown(Result, AOriginal, SetupKeys);
end;

{ TAtlasProjectTests }

class function TAtlasProjectTests.Empty: TAtlasProjectTests;
begin
  Result := Default(TAtlasProjectTests);
  Result.Failures := nil;
end;

function TAtlasProjectTests.FailedTests: TArray<string>;
var
  Failure: TAtlasProjectTestFailure;
  Name: string;
  Seen: Boolean;
begin
  Result := nil;
  for Failure in Failures do
  begin
    if Failure.Test = '' then
    begin
      Continue;
    end;
    Seen := False;
    for Name in Result do
    begin
      if SameText(Name, Failure.Test) then
      begin
        Seen := True;
      end;
    end;
    if not Seen then
    begin
      Result := Result + [Failure.Test];
    end;
  end;
end;

function TAtlasProjectTests.Total: Integer;
begin
  Result := Passed + Failed + Errors + Skipped;
end;

class function TAtlasSummarySections.TestsOf(ASection: TJSONObject): TAtlasProjectTests;
var
  Items: TJSONValue;
  Item: TJSONValue;
  Failure: TAtlasProjectTestFailure;
begin
  Result := TAtlasProjectTests.Empty;
  if ASection = nil then
  begin
    Exit;
  end;
  Result.Known := True;
  Result.At := SummaryTimeOf(TextOf(ASection, 'at'));
  Result.Project := TextOf(ASection, 'project');
  Result.Configuration := TextOf(ASection, 'configuration');
  Result.Platform := TextOf(ASection, 'platform');
  Result.Passed := NumberOf(ASection, 'passed', 0);
  Result.Failed := NumberOf(ASection, 'failed', 0);
  Result.Errors := NumberOf(ASection, 'errors', 0);
  Result.Skipped := NumberOf(ASection, 'skipped', 0);
  Result.DurationMs := NumberOf(ASection, 'durationMs', 0);
  Items := ASection.GetValue('failures');
  if not (Items is TJSONArray) then
  begin
    Exit;
  end;
  for Item in TJSONArray(Items) do
  begin
    if not (Item is TJSONObject) or (Length(Result.Failures) >= TAtlasProjectTests.MaxFailures) then
    begin
      Continue;
    end;
    Failure := Default(TAtlasProjectTestFailure);
    Failure.Test := TextOf(TJSONObject(Item), 'test');
    Failure.Message := TextOf(TJSONObject(Item), 'message');
    Failure.FileName := TextOf(TJSONObject(Item), 'file');
    Failure.Line := NumberOf(TJSONObject(Item), 'line', 0);
    if Failure.Test <> '' then
    begin
      Result.Failures := Result.Failures + [Failure];
    end;
  end;
end;

class function TAtlasSummarySections.TestsJson(const ATests: TAtlasProjectTests; AOriginal: TJSONObject): TJSONObject;
var
  Items: TJSONArray;
  Item: TJSONObject;
  Index: Integer;
begin
  Result := TJSONObject.Create;
  AddTime(Result, 'at', ATests.At);
  Result.AddPair('project', ATests.Project);
  if ATests.Configuration <> '' then
  begin
    Result.AddPair('configuration', ATests.Configuration);
  end;
  if ATests.Platform <> '' then
  begin
    Result.AddPair('platform', ATests.Platform);
  end;
  Result.AddPair('passed', TJSONNumber.Create(ATests.Passed));
  Result.AddPair('failed', TJSONNumber.Create(ATests.Failed));
  Result.AddPair('errors', TJSONNumber.Create(ATests.Errors));
  Result.AddPair('skipped', TJSONNumber.Create(ATests.Skipped));
  Result.AddPair('durationMs', TJSONNumber.Create(ATests.DurationMs));
  Items := TJSONArray.Create;
  Result.AddPair('failures', Items);
  for Index := 0 to High(ATests.Failures) do
  begin
    if Index >= TAtlasProjectTests.MaxFailures then
    begin
      Break;
    end;
    Item := TJSONObject.Create;
    Items.AddElement(Item);
    Item.AddPair('test', ATests.Failures[Index].Test);
    if ATests.Failures[Index].Message <> '' then
    begin
      Item.AddPair('message', ATests.Failures[Index].Message);
    end;
    if ATests.Failures[Index].FileName <> '' then
    begin
      Item.AddPair('file', ATests.Failures[Index].FileName);
    end;
    if ATests.Failures[Index].Line > 0 then
    begin
      Item.AddPair('line', TJSONNumber.Create(ATests.Failures[Index].Line));
    end;
  end;
  KeepUnknown(Result, AOriginal, TestsKeys);
end;

{ TAtlasProjectRelease }

class function TAtlasProjectRelease.Empty: TAtlasProjectRelease;
begin
  Result := Default(TAtlasProjectRelease);
  Result.Rules := nil;
  Result.Builds := nil;
end;

function TAtlasProjectRelease.VersionOf(const AConfiguration, APlatform: string): string;
var
  Build: TAtlasProjectReleaseBuild;
begin
  Result := '';
  for Build in Builds do
  begin
    if SameText(Build.Configuration, AConfiguration) and SameText(Build.Platform, APlatform) then
    begin
      Exit(Build.Version);
    end;
  end;
end;

procedure TAtlasProjectRelease.Remember(const AConfiguration, APlatform, AVersion: string; AAtUtc: TDateTime);
var
  Entry: TAtlasProjectReleaseBuild;
  Kept: TArray<TAtlasProjectReleaseBuild>;
  Build: TAtlasProjectReleaseBuild;
begin
  Entry.Configuration := AConfiguration;
  Entry.Platform := APlatform;
  Entry.Version := AVersion;
  Entry.At := AAtUtc;
  Kept := nil;
  Kept := Kept + [Entry];
  for Build in Builds do
  begin
    if (Length(Kept) < MaxBuilds) and
      not (SameText(Build.Configuration, AConfiguration) and SameText(Build.Platform, APlatform)) then
    begin
      Kept := Kept + [Build];
    end;
  end;
  Builds := Kept;
  Known := True;
end;

class function TAtlasSummarySections.ReleaseOf(ASection: TJSONObject): TAtlasProjectRelease;
var
  Items: TJSONValue;
  Item: TJSONValue;
  Build: TAtlasProjectReleaseBuild;
begin
  Result := TAtlasProjectRelease.Empty;
  if ASection = nil then
  begin
    Exit;
  end;
  Result.Known := True;
  Result.CheckedAt := SummaryTimeOf(TextOf(ASection, 'checkedAt'));
  Result.Configuration := TextOf(ASection, 'configuration');
  Result.Platform := TextOf(ASection, 'platform');
  Result.Findings := NumberOf(ASection, 'findings', 0);
  Result.Blocked := FlagOf(ASection, 'blocked');
  Items := ASection.GetValue('rules');
  if Items is TJSONArray then
  begin
    for Item in TJSONArray(Items) do
    begin
      if (Item is TJSONString) and (TJSONString(Item).Value <> '') then
      begin
        Result.Rules := Result.Rules + [TJSONString(Item).Value];
      end;
    end;
  end;
  Items := ASection.GetValue('builds');
  if not (Items is TJSONArray) then
  begin
    Exit;
  end;
  for Item in TJSONArray(Items) do
  begin
    if not (Item is TJSONObject) or (Length(Result.Builds) >= TAtlasProjectRelease.MaxBuilds) then
    begin
      Continue;
    end;
    Build := Default(TAtlasProjectReleaseBuild);
    Build.Configuration := TextOf(TJSONObject(Item), 'configuration');
    Build.Platform := TextOf(TJSONObject(Item), 'platform');
    Build.Version := TextOf(TJSONObject(Item), 'version');
    Build.At := SummaryTimeOf(TextOf(TJSONObject(Item), 'at'));
    if Build.Configuration <> '' then
    begin
      Result.Builds := Result.Builds + [Build];
    end;
  end;
end;

/// <summary>Eintrag in "builds" zu AConfiguration/APlatform aus dem gelesenen Text (für unbekannte Felder).</summary>
function OriginalReleaseBuild(AOriginal: TJSONObject; const AConfiguration, APlatform: string): TJSONObject;
var
  Items: TJSONValue;
  Item: TJSONValue;
begin
  Result := nil;
  if AOriginal = nil then
  begin
    Exit;
  end;
  Items := AOriginal.GetValue('builds');
  if not (Items is TJSONArray) then
  begin
    Exit;
  end;
  for Item in TJSONArray(Items) do
  begin
    if (Item is TJSONObject) and SameText(TextOf(TJSONObject(Item), 'configuration'), AConfiguration) and
      SameText(TextOf(TJSONObject(Item), 'platform'), APlatform) then
    begin
      Exit(TJSONObject(Item));
    end;
  end;
end;

class function TAtlasSummarySections.ReleaseJson(const ARelease: TAtlasProjectRelease;
  AOriginal: TJSONObject): TJSONObject;
var
  Items: TJSONArray;
  Item: TJSONObject;
  Rule: string;
  Build: TAtlasProjectReleaseBuild;
begin
  Result := TJSONObject.Create;
  if ARelease.CheckedAt > 0 then
  begin
    AddTime(Result, 'checkedAt', ARelease.CheckedAt);
    Result.AddPair('configuration', ARelease.Configuration);
    Result.AddPair('platform', ARelease.Platform);
    Result.AddPair('findings', TJSONNumber.Create(ARelease.Findings));
    Result.AddPair('blocked', TJSONBool.Create(ARelease.Blocked));
    Items := TJSONArray.Create;
    Result.AddPair('rules', Items);
    for Rule in ARelease.Rules do
    begin
      Items.Add(Rule);
    end;
  end;
  Items := TJSONArray.Create;
  Result.AddPair('builds', Items);
  for Build in ARelease.Builds do
  begin
    Item := TJSONObject.Create;
    Items.AddElement(Item);
    Item.AddPair('configuration', Build.Configuration);
    Item.AddPair('platform', Build.Platform);
    Item.AddPair('version', Build.Version);
    AddTime(Item, 'at', Build.At);
    KeepUnknown(Item, OriginalReleaseBuild(AOriginal, Build.Configuration, Build.Platform), ReleaseBuildKeys);
  end;
  KeepUnknown(Result, AOriginal, ReleaseKeys);
end;

{ TAtlasProjectCi }

class function TAtlasProjectCi.Empty: TAtlasProjectCi;
begin
  Result := Default(TAtlasProjectCi);
  Result.Build := TAtlasCiBuild.Empty;
end;

function TAtlasProjectCi.Matches(const AJob: TAtlasCiJob): Boolean;
begin
  Result := Known and SameText(Provider, AJob.Provider) and SameText(Server, AJob.Server) and
    SameText(Job, AJob.Job) and SameText(Branch, AJob.JobBranch);
end;

function TAtlasProjectCi.HasBuild: Boolean;
begin
  Result := Known and (Build.Number > 0);
end;

class function TAtlasSummarySections.CiOf(ASection: TJSONObject): TAtlasProjectCi;
var
  Items: TJSONValue;
  Item: TJSONValue;
  Failure: TAtlasCiFailure;
begin
  Result := TAtlasProjectCi.Empty;
  if ASection = nil then
  begin
    Exit;
  end;
  Result.Known := True;
  Result.Provider := TextOf(ASection, 'provider');
  Result.Server := TextOf(ASection, 'server');
  Result.Job := TextOf(ASection, 'job');
  Result.Branch := TextOf(ASection, 'branch');
  Result.Attempt := SummaryTimeOf(TextOf(ASection, 'attempt'));
  Result.Error := TAtlasCiBuild.ErrorOf(TextOf(ASection, 'error'));
  Result.At := SummaryTimeOf(TextOf(ASection, 'at'));
  Result.Build.Number := NumberOf(ASection, 'number', 0);
  if Result.Build.Number < 0 then
  begin
    Result.Build.Number := 0;
  end;
  Result.Build.Outcome := TAtlasCiBuild.OutcomeOf(TextOf(ASection, 'result'));
  Result.Build.StartedUtc := SummaryTimeOf(TextOf(ASection, 'started'));
  Result.Build.DurationMs := NumberOf(ASection, 'durationMs', 0);
  Items := ASection.GetValue('failures');
  Result.Build.TestsKnown := (ASection.GetValue('passed') is TJSONNumber) or (Items is TJSONArray);
  Result.Build.Passed := NumberOf(ASection, 'passed', 0);
  Result.Build.Failed := NumberOf(ASection, 'failed', 0);
  Result.Build.Skipped := NumberOf(ASection, 'skipped', 0);
  if not (Items is TJSONArray) then
  begin
    Exit;
  end;
  for Item in TJSONArray(Items) do
  begin
    if not (Item is TJSONObject) or (Length(Result.Build.Failures) >= TAtlasCiBuild.MaxFailures) then
    begin
      Continue;
    end;
    Failure.Test := TextOf(TJSONObject(Item), 'test');
    Failure.Message := TextOf(TJSONObject(Item), 'message');
    if Failure.Test <> '' then
    begin
      Result.Build.Failures := Result.Build.Failures + [Failure];
    end;
  end;
end;

/// <summary>Eintrag in "failures" zu ATest aus dem gelesenen Text (für unbekannte Felder).</summary>
function OriginalCiFailure(AOriginal: TJSONObject; const ATest: string): TJSONObject;
var
  Items: TJSONValue;
  Item: TJSONValue;
begin
  Result := nil;
  if AOriginal = nil then
  begin
    Exit;
  end;
  Items := AOriginal.GetValue('failures');
  if not (Items is TJSONArray) then
  begin
    Exit;
  end;
  for Item in TJSONArray(Items) do
  begin
    if (Item is TJSONObject) and (TextOf(TJSONObject(Item), 'test') = ATest) then
    begin
      Exit(TJSONObject(Item));
    end;
  end;
end;

/// <summary>Fehlgeschlagene Tests des Builds, höchstens TAtlasCiBuild.MaxFailures; unbekannte Felder aus
/// AOriginal (Abschnitt "ci", darf nil sein) bleiben erhalten.</summary>
function CiFailuresJson(const AFailures: TArray<TAtlasCiFailure>; AOriginal: TJSONObject): TJSONArray;
var
  Item: TJSONObject;
  Index: Integer;
begin
  Result := TJSONArray.Create;
  for Index := 0 to Min(High(AFailures), TAtlasCiBuild.MaxFailures - 1) do
  begin
    Item := TJSONObject.Create;
    Result.AddElement(Item);
    Item.AddPair('test', AFailures[Index].Test);
    if AFailures[Index].Message <> '' then
    begin
      Item.AddPair('message', AFailures[Index].Message);
    end;
    KeepUnknown(Item, OriginalCiFailure(AOriginal, AFailures[Index].Test), CiFailureKeys);
  end;
end;

class function TAtlasSummarySections.CiJson(const ACi: TAtlasProjectCi; AOriginal: TJSONObject): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('provider', ACi.Provider);
  Result.AddPair('server', ACi.Server);
  Result.AddPair('job', ACi.Job);
  if ACi.Branch <> '' then
  begin
    Result.AddPair('branch', ACi.Branch);
  end;
  AddTime(Result, 'attempt', ACi.Attempt);
  if ACi.Error <> TAtlasCiFetchError.None then
  begin
    Result.AddPair('error', TAtlasCiBuild.ErrorKey(ACi.Error));
  end;
  AddTime(Result, 'at', ACi.At);
  if ACi.Build.Number > 0 then
  begin
    Result.AddPair('number', TJSONNumber.Create(ACi.Build.Number));
    Result.AddPair('result', TAtlasCiBuild.OutcomeKey(ACi.Build.Outcome));
    AddTime(Result, 'started', ACi.Build.StartedUtc);
    if ACi.Build.DurationMs > 0 then
    begin
      Result.AddPair('durationMs', TJSONNumber.Create(ACi.Build.DurationMs));
    end;
    if ACi.Build.TestsKnown then
    begin
      Result.AddPair('passed', TJSONNumber.Create(ACi.Build.Passed));
      Result.AddPair('failed', TJSONNumber.Create(ACi.Build.Failed));
      Result.AddPair('skipped', TJSONNumber.Create(ACi.Build.Skipped));
      Result.AddPair('failures', CiFailuresJson(ACi.Build.Failures, AOriginal));
    end;
  end;
  KeepUnknown(Result, AOriginal, CiKeys);
end;

end.
