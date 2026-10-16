unit Atlas.Core.Build.OpenBuild.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasOpenBuildTests = class
  public
    /// <summary>Fällig erst nach der Wartezeit seit dem letzten Öffnen und der letzten Eingabe.</summary>
    [Test]
    procedure WaitsForQuietIde;
    /// <summary>Nicht während eines Builds des Benutzers, im Debugger oder im eigenen Lauf; Vormerkung bleibt.
    /// </summary>
    [Test]
    procedure WaitsForBuildDebuggerAndOwnRun;
    /// <summary>Einmal je Öffnen: schon gebaute, doppelte und ausgeschlossene Projekte fallen weg; Schließen gibt
    /// frei.</summary>
    [Test]
    procedure SelectsEachProjectOncePerOpening;
    /// <summary>Noch nicht geladene Dateien werden bis MaxAttempts erneut vorgemerkt.</summary>
    [Test]
    procedure RetriesUnresolvedFiles;
    /// <summary>Ergebnis des Laufs: erfolgreich, fehlgeschlagen, nicht gebaut (Abbruch mit Grund).</summary>
    [Test]
    procedure CountsRunResult;
    /// <summary>Namen, Schlüssel, Art, Umfang und Ausschlussliste.</summary>
    [Test]
    procedure NamesAndSettingsValues;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Build.Events,
  Atlas.Core.Build.OpenBuild;

procedure TAtlasOpenBuildTests.WaitsForQuietIde;
var
  Build: TAtlasOpenBuild;
begin
  Build := TAtlasOpenBuild.Create;
  try
    Assert.IsFalse(Build.Due(10000, 3000, 10000, False), 'nichts vorgemerkt');
    Build.Opened('C:\P\Gruppe.groupproj', 1000);
    Build.Opened('C:\P\Unit1.pas', 1000);
    Assert.IsFalse(Build.Due(3999, 3000, 10000, False), 'zu früh nach dem Öffnen');
    Assert.IsTrue(Build.Due(4000, 3000, 10000, False));
    Assert.IsFalse(Build.Due(4000, 3000, 2999, False), 'der Benutzer tippt noch');
    // Ein weiteres Projekt verschiebt den Lauf.
    Build.Opened('C:\P\App.dproj', 3500);
    Assert.IsFalse(Build.Due(4000, 3000, 10000, False));
    Assert.IsTrue(Build.Due(6500, 3000, 10000, False));
    Assert.AreEqual(2, Integer(Length(Build.Take)), 'Units zählen nicht');
    Assert.IsFalse(Build.Due(10000, 3000, 10000, False), 'Take leert die Vormerkung');
  finally
    Build.Free;
  end;
end;

procedure TAtlasOpenBuildTests.WaitsForBuildDebuggerAndOwnRun;
var
  Build: TAtlasOpenBuild;
begin
  Build := TAtlasOpenBuild.Create;
  try
    Build.Opened('C:\P\App.dproj', 0);
    Assert.IsFalse(Build.Due(5000, 3000, 5000, True), 'Debugger läuft');
    Build.BuildStarted;
    Assert.IsFalse(Build.Due(5000, 3000, 5000, False), 'Build des Benutzers läuft');
    Build.BuildFinished;
    Assert.IsTrue(Build.Due(5000, 3000, 5000, False));
    Build.RunStarted(['C:\P\Lib.dproj'], 5000);
    Assert.IsFalse(Build.Due(5000, 3000, 5000, False), 'eigener Lauf');
    Build.RunFinished;
    Assert.IsTrue(Build.Due(5000, 3000, 5000, False), 'Vormerkung bleibt');
  finally
    Build.Free;
  end;
end;

procedure TAtlasOpenBuildTests.SelectsEachProjectOncePerOpening;
var
  Build: TAtlasOpenBuild;
  Selected: TArray<string>;
