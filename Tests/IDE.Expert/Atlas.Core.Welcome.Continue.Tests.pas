unit Atlas.Core.Welcome.Continue.Tests;

// Tests des Bereichs „Weiterarbeiten“ ohne VCL (#755), Reiter „Zuletzt“:
// Schreiben und Lesen des Arbeitsstands im Abschnitt "continue" der
// Projekt-Zusammenfassung, Aufbau beim Schließen, Liste der Arbeitsstände,
// Plan für „Fortsetzen“, Zeitangaben, Reihenfolge der Reiter, Methode an der
// letzten Änderung und die Auswahl eingehender Commits mit einer
// Ersatz-Versionsverwaltung.
// Akzeptanzkriterien: 7 Reiter werden in gleicher Reihenfolge mit dem Cursor an
// der letzten Änderung wiederhergestellt; eine gelöschte Datei wird
// übersprungen und genannt; ein Commit auf origin/main zu einer bearbeiteten
// Datei erscheint, einer zu anderen Dateien nicht; ohne Versionsverwaltung kein
// Abschnitt und kein Fehler.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasWelcomeContinueTests = class
  public
    [Test]
    procedure WorkStateRoundTripKeepsSummary;
    [Test]
    procedure ReadIgnoresBrokenSection;
    [Test]
    procedure BuildTakesChangesAndKeepsOlderOnes;
    [Test]
    procedure SevenTabsResumeInSameOrderAtLastChange;
    [Test]
    procedure DeletedFileIsSkippedAndNamed;
    [Test]
    procedure EntriesNewestFirstLimitedAndWithTabs;
    [Test]
    procedure LastTabIsNewestChange;
    [Test]
    procedure AgeTexts;
    [Test]
    procedure OrderFollowsTabCaptions;
    [Test]
    procedure MethodAtLastChange;
    [Test]
    procedure SelectShowsOnlyCommitsOnWorkFiles;
    [Test]
    procedure IncomingCommitOnEditedFileAppears;
    [Test]
    procedure IncomingFetchOnlyWhenAsked;
    [Test]
    procedure IncomingWithoutVersionControlHasNoSection;
    [Test]
    procedure IncomingWithoutUpstreamHasNoSection;
    [Test]
    procedure ProbeHeadStoresHeadAndUpstream;
  end;

implementation

uses
  System.SysUtils,
  System.DateUtils,
  Atlas.Core.Projects.Summary,
  Atlas.Core.Vcs.Contract,
  Atlas.Core.Vcs.Providers.Null,
  Atlas.Core.Welcome.Projects,
  Atlas.Core.Welcome.Continue;

const
  Root = 'C:\Repo';

type
  /// <summary>Ersatz für Git: festgelegte Ergebnisse ohne Prozess, merkt sich Aufrufe und Ausschlüsse.</summary>
  TFakeVcs = class(TInterfacedObject, IAtlasVersionControl, IAtlasVcsIncoming)
  public
    FKind: TAtlasVcsKind;
    FHead: TAtlasVcsHead;
    FHeadOutcome: TAtlasVcsOutcome;
    FCommits: TArray<TAtlasVcsIncomingCommit>;
    FFetchOutcome: TAtlasVcsOutcome;
    // Bekannte Revisionen für Resolve.
    FKnown: TArray<string>;
    Calls: TArray<string>;
    Excluded: TArray<string>;
    constructor Create;
    function Kind: TAtlasVcsKind;
    function WorkingCopy: TAtlasVcsWorkingCopy;
    function Head(out AHead: TAtlasVcsHead): TAtlasVcsOutcome;
    function Changes(out AChanges: TArray<TAtlasVcsChange>): TAtlasVcsOutcome;
    function FileAt(const AFileName, ARevision: string; out AContent: TBytes): TAtlasVcsOutcome;
    function Blame(const AFileName: string; out ALines: TArray<TAtlasVcsBlameLine>): TAtlasVcsOutcome;
    function ChangeMarker: string;
    function Resolve(const ARef: string; out ARevision: string): TAtlasVcsOutcome;
    function Incoming(const AUpstream: string; const AExclude: TArray<string>; AMax: Integer;
      out ACommits: TArray<TAtlasVcsIncomingCommit>): TAtlasVcsOutcome;
    function Fetch(const ARemote: string): TAtlasVcsOutcome;
    function Called(const AName: string): Boolean;
    function CalledStarting(const APrefix: string): Boolean;
  end;

constructor TFakeVcs.Create;
begin
  inherited Create;
  FKind := TAtlasVcsKind.Git;
  FHead := TAtlasVcsHead.Empty;
  FHead.Branch := 'main';
  FHead.Revision := 'cccccccccccccccccccccccccccccccccccccccc';
  FHead.Upstream := 'origin/main';
  FHeadOutcome := TAtlasVcsOutcome.Ok;
  FFetchOutcome := TAtlasVcsOutcome.Ok;
