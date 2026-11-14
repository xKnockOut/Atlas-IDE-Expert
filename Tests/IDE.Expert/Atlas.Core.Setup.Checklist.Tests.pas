unit Atlas.Core.Setup.Checklist.Tests;

// Einrichtung mit Prüfliste (#625), Teil ohne VCL: Jede Prüfung liefert für
// einen gestellten Zustand Befund, Ampel und Knopf (Server fehlt, Version
// passt nicht, Index unvollständig …), jeder gelbe oder rote Punkt hat einen
// Knopf, der Fortschritt zählt die grünen Punkte (Zustandskachel #754), der
// Start öffnet die Prüfliste nur, solange etwas fest nicht grün ist, und
// „Server-Pfad wählen“ speichert den Pfad und macht die Prüfung grün.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasSetupChecklistTests = class
  public
    [Test]
    procedure ServerMissingIsRedWithChoosePath;
    [Test]
    procedure ServerVersionMismatchIsRed;
    [Test]
    procedure ServerReadyWithMatchingVersion;
    [Test]
    procedure ServerPhases;
    [Test]
    procedure VersionsMatchIgnoresBuildAndPrefix;
    [Test]
    procedure DelphiVersionAndPlatform;
    [Test]
    procedure IndexIncompleteNamesMissingProjects;
    [Test]
    procedure IndexBuildingShowsProgressPerProject;
    [Test]
    procedure IndexReadyForWholeGroup;
    [Test]
    procedure IndexWithoutServerOrProjects;
    [Test]
    procedure LibraryCache;
    [Test]
    procedure ErrorInsightDuplicateMessages;
    [Test]
    procedure KeysConflictOnlyWhenLeftToOther;
    [Test]
    procedure KeysCoverEditorCommands;
    [Test]
    procedure EveryNonGreenPointHasAButton;
    [Test]
    procedure ProgressCountsGreenPoints;
    [Test]
    procedure StartOpensOnlyWhileNotGreen;
    [Test]
    procedure StatusParsesWorkspaces;
    /// <summary>#2142: Token und laufender Aufbau je Arbeitsbereich, Prozent live über das Token.</summary>
    [Test]
    procedure StatusParsesIndexingPerWorkspace;
    /// <summary>#2142: Prozent, Stufe und Warten je Projekt; ein neuer Aufbau macht ein fertiges Projekt
    /// gelb.</summary>
    [Test]
    procedure IndexShowsStagePerProject;
    [Test]
    procedure ReportHasLinesAndNoIdentity;
  end;

  [TestFixture]
  TAtlasSetupControllerTests = class
  public
    [Test]
    procedure ChooseServerPathSavesPathAndTurnsGreen;
    [Test]
    procedure CancelledChoiceChangesNothing;
    [Test]
    procedure FixesCallTheEnvironment;
    [Test]
    procedure VersionOnlyOnChange;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Status.Contract,
  Atlas.Core.Status.Lines,
  Atlas.Core.Commands.KeyConflicts,
  Atlas.Core.Setup.Checklist;

/// <summary>Alles in Ordnung: Server 0.1.0 läuft, Delphi 13 Win64, zwei Projekte fertig indiziert.</summary>
function GoodInput: TAtlasSetupInput;
var
  mWorkspace: TAtlasSetupWorkspace;
begin
  Result := Default(TAtlasSetupInput);
  Result.ServerFound := True;
  Result.Server.Phase := TAtlasServerPhase.Running;
  Result.Server.Version := '0.1.0';
  Result.PluginVersion := '0.1.0';
  Result.BdsVersion := '37.0';
  Result.Platform := 'Win64';
  Result.Projects := ['Kunden', 'Export'];
  Result.IndexPercent := -1;
  Result.Status.Known := True;
  Result.Status.Units := 1569;
  mWorkspace := Default(TAtlasSetupWorkspace);
  mWorkspace.Name := 'Kunden';
  mWorkspace.Done := True;
  mWorkspace.LibraryCacheBytes := 5 * 1024 * 1024;
  Result.Status.Workspaces := [mWorkspace];
  mWorkspace.Name := 'Export';
  mWorkspace.LibraryCacheBytes := 0;
  Result.Status.Workspaces := Result.Status.Workspaces + [mWorkspace];
  Result.ErrorInsight := False;
  Result.AtlasProblems := True;
  Result.Keys := [TAtlasSetupKey.Create(TAtlasKeyEntry.Create(TAtlasKeyFunction.Palette, $6050, False),
    'Strg+Umschalt+P', '')];
end;

function Workspace(const AName: string; ADone: Boolean; ALibrary: Int64): TAtlasSetupWorkspace;
begin
  Result := Default(TAtlasSetupWorkspace);
  Result.Name := AName;
  Result.Done := ADone;
  Result.LibraryCacheBytes := ALibrary;
end;

{ TAtlasSetupChecklistTests }

procedure TAtlasSetupChecklistTests.ServerMissingIsRedWithChoosePath;
var
  mInput: TAtlasSetupInput;
  mCheck: TAtlasSetupResult;
begin
  mInput := GoodInput;
  mInput.ServerFound := False;
  mInput.Server := Default(TAtlasServerInfo);
  mCheck := TAtlasSetupChecklist.CheckServer(mInput);
  Assert.AreEqual(Ord(TAtlasSetupFinding.ServerMissing), Ord(mCheck.Finding));
  Assert.AreEqual(Ord(TAtlasStatusState.Red), Ord(mCheck.State));
  Assert.AreEqual(Ord(TAtlasSetupFix.ChooseServerPath), Ord(mCheck.Fix), 'Knopf „Server-Pfad wählen …“');
  Assert.IsFalse(mCheck.Pending, 'Fehlender Server ist ein fester Befund');
