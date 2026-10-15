unit Atlas.Core.Welcome.Projects.Tests;

// Tests des Bereichs „Projekte“ ohne VCL (#592): Auswahl der Projekte,
// Marken nach Zustand (Akzeptanzkriterien: „main“ mit grüner Marke
// „Build 0/0/0“, rote Marke „2 Fehler“ mit Sprungziel, ohne
// Versionsverwaltung kein Branch und kein Fehler), Übernahme eines Compiles
// in die Zusammenfassung, Abfrage der Versionsverwaltung mit Ersatz-Umsetzung
// und gekürzte Pfade.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasWelcomeProjectsTests = class
  public
    [Test]
    procedure EntriesKeepOrderDropDuplicatesAndHidden;
    [Test]
    procedure EntriesRespectMaximum;
    [Test]
    procedure CleanBuildOnMainIsGreen;
    [Test]
    procedure BuildErrorsAreRedAndJump;
    [Test]
    procedure WarningsAndHintsAreYellow;
    [Test]
    procedure FailedBuildWithoutMessagesIsRed;
    [Test]
    procedure NewerCheckErrorsShow;
    [Test]
    procedure ChangesSyncAndRules;
    [Test]
    procedure NoVersionControlShowsNothing;
    [Test]
    procedure DetachedHeadShowsCommit;
    [Test]
    procedure RecordsBuildAndCheck;
    [Test]
    procedure ProbeReadsHeadAndChanges;
    [Test]
    procedure ProbeWithoutWorkingCopyIsNone;
    [Test]
    procedure ProbeFailureKeepsStoredState;
    [Test]
    procedure ShortensLongPaths;
    [Test]
    procedure SettingsDefaultsAndLimits;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Projects.Summary,
  Atlas.Core.Build.Messages,
  Atlas.Core.Vcs.Contract,
  Atlas.Core.Welcome.Projects;

type
  /// <summary>Ersatz für Git/SVN: liefert festgelegte Ergebnisse ohne Prozess.</summary>
  TFakeVcs = class(TInterfacedObject, IAtlasVersionControl)
  public
    FKind: TAtlasVcsKind;
    FHeadOutcome: TAtlasVcsOutcome;
    FChangesOutcome: TAtlasVcsOutcome;
    FHead: TAtlasVcsHead;
    FChanges: TArray<TAtlasVcsChange>;
    function Kind: TAtlasVcsKind;
    function WorkingCopy: TAtlasVcsWorkingCopy;
    function Head(out AHead: TAtlasVcsHead): TAtlasVcsOutcome;
    function Changes(out AChanges: TArray<TAtlasVcsChange>): TAtlasVcsOutcome;
    function FileAt(const AFileName, ARevision: string; out AContent: TBytes): TAtlasVcsOutcome;
    function Blame(const AFileName: string; out ALines: TArray<TAtlasVcsBlameLine>): TAtlasVcsOutcome;
    function ChangeMarker: string;
  end;

function TFakeVcs.Kind: TAtlasVcsKind;
begin
  Result := FKind;
end;

function TFakeVcs.WorkingCopy: TAtlasVcsWorkingCopy;
begin
  Result := TAtlasVcsWorkingCopy.Empty;
  Result.Kind := FKind;
end;

function TFakeVcs.Head(out AHead: TAtlasVcsHead): TAtlasVcsOutcome;
begin
  AHead := FHead;
  Result := FHeadOutcome;
end;

function TFakeVcs.Changes(out AChanges: TArray<TAtlasVcsChange>): TAtlasVcsOutcome;
begin
  AChanges := FChanges;
  Result := FChangesOutcome;
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

function Entry(const ASummary: TAtlasProjectSummary): TAtlasProjectEntry;
begin
  Result := Default(TAtlasProjectEntry);
  Result.Summary := ASummary;
  Result.HasSummary := True;
end;

function OnMain: TAtlasProjectSummary;
begin
  Result := TAtlasProjectSummary.Create('C:\Projekte\Demo.dproj');
  Result.Vcs.Known := True;
  Result.Vcs.Kind := 'git';
  Result.Vcs.Branch := 'main';
  Result.Vcs.Revision := 'abcdef0123456789';
  Result.Vcs.Changed := 0;
  Result.Vcs.Ahead := 0;
  Result.Vcs.Behind := 0;