end;

function TFakeVcs.Kind: TAtlasVcsKind;
begin
  Result := FKind;
end;

function TFakeVcs.WorkingCopy: TAtlasVcsWorkingCopy;
begin
  Result.Kind := FKind;
  Result.Root := Root;
end;

function TFakeVcs.Head(out AHead: TAtlasVcsHead): TAtlasVcsOutcome;
begin
  Calls := Calls + ['head'];
  AHead := FHead;
  Result := FHeadOutcome;
end;

function TFakeVcs.Changes(out AChanges: TArray<TAtlasVcsChange>): TAtlasVcsOutcome;
begin
  AChanges := nil;
  Result := TAtlasVcsOutcome.Ok;
end;

function TFakeVcs.FileAt(const AFileName, ARevision: string; out AContent: TBytes): TAtlasVcsOutcome;
begin
  AContent := nil;
  Result := TAtlasVcsOutcome.Failed;
end;

function TFakeVcs.Blame(const AFileName: string; out ALines: TArray<TAtlasVcsBlameLine>): TAtlasVcsOutcome;
begin
  ALines := nil;
  Result := TAtlasVcsOutcome.Failed;
end;

function TFakeVcs.ChangeMarker: string;
begin
  Result := '';
end;

function TFakeVcs.Resolve(const ARef: string; out ARevision: string): TAtlasVcsOutcome;
var
  Known: string;
begin
  Calls := Calls + ['resolve ' + ARef];
  ARevision := '';
  Result := TAtlasVcsOutcome.Failed;
  for Known in FKnown do
    if Known = ARef then
    begin
      ARevision := ARef;
      Exit(TAtlasVcsOutcome.Ok);
    end;
  // Branch des Upstreams: dessen heutiger Stand.
  if ARef = FHead.Upstream then
  begin
    ARevision := 'uuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuu';
    Result := TAtlasVcsOutcome.Ok;
  end;
end;

function TFakeVcs.Incoming(const AUpstream: string; const AExclude: TArray<string>; AMax: Integer;
  out ACommits: TArray<TAtlasVcsIncomingCommit>): TAtlasVcsOutcome;
begin
  Calls := Calls + ['incoming ' + AUpstream];
  Excluded := AExclude;
  ACommits := FCommits;
  Result := TAtlasVcsOutcome.Ok;
end;

function TFakeVcs.Fetch(const ARemote: string): TAtlasVcsOutcome;
begin
  Calls := Calls + ['fetch'];
  Result := FFetchOutcome;
end;

function TFakeVcs.Called(const AName: string): Boolean;
var
  Call: string;
begin
  Result := False;
  for Call in Calls do
    if Call = AName then
      Exit(True);
end;

function TFakeVcs.CalledStarting(const APrefix: string): Boolean;
var
  Call: string;
begin
  Result := False;
  for Call in Calls do
    if Call.StartsWith(APrefix) then
      Exit(True);
end;

function Path(const AName: string): string;
begin
  Result := Root + '\' + AName;
end;

function Stamp(AHour, AMinute: Word): TDateTime;
begin
  Result := EncodeDateTime(2026, 10, 15, AHour, AMinute, 0, 0);
end;

function Commit(const AHash, ASummary, AAuthor: string; const AFiles: TArray<string>): TAtlasVcsIncomingCommit;
begin
  Result := Default(TAtlasVcsIncomingCommit);
  Result.Hash := AHash;
  Result.Summary := ASummary;
  Result.Author := AAuthor;
  Result.Date := Stamp(12, 0);
  Result.Files := AFiles;
end;

/// <summary>Arbeitsstand mit den Reitern ANames (offen in dieser Reihenfolge), ohne Änderungen.</summary>
function StateOf(const ANames: TArray<string>): TAtlasWorkState;
var
  Name: string;
begin
  Result := TAtlasWorkState.Empty;
  Result.Known := True;
  Result.At := Stamp(9, 0);
  for Name in ANames do
    Result.Tabs := Result.Tabs + [TAtlasWorkTab.Create(Path(Name), 1, 1)];
end;

{ TAtlasWelcomeContinueTests }

procedure TAtlasWelcomeContinueTests.WorkStateRoundTripKeepsSummary;
var
  Summary, Parsed: TAtlasProjectSummary;
  State, Read_: TAtlasWorkState;
  Json: string;
