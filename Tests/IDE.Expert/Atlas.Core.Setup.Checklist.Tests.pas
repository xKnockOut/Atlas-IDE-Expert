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
  Workspace: TAtlasSetupWorkspace;
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
  Workspace.Name := 'Kunden';
  Workspace.Done := True;
  Workspace.LibraryCacheBytes := 5 * 1024 * 1024;
  Result.Status.Workspaces := [Workspace];
  Workspace.Name := 'Export';
  Workspace.LibraryCacheBytes := 0;
  Result.Status.Workspaces := Result.Status.Workspaces + [Workspace];
  Result.ErrorInsight := False;
  Result.AtlasProblems := True;
  Result.Keys := [TAtlasSetupKey.Create(TAtlasKeyEntry.Create(TAtlasKeyFunction.Palette, $6050, False),
    'Strg+Umschalt+P', '')];
end;

function Workspace(const AName: string; ADone: Boolean; ALibrary: Int64): TAtlasSetupWorkspace;
begin
  Result.Name := AName;
  Result.Done := ADone;
  Result.LibraryCacheBytes := ALibrary;
end;

{ TAtlasSetupChecklistTests }

procedure TAtlasSetupChecklistTests.ServerMissingIsRedWithChoosePath;
var
  Input: TAtlasSetupInput;
  Check: TAtlasSetupResult;
begin
  Input := GoodInput;
  Input.ServerFound := False;
  Input.Server := Default(TAtlasServerInfo);
  Check := TAtlasSetupChecklist.CheckServer(Input);
  Assert.AreEqual(Ord(TAtlasSetupFinding.ServerMissing), Ord(Check.Finding));
  Assert.AreEqual(Ord(TAtlasStatusState.Red), Ord(Check.State));
  Assert.AreEqual(Ord(TAtlasSetupFix.ChooseServerPath), Ord(Check.Fix), 'Knopf „Server-Pfad wählen …“');
  Assert.IsFalse(Check.Pending, 'Fehlender Server ist ein fester Befund');
end;

procedure TAtlasSetupChecklistTests.ServerVersionMismatchIsRed;
var
  Input: TAtlasSetupInput;
  Check: TAtlasSetupResult;
begin
  Input := GoodInput;
  Input.Server.Version := '0.0.9';
  Check := TAtlasSetupChecklist.CheckServer(Input);
  Assert.AreEqual(Ord(TAtlasSetupFinding.ServerVersionMismatch), Ord(Check.Finding));
  Assert.AreEqual(Ord(TAtlasStatusState.Red), Ord(Check.State));
  Assert.AreEqual(Ord(TAtlasSetupFix.ChooseServerPath), Ord(Check.Fix));
  Assert.AreEqual(2, Length(Check.Args));
  Assert.AreEqual('0.0.9', Check.Args[0]);
  Assert.AreEqual('0.1.0', Check.Args[1]);
end;

procedure TAtlasSetupChecklistTests.ServerReadyWithMatchingVersion;
var
  Check: TAtlasSetupResult;
begin
  Check := TAtlasSetupChecklist.CheckServer(GoodInput);
  Assert.AreEqual(Ord(TAtlasSetupFinding.ServerReady), Ord(Check.Finding));
  Assert.AreEqual(Ord(TAtlasStatusState.Green), Ord(Check.State));
  Assert.AreEqual(Ord(TAtlasSetupFix.None), Ord(Check.Fix));
  Assert.AreEqual('0.1.0', Check.Args[0]);
end;

procedure TAtlasSetupChecklistTests.ServerPhases;
var
  Input: TAtlasSetupInput;
  Check: TAtlasSetupResult;
