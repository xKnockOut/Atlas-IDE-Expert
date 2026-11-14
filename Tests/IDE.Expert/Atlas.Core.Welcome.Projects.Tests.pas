unit Atlas.Core.Welcome.Projects.Tests;

// Tests des Bereichs „Projekte“ ohne VCL (#592): Auswahl der Projekte,
// Marken nach Zustand (Akzeptanzkriterien: „main“ mit grüner Marke
// „Build 0/0/0“, rote Marke „2 Fehler“ mit Sprungziel, ohne
// Versionsverwaltung kein Branch und kein Fehler), Übernahme eines Compiles
// in die Zusammenfassung, Abfrage der Versionsverwaltung mit Ersatz-Umsetzung
// (geänderte Dateien nur im Projektordner, Ende einer hängenden Abfrage),
// Regeltreffer aus den Problemen des Servers, gekürzte Pfade und wann sich
// „Atlas-Start“ ohne Projekt öffnet (#1114).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Welcome')]
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
    procedure ShortensLongPaths;
    [Test]
    procedure SettingsDefaultsAndLimits;
    [Test]
    procedure OpensWhenLastProjectClosed;
    [Test]
    procedure StaysClosedWhileProjectsRemain;
    [Test]
    procedure StaysClosedWhenSwitchedOff;
    [Test]
    procedure StaysClosedWhenIdeEnds;
    [Test]
    procedure OpenWhenNoProjectDefaultsOn;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.History,
  Atlas.Core.Projects.Summary,
  Atlas.Core.Build.Messages,
  Atlas.Core.VersionControl.Contract,
  Atlas.Core.Problems.Store,
  Atlas.Core.Welcome.Projects;

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

{ TAtlasWelcomeProjectsTests }

procedure TAtlasWelcomeProjectsTests.EntriesKeepOrderDropDuplicatesAndHidden;
var
  mEntries: TAtlasProjectEntries;
begin
  mEntries := TAtlasWelcomeProjects.Entries(['C:\A\Eins.dproj', '', 'C:\B\Zwei.groupproj', 'c:/a/eins.dproj',
    'C:\C\Weg.dproj', 'C:\D\Neu.dproj'],
    function(const AProject: string; out ASummary: TAtlasProjectSummary): Boolean
    begin
      ASummary := TAtlasProjectSummary.Create('C:\anders\geschrieben.dproj');
      Result := not SameText(ExtractFileName(AProject), 'Neu.dproj');
      ASummary.Hidden := SameText(ExtractFileName(AProject), 'Weg.dproj');
    end, 8);
  Assert.AreEqual(3, Integer(Length(mEntries)));
  Assert.AreEqual('C:\A\Eins.dproj', mEntries[0].Project, 'Pfad der IDE gilt');
  Assert.AreEqual('Eins', mEntries[0].Name);
  Assert.IsTrue(mEntries[0].HasSummary);
  Assert.AreEqual('C:\B\Zwei.groupproj', mEntries[1].Project, 'Projektgruppen zählen mit');
  Assert.AreEqual('C:\D\Neu.dproj', mEntries[2].Project);
  Assert.IsFalse(mEntries[2].HasSummary, 'ohne Datei trotzdem in der Liste');
  Assert.IsFalse(mEntries[2].Summary.Build.Known);
end;

procedure TAtlasWelcomeProjectsTests.EntriesRespectMaximum;
var
  mRecent: TArray<string>;
  mIndex: Integer;
begin
  mRecent := nil;
  for mIndex := 1 to 40 do
  begin
    mRecent := mRecent + [Format('C:\P%d\P%d.dproj', [mIndex, mIndex])];
  end;
  Assert.AreEqual(8, Integer(Length(TAtlasWelcomeProjects.Entries(mRecent, nil, TAtlasWelcomeProjects.cDefaultMax))));
  Assert.AreEqual(1, Integer(Length(TAtlasWelcomeProjects.Entries(mRecent, nil, 0))), 'mindestens eins');
  Assert.AreEqual(30, Integer(Length(TAtlasWelcomeProjects.Entries(mRecent, nil, 99))), 'höchstens 30');
  Assert.AreEqual(0, Integer(Length(TAtlasWelcomeProjects.Entries(nil, nil, 8))));
end;

procedure TAtlasWelcomeProjectsTests.CleanBuildOnMainIsGreen;
var
  mItem: TAtlasProjectEntry;
  mPills: TArray<TAtlasProjectPill>;
