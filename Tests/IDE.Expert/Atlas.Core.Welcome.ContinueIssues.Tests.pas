unit Atlas.Core.Welcome.ContinueIssues.Tests;

// Tests des Arbeitsstands je Issue ohne VCL (#2052), Reiter „Issues“ in
// „Weiterarbeiten“: Format des Abschnitts "continueIssues" (Lesen, Schreiben,
// übrige Abschnitte bleiben), Grenze welcomePage.continue.issues.count,
// Auswahl nur offener Issues (behobene fallen heraus, unbekannte bleiben),
// Rückfrage zum Branch und Plan für „Fortsetzen“ mit fehlender Datei.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Welcome')]
  TAtlasWelcomeContinueIssuesTests = class
  public
    [Test]
    procedure EntriesRoundTripKeepContinueAndOtherFields;
    [Test]
    procedure WriteWithoutEntriesDropsSection;
    [Test]
    procedure ReadIgnoresBrokenEntries;
    [Test]
    procedure StoreReplacesSameKeyNewestFirst;
    [Test]
    procedure StoreDropsOldestBeyondLimit;
    [Test]
    procedure StoreNeedsKeyAndTabs;
    [Test]
    procedure ResolvedKeysAreRemoved;
    [Test]
    procedure RowsShowOnlyOpenOrUnknownIssues;
    [Test]
    procedure RowsNewestFirstLimitedAndEachProjectOnce;
    [Test]
    procedure BranchStepAsksOnlyForOtherExistingBranch;
    [Test]
    procedure PlanOpensTabsOfIssueAndNamesMissingFile;
  end;

implementation

uses
  System.SysUtils,
  System.DateUtils,
  Atlas.Core.Projects.Summary,
  Atlas.Core.Welcome.Projects,
  Atlas.Core.Welcome.Continue,
  Atlas.Core.Welcome.ContinueIssues;

const
  cRoot = 'C:\Repo';
  cProject = 'C:\Repo\Atlas.dproj';
  cOther = 'C:\Repo\Werkzeug.dproj';

function Path(const AName: string): string;
begin
  Result := cRoot + '\' + AName;
end;

function Stamp(AHour, AMinute: Word): TDateTime;
begin
  Result := EncodeDateTime(2026, 11, 11, AHour, AMinute, 0, 0);
end;

function StateOf(const ANames: TArray<string>; AHour: Word): TAtlasWorkState;
var
  mName: string;
begin
  Result := TAtlasWorkState.Empty;
  Result.Known := True;
  Result.At := Stamp(AHour, 0);
  for mName in ANames do
  begin
    Result.Tabs := Result.Tabs + [TAtlasWorkTab.Create(Path(mName), 1, 1)];
  end;
end;

function EntryOf(const AKey: string; AHour: Word): TAtlasIssueWorkEntry;
begin
  Result := TAtlasIssueWorkEntry.Create(AKey, 'Titel ' + AKey, 'feature/' + AKey, StateOf(['Main.pas'], AHour));
end;

function SummaryWith(const AProject: string; const AEntries: TAtlasIssueWorkEntries): TAtlasProjectSummary;
begin
  Result := TAtlasProjectSummary.Create(AProject);
  TAtlasWelcomeContinueIssues.Write(Result, AEntries);
end;

{ TAtlasWelcomeContinueIssuesTests }

procedure TAtlasWelcomeContinueIssuesTests.EntriesRoundTripKeepContinueAndOtherFields;
var
  mSummary, mParsed: TAtlasProjectSummary;
  mState: TAtlasWorkState;
  mEntries, mRead: TAtlasIssueWorkEntries;
  mJson: string;
