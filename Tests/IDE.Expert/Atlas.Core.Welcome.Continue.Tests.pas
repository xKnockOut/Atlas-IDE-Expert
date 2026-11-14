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
  [Category('Atlas.IDE.Welcome')]
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
    /// <summary>#1286: Ohne verfolgten Branch vergleicht „Eingehend“ gegen den Hauptbranch des Projekts.</summary>
    [Test]
    procedure IncomingWithoutUpstreamUsesMainBranch;
    [Test]
    procedure ProbeHeadStoresHeadAndUpstream;
  end;

implementation

uses
  System.SysUtils,
  System.DateUtils,
  Atlas.Core.Projects.Summary,
  Atlas.Core.VersionControl.Contract,
  Atlas.Core.VersionControl.Providers.Null,
  Atlas.Core.Welcome.Projects,
  Atlas.Core.Welcome.Continue;

const
  cRoot = 'C:\Repo';

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
  Result.Root := cRoot;
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
  mKnown: string;
begin
  Calls := Calls + ['resolve ' + ARef];
  ARevision := '';
  Result := TAtlasVcsOutcome.Failed;
  for mKnown in FKnown do
  begin
    if mKnown = ARef then
    begin
      ARevision := ARef;
      Exit(TAtlasVcsOutcome.Ok);
    end;
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
  mCall: string;
begin
  Result := False;
  for mCall in Calls do
  begin
    if mCall = AName then
    begin
      Exit(True);
    end;
  end;
end;

function TFakeVcs.CalledStarting(const APrefix: string): Boolean;
var
  mCall: string;
begin
  Result := False;
  for mCall in Calls do
  begin
    if mCall.StartsWith(APrefix) then
    begin
      Exit(True);
    end;
  end;
end;

function Path(const AName: string): string;
begin
  Result := cRoot + '\' + AName;
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
  mName: string;
begin
  Result := TAtlasWorkState.Empty;
  Result.Known := True;
  Result.At := Stamp(9, 0);
  for mName in ANames do
  begin
    Result.Tabs := Result.Tabs + [TAtlasWorkTab.Create(Path(mName), 1, 1)];
  end;
end;

{ TAtlasWelcomeContinueTests }

procedure TAtlasWelcomeContinueTests.WorkStateRoundTripKeepsSummary;
var
  mSummary, mParsed: TAtlasProjectSummary;
  mState, mRead_: TAtlasWorkState;
  mJson: string;
begin
  Assert.IsTrue(TAtlasProjectSummaries.Parse('{"format":1,"project":"C:\\Repo\\Atlas.dproj","hidden":true,' +
    '"vcs":{"kind":"git","branch":"main"},"unsaved":{"kind":"git"},"history":{"x":1}}', mSummary));
  mState := StateOf(['Kunde.pas', 'Main.pas', 'Liste.pas']);
  mState.Tabs[1] := TAtlasWorkTab.Create(Path('Main.pas'), 42, 5);
  mState.Tabs[1].Method := 'TMain.Laden';
  mState.Tabs[1].Changed := True;
  mState.Tabs[1].ChangedAt := Stamp(8, 55);
  mState.Active := 2;
  mState.Edited := [Path('Alt.pas')];
  mState.VcsKind := 'git';
  mState.Head := 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  mState.Upstream := 'origin/main';
  mState.UpstreamRevision := 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
  TAtlasWelcomeContinue.Write(mSummary, mState);
  mJson := TAtlasProjectSummaries.ToJson(mSummary);
  Assert.Contains(mJson, '"history"', 'fremde Abschnitte bleiben');
  Assert.Contains(mJson, '"unsaved"', 'Abschnitt von #762 bleibt');
  Assert.IsTrue(TAtlasProjectSummaries.Parse(mJson, mParsed));
  Assert.IsTrue(mParsed.Hidden, 'bekannte Felder bleiben');
  Assert.AreEqual('main', mParsed.Vcs.Branch);
  Assert.IsTrue(TAtlasWelcomeContinue.Read(mParsed, mRead_));
  Assert.IsTrue(mRead_.Known);
  Assert.AreEqual(3, mRead_.TabCount);
  Assert.AreEqual(Path('Kunde.pas'), mRead_.Tabs[0].FileName, 'Reihenfolge');
  Assert.AreEqual(Path('Main.pas'), mRead_.Tabs[1].FileName);
  Assert.AreEqual(Path('Liste.pas'), mRead_.Tabs[2].FileName);
  Assert.AreEqual(42, mRead_.Tabs[1].Line);
  Assert.AreEqual(5, mRead_.Tabs[1].Column);
  Assert.AreEqual('TMain.Laden', mRead_.Tabs[1].Method);
  Assert.IsTrue(mRead_.Tabs[1].Changed);
  Assert.IsTrue(Abs(mRead_.Tabs[1].ChangedAt - Stamp(8, 55)) < OneSecond);
  Assert.IsFalse(mRead_.Tabs[0].Changed);
  Assert.AreEqual(2, mRead_.Active);
  Assert.IsTrue(Abs(mRead_.At - Stamp(9, 0)) < OneSecond);
  Assert.AreEqual(1, Integer(Length(mRead_.Edited)));
  Assert.AreEqual(Path('Alt.pas'), mRead_.Edited[0]);
  Assert.AreEqual('git', mRead_.VcsKind);
  Assert.AreEqual(mState.Head, mRead_.Head);
  Assert.AreEqual('origin/main', mRead_.Upstream);
  Assert.AreEqual(mState.UpstreamRevision, mRead_.UpstreamRevision);
  // Zweites Schreiben ersetzt den Abschnitt, statt einen zweiten anzulegen.
  mState.Active := 0;
  TAtlasWelcomeContinue.Write(mParsed, mState);
  Assert.IsTrue(TAtlasWelcomeContinue.Read(mParsed, mRead_));
  Assert.AreEqual(0, mRead_.Active);
  Assert.AreEqual(1, Integer(Length(TAtlasProjectSummaries.ToJson(mParsed).Split(['"continue"']))) - 1);