begin
  Assert.IsTrue(TAtlasProjectSummaries.Parse('{"format":1,"project":"C:\\Repo\\Atlas.dproj","hidden":true,' +
    '"vcs":{"kind":"git","branch":"main"},"unsaved":{"kind":"git"},"history":{"x":1}}', Summary));
  State := StateOf(['Kunde.pas', 'Main.pas', 'Liste.pas']);
  State.Tabs[1] := TAtlasWorkTab.Create(Path('Main.pas'), 42, 5);
  State.Tabs[1].Method := 'TMain.Laden';
  State.Tabs[1].Changed := True;
  State.Tabs[1].ChangedAt := Stamp(8, 55);
  State.Active := 2;
  State.Edited := [Path('Alt.pas')];
  State.VcsKind := 'git';
  State.Head := 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  State.Upstream := 'origin/main';
  State.UpstreamRevision := 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
  TAtlasWelcomeContinue.Write(Summary, State);
  Json := TAtlasProjectSummaries.ToJson(Summary);
  Assert.Contains(Json, '"history"', 'fremde Abschnitte bleiben');
  Assert.Contains(Json, '"unsaved"', 'Abschnitt von #762 bleibt');
  Assert.IsTrue(TAtlasProjectSummaries.Parse(Json, Parsed));
  Assert.IsTrue(Parsed.Hidden, 'bekannte Felder bleiben');
  Assert.AreEqual('main', Parsed.Vcs.Branch);
  Assert.IsTrue(TAtlasWelcomeContinue.Read(Parsed, Read_));
  Assert.IsTrue(Read_.Known);
  Assert.AreEqual(3, Read_.TabCount);
  Assert.AreEqual(Path('Kunde.pas'), Read_.Tabs[0].FileName, 'Reihenfolge');
  Assert.AreEqual(Path('Main.pas'), Read_.Tabs[1].FileName);
  Assert.AreEqual(Path('Liste.pas'), Read_.Tabs[2].FileName);
  Assert.AreEqual(42, Read_.Tabs[1].Line);
  Assert.AreEqual(5, Read_.Tabs[1].Column);
  Assert.AreEqual('TMain.Laden', Read_.Tabs[1].Method);
  Assert.IsTrue(Read_.Tabs[1].Changed);
  Assert.IsTrue(Abs(Read_.Tabs[1].ChangedAt - Stamp(8, 55)) < OneSecond);
  Assert.IsFalse(Read_.Tabs[0].Changed);
  Assert.AreEqual(2, Read_.Active);
  Assert.IsTrue(Abs(Read_.At - Stamp(9, 0)) < OneSecond);
  Assert.AreEqual(1, Integer(Length(Read_.Edited)));
  Assert.AreEqual(Path('Alt.pas'), Read_.Edited[0]);
  Assert.AreEqual('git', Read_.VcsKind);
  Assert.AreEqual(State.Head, Read_.Head);
  Assert.AreEqual('origin/main', Read_.Upstream);
  Assert.AreEqual(State.UpstreamRevision, Read_.UpstreamRevision);
  // Zweites Schreiben ersetzt den Abschnitt, statt einen zweiten anzulegen.
  State.Active := 0;
  TAtlasWelcomeContinue.Write(Parsed, State);
  Assert.IsTrue(TAtlasWelcomeContinue.Read(Parsed, Read_));
  Assert.AreEqual(0, Read_.Active);
  Assert.AreEqual(1, Integer(Length(TAtlasProjectSummaries.ToJson(Parsed).Split(['"continue"']))) - 1);
end;

procedure TAtlasWelcomeContinueTests.ReadIgnoresBrokenSection;
var
  Summary: TAtlasProjectSummary;
  State: TAtlasWorkState;
begin
  Assert.IsTrue(TAtlasProjectSummaries.Parse('{"format":1,"project":"C:\\Repo\\Atlas.dproj"}', Summary));
  Assert.IsFalse(TAtlasWelcomeContinue.Read(Summary, State), 'ohne Abschnitt');
  Assert.AreEqual(-1, State.Active);
  Assert.IsTrue(TAtlasWelcomeContinue.FromJson('{"active":9,"tabs":[{"file":""},{"line":3},' +
    '{"file":"C:\\Repo\\A.pas","line":-4,"column":"x"},7],"edited":[1,""]}', State));
  Assert.AreEqual(1, State.TabCount, 'Reiter ohne Datei fallen weg');
  Assert.AreEqual(0, State.Tabs[0].Line, 'negative Zeile wird 0');
  Assert.AreEqual(0, State.Tabs[0].Column);
  Assert.AreEqual(-1, State.Active, 'aktiver Reiter außerhalb');
  Assert.AreEqual(0, Integer(Length(State.Edited)));
  Assert.IsFalse(TAtlasWelcomeContinue.FromJson('kein json', State));
end;

procedure TAtlasWelcomeContinueTests.BuildTakesChangesAndKeepsOlderOnes;
var
  Open, Changes: TArray<TAtlasWorkTab>;
  Old, State: TAtlasWorkState;
  Change: TAtlasWorkTab;