begin
  Assert.IsTrue(TAtlasProjectSummaries.Parse('{"format":1,"project":"C:\\Repo\\Atlas.dproj","hidden":true,' +
    '"vcs":{"kind":"git","branch":"main"},"history":{"x":1}}', mSummary));
  TAtlasWelcomeContinue.Write(mSummary, StateOf(['Zuletzt.pas'], 7));
  mState := StateOf(['Kunde.pas', 'Main.pas'], 9);
  mState.Tabs[1] := TAtlasWorkTab.Create(Path('Main.pas'), 42, 5);
  mState.Tabs[1].Method := 'TMain.Laden';
  mState.Tabs[1].Changed := True;
  mState.Active := 1;
  mEntries := [TAtlasIssueWorkEntry.Create(' #1926 ', 'Größe prüfen', ' feature/1926-groesse ', mState),
    EntryOf('ATL-12', 8)];
  TAtlasWelcomeContinueIssues.Write(mSummary, mEntries);
  mJson := TAtlasProjectSummaries.ToJson(mSummary);
  Assert.Contains(mJson, '"history"', 'fremde Abschnitte bleiben');
  Assert.Contains(mJson, '"continueIssues"');
  Assert.IsTrue(TAtlasProjectSummaries.Parse(mJson, mParsed));
  Assert.IsTrue(mParsed.Hidden, 'bekannte Felder bleiben');
  Assert.IsTrue(TAtlasWelcomeContinue.Read(mParsed, mState), 'Abschnitt "continue" bleibt');
  Assert.AreEqual(Path('Zuletzt.pas'), mState.Tabs[0].FileName);
  Assert.IsTrue(TAtlasWelcomeContinueIssues.Read(mParsed, mRead));
  Assert.AreEqual(2, Integer(Length(mRead)));
  Assert.AreEqual('#1926', mRead[0].Key, 'Kennung ohne Leerraum, neueste zuerst');
  Assert.AreEqual('Größe prüfen', mRead[0].Title);
  Assert.AreEqual('feature/1926-groesse', mRead[0].Branch);
  Assert.AreEqual(2, mRead[0].State.TabCount);
  Assert.AreEqual(Path('Kunde.pas'), mRead[0].State.Tabs[0].FileName, 'Reihenfolge der Reiter');
  Assert.AreEqual(42, mRead[0].State.Tabs[1].Line);
  Assert.AreEqual('TMain.Laden', mRead[0].State.Tabs[1].Method);
  Assert.AreEqual(1, mRead[0].State.Active);
  Assert.IsTrue(Abs(mRead[0].State.At - Stamp(9, 0)) < OneSecond);
  Assert.AreEqual('ATL-12', mRead[1].Key);
  // Zweites Schreiben ersetzt den Abschnitt, statt einen zweiten anzulegen.
  TAtlasWelcomeContinueIssues.Write(mParsed, [EntryOf('#7', 10)]);
  Assert.IsTrue(TAtlasWelcomeContinueIssues.Read(mParsed, mRead));
  Assert.AreEqual(1, Integer(Length(mRead)));
  Assert.AreEqual('#7', mRead[0].Key);
  Assert.IsTrue(TAtlasWelcomeContinue.Read(mParsed, mState), '"continue" bleibt auch beim zweiten Schreiben');
end;

procedure TAtlasWelcomeContinueIssuesTests.WriteWithoutEntriesDropsSection;
var
  mSummary: TAtlasProjectSummary;
  mRead: TAtlasIssueWorkEntries;
begin
  mSummary := SummaryWith(cProject, [EntryOf('#1', 9)]);
  Assert.IsTrue(TAtlasWelcomeContinueIssues.Read(mSummary, mRead));
  TAtlasWelcomeContinueIssues.Write(mSummary, nil);
  Assert.IsFalse(TAtlasWelcomeContinueIssues.Read(mSummary, mRead), 'leer: kein Abschnitt');
  Assert.AreEqual(0, Integer(Length(mRead)));
  Assert.DoesNotContain(TAtlasProjectSummaries.ToJson(mSummary), 'continueIssues');
end;

procedure TAtlasWelcomeContinueIssuesTests.ReadIgnoresBrokenEntries;
var
  mEntries: TAtlasIssueWorkEntries;
begin
  Assert.IsFalse(TAtlasWelcomeContinueIssues.FromJson('kein JSON', mEntries));
  Assert.IsFalse(TAtlasWelcomeContinueIssues.FromJson('[1,2]', mEntries));
  Assert.IsTrue(TAtlasWelcomeContinueIssues.FromJson('{"#1":5,"":{"at":"x"},"#2":"text"}', mEntries));
  Assert.AreEqual(0, Integer(Length(mEntries)), 'Einträge ohne Objekt oder Kennung fallen weg');
end;

procedure TAtlasWelcomeContinueIssuesTests.StoreReplacesSameKeyNewestFirst;
var
  mEntries: TAtlasIssueWorkEntries;
  mFound: TAtlasIssueWorkEntry;
begin
  mEntries := nil;
  mEntries := TAtlasWelcomeContinueIssues.Store(mEntries, EntryOf('#1', 8), 10);
  mEntries := TAtlasWelcomeContinueIssues.Store(mEntries, EntryOf('#2', 9), 10);
  mEntries := TAtlasWelcomeContinueIssues.Store(mEntries, TAtlasIssueWorkEntry.Create('#1', 'Neu', '',
    StateOf(['A.pas', 'B.pas'], 10)), 10);
  Assert.AreEqual(2, Integer(Length(mEntries)), 'gleiche Kennung ersetzt');
  Assert.AreEqual('#1', mEntries[0].Key, 'zuletzt gespeichert vorn');
  Assert.AreEqual(2, mEntries[0].State.TabCount);
  Assert.AreEqual('#2', mEntries[1].Key);
  Assert.IsTrue(TAtlasWelcomeContinueIssues.Find(mEntries, ' #1', mFound), 'Kennung ohne Leerraum am Rand');
  Assert.AreEqual('Neu', mFound.Title);
  Assert.IsFalse(TAtlasWelcomeContinueIssues.Find(mEntries, '#3', mFound));
  Assert.IsTrue(TAtlasWelcomeContinueIssues.SameKey('atl-12', 'ATL-12 '));