end;

procedure TAtlasWelcomeContinueTests.ReadIgnoresBrokenSection;
var
  mSummary: TAtlasProjectSummary;
  mState: TAtlasWorkState;
begin
  Assert.IsTrue(TAtlasProjectSummaries.Parse('{"format":1,"project":"C:\\Repo\\Atlas.dproj"}', mSummary));
  Assert.IsFalse(TAtlasWelcomeContinue.Read(mSummary, mState), 'ohne Abschnitt');
  Assert.AreEqual(-1, mState.Active);
  Assert.IsTrue(TAtlasWelcomeContinue.FromJson('{"active":9,"tabs":[{"file":""},{"line":3},' +
    '{"file":"C:\\Repo\\A.pas","line":-4,"column":"x"},7],"edited":[1,""]}', mState));
  Assert.AreEqual(1, mState.TabCount, 'Reiter ohne Datei fallen weg');
  Assert.AreEqual(0, mState.Tabs[0].Line, 'negative Zeile wird 0');
  Assert.AreEqual(0, mState.Tabs[0].Column);
  Assert.AreEqual(-1, mState.Active, 'aktiver Reiter außerhalb');
  Assert.AreEqual(0, Integer(Length(mState.Edited)));
  Assert.IsFalse(TAtlasWelcomeContinue.FromJson('kein json', mState));
end;

procedure TAtlasWelcomeContinueTests.BuildTakesChangesAndKeepsOlderOnes;
var
  mOpen, mChanges: TArray<TAtlasWorkTab>;
  mOld, mState: TAtlasWorkState;
  mChange: TAtlasWorkTab;
begin
  mOpen := [TAtlasWorkTab.Create(Path('A.pas'), 10, 1), TAtlasWorkTab.Create(Path('B.pas'), 20, 2),
    TAtlasWorkTab.Create(Path('C.pas'), 30, 3), TAtlasWorkTab.Create(Path('a.PAS'), 99, 9)];
  // Änderung in A (diese Sitzung) und in einer inzwischen geschlossenen Datei.
  mChange := TAtlasWorkTab.Create(Path('A.pas'), 12, 7);
  mChange.ChangedAt := Stamp(10, 5);
  mChanges := [mChange, TAtlasWorkTab.Create(Path('Zu.pas'), 3, 1)];
  // Gespeicherte Änderung in B aus einer früheren Sitzung.
  mOld := StateOf(['B.pas']);
  mOld.Tabs[0] := TAtlasWorkTab.Create(Path('B.pas'), 77, 4);
  mOld.Tabs[0].Changed := True;
  mOld.Tabs[0].ChangedAt := Stamp(8, 0);
  mOld.Tabs[0].Method := 'TB.Alt';
  mState := TAtlasWelcomeContinue.Build(mOpen, Path('C.pas'), mChanges, mOld, Stamp(11, 0));
  Assert.IsTrue(mState.Known);
  Assert.AreEqual(3, mState.TabCount, 'dieselbe Datei zweimal zählt einmal');
  Assert.AreEqual(12, mState.Tabs[0].Line, 'Änderung statt Cursor');
  Assert.AreEqual(7, mState.Tabs[0].Column);
  Assert.IsTrue(mState.Tabs[0].Changed);
  Assert.IsTrue(Abs(mState.Tabs[0].ChangedAt - Stamp(10, 5)) < OneSecond);
  Assert.AreEqual(77, mState.Tabs[1].Line, 'frühere Änderung bleibt die letzte');
  Assert.AreEqual('TB.Alt', mState.Tabs[1].Method);
  Assert.IsTrue(mState.Tabs[1].Changed);
  Assert.AreEqual(30, mState.Tabs[2].Line, 'ohne Änderung der Cursor');
  Assert.IsFalse(mState.Tabs[2].Changed);
  Assert.AreEqual(2, mState.Active);
  Assert.AreEqual(1, Integer(Length(mState.Edited)));
  Assert.AreEqual(Path('Zu.pas'), mState.Edited[0]);
  Assert.IsTrue(Abs(mState.At - Stamp(11, 0)) < OneSecond);
  Assert.AreEqual(4, Integer(Length(mState.Files)), 'Reiter und geänderte Dateien');