begin
  Open := [TAtlasWorkTab.Create(Path('A.pas'), 10, 1), TAtlasWorkTab.Create(Path('B.pas'), 20, 2),
    TAtlasWorkTab.Create(Path('C.pas'), 30, 3), TAtlasWorkTab.Create(Path('a.PAS'), 99, 9)];
  // Änderung in A (diese Sitzung) und in einer inzwischen geschlossenen Datei.
  Change := TAtlasWorkTab.Create(Path('A.pas'), 12, 7);
  Change.ChangedAt := Stamp(10, 5);
  Changes := [Change, TAtlasWorkTab.Create(Path('Zu.pas'), 3, 1)];
  // Gespeicherte Änderung in B aus einer früheren Sitzung.
  Old := StateOf(['B.pas']);
  Old.Tabs[0] := TAtlasWorkTab.Create(Path('B.pas'), 77, 4);
  Old.Tabs[0].Changed := True;
  Old.Tabs[0].ChangedAt := Stamp(8, 0);
  Old.Tabs[0].Method := 'TB.Alt';
  State := TAtlasWelcomeContinue.Build(Open, Path('C.pas'), Changes, Old, Stamp(11, 0));
  Assert.IsTrue(State.Known);
  Assert.AreEqual(3, State.TabCount, 'dieselbe Datei zweimal zählt einmal');
  Assert.AreEqual(12, State.Tabs[0].Line, 'Änderung statt Cursor');
  Assert.AreEqual(7, State.Tabs[0].Column);
  Assert.IsTrue(State.Tabs[0].Changed);
  Assert.IsTrue(Abs(State.Tabs[0].ChangedAt - Stamp(10, 5)) < OneSecond);
  Assert.AreEqual(77, State.Tabs[1].Line, 'frühere Änderung bleibt die letzte');
  Assert.AreEqual('TB.Alt', State.Tabs[1].Method);
  Assert.IsTrue(State.Tabs[1].Changed);
  Assert.AreEqual(30, State.Tabs[2].Line, 'ohne Änderung der Cursor');
  Assert.IsFalse(State.Tabs[2].Changed);
  Assert.AreEqual(2, State.Active);
  Assert.AreEqual(1, Integer(Length(State.Edited)));
  Assert.AreEqual(Path('Zu.pas'), State.Edited[0]);
  Assert.IsTrue(Abs(State.At - Stamp(11, 0)) < OneSecond);
  Assert.AreEqual(4, Integer(Length(State.Files)), 'Reiter und geänderte Dateien');
end;

procedure TAtlasWelcomeContinueTests.SevenTabsResumeInSameOrderAtLastChange;
var
  Names: TArray<string>;
  Open, Changes: TArray<TAtlasWorkTab>;
  Change: TAtlasWorkTab;
  Summary, Parsed: TAtlasProjectSummary;
  State, Read_: TAtlasWorkState;
  Plan: TAtlasContinuePlan;
  Name: string;
  Index: Integer;
begin
  Names := ['Main.pas', 'Kunde.pas', 'Liste.pas', 'Daten.pas', 'Hilfe.pas', 'Form1.pas', 'Projekt.dpr'];
  Open := nil;
  for Name in Names do
    Open := Open + [TAtlasWorkTab.Create(Path(Name), 5, 3)];
  Change := TAtlasWorkTab.Create(Path('Daten.pas'), 120, 14);
  Change.ChangedAt := Stamp(17, 30);
  Changes := [Change];
  State := TAtlasWelcomeContinue.Build(Open, Path('Hilfe.pas'), Changes, TAtlasWorkState.Empty, Stamp(18, 40));
  Summary := TAtlasProjectSummary.Create(Path('Atlas.dproj'));
  TAtlasWelcomeContinue.Write(Summary, State);
  Assert.IsTrue(TAtlasProjectSummaries.Parse(TAtlasProjectSummaries.ToJson(Summary), Parsed));
  Assert.IsTrue(TAtlasWelcomeContinue.Read(Parsed, Read_));
  Assert.AreEqual(7, Read_.TabCount);
  Plan := TAtlasWelcomeContinue.Plan(Path('Atlas.dproj'), Read_, nil);
  Assert.AreEqual(7, Integer(Length(Plan.Open)));
  Assert.AreEqual(0, Integer(Length(Plan.Missing)));
  for Index := 0 to High(Names) do
    Assert.AreEqual(Path(Names[Index]), Plan.Open[Index].FileName, 'gleiche Reihenfolge');
  Assert.AreEqual(4, Plan.Active, 'zuletzt aktiver Reiter');
  Assert.AreEqual(120, Plan.Open[3].Line, 'Cursor an der letzten Änderung');
  Assert.AreEqual(14, Plan.Open[3].Column);
  Assert.AreEqual(3, Read_.LastIndex, 'zuletzt bearbeitet');
  // Ohne bekannten aktiven Reiter: die zuletzt bearbeitete Datei.
  Read_.Active := -1;
  Plan := TAtlasWelcomeContinue.Plan(Path('Atlas.dproj'), Read_, nil);
  Assert.AreEqual(3, Plan.Active);
end;

procedure TAtlasWelcomeContinueTests.DeletedFileIsSkippedAndNamed;
var
  State: TAtlasWorkState;
  Plan: TAtlasContinuePlan;