begin
  Input := GoodInput;
  Input.Server.Phase := TAtlasServerPhase.NotStarted;
  Check := TAtlasSetupChecklist.CheckServer(Input);
  Assert.AreEqual(Ord(TAtlasSetupFinding.ServerNotStarted), Ord(Check.Finding));
  Assert.AreEqual(Ord(TAtlasStatusState.Yellow), Ord(Check.State));
  Assert.AreEqual(Ord(TAtlasSetupFix.StartServer), Ord(Check.Fix));
  Assert.IsTrue(Check.Pending, 'Der Server startet beim ersten Bedarf');
  Input.Server.Phase := TAtlasServerPhase.Starting;
  Check := TAtlasSetupChecklist.CheckServer(Input);
  Assert.AreEqual(Ord(TAtlasSetupFinding.ServerStarting), Ord(Check.Finding));
  Assert.IsTrue(Check.Pending);
  Input.Server.Phase := TAtlasServerPhase.Stopped;
  Check := TAtlasSetupChecklist.CheckServer(Input);
  Assert.AreEqual(Ord(TAtlasSetupFinding.ServerStopped), Ord(Check.Finding));
  Assert.AreEqual(Ord(TAtlasStatusState.Red), Ord(Check.State));
  Assert.AreEqual(Ord(TAtlasSetupFix.RestartServer), Ord(Check.Fix));
  Input.Server.Phase := TAtlasServerPhase.Failed;
  Input.Server.Error := 'Zeitlimit';
  Check := TAtlasSetupChecklist.CheckServer(Input);
  Assert.AreEqual(Ord(TAtlasSetupFinding.ServerFailed), Ord(Check.Finding));
  Assert.AreEqual('Zeitlimit', Check.Args[0]);
  Input.Server.Phase := TAtlasServerPhase.Running;
  Input.Server.Version := '';
  Check := TAtlasSetupChecklist.CheckServer(Input);
  Assert.AreEqual(Ord(TAtlasSetupFinding.ServerVersionUnknown), Ord(Check.Finding));
  Assert.IsTrue(Check.Pending, 'Version kommt mit der Antwort auf initialize');
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
  Input: TAtlasSetupInput;
  Check: TAtlasSetupResult;
begin
  Check := TAtlasSetupChecklist.CheckDelphi(GoodInput);
  Assert.AreEqual(Ord(TAtlasSetupFinding.DelphiReady), Ord(Check.Finding));
  Assert.AreEqual(Ord(TAtlasStatusState.Green), Ord(Check.State));
  Assert.AreEqual('Delphi 13 (37.0)', Check.Args[0]);
  Assert.AreEqual('Win64', Check.Args[1]);
  Input := GoodInput;
  Input.Platform := '';
  Check := TAtlasSetupChecklist.CheckDelphi(Input);
  Assert.AreEqual(Ord(TAtlasSetupFinding.DelphiNoProject), Ord(Check.Finding));
  Assert.AreEqual(Ord(TAtlasStatusState.Yellow), Ord(Check.State));
  Assert.IsTrue(Check.Pending, 'Ohne Projekt keine Plattform; das ist kein Fehler');
  Input.BdsVersion := '';
  Check := TAtlasSetupChecklist.CheckDelphi(Input);
  Assert.AreEqual(Ord(TAtlasSetupFinding.DelphiUnknown), Ord(Check.Finding));
  Assert.AreEqual(Ord(TAtlasStatusState.Red), Ord(Check.State));
end;

procedure TAtlasSetupChecklistTests.IndexIncompleteNamesMissingProjects;
var
  Input: TAtlasSetupInput;
  Check: TAtlasSetupResult;
begin
  Input := GoodInput;
  Input.Projects := ['Kunden', 'Export', 'Rechnung'];
  Check := TAtlasSetupChecklist.CheckIndex(Input);
  Assert.AreEqual(Ord(TAtlasSetupFinding.IndexIncomplete), Ord(Check.Finding));
  Assert.AreEqual(Ord(TAtlasStatusState.Yellow), Ord(Check.State));
  Assert.AreEqual(Ord(TAtlasSetupFix.RebuildIndex), Ord(Check.Fix), 'Knopf „Index neu aufbauen“');
  Assert.IsFalse(Check.Pending);
  Assert.AreEqual('1', Check.Args[0]);
  Assert.AreEqual('3', Check.Args[1]);
  Assert.AreEqual('Rechnung', Check.Args[2]);
  Assert.AreEqual(3, Length(Check.Projects));
  Assert.AreEqual(Ord(TAtlasSetupProjectState.Missing), Ord(Check.Projects[2].State));