end;

procedure TAtlasSetupChecklistTests.ServerVersionMismatchIsRed;
var
  mInput: TAtlasSetupInput;
  mCheck: TAtlasSetupResult;
begin
  mInput := GoodInput;
  mInput.Server.Version := '0.0.9';
  mCheck := TAtlasSetupChecklist.CheckServer(mInput);
  Assert.AreEqual(Ord(TAtlasSetupFinding.ServerVersionMismatch), Ord(mCheck.Finding));
  Assert.AreEqual(Ord(TAtlasStatusState.Red), Ord(mCheck.State));
  Assert.AreEqual(Ord(TAtlasSetupFix.ChooseServerPath), Ord(mCheck.Fix));
  Assert.AreEqual(2, Integer(Length(mCheck.Args)));
  Assert.AreEqual('0.0.9', mCheck.Args[0]);
  Assert.AreEqual('0.1.0', mCheck.Args[1]);
end;

procedure TAtlasSetupChecklistTests.ServerReadyWithMatchingVersion;
var
  mCheck: TAtlasSetupResult;
begin
  mCheck := TAtlasSetupChecklist.CheckServer(GoodInput);
  Assert.AreEqual(Ord(TAtlasSetupFinding.ServerReady), Ord(mCheck.Finding));
  Assert.AreEqual(Ord(TAtlasStatusState.Green), Ord(mCheck.State));
  Assert.AreEqual(Ord(TAtlasSetupFix.None), Ord(mCheck.Fix));
  Assert.AreEqual('0.1.0', mCheck.Args[0]);
end;

procedure TAtlasSetupChecklistTests.ServerPhases;
var
  mInput: TAtlasSetupInput;
  mCheck: TAtlasSetupResult;
begin
  mInput := GoodInput;
  mInput.Server.Phase := TAtlasServerPhase.NotStarted;
  mCheck := TAtlasSetupChecklist.CheckServer(mInput);
  Assert.AreEqual(Ord(TAtlasSetupFinding.ServerNotStarted), Ord(mCheck.Finding));
  Assert.AreEqual(Ord(TAtlasStatusState.Yellow), Ord(mCheck.State));
  Assert.AreEqual(Ord(TAtlasSetupFix.StartServer), Ord(mCheck.Fix));
  Assert.IsTrue(mCheck.Pending, 'Der Server startet beim ersten Bedarf');
  mInput.Server.Phase := TAtlasServerPhase.Starting;
  mCheck := TAtlasSetupChecklist.CheckServer(mInput);
  Assert.AreEqual(Ord(TAtlasSetupFinding.ServerStarting), Ord(mCheck.Finding));
  Assert.IsTrue(mCheck.Pending);
  mInput.Server.Phase := TAtlasServerPhase.Stopped;
  mCheck := TAtlasSetupChecklist.CheckServer(mInput);
  Assert.AreEqual(Ord(TAtlasSetupFinding.ServerStopped), Ord(mCheck.Finding));
  Assert.AreEqual(Ord(TAtlasStatusState.Red), Ord(mCheck.State));
  Assert.AreEqual(Ord(TAtlasSetupFix.RestartServer), Ord(mCheck.Fix));
  mInput.Server.Phase := TAtlasServerPhase.Failed;
  mInput.Server.Error := 'Zeitlimit';
  mCheck := TAtlasSetupChecklist.CheckServer(mInput);
  Assert.AreEqual(Ord(TAtlasSetupFinding.ServerFailed), Ord(mCheck.Finding));
  Assert.AreEqual('Zeitlimit', mCheck.Args[0]);
  mInput.Server.Phase := TAtlasServerPhase.Running;
  mInput.Server.Version := '';
  mCheck := TAtlasSetupChecklist.CheckServer(mInput);
  Assert.AreEqual(Ord(TAtlasSetupFinding.ServerVersionUnknown), Ord(mCheck.Finding));
  Assert.IsTrue(mCheck.Pending, 'Version kommt mit der Antwort auf initialize');
end;

procedure TAtlasSetupChecklistTests.VersionsMatchIgnoresBuildAndPrefix;
begin
  Assert.IsTrue(TAtlasSetupChecklist.VersionsMatch('0.1.0', '0.1.0'));
  Assert.IsTrue(TAtlasSetupChecklist.VersionsMatch('v0.1.0+abc123', '0.1.0'));
  Assert.IsFalse(TAtlasSetupChecklist.VersionsMatch('0.1.1', '0.1.0'));
  Assert.IsFalse(TAtlasSetupChecklist.VersionsMatch('0.1.0-beta.1', '0.1.0'));
  Assert.IsFalse(TAtlasSetupChecklist.VersionsMatch('', ''));
end;

procedure TAtlasSetupChecklistTests.DelphiVersionAndPlatform;
var
  mInput: TAtlasSetupInput;
  mCheck: TAtlasSetupResult;