begin
  State := StateOf(['A.pas', 'Weg.pas', 'C.pas', 'D.pas']);
  State.Active := 3;
  Plan := TAtlasWelcomeContinue.Plan(Path('Atlas.dproj'), State,
    function(const AFileName: string): Boolean
    begin
      Result := not AFileName.EndsWith('Weg.pas');
    end);
  Assert.AreEqual(3, Integer(Length(Plan.Open)));
  Assert.AreEqual(Path('A.pas'), Plan.Open[0].FileName);
  Assert.AreEqual(Path('C.pas'), Plan.Open[1].FileName);
  Assert.AreEqual(Path('D.pas'), Plan.Open[2].FileName);
  Assert.AreEqual(1, Integer(Length(Plan.Missing)));
  Assert.AreEqual(Path('Weg.pas'), Plan.Missing[0], 'genannt');
  Assert.AreEqual(2, Plan.Active, 'Index in der verkürzten Liste');
  // Fehlt der aktive Reiter selbst, ist der zuletzt geöffnete aktiv.
  State.Active := 1;
  Plan := TAtlasWelcomeContinue.Plan(Path('Atlas.dproj'), State,
    function(const AFileName: string): Boolean
    begin
      Result := not AFileName.EndsWith('Weg.pas');
    end);
  Assert.AreEqual(2, Plan.Active);
  Assert.AreEqual(Path('Atlas.dproj'), Plan.Project);
end;

procedure TAtlasWelcomeContinueTests.EntriesNewestFirstLimitedAndWithTabs;
var
  Recent: TArray<string>;
  Entries: TAtlasContinueEntries;
  Loader: TAtlasProjectSummaryLoader;
begin
  Recent := ['C:\A\A.dproj', 'C:\B\B.groupproj', 'C:\C\C.dproj', 'c:\a\a.DPROJ', 'C:\Leer\Leer.dproj',
    'C:\Ohne\Ohne.dproj', 'C:\D\D.dproj'];
  Loader :=
    function(const AProject: string; out ASummary: TAtlasProjectSummary): Boolean
    var
      State: TAtlasWorkState;
      Hour: Word;
    begin
      ASummary := TAtlasProjectSummary.Create(AProject);
      Result := not AProject.Contains('Ohne');
      if not Result then
        Exit;
      State := StateOf(['X.pas']);
      if AProject.Contains('Leer') then
        State.Tabs := nil;
      Hour := 8;
      if AProject.Contains('B.') then
        Hour := 12;
      if AProject.Contains('C.') then
        Hour := 10;
      if AProject.Contains('D.') then
        Hour := 10;
      State.At := Stamp(Hour, 0);
      TAtlasWelcomeContinue.Write(ASummary, State);
    end;
  Entries := TAtlasWelcomeContinue.Entries(Recent, Loader, 5);
  Assert.AreEqual(4, Integer(Length(Entries)), 'ohne Reiter, ohne Zusammenfassung und doppelt fallen weg');
  Assert.AreEqual('C:\B\B.groupproj', Entries[0].Project, 'neueste zuerst');
  Assert.IsTrue(Entries[0].IsGroup);
  Assert.AreEqual('B', Entries[0].Name);
  Assert.AreEqual('C:\C\C.dproj', Entries[1].Project, 'Gleichstand: Reihenfolge der IDE');
  Assert.AreEqual('C:\D\D.dproj', Entries[2].Project);
  Assert.AreEqual('C:\A\A.dproj', Entries[3].Project);
  Entries := TAtlasWelcomeContinue.Entries(Recent, Loader, 2);
  Assert.AreEqual(2, Integer(Length(Entries)), 'höchstens welcomePage.continue.count');
  Entries := TAtlasWelcomeContinue.Entries(Recent, Loader, 0);
  Assert.AreEqual(1, Integer(Length(Entries)), 'mindestens einer');
  Entries := TAtlasWelcomeContinue.Entries(Recent, nil, 5);
  Assert.AreEqual(0, Integer(Length(Entries)));
end;

procedure TAtlasWelcomeContinueTests.LastTabIsNewestChange;
var
  Entry: TAtlasContinueEntry;
begin
  Entry := Default(TAtlasContinueEntry);
  Entry.Project := 'C:\Repo\Atlas.dproj';
  Entry.State := StateOf(['A.pas', 'B.pas', 'C.pas']);
  Assert.AreEqual(Path('A.pas'), Entry.LastTab.FileName, 'ohne Änderung und aktiven Reiter der erste');
  Entry.State.Active := 2;
  Assert.AreEqual(Path('C.pas'), Entry.LastTab.FileName, 'sonst der aktive');
  Entry.State.Tabs[0].Changed := True;
  Entry.State.Tabs[0].ChangedAt := Stamp(9, 0);
  Entry.State.Tabs[1].Changed := True;
  Entry.State.Tabs[1].ChangedAt := Stamp(10, 0);
  Entry.State.Tabs[1].Method := 'TB.Speichern';
  Assert.AreEqual(Path('B.pas'), Entry.LastTab.FileName, 'jüngste Änderung');
  Assert.AreEqual('TB.Speichern', Entry.LastTab.Method);
  Assert.AreEqual('Atlas', Entry.Name);
  Assert.IsFalse(Entry.IsGroup);
  Entry.State.Tabs := nil;
  Assert.AreEqual('', Entry.LastTab.FileName);