begin
  Build := TAtlasOpenBuild.Create;
  try
    Selected := Build.Select(['C:\P\Lib.dproj', 'C:\P\App.dproj', 'C:\P\App.dpr', 'C:\P\Atlas.IDE.Expert.dproj'],
      ['atlas.ide.expert']);
    Assert.AreEqual(2, Integer(Length(Selected)), 'App einmal, Package ausgeschlossen');
    Assert.AreEqual('C:\P\Lib.dproj', Selected[0], 'Reihenfolge der Gruppe');
    Assert.AreEqual('C:\P\App.dproj', Selected[1]);
    // Ein weiteres Projekt in der Gruppe: nur dieses.
    Selected := Build.Select(['C:\P\Lib.dproj', 'C:\P\App.dproj', 'c:\p\NEU.dproj'], nil);
    Assert.AreEqual(1, Integer(Length(Selected)));
    Assert.AreEqual('c:\p\NEU.dproj', Selected[0]);
    // Ausgeschlossen bleibt bis zum Schließen ausgelassen, auch ohne Ausschluss.
    Assert.AreEqual(0, Integer(Length(Build.Select(['C:\P\Atlas.IDE.Expert.dproj'], nil))));
    // Geschlossen und wieder geöffnet: wieder bauen.
    Build.Closed('C:\P\App.dproj');
    Selected := Build.Select(['C:\P\Lib.dproj', 'C:\P\App.dproj'], nil);
    Assert.AreEqual(1, Integer(Length(Selected)));
    Assert.AreEqual('C:\P\App.dproj', Selected[0]);
  finally
    Build.Free;
  end;
end;

procedure TAtlasOpenBuildTests.RetriesUnresolvedFiles;
var
  Build: TAtlasOpenBuild;
  Attempt: Integer;
  Taken: TArray<string>;
begin
  Build := TAtlasOpenBuild.Create;
  try
    Build.Opened('C:\P\Gruppe.groupproj', 0);
    Build.Take;
    Assert.IsTrue(Build.Retry('C:\P\Gruppe.groupproj', 4000));
    Assert.IsFalse(Build.Due(6000, 3000, 10000, False), 'Wartezeit ab dem erneuten Vormerken');
    Assert.IsTrue(Build.Due(7000, 3000, 10000, False));
    Taken := Build.Take;
    Assert.AreEqual(1, Integer(Length(Taken)));
    Assert.AreEqual('C:\P\Gruppe.groupproj', Taken[0]);
    for Attempt := 2 to TAtlasOpenBuild.MaxAttempts - 1 do
    begin
      Assert.IsTrue(Build.Retry('C:\P\Gruppe.groupproj', 0), Format('Versuch %d', [Attempt]));
      Build.Take;
    end;
    Assert.IsFalse(Build.Retry('C:\P\Gruppe.groupproj', 0), 'nach MaxAttempts aufgeben');
    Assert.AreEqual(0, Integer(Length(Build.Take)));
    // Erneutes Öffnen setzt die Versuche zurück.
    Build.Opened('C:\P\Gruppe.groupproj', 0);
    Build.Take;
    Assert.IsTrue(Build.Retry('C:\P\Gruppe.groupproj', 0));
  finally
    Build.Free;
  end;
end;

procedure TAtlasOpenBuildTests.CountsRunResult;
var
  Build: TAtlasOpenBuild;
  Outcome: TAtlasOpenBuildResult;