end;

function WithBuild(const ASummary: TAtlasProjectSummary; ASucceeded: Boolean; AErrors, AWarnings,
  AHints: Integer): TAtlasProjectSummary;
begin
  Result := ASummary;
  Result.Build.Known := True;
  Result.Build.At := EncodeDate(2026, 10, 15) + EncodeTime(10, 0, 0, 0);
  Result.Build.Kind := 'build';
  Result.Build.Succeeded := ASucceeded;
  Result.Build.Errors := AErrors;
  Result.Build.Warnings := AWarnings;
  Result.Build.Hints := AHints;
end;

function Message(ASeverity: TAtlasCompilerSeverity; const AFileName: string; ALine: Integer;
  const ACode: string): TAtlasCompilerMessage;
begin
  Result := Default(TAtlasCompilerMessage);
  Result.Severity := ASeverity;
  Result.FileName := AFileName;
  Result.Line := ALine;
  Result.Column := 3;
  Result.Code := ACode;
  Result.Text := 'Text';
end;

{ TAtlasWelcomeProjectsTests }

procedure TAtlasWelcomeProjectsTests.EntriesKeepOrderDropDuplicatesAndHidden;
var
  Entries: TAtlasProjectEntries;
begin
  Entries := TAtlasWelcomeProjects.Entries(['C:\A\Eins.dproj', '', 'C:\B\Zwei.groupproj', 'c:/a/eins.dproj',
    'C:\C\Weg.dproj', 'C:\D\Neu.dproj'],
    function(const AProject: string; out ASummary: TAtlasProjectSummary): Boolean
    begin
      ASummary := TAtlasProjectSummary.Create('C:\anders\geschrieben.dproj');
      Result := not SameText(ExtractFileName(AProject), 'Neu.dproj');
      ASummary.Hidden := SameText(ExtractFileName(AProject), 'Weg.dproj');
    end, 8);
  Assert.AreEqual(3, Length(Entries));
  Assert.AreEqual('C:\A\Eins.dproj', Entries[0].Project, 'Pfad der IDE gilt');
  Assert.AreEqual('Eins', Entries[0].Name);
  Assert.IsTrue(Entries[0].HasSummary);
  Assert.AreEqual('C:\B\Zwei.groupproj', Entries[1].Project, 'Projektgruppen zählen mit');
  Assert.AreEqual('C:\D\Neu.dproj', Entries[2].Project);
  Assert.IsFalse(Entries[2].HasSummary, 'ohne Datei trotzdem in der Liste');
  Assert.IsFalse(Entries[2].Summary.Build.Known);
end;

procedure TAtlasWelcomeProjectsTests.EntriesRespectMaximum;
var
  Recent: TArray<string>;
  Index: Integer;
begin
  Recent := nil;
  for Index := 1 to 40 do
    Recent := Recent + [Format('C:\P%d\P%d.dproj', [Index, Index])];
  Assert.AreEqual(8, Length(TAtlasWelcomeProjects.Entries(Recent, nil, TAtlasWelcomeProjects.DefaultMax)));
  Assert.AreEqual(1, Length(TAtlasWelcomeProjects.Entries(Recent, nil, 0)), 'mindestens eins');
  Assert.AreEqual(30, Length(TAtlasWelcomeProjects.Entries(Recent, nil, 99)), 'höchstens 30');
  Assert.AreEqual(0, Length(TAtlasWelcomeProjects.Entries(nil, nil, 8)));
end;

procedure TAtlasWelcomeProjectsTests.CleanBuildOnMainIsGreen;
var
  Item: TAtlasProjectEntry;
  Pills: TArray<TAtlasProjectPill>;