end;

procedure TAtlasWelcomeContinueTests.AgeTexts;
var
  Value: Integer;
  Now_: TDateTime;
begin
  Now_ := Stamp(20, 0);
  Assert.IsTrue(TAtlasWelcomeContinue.Age(Now_ - 20 * OneSecond, Now_, Value) = TAtlasContinueAge.JustNow);
  Assert.IsTrue(TAtlasWelcomeContinue.Age(Now_ + OneMinute, Now_, Value) = TAtlasContinueAge.JustNow,
    'Zukunft (Uhr verstellt)');
  Assert.IsTrue(TAtlasWelcomeContinue.Age(Stamp(19, 35), Now_, Value) = TAtlasContinueAge.Minutes);
  Assert.AreEqual(25, Value);
  Assert.IsTrue(TAtlasWelcomeContinue.Age(Stamp(17, 50), Now_, Value) = TAtlasContinueAge.Hours, 'vor 2 Std.');
  Assert.AreEqual(2, Value);
  Assert.IsTrue(TAtlasWelcomeContinue.Age(Stamp(18, 40) - 1, Now_, Value) = TAtlasContinueAge.Yesterday,
    'gestern 18:40');
  Assert.IsTrue(TAtlasWelcomeContinue.Age(Stamp(23, 0) - 1, Stamp(0, 30), Value) = TAtlasContinueAge.Yesterday,
    'kurz nach Mitternacht: gestern, nicht vor 1 Std.');
  Assert.IsTrue(TAtlasWelcomeContinue.Age(Stamp(18, 40) - 3, Now_, Value) = TAtlasContinueAge.Date);
end;

procedure TAtlasWelcomeContinueTests.OrderFollowsTabCaptions;
var
  Files, Ordered: TArray<string>;
begin
  Files := [Path('A.pas'), Path('B.pas'), Path('Sub\B.pas'), Path('C.pas'), Path('Projekt.dpr')];
  Ordered := TAtlasWelcomeContinue.OrderByTabs(Files, ['Willkommensseite', 'C.pas', '*B.pas', 'Projekt', 'B.pas*',
    'A']);
  Assert.AreEqual(5, Integer(Length(Ordered)));
  Assert.AreEqual(Path('C.pas'), Ordered[0]);
  Assert.AreEqual(Path('B.pas'), Ordered[1], 'Markierung „*“ zählt nicht');
  Assert.AreEqual(Path('Projekt.dpr'), Ordered[2], 'Beschriftung ohne Endung');
  Assert.AreEqual(Path('Sub\B.pas'), Ordered[3], 'gleicher Name: der nächste noch freie');
  Assert.AreEqual(Path('A.pas'), Ordered[4]);
  Ordered := TAtlasWelcomeContinue.OrderByTabs(Files, nil);
  Assert.AreEqual(Path('A.pas'), Ordered[0], 'ohne Beschriftungen die Reihenfolge der Puffer');
  Assert.AreEqual(Path('Projekt.dpr'), Ordered[4]);
end;

procedure TAtlasWelcomeContinueTests.MethodAtLastChange;
const
  Text = 'unit Kunde;'#10 + 'interface'#10 + 'type'#10 + '  TKunde = class'#10 + '    procedure Laden;'#10 +
    '  end;'#10 + 'implementation'#10 + 'procedure TKunde.Laden;'#10 + 'begin'#10 + '  Writeln;'#10 + 'end;'#10 +
    'end.'#10;
begin
  Assert.AreEqual('TKunde.Laden', TAtlasWelcomeContinue.MethodAt(Text, 10));
  Assert.AreEqual('', TAtlasWelcomeContinue.MethodAt(Text, 1), 'außerhalb jeder Methode');
  Assert.AreEqual('', TAtlasWelcomeContinue.MethodAt(Text, 0));
  Assert.AreEqual('', TAtlasWelcomeContinue.MethodAt('', 3));
end;

procedure TAtlasWelcomeContinueTests.SelectShowsOnlyCommitsOnWorkFiles;
var
  Commits: TArray<TAtlasVcsIncomingCommit>;
  Selected: TArray<TAtlasContinueCommit>;
  More: Boolean;