end;

procedure TAtlasWelcomeContinueTests.SevenTabsResumeInSameOrderAtLastChange;
var
  mNames: TArray<string>;
  mOpen, mChanges: TArray<TAtlasWorkTab>;
  mChange: TAtlasWorkTab;
  mSummary, mParsed: TAtlasProjectSummary;
  mState, mRead_: TAtlasWorkState;
  mPlan: TAtlasContinuePlan;
  mName: string;
  mIndex: Integer;
begin
  mNames := ['Main.pas', 'Kunde.pas', 'Liste.pas', 'Daten.pas', 'Hilfe.pas', 'Form1.pas', 'Projekt.dpr'];
  mOpen := nil;
  for mName in mNames do
  begin
    mOpen := mOpen + [TAtlasWorkTab.Create(Path(mName), 5, 3)];
  end;
  mChange := TAtlasWorkTab.Create(Path('Daten.pas'), 120, 14);
  mChange.ChangedAt := Stamp(17, 30);
  mChanges := [mChange];
  mState := TAtlasWelcomeContinue.Build(mOpen, Path('Hilfe.pas'), mChanges, TAtlasWorkState.Empty, Stamp(18, 40));
  mSummary := TAtlasProjectSummary.Create(Path('Atlas.dproj'));
  TAtlasWelcomeContinue.Write(mSummary, mState);
  Assert.IsTrue(TAtlasProjectSummaries.Parse(TAtlasProjectSummaries.ToJson(mSummary), mParsed));
  Assert.IsTrue(TAtlasWelcomeContinue.Read(mParsed, mRead_));
  Assert.AreEqual(7, mRead_.TabCount);
  mPlan := TAtlasWelcomeContinue.Plan(Path('Atlas.dproj'), mRead_, nil);
  Assert.AreEqual(7, Integer(Length(mPlan.Open)));
  Assert.AreEqual(0, Integer(Length(mPlan.Missing)));
  for mIndex := 0 to High(mNames) do
  begin
    Assert.AreEqual(Path(mNames[mIndex]), mPlan.Open[mIndex].FileName, 'gleiche Reihenfolge');
  end;
  Assert.AreEqual(4, mPlan.Active, 'zuletzt aktiver Reiter');
  Assert.AreEqual(120, mPlan.Open[3].Line, 'Cursor an der letzten Änderung');
  Assert.AreEqual(14, mPlan.Open[3].Column);
  Assert.AreEqual(3, mRead_.LastIndex, 'zuletzt bearbeitet');
  // Ohne bekannten aktiven Reiter: die zuletzt bearbeitete Datei.
  mRead_.Active := -1;
  mPlan := TAtlasWelcomeContinue.Plan(Path('Atlas.dproj'), mRead_, nil);
  Assert.AreEqual(3, mPlan.Active);
end;

procedure TAtlasWelcomeContinueTests.DeletedFileIsSkippedAndNamed;
var
  mState: TAtlasWorkState;
  mPlan: TAtlasContinuePlan;
