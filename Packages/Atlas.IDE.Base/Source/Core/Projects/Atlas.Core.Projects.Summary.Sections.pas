unit Atlas.Core.Projects.Summary.Sections;

// Abschnitte "setup" (#759), "tests" (#69, mit den langsamsten Tests #1772),
// "release" (#533) und "ci" (#763)
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
    cMaxFindings = 50;
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

  /// <summary>Einer der langsamsten Tests des letzten Laufs (#1772).</summary>
  TAtlasProjectSlowTest = record
    /// <summary>Voller Name aus dem Bericht von DUnitX (Unit.Fixture.Methode[.Fall]).</summary>
    Test: string;
    /// <summary>Datei des Tests (absolut); '' ohne Fundstelle.</summary>
    FileName: string;
    /// <summary>Zeile ab 1; 0 = ohne.</summary>
    Line: Integer;
    DurationMs: Integer;
  end;

  /// <summary>Letzter DUnitX-Lauf aus der IDE (#69), Grundlage der Karte Tests (#763).</summary>
  TAtlasProjectTests = record
  public const
    /// <summary>Höchstens so viele fehlgeschlagene Tests stehen in der Datei.</summary>
    cMaxFailures = 50;
    /// <summary>So viele langsamste Tests stehen in der Datei (#1772).</summary>
    cMaxSlowest = 5;
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
    /// <summary>Die langsamsten Tests, der langsamste zuerst; höchstens cMaxSlowest (#1772).</summary>
    Slowest: TArray<TAtlasProjectSlowTest>;
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
    cMaxBuilds = 20;
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
  private
    /// <summary>Liste "slowest" des Abschnitts "tests" (#1772).</summary>
    class function SlowestOf(ASection: TJSONObject): TArray<TAtlasProjectSlowTest>; static;
    class function SlowestJson(const ASlowest: TArray<TAtlasProjectSlowTest>): TJSONArray; static;
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
  System.Generics.Collections,
  System.SysUtils,
  System.Math,
  Atlas.Core.Projects.Summary.Json,
  Atlas.Text.Json;