begin
  mCheck := TAtlasSetupChecklist.CheckDelphi(GoodInput);
  Assert.AreEqual(Ord(TAtlasSetupFinding.DelphiReady), Ord(mCheck.Finding));
  Assert.AreEqual(Ord(TAtlasStatusState.Green), Ord(mCheck.State));
  Assert.AreEqual('Delphi 13 (37.0)', mCheck.Args[0]);
  Assert.AreEqual('Win64', mCheck.Args[1]);
  mInput := GoodInput;
  mInput.Platform := '';
  mCheck := TAtlasSetupChecklist.CheckDelphi(mInput);
  Assert.AreEqual(Ord(TAtlasSetupFinding.DelphiNoProject), Ord(mCheck.Finding));
  Assert.AreEqual(Ord(TAtlasStatusState.Yellow), Ord(mCheck.State));
  Assert.IsTrue(mCheck.Pending, 'Ohne Projekt keine Plattform; das ist kein Fehler');
  mInput.BdsVersion := '';
  mCheck := TAtlasSetupChecklist.CheckDelphi(mInput);
  Assert.AreEqual(Ord(TAtlasSetupFinding.DelphiUnknown), Ord(mCheck.Finding));
  Assert.AreEqual(Ord(TAtlasStatusState.Red), Ord(mCheck.State));
end;

procedure TAtlasSetupChecklistTests.IndexIncompleteNamesMissingProjects;
var
  mInput: TAtlasSetupInput;
  mCheck: TAtlasSetupResult;
begin
  mInput := GoodInput;
  mInput.Projects := ['Kunden', 'Export', 'Rechnung'];
  mCheck := TAtlasSetupChecklist.CheckIndex(mInput);
  Assert.AreEqual(Ord(TAtlasSetupFinding.IndexIncomplete), Ord(mCheck.Finding));
  Assert.AreEqual(Ord(TAtlasStatusState.Yellow), Ord(mCheck.State));
  Assert.AreEqual(Ord(TAtlasSetupFix.RebuildIndex), Ord(mCheck.Fix), 'Knopf „Index neu aufbauen“');
  Assert.IsFalse(mCheck.Pending);
  Assert.AreEqual('1', mCheck.Args[0]);
  Assert.AreEqual('3', mCheck.Args[1]);
  Assert.AreEqual('Rechnung', mCheck.Args[2]);
  Assert.AreEqual(3, Integer(Length(mCheck.Projects)));
  Assert.AreEqual(Ord(TAtlasSetupProjectState.Missing), Ord(mCheck.Projects[2].State));
end;

procedure TAtlasSetupChecklistTests.IndexBuildingShowsProgressPerProject;
var
  mInput: TAtlasSetupInput;
  mCheck: TAtlasSetupResult;
begin
  mInput := GoodInput;
  mInput.Status.Workspaces := [Workspace('kunden', True, 0), Workspace('Export', False, 0)];
  mInput.Indexing := True;
  mInput.IndexPercent := 45;
  mCheck := TAtlasSetupChecklist.CheckIndex(mInput);
  Assert.AreEqual(Ord(TAtlasSetupFinding.IndexBuilding), Ord(mCheck.Finding));
  Assert.IsTrue(mCheck.Pending);
  Assert.AreEqual('1', mCheck.Args[0], 'fertig');
  Assert.AreEqual('2', mCheck.Args[1], 'gesamt');
  Assert.AreEqual('45', mCheck.Args[2], 'Prozent');
  Assert.AreEqual(Ord(TAtlasSetupProjectState.Done), Ord(mCheck.Projects[0].State), 'Name ohne Groß-/Kleinschreibung');
  Assert.AreEqual(Ord(TAtlasSetupProjectState.Building), Ord(mCheck.Projects[1].State));
  // Vor der ersten Antwort von atlas.server.status: alles „wird aufgebaut“.
  mInput := GoodInput;
  mInput.Status := Default(TAtlasSetupServerStatus);
  mCheck := TAtlasSetupChecklist.CheckIndex(mInput);
  Assert.AreEqual(Ord(TAtlasSetupFinding.IndexBuilding), Ord(mCheck.Finding));
  Assert.AreEqual('', mCheck.Args[2], 'Prozent unbekannt');
end;

procedure TAtlasSetupChecklistTests.IndexReadyForWholeGroup;
var
  mCheck: TAtlasSetupResult;
  mInput: TAtlasSetupInput;
begin
  mCheck := TAtlasSetupChecklist.CheckIndex(GoodInput);
  Assert.AreEqual(Ord(TAtlasSetupFinding.IndexReady), Ord(mCheck.Finding));
  Assert.AreEqual(Ord(TAtlasStatusState.Green), Ord(mCheck.State));
  Assert.AreEqual('2', mCheck.Args[0]);
  Assert.AreEqual('1569', mCheck.Args[1]);
  // Ohne Projektgruppe zählen die Arbeitsbereiche des Servers.
  mInput := GoodInput;
  mInput.Projects := nil;
  mCheck := TAtlasSetupChecklist.CheckIndex(mInput);
  Assert.AreEqual(Ord(TAtlasSetupFinding.IndexReady), Ord(mCheck.Finding));
  Assert.AreEqual(2, Integer(Length(mCheck.Projects)));
end;

procedure TAtlasSetupChecklistTests.IndexWithoutServerOrProjects;
var
  mInput: TAtlasSetupInput;
  mCheck: TAtlasSetupResult;
begin
  mInput := GoodInput;
  mInput.Server.Phase := TAtlasServerPhase.NotStarted;
  mCheck := TAtlasSetupChecklist.CheckIndex(mInput);
  Assert.AreEqual(Ord(TAtlasSetupFinding.IndexNoServer), Ord(mCheck.Finding));
  Assert.AreEqual(Ord(TAtlasSetupFix.StartServer), Ord(mCheck.Fix));
  Assert.IsTrue(mCheck.Pending);
  mInput := GoodInput;
  mInput.Projects := nil;
  mInput.Status.Workspaces := nil;
  mCheck := TAtlasSetupChecklist.CheckIndex(mInput);
  Assert.AreEqual(Ord(TAtlasSetupFinding.IndexNoProjects), Ord(mCheck.Finding));
  Assert.IsTrue(mCheck.Pending);