begin
  mState := StateOf(['A.pas', 'Weg.pas', 'C.pas', 'D.pas']);
  mState.Active := 3;
  mPlan := TAtlasWelcomeContinue.Plan(Path('Atlas.dproj'), mState,
    function(const AFileName: string): Boolean
    begin
      Result := not AFileName.EndsWith('Weg.pas');
    end);
  Assert.AreEqual(3, Integer(Length(mPlan.Open)));
  Assert.AreEqual(Path('A.pas'), mPlan.Open[0].FileName);
  Assert.AreEqual(Path('C.pas'), mPlan.Open[1].FileName);
  Assert.AreEqual(Path('D.pas'), mPlan.Open[2].FileName);
  Assert.AreEqual(1, Integer(Length(mPlan.Missing)));
  Assert.AreEqual(Path('Weg.pas'), mPlan.Missing[0], 'genannt');
  Assert.AreEqual(2, mPlan.Active, 'Index in der verkürzten Liste');
  // Fehlt der aktive Reiter selbst, ist der zuletzt geöffnete aktiv.
  mState.Active := 1;
  mPlan := TAtlasWelcomeContinue.Plan(Path('Atlas.dproj'), mState,
    function(const AFileName: string): Boolean
    begin
      Result := not AFileName.EndsWith('Weg.pas');
    end);
  Assert.AreEqual(2, mPlan.Active);
  Assert.AreEqual(Path('Atlas.dproj'), mPlan.Project);
end;

procedure TAtlasWelcomeContinueTests.EntriesNewestFirstLimitedAndWithTabs;
var
  mRecent: TArray<string>;
  mEntries: TAtlasContinueEntries;
  mLoader: TAtlasProjectSummaryLoader;
begin
  mRecent := ['C:\A\A.dproj', 'C:\B\B.groupproj', 'C:\C\C.dproj', 'c:\a\a.DPROJ', 'C:\Leer\Leer.dproj',
    'C:\Ohne\Ohne.dproj', 'C:\D\D.dproj'];
  mLoader :=
    function(const AProject: string; out ASummary: TAtlasProjectSummary): Boolean
    var
      State: TAtlasWorkState;
      Hour: Word;
    begin
      ASummary := TAtlasProjectSummary.Create(AProject);
      Result := not AProject.Contains('Ohne');
      if not Result then
      begin
        Exit;
      end;
      State := StateOf(['X.pas']);
      if AProject.Contains('Leer') then
      begin
        State.Tabs := nil;
      end;
      Hour := 8;
      if AProject.Contains('B.') then
      begin
        Hour := 12;
      end;
      if AProject.Contains('C.') then
      begin
        Hour := 10;
      end;
      if AProject.Contains('D.') then
      begin
        Hour := 10;
      end;
      State.At := Stamp(Hour, 0);
      TAtlasWelcomeContinue.Write(ASummary, State);
    end;
  mEntries := TAtlasWelcomeContinue.Entries(mRecent, mLoader, 5);
  Assert.AreEqual(4, Integer(Length(mEntries)), 'ohne Reiter, ohne Zusammenfassung und doppelt fallen weg');
  Assert.AreEqual('C:\B\B.groupproj', mEntries[0].Project, 'neueste zuerst');
  Assert.IsTrue(mEntries[0].IsGroup);
  Assert.AreEqual('B', mEntries[0].Name);
  Assert.AreEqual('C:\C\C.dproj', mEntries[1].Project, 'Gleichstand: Reihenfolge der IDE');
  Assert.AreEqual('C:\D\D.dproj', mEntries[2].Project);
  Assert.AreEqual('C:\A\A.dproj', mEntries[3].Project);
  mEntries := TAtlasWelcomeContinue.Entries(mRecent, mLoader, 2);
  Assert.AreEqual(2, Integer(Length(mEntries)), 'höchstens welcomePage.continue.count');
  mEntries := TAtlasWelcomeContinue.Entries(mRecent, mLoader, 0);
  Assert.AreEqual(1, Integer(Length(mEntries)), 'mindestens einer');
  mEntries := TAtlasWelcomeContinue.Entries(mRecent, nil, 5);
  Assert.AreEqual(0, Integer(Length(mEntries)));
end;

procedure TAtlasWelcomeContinueTests.LastTabIsNewestChange;
var
  mEntry: TAtlasContinueEntry;