begin
  Commits := [Commit('1111111aaaa', 'Kunde erweitert', 'Eva', [Path('Kunde.pas'), Path('Neu.pas')]),
    Commit('2222222bbbb', 'Fremde Datei', 'Max', [Path('Andere.pas')]),
    Commit('3333333cccc', 'Merge', 'Max', nil),
    Commit('4444444dddd', 'Alt geändert', 'Eva', [Path('alt.PAS')])];
  Selected := TAtlasWelcomeContinue.Select(Commits, [Path('Kunde.pas'), Path('Alt.pas')], 8, More);
  Assert.AreEqual(2, Integer(Length(Selected)), 'nur Commits auf Dateien des Arbeitsstands');
  Assert.AreEqual('1111111aaaa', Selected[0].Commit.Hash, 'Reihenfolge bleibt');
  Assert.AreEqual('1111111', Selected[0].Commit.ShortHash);
  Assert.AreEqual(1, Integer(Length(Selected[0].Files)));
  Assert.AreEqual(Path('Kunde.pas'), Selected[0].Files[0], 'betroffene Datei');
  Assert.AreEqual(Path('Alt.pas'), Selected[1].Files[0], 'Groß/klein egal');
  Assert.IsFalse(More);
  Selected := TAtlasWelcomeContinue.Select(Commits, [Path('Kunde.pas'), Path('Alt.pas')], 1, More);
  Assert.AreEqual(1, Integer(Length(Selected)));
  Assert.IsTrue(More, '… und weitere');
end;

procedure TAtlasWelcomeContinueTests.IncomingCommitOnEditedFileAppears;
var
  Fake: TFakeVcs;
  Vcs: IAtlasVersionControl;
  State: TAtlasWorkState;
  Found: TAtlasContinueIncoming;
begin
  Fake := TFakeVcs.Create;
  Vcs := Fake;
  Fake.FKnown := ['aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'];
  Fake.FCommits := [Commit('5555555eeee', 'Kunde: Prüfung', 'Eva', [Path('Kunde.pas')]),
    Commit('6666666ffff', 'Anderes Modul', 'Max', [Path('Fremd.pas')])];
  State := StateOf(['Main.pas']);
  State.Edited := [Path('Kunde.pas')];
  State.Head := 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  State.Upstream := 'origin/main';
  State.UpstreamRevision := 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
  Assert.IsTrue(TAtlasWelcomeContinue.ProbeIncoming(Vcs, nil, Path('Atlas.dproj'), State, Stamp(9, 0), Found));
  Assert.IsTrue(Found.Available);
  Assert.AreEqual('origin/main', Found.Upstream);
  Assert.AreEqual(Path('Atlas.dproj'), Found.Project);
  Assert.AreEqual(1, Integer(Length(Found.Commits)), 'Commit zu einer bearbeiteten Datei, nicht zu anderen');
  Assert.AreEqual('Kunde: Prüfung', Found.Commits[0].Commit.Summary);
  Assert.AreEqual('Eva', Found.Commits[0].Commit.Author);
  Assert.AreEqual(Path('Kunde.pas'), Found.Commits[0].Files[0]);
  Assert.IsTrue(Fake.Called('incoming origin/main'));
  Assert.AreEqual(2, Integer(Length(Fake.Excluded)), 'HEAD und Upstream beim Schließen');
  Assert.AreEqual(State.Head, Fake.Excluded[0]);
  Assert.AreEqual(State.UpstreamRevision, Fake.Excluded[1]);
  Assert.IsFalse(Fake.Called('fetch'), 'ohne welcomePage.continue.fetch kein Abruf');
  Assert.IsFalse(Found.FetchFailed);
  // Unbekannter Stand (z. B. alte Commits verschwunden): gegenüber dem heutigen HEAD.
  Fake.FKnown := nil;
  Assert.IsTrue(TAtlasWelcomeContinue.ProbeIncoming(Vcs, nil, Path('Atlas.dproj'), State, Stamp(9, 0), Found));
  Assert.AreEqual(1, Integer(Length(Fake.Excluded)));
  Assert.AreEqual(Fake.FHead.Revision, Fake.Excluded[0]);
end;

procedure TAtlasWelcomeContinueTests.IncomingFetchOnlyWhenAsked;
var
  Fake: TFakeVcs;
  Vcs: IAtlasVersionControl;
  State: TAtlasWorkState;
  Found: TAtlasContinueIncoming;
begin
  Fake := TFakeVcs.Create;
  Vcs := Fake;
  State := StateOf(['Kunde.pas']);
  Assert.IsTrue(TAtlasWelcomeContinue.ProbeIncoming(Vcs, Vcs, Path('Atlas.dproj'), State, Stamp(9, 0), Found));
  Assert.IsTrue(Fake.Called('fetch'));
  Assert.IsTrue(Found.Available);
  Assert.IsFalse(Found.FetchFailed);
  // Abruf misslungen (Zeitlimit, Anmeldung nötig): Abschnitt mit dem lokalen Stand und Hinweis.
  Fake.FFetchOutcome := TAtlasVcsOutcome.TimedOut;
  Assert.IsTrue(TAtlasWelcomeContinue.ProbeIncoming(Vcs, Vcs, Path('Atlas.dproj'), State, Stamp(9, 0), Found));
  Assert.IsTrue(Found.Available);
  Assert.IsTrue(Found.FetchFailed);