begin
  Build := TAtlasOpenBuild.Create;
  try
    Build.RunStarted(['C:\P\Lib.dproj', 'C:\P\App.dproj', 'C:\P\Tests.dproj'], 0);
    Assert.IsTrue(Build.Running);
    Assert.IsTrue(Build.InRun('c:\p\app.dpr'), '.dpr und .dproj sind dasselbe Projekt');
    Assert.IsFalse(Build.InRun('C:\P\Fremd.dproj'));
    Build.ProjectFinished('C:\P\Lib.dproj', True);
    Build.ProjectFinished('C:\P\Fremd.dproj', False);
    Assert.IsFalse(Build.RunComplete);
    Build.ProjectFinished('C:\P\App.dproj', False);
    Build.ProjectCancelled('C:\P\Tests.dproj', 'Release-Wächter');
    Assert.IsFalse(Build.RunComplete, 'abgebrochen hat kein Ergebnis');
    Assert.IsFalse(Build.RunOverdue(TAtlasOpenBuild.MaxRunMs));
    Assert.IsTrue(Build.RunOverdue(TAtlasOpenBuild.MaxRunMs + 1));
    Outcome := Build.RunFinished;
    Assert.IsFalse(Build.Running);
    Assert.AreEqual(3, Outcome.Total);
    Assert.AreEqual(1, Outcome.Succeeded);
    Assert.AreEqual(1, Outcome.Failed);
    Assert.AreEqual(1, Outcome.NotBuilt);
    Assert.AreEqual('App', Outcome.FailedNames[0]);
    Assert.AreEqual('Tests', Outcome.NotBuiltNames[0]);
    Assert.AreEqual('Release-Wächter', Outcome.CancelReason);
    Assert.IsFalse(Outcome.AllSucceeded);
    Build.RunStarted(['C:\P\Lib.dproj'], 0);
    Build.ProjectFinished('C:\P\Lib.dproj', True);
    Assert.IsTrue(Build.RunComplete);
    Outcome := Build.RunFinished;
    Assert.IsTrue(Outcome.AllSucceeded);
    Assert.AreEqual('', Outcome.CancelReason);
  finally
    Build.Free;
  end;
end;

procedure TAtlasOpenBuildTests.NamesAndSettingsValues;
var
  Exclude: TArray<string>;
begin
  Assert.AreEqual('Atlas.IDE.Expert', TAtlasOpenBuild.NameOf('C:\P\Atlas.IDE.Expert.dproj'));
  Assert.AreEqual('App', TAtlasOpenBuild.NameOf('/home/p/App.dpr'));
  Assert.AreEqual('Atlas.Text', TAtlasOpenBuild.NameOf('Atlas.Text'), 'Punkte im Namen bleiben');
  Assert.AreEqual('c:\p\app', TAtlasOpenBuild.KeyOf(' C:\P\App.dproj '));
  Assert.AreEqual(TAtlasOpenBuild.KeyOf('C:\P\App.dpr'), TAtlasOpenBuild.KeyOf('c:\p\APP.DPROJ'));
  Assert.IsTrue(TAtlasOpenBuild.IsGroupFile('C:\P\Atlas.GROUPPROJ'));
  Assert.IsFalse(TAtlasOpenBuild.IsGroupFile('C:\P\App.dproj'));
  Assert.IsTrue(TAtlasOpenBuild.IsProjectFile('C:\P\Pkg.dpk'));
  Assert.IsFalse(TAtlasOpenBuild.IsProjectFile('C:\P\Unit1.pas'));
  Assert.AreEqual(Ord(TAtlasCompileKind.Check), Ord(TAtlasOpenBuild.KindOf(' Check ')));
  Assert.AreEqual(Ord(TAtlasCompileKind.Build), Ord(TAtlasOpenBuild.KindOf('build')));
  Assert.AreEqual(Ord(TAtlasCompileKind.Make), Ord(TAtlasOpenBuild.KindOf('quatsch')));
  Assert.AreEqual('make', TAtlasOpenBuild.KindName(TAtlasCompileKind.Clean), 'nur check, make, build');
  Assert.AreEqual(Ord(TAtlasOpenBuildScope.Active), Ord(TAtlasOpenBuild.ScopeOf('ACTIVE')));
  Assert.AreEqual(Ord(TAtlasOpenBuildScope.All), Ord(TAtlasOpenBuild.ScopeOf('')));
  Exclude := TAtlasOpenBuild.ParseExclude('Atlas.IDE.Expert.dpk;  Demo' + #13#10 + 'demo, ,');
  Assert.AreEqual(2, Integer(Length(Exclude)));
  Assert.AreEqual('Atlas.IDE.Expert', Exclude[0]);
  Assert.AreEqual('Demo', Exclude[1]);
  Assert.AreEqual('Atlas.IDE.Expert, Demo', TAtlasOpenBuild.NormalizedExclude('Atlas.IDE.Expert.dpk;Demo;demo'));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasOpenBuildTests);

end.