begin
  // Akzeptanzkriterium: letzter Build 0/0/0 auf main → „main“ und grüne Marke „Build 0/0/0“.
  Item := Entry(WithBuild(OnMain, True, 0, 0, 0));
  Assert.AreEqual('main', Item.Branch);
  Pills := TAtlasWelcomeProjects.Pills(Item);
  Assert.AreEqual(1, Length(Pills));
  Assert.IsTrue(Pills[0].Kind = TAtlasProjectPillKind.Build);
  Assert.IsTrue(Pills[0].Level = TAtlasProjectPillLevel.Good);
  Assert.AreEqual(0, Pills[0].A + Pills[0].B + Pills[0].C);
  Assert.IsFalse(Pills[0].Clickable);
  Assert.IsTrue(TAtlasWelcomeProjects.Level(Pills) = TAtlasProjectPillLevel.Good);
end;

procedure TAtlasWelcomeProjectsTests.BuildErrorsAreRedAndJump;
var
  Summary: TAtlasProjectSummary;
  Pills: TArray<TAtlasProjectPill>;
begin
  // Akzeptanzkriterium: Build mit 2 Fehlern → rote Marke „2 Fehler“, Klick springt zum ersten Fehler.
  Summary := WithBuild(OnMain, False, 2, 1, 0);
  Summary.Build.First.FileName := 'C:\Projekte\Main.pas';
  Summary.Build.First.Line := 12;
  Pills := TAtlasWelcomeProjects.Pills(Entry(Summary));
  Assert.IsTrue(Pills[0].Kind = TAtlasProjectPillKind.BuildErrors);
  Assert.IsTrue(Pills[0].Level = TAtlasProjectPillLevel.Error);
  Assert.AreEqual(2, Pills[0].A);
  Assert.IsTrue(Pills[0].Clickable);
  Assert.AreEqual('C:\Projekte\Main.pas', Pills[0].Target.FileName);
  Assert.AreEqual(12, Pills[0].Target.Line);
  Assert.IsTrue(TAtlasWelcomeProjects.Level(Pills) = TAtlasProjectPillLevel.Error);
end;

procedure TAtlasWelcomeProjectsTests.WarningsAndHintsAreYellow;
var
  Pills: TArray<TAtlasProjectPill>;
begin
  Pills := TAtlasWelcomeProjects.Pills(Entry(WithBuild(OnMain, True, 0, 3, 1)));
  Assert.IsTrue(Pills[0].Kind = TAtlasProjectPillKind.Build);
  Assert.IsTrue(Pills[0].Level = TAtlasProjectPillLevel.Warning);
  Assert.AreEqual(3, Pills[0].B);
  Assert.AreEqual(1, Pills[0].C);
  Pills := TAtlasWelcomeProjects.Pills(Entry(WithBuild(OnMain, True, 0, 0, 2)));
  Assert.IsTrue(Pills[0].Level = TAtlasProjectPillLevel.Warning, 'Hinweise auch: Ziel ist 0/0/0');
end;

procedure TAtlasWelcomeProjectsTests.FailedBuildWithoutMessagesIsRed;
var
  Pills: TArray<TAtlasProjectPill>;
begin
  Pills := TAtlasWelcomeProjects.Pills(Entry(WithBuild(OnMain, False, 0, 0, 0)));
  Assert.IsTrue(Pills[0].Kind = TAtlasProjectPillKind.Build);
  Assert.IsTrue(Pills[0].Level = TAtlasProjectPillLevel.Error);
  Assert.IsFalse(Pills[0].Clickable);
end;

procedure TAtlasWelcomeProjectsTests.NewerCheckErrorsShow;
var
  Summary: TAtlasProjectSummary;
  Pills: TArray<TAtlasProjectPill>;
begin
  Summary := WithBuild(OnMain, True, 0, 0, 0);
  Summary.Check.Known := True;
  Summary.Check.Errors := 1;
  Summary.Check.First.FileName := 'C:\Projekte\Unit2.pas';
  Summary.Check.At := Summary.Build.At + 1 / 24;
  Pills := TAtlasWelcomeProjects.Pills(Entry(Summary));
  Assert.AreEqual(2, Length(Pills));
  Assert.IsTrue(Pills[1].Kind = TAtlasProjectPillKind.CheckErrors);
  Assert.IsTrue(Pills[1].Clickable);
  Summary.Check.At := Summary.Build.At - 1 / 24;
  Assert.AreEqual(1, Length(TAtlasWelcomeProjects.Pills(Entry(Summary))), 'ältere Prüfung zählt nicht');
  Summary.Check.At := Summary.Build.At + 1 / 24;
  Summary.Check.Errors := 0;
  Assert.AreEqual(1, Length(TAtlasWelcomeProjects.Pills(Entry(Summary))), 'fehlerfreie Prüfung ohne Marke');