end;

procedure TAtlasSetupChecklistTests.LibraryCache;
var
  mInput: TAtlasSetupInput;
  mCheck: TAtlasSetupResult;
begin
  mCheck := TAtlasSetupChecklist.CheckLibraryCache(GoodInput);
  Assert.AreEqual(Ord(TAtlasSetupFinding.LibraryReady), Ord(mCheck.Finding));
  Assert.AreEqual(IntToStr(5 * 1024 * 1024), mCheck.Args[0]);
  mInput := GoodInput;
  mInput.Status.Workspaces := [Workspace('Kunden', True, 0), Workspace('Export', True, 0)];
  mCheck := TAtlasSetupChecklist.CheckLibraryCache(mInput);
  Assert.AreEqual(Ord(TAtlasSetupFinding.LibraryMissing), Ord(mCheck.Finding));
  Assert.AreEqual(Ord(TAtlasStatusState.Yellow), Ord(mCheck.State));
  Assert.AreEqual(Ord(TAtlasSetupFix.BuildLibraryCache), Ord(mCheck.Fix), 'Knopf „Jetzt aufbauen“');
  mInput.Status.Workspaces := [Workspace('Kunden', False, 0)];
  mCheck := TAtlasSetupChecklist.CheckLibraryCache(mInput);
  Assert.AreEqual(Ord(TAtlasSetupFinding.LibraryPending), Ord(mCheck.Finding));
  Assert.IsTrue(mCheck.Pending);
  mInput.Server.Phase := TAtlasServerPhase.Stopped;
  mCheck := TAtlasSetupChecklist.CheckLibraryCache(mInput);
  Assert.AreEqual(Ord(TAtlasSetupFinding.LibraryUnknown), Ord(mCheck.Finding));
end;

procedure TAtlasSetupChecklistTests.ErrorInsightDuplicateMessages;
var
  mInput: TAtlasSetupInput;
  mCheck: TAtlasSetupResult;
begin
  mInput := GoodInput;
  mInput.ErrorInsight := True;
  mInput.AtlasProblems := True;
  mCheck := TAtlasSetupChecklist.CheckErrorInsight(mInput);
  Assert.AreEqual(Ord(TAtlasSetupFinding.ErrorInsightDuplicate), Ord(mCheck.Finding));
  Assert.AreEqual(Ord(TAtlasStatusState.Yellow), Ord(mCheck.State));
  Assert.AreEqual(Ord(TAtlasSetupFix.DisableErrorInsight), Ord(mCheck.Fix), 'Knopf „Error Insight abschalten“');
  mInput.AtlasProblems := False;
  mCheck := TAtlasSetupChecklist.CheckErrorInsight(mInput);
  Assert.AreEqual(Ord(TAtlasSetupFinding.ErrorInsightIde), Ord(mCheck.Finding));
  Assert.AreEqual(Ord(TAtlasStatusState.Green), Ord(mCheck.State));
  mInput.ErrorInsight := False;
  mCheck := TAtlasSetupChecklist.CheckErrorInsight(mInput);
  Assert.AreEqual(Ord(TAtlasSetupFinding.ErrorInsightNone), Ord(mCheck.Finding));
  Assert.AreEqual(Ord(TAtlasSetupFix.EnableErrorInsight), Ord(mCheck.Fix));
  mInput.AtlasProblems := True;
  mCheck := TAtlasSetupChecklist.CheckErrorInsight(mInput);
  Assert.AreEqual(Ord(TAtlasSetupFinding.ErrorInsightAtlas), Ord(mCheck.Finding));
  mInput.ErrorInsightRestart := True;
  mCheck := TAtlasSetupChecklist.CheckErrorInsight(mInput);
  Assert.AreEqual(Ord(TAtlasSetupFinding.ErrorInsightRestart), Ord(mCheck.Finding), 'Wirkt erst nach dem Neustart');
  Assert.AreEqual(Ord(TAtlasStatusState.Yellow), Ord(mCheck.State));
end;

procedure TAtlasSetupChecklistTests.KeysConflictOnlyWhenLeftToOther;
var
  mInput: TAtlasSetupInput;
  mCheck: TAtlasSetupResult;
begin
  mCheck := TAtlasSetupChecklist.CheckKeys(GoodInput);
  Assert.AreEqual(Ord(TAtlasSetupFinding.KeysReady), Ord(mCheck.Finding));
  mInput := GoodInput;
  // Belegt, Atlas mit Vorrang: bewusst entschieden, kein offener Konflikt.
  mInput.Keys := [TAtlasSetupKey.Create(TAtlasKeyEntry.Create(TAtlasKeyFunction.Palette, $6050, True),
    'Strg+Umschalt+P', 'IDE: Tastaturmakro abspielen')];
  mCheck := TAtlasSetupChecklist.CheckKeys(mInput);
  Assert.AreEqual(Ord(TAtlasSetupFinding.KeysReady), Ord(mCheck.Finding));
  Assert.AreEqual('1', mCheck.Args[0]);
  mInput.Keys := mInput.Keys + [TAtlasSetupKey.Create(TAtlasKeyEntry.Create(TAtlasKeyFunction.Check, $C078, False),
    'Strg+Alt+F9', 'Andere Erweiterung')];
  mCheck := TAtlasSetupChecklist.CheckKeys(mInput);
  Assert.AreEqual(Ord(TAtlasSetupFinding.KeysConflict), Ord(mCheck.Finding));
  Assert.AreEqual(Ord(TAtlasSetupFix.OpenKeyConflicts), Ord(mCheck.Fix));
  Assert.AreEqual('1', mCheck.Args[0]);
  Assert.AreEqual('Strg+Alt+F9', mCheck.Args[1]);
  Assert.AreEqual('Andere Erweiterung', mCheck.Args[2]);
