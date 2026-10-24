unit Atlas.Core.Settings.TeamFile.Tests;

// Tests der Projektdatei .atlas (#486): Ort, Lesen aller Abschnitte, Sperre
// für Zugangsdaten und Pfade, fehlerhafte Datei und Vorrang vor den
// persönlichen Einstellungen.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Settings.TeamFile;

type
  [TestFixture]
  TAtlasTeamFileTests = class
  private
    function Parsed(const AText: string): TAtlasTeamSettings;
    function HasIssue(const ATeam: TAtlasTeamSettings; AKind: TAtlasTeamIssueKind; const APath: string): Boolean;
  public
    [Test]
    procedure LocatesFileNextToProject;
    [Test]
    procedure LocatesFileInRepositoryRoot;
    [Test]
    procedure NoFileWithoutRepositoryAbove;
    [Test]
    procedure RootIsRepositoryOrFolder;
    [Test]
    procedure ReadsAllSections;
    [Test]
    procedure TeamPrefixBeatsPersonalSetting;
    [Test]
    procedure BrokenFileIsInvalidWithIssue;
    [Test]
    procedure IgnoresCredentials;
    [Test]
    procedure IgnoresAbsoluteAndOutsidePaths;
    [Test]
    procedure ReportsUnknownKeysWrongTypesAndVersion;
    [Test]
    procedure MergeKeepsTeamFirst;
    [Test]
    procedure SkeletonIsValidWithoutIssues;
    [Test]
    procedure SnippetFolderIsResolved;
    [Test]
    procedure ValuesNameEverySetEntry;
    [Test]
    procedure ReadsDebugDisplayRules;
  end;

implementation

uses
  System.SysUtils;

const
  FileName = 'C:\Repo\App\.atlas';
  Root = 'C:\Repo';

function ExistsIn(const APaths: array of string): TAtlasTeamFileExists;
var
  Paths: TArray<string>;
  Index: Integer;
begin
  SetLength(Paths, Length(APaths));
  for Index := 0 to High(APaths) do
    Paths[Index] := APaths[Index];
  Result :=
    function(const APath: string): Boolean
    var
      Item: string;
    begin
      for Item in Paths do
        if SameText(Item, APath) then
          Exit(True);
      Result := False;
    end;
end;

function TAtlasTeamFileTests.Parsed(const AText: string): TAtlasTeamSettings;
begin
  Result := TAtlasTeamFile.Parse(AText, FileName, Root);
end;

function TAtlasTeamFileTests.HasIssue(const ATeam: TAtlasTeamSettings; AKind: TAtlasTeamIssueKind;
  const APath: string): Boolean;
var
  Issue: TAtlasTeamIssue;
begin
  for Issue in ATeam.Issues do
    if (Issue.Kind = AKind) and (Issue.Path = APath) then
      Exit(True);
  Result := False;
end;

procedure TAtlasTeamFileTests.LocatesFileNextToProject;
begin
  Assert.AreEqual('C:\Repo\App\.atlas', TAtlasTeamFile.Locate('C:\Repo\App',
    ExistsIn(['C:\Repo\App\.atlas', 'C:\Repo\.git', 'C:\Repo\.atlas'])), 'Ordner der .dproj zuerst');
  Assert.AreEqual('C:\Repo\App\.atlas', TAtlasTeamFile.Locate('C:\Repo\App\',
    ExistsIn(['C:\Repo\App\.atlas'])), 'ohne Repository');
end;

procedure TAtlasTeamFileTests.LocatesFileInRepositoryRoot;
begin
  Assert.AreEqual('C:\Repo\.atlas', TAtlasTeamFile.Locate('C:\Repo\Quellen\App',
    ExistsIn(['C:\Repo\.git', 'C:\Repo\.atlas'])));
  Assert.AreEqual('\\srv\daten\Repo\.atlas', TAtlasTeamFile.Locate('\\srv\daten\Repo\App',
    ExistsIn(['\\srv\daten\Repo\.git', '\\srv\daten\Repo\.atlas'])), 'UNC');