const
  cSetupKeys: array[0..2] of string = ('dismissed', 'dismissedAt', 'paths');
  cTestsKeys: array[0..10] of string = ('at', 'project', 'configuration', 'platform', 'passed', 'failed', 'errors',
    'skipped', 'durationMs', 'failures', 'slowest');
  cReleaseKeys: array[0..6] of string = ('checkedAt', 'configuration', 'platform', 'findings', 'blocked', 'rules',
    'builds');
  cCiKeys: array[0..14] of string = ('provider', 'server', 'job', 'branch', 'attempt', 'error', 'at', 'number',
    'result', 'started', 'durationMs', 'passed', 'failed', 'skipped', 'failures');
  cCiFailureKeys: array[0..1] of string = ('test', 'message');
  cReleaseBuildKeys: array[0..3] of string = ('configuration', 'platform', 'version', 'at');
  cPathsKeys: array[0..10] of string = ('at', 'files', 'unreadable', 'missingUnits', 'undefinedDefines', 'units',
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
  mIndex: Integer;
  mItem: TJSONValue;
  mFinding: TAtlasSetupFinding;
begin
  Result := nil;
  if not (AValue is TJSONArray) then
  begin
    Exit;
  end;
  for mIndex := 0 to TJSONArray(AValue).Count - 1 do
  begin
    mItem := TJSONArray(AValue).Items[mIndex];
    if not (mItem is TJSONObject) then
    begin
      Continue;
    end;
    mFinding.Name := TJsonRead.Text(TJSONObject(mItem), 'name');
    mFinding.FileName := TJsonRead.Text(TJSONObject(mItem), 'file');
    mFinding.Line := TJsonRead.IntOr(TJSONObject(mItem), 'line', 0);
    mFinding.Count := TJsonRead.IntOr(TJSONObject(mItem), 'count', 1);
    mFinding.Uncertain := TJsonRead.Flag(TJSONObject(mItem), 'uncertain');
    mFinding.Note := TJsonRead.Text(TJSONObject(mItem), 'note');
    mFinding.Project := '';
    if (mFinding.Name <> '') and (Length(Result) < TAtlasProjectSetup.cMaxFindings) then
    begin
      Result := Result + [mFinding];
    end;
  end;
end;

function SetupFindingsJson(const AFindings: TArray<TAtlasSetupFinding>): TJSONArray;
var
  mIndex: Integer;
  mItem: TJSONObject;
begin
  Result := TJSONArray.Create;
  for mIndex := 0 to High(AFindings) do
  begin
    if mIndex >= TAtlasProjectSetup.cMaxFindings then
    begin
      Break;
    end;
    mItem := TJSONObject.Create;
    Result.AddElement(mItem);
    mItem.AddPair('name', AFindings[mIndex].Name);
    if AFindings[mIndex].FileName <> '' then
    begin
      mItem.AddPair('file', AFindings[mIndex].FileName);
    end;
    if AFindings[mIndex].Line > 0 then
    begin
      mItem.AddPair('line', TJSONNumber.Create(AFindings[mIndex].Line));
    end;
    mItem.AddPair('count', TJSONNumber.Create(AFindings[mIndex].Count));
    if AFindings[mIndex].Uncertain then
    begin
      mItem.AddPair('uncertain', TJSONBool.Create(True));
    end;
    if AFindings[mIndex].Note <> '' then
    begin
      mItem.AddPair('note', AFindings[mIndex].Note);
    end;
  end;
end;

/// <summary>Texte aus einem Array von Zeichenketten; anderes (auch Zahlen) fällt weg.</summary>
function TextsOfSetup(AValue: TJSONValue): TArray<string>;
var
  mIndex: Integer;
  mItem: TJSONValue;
begin
  Result := nil;
  if not (AValue is TJSONArray) then
  begin
    Exit;
  end;
  for mIndex := 0 to TJSONArray(AValue).Count - 1 do
  begin
    mItem := TJSONArray(AValue).Items[mIndex];
    // TJSONNumber erbt von TJSONString.
    if (mItem is TJSONString) and not (mItem is TJSONNumber) and (mItem.Value <> '') then
    begin
      Result := Result + [mItem.Value];
    end;
  end;
end;

/// <summary>Abschnitt "setup"; leer ohne Abschnitt.</summary>
class function TAtlasSummarySections.SetupOf(ASection: TJSONObject): TAtlasProjectSetup;
var
  mPaths: TJSONObject;
begin
  Result := TAtlasProjectSetup.Empty;
  if ASection = nil then
  begin
    Exit;
  end;
  Result.Known := True;
  Result.Dismissed := TJsonRead.Flag(ASection, 'dismissed');
  Result.DismissedAt := SummaryTimeOf(TJsonRead.Text(ASection, 'dismissedAt'));
  mPaths := TJsonRead.Obj(ASection, 'paths');
  if mPaths = nil then
  begin
    Exit;
  end;
  Result.Checked := True;
  Result.CheckedAt := SummaryTimeOf(TJsonRead.Text(mPaths, 'at'));
  Result.Files := TJsonRead.IntOr(mPaths, 'files', 0);
  Result.Unreadable := TJsonRead.IntOr(mPaths, 'unreadable', 0);
  Result.MissingUnits := SetupFindingsOf(mPaths.GetValue('units'));
  Result.UndefinedDefines := SetupFindingsOf(mPaths.GetValue('defines'));
  Result.Hints := SetupFindingsOf(mPaths.GetValue('hints'));
  // Die Zähler sind nie kleiner als die gespeicherten Funde.
  Result.MissingUnitCount := TJsonRead.IntOr(mPaths, 'missingUnits', 0);
  if Result.MissingUnitCount < Length(Result.MissingUnits) then
  begin
    Result.MissingUnitCount := Length(Result.MissingUnits);
  end;
  Result.UndefinedDefineCount := TJsonRead.IntOr(mPaths, 'undefinedDefines', 0);
  if Result.UndefinedDefineCount < Length(Result.UndefinedDefines) then
  begin
    Result.UndefinedDefineCount := Length(Result.UndefinedDefines);
  end;
  // Unsichere nie mehr als alle.
  Result.UncertainUnitCount := TJsonRead.IntOr(mPaths, 'uncertainUnits', 0);
  if Result.UncertainUnitCount > Result.MissingUnitCount then
  begin
    Result.UncertainUnitCount := Result.MissingUnitCount;
  end;
  Result.UncertainDefineCount := TJsonRead.IntOr(mPaths, 'uncertainDefines', 0);
  if Result.UncertainDefineCount > Result.UndefinedDefineCount then
  begin
    Result.UncertainDefineCount := Result.UndefinedDefineCount;
  end;
  Result.SkippedMacros := TextsOfSetup(mPaths.GetValue('skippedMacros'));
end;

class function TAtlasSummarySections.SetupJson(const ASetup: TAtlasProjectSetup; AOriginal: TJSONObject): TJSONObject;
var
  mPaths: TJSONObject;
  mMacros: TJSONArray;
  mMacro: string;
begin
  Result := TJSONObject.Create;
  if ASetup.Dismissed then
  begin
    Result.AddPair('dismissed', TJSONBool.Create(True));
    AddTime(Result, 'dismissedAt', ASetup.DismissedAt);
  end;
  if ASetup.Checked then
  begin
    mPaths := TJSONObject.Create;
    Result.AddPair('paths', mPaths);
    AddTime(mPaths, 'at', ASetup.CheckedAt);
    mPaths.AddPair('files', TJSONNumber.Create(ASetup.Files));
    mPaths.AddPair('unreadable', TJSONNumber.Create(ASetup.Unreadable));
    mPaths.AddPair('missingUnits', TJSONNumber.Create(ASetup.MissingUnitCount));
    mPaths.AddPair('undefinedDefines', TJSONNumber.Create(ASetup.UndefinedDefineCount));
    if ASetup.UncertainUnitCount > 0 then
    begin
      mPaths.AddPair('uncertainUnits', TJSONNumber.Create(ASetup.UncertainUnitCount));
    end;
    if ASetup.UncertainDefineCount > 0 then
    begin
      mPaths.AddPair('uncertainDefines', TJSONNumber.Create(ASetup.UncertainDefineCount));
    end;
    if Length(ASetup.SkippedMacros) > 0 then
    begin
      mMacros := TJSONArray.Create;
      mPaths.AddPair('skippedMacros', mMacros);
      for mMacro in ASetup.SkippedMacros do
      begin
        mMacros.Add(mMacro);
      end;
    end;
    mPaths.AddPair('units', SetupFindingsJson(ASetup.MissingUnits));
    mPaths.AddPair('defines', SetupFindingsJson(ASetup.UndefinedDefines));
    if Length(ASetup.Hints) > 0 then
    begin
      mPaths.AddPair('hints', SetupFindingsJson(ASetup.Hints));
    end;
    KeepUnknown(mPaths, TJsonRead.Obj(AOriginal, 'paths'), cPathsKeys);
  end;
  KeepUnknown(Result, AOriginal, cSetupKeys);
end;

{ TAtlasProjectTests }

class function TAtlasProjectTests.Empty: TAtlasProjectTests;
begin
  Result := Default(TAtlasProjectTests);
  Result.Failures := nil;
  Result.Slowest := nil;
end;

function TAtlasProjectTests.FailedTests: TArray<string>;
var
  mFailure: TAtlasProjectTestFailure;
  mName: string;
  mSeen: Boolean;
begin
  Result := nil;
  for mFailure in Failures do
  begin
    if mFailure.Test = '' then
    begin
      Continue;
    end;
    mSeen := False;
    for mName in Result do
    begin
      if SameText(mName, mFailure.Test) then
      begin
        mSeen := True;
      end;
    end;
    if not mSeen then
    begin
      Result := Result + [mFailure.Test];
    end;
  end;
end;

function TAtlasProjectTests.Total: Integer;
begin
  Result := Passed + Failed + Errors + Skipped;
end;

class function TAtlasSummarySections.TestsOf(ASection: TJSONObject): TAtlasProjectTests;
var
  mItems: TJSONValue;
  mItem: TJSONValue;
  mFailure: TAtlasProjectTestFailure;
begin
  Result := TAtlasProjectTests.Empty;
  if ASection = nil then
  begin
    Exit;
  end;
  Result.Known := True;
  Result.At := SummaryTimeOf(TJsonRead.Text(ASection, 'at'));
  Result.Project := TJsonRead.Text(ASection, 'project');
  Result.Configuration := TJsonRead.Text(ASection, 'configuration');
  Result.Platform := TJsonRead.Text(ASection, 'platform');
  Result.Passed := TJsonRead.IntOr(ASection, 'passed', 0);
  Result.Failed := TJsonRead.IntOr(ASection, 'failed', 0);
  Result.Errors := TJsonRead.IntOr(ASection, 'errors', 0);
  Result.Skipped := TJsonRead.IntOr(ASection, 'skipped', 0);
  Result.DurationMs := TJsonRead.IntOr(ASection, 'durationMs', 0);
  Result.Slowest := SlowestOf(ASection);
  mItems := ASection.GetValue('failures');
  if not (mItems is TJSONArray) then
  begin
    Exit;
  end;
  for mItem in TJSONArray(mItems) do
  begin
    if not (mItem is TJSONObject) or (Length(Result.Failures) >= TAtlasProjectTests.cMaxFailures) then
    begin
      Continue;
    end;
    mFailure := Default(TAtlasProjectTestFailure);
    mFailure.Test := TJsonRead.Text(TJSONObject(mItem), 'test');
    mFailure.Message := TJsonRead.Text(TJSONObject(mItem), 'message');
    mFailure.FileName := TJsonRead.Text(TJSONObject(mItem), 'file');
    mFailure.Line := TJsonRead.IntOr(TJSONObject(mItem), 'line', 0);
    if mFailure.Test <> '' then
    begin
      Result.Failures := Result.Failures + [mFailure];
    end;
  end;
end;

class function TAtlasSummarySections.TestsJson(const ATests: TAtlasProjectTests; AOriginal: TJSONObject): TJSONObject;
var
  mItems: TJSONArray;
  mItem: TJSONObject;
  mIndex: Integer;
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
  mItems := TJSONArray.Create;
  Result.AddPair('failures', mItems);
  for mIndex := 0 to High(ATests.Failures) do
  begin
    if mIndex >= TAtlasProjectTests.cMaxFailures then
    begin
      Break;
    end;
    mItem := TJSONObject.Create;
    mItems.AddElement(mItem);
    mItem.AddPair('test', ATests.Failures[mIndex].Test);
    if ATests.Failures[mIndex].Message <> '' then
    begin
      mItem.AddPair('message', ATests.Failures[mIndex].Message);
    end;
    if ATests.Failures[mIndex].FileName <> '' then
    begin
      mItem.AddPair('file', ATests.Failures[mIndex].FileName);
    end;
    if ATests.Failures[mIndex].Line > 0 then
    begin
      mItem.AddPair('line', TJSONNumber.Create(ATests.Failures[mIndex].Line));
    end;
  end;
  if Length(ATests.Slowest) > 0 then
  begin
    Result.AddPair('slowest', SlowestJson(ATests.Slowest));
  end;
  KeepUnknown(Result, AOriginal, cTestsKeys);
end;

class function TAtlasSummarySections.SlowestOf(ASection: TJSONObject): TArray<TAtlasProjectSlowTest>;
var
  mItems: TJSONValue;
  mItem: TJSONValue;
  mSlow: TAtlasProjectSlowTest;
begin
  Result := nil;
  mItems := ASection.GetValue('slowest');
  if not (mItems is TJSONArray) then
  begin
    Exit;
  end;
  for mItem in TJSONArray(mItems) do
  begin
    if not (mItem is TJSONObject) or (Length(Result) >= TAtlasProjectTests.cMaxSlowest) then
    begin
      Continue;
    end;
    mSlow := Default(TAtlasProjectSlowTest);
    mSlow.Test := TJsonRead.Text(TJSONObject(mItem), 'test');
    mSlow.FileName := TJsonRead.Text(TJSONObject(mItem), 'file');
    mSlow.Line := TJsonRead.IntOr(TJSONObject(mItem), 'line', 0);
    mSlow.DurationMs := TJsonRead.IntOr(TJSONObject(mItem), 'durationMs', 0);
    if mSlow.Test <> '' then
    begin
      Result := Result + [mSlow];
    end;
  end;
end;

class function TAtlasSummarySections.SlowestJson(const ASlowest: TArray<TAtlasProjectSlowTest>): TJSONArray;
var
  mItem: TJSONObject;
  mIndex: Integer;
begin
  Result := TJSONArray.Create;
  for mIndex := 0 to Min(High(ASlowest), TAtlasProjectTests.cMaxSlowest - 1) do
  begin
    mItem := TJSONObject.Create;
    Result.AddElement(mItem);
    mItem.AddPair('test', ASlowest[mIndex].Test);
    if ASlowest[mIndex].FileName <> '' then
    begin
      mItem.AddPair('file', ASlowest[mIndex].FileName);
    end;
    if ASlowest[mIndex].Line > 0 then
    begin
      mItem.AddPair('line', TJSONNumber.Create(ASlowest[mIndex].Line));
    end;
    mItem.AddPair('durationMs', TJSONNumber.Create(ASlowest[mIndex].DurationMs));
  end;
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
  mBuild: TAtlasProjectReleaseBuild;
begin
  Result := '';
  for mBuild in Builds do
  begin
    if SameText(mBuild.Configuration, AConfiguration) and SameText(mBuild.Platform, APlatform) then
    begin
      Exit(mBuild.Version);
    end;
  end;
end;

procedure TAtlasProjectRelease.Remember(const AConfiguration, APlatform, AVersion: string; AAtUtc: TDateTime);
var
  mEntry: TAtlasProjectReleaseBuild;
  mKept: TArray<TAtlasProjectReleaseBuild>;
  mBuild: TAtlasProjectReleaseBuild;
begin
  mEntry.Configuration := AConfiguration;
  mEntry.Platform := APlatform;
  mEntry.Version := AVersion;
  mEntry.At := AAtUtc;
  mKept := nil;
  mKept := mKept + [mEntry];
  for mBuild in Builds do
  begin
    if (Length(mKept) < cMaxBuilds) and
      not (SameText(mBuild.Configuration, AConfiguration) and SameText(mBuild.Platform, APlatform)) then
    begin
      mKept := mKept + [mBuild];
    end;
  end;
  Builds := mKept;
  Known := True;
end;

class function TAtlasSummarySections.ReleaseOf(ASection: TJSONObject): TAtlasProjectRelease;
var
  mItems: TJSONValue;
  mItem: TJSONValue;
  mBuild: TAtlasProjectReleaseBuild;
begin
  Result := TAtlasProjectRelease.Empty;
  if ASection = nil then
  begin
    Exit;
  end;
  Result.Known := True;
  Result.CheckedAt := SummaryTimeOf(TJsonRead.Text(ASection, 'checkedAt'));
  Result.Configuration := TJsonRead.Text(ASection, 'configuration');
  Result.Platform := TJsonRead.Text(ASection, 'platform');
  Result.Findings := TJsonRead.IntOr(ASection, 'findings', 0);
  Result.Blocked := TJsonRead.Flag(ASection, 'blocked');
  mItems := ASection.GetValue('rules');
  if mItems is TJSONArray then
  begin
    for mItem in TJSONArray(mItems) do
    begin
      if (mItem is TJSONString) and (TJSONString(mItem).Value <> '') then
      begin
        Result.Rules := Result.Rules + [TJSONString(mItem).Value];
      end;
    end;
  end;
  mItems := ASection.GetValue('builds');
  if not (mItems is TJSONArray) then
  begin
    Exit;
  end;
  for mItem in TJSONArray(mItems) do
  begin
    if not (mItem is TJSONObject) or (Length(Result.Builds) >= TAtlasProjectRelease.cMaxBuilds) then
    begin
      Continue;
    end;
    mBuild := Default(TAtlasProjectReleaseBuild);
    mBuild.Configuration := TJsonRead.Text(TJSONObject(mItem), 'configuration');
    mBuild.Platform := TJsonRead.Text(TJSONObject(mItem), 'platform');
    mBuild.Version := TJsonRead.Text(TJSONObject(mItem), 'version');
    mBuild.At := SummaryTimeOf(TJsonRead.Text(TJSONObject(mItem), 'at'));
    if mBuild.Configuration <> '' then
    begin
      Result.Builds := Result.Builds + [mBuild];
    end;
  end;
end;

/// <summary>Eintrag in "builds" zu AConfiguration/APlatform aus dem gelesenen Text (für unbekannte Felder).</summary>
function OriginalReleaseBuild(AOriginal: TJSONObject; const AConfiguration, APlatform: string): TJSONObject;
var
  mItems: TJSONValue;
  mItem: TJSONValue;
begin
  Result := nil;
  if AOriginal = nil then
  begin
    Exit;
  end;
  mItems := AOriginal.GetValue('builds');
  if not (mItems is TJSONArray) then
  begin
    Exit;
  end;
  for mItem in TJSONArray(mItems) do
  begin
    if (mItem is TJSONObject) and SameText(TJsonRead.Text(TJSONObject(mItem), 'configuration'), AConfiguration) and
      SameText(TJsonRead.Text(TJSONObject(mItem), 'platform'), APlatform) then
    begin
      Exit(TJSONObject(mItem));
    end;
  end;
end;

class function TAtlasSummarySections.ReleaseJson(const ARelease: TAtlasProjectRelease;
  AOriginal: TJSONObject): TJSONObject;
var
  mItems: TJSONArray;
  mItem: TJSONObject;
  mRule: string;
  mBuild: TAtlasProjectReleaseBuild;
begin
  Result := TJSONObject.Create;
  if ARelease.CheckedAt > 0 then
  begin
    AddTime(Result, 'checkedAt', ARelease.CheckedAt);
    Result.AddPair('configuration', ARelease.Configuration);
    Result.AddPair('platform', ARelease.Platform);
    Result.AddPair('findings', TJSONNumber.Create(ARelease.Findings));
    Result.AddPair('blocked', TJSONBool.Create(ARelease.Blocked));
    mItems := TJSONArray.Create;
    Result.AddPair('rules', mItems);
    for mRule in ARelease.Rules do
    begin
      mItems.Add(mRule);
    end;
  end;
  mItems := TJSONArray.Create;
  Result.AddPair('builds', mItems);
  for mBuild in ARelease.Builds do
  begin
    mItem := TJSONObject.Create;
    mItems.AddElement(mItem);
    mItem.AddPair('configuration', mBuild.Configuration);
    mItem.AddPair('platform', mBuild.Platform);
    mItem.AddPair('version', mBuild.Version);
    AddTime(mItem, 'at', mBuild.At);
    KeepUnknown(mItem, OriginalReleaseBuild(AOriginal, mBuild.Configuration, mBuild.Platform), cReleaseBuildKeys);
  end;
  KeepUnknown(Result, AOriginal, cReleaseKeys);
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
  mItems: TJSONValue;
  mItem: TJSONValue;
  mFailure: TAtlasCiFailure;
begin
  Result := TAtlasProjectCi.Empty;
  if ASection = nil then
  begin
    Exit;
  end;
  Result.Known := True;
  Result.Provider := TJsonRead.Text(ASection, 'provider');
  Result.Server := TJsonRead.Text(ASection, 'server');
  Result.Job := TJsonRead.Text(ASection, 'job');
  Result.Branch := TJsonRead.Text(ASection, 'branch');
  Result.Attempt := SummaryTimeOf(TJsonRead.Text(ASection, 'attempt'));
  Result.Error := TAtlasCiBuild.ErrorOf(TJsonRead.Text(ASection, 'error'));
  Result.At := SummaryTimeOf(TJsonRead.Text(ASection, 'at'));
  Result.Build.Number := TJsonRead.IntOr(ASection, 'number', 0);
  if Result.Build.Number < 0 then
  begin
    Result.Build.Number := 0;
  end;
  Result.Build.Outcome := TAtlasCiBuild.OutcomeOf(TJsonRead.Text(ASection, 'result'));
  Result.Build.StartedUtc := SummaryTimeOf(TJsonRead.Text(ASection, 'started'));
  Result.Build.DurationMs := TJsonRead.IntOr(ASection, 'durationMs', 0);
  mItems := ASection.GetValue('failures');
  Result.Build.TestsKnown := (ASection.GetValue('passed') is TJSONNumber) or (mItems is TJSONArray);
  Result.Build.Passed := TJsonRead.IntOr(ASection, 'passed', 0);
  Result.Build.Failed := TJsonRead.IntOr(ASection, 'failed', 0);
  Result.Build.Skipped := TJsonRead.IntOr(ASection, 'skipped', 0);
  if not (mItems is TJSONArray) then
  begin
    Exit;
  end;
  for mItem in TJSONArray(mItems) do
  begin
    if not (mItem is TJSONObject) or (Length(Result.Build.Failures) >= TAtlasCiBuild.cMaxFailures) then
    begin
      Continue;
    end;
    mFailure.Test := TJsonRead.Text(TJSONObject(mItem), 'test');
    mFailure.Message := TJsonRead.Text(TJSONObject(mItem), 'message');
    if mFailure.Test <> '' then
    begin
      Result.Build.Failures := Result.Build.Failures + [mFailure];
    end;
  end;
end;

/// <summary>Eintrag in "failures" zu ATest aus dem gelesenen Text (für unbekannte Felder).</summary>
function OriginalCiFailure(AOriginal: TJSONObject; const ATest: string): TJSONObject;
var
  mItems: TJSONValue;
  mItem: TJSONValue;
begin
  Result := nil;
  if AOriginal = nil then
  begin
    Exit;
  end;
  mItems := AOriginal.GetValue('failures');
  if not (mItems is TJSONArray) then
  begin
    Exit;
  end;
  for mItem in TJSONArray(mItems) do
  begin
    if (mItem is TJSONObject) and (TJsonRead.Text(TJSONObject(mItem), 'test') = ATest) then
    begin
      Exit(TJSONObject(mItem));
    end;
  end;
end;

/// <summary>Fehlgeschlagene Tests des Builds, höchstens TAtlasCiBuild.cMaxFailures; unbekannte Felder aus
/// AOriginal (Abschnitt "ci", darf nil sein) bleiben erhalten.</summary>
function CiFailuresJson(const AFailures: TArray<TAtlasCiFailure>; AOriginal: TJSONObject): TJSONArray;
var
  mItem: TJSONObject;
  mIndex: Integer;
begin
  Result := TJSONArray.Create;
  for mIndex := 0 to Min(High(AFailures), TAtlasCiBuild.cMaxFailures - 1) do
  begin
    mItem := TJSONObject.Create;
    Result.AddElement(mItem);
    mItem.AddPair('test', AFailures[mIndex].Test);
    if AFailures[mIndex].Message <> '' then
    begin
      mItem.AddPair('message', AFailures[mIndex].Message);
    end;
    KeepUnknown(mItem, OriginalCiFailure(AOriginal, AFailures[mIndex].Test), cCiFailureKeys);
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
  KeepUnknown(Result, AOriginal, cCiKeys);
end;

end.