end;

procedure TAtlasWelcomeContinueTests.IncomingWithoutVersionControlHasNoSection;
var
  Vcs: IAtlasVersionControl;
  Fake: TFakeVcs;
  Found: TAtlasContinueIncoming;
begin
  Vcs := TAtlasNullVersionControl.Create(TAtlasVcsOutcome.NoWorkingCopy);
  Assert.IsTrue(TAtlasWelcomeContinue.ProbeIncoming(Vcs, Vcs, Path('Atlas.dproj'), StateOf(['A.pas']), Stamp(9, 0),
    Found), 'kein Fehler');
  Assert.IsFalse(Found.Available, 'kein Abschnitt');
  Assert.IsFalse(Found.FetchFailed);
  Assert.IsFalse(TAtlasWelcomeContinue.ProbeIncoming(nil, nil, Path('Atlas.dproj'), StateOf(['A.pas']), Stamp(9, 0),
    Found));
  Assert.IsFalse(Found.Available);
  // Arbeitskopie verschwunden.
  Fake := TFakeVcs.Create;
  Vcs := Fake;
  Fake.FHeadOutcome := TAtlasVcsOutcome.NoWorkingCopy;
  Assert.IsTrue(TAtlasWelcomeContinue.ProbeIncoming(Vcs, nil, Path('Atlas.dproj'), StateOf(['A.pas']), Stamp(9, 0),
    Found));
  Assert.IsFalse(Found.Available);
  // Fehler beim Abfragen: Ergebnis gilt nicht.
  Fake.FHeadOutcome := TAtlasVcsOutcome.Failed;
  Assert.IsFalse(TAtlasWelcomeContinue.ProbeIncoming(Vcs, nil, Path('Atlas.dproj'), StateOf(['A.pas']), Stamp(9, 0),
    Found));
end;

procedure TAtlasWelcomeContinueTests.IncomingWithoutUpstreamHasNoSection;
var
  Fake: TFakeVcs;
  Vcs: IAtlasVersionControl;
  Found: TAtlasContinueIncoming;
begin
  Fake := TFakeVcs.Create;
  Vcs := Fake;
  Fake.FHead.Upstream := '';
  Assert.IsTrue(TAtlasWelcomeContinue.ProbeIncoming(Vcs, nil, Path('Atlas.dproj'), StateOf(['A.pas']), Stamp(9, 0),
    Found));
  Assert.IsFalse(Found.Available, 'Branch ohne Upstream');
  Assert.IsFalse(Fake.CalledStarting('incoming'), 'keine Abfrage');
  // SVN kennt keinen lokalen Stand des Servers: kein Abschnitt.
  Fake.FKind := TAtlasVcsKind.Svn;
  Fake.FHead.Branch := 'trunk';
  Fake.FHead.Revision := '42';
  Assert.IsTrue(TAtlasWelcomeContinue.ProbeIncoming(Vcs, nil, Path('Atlas.dproj'), StateOf(['A.pas']), Stamp(9, 0),
    Found));
  Assert.IsFalse(Found.Available);
end;

procedure TAtlasWelcomeContinueTests.ProbeHeadStoresHeadAndUpstream;
var
  Fake: TFakeVcs;
  Vcs: IAtlasVersionControl;
  State: TAtlasWorkState;
begin
  Fake := TFakeVcs.Create;
  Vcs := Fake;
  State := StateOf(['A.pas']);
  Assert.IsTrue(TAtlasWelcomeContinue.ProbeHead(Vcs, State));
  Assert.AreEqual('git', State.VcsKind);
  Assert.AreEqual(Fake.FHead.Revision, State.Head);
  Assert.AreEqual('origin/main', State.Upstream);
  Assert.AreEqual('uuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuu', State.UpstreamRevision);
  Vcs := TAtlasNullVersionControl.Create(TAtlasVcsOutcome.NoWorkingCopy);
  Assert.IsTrue(TAtlasWelcomeContinue.ProbeHead(Vcs, State), 'ohne Arbeitskopie kein Fehler');
  Assert.AreEqual('none', State.VcsKind);
  Assert.AreEqual('', State.Head);
  Assert.AreEqual('', State.Upstream);
  Fake := TFakeVcs.Create;
  Vcs := Fake;
  Fake.FHeadOutcome := TAtlasVcsOutcome.TimedOut;
  Assert.IsFalse(TAtlasWelcomeContinue.ProbeHead(Vcs, State));
  Assert.IsFalse(TAtlasWelcomeContinue.ProbeHead(nil, State));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasWelcomeContinueTests);

end.