end;

procedure TAtlasTeamFileTests.NoFileWithoutRepositoryAbove;
begin
  Assert.AreEqual('', TAtlasTeamFile.Locate('C:\Repo\App', ExistsIn(['C:\Repo\.atlas'])),
    'ohne .git nur der Ordner der .dproj');
  Assert.AreEqual('', TAtlasTeamFile.Locate('C:\Repo\Teil\App',
    ExistsIn(['C:\Repo\.git', 'C:\Repo\Teil\.atlas'])), 'nur Ordner der .dproj und Wurzel');
  Assert.AreEqual('', TAtlasTeamFile.Locate('C:\Repo\App', ExistsIn(['C:\Repo\.git'])));
  Assert.AreEqual('', TAtlasTeamFile.Locate('', ExistsIn(['\.atlas'])));
end;

procedure TAtlasTeamFileTests.RootIsRepositoryOrFolder;
begin
  Assert.AreEqual('C:\Repo', TAtlasTeamFile.RootOf('C:\Repo\a\b', ExistsIn(['C:\Repo\.git', 'C:\.git'])),
    'nächster Ordner mit .git');
  Assert.AreEqual('C:\Projekt', TAtlasTeamFile.RootOf('C:\Projekt\', ExistsIn([])));
end;

procedure TAtlasTeamFileTests.ReadsAllSections;
var
  Team: TAtlasTeamSettings;
begin
  Team := Parsed(
    '{'#13#10 +
    '  // Kommentar'#13#10 +
    '  "version": 1,'#13#10 +
    '  "naming": {"field": "F", "parameter": "A", "local": "", "constant": "c"},'#13#10 +
    '  "snippets": "Vorlagen\\Snippets",'#13#10 +
    '  "formatFunctions": [{"name": "Log", "formatIndex": 0}, {"name": "Trace", "formatIndex": 1}],'#13#10 +
    '  "sqlTargets": ["TMyQuery.SQL", "TMyQuery.SQL"],'#13#10 +
    '  "fileMethods": ["TDateien.Laden"],'#13#10 +
    '  "mainThreadExceptions": ["TLogger.Write"],'#13#10 +
    '  "startProfiles": [{"name": "Demo", "parameters": "-demo /silent", "workingDir": "..\\Bin",'#13#10 +
    '    "host": "$(BDS)\\bin\\bds.exe", "environment": {"MODUS": "demo"}}],'#13#10 +
    '  "ci": {"provider": "jenkins", "url": "https://ci.example.com", "job": "kasse", "multibranch": true},'#13#10 +
    '  "tracker": {"provider": "YouTrack", "url": "https://firma.youtrack.cloud", "project": "ATL"},'#13#10 +
    '}');
  Assert.IsTrue(Team.Valid);
  Assert.IsTrue(Team.Exists);
  Assert.AreEqual(0, Integer(Length(Team.Issues)), 'keine Meldung');
  Assert.AreEqual('C:\Repo\App', Team.Folder);
  Assert.AreEqual('F', Team.Naming[TAtlasNamingKind.Field]);
  Assert.AreEqual('A', Team.Naming[TAtlasNamingKind.Parameter]);
  Assert.IsTrue(Team.HasNaming[TAtlasNamingKind.Local], 'leeres Präfix ist ein Wert');
  // Konstanten für die Prüfregel naming-prefix (#1111).
  Assert.AreEqual('c', Team.Naming[TAtlasNamingKind.Constant]);
  Assert.AreEqual('Vorlagen\Snippets', Team.Snippets);
  Assert.AreEqual(2, Integer(Length(Team.FormatFunctions)));
  Assert.AreEqual('Trace', Team.FormatFunctions[1].Name);
  Assert.AreEqual(1, Team.FormatFunctions[1].FormatIndex);
  Assert.AreEqual(1, Integer(Length(Team.SqlTargets)), 'doppelte Einträge einmal');
  Assert.AreEqual('TDateien.Laden', Team.FileMethods[0]);
  Assert.AreEqual('TLogger.Write', Team.MainThreadExceptions[0]);
  Assert.AreEqual(1, Integer(Length(Team.StartProfiles)));
  Assert.AreEqual('Demo', Team.StartProfiles[0].Name);
  Assert.AreEqual('-demo /silent', Team.StartProfiles[0].Parameters);
  Assert.AreEqual('..\Bin', Team.StartProfiles[0].WorkingDir);
  Assert.AreEqual('$(BDS)\bin\bds.exe', Team.StartProfiles[0].Host);
  Assert.AreEqual('MODUS', Team.StartProfiles[0].Environment[0].Name);
  Assert.AreEqual('demo', Team.StartProfiles[0].Environment[0].Value);
  Assert.IsTrue(Team.Ci.Configured);
  Assert.IsTrue(Team.Ci.Multibranch);
  Assert.AreEqual('kasse', Team.Ci.Job);
  Assert.IsTrue(Team.Tracker.Configured);
  Assert.AreEqual('youtrack', Team.Tracker.Provider);
  Assert.AreEqual('ATL', Team.Tracker.Project);
end;

procedure TAtlasTeamFileTests.TeamPrefixBeatsPersonalSetting;
var
  Team: TAtlasTeamSettings;
begin
  // Akzeptanzkriterium: "field": "F" erzwingt das F-Präfix trotz anderer persönlicher Einstellung.
  Team := Parsed('{"version": 1, "naming": {"field": "F"}}');
  Assert.AreEqual('F', TAtlasTeamFile.Prefix(Team, TAtlasNamingKind.Field, 'f_'));
  Assert.AreEqual('A', TAtlasTeamFile.Prefix(Team, TAtlasNamingKind.Parameter, 'A'), 'nicht gesetzt: persönlich');
  Assert.AreEqual('f_', TAtlasTeamFile.Prefix(TAtlasTeamFile.Empty, TAtlasNamingKind.Field, 'f_'),
    'ohne Projektdatei');
end;

procedure TAtlasTeamFileTests.BrokenFileIsInvalidWithIssue;
var
  Team: TAtlasTeamSettings;
begin
  // Akzeptanzkriterium: Hinweis statt Absturz, es gelten die persönlichen Einstellungen.
  Team := Parsed('{"version": 1, "naming": {"field": "F"');
  Assert.IsFalse(Team.Valid);
  Assert.IsTrue(Team.Exists);
  Assert.IsTrue(HasIssue(Team, TAtlasTeamIssueKind.Syntax, ''));
  Assert.AreEqual('f_', TAtlasTeamFile.Prefix(Team, TAtlasNamingKind.Field, 'f_'));
  Assert.AreEqual(0, Integer(Length(TAtlasTeamFile.Values(Team))));
  Assert.IsFalse(Parsed('[1, 2]').Valid, 'kein Objekt');
  Assert.IsFalse(Parsed('').Valid, 'leer');
  Assert.IsFalse(Parsed('kein json').Valid);
end;

procedure TAtlasTeamFileTests.IgnoresCredentials;
var
  Team: TAtlasTeamSettings;
begin
  Team := Parsed('{"version": 1, "token": "abc",'#13#10 +
    '"ci": {"url": "https://marco:geheim@ci.example.com", "job": "kasse", "apiToken": "x"},'#13#10 +
    '"tracker": {"provider": "github", "url": "https://github.com/firma/kasse", "password": "x"},'#13#10 +
    '"startProfiles": [{"name": "Db", "environment": {"DB_PASSWORD": "geheim"}},'#13#10 +
    '  {"name": "Login", "parameters": "-url=https://ci.example.com/?token=abc"},'#13#10 +
    '  {"name": "Gut", "parameters": "-demo"}],'#13#10 +
    '"extra": {"nested": {"secret": "x"}}}');
  Assert.IsTrue(Team.Valid);
  Assert.IsTrue(HasIssue(Team, TAtlasTeamIssueKind.Credential, 'token'));
  Assert.IsTrue(HasIssue(Team, TAtlasTeamIssueKind.Credential, 'ci.url'));
  Assert.IsTrue(HasIssue(Team, TAtlasTeamIssueKind.Credential, 'ci.apiToken'));
  Assert.IsTrue(HasIssue(Team, TAtlasTeamIssueKind.Credential, 'tracker.password'));
  Assert.IsTrue(HasIssue(Team, TAtlasTeamIssueKind.Credential, 'startProfiles[Db].environment.DB_PASSWORD'));
  Assert.IsTrue(HasIssue(Team, TAtlasTeamIssueKind.Credential, 'startProfiles[Login].parameters'));
  Assert.IsTrue(HasIssue(Team, TAtlasTeamIssueKind.Credential, 'extra.nested.secret'));
  Assert.IsTrue(HasIssue(Team, TAtlasTeamIssueKind.UnknownKey, 'extra'));
  Assert.AreEqual('', Team.Ci.Url, 'Adresse mit Zugangsdaten ignoriert');
  Assert.IsFalse(Team.Ci.Configured);
  Assert.IsTrue(Team.Tracker.Configured, 'der Rest des Trackers gilt');
  Assert.AreEqual(1, Integer(Length(Team.StartProfiles)), 'Profile mit Zugangsdaten entfallen ganz');
  Assert.AreEqual('Gut', Team.StartProfiles[0].Name);
end;

procedure TAtlasTeamFileTests.IgnoresAbsoluteAndOutsidePaths;
var
  Team: TAtlasTeamSettings;
begin
  Team := Parsed('{"version": 1, "snippets": "C:\\Vorlagen",'#13#10 +
    '"startProfiles": [{"name": "Abs", "host": "C:\\Tools\\host.exe"},'#13#10 +
    '  {"name": "Raus", "workingDir": "..\\..\\Anderes"},'#13#10 +
    '  {"name": "Param", "parameters": "-db D:\\Daten\\test.fdb"},'#13#10 +
    '  {"name": "Env", "environment": {"DATEN": "\\\\server\\daten"}},'#13#10 +
    '  {"name": "Innen", "workingDir": "..\\Bin"}]}');
  Assert.IsTrue(HasIssue(Team, TAtlasTeamIssueKind.AbsolutePath, 'snippets'));
  Assert.AreEqual('', Team.Snippets);
  Assert.IsTrue(HasIssue(Team, TAtlasTeamIssueKind.AbsolutePath, 'startProfiles[Abs].host'));
  Assert.IsTrue(HasIssue(Team, TAtlasTeamIssueKind.OutsidePath, 'startProfiles[Raus].workingDir'));
  Assert.IsTrue(HasIssue(Team, TAtlasTeamIssueKind.AbsolutePath, 'startProfiles[Param].parameters'));
  Assert.IsTrue(HasIssue(Team, TAtlasTeamIssueKind.AbsolutePath, 'startProfiles[Env].environment.DATEN'));
  Assert.AreEqual(1, Integer(Length(Team.StartProfiles)));
  Assert.AreEqual('Innen', Team.StartProfiles[0].Name, '..\Bin bleibt im Repository');
  Team := Parsed('{"version": 1, "snippets": "..\\Vorlagen"}');
  Assert.AreEqual('..\Vorlagen', Team.Snippets);
  Assert.IsTrue(HasIssue(TAtlasTeamFile.Parse('{"version": 1, "snippets": "..\\Vorlagen"}', FileName, ''),
    TAtlasTeamIssueKind.OutsidePath, 'snippets'), 'ohne Repository ist der Ordner der Datei die Wurzel');
end;

procedure TAtlasTeamFileTests.ReportsUnknownKeysWrongTypesAndVersion;
var
  Team: TAtlasTeamSettings;
begin
  Team := Parsed('{"$schema": "x", "naming": {"feld": "F", "field": 3, "local": "L-"},'#13#10 +
    '"sqlTargets": "TQuery.SQL", "fileMethods": ["A", 2, ""], "formatFunctions": [{"name": "Log"}],'#13#10 +
    '"ci": {"provider": "teamcity", "url": "https://ci"}, "tracker": {"provider": "github", "url": "ci"}}');
  Assert.IsTrue(Team.Valid, 'Fehler in Werten machen die Datei nicht ungültig');
  Assert.IsTrue(HasIssue(Team, TAtlasTeamIssueKind.Version, 'version'), 'Version fehlt');
  Assert.AreEqual(1, Team.Version);
  Assert.IsTrue(HasIssue(Team, TAtlasTeamIssueKind.UnknownKey, 'naming.feld'));
  Assert.IsTrue(HasIssue(Team, TAtlasTeamIssueKind.WrongType, 'naming.field'));
  Assert.IsTrue(HasIssue(Team, TAtlasTeamIssueKind.InvalidValue, 'naming.local'));
  Assert.IsFalse(Team.HasNaming[TAtlasNamingKind.Field]);
  Assert.IsTrue(HasIssue(Team, TAtlasTeamIssueKind.WrongType, 'sqlTargets'));
  Assert.IsTrue(HasIssue(Team, TAtlasTeamIssueKind.WrongType, 'fileMethods[1]'));
  Assert.IsTrue(HasIssue(Team, TAtlasTeamIssueKind.InvalidValue, 'fileMethods[2]'));
  Assert.AreEqual(1, Integer(Length(Team.FileMethods)));
  Assert.IsTrue(HasIssue(Team, TAtlasTeamIssueKind.InvalidValue, 'formatFunctions[0]'));
  Assert.IsTrue(HasIssue(Team, TAtlasTeamIssueKind.InvalidValue, 'ci.provider'));
  Assert.IsFalse(Team.Ci.Configured);
  Assert.IsTrue(HasIssue(Team, TAtlasTeamIssueKind.InvalidValue, 'tracker.url'));
  Assert.IsFalse(HasIssue(Team, TAtlasTeamIssueKind.UnknownKey, '$schema'));
  Team := Parsed('{"version": 2, "naming": {"field": "F"}}');
  Assert.IsTrue(HasIssue(Team, TAtlasTeamIssueKind.Version, 'version'), 'neuer als bekannt');
  Assert.AreEqual(2, Team.Version);
  Assert.AreEqual('F', Team.Naming[TAtlasNamingKind.Field], 'Bekanntes gilt weiter');
end;

procedure TAtlasTeamFileTests.MergeKeepsTeamFirst;
var
  Names: TArray<string>;
  Functions: TArray<TAtlasFormatFunction>;
  Team, Personal, Merged: TArray<TAtlasStartProfile>;
begin
  Names := TAtlasTeamFile.MergeNames(['TQuery.SQL', 'TTeam.Sql'], ['tquery.sql', 'TMein.Sql']);
  Assert.AreEqual(3, Integer(Length(Names)));
  Assert.AreEqual('TQuery.SQL', Names[0]);
  Assert.AreEqual('TMein.Sql', Names[2]);
  Functions := TAtlasTeamFile.MergeFormatFunctions([TAtlasFormatFunction.Create('Log', 1)],
    [TAtlasFormatFunction.Create('log', 0), TAtlasFormatFunction.Create('Trace', 2)]);
  Assert.AreEqual(2, Integer(Length(Functions)));
  Assert.AreEqual(1, Functions[0].FormatIndex, 'Index aus der Projektdatei');
  SetLength(Team, 1);
  Team[0].Name := 'Demo';
  Team[0].Parameters := '-team';
  SetLength(Personal, 2);
  Personal[0].Name := 'demo';
  Personal[0].Parameters := '-mein';
  Personal[1].Name := 'Lokal';
  Merged := TAtlasTeamFile.MergeStartProfiles(Team, Personal);
  Assert.AreEqual(2, Integer(Length(Merged)));
  Assert.AreEqual('-team', Merged[0].Parameters);
  Assert.AreEqual('Lokal', Merged[1].Name);
end;

procedure TAtlasTeamFileTests.SkeletonIsValidWithoutIssues;
var
  Team: TAtlasTeamSettings;
begin
  Team := Parsed(TAtlasTeamFile.Skeleton);
  Assert.IsTrue(Team.Valid);
  Assert.AreEqual(0, Integer(Length(Team.Issues)));
  Assert.IsFalse(Team.HasValues, 'Beispiele stehen nur als Kommentar');
  Assert.Contains(TAtlasTeamFile.Skeleton, '"version": 1');
end;

procedure TAtlasTeamFileTests.SnippetFolderIsResolved;
begin
  Assert.AreEqual('C:\Repo\Vorlagen\Snippets', Parsed('{"version": 1, "snippets": "../Vorlagen/./Snippets/"}').SnippetFolder);
  Assert.AreEqual('', Parsed('{"version": 1}').SnippetFolder);
  Assert.AreEqual('\\srv\daten\Repo\Vorlagen', TAtlasTeamFile.Combine('\\srv\daten\Repo\App', '..\Vorlagen'));
end;

procedure TAtlasTeamFileTests.ValuesNameEverySetEntry;
var
  Values: TArray<TAtlasTeamValue>;
begin
  Values := TAtlasTeamFile.Values(Parsed('{"version": 1, "naming": {"field": "F"}, "sqlTargets": ["A", "B"],' +
    '"ci": {"url": "https://ci.example.com", "job": "kasse"}}'));
  Assert.AreEqual(3, Integer(Length(Values)));
  Assert.AreEqual('naming.field', Values[0].Key);
  Assert.AreEqual('"F"', Values[0].Value);
  Assert.AreEqual('A, B', Values[1].Value);
  Assert.AreEqual('ci', Values[2].Key);
  Assert.Contains(Values[2].Value, 'jenkins');
  Assert.IsFalse(TAtlasTeamFile.Empty.HasValues);
end;

procedure TAtlasTeamFileTests.ReadsDebugDisplayRules;
var
  Team: TAtlasTeamSettings;
begin
  Team := Parsed('{"version": 1, "debugDisplayRules": {' +
    '"FireDAC.Comp.Client.TFDConnection": "{ConnectionName} ({DriverName})",' +
    '"TKunde": {"template": "{Name}", "children": ["Name", "Ort", "name"]},' +
    '"TPunkt": {"children": "X, Y"},' +
    '"TKaputt": "{Name",' +
    '"TLeer": {},' +
    '"TZahl": 1,' +
    '"TExtra": {"template": "{A}", "farbe": "rot"}}}');
  Assert.AreEqual(4, Integer(Length(Team.DisplayRules)));
  Assert.AreEqual('FireDAC.Comp.Client.TFDConnection', Team.DisplayRules[0].TypeName);
  Assert.AreEqual('{ConnectionName} ({DriverName})', Team.DisplayRules[0].Template);
  Assert.AreEqual('Name|Ort', string.Join('|', Team.DisplayRules[1].Children));
  Assert.AreEqual('', Team.DisplayRules[2].Template);
  Assert.AreEqual('X|Y', string.Join('|', Team.DisplayRules[2].Children));
  Assert.AreEqual('TExtra', Team.DisplayRules[3].TypeName);
  Assert.IsTrue(HasIssue(Team, TAtlasTeamIssueKind.InvalidValue, 'debugDisplayRules.TKaputt'));
  Assert.IsTrue(HasIssue(Team, TAtlasTeamIssueKind.InvalidValue, 'debugDisplayRules.TLeer'));
  Assert.IsTrue(HasIssue(Team, TAtlasTeamIssueKind.WrongType, 'debugDisplayRules.TZahl'));
  Assert.IsTrue(HasIssue(Team, TAtlasTeamIssueKind.UnknownKey, 'debugDisplayRules.TExtra.farbe'));
  Assert.AreEqual('debugDisplayRules', TAtlasTeamFile.Values(Team)[0].Key);
  Assert.IsTrue(Parsed('{"version": 1, "debugDisplayRules": []}').Issues[0].Kind = TAtlasTeamIssueKind.WrongType);
  Assert.Contains(TAtlasTeamFile.Skeleton, '"debugDisplayRules"');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTeamFileTests);

end.