end;

procedure TAtlasSetupChecklistTests.IndexBuildingShowsProgressPerProject;
var
  Input: TAtlasSetupInput;
  Check: TAtlasSetupResult;
begin
  Input := GoodInput;
  Input.Status.Workspaces := [Workspace('kunden', True, 0), Workspace('Export', False, 0)];
  Input.Indexing := True;
  Input.IndexPercent := 45;
  Check := TAtlasSetupChecklist.CheckIndex(Input);
  Assert.AreEqual(Ord(TAtlasSetupFinding.IndexBuilding), Ord(Check.Finding));
  Assert.IsTrue(Check.Pending);
  Assert.AreEqual('1', Check.Args[0], 'fertig');
  Assert.AreEqual('2', Check.Args[1], 'gesamt');
  Assert.AreEqual('45', Check.Args[2], 'Prozent');
  Assert.AreEqual(Ord(TAtlasSetupProjectState.Done), Ord(Check.Projects[0].State), 'Name ohne Groß-/Kleinschreibung');
  Assert.AreEqual(Ord(TAtlasSetupProjectState.Building), Ord(Check.Projects[1].State));
  // Vor der ersten Antwort von atlas.server.status: alles „wird aufgebaut“.
  Input := GoodInput;
  Input.Status := Default(TAtlasSetupServerStatus);
  Check := TAtlasSetupChecklist.CheckIndex(Input);
  Assert.AreEqual(Ord(TAtlasSetupFinding.IndexBuilding), Ord(Check.Finding));
  Assert.AreEqual('', Check.Args[2], 'Prozent unbekannt');
end;

procedure TAtlasSetupChecklistTests.IndexReadyForWholeGroup;
var
  Check: TAtlasSetupResult;
  Input: TAtlasSetupInput;
begin
  Check := TAtlasSetupChecklist.CheckIndex(GoodInput);
  Assert.AreEqual(Ord(TAtlasSetupFinding.IndexReady), Ord(Check.Finding));
  Assert.AreEqual(Ord(TAtlasStatusState.Green), Ord(Check.State));
  Assert.AreEqual('2', Check.Args[0]);
  Assert.AreEqual('1569', Check.Args[1]);
  // Ohne Projektgruppe zählen die Arbeitsbereiche des Servers.
  Input := GoodInput;
  Input.Projects := nil;
  Check := TAtlasSetupChecklist.CheckIndex(Input);
  Assert.AreEqual(Ord(TAtlasSetupFinding.IndexReady), Ord(Check.Finding));
  Assert.AreEqual(2, Length(Check.Projects));
end;

procedure TAtlasSetupChecklistTests.IndexWithoutServerOrProjects;
var
  Input: TAtlasSetupInput;
  Check: TAtlasSetupResult;
begin
  Input := GoodInput;
  Input.Server.Phase := TAtlasServerPhase.NotStarted;
  Check := TAtlasSetupChecklist.CheckIndex(Input);
  Assert.AreEqual(Ord(TAtlasSetupFinding.IndexNoServer), Ord(Check.Finding));
  Assert.AreEqual(Ord(TAtlasSetupFix.StartServer), Ord(Check.Fix));
  Assert.IsTrue(Check.Pending);
  Input := GoodInput;
  Input.Projects := nil;
  Input.Status.Workspaces := nil;
  Check := TAtlasSetupChecklist.CheckIndex(Input);
  Assert.AreEqual(Ord(TAtlasSetupFinding.IndexNoProjects), Ord(Check.Finding));
  Assert.IsTrue(Check.Pending);