end;

procedure TAtlasSetupChecklistTests.KeysCoverEditorCommands;
var
  mInput: TAtlasSetupInput;
  mCheck: TAtlasSetupResult;
begin
  // Gemeinsame Quelle mit der Tastenkürzel-Übersicht (#520): auch die Tasten der Editorbefehle zählen.
  mInput := GoodInput;
  mInput.Keys := [TAtlasSetupKey.Create(TAtlasKeyEntry.Create(TAtlasKeyFunction.ExpandSelection, $4057, False),
    'Strg+W', 'Tastaturbelegung des Editors (CnWizards_D120)'),
    TAtlasSetupKey.Create(TAtlasKeyEntry.Create(TAtlasKeyFunction.WelcomeSearch, $4045, True), 'Strg+E',
    'Inkrementelle Suche (IDE)')];
  mCheck := TAtlasSetupChecklist.CheckKeys(mInput);
  Assert.AreEqual(Ord(TAtlasSetupFinding.KeysConflict), Ord(mCheck.Finding));
  Assert.AreEqual('1', mCheck.Args[0], 'das Suchfeld der Willkommensseite gewinnt dort immer');
  Assert.AreEqual('Strg+W', mCheck.Args[1]);
end;

procedure TAtlasSetupChecklistTests.EveryNonGreenPointHasAButton;
var
  mInput: TAtlasSetupInput;
  mItem: TAtlasSetupResult;
  mPhase: TAtlasServerPhase;
begin
  for mPhase := Low(TAtlasServerPhase) to High(TAtlasServerPhase) do
  begin
    mInput := GoodInput;
    mInput.Server.Phase := mPhase;
    mInput.ServerFound := mPhase <> TAtlasServerPhase.Failed;
    mInput.ErrorInsight := mPhase = TAtlasServerPhase.Running;
    mInput.Platform := '';
    for mItem in TAtlasSetupChecklist.Evaluate(mInput) do
    begin
      if mItem.State <> TAtlasStatusState.Green then
      begin
        Assert.AreNotEqual(Ord(TAtlasSetupFix.None), Ord(mItem.Fix), 'Punkt ohne Knopf: ' + IntToStr(Ord(mItem.Finding)));
      end
      else
      begin
        Assert.AreEqual(Ord(TAtlasSetupFix.None), Ord(mItem.Fix));
      end;
    end;
  end;
end;

procedure TAtlasSetupChecklistTests.ProgressCountsGreenPoints;
var
  mInput: TAtlasSetupInput;
  mDone, mTotal: Integer;
  mResults: TArray<TAtlasSetupResult>;
begin
  mResults := TAtlasSetupChecklist.Evaluate(GoodInput);
  TAtlasSetupChecklist.Progress(mResults, mDone, mTotal);
  Assert.AreEqual(6, mTotal);
  Assert.AreEqual(6, mDone);
  Assert.IsTrue(TAtlasSetupChecklist.Complete(mResults));
  mInput := GoodInput;
  mInput.ErrorInsight := True;
  mResults := TAtlasSetupChecklist.Evaluate(mInput);
  TAtlasSetupChecklist.Progress(mResults, mDone, mTotal);
  Assert.AreEqual(5, mDone, '„Einrichtung: 5 von 6 erledigt“ (#754)');
  Assert.IsFalse(TAtlasSetupChecklist.Complete(mResults));
  Assert.IsFalse(TAtlasSetupChecklist.Complete(nil));
end;

procedure TAtlasSetupChecklistTests.StartOpensOnlyWhileNotGreen;
var
  mInput: TAtlasSetupInput;
  mGood, mDuplicate, mStarting: TArray<TAtlasSetupResult>;
begin
  mGood := TAtlasSetupChecklist.Evaluate(GoodInput);
  mInput := GoodInput;
  mInput.ErrorInsight := True;
  mDuplicate := TAtlasSetupChecklist.Evaluate(mInput);
  mInput := GoodInput;
  mInput.Server.Phase := TAtlasServerPhase.Starting;
  mStarting := TAtlasSetupChecklist.Evaluate(mInput);
  // ui.setupChecklist aus: nur auf Abruf.
  Assert.AreEqual(Ord(TAtlasSetupStartAction.Skip),
    Ord(TAtlasSetupChecklist.StartAction(False, True, mDuplicate, 0, 1000)));
  // Erster Start: immer.
  Assert.AreEqual(Ord(TAtlasSetupStartAction.Open), Ord(TAtlasSetupChecklist.StartAction(True, True, mGood, 0, 1000)));
  // Alles grün: nicht mehr von selbst.
  Assert.AreEqual(Ord(TAtlasSetupStartAction.Skip), Ord(TAtlasSetupChecklist.StartAction(True, False, mGood, 0, 1000)));
  // Fest gelb: sofort.
  Assert.AreEqual(Ord(TAtlasSetupStartAction.Open),
    Ord(TAtlasSetupChecklist.StartAction(True, False, mDuplicate, 0, 1000)));
  // Nur im Gange: warten, nach der Wartezeit nicht öffnen.
  Assert.AreEqual(Ord(TAtlasSetupStartAction.Wait),
    Ord(TAtlasSetupChecklist.StartAction(True, False, mStarting, 500, 1000)));
  Assert.AreEqual(Ord(TAtlasSetupStartAction.Skip),
    Ord(TAtlasSetupChecklist.StartAction(True, False, mStarting, 1000, 1000)));
  Assert.AreEqual(Ord(TAtlasSetupStartAction.Wait), Ord(TAtlasSetupChecklist.StartAction(True, False, nil, 0, 1000)));