begin
  mEntry := Default(TAtlasContinueEntry);
  mEntry.Project := 'C:\Repo\Atlas.dproj';
  mEntry.State := StateOf(['A.pas', 'B.pas', 'C.pas']);
  Assert.AreEqual(Path('A.pas'), mEntry.LastTab.FileName, 'ohne Änderung und aktiven Reiter der erste');
  mEntry.State.Active := 2;
  Assert.AreEqual(Path('C.pas'), mEntry.LastTab.FileName, 'sonst der aktive');
  mEntry.State.Tabs[0].Changed := True;
  mEntry.State.Tabs[0].ChangedAt := Stamp(9, 0);
  mEntry.State.Tabs[1].Changed := True;
  mEntry.State.Tabs[1].ChangedAt := Stamp(10, 0);
  mEntry.State.Tabs[1].Method := 'TB.Speichern';
  Assert.AreEqual(Path('B.pas'), mEntry.LastTab.FileName, 'jüngste Änderung');
  Assert.AreEqual('TB.Speichern', mEntry.LastTab.Method);
  Assert.AreEqual('Atlas', mEntry.Name);
  Assert.IsFalse(mEntry.IsGroup);
  mEntry.State.Tabs := nil;
  Assert.AreEqual('', mEntry.LastTab.FileName);
end;

procedure TAtlasWelcomeContinueTests.AgeTexts;
var
  mValue: Integer;
  mNow_: TDateTime;
begin
  mNow_ := Stamp(20, 0);
  Assert.AreEqual<TAtlasContinueAge>(TAtlasContinueAge.JustNow,
    TAtlasWelcomeContinue.Age(mNow_ - 20 * OneSecond, mNow_, mValue));
  Assert.AreEqual<TAtlasContinueAge>(TAtlasContinueAge.JustNow,
    TAtlasWelcomeContinue.Age(mNow_ + OneMinute, mNow_, mValue),
    'Zukunft (Uhr verstellt)');
  Assert.AreEqual<TAtlasContinueAge>(TAtlasContinueAge.Minutes,
    TAtlasWelcomeContinue.Age(Stamp(19, 35), mNow_, mValue));
  Assert.AreEqual(25, mValue);
  Assert.AreEqual<TAtlasContinueAge>(TAtlasContinueAge.Hours,
    TAtlasWelcomeContinue.Age(Stamp(17, 50), mNow_, mValue), 'vor 2 Std.');
  Assert.AreEqual(2, mValue);
  Assert.AreEqual<TAtlasContinueAge>(TAtlasContinueAge.Yesterday,
    TAtlasWelcomeContinue.Age(Stamp(18, 40) - 1, mNow_, mValue),
    'gestern 18:40');
  Assert.AreEqual<TAtlasContinueAge>(TAtlasContinueAge.Yesterday,
    TAtlasWelcomeContinue.Age(Stamp(23, 0) - 1, Stamp(0, 30), mValue),
    'kurz nach Mitternacht: gestern, nicht vor 1 Std.');
  Assert.AreEqual<TAtlasContinueAge>(TAtlasContinueAge.Date,
    TAtlasWelcomeContinue.Age(Stamp(18, 40) - 3, mNow_, mValue));
end;

procedure TAtlasWelcomeContinueTests.OrderFollowsTabCaptions;
var
  mFiles, mOrdered: TArray<string>;
begin
  mFiles := [Path('A.pas'), Path('B.pas'), Path('Sub\B.pas'), Path('C.pas'), Path('Projekt.dpr')];
  mOrdered := TAtlasWelcomeContinue.OrderByTabs(mFiles, ['Willkommensseite', 'C.pas', '*B.pas', 'Projekt', 'B.pas*',
    'A']);
  Assert.AreEqual(5, Integer(Length(mOrdered)));
  Assert.AreEqual(Path('C.pas'), mOrdered[0]);
  Assert.AreEqual(Path('B.pas'), mOrdered[1], 'Markierung „*“ zählt nicht');
  Assert.AreEqual(Path('Projekt.dpr'), mOrdered[2], 'Beschriftung ohne Endung');
  Assert.AreEqual(Path('Sub\B.pas'), mOrdered[3], 'gleicher Name: der nächste noch freie');
  Assert.AreEqual(Path('A.pas'), mOrdered[4]);
  mOrdered := TAtlasWelcomeContinue.OrderByTabs(mFiles, nil);
  Assert.AreEqual(Path('A.pas'), mOrdered[0], 'ohne Beschriftungen die Reihenfolge der Puffer');
  Assert.AreEqual(Path('Projekt.dpr'), mOrdered[4]);
end;

procedure TAtlasWelcomeContinueTests.MethodAtLastChange;
const
  cText = 'unit Kunde;'#10 + 'interface'#10 + 'type'#10 + '  TKunde = class'#10 + '    procedure Laden;'#10 +
    '  end;'#10 + 'implementation'#10 + 'procedure TKunde.Laden;'#10 + 'begin'#10 + '  Writeln;'#10 + 'end;'#10 +
    'end.'#10;
