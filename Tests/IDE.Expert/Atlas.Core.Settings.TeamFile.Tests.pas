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
    procedure LocatesFileInFolderBetweenProjectAndRoot;
    [Test]
    procedure LocatesFileInSubversionRoot;
    [Test]
    procedure LocatesFileNextToProjectGroup;
    [Test]
    procedure NoFileWithoutRepositoryAbove;
    [Test]
    procedure RootIsRepositoryOrFolder;
    [Test]
    procedure ReadsAllSections;
    [Test]
    procedure TeamPrefixBeatsPersonalSetting;
    /// <summary>#1286: Abschnitt vcs mit provider und mainBranch; falsche Werte gemeldet und übergangen.</summary>
    [Test]
    procedure ReadsVcsSection;
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
    /// <summary>Gerüst mit englischer Oberfläche: englische Kommentare, gleiche gültige Datei (#1458).</summary>
    [Test]
    procedure SkeletonIsValidInEnglish;
    [Test]
    procedure SnippetFolderIsResolved;
    [Test]
    procedure ValuesNameEverySetEntry;
    [Test]
    procedure ReadsDebugDisplayRules;
    /// <summary>Startverbünde (#867): Array als JSON-Text; mit Zugangsdaten verworfen.</summary>
    [Test]
    procedure KeepsLaunchGroups;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Localization.Language;

const
  cFileName = 'C:\Repo\App\.atlas';
  cRoot = 'C:\Repo';

function ExistsIn(const APaths: array of string): TAtlasTeamFileExists;
var
  mPaths: TArray<string>;
  mIndex: Integer;
begin
  SetLength(mPaths, Length(APaths));
  for mIndex := 0 to High(APaths) do
  begin
    mPaths[mIndex] := APaths[mIndex];
  end;
  Result :=
    function(const APath: string): Boolean
    var
      Item: string;
    begin
      for Item in mPaths do
      begin
        if SameText(Item, APath) then
        begin
          Exit(True);
        end;
      end;
      Result := False;
    end;
end;

function TAtlasTeamFileTests.Parsed(const AText: string): TAtlasTeamSettings;
begin
  Result := TAtlasTeamFile.Parse(AText, cFileName, cRoot);
end;

function TAtlasTeamFileTests.HasIssue(const ATeam: TAtlasTeamSettings; AKind: TAtlasTeamIssueKind;
  const APath: string): Boolean;
var
  mIssue: TAtlasTeamIssue;
begin
  for mIssue in ATeam.Issues do
  begin
    if (mIssue.Kind = AKind) and (mIssue.Path = APath) then
    begin
      Exit(True);
    end;
  end;
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

procedure TAtlasTeamFileTests.LocatesFileInFolderBetweenProjectAndRoot;
begin
  Assert.AreEqual('C:\Repo\Teil\.atlas', TAtlasTeamFile.Locate('C:\Repo\Teil\App',
    ExistsIn(['C:\Repo\.git', 'C:\Repo\Teil\.atlas', 'C:\Repo\.atlas'])), 'nächster Ordner gewinnt');
  Assert.AreEqual('C:\Repo\.atlas', TAtlasTeamFile.Locate('C:\Repo\Teil\App\',
    ExistsIn(['C:\Repo\.git', 'C:\Repo\.atlas', 'C:\.atlas'])), 'nicht über die Wurzel hinaus');
end;

procedure TAtlasTeamFileTests.LocatesFileInSubversionRoot;
begin
  Assert.AreEqual('C:\Arbeit\.atlas', TAtlasTeamFile.Locate('C:\Arbeit\Quellen\App',
    ExistsIn(['C:\Arbeit\.svn', 'C:\Arbeit\.atlas'])));
  Assert.AreEqual('C:\Arbeit', TAtlasTeamFile.RootOf('C:\Arbeit\Quellen', ExistsIn(['C:\Arbeit\.svn'])),
    'Wurzel einer SVN-Arbeitskopie');
end;