end;

procedure TAtlasSetupChecklistTests.LibraryCache;
var
  Input: TAtlasSetupInput;
  Check: TAtlasSetupResult;
begin
  Check := TAtlasSetupChecklist.CheckLibraryCache(GoodInput);
  Assert.AreEqual(Ord(TAtlasSetupFinding.LibraryReady), Ord(Check.Finding));
  Assert.AreEqual(IntToStr(5 * 1024 * 1024), Check.Args[0]);
  Input := GoodInput;
  Input.Status.Workspaces := [Workspace('Kunden', True, 0), Workspace('Export', True, 0)];
  Check := TAtlasSetupChecklist.CheckLibraryCache(Input);
  Assert.AreEqual(Ord(TAtlasSetupFinding.LibraryMissing), Ord(Check.Finding));
  Assert.AreEqual(Ord(TAtlasStatusState.Yellow), Ord(Check.State));
  Assert.AreEqual(Ord(TAtlasSetupFix.BuildLibraryCache), Ord(Check.Fix), 'Knopf „Jetzt aufbauen“');
  Input.Status.Workspaces := [Workspace('Kunden', False, 0)];
  Check := TAtlasSetupChecklist.CheckLibraryCache(Input);
  Assert.AreEqual(Ord(TAtlasSetupFinding.LibraryPending), Ord(Check.Finding));
  Assert.IsTrue(Check.Pending);
  Input.Server.Phase := TAtlasServerPhase.Stopped;
  Check := TAtlasSetupChecklist.CheckLibraryCache(Input);
  Assert.AreEqual(Ord(TAtlasSetupFinding.LibraryUnknown), Ord(Check.Finding));
end;

procedure TAtlasSetupChecklistTests.ErrorInsightDuplicateMessages;
var
  Input: TAtlasSetupInput;
  Check: TAtlasSetupResult;
begin
  Input := GoodInput;
  Input.ErrorInsight := True;
  Input.AtlasProblems := True;
  Check := TAtlasSetupChecklist.CheckErrorInsight(Input);
  Assert.AreEqual(Ord(TAtlasSetupFinding.ErrorInsightDuplicate), Ord(Check.Finding));
  Assert.AreEqual(Ord(TAtlasStatusState.Yellow), Ord(Check.State));
  Assert.AreEqual(Ord(TAtlasSetupFix.DisableErrorInsight), Ord(Check.Fix), 'Knopf „Error Insight abschalten“');
  Input.AtlasProblems := False;
  Check := TAtlasSetupChecklist.CheckErrorInsight(Input);
  Assert.AreEqual(Ord(TAtlasSetupFinding.ErrorInsightIde), Ord(Check.Finding));
  Assert.AreEqual(Ord(TAtlasStatusState.Green), Ord(Check.State));
  Input.ErrorInsight := False;
  Check := TAtlasSetupChecklist.CheckErrorInsight(Input);
  Assert.AreEqual(Ord(TAtlasSetupFinding.ErrorInsightNone), Ord(Check.Finding));
  Assert.AreEqual(Ord(TAtlasSetupFix.EnableErrorInsight), Ord(Check.Fix));
  Input.AtlasProblems := True;
  Check := TAtlasSetupChecklist.CheckErrorInsight(Input);
  Assert.AreEqual(Ord(TAtlasSetupFinding.ErrorInsightAtlas), Ord(Check.Finding));
  Input.ErrorInsightRestart := True;
  Check := TAtlasSetupChecklist.CheckErrorInsight(Input);
  Assert.AreEqual(Ord(TAtlasSetupFinding.ErrorInsightRestart), Ord(Check.Finding), 'Wirkt erst nach dem Neustart');
  Assert.AreEqual(Ord(TAtlasStatusState.Yellow), Ord(Check.State));
end;