begin
  Assert.AreEqual('TKunde.Laden', TAtlasWelcomeContinue.MethodAt(cText, 10));
  Assert.AreEqual('', TAtlasWelcomeContinue.MethodAt(cText, 1), 'außerhalb jeder Methode');
  Assert.AreEqual('', TAtlasWelcomeContinue.MethodAt(cText, 0));
  Assert.AreEqual('', TAtlasWelcomeContinue.MethodAt('', 3));
end;

procedure TAtlasWelcomeContinueTests.SelectShowsOnlyCommitsOnWorkFiles;
var
  mCommits: TArray<TAtlasVcsIncomingCommit>;
  mSelected: TArray<TAtlasContinueCommit>;
  mMore: Boolean;
begin
  mCommits := [Commit('1111111aaaa', 'Kunde erweitert', 'Eva', [Path('Kunde.pas'), Path('Neu.pas')]),
    Commit('2222222bbbb', 'Fremde Datei', 'Max', [Path('Andere.pas')]),
    Commit('3333333cccc', 'Merge', 'Max', nil),
    Commit('4444444dddd', 'Alt geändert', 'Eva', [Path('alt.PAS')])];
  mSelected := TAtlasWelcomeContinue.Select(mCommits, [Path('Kunde.pas'), Path('Alt.pas')], 8, mMore);
  Assert.AreEqual(2, Integer(Length(mSelected)), 'nur Commits auf Dateien des Arbeitsstands');
  Assert.AreEqual('1111111aaaa', mSelected[0].Commit.Hash, 'Reihenfolge bleibt');
  Assert.AreEqual('1111111', mSelected[0].Commit.ShortHash);
  Assert.AreEqual(1, Integer(Length(mSelected[0].Files)));
  Assert.AreEqual(Path('Kunde.pas'), mSelected[0].Files[0], 'betroffene Datei');
  Assert.AreEqual(Path('Alt.pas'), mSelected[1].Files[0], 'Groß/klein egal');
  Assert.IsFalse(mMore);
  mSelected := TAtlasWelcomeContinue.Select(mCommits, [Path('Kunde.pas'), Path('Alt.pas')], 1, mMore);
  Assert.AreEqual(1, Integer(Length(mSelected)));
  Assert.IsTrue(mMore, '… und weitere');
end;

procedure TAtlasWelcomeContinueTests.IncomingCommitOnEditedFileAppears;
var
  mFake: TFakeVcs;
  mVcs: IAtlasVersionControl;
  mState: TAtlasWorkState;
  mFound: TAtlasContinueIncoming;
begin
  mFake := TFakeVcs.Create;
  mVcs := mFake;
  mFake.FKnown := ['aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'];
  mFake.FCommits := [Commit('5555555eeee', 'Kunde: Prüfung', 'Eva', [Path('Kunde.pas')]),
    Commit('6666666ffff', 'Anderes Modul', 'Max', [Path('Fremd.pas')])];
  mState := StateOf(['Main.pas']);
  mState.Edited := [Path('Kunde.pas')];
  mState.Head := 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  mState.Upstream := 'origin/main';
  mState.UpstreamRevision := 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
  Assert.IsTrue(TAtlasWelcomeContinue.ProbeIncoming(mVcs, nil, Path('Atlas.dproj'), mState, Stamp(9, 0), mFound));
  Assert.IsTrue(mFound.Available);
  Assert.AreEqual('origin/main', mFound.Upstream);
  Assert.AreEqual(Path('Atlas.dproj'), mFound.Project);
  Assert.AreEqual(1, Integer(Length(mFound.Commits)), 'Commit zu einer bearbeiteten Datei, nicht zu anderen');
  Assert.AreEqual('Kunde: Prüfung', mFound.Commits[0].Commit.Summary);
  Assert.AreEqual('Eva', mFound.Commits[0].Commit.Author);
  Assert.AreEqual(Path('Kunde.pas'), mFound.Commits[0].Files[0]);
  Assert.IsTrue(mFake.Called('incoming origin/main'));
  Assert.AreEqual(2, Integer(Length(mFake.Excluded)), 'HEAD und Upstream beim Schließen');
  Assert.AreEqual(mState.Head, mFake.Excluded[0]);
  Assert.AreEqual(mState.UpstreamRevision, mFake.Excluded[1]);
  Assert.IsFalse(mFake.Called('fetch'), 'ohne welcomePage.continue.fetch kein Abruf');
  Assert.IsFalse(mFound.FetchFailed);
  // Unbekannter Stand (z. B. alte Commits verschwunden): gegenüber dem heutigen HEAD.
  mFake.FKnown := nil;
  Assert.IsTrue(TAtlasWelcomeContinue.ProbeIncoming(mVcs, nil, Path('Atlas.dproj'), mState, Stamp(9, 0), mFound));
  Assert.AreEqual(1, Integer(Length(mFake.Excluded)));
  Assert.AreEqual(mFake.FHead.Revision, mFake.Excluded[0]);