end;

procedure TAtlasWelcomeProjectsTests.ChangesSyncAndRules;
var
  Summary: TAtlasProjectSummary;
  Pills: TArray<TAtlasProjectPill>;
begin
  Summary := OnMain;
  Summary.Vcs.Changed := 4;
  Summary.Vcs.Ahead := 2;
  Summary.Vcs.Behind := -1;
  Summary.Rules.Known := True;
  Summary.Rules.NewHits := 3;
  Pills := TAtlasWelcomeProjects.Pills(Entry(Summary));
  Assert.AreEqual(3, Length(Pills), 'ohne Build keine Build-Marke');
  Assert.IsTrue(Pills[0].Kind = TAtlasProjectPillKind.Changes);
  Assert.AreEqual(4, Pills[0].A);
  Assert.IsTrue(Pills[0].Level = TAtlasProjectPillLevel.Warning);
  Assert.IsTrue(Pills[1].Kind = TAtlasProjectPillKind.Sync);
  Assert.AreEqual(2, Pills[1].A);
  Assert.AreEqual(0, Pills[1].B, 'unbekannt zählt als 0');
  Assert.IsTrue(Pills[1].Level = TAtlasProjectPillLevel.Neutral);
  Assert.IsTrue(Pills[2].Kind = TAtlasProjectPillKind.Rules);
  Assert.AreEqual(3, Pills[2].A);
end;

procedure TAtlasWelcomeProjectsTests.NoVersionControlShowsNothing;
var
  Summary: TAtlasProjectSummary;
  Item: TAtlasProjectEntry;
begin
  // Akzeptanzkriterium: außerhalb einer Versionsverwaltung kein Branch und kein Fehler.
  Summary := TAtlasProjectSummary.Create('C:\Ohne\Demo.dproj');
  Summary.Vcs.Known := True;
  Summary.Vcs.Kind := 'none';
  Item := Entry(Summary);
  Assert.AreEqual('', Item.Branch);
  Assert.IsFalse(Item.VcsStale, 'kein „Stand vom …“');
  Assert.AreEqual(0, Length(TAtlasWelcomeProjects.Pills(Item)));
  Assert.IsTrue(TAtlasWelcomeProjects.Level(TAtlasWelcomeProjects.Pills(Item)) = TAtlasProjectPillLevel.Neutral);
  // Gespeicherter Stand mit Arbeitskopie: bis zur frischen Abfrage „Stand vom …“.
  Item := Entry(OnMain);
  Assert.IsTrue(Item.VcsStale);
  Item.VcsFresh := True;
  Assert.IsFalse(Item.VcsStale);
end;

procedure TAtlasWelcomeProjectsTests.DetachedHeadShowsCommit;
var
  Summary: TAtlasProjectSummary;
begin
  Summary := OnMain;
  Summary.Vcs.Branch := '';
  Assert.AreEqual('abcdef0', Entry(Summary).Branch);
  Summary.Vcs.Kind := 'svn';
  Summary.Vcs.Branch := 'trunk';
  Assert.AreEqual('trunk', Entry(Summary).Branch);
end;

procedure TAtlasWelcomeProjectsTests.RecordsBuildAndCheck;
var
  Summary: TAtlasProjectSummary;
  Now_: TDateTime;