procedure TAtlasSetupChecklistTests.KeysConflictOnlyWhenLeftToOther;
var
  Input: TAtlasSetupInput;
  Check: TAtlasSetupResult;
begin
  Check := TAtlasSetupChecklist.CheckKeys(GoodInput);
  Assert.AreEqual(Ord(TAtlasSetupFinding.KeysReady), Ord(Check.Finding));
  Input := GoodInput;
  // Belegt, Atlas mit Vorrang: bewusst entschieden, kein offener Konflikt.
  Input.Keys := [TAtlasSetupKey.Create(TAtlasKeyEntry.Create(TAtlasKeyFunction.Palette, $6050, True),
    'Strg+Umschalt+P', 'IDE: Tastaturmakro abspielen')];
  Check := TAtlasSetupChecklist.CheckKeys(Input);
  Assert.AreEqual(Ord(TAtlasSetupFinding.KeysReady), Ord(Check.Finding));
  Assert.AreEqual('1', Check.Args[0]);
  Input.Keys := Input.Keys + [TAtlasSetupKey.Create(TAtlasKeyEntry.Create(TAtlasKeyFunction.Check, $C078, False),
    'Strg+Alt+F9', 'Andere Erweiterung')];
  Check := TAtlasSetupChecklist.CheckKeys(Input);
  Assert.AreEqual(Ord(TAtlasSetupFinding.KeysConflict), Ord(Check.Finding));
  Assert.AreEqual(Ord(TAtlasSetupFix.OpenKeyConflicts), Ord(Check.Fix));
  Assert.AreEqual('1', Check.Args[0]);
  Assert.AreEqual('Strg+Alt+F9', Check.Args[1]);
  Assert.AreEqual('Andere Erweiterung', Check.Args[2]);
end;

procedure TAtlasSetupChecklistTests.KeysCoverEditorCommands;
var
  Input: TAtlasSetupInput;
  Check: TAtlasSetupResult;
begin
  // Gemeinsame Quelle mit der Tastenkürzel-Übersicht (#520): auch die Tasten der Editorbefehle zählen.
  Input := GoodInput;
  Input.Keys := [TAtlasSetupKey.Create(TAtlasKeyEntry.Create(TAtlasKeyFunction.ExpandSelection, $4057, False),
    'Strg+W', 'Tastaturbelegung des Editors (CnWizards_D120)'),
    TAtlasSetupKey.Create(TAtlasKeyEntry.Create(TAtlasKeyFunction.WelcomeSearch, $4045, True), 'Strg+E',
    'Inkrementelle Suche (IDE)')];
  Check := TAtlasSetupChecklist.CheckKeys(Input);
  Assert.AreEqual(Ord(TAtlasSetupFinding.KeysConflict), Ord(Check.Finding));
  Assert.AreEqual('1', Check.Args[0], 'das Suchfeld der Willkommensseite gewinnt dort immer');
  Assert.AreEqual('Strg+W', Check.Args[1]);
end;

procedure TAtlasSetupChecklistTests.EveryNonGreenPointHasAButton;
var
  Input: TAtlasSetupInput;
  Item: TAtlasSetupResult;
  Phase: TAtlasServerPhase;
begin
  for Phase := Low(TAtlasServerPhase) to High(TAtlasServerPhase) do
  begin
    Input := GoodInput;
    Input.Server.Phase := Phase;
    Input.ServerFound := Phase <> TAtlasServerPhase.Failed;
    Input.ErrorInsight := Phase = TAtlasServerPhase.Running;
    Input.Platform := '';
    for Item in TAtlasSetupChecklist.Evaluate(Input) do
      if Item.State <> TAtlasStatusState.Green then
        Assert.AreNotEqual(Ord(TAtlasSetupFix.None), Ord(Item.Fix), 'Punkt ohne Knopf: ' + IntToStr(Ord(Item.Finding)))
      else
        Assert.AreEqual(Ord(TAtlasSetupFix.None), Ord(Item.Fix));
  end;