begin
  // Akzeptanzkriterium: letzter Build 0/0/0 auf main → „main“ und grüne Marke „Build 0/0/0“.
  mItem := Entry(WithBuild(OnMain, True, 0, 0, 0));
  Assert.AreEqual('main', mItem.Branch);
  mPills := TAtlasWelcomeProjects.Pills(mItem);
  Assert.AreEqual(1, Integer(Length(mPills)));
  Assert.AreEqual<TAtlasProjectPillKind>(TAtlasProjectPillKind.Build, mPills[0].Kind);
  Assert.AreEqual<TAtlasProjectPillLevel>(TAtlasProjectPillLevel.Good, mPills[0].Level);
  Assert.AreEqual(0, mPills[0].A + mPills[0].B + mPills[0].C);
  Assert.IsFalse(mPills[0].Clickable);
  Assert.AreEqual<TAtlasProjectPillLevel>(TAtlasProjectPillLevel.Good, TAtlasWelcomeProjects.Level(mPills));
end;

procedure TAtlasWelcomeProjectsTests.BuildErrorsAreRedAndJump;
var
  mSummary: TAtlasProjectSummary;
  mPills: TArray<TAtlasProjectPill>;
begin
  // Akzeptanzkriterium: Build mit 2 Fehlern → rote Marke „2 Fehler“, Klick springt zum ersten Fehler.
  mSummary := WithBuild(OnMain, False, 2, 1, 0);
  mSummary.Build.First.FileName := 'C:\Projekte\Main.pas';
  mSummary.Build.First.Line := 12;
  mPills := TAtlasWelcomeProjects.Pills(Entry(mSummary));
  Assert.AreEqual<TAtlasProjectPillKind>(TAtlasProjectPillKind.BuildErrors, mPills[0].Kind);
  Assert.AreEqual<TAtlasProjectPillLevel>(TAtlasProjectPillLevel.Error, mPills[0].Level);
  Assert.AreEqual(2, mPills[0].A);
  Assert.IsTrue(mPills[0].Clickable);
  Assert.AreEqual('C:\Projekte\Main.pas', mPills[0].Target.FileName);
  Assert.AreEqual(12, mPills[0].Target.Line);
  Assert.AreEqual<TAtlasProjectPillLevel>(TAtlasProjectPillLevel.Error, TAtlasWelcomeProjects.Level(mPills));
end;

procedure TAtlasWelcomeProjectsTests.WarningsAndHintsAreYellow;
var
  mPills: TArray<TAtlasProjectPill>;
begin
  mPills := TAtlasWelcomeProjects.Pills(Entry(WithBuild(OnMain, True, 0, 3, 1)));
  Assert.AreEqual<TAtlasProjectPillKind>(TAtlasProjectPillKind.Build, mPills[0].Kind);
  Assert.AreEqual<TAtlasProjectPillLevel>(TAtlasProjectPillLevel.Warning, mPills[0].Level);
  Assert.AreEqual(3, mPills[0].B);
  Assert.AreEqual(1, mPills[0].C);
  mPills := TAtlasWelcomeProjects.Pills(Entry(WithBuild(OnMain, True, 0, 0, 2)));
  Assert.AreEqual<TAtlasProjectPillLevel>(TAtlasProjectPillLevel.Warning,
    mPills[0].Level, 'Hinweise auch: Ziel ist 0/0/0');
end;

procedure TAtlasWelcomeProjectsTests.FailedBuildWithoutMessagesIsRed;
var
  mPills: TArray<TAtlasProjectPill>;
begin
  mPills := TAtlasWelcomeProjects.Pills(Entry(WithBuild(OnMain, False, 0, 0, 0)));
  Assert.AreEqual<TAtlasProjectPillKind>(TAtlasProjectPillKind.Build, mPills[0].Kind);
  Assert.AreEqual<TAtlasProjectPillLevel>(TAtlasProjectPillLevel.Error, mPills[0].Level);
  Assert.IsFalse(mPills[0].Clickable);
end;

procedure TAtlasWelcomeProjectsTests.NewerCheckErrorsShow;
var
  mSummary: TAtlasProjectSummary;
  mPills: TArray<TAtlasProjectPill>;