end;

procedure TAtlasWelcomeContinueTests.IncomingFetchOnlyWhenAsked;
var
  mFake: TFakeVcs;
  mVcs: IAtlasVersionControl;
  mState: TAtlasWorkState;
  mFound: TAtlasContinueIncoming;
begin
  mFake := TFakeVcs.Create;
  mVcs := mFake;
  mState := StateOf(['Kunde.pas']);
  Assert.IsTrue(TAtlasWelcomeContinue.ProbeIncoming(mVcs, mVcs, Path('Atlas.dproj'), mState, Stamp(9, 0), mFound));
  Assert.IsTrue(mFake.Called('fetch'));
  Assert.IsTrue(mFound.Available);
  Assert.IsFalse(mFound.FetchFailed);
  // Abruf misslungen (Zeitlimit, Anmeldung nötig): Abschnitt mit dem lokalen Stand und Hinweis.
  mFake.FFetchOutcome := TAtlasVcsOutcome.TimedOut;
  Assert.IsTrue(TAtlasWelcomeContinue.ProbeIncoming(mVcs, mVcs, Path('Atlas.dproj'), mState, Stamp(9, 0), mFound));
  Assert.IsTrue(mFound.Available);
  Assert.IsTrue(mFound.FetchFailed);
  Assert.IsFalse(mFound.LoginNeeded);
  // Anmeldung fehlt (#1287): Ursache statt stillem Scheitern.
  mFake.FFetchOutcome := TAtlasVcsOutcome.LoginNeeded;
  Assert.IsTrue(TAtlasWelcomeContinue.ProbeIncoming(mVcs, mVcs, Path('Atlas.dproj'), mState, Stamp(9, 0), mFound));
  Assert.IsTrue(mFound.FetchFailed);
  Assert.IsTrue(mFound.LoginNeeded);
end;

procedure TAtlasWelcomeContinueTests.IncomingWithoutVersionControlHasNoSection;
var
  mVcs: IAtlasVersionControl;
  mFake: TFakeVcs;
  mFound: TAtlasContinueIncoming;
begin
  mVcs := TAtlasNullVersionControl.Create(TAtlasVcsOutcome.NoWorkingCopy);
  Assert.IsTrue(TAtlasWelcomeContinue.ProbeIncoming(mVcs, mVcs, Path('Atlas.dproj'), StateOf(['A.pas']), Stamp(9, 0),
    mFound), 'kein Fehler');
  Assert.IsFalse(mFound.Available, 'kein Abschnitt');
  Assert.IsFalse(mFound.FetchFailed);
  Assert.IsFalse(TAtlasWelcomeContinue.ProbeIncoming(nil, nil, Path('Atlas.dproj'), StateOf(['A.pas']), Stamp(9, 0),
    mFound));
  Assert.IsFalse(mFound.Available);
  // Arbeitskopie verschwunden.
  mFake := TFakeVcs.Create;
  mVcs := mFake;
  mFake.FHeadOutcome := TAtlasVcsOutcome.NoWorkingCopy;
  Assert.IsTrue(TAtlasWelcomeContinue.ProbeIncoming(mVcs, nil, Path('Atlas.dproj'), StateOf(['A.pas']), Stamp(9, 0),
    mFound));
  Assert.IsFalse(mFound.Available);
  // Fehler beim Abfragen: Ergebnis gilt nicht.
  mFake.FHeadOutcome := TAtlasVcsOutcome.Failed;
  Assert.IsFalse(TAtlasWelcomeContinue.ProbeIncoming(mVcs, nil, Path('Atlas.dproj'), StateOf(['A.pas']), Stamp(9, 0),
    mFound));
end;

procedure TAtlasWelcomeContinueTests.IncomingWithoutUpstreamHasNoSection;
var
  mFake: TFakeVcs;
  mVcs: IAtlasVersionControl;
  mFound: TAtlasContinueIncoming;