procedure TAtlasTeamFileTests.LocatesFileNextToProjectGroup;
begin
  Assert.AreEqual('C:\Gruppe\.atlas', TAtlasTeamFile.Locate('C:\Gruppe\Pakete\Kern', 'C:\Gruppe',
    ExistsIn(['C:\Gruppe\.atlas'])), 'Gruppe über dem Projekt, ohne Repository');
  Assert.AreEqual('C:\Gruppe\Pakete\.atlas', TAtlasTeamFile.Locate('C:\Gruppe\Pakete\Kern', 'C:\Gruppe\',
    ExistsIn(['C:\Gruppe\.atlas', 'C:\Gruppe\Pakete\.atlas'])), 'nächster Ordner vor der Gruppe');
  Assert.AreEqual('C:\Arbeit\.atlas', TAtlasTeamFile.Locate('C:\Arbeit\Repo\App', 'C:\Arbeit',
    ExistsIn(['C:\Arbeit\Repo\.git', 'C:\Arbeit\.atlas'])), 'Gruppe außerhalb des Repositorys');
  Assert.AreEqual('C:\Gruppen\.atlas', TAtlasTeamFile.Locate('C:\Repo\App', 'C:\Gruppen',
    ExistsIn(['C:\Gruppen\.atlas'])), 'Gruppe neben dem Projekt');
  Assert.AreEqual('C:\Repo\App\.atlas', TAtlasTeamFile.Locate('C:\Repo\App', 'C:\Repo',
    ExistsIn(['C:\Repo\.atlas', 'C:\Repo\App\.atlas'])), 'Ordner der .dproj zuerst');
  Assert.AreEqual('', TAtlasTeamFile.Locate('C:\Gruppe\App', 'C:\Gruppe', ExistsIn(['C:\.atlas'])),
    'nicht über die Gruppe hinaus');
end;

procedure TAtlasTeamFileTests.NoFileWithoutRepositoryAbove;
begin
  Assert.AreEqual('', TAtlasTeamFile.Locate('C:\Repo\App', ExistsIn(['C:\Repo\.atlas'])),
    'ohne .git, .svn und Gruppe nur der Ordner der .dproj');
  Assert.AreEqual('', TAtlasTeamFile.Locate('C:\Repo\App', '', ExistsIn(['C:\Repo\.atlas'])), 'ohne Gruppe');
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
  mTeam: TAtlasTeamSettings;
begin
  mTeam := Parsed(
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
    '  "tracker": {"provider": "YouTrack", "url": "https://firma.youtrack.cloud", "project": "ATL",'#13#10 +
    '    "templateFields": {"version": "{version}", "steps": "{code}"}},'#13#10 +
    '}');
  Assert.IsTrue(mTeam.Valid);
  Assert.IsTrue(mTeam.Exists);
  Assert.AreEqual(0, Integer(Length(mTeam.Issues)), 'keine Meldung');
  Assert.AreEqual('C:\Repo\App', mTeam.Folder);
  Assert.AreEqual('F', mTeam.Naming[TAtlasNamingKind.Field]);
  Assert.AreEqual('A', mTeam.Naming[TAtlasNamingKind.Parameter]);
  Assert.IsTrue(mTeam.HasNaming[TAtlasNamingKind.Local], 'leeres Präfix ist ein Wert');
  // Konstanten für die Prüfregel naming-prefix (#1111).
  Assert.AreEqual('c', mTeam.Naming[TAtlasNamingKind.Constant]);
  Assert.AreEqual('Vorlagen\Snippets', mTeam.Snippets);
  Assert.AreEqual(2, Integer(Length(mTeam.FormatFunctions)));
  Assert.AreEqual('Trace', mTeam.FormatFunctions[1].Name);
  Assert.AreEqual(1, mTeam.FormatFunctions[1].FormatIndex);
  Assert.AreEqual(1, Integer(Length(mTeam.SqlTargets)), 'doppelte Einträge einmal');
  Assert.AreEqual('TDateien.Laden', mTeam.FileMethods[0]);
  Assert.AreEqual('TLogger.Write', mTeam.MainThreadExceptions[0]);
  Assert.AreEqual(1, Integer(Length(mTeam.StartProfiles)));
  Assert.AreEqual('Demo', mTeam.StartProfiles[0].Name);
  Assert.AreEqual('-demo /silent', mTeam.StartProfiles[0].Parameters);
  Assert.AreEqual('..\Bin', mTeam.StartProfiles[0].WorkingDir);
  Assert.AreEqual('$(BDS)\bin\bds.exe', mTeam.StartProfiles[0].Host);
  Assert.AreEqual('MODUS', mTeam.StartProfiles[0].Environment[0].Name);
  Assert.AreEqual('demo', mTeam.StartProfiles[0].Environment[0].Value);
  Assert.IsTrue(mTeam.Ci.Configured);
  Assert.IsTrue(mTeam.Ci.Multibranch);
  Assert.AreEqual('kasse', mTeam.Ci.Job);
  Assert.IsTrue(mTeam.Tracker.Configured);
  Assert.AreEqual('youtrack', mTeam.Tracker.Provider);
  Assert.AreEqual('ATL', mTeam.Tracker.Project);
  // Vorbelegung der GitHub-Vorlagen (#2137) wie Umgebungsvariablen: Feld-Id → Text.
  Assert.AreEqual(2, Integer(Length(mTeam.Tracker.TemplateFields)));
  Assert.AreEqual('steps', mTeam.Tracker.TemplateFields[1].Name);
  Assert.AreEqual('{code}', mTeam.Tracker.TemplateFields[1].Value);