end;

procedure TAtlasSetupChecklistTests.StatusParsesWorkspaces;
var
  mStatus: TAtlasSetupServerStatus;
begin
  mStatus := TAtlasSetupServerStatus.Parse('{"units":42,"workspaces":[{"name":"Kunden","lastIndexMs":120,' +
    '"libraryCacheBytes":2048},{"name":"Export","lastIndexMs":-1,"libraryCacheBytes":0}],"requests":[]}');
  Assert.IsTrue(mStatus.Known);
  Assert.AreEqual(42, mStatus.Units);
  Assert.AreEqual(2, Integer(Length(mStatus.Workspaces)));
  Assert.AreEqual('Kunden', mStatus.Workspaces[0].Name);
  Assert.IsTrue(mStatus.Workspaces[0].Done);
  Assert.AreEqual(Int64(2048), mStatus.Workspaces[0].LibraryCacheBytes);
  Assert.IsFalse(mStatus.Workspaces[1].Done);
  Assert.IsFalse(TAtlasSetupServerStatus.Parse('').Known);
  Assert.IsFalse(TAtlasSetupServerStatus.Parse('kein json').Known);
  Assert.AreEqual(-1, TAtlasSetupServerStatus.Parse('[]').Units);
  Assert.AreEqual('Kunden', TAtlasSetupChecklist.ProjectName('C:\Projekte\Kunden\Kunden.dproj'));
end;

procedure TAtlasSetupChecklistTests.StatusParsesIndexingPerWorkspace;
var
  mStatus, mLive: TAtlasSetupServerStatus;
  mIndexingOf: TAtlasSetupTokenIndexingFunc;
begin
  mStatus := TAtlasSetupServerStatus.Parse('{"workspaces":[{"name":"Kunden","lastIndexMs":120,' +
    '"progressToken":"atlas-index-1"},{"name":"Lager","lastIndexMs":-1,"progressToken":"atlas-index-1-1",' +
    '"indexing":{"percent":40,"stage":"searchPaths","waiting":true}},{"name":"Alt","lastIndexMs":-1}]}');
  Assert.AreEqual('atlas-index-1', mStatus.Workspaces[0].ProgressToken);
  Assert.IsFalse(mStatus.Workspaces[0].Indexing.Active);
  Assert.IsTrue(mStatus.Workspaces[1].Indexing.Active);
  Assert.AreEqual(40, mStatus.Workspaces[1].Indexing.Percent);
  Assert.AreEqual(Ord(TAtlasSetupIndexStage.SearchPaths), Ord(mStatus.Workspaces[1].Indexing.Stage));
  Assert.IsTrue(mStatus.Workspaces[1].Indexing.Waiting);
  Assert.AreEqual('', mStatus.Workspaces[2].ProgressToken, 'älterer Server');
  Assert.AreEqual(-1, mStatus.Workspaces[2].Indexing.Percent);
  // Live: Lager meldet 62 %, Kunden baut neu auf (10 %); ohne Token bleibt der Status.
  mIndexingOf :=
    function(const AToken: string; out APercent: Integer): Boolean
    begin
      APercent := -1;
      Result := True;
      if AToken = 'atlas-index-1-1' then
      begin
        APercent := 62;
      end
      else if AToken = 'atlas-index-1' then
      begin
        APercent := 10;
      end;
    end;
  mLive := mStatus.WithLiveProgress(mIndexingOf);
  Assert.AreEqual(62, mLive.Workspaces[1].Indexing.Percent);
  Assert.AreEqual(Ord(TAtlasSetupIndexStage.SearchPaths), Ord(mLive.Workspaces[1].Indexing.Stage), 'Stufe bleibt');
  Assert.IsTrue(mLive.Workspaces[0].Indexing.Active);
  Assert.AreEqual(10, mLive.Workspaces[0].Indexing.Percent);
  Assert.AreEqual(40, mStatus.Workspaces[1].Indexing.Percent, 'Original unverändert');
  // Läuft das Token nicht mehr, ist der Aufbau vorbei, auch wenn der Status noch älter ist.
  mIndexingOf :=
    function(const AToken: string; out APercent: Integer): Boolean
    begin
      APercent := -1;
      Result := False;
    end;
  mLive := mStatus.WithLiveProgress(mIndexingOf);
  Assert.IsFalse(mLive.Workspaces[1].Indexing.Active);
  mLive := mStatus.WithLiveProgress(nil);
  Assert.IsTrue(mLive.Workspaces[1].Indexing.Active, 'ohne Meldungen gilt der Status');
end;

procedure TAtlasSetupChecklistTests.IndexShowsStagePerProject;
var
  mInput: TAtlasSetupInput;
  mCheck: TAtlasSetupResult;
  mBuilding: TAtlasSetupWorkspace;