end;

procedure TAtlasSetupChecklistTests.ProgressCountsGreenPoints;
var
  Input: TAtlasSetupInput;
  Done, Total: Integer;
  Results: TArray<TAtlasSetupResult>;
begin
  Results := TAtlasSetupChecklist.Evaluate(GoodInput);
  TAtlasSetupChecklist.Progress(Results, Done, Total);
  Assert.AreEqual(6, Total);
  Assert.AreEqual(6, Done);
  Assert.IsTrue(TAtlasSetupChecklist.Complete(Results));
  Input := GoodInput;
  Input.ErrorInsight := True;
  Results := TAtlasSetupChecklist.Evaluate(Input);
  TAtlasSetupChecklist.Progress(Results, Done, Total);
  Assert.AreEqual(5, Done, '„Einrichtung: 5 von 6 erledigt“ (#754)');
  Assert.IsFalse(TAtlasSetupChecklist.Complete(Results));
  Assert.IsFalse(TAtlasSetupChecklist.Complete(nil));
end;

procedure TAtlasSetupChecklistTests.StartOpensOnlyWhileNotGreen;
var
  Input: TAtlasSetupInput;
  Good, Duplicate, Starting: TArray<TAtlasSetupResult>;
begin
  Good := TAtlasSetupChecklist.Evaluate(GoodInput);
  Input := GoodInput;
  Input.ErrorInsight := True;
  Duplicate := TAtlasSetupChecklist.Evaluate(Input);
  Input := GoodInput;
  Input.Server.Phase := TAtlasServerPhase.Starting;
  Starting := TAtlasSetupChecklist.Evaluate(Input);
  // ui.setupChecklist aus: nur auf Abruf.
  Assert.AreEqual(Ord(TAtlasSetupStartAction.Skip),
    Ord(TAtlasSetupChecklist.StartAction(False, True, Duplicate, 0, 1000)));
  // Erster Start: immer.
  Assert.AreEqual(Ord(TAtlasSetupStartAction.Open), Ord(TAtlasSetupChecklist.StartAction(True, True, Good, 0, 1000)));
  // Alles grün: nicht mehr von selbst.
  Assert.AreEqual(Ord(TAtlasSetupStartAction.Skip), Ord(TAtlasSetupChecklist.StartAction(True, False, Good, 0, 1000)));
  // Fest gelb: sofort.
  Assert.AreEqual(Ord(TAtlasSetupStartAction.Open),
    Ord(TAtlasSetupChecklist.StartAction(True, False, Duplicate, 0, 1000)));
  // Nur im Gange: warten, nach der Wartezeit nicht öffnen.
  Assert.AreEqual(Ord(TAtlasSetupStartAction.Wait),
    Ord(TAtlasSetupChecklist.StartAction(True, False, Starting, 500, 1000)));
  Assert.AreEqual(Ord(TAtlasSetupStartAction.Skip),
    Ord(TAtlasSetupChecklist.StartAction(True, False, Starting, 1000, 1000)));
  Assert.AreEqual(Ord(TAtlasSetupStartAction.Wait), Ord(TAtlasSetupChecklist.StartAction(True, False, nil, 0, 1000)));
end;

procedure TAtlasSetupChecklistTests.StatusParsesWorkspaces;
var
  Status: TAtlasSetupServerStatus;