end;

procedure TAtlasTeamFileTests.ReadsVcsSection;
var
  mTeam: TAtlasTeamSettings;
begin
  mTeam := Parsed('{"version": 1, "vcs": {"provider": "SVN", "mainBranch": " develop "}}');
  Assert.AreEqual(0, Integer(Length(mTeam.Issues)));
  Assert.IsTrue(mTeam.Vcs.Configured);
  Assert.AreEqual('svn', mTeam.Vcs.Provider);
  Assert.AreEqual('develop', mTeam.Vcs.MainBranch);
  Assert.AreEqual('vcs', TAtlasTeamFile.Values(mTeam)[0].Key);
  Assert.AreEqual('svn, develop', TAtlasTeamFile.Values(mTeam)[0].Value);
  mTeam := Parsed('{"version": 1, "vcs": {"mainBranch": "develop"}}');
  Assert.AreEqual('', mTeam.Vcs.Provider, 'nicht gesetzt');
  Assert.IsTrue(mTeam.Vcs.Configured);
  mTeam := Parsed('{"version": 1, "vcs": {"provider": "cvs", "mainBranch": "mein branch", "x": 1}}');
  Assert.IsFalse(mTeam.Vcs.Configured);
  Assert.IsTrue(HasIssue(mTeam, TAtlasTeamIssueKind.InvalidValue, 'vcs.provider'));
  Assert.IsTrue(HasIssue(mTeam, TAtlasTeamIssueKind.InvalidValue, 'vcs.mainBranch'));
  Assert.IsTrue(HasIssue(mTeam, TAtlasTeamIssueKind.UnknownKey, 'vcs.x'));
  mTeam := Parsed('{"version": 1, "vcs": "git"}');
  Assert.IsTrue(HasIssue(mTeam, TAtlasTeamIssueKind.WrongType, 'vcs'));
end;

procedure TAtlasTeamFileTests.TeamPrefixBeatsPersonalSetting;
var
  mTeam: TAtlasTeamSettings;
begin
  // Akzeptanzkriterium: "field": "F" erzwingt das F-Präfix trotz anderer persönlicher Einstellung.
  mTeam := Parsed('{"version": 1, "naming": {"field": "F"}}');
  Assert.AreEqual('F', TAtlasTeamFile.Prefix(mTeam, TAtlasNamingKind.Field, 'f_'));
  Assert.AreEqual('A', TAtlasTeamFile.Prefix(mTeam, TAtlasNamingKind.Parameter, 'A'), 'nicht gesetzt: persönlich');
  Assert.AreEqual('f_', TAtlasTeamFile.Prefix(TAtlasTeamFile.Empty, TAtlasNamingKind.Field, 'f_'),
    'ohne Projektdatei');
end;

procedure TAtlasTeamFileTests.BrokenFileIsInvalidWithIssue;
var
  mTeam: TAtlasTeamSettings;