begin
  mInput := GoodInput;
  mBuilding := Workspace('Export', False, 0);
  mBuilding.Indexing.Active := True;
  mBuilding.Indexing.Percent := 18;
  mBuilding.Indexing.Stage := TAtlasSetupIndexStage.Library_;
  mBuilding.Indexing.Waiting := True;
  mInput.Status.Workspaces := [Workspace('Kunden', True, 0), mBuilding];
  mInput.Indexing := True;
  mCheck := TAtlasSetupChecklist.CheckIndex(mInput);
  Assert.AreEqual(Ord(TAtlasSetupProjectState.Done), Ord(mCheck.Projects[0].State));
  Assert.IsFalse(mCheck.Projects[0].Indexing.Active);
  Assert.AreEqual(Ord(TAtlasSetupProjectState.Building), Ord(mCheck.Projects[1].State));
  Assert.AreEqual(18, mCheck.Projects[1].Indexing.Percent);
  Assert.IsTrue(mCheck.Projects[1].Indexing.Waiting);
  Assert.AreEqual(Ord(TAtlasSetupIndexStage.Library_), Ord(mCheck.Projects[1].Indexing.Stage));
  // Neuer Aufbau eines schon fertigen Projekts (Index neu aufbauen): wieder gelb.
  mBuilding.Done := True;
  mInput.Status.Workspaces := [Workspace('Kunden', True, 0), mBuilding];
  mCheck := TAtlasSetupChecklist.CheckIndex(mInput);
  Assert.AreEqual(Ord(TAtlasSetupProjectState.Building), Ord(mCheck.Projects[1].State));
  // Anderer Fortschritt: andere Zeile für die Anzeige.
  mBuilding.Indexing.Percent := 19;
  mInput.Status.Workspaces := [Workspace('Kunden', True, 0), mBuilding];
  Assert.AreNotEqual(mCheck.Key, TAtlasSetupChecklist.CheckIndex(mInput).Key);
  // Projekt ohne Arbeitsbereich: fehlt, ohne Prozent.
  mInput.Projects := ['Kunden', 'Export', 'Neu'];
  mCheck := TAtlasSetupChecklist.CheckIndex(mInput);
  Assert.AreEqual(Ord(TAtlasSetupProjectState.Missing), Ord(mCheck.Projects[2].State));
  Assert.AreEqual(-1, mCheck.Projects[2].Indexing.Percent);
end;

procedure TAtlasSetupChecklistTests.ReportHasLinesAndNoIdentity;
var
  mInput: TAtlasSetupReportInput;
  mReport: string;
begin
  mInput := Default(TAtlasSetupReportInput);
  mInput.Title := 'Atlas-Einrichtung';
  mInput.Summary := '5 von 6 erledigt';
  mInput.AtlasVersion := '0.1.0';
  mInput.IdeVersion := '37.0';
  mInput.Platform := 'Win64';
  mInput.Created := EncodeDate(2026, 10, 15) + EncodeTime(14, 30, 0, 0);
  mInput.Identity := ['marco', 'WS-MARCO'];
  mInput.Lines := [TAtlasSetupReportLine.Create(TAtlasStatusState.Green, 'Server gefunden, Version 0.1.0', False),
    TAtlasSetupReportLine.Create(TAtlasStatusState.Yellow, 'Projektgruppe von marco wird indiziert', False),
    TAtlasSetupReportLine.Create(TAtlasStatusState.Yellow, 'Export: wird aufgebaut', True),
    TAtlasSetupReportLine.Create(TAtlasStatusState.Red, 'Server WS-MARCO fehlt', False)];
  mReport := TAtlasSetupChecklist.Report(mInput);
  Assert.Contains(mReport, 'Atlas-Einrichtung');
  Assert.Contains(mReport, 'Atlas 0.1.0, IDE 37.0, Win64');
  Assert.Contains(mReport, '2026-10-15 14:30');
  Assert.Contains(mReport, '5 von 6 erledigt');
  Assert.Contains(mReport, '[ok] Server gefunden, Version 0.1.0');
  Assert.Contains(mReport, '[!]  Projektgruppe von <benutzer> wird indiziert');
  Assert.Contains(mReport, '       - Export: wird aufgebaut');
  Assert.Contains(mReport, '[x]  Server <benutzer> fehlt');
  Assert.IsFalse(mReport.ToLower.Contains('marco'), 'Benutzer- und Rechnername ersetzt');
end;

type
  TFakeEnvironment = class(TInterfacedObject, IAtlasSetupEnvironment)
  public
    Path: string;
    Chosen: string;
    Choose: Boolean;
    Starts: Integer;
    Restarts: Integer;
    Rebuilds: Integer;
    ErrorInsight: Boolean;
    KeysOpened: Integer;
    function Snapshot: TAtlasSetupInput;
    function ChooseServerPath(out APath: string): Boolean;
    procedure SaveServerPath(const APath: string);
    function StartServer(ARestart: Boolean): Boolean;
    function RebuildIndex: Boolean;
    function SetErrorInsight(AEnabled: Boolean): Boolean;
    procedure OpenKeyConflicts;
  end;

function TFakeEnvironment.Snapshot: TAtlasSetupInput;
begin
  Result := GoodInput;
  Result.ErrorInsight := ErrorInsight;
  // Ohne gespeicherten Pfad kein Server; mit Pfad läuft er erst nach dem (Neu-)Start.
  Result.ServerFound := Path <> '';
  if not Result.ServerFound then
  begin
    Result.Server.Phase := TAtlasServerPhase.Failed;
  end
  else if Starts + Restarts = 0 then
  begin
    Result.Server.Phase := TAtlasServerPhase.NotStarted;
  end;
end;

function TFakeEnvironment.ChooseServerPath(out APath: string): Boolean;
begin
  APath := Chosen;
  Result := Choose;
end;

procedure TFakeEnvironment.SaveServerPath(const APath: string);
begin
  Path := APath;
end;