begin
  Status := TAtlasSetupServerStatus.Parse('{"units":42,"workspaces":[{"name":"Kunden","lastIndexMs":120,' +
    '"libraryCacheBytes":2048},{"name":"Export","lastIndexMs":-1,"libraryCacheBytes":0}],"requests":[]}');
  Assert.IsTrue(Status.Known);
  Assert.AreEqual(42, Status.Units);
  Assert.AreEqual(2, Length(Status.Workspaces));
  Assert.AreEqual('Kunden', Status.Workspaces[0].Name);
  Assert.IsTrue(Status.Workspaces[0].Done);
  Assert.AreEqual(Int64(2048), Status.Workspaces[0].LibraryCacheBytes);
  Assert.IsFalse(Status.Workspaces[1].Done);
  Assert.IsFalse(TAtlasSetupServerStatus.Parse('').Known);
  Assert.IsFalse(TAtlasSetupServerStatus.Parse('kein json').Known);
  Assert.AreEqual(-1, TAtlasSetupServerStatus.Parse('[]').Units);
  Assert.AreEqual('Kunden', TAtlasSetupChecklist.ProjectName('C:\Projekte\Kunden\Kunden.dproj'));
end;

procedure TAtlasSetupChecklistTests.ReportHasLinesAndNoIdentity;
var
  Input: TAtlasSetupReportInput;
  Report: string;
begin
  Input := Default(TAtlasSetupReportInput);
  Input.Title := 'Atlas-Einrichtung';
  Input.Summary := '5 von 6 erledigt';
  Input.AtlasVersion := '0.1.0';
  Input.IdeVersion := '37.0';
  Input.Platform := 'Win64';
  Input.Created := EncodeDate(2026, 10, 15) + EncodeTime(14, 30, 0, 0);
  Input.Identity := ['marco', 'WS-MARCO'];
  Input.Lines := [TAtlasSetupReportLine.Create(TAtlasStatusState.Green, 'Server gefunden, Version 0.1.0', False),
    TAtlasSetupReportLine.Create(TAtlasStatusState.Yellow, 'Projektgruppe von marco wird indiziert', False),
    TAtlasSetupReportLine.Create(TAtlasStatusState.Yellow, 'Export: wird aufgebaut', True),
    TAtlasSetupReportLine.Create(TAtlasStatusState.Red, 'Server WS-MARCO fehlt', False)];
  Report := TAtlasSetupChecklist.Report(Input);
  Assert.Contains(Report, 'Atlas-Einrichtung');
  Assert.Contains(Report, 'Atlas 0.1.0, IDE 37.0, Win64');
  Assert.Contains(Report, '2026-10-15 14:30');
  Assert.Contains(Report, '5 von 6 erledigt');
  Assert.Contains(Report, '[ok] Server gefunden, Version 0.1.0');
  Assert.Contains(Report, '[!]  Projektgruppe von <benutzer> wird indiziert');
  Assert.Contains(Report, '       - Export: wird aufgebaut');
  Assert.Contains(Report, '[x]  Server <benutzer> fehlt');
  Assert.IsFalse(Report.ToLower.Contains('marco'), 'Benutzer- und Rechnername ersetzt');
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
    Result.Server.Phase := TAtlasServerPhase.Failed
  else if Starts + Restarts = 0 then
    Result.Server.Phase := TAtlasServerPhase.NotStarted;
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
    Inc(Restarts)
  else
    Inc(Starts);
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
  Fake: TFakeEnvironment;
  Environment: IAtlasSetupEnvironment;
  Controller: TAtlasSetupController;
begin
  Fake := TFakeEnvironment.Create;
  Environment := Fake;
  Fake.Choose := True;
  Fake.Chosen := ' C:\Atlas\AtlasServer.exe ';
  Controller := TAtlasSetupController.Create(Environment);
  try
    Controller.Refresh;
    Assert.AreEqual(Ord(TAtlasSetupFinding.ServerMissing), Ord(Controller.Results[0].Finding));
    Assert.IsTrue(Controller.Apply(Controller.Results[0].Fix));
    Assert.AreEqual('C:\Atlas\AtlasServer.exe', Fake.Path, 'Pfad gespeichert');
    Assert.AreEqual(1, Fake.Restarts, 'Mit dem neuen Pfad neu gestartet');
    Assert.AreEqual(Ord(TAtlasSetupFinding.ServerReady), Ord(Controller.Results[0].Finding));
    Assert.AreEqual(Ord(TAtlasStatusState.Green), Ord(Controller.Results[0].State), 'Prüfung danach grün');
    Assert.IsTrue(Controller.Complete);
  finally
    Controller.Free;
  end;