end;

procedure TAtlasWelcomeContinueIssuesTests.StoreDropsOldestBeyondLimit;
var
  mEntries: TAtlasIssueWorkEntries;
  mIndex: Integer;
begin
  mEntries := nil;
  for mIndex := 1 to 12 do
  begin
    mEntries := TAtlasWelcomeContinueIssues.Store(mEntries, EntryOf('#' + IntToStr(mIndex), mIndex),
      TAtlasWelcomeContinueIssues.cDefaultCount);
  end;
  Assert.AreEqual(10, Integer(Length(mEntries)), 'Vorgabe 10');
  Assert.AreEqual('#12', mEntries[0].Key);
  Assert.AreEqual('#3', mEntries[9].Key, 'die ältesten (#1, #2) fallen heraus');
  Assert.AreEqual(1, Integer(Length(TAtlasWelcomeContinueIssues.Limit(mEntries, 0))), 'mindestens 1');
  Assert.AreEqual(10, Integer(Length(TAtlasWelcomeContinueIssues.Limit(mEntries, 99))), 'höchstens 30');
end;

procedure TAtlasWelcomeContinueIssuesTests.StoreNeedsKeyAndTabs;
var
  mEntries: TAtlasIssueWorkEntries;
begin
  mEntries := [EntryOf('#1', 8)];
  mEntries := TAtlasWelcomeContinueIssues.Store(mEntries, EntryOf('  ', 9), 10);
  Assert.AreEqual(1, Integer(Length(mEntries)), 'ohne Kennung unverändert');
  mEntries := TAtlasWelcomeContinueIssues.Store(mEntries, TAtlasIssueWorkEntry.Create('#2', '', '',
    StateOf([], 9)), 10);
  Assert.AreEqual(1, Integer(Length(mEntries)), 'ohne Reiter unverändert');
  Assert.AreEqual('#1', mEntries[0].Key);
end;

procedure TAtlasWelcomeContinueIssuesTests.ResolvedKeysAreRemoved;
var
  mEntries: TAtlasIssueWorkEntries;
  mKeys, mResolved: TArray<string>;
begin
  mEntries := [EntryOf('#3', 10), EntryOf('#2', 9), EntryOf('#1', 8)];
  mKeys := TAtlasWelcomeContinueIssues.Keys(mEntries);
  Assert.AreEqual('#3,#2,#1', string.Join(',', mKeys));
  mResolved := TAtlasWelcomeContinueIssues.ResolvedKeys(mKeys, [TAtlasIssueStateKind.Open,
    TAtlasIssueStateKind.Resolved]);
  Assert.AreEqual('#2', string.Join(',', mResolved), 'fehlender Zustand gilt als unbekannt');
  mEntries := TAtlasWelcomeContinueIssues.Without(mEntries, mResolved);
  Assert.AreEqual('#3,#1', string.Join(',', TAtlasWelcomeContinueIssues.Keys(mEntries)));
end;

procedure TAtlasWelcomeContinueIssuesTests.RowsShowOnlyOpenOrUnknownIssues;
var
  mRows: TAtlasIssueWorkRows;
  mAsked: TArray<string>;
begin
  mAsked := nil;
  mRows := TAtlasWelcomeContinueIssues.Rows([cProject],
    function(const AProject: string; out ASummary: TAtlasProjectSummary): Boolean
    begin
      ASummary := SummaryWith(AProject, [EntryOf('#3', 10), EntryOf('#2', 9), EntryOf('#1', 8)]);
      Result := True;
    end,
    function(const AProject: string; const AKeys: TArray<string>): TArray<TAtlasIssueStateKind>
    begin
      mAsked := AKeys;
      Result := [TAtlasIssueStateKind.Open, TAtlasIssueStateKind.Resolved];
    end, 10);
  Assert.AreEqual('#3,#2,#1', string.Join(',', mAsked), 'alle Kennungen eines Projekts in einer Frage');
  Assert.AreEqual(2, Integer(Length(mRows)), 'behobenes Issue fehlt');
  Assert.AreEqual('#3', mRows[0].Entry.Key);
  Assert.IsTrue(mRows[0].Status = TAtlasIssueStateKind.Open);
  Assert.AreEqual('#1', mRows[1].Entry.Key);
  Assert.IsTrue(mRows[1].Status = TAtlasIssueStateKind.Unknown, 'ohne Antwort: Zustand unbekannt, bleibt');
  Assert.AreEqual(cProject, mRows[0].Project);
  Assert.AreEqual(Path('Main.pas'), mRows[0].LastTab.FileName);
  // Ohne Tracker: alle unbekannt, keiner fällt weg.
  mRows := TAtlasWelcomeContinueIssues.Rows([cProject],
    function(const AProject: string; out ASummary: TAtlasProjectSummary): Boolean
    begin
      ASummary := SummaryWith(AProject, [EntryOf('#3', 10), EntryOf('#2', 9)]);
      Result := True;
    end, nil, 10);
  Assert.AreEqual(2, Integer(Length(mRows)));
  Assert.IsTrue(mRows[1].Status = TAtlasIssueStateKind.Unknown);