begin
  mFake := TFakeVcs.Create;
  mVcs := mFake;
  mFake.FHead.Upstream := '';
  Assert.IsTrue(TAtlasWelcomeContinue.ProbeIncoming(mVcs, nil, Path('Atlas.dproj'), StateOf(['A.pas']), Stamp(9, 0),
    mFound));
  Assert.IsFalse(mFound.Available, 'Branch ohne Upstream');
  Assert.IsFalse(mFake.CalledStarting('incoming'), 'keine Abfrage');
  // SVN kennt keinen lokalen Stand des Servers: kein Abschnitt.
  mFake.FKind := TAtlasVcsKind.Svn;
  mFake.FHead.Branch := 'trunk';
  mFake.FHead.Revision := '42';
  Assert.IsTrue(TAtlasWelcomeContinue.ProbeIncoming(mVcs, nil, Path('Atlas.dproj'), StateOf(['A.pas']), Stamp(9, 0),
    mFound));
  Assert.IsFalse(mFound.Available);
end;

procedure TAtlasWelcomeContinueTests.IncomingWithoutUpstreamUsesMainBranch;
var
  mFake: TFakeVcs;
  mVcs: IAtlasVersionControl;
  mFound: TAtlasContinueIncoming;
begin
  mFake := TFakeVcs.Create;
  mVcs := mFake;
  mFake.FHead.Branch := 'feature/42-kasse';
  mFake.FHead.Upstream := '';
  mFake.FKnown := ['origin/develop'];
  Assert.IsTrue(TAtlasWelcomeContinue.ProbeIncoming(mVcs, nil, TAtlasContinueProbe.Create(Path('Atlas.dproj'), 'develop',
    StateOf(['A.pas']), Stamp(9, 0)), mFound));
  Assert.IsTrue(mFound.Available);
  Assert.AreEqual('origin/develop', mFound.Upstream);
  Assert.IsTrue(mFake.Called('incoming origin/develop'));
  // Nur lokal vorhanden: der lokale Hauptbranch.
  mFake.FKnown := ['develop'];
  mFake.Calls := nil;
  Assert.IsTrue(TAtlasWelcomeContinue.ProbeIncoming(mVcs, nil, TAtlasContinueProbe.Create(Path('Atlas.dproj'), 'develop',
    StateOf(['A.pas']), Stamp(9, 0)), mFound));
  Assert.AreEqual('develop', mFound.Upstream);
  // Auf dem Hauptbranch selbst und ohne Hauptbranch: kein Abschnitt wie bisher.
  mFake.FHead.Branch := 'develop';
  mFake.Calls := nil;
  Assert.IsTrue(TAtlasWelcomeContinue.ProbeIncoming(mVcs, nil, TAtlasContinueProbe.Create(Path('Atlas.dproj'), 'develop',
    StateOf(['A.pas']), Stamp(9, 0)), mFound));
  Assert.IsFalse(mFound.Available);
  Assert.IsFalse(mFake.CalledStarting('incoming'));
  mFake.FHead.Branch := 'feature/42-kasse';
  Assert.IsTrue(TAtlasWelcomeContinue.ProbeIncoming(mVcs, nil, TAtlasContinueProbe.Create(Path('Atlas.dproj'), '',
    StateOf(['A.pas']), Stamp(9, 0)), mFound));
  Assert.IsFalse(mFound.Available);
end;

procedure TAtlasWelcomeContinueTests.ProbeHeadStoresHeadAndUpstream;
var
  mFake: TFakeVcs;
  mVcs: IAtlasVersionControl;
  mState: TAtlasWorkState;
begin
  mFake := TFakeVcs.Create;
  mVcs := mFake;
  mState := StateOf(['A.pas']);
  Assert.IsTrue(TAtlasWelcomeContinue.ProbeHead(mVcs, mState));
  Assert.AreEqual('git', mState.VcsKind);
  Assert.AreEqual(mFake.FHead.Revision, mState.Head);
  Assert.AreEqual('origin/main', mState.Upstream);
  Assert.AreEqual('uuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuu', mState.UpstreamRevision);
  mVcs := TAtlasNullVersionControl.Create(TAtlasVcsOutcome.NoWorkingCopy);
  Assert.IsTrue(TAtlasWelcomeContinue.ProbeHead(mVcs, mState), 'ohne Arbeitskopie kein Fehler');
  Assert.AreEqual('none', mState.VcsKind);
  Assert.AreEqual('', mState.Head);
  Assert.AreEqual('', mState.Upstream);
  mFake := TFakeVcs.Create;
  mVcs := mFake;
  mFake.FHeadOutcome := TAtlasVcsOutcome.TimedOut;
  Assert.IsFalse(TAtlasWelcomeContinue.ProbeHead(mVcs, mState));
  Assert.IsFalse(TAtlasWelcomeContinue.ProbeHead(nil, mState));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasWelcomeContinueTests);

end.