begin
  mSummary := WithBuild(OnMain, True, 0, 0, 0);
  mSummary.Check.Known := True;
  mSummary.Check.Errors := 1;
  mSummary.Check.First.FileName := 'C:\Projekte\Unit2.pas';
  mSummary.Check.At := mSummary.Build.At + 1 / 24;
  mPills := TAtlasWelcomeProjects.Pills(Entry(mSummary));
  Assert.AreEqual(2, Integer(Length(mPills)));
  Assert.AreEqual<TAtlasProjectPillKind>(TAtlasProjectPillKind.CheckErrors, mPills[1].Kind);
  Assert.IsTrue(mPills[1].Clickable);
  mSummary.Check.At := mSummary.Build.At - 1 / 24;
  Assert.AreEqual(1, Integer(Length(TAtlasWelcomeProjects.Pills(Entry(mSummary)))), 'ältere Prüfung zählt nicht');
  mSummary.Check.At := mSummary.Build.At + 1 / 24;
  mSummary.Check.Errors := 0;
  Assert.AreEqual(1, Integer(Length(TAtlasWelcomeProjects.Pills(Entry(mSummary)))), 'fehlerfreie Prüfung ohne Marke');
end;

procedure TAtlasWelcomeProjectsTests.ChangesSyncAndRules;
var
  mSummary: TAtlasProjectSummary;
  mPills: TArray<TAtlasProjectPill>;
begin
  mSummary := OnMain;
  mSummary.Vcs.Changed := 4;
  mSummary.Vcs.Ahead := 2;
  mSummary.Vcs.Behind := -1;
  mSummary.Rules.Known := True;
  mSummary.Rules.NewHits := 3;
  mPills := TAtlasWelcomeProjects.Pills(Entry(mSummary));
  Assert.AreEqual(3, Integer(Length(mPills)), 'ohne Build keine Build-Marke');
  Assert.AreEqual<TAtlasProjectPillKind>(TAtlasProjectPillKind.Changes, mPills[0].Kind);
  Assert.AreEqual(4, mPills[0].A);
  Assert.AreEqual<TAtlasProjectPillLevel>(TAtlasProjectPillLevel.Warning, mPills[0].Level);
  Assert.AreEqual<TAtlasProjectPillKind>(TAtlasProjectPillKind.Sync, mPills[1].Kind);
  Assert.AreEqual(2, mPills[1].A);
  Assert.AreEqual(0, mPills[1].B, 'unbekannt zählt als 0');
  Assert.AreEqual<TAtlasProjectPillLevel>(TAtlasProjectPillLevel.Neutral, mPills[1].Level);
  Assert.AreEqual<TAtlasProjectPillKind>(TAtlasProjectPillKind.Rules, mPills[2].Kind);
  Assert.AreEqual(3, mPills[2].A);
end;

procedure TAtlasWelcomeProjectsTests.NoVersionControlShowsNothing;
var
  mSummary: TAtlasProjectSummary;
  mItem: TAtlasProjectEntry;
begin
  // Akzeptanzkriterium: außerhalb einer Versionsverwaltung kein Branch und kein Fehler.
  mSummary := TAtlasProjectSummary.Create('C:\Ohne\Demo.dproj');
  mSummary.Vcs.Known := True;
  mSummary.Vcs.Kind := 'none';
  mItem := Entry(mSummary);
  Assert.AreEqual('', mItem.Branch);
  Assert.IsFalse(mItem.VcsStale, 'kein „Stand vom …“');
  Assert.AreEqual(0, Integer(Length(TAtlasWelcomeProjects.Pills(mItem))));
  Assert.AreEqual<TAtlasProjectPillLevel>(TAtlasProjectPillLevel.Neutral,
    TAtlasWelcomeProjects.Level(TAtlasWelcomeProjects.Pills(mItem)));
  // Gespeicherter Stand mit Arbeitskopie: bis zur frischen Abfrage „Stand vom …“.
  mItem := Entry(OnMain);
  Assert.IsTrue(mItem.VcsStale);
  mItem.VcsFresh := True;
  Assert.IsFalse(mItem.VcsStale);
end;

procedure TAtlasWelcomeProjectsTests.DetachedHeadShowsCommit;
var
  mSummary: TAtlasProjectSummary;
begin
  mSummary := OnMain;
  mSummary.Vcs.Branch := '';
  Assert.AreEqual('abcdef0', Entry(mSummary).Branch);
  mSummary.Vcs.Kind := 'svn';
  mSummary.Vcs.Branch := 'trunk';
  Assert.AreEqual('trunk', Entry(mSummary).Branch);