function TFakeEnvironment.StartServer(ARestart: Boolean): Boolean;
begin
  if ARestart then
  begin
    Inc(Restarts);
  end
  else
  begin
    Inc(Starts);
  end;
  Result := Path <> '';
end;

function TFakeEnvironment.RebuildIndex: Boolean;
begin
  Inc(Rebuilds);
  Result := True;
end;

function TFakeEnvironment.SetErrorInsight(AEnabled: Boolean): Boolean;
begin
  ErrorInsight := AEnabled;
  Result := True;
end;

procedure TFakeEnvironment.OpenKeyConflicts;
begin
  Inc(KeysOpened);
end;

{ TAtlasSetupControllerTests }

procedure TAtlasSetupControllerTests.ChooseServerPathSavesPathAndTurnsGreen;
var
  mFake: TFakeEnvironment;
  mEnvironment: IAtlasSetupEnvironment;
  mController: TAtlasSetupController;
begin
  mFake := TFakeEnvironment.Create;
  mEnvironment := mFake;
  mFake.Choose := True;
  mFake.Chosen := ' C:\Atlas\AtlasServer.exe ';
  mController := TAtlasSetupController.Create(mEnvironment);
  try
    mController.Refresh;
    Assert.AreEqual(Ord(TAtlasSetupFinding.ServerMissing), Ord(mController.Results[0].Finding));
    Assert.IsTrue(mController.Apply(mController.Results[0].Fix));
    Assert.AreEqual('C:\Atlas\AtlasServer.exe', mFake.Path, 'Pfad gespeichert');
    Assert.AreEqual(1, mFake.Restarts, 'Mit dem neuen Pfad neu gestartet');
    Assert.AreEqual(Ord(TAtlasSetupFinding.ServerReady), Ord(mController.Results[0].Finding));
    Assert.AreEqual(Ord(TAtlasStatusState.Green), Ord(mController.Results[0].State), 'Prüfung danach grün');
    Assert.IsTrue(mController.Complete);
  finally
    mController.Free;
  end;
end;

procedure TAtlasSetupControllerTests.CancelledChoiceChangesNothing;
var
  mFake: TFakeEnvironment;
  mEnvironment: IAtlasSetupEnvironment;
  mController: TAtlasSetupController;
begin
  mFake := TFakeEnvironment.Create;
  mEnvironment := mFake;
  mFake.Choose := False;
  mFake.Chosen := 'C:\Atlas\AtlasServer.exe';
  mController := TAtlasSetupController.Create(mEnvironment);
  try
    mController.Refresh;
    Assert.IsFalse(mController.Apply(TAtlasSetupFix.ChooseServerPath));
    Assert.AreEqual('', mFake.Path);
    Assert.AreEqual(0, mFake.Restarts);
    Assert.AreEqual(Ord(TAtlasStatusState.Red), Ord(mController.Results[0].State));
    Assert.IsFalse(mController.Apply(TAtlasSetupFix.Explain), 'Erklären tut nichts in der Umgebung');
  finally
    mController.Free;
  end;
end;

procedure TAtlasSetupControllerTests.FixesCallTheEnvironment;
var
  mFake: TFakeEnvironment;
  mEnvironment: IAtlasSetupEnvironment;
  mController: TAtlasSetupController;
  mDone, mTotal: Integer;
begin
  mFake := TFakeEnvironment.Create;
  mEnvironment := mFake;
  mFake.Path := 'C:\Atlas\AtlasServer.exe';
  mFake.ErrorInsight := True;
  mController := TAtlasSetupController.Create(mEnvironment);
  try
    mController.Refresh;
    mController.Progress(mDone, mTotal);
    Assert.AreEqual(2, mDone, 'Server nicht gestartet, Index und Cache unbekannt, Error Insight doppelt');
    Assert.IsTrue(mController.Apply(TAtlasSetupFix.StartServer));
    Assert.AreEqual(1, mFake.Starts);
    Assert.IsTrue(mController.Apply(TAtlasSetupFix.DisableErrorInsight));
    Assert.IsFalse(mFake.ErrorInsight);
    Assert.IsTrue(mController.Complete);
    mController.Apply(TAtlasSetupFix.RebuildIndex);
    mController.Apply(TAtlasSetupFix.BuildLibraryCache);
    Assert.AreEqual(2, mFake.Rebuilds);
    mController.Apply(TAtlasSetupFix.OpenKeyConflicts);
    Assert.AreEqual(1, mFake.KeysOpened);
    mController.Apply(TAtlasSetupFix.RestartServer);
    Assert.AreEqual(1, mFake.Restarts);
    mController.Apply(TAtlasSetupFix.EnableErrorInsight);
    Assert.IsTrue(mFake.ErrorInsight);
  finally
    mController.Free;
  end;
end;

procedure TAtlasSetupControllerTests.VersionOnlyOnChange;
var
  mFake: TFakeEnvironment;
  mEnvironment: IAtlasSetupEnvironment;
  mController: TAtlasSetupController;
  mVersion: Integer;
begin
  mFake := TFakeEnvironment.Create;
  mEnvironment := mFake;
  mFake.Path := 'C:\Atlas\AtlasServer.exe';
  mController := TAtlasSetupController.Create(mEnvironment);
  try
    mController.Refresh;
    mVersion := mController.Version;
    mController.Refresh;
    Assert.AreEqual(mVersion, mController.Version, 'Gleicher Stand: keine neue Version');
    mFake.ErrorInsight := True;
    mController.Refresh;
    Assert.AreEqual(mVersion + 1, mController.Version);
  finally
    mController.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSetupChecklistTests);
  TDUnitX.RegisterTestFixture(TAtlasSetupControllerTests);

end.