begin
  Summary := TAtlasProjectSummary.Create('C:\Projekte\Demo.dproj');
  Now_ := EncodeDate(2026, 10, 15) + EncodeTime(11, 0, 0, 0);
  TAtlasWelcomeProjects.RecordCompile(Summary, [
    Message(TAtlasCompilerSeverity.Hint, 'C:\Projekte\A.pas', 1, 'H2077'),
    Message(TAtlasCompilerSeverity.Error, '', 0, 'F2613'),
    Message(TAtlasCompilerSeverity.Error, 'C:\Projekte\B.pas', 12, 'E2003'),
    Message(TAtlasCompilerSeverity.Fatal, 'C:\Projekte\C.pas', 1, 'F1026'),
    Message(TAtlasCompilerSeverity.Warning, 'C:\Projekte\A.pas', 4, 'W1000'),
    Message(TAtlasCompilerSeverity.Info, '', 0, '')], False, False, 'build', 'Debug', 'Win32', Now_);
  Assert.IsTrue(Summary.Build.Known);
  Assert.AreEqual(3, Summary.Build.Errors, 'Fatal zählt als Fehler');
  Assert.AreEqual(1, Summary.Build.Warnings);
  Assert.AreEqual(1, Summary.Build.Hints);
  Assert.IsFalse(Summary.Build.Succeeded);
  Assert.AreEqual('build', Summary.Build.Kind);
  Assert.AreEqual('Debug', Summary.Build.Configuration);
  Assert.AreEqual('Win32', Summary.Build.Platform);
  Assert.AreEqual('C:\Projekte\B.pas', Summary.Build.First.FileName, 'erste Fehlermeldung mit Datei');
  Assert.AreEqual(12, Summary.Build.First.Line);
  Assert.AreEqual(3, Summary.Build.First.Column);
  Assert.AreEqual('E2003', Summary.Build.First.Code);
  Assert.IsTrue(Summary.Build.At = Now_);
  Assert.IsFalse(Summary.Check.Known, 'Build ist keine Prüfung');
  // Hintergrundprüfung (#548): nur "check", der Build bleibt.
  TAtlasWelcomeProjects.RecordCompile(Summary, [], True, True, 'check', 'Debug', 'Win32', Now_ + 1 / 24);
  Assert.IsTrue(Summary.Check.Known);
  Assert.AreEqual(0, Summary.Check.Errors);
  Assert.IsTrue(Summary.Check.First.IsEmpty);
  Assert.AreEqual(3, Summary.Build.Errors);
  // Neuer fehlerfreier Build ersetzt das Sprungziel.
  TAtlasWelcomeProjects.RecordCompile(Summary, [], False, True, 'make', 'Debug', 'Win32', Now_ + 2 / 24);
  Assert.AreEqual(0, Summary.Build.Errors);
  Assert.IsTrue(Summary.Build.First.IsEmpty);
  Assert.IsTrue(Summary.Build.Succeeded);
end;

procedure TAtlasWelcomeProjectsTests.ProbeReadsHeadAndChanges;
var
  Fake: TFakeVcs;
  Vcs: IAtlasVersionControl;
  State: TAtlasProjectVcs;
  Change: TAtlasVcsChange;
begin
  Fake := TFakeVcs.Create;
  Vcs := Fake;
  Fake.FKind := TAtlasVcsKind.Git;
  Fake.FHeadOutcome := TAtlasVcsOutcome.Ok;
  Fake.FChangesOutcome := TAtlasVcsOutcome.Ok;
  Fake.FHead := TAtlasVcsHead.Empty;
  Fake.FHead.Branch := 'main';
  Fake.FHead.Revision := '0123456789';
  Fake.FHead.Ahead := 1;
  Fake.FHead.Behind := 2;
  Change := Default(TAtlasVcsChange);
  Fake.FChanges := [Change, Change, Change];
  Assert.IsTrue(TAtlasWelcomeProjects.Probe(Vcs, 46000, State));
  Assert.IsTrue(State.Known);
  Assert.IsTrue(State.InWorkingCopy);
  Assert.AreEqual('git', State.Kind);
  Assert.AreEqual('main', State.Branch);
  Assert.AreEqual('0123456789', State.Revision);
  Assert.AreEqual(3, State.Changed);
  Assert.AreEqual(1, State.Ahead);
  Assert.AreEqual(2, State.Behind);
  Assert.IsTrue(State.At = 46000);
  // Änderungen nicht lesbar (Zeitlimit): Branch gilt, Anzahl unbekannt.
  Fake.FChangesOutcome := TAtlasVcsOutcome.TimedOut;
  Assert.IsTrue(TAtlasWelcomeProjects.Probe(Vcs, 46000, State));
  Assert.AreEqual(-1, State.Changed);
  Fake.FKind := TAtlasVcsKind.Svn;
  Fake.FChangesOutcome := TAtlasVcsOutcome.Ok;
  Assert.IsTrue(TAtlasWelcomeProjects.Probe(Vcs, 46000, State));
  Assert.AreEqual('svn', State.Kind);