end;

procedure TAtlasSetupControllerTests.CancelledChoiceChangesNothing;
var
  Fake: TFakeEnvironment;
  Environment: IAtlasSetupEnvironment;
  Controller: TAtlasSetupController;
begin
  Fake := TFakeEnvironment.Create;
  Environment := Fake;
  Fake.Choose := False;
  Fake.Chosen := 'C:\Atlas\AtlasServer.exe';
  Controller := TAtlasSetupController.Create(Environment);
  try
    Controller.Refresh;
    Assert.IsFalse(Controller.Apply(TAtlasSetupFix.ChooseServerPath));
    Assert.AreEqual('', Fake.Path);
    Assert.AreEqual(0, Fake.Restarts);
    Assert.AreEqual(Ord(TAtlasStatusState.Red), Ord(Controller.Results[0].State));
    Assert.IsFalse(Controller.Apply(TAtlasSetupFix.Explain), 'Erklären tut nichts in der Umgebung');
  finally
    Controller.Free;
  end;
end;

procedure TAtlasSetupControllerTests.FixesCallTheEnvironment;
var
  Fake: TFakeEnvironment;
  Environment: IAtlasSetupEnvironment;
  Controller: TAtlasSetupController;
  Done, Total: Integer;
begin
  Fake := TFakeEnvironment.Create;
  Environment := Fake;
  Fake.Path := 'C:\Atlas\AtlasServer.exe';
  Fake.ErrorInsight := True;
  Controller := TAtlasSetupController.Create(Environment);
  try
    Controller.Refresh;
    Controller.Progress(Done, Total);
    Assert.AreEqual(2, Done, 'Server nicht gestartet, Index und Cache unbekannt, Error Insight doppelt');
    Assert.IsTrue(Controller.Apply(TAtlasSetupFix.StartServer));
    Assert.AreEqual(1, Fake.Starts);
    Assert.IsTrue(Controller.Apply(TAtlasSetupFix.DisableErrorInsight));
    Assert.IsFalse(Fake.ErrorInsight);
    Assert.IsTrue(Controller.Complete);
    Controller.Apply(TAtlasSetupFix.RebuildIndex);
    Controller.Apply(TAtlasSetupFix.BuildLibraryCache);
    Assert.AreEqual(2, Fake.Rebuilds);
    Controller.Apply(TAtlasSetupFix.OpenKeyConflicts);
    Assert.AreEqual(1, Fake.KeysOpened);
    Controller.Apply(TAtlasSetupFix.RestartServer);
    Assert.AreEqual(1, Fake.Restarts);
    Controller.Apply(TAtlasSetupFix.EnableErrorInsight);
    Assert.IsTrue(Fake.ErrorInsight);
  finally
    Controller.Free;
  end;
end;

procedure TAtlasSetupControllerTests.VersionOnlyOnChange;
var
  Fake: TFakeEnvironment;
  Environment: IAtlasSetupEnvironment;
  Controller: TAtlasSetupController;
  Version: Integer;
begin
  Fake := TFakeEnvironment.Create;
  Environment := Fake;
  Fake.Path := 'C:\Atlas\AtlasServer.exe';
  Controller := TAtlasSetupController.Create(Environment);
  try
    Controller.Refresh;
    Version := Controller.Version;
    Controller.Refresh;
    Assert.AreEqual(Version, Controller.Version, 'Gleicher Stand: keine neue Version');
    Fake.ErrorInsight := True;
    Controller.Refresh;
    Assert.AreEqual(Version + 1, Controller.Version);
  finally
    Controller.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSetupChecklistTests);
  TDUnitX.RegisterTestFixture(TAtlasSetupControllerTests);

end.