end;

procedure TAtlasWelcomeContinueIssuesTests.RowsNewestFirstLimitedAndEachProjectOnce;
var
  mRows: TAtlasIssueWorkRows;
  mLoads: Integer;
begin
  mLoads := 0;
  mRows := TAtlasWelcomeContinueIssues.Rows([cProject, '', cOther, LowerCase(cProject), 'C:\Repo\Leer.dproj'],
    function(const AProject: string; out ASummary: TAtlasProjectSummary): Boolean
    begin
      Inc(mLoads);
      Result := not SameText(AProject, 'C:\Repo\Leer.dproj');
      if SameText(AProject, cProject) then
      begin
        ASummary := SummaryWith(AProject, [EntryOf('#5', 12), EntryOf('#1', 8)]);
      end
      else
      begin
        ASummary := SummaryWith(AProject, [EntryOf('W-2', 11), EntryOf('W-1', 9)]);
      end;
    end, nil, 3);
  Assert.AreEqual(3, mLoads, 'jedes Projekt einmal, leere Pfade nicht');
  Assert.AreEqual(3, Integer(Length(mRows)), 'höchstens ACount');
  Assert.AreEqual('#5', mRows[0].Entry.Key, 'neueste zuerst über alle Projekte');
  Assert.AreEqual('W-2', mRows[1].Entry.Key);
  Assert.AreEqual(cOther, mRows[1].Project);
  Assert.AreEqual('W-1', mRows[2].Entry.Key);
  Assert.AreEqual(0, Integer(Length(TAtlasWelcomeContinueIssues.Rows([cProject], nil, nil, 10))), 'ohne Lader');
end;

procedure TAtlasWelcomeContinueIssuesTests.BranchStepAsksOnlyForOtherExistingBranch;
begin
  Assert.IsTrue(TAtlasWelcomeContinueIssues.BranchStep('', 'main', False) = TAtlasIssueBranchStep.Keep,
    'ohne gespeicherten Branch');
  Assert.IsTrue(TAtlasWelcomeContinueIssues.BranchStep('feature/1', 'Feature/1', True) = TAtlasIssueBranchStep.Keep,
    'schon ausgecheckt');
  Assert.IsTrue(TAtlasWelcomeContinueIssues.BranchStep('feature/1', 'main', True) = TAtlasIssueBranchStep.Ask,
    'anderer Branch: Rückfrage');
  Assert.IsTrue(TAtlasWelcomeContinueIssues.BranchStep('feature/1', 'main', False) = TAtlasIssueBranchStep.Missing,
    'Branch gelöscht: nur Reiter');
end;

procedure TAtlasWelcomeContinueIssuesTests.PlanOpensTabsOfIssueAndNamesMissingFile;
var
  mEntry: TAtlasIssueWorkEntry;
  mPlan: TAtlasContinuePlan;
begin
  mEntry := TAtlasIssueWorkEntry.Create('#1926', '', 'feature/1926', StateOf(['Kunde.pas', 'Alt.pas',
    'Main.pas'], 9));
  mEntry.State.Active := 2;
  mPlan := TAtlasWelcomeContinue.Plan(cProject, mEntry.State,
    function(const AFileName: string): Boolean
    begin
      Result := not SameText(AFileName, Path('Alt.pas'));
    end);
  Assert.AreEqual(cProject, mPlan.Project);
  Assert.AreEqual(2, Integer(Length(mPlan.Open)));
  Assert.AreEqual(Path('Kunde.pas'), mPlan.Open[0].FileName, 'Reihenfolge der Reiter');
  Assert.AreEqual(Path('Main.pas'), mPlan.Open[1].FileName);
  Assert.AreEqual(1, Integer(Length(mPlan.Missing)));
  Assert.AreEqual(Path('Alt.pas'), mPlan.Missing[0]);
  Assert.AreEqual(1, mPlan.Active, 'aktiver Reiter nach dem Überspringen');
end;

end.