begin
  // Akzeptanzkriterium: Hinweis statt Absturz, es gelten die persönlichen Einstellungen.
  mTeam := Parsed('{"version": 1, "naming": {"field": "F"');
  Assert.IsFalse(mTeam.Valid);
  Assert.IsTrue(mTeam.Exists);
  Assert.IsTrue(HasIssue(mTeam, TAtlasTeamIssueKind.Syntax, ''));
  Assert.AreEqual<Integer>(1, mTeam.Issues[0].Line, 'Zeile der fehlerhaften Stelle');
  Assert.AreEqual<Integer>(39, mTeam.Issues[0].Column, 'Spalte: Ende des Texts');
  mTeam := Parsed('{'#13#10'  "version": 1'#13#10'  "tracker": {}'#13#10'}');
  Assert.IsFalse(mTeam.Valid, 'fehlendes Komma');
  Assert.AreEqual<Integer>(3, mTeam.Issues[0].Line);
  Assert.AreEqual<Integer>(3, mTeam.Issues[0].Column);
  Assert.AreEqual<Integer>(0, Parsed('[1, 2]').Issues[0].Line, 'gültiges JSON, aber kein Objekt: ohne Stelle');
  Assert.AreEqual('f_', TAtlasTeamFile.Prefix(mTeam, TAtlasNamingKind.Field, 'f_'));
  Assert.AreEqual(0, Integer(Length(TAtlasTeamFile.Values(mTeam))));
  Assert.IsFalse(Parsed('[1, 2]').Valid, 'kein Objekt');
  Assert.IsFalse(Parsed('').Valid, 'leer');
  Assert.IsFalse(Parsed('kein json').Valid);
end;

procedure TAtlasTeamFileTests.IgnoresCredentials;
var
  mTeam: TAtlasTeamSettings;
begin
  mTeam := Parsed('{"version": 1, "token": "abc",'#13#10 +
    '"ci": {"url": "https://marco:geheim@ci.example.com", "job": "kasse", "apiToken": "x"},'#13#10 +
    '"tracker": {"provider": "github", "url": "https://github.com/firma/kasse", "password": "x"},'#13#10 +
    '"startProfiles": [{"name": "Db", "environment": {"DB_PASSWORD": "geheim"}},'#13#10 +
    '  {"name": "Login", "parameters": "-url=https://ci.example.com/?token=abc"},'#13#10 +
    '  {"name": "Gut", "parameters": "-demo"}],'#13#10 +
    '"extra": {"nested": {"secret": "x"}}}');
  Assert.IsTrue(mTeam.Valid);
  Assert.IsTrue(HasIssue(mTeam, TAtlasTeamIssueKind.Credential, 'token'));
  Assert.IsTrue(HasIssue(mTeam, TAtlasTeamIssueKind.Credential, 'ci.url'));
  Assert.IsTrue(HasIssue(mTeam, TAtlasTeamIssueKind.Credential, 'ci.apiToken'));
  Assert.IsTrue(HasIssue(mTeam, TAtlasTeamIssueKind.Credential, 'tracker.password'));
  Assert.IsTrue(HasIssue(mTeam, TAtlasTeamIssueKind.Credential, 'startProfiles[Db].environment.DB_PASSWORD'));
  Assert.IsTrue(HasIssue(mTeam, TAtlasTeamIssueKind.Credential, 'startProfiles[Login].parameters'));
  Assert.IsTrue(HasIssue(mTeam, TAtlasTeamIssueKind.Credential, 'extra.nested.secret'));
  Assert.IsTrue(HasIssue(mTeam, TAtlasTeamIssueKind.UnknownKey, 'extra'));
  Assert.AreEqual('', mTeam.Ci.Url, 'Adresse mit Zugangsdaten ignoriert');
  Assert.IsFalse(mTeam.Ci.Configured);
  Assert.IsTrue(mTeam.Tracker.Configured, 'der Rest des Trackers gilt');
  Assert.AreEqual(1, Integer(Length(mTeam.StartProfiles)), 'Profile mit Zugangsdaten entfallen ganz');
  Assert.AreEqual('Gut', mTeam.StartProfiles[0].Name);
end;

procedure TAtlasTeamFileTests.IgnoresAbsoluteAndOutsidePaths;
var
  mTeam: TAtlasTeamSettings;
begin
  mTeam := Parsed('{"version": 1, "snippets": "C:\\Vorlagen",'#13#10 +
    '"startProfiles": [{"name": "Abs", "host": "C:\\Tools\\host.exe"},'#13#10 +
    '  {"name": "Raus", "workingDir": "..\\..\\Anderes"},'#13#10 +
    '  {"name": "Param", "parameters": "-db D:\\Daten\\test.fdb"},'#13#10 +
    '  {"name": "Env", "environment": {"DATEN": "\\\\server\\daten"}},'#13#10 +
    '  {"name": "Innen", "workingDir": "..\\Bin"}]}');
  Assert.IsTrue(HasIssue(mTeam, TAtlasTeamIssueKind.AbsolutePath, 'snippets'));
  Assert.AreEqual('', mTeam.Snippets);
  Assert.IsTrue(HasIssue(mTeam, TAtlasTeamIssueKind.AbsolutePath, 'startProfiles[Abs].host'));
  Assert.IsTrue(HasIssue(mTeam, TAtlasTeamIssueKind.OutsidePath, 'startProfiles[Raus].workingDir'));
  Assert.IsTrue(HasIssue(mTeam, TAtlasTeamIssueKind.AbsolutePath, 'startProfiles[Param].parameters'));
  Assert.IsTrue(HasIssue(mTeam, TAtlasTeamIssueKind.AbsolutePath, 'startProfiles[Env].environment.DATEN'));
  Assert.AreEqual(1, Integer(Length(mTeam.StartProfiles)));
  Assert.AreEqual('Innen', mTeam.StartProfiles[0].Name, '..\Bin bleibt im Repository');
  mTeam := Parsed('{"version": 1, "snippets": "..\\Vorlagen"}');
  Assert.AreEqual('..\Vorlagen', mTeam.Snippets);
  Assert.IsTrue(HasIssue(TAtlasTeamFile.Parse('{"version": 1, "snippets": "..\\Vorlagen"}', cFileName, ''),
    TAtlasTeamIssueKind.OutsidePath, 'snippets'), 'ohne Repository ist der Ordner der Datei die Wurzel');
end;

procedure TAtlasTeamFileTests.ReportsUnknownKeysWrongTypesAndVersion;
var
  mTeam: TAtlasTeamSettings;
begin
  mTeam := Parsed('{"$schema": "x", "naming": {"feld": "F", "field": 3, "local": "L-"},'#13#10 +
    '"sqlTargets": "TQuery.SQL", "fileMethods": ["A", 2, ""], "formatFunctions": [{"name": "Log"}],'#13#10 +
    '"ci": {"provider": "teamcity", "url": "https://ci"}, "tracker": {"provider": "github", "url": "ci"}}');
  Assert.IsTrue(mTeam.Valid, 'Fehler in Werten machen die Datei nicht ungültig');
  Assert.IsTrue(HasIssue(mTeam, TAtlasTeamIssueKind.Version, 'version'), 'Version fehlt');
  Assert.AreEqual(1, mTeam.Version);
  Assert.IsTrue(HasIssue(mTeam, TAtlasTeamIssueKind.UnknownKey, 'naming.feld'));
  Assert.IsTrue(HasIssue(mTeam, TAtlasTeamIssueKind.WrongType, 'naming.field'));
  Assert.IsTrue(HasIssue(mTeam, TAtlasTeamIssueKind.InvalidValue, 'naming.local'));
  Assert.IsFalse(mTeam.HasNaming[TAtlasNamingKind.Field]);
  Assert.IsTrue(HasIssue(mTeam, TAtlasTeamIssueKind.WrongType, 'sqlTargets'));
  Assert.IsTrue(HasIssue(mTeam, TAtlasTeamIssueKind.WrongType, 'fileMethods[1]'));
  Assert.IsTrue(HasIssue(mTeam, TAtlasTeamIssueKind.InvalidValue, 'fileMethods[2]'));
  Assert.AreEqual(1, Integer(Length(mTeam.FileMethods)));
  Assert.IsTrue(HasIssue(mTeam, TAtlasTeamIssueKind.InvalidValue, 'formatFunctions[0]'));
  Assert.IsTrue(HasIssue(mTeam, TAtlasTeamIssueKind.InvalidValue, 'ci.provider'));
  Assert.IsFalse(mTeam.Ci.Configured);
  Assert.IsTrue(HasIssue(mTeam, TAtlasTeamIssueKind.InvalidValue, 'tracker.url'));
  Assert.IsFalse(HasIssue(mTeam, TAtlasTeamIssueKind.UnknownKey, '$schema'));
  mTeam := Parsed('{"version": 2, "naming": {"field": "F"}}');
  Assert.IsTrue(HasIssue(mTeam, TAtlasTeamIssueKind.Version, 'version'), 'neuer als bekannt');
  Assert.AreEqual(2, mTeam.Version);
  Assert.AreEqual('F', mTeam.Naming[TAtlasNamingKind.Field], 'Bekanntes gilt weiter');
end;

procedure TAtlasTeamFileTests.MergeKeepsTeamFirst;
var
  mNames: TArray<string>;
  mFunctions: TArray<TAtlasFormatFunction>;
  mTeam, mPersonal, mMerged: TArray<TAtlasStartProfile>;
begin
  mNames := TAtlasTeamFile.MergeNames(['TQuery.SQL', 'TTeam.Sql'], ['tquery.sql', 'TMein.Sql']);
  Assert.AreEqual(3, Integer(Length(mNames)));
  Assert.AreEqual('TQuery.SQL', mNames[0]);
  Assert.AreEqual('TMein.Sql', mNames[2]);
  mFunctions := TAtlasTeamFile.MergeFormatFunctions([TAtlasFormatFunction.Create('Log', 1)],
    [TAtlasFormatFunction.Create('log', 0), TAtlasFormatFunction.Create('Trace', 2)]);
  Assert.AreEqual(2, Integer(Length(mFunctions)));
  Assert.AreEqual(1, mFunctions[0].FormatIndex, 'Index aus der Projektdatei');
  SetLength(mTeam, 1);
  mTeam[0].Name := 'Demo';
  mTeam[0].Parameters := '-team';
  SetLength(mPersonal, 2);
  mPersonal[0].Name := 'demo';
  mPersonal[0].Parameters := '-mein';
  mPersonal[1].Name := 'Lokal';
  mMerged := TAtlasTeamFile.MergeStartProfiles(mTeam, mPersonal);
  Assert.AreEqual(2, Integer(Length(mMerged)));
  Assert.AreEqual('-team', mMerged[0].Parameters);
  Assert.AreEqual('Lokal', mMerged[1].Name);
end;

procedure TAtlasTeamFileTests.SkeletonIsValidWithoutIssues;
var
  mTeam: TAtlasTeamSettings;
begin
  mTeam := Parsed(TAtlasTeamFile.Skeleton);
  Assert.IsTrue(mTeam.Valid);
  Assert.AreEqual(0, Integer(Length(mTeam.Issues)));
  Assert.IsFalse(mTeam.HasValues, 'Beispiele stehen nur als Kommentar');
  Assert.Contains(TAtlasTeamFile.Skeleton, '"version": 1');
end;

procedure TAtlasTeamFileTests.SkeletonIsValidInEnglish;
var
  mSkeleton: string;
  mSaved: TAtlasLanguage;
begin
  mSaved := TAtlasTextLanguage.Current;
  TAtlasTextLanguage.Current := TAtlasLanguage.English;
  try
    mSkeleton := TAtlasTeamFile.Skeleton;
  finally
    TAtlasTextLanguage.Current := mSaved;
  end;
  Assert.IsTrue(Parsed(mSkeleton).Valid);
  Assert.AreEqual(0, Integer(Length(Parsed(mSkeleton).Issues)));
  Assert.IsTrue(Pos('Atlas project settings for the whole team', mSkeleton) > 0);
  Assert.AreEqual(0, Pos('Projekteinstellungen', mSkeleton));
end;

procedure TAtlasTeamFileTests.SnippetFolderIsResolved;
begin
  Assert.AreEqual('C:\Repo\Vorlagen\Snippets', Parsed('{"version": 1, "snippets": "../Vorlagen/./Snippets/"}').SnippetFolder);
  Assert.AreEqual('', Parsed('{"version": 1}').SnippetFolder);
  Assert.AreEqual('\\srv\daten\Repo\Vorlagen', TAtlasTeamFile.Combine('\\srv\daten\Repo\App', '..\Vorlagen'));
end;

procedure TAtlasTeamFileTests.ValuesNameEverySetEntry;
var
  mValues: TArray<TAtlasTeamValue>;
begin
  mValues := TAtlasTeamFile.Values(Parsed('{"version": 1, "naming": {"field": "F"}, "sqlTargets": ["A", "B"],' +
    '"ci": {"url": "https://ci.example.com", "job": "kasse"}}'));
  Assert.AreEqual(3, Integer(Length(mValues)));
  Assert.AreEqual('naming.field', mValues[0].Key);
  Assert.AreEqual('"F"', mValues[0].Value);
  Assert.AreEqual('A, B', mValues[1].Value);
  Assert.AreEqual('ci', mValues[2].Key);
  Assert.Contains(mValues[2].Value, 'jenkins');
  Assert.IsFalse(TAtlasTeamFile.Empty.HasValues);
  // tracker.templateFields (#2137) als Zeile mit Feld-Id=Text.
  mValues := TAtlasTeamFile.Values(Parsed('{"version": 1, "tracker": {"templateFields": {"ide": "{ide}"}}}'));
  Assert.AreEqual('tracker.templateFields', mValues[High(mValues)].Key);
  Assert.AreEqual('ide={ide}', mValues[High(mValues)].Value);
end;

procedure TAtlasTeamFileTests.ReadsDebugDisplayRules;
var
  mTeam: TAtlasTeamSettings;
begin
  mTeam := Parsed('{"version": 1, "debugDisplayRules": {' +
    '"FireDAC.Comp.Client.TFDConnection": "{ConnectionName} ({DriverName})",' +
    '"TKunde": {"template": "{Name}", "children": ["Name", "Ort", "name"]},' +
    '"TPunkt": {"children": "X, Y"},' +
    '"TKaputt": "{Name",' +
    '"TLeer": {},' +
    '"TZahl": 1,' +
    '"TExtra": {"template": "{A}", "farbe": "rot"}}}');
  Assert.AreEqual(4, Integer(Length(mTeam.DisplayRules)));
  Assert.AreEqual('FireDAC.Comp.Client.TFDConnection', mTeam.DisplayRules[0].TypeName);
  Assert.AreEqual('{ConnectionName} ({DriverName})', mTeam.DisplayRules[0].Template);
  Assert.AreEqual('Name|Ort', string.Join('|', mTeam.DisplayRules[1].Children));
  Assert.AreEqual('', mTeam.DisplayRules[2].Template);
  Assert.AreEqual('X|Y', string.Join('|', mTeam.DisplayRules[2].Children));
  Assert.AreEqual('TExtra', mTeam.DisplayRules[3].TypeName);
  Assert.IsTrue(HasIssue(mTeam, TAtlasTeamIssueKind.InvalidValue, 'debugDisplayRules.TKaputt'));
  Assert.IsTrue(HasIssue(mTeam, TAtlasTeamIssueKind.InvalidValue, 'debugDisplayRules.TLeer'));
  Assert.IsTrue(HasIssue(mTeam, TAtlasTeamIssueKind.WrongType, 'debugDisplayRules.TZahl'));
  Assert.IsTrue(HasIssue(mTeam, TAtlasTeamIssueKind.UnknownKey, 'debugDisplayRules.TExtra.farbe'));
  Assert.AreEqual('debugDisplayRules', TAtlasTeamFile.Values(mTeam)[0].Key);
  Assert.AreEqual<TAtlasTeamIssueKind>(TAtlasTeamIssueKind.WrongType,
    Parsed('{"version": 1, "debugDisplayRules": []}').Issues[0].Kind);
  Assert.Contains(TAtlasTeamFile.Skeleton, '"debugDisplayRules"');
end;

procedure TAtlasTeamFileTests.KeepsLaunchGroups;
var
  mTeam: TAtlasTeamSettings;
begin
  mTeam := Parsed('{"version": 1, "launchGroups": [{"name": "A", "items": [{"project": "S.dproj"}]}]}');
  Assert.AreEqual(0, Integer(Length(mTeam.Issues)));
  Assert.AreEqual('[{"name":"A","items":[{"project":"S.dproj"}]}]', mTeam.LaunchGroups);
  Assert.AreEqual('launchGroups', TAtlasTeamFile.Values(mTeam)[0].Key);
  mTeam := Parsed('{"version": 1, "launchGroups": [{"name": "A", "password": "geheim"}]}');
  Assert.AreEqual('', mTeam.LaunchGroups, 'mit Zugangsdaten verworfen');
  Assert.IsTrue(HasIssue(mTeam, TAtlasTeamIssueKind.Credential, 'launchGroups.password'));
  Assert.IsTrue(HasIssue(Parsed('{"version": 1, "launchGroups": {}}'), TAtlasTeamIssueKind.WrongType, 'launchGroups'));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTeamFileTests);

end.