end;

procedure TAtlasWelcomeProjectsTests.ProbeWithoutWorkingCopyIsNone;
var
  Fake: TFakeVcs;
  Vcs: IAtlasVersionControl;
  State: TAtlasProjectVcs;
begin
  Fake := TFakeVcs.Create;
  Vcs := Fake;
  Fake.FKind := TAtlasVcsKind.None;
  Fake.FHeadOutcome := TAtlasVcsOutcome.NoWorkingCopy;
  Assert.IsTrue(TAtlasWelcomeProjects.Probe(Vcs, 46000, State));
  Assert.AreEqual('none', State.Kind);
  Assert.IsFalse(State.InWorkingCopy);
  Fake.FHeadOutcome := TAtlasVcsOutcome.Disabled;
  Assert.IsTrue(TAtlasWelcomeProjects.Probe(Vcs, 46000, State), 'vcs.provider = off');
  Assert.AreEqual('none', State.Kind);
end;

procedure TAtlasWelcomeProjectsTests.ProbeFailureKeepsStoredState;
var
  Fake: TFakeVcs;
  Vcs: IAtlasVersionControl;
  State: TAtlasProjectVcs;
  Outcome: TAtlasVcsOutcome;
begin
  Fake := TFakeVcs.Create;
  Vcs := Fake;
  Fake.FKind := TAtlasVcsKind.Git;
  for Outcome in [TAtlasVcsOutcome.ToolMissing, TAtlasVcsOutcome.Failed, TAtlasVcsOutcome.TimedOut,
    TAtlasVcsOutcome.Cancelled, TAtlasVcsOutcome.MainThread] do
  begin
    Fake.FHeadOutcome := Outcome;
    Assert.IsFalse(TAtlasWelcomeProjects.Probe(Vcs, 46000, State), AtlasVcsOutcomeName(Outcome));
    Assert.IsFalse(State.Known);
  end;
  Assert.IsFalse(TAtlasWelcomeProjects.Probe(nil, 46000, State));
end;

procedure TAtlasWelcomeProjectsTests.ShortensLongPaths;
var
  Short: string;
begin
  Assert.AreEqual('C:\P\Demo.dproj', TAtlasWelcomeProjects.ShortPath('C:\P\Demo.dproj', 40));
  Short := TAtlasWelcomeProjects.ShortPath('C:\Users\marco\Documents\Embarcadero\Studio\Projekte\Atlas\Demo.dproj', 40);
  Assert.AreEqual('C:\'#$2026'\Studio\Projekte\Atlas\Demo.dproj', Short);
  Assert.IsTrue(Length(Short) <= 40);
  Short := TAtlasWelcomeProjects.ShortPath('C:\Ordner\EinSehrLangerProjektnameDerNichtPasst.dproj', 20);
  Assert.AreEqual(20, Length(Short), 'nur das Ende des Namens');
  Assert.AreEqual(#$2026, Copy(Short, 1, 1));
end;

procedure TAtlasWelcomeProjectsTests.SettingsDefaultsAndLimits;
var
  Settings: TAtlasPluginSettings;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.WelcomePageProjectStatus);
  Assert.AreEqual(TAtlasWelcomeProjects.DefaultMax, Settings.WelcomePageMaxProjects);
  Assert.IsTrue(Settings.WelcomePageRefreshVcs);
  Settings.WelcomePageMaxProjects := 0;
  Settings.Normalize;
  Assert.AreEqual(TAtlasWelcomeProjects.MinMax, Settings.WelcomePageMaxProjects);
  Settings.WelcomePageMaxProjects := 500;
  Settings.Normalize;
  Assert.AreEqual(TAtlasWelcomeProjects.MaxMax, Settings.WelcomePageMaxProjects);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasWelcomeProjectsTests);

end.