end;

procedure TAtlasWelcomeProjectsTests.ShortensLongPaths;
var
  mShort: string;
begin
  Assert.AreEqual('C:\P\Demo.dproj', TAtlasWelcomeProjects.ShortPath('C:\P\Demo.dproj', 40));
  mShort := TAtlasWelcomeProjects.ShortPath('C:\Users\marco\Documents\Embarcadero\Studio\Projekte\Atlas\Demo.dproj', 40);
  Assert.AreEqual('C:\'#$2026'\Studio\Projekte\Atlas\Demo.dproj', mShort);
  Assert.IsTrue(Length(mShort) <= 40);
  mShort := TAtlasWelcomeProjects.ShortPath('C:\Ordner\EinSehrLangerProjektnameDerNichtPasst.dproj', 20);
  Assert.AreEqual(20, Integer(Length(mShort)), 'nur das Ende des Namens');
  Assert.AreEqual(#$2026, Copy(mShort, 1, 1));
end;

procedure TAtlasWelcomeProjectsTests.SettingsDefaultsAndLimits;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.WelcomePageProjectStatus);
  Assert.AreEqual(TAtlasWelcomeProjects.cDefaultMax, mSettings.WelcomePageMaxProjects);
  Assert.IsTrue(mSettings.WelcomePageRefreshVcs);
  mSettings.WelcomePageMaxProjects := 0;
  mSettings.Normalize;
  Assert.AreEqual(TAtlasWelcomeProjects.cMinMax, mSettings.WelcomePageMaxProjects);
  mSettings.WelcomePageMaxProjects := 500;
  mSettings.Normalize;
  Assert.AreEqual(TAtlasWelcomeProjects.cMaxMax, mSettings.WelcomePageMaxProjects);
end;

procedure TAtlasWelcomeProjectsTests.OpensWhenLastProjectClosed;
begin
  Assert.IsTrue(TAtlasWelcomeAutoOpen.AfterProjectClosed(True, True, 0, True, False));
end;

procedure TAtlasWelcomeProjectsTests.StaysClosedWhileProjectsRemain;
begin
  // Noch ein Projekt der Gruppe offen, oder die Zahl ist unbekannt.
  Assert.IsFalse(TAtlasWelcomeAutoOpen.AfterProjectClosed(True, True, 1, True, False));
  Assert.IsFalse(TAtlasWelcomeAutoOpen.AfterProjectClosed(True, True, -1, True, False));
  // Schon sichtbar: nicht noch einmal nach vorn holen.
  Assert.IsFalse(TAtlasWelcomeAutoOpen.AfterProjectClosed(True, True, 0, True, True));
end;

procedure TAtlasWelcomeProjectsTests.StaysClosedWhenSwitchedOff;
begin
  Assert.IsFalse(TAtlasWelcomeAutoOpen.AfterProjectClosed(False, True, 0, True, False), 'welcomePage.enabled aus');
  Assert.IsFalse(TAtlasWelcomeAutoOpen.AfterProjectClosed(True, False, 0, True, False),
    'welcomePage.openWhenNoProject aus');
end;

procedure TAtlasWelcomeProjectsTests.StaysClosedWhenIdeEnds;
begin
  // Beim Beenden schließt die IDE alle Projekte; dann kein Fenster mehr öffnen.
  Assert.IsFalse(TAtlasWelcomeAutoOpen.AfterProjectClosed(True, True, 0, False, False));
end;

procedure TAtlasWelcomeProjectsTests.OpenWhenNoProjectDefaultsOn;
var
  mStore: IAtlasSettingsStore;
  mSettings: TAtlasPluginSettings;
begin
  Assert.IsTrue(TAtlasPluginSettings.Defaults.WelcomePageOpenWhenNoProject);
  mStore := TAtlasMemorySettingsStore.Create;
  mSettings := TAtlasPluginSettings.Defaults;
  mSettings.WelcomePageOpenWhenNoProject := False;
  mSettings.Save(mStore);
  Assert.AreEqual(0, mStore.ReadInteger('WelcomePageOpenWhenNoProject', 1), 'Registry-Name');
  mSettings := TAtlasPluginSettings.Defaults;
  mSettings.Load(mStore);
  Assert.IsFalse(mSettings.WelcomePageOpenWhenNoProject);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasWelcomeProjectsTests);

end.
