unit Atlas.Core.Build.OpenBuild.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Build')]
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
    /// <summary>Schlüssel und Projektdateien; Namen und Werte der Einstellungen testet
    /// Atlas.Core.Build.OpenBuildSettings.Tests.</summary>
    [Test]
    procedure KeysAndProjectFiles;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Build.OpenBuild;

procedure TAtlasOpenBuildTests.WaitsForQuietIde;
var
  mBuild: TAtlasOpenBuild;
begin
  mBuild := TAtlasOpenBuild.Create;
  try
    Assert.IsFalse(mBuild.Due(10000, 3000, 10000, False), 'nichts vorgemerkt');
    mBuild.Opened('C:\P\Gruppe.groupproj', 1000);
    mBuild.Opened('C:\P\Unit1.pas', 1000);
    Assert.IsFalse(mBuild.Due(3999, 3000, 10000, False), 'zu früh nach dem Öffnen');
    Assert.IsTrue(mBuild.Due(4000, 3000, 10000, False));
    Assert.IsFalse(mBuild.Due(4000, 3000, 2999, False), 'der Benutzer tippt noch');
    // Ein weiteres Projekt verschiebt den Lauf.
    mBuild.Opened('C:\P\App.dproj', 3500);
    Assert.IsFalse(mBuild.Due(4000, 3000, 10000, False));
    Assert.IsTrue(mBuild.Due(6500, 3000, 10000, False));
    Assert.AreEqual(2, Integer(Length(mBuild.Take)), 'Units zählen nicht');
    Assert.IsFalse(mBuild.Due(10000, 3000, 10000, False), 'Take leert die Vormerkung');
  finally
    mBuild.Free;
  end;
end;

procedure TAtlasOpenBuildTests.WaitsForBuildDebuggerAndOwnRun;
var
  mBuild: TAtlasOpenBuild;
begin
  mBuild := TAtlasOpenBuild.Create;
  try
    mBuild.Opened('C:\P\App.dproj', 0);
    Assert.IsFalse(mBuild.Due(5000, 3000, 5000, True), 'Debugger läuft');
    mBuild.BuildStarted;
    Assert.IsFalse(mBuild.Due(5000, 3000, 5000, False), 'Build des Benutzers läuft');
    mBuild.BuildFinished;
    Assert.IsTrue(mBuild.Due(5000, 3000, 5000, False));
    mBuild.RunStarted(['C:\P\Lib.dproj'], 5000);
    Assert.IsFalse(mBuild.Due(5000, 3000, 5000, False), 'eigener Lauf');
    mBuild.RunFinished;
    Assert.IsTrue(mBuild.Due(5000, 3000, 5000, False), 'Vormerkung bleibt');
  finally
    mBuild.Free;
  end;
end;

procedure TAtlasOpenBuildTests.SelectsEachProjectOncePerOpening;
var
  mBuild: TAtlasOpenBuild;
  mSelected: TArray<string>;
begin
  mBuild := TAtlasOpenBuild.Create;
  try
    mSelected := mBuild.Select(['C:\P\Lib.dproj', 'C:\P\App.dproj', 'C:\P\App.dpr', 'C:\P\Atlas.IDE.Expert.dproj'],
      ['atlas.ide.expert']);
    Assert.AreEqual(2, Integer(Length(mSelected)), 'App einmal, Package ausgeschlossen');
    Assert.AreEqual('C:\P\Lib.dproj', mSelected[0], 'Reihenfolge der Gruppe');
    Assert.AreEqual('C:\P\App.dproj', mSelected[1]);
    // Ein weiteres Projekt in der Gruppe: nur dieses.
    mSelected := mBuild.Select(['C:\P\Lib.dproj', 'C:\P\App.dproj', 'c:\p\NEU.dproj'], nil);
    Assert.AreEqual(1, Integer(Length(mSelected)));
    Assert.AreEqual('c:\p\NEU.dproj', mSelected[0]);
    // Ausgeschlossen bleibt bis zum Schließen ausgelassen, auch ohne Ausschluss.
    Assert.AreEqual(0, Integer(Length(mBuild.Select(['C:\P\Atlas.IDE.Expert.dproj'], nil))));
    // Geschlossen und wieder geöffnet: wieder bauen.
    mBuild.Closed('C:\P\App.dproj');
    mSelected := mBuild.Select(['C:\P\Lib.dproj', 'C:\P\App.dproj'], nil);
    Assert.AreEqual(1, Integer(Length(mSelected)));
    Assert.AreEqual('C:\P\App.dproj', mSelected[0]);
  finally
    mBuild.Free;
  end;
end;

procedure TAtlasOpenBuildTests.RetriesUnresolvedFiles;
var
  mBuild: TAtlasOpenBuild;
  mAttempt: Integer;
  mTaken: TArray<string>;
begin
  mBuild := TAtlasOpenBuild.Create;
  try
    mBuild.Opened('C:\P\Gruppe.groupproj', 0);
    mBuild.Take;
    Assert.IsTrue(mBuild.Retry('C:\P\Gruppe.groupproj', 4000));
    Assert.IsFalse(mBuild.Due(6000, 3000, 10000, False), 'Wartezeit ab dem erneuten Vormerken');
    Assert.IsTrue(mBuild.Due(7000, 3000, 10000, False));
    mTaken := mBuild.Take;
    Assert.AreEqual(1, Integer(Length(mTaken)));
    Assert.AreEqual('C:\P\Gruppe.groupproj', mTaken[0]);
    for mAttempt := 2 to TAtlasOpenBuild.cMaxAttempts - 1 do
    begin
      Assert.IsTrue(mBuild.Retry('C:\P\Gruppe.groupproj', 0), Format('Versuch %d', [mAttempt]));
      mBuild.Take;
    end;
    Assert.IsFalse(mBuild.Retry('C:\P\Gruppe.groupproj', 0), 'nach MaxAttempts aufgeben');
    Assert.AreEqual(0, Integer(Length(mBuild.Take)));
    // Erneutes Öffnen setzt die Versuche zurück.
    mBuild.Opened('C:\P\Gruppe.groupproj', 0);
    mBuild.Take;
    Assert.IsTrue(mBuild.Retry('C:\P\Gruppe.groupproj', 0));
  finally
    mBuild.Free;
  end;
end;

procedure TAtlasOpenBuildTests.CountsRunResult;
var
  mBuild: TAtlasOpenBuild;
  mOutcome: TAtlasOpenBuildResult;
begin
  mBuild := TAtlasOpenBuild.Create;
  try
    mBuild.RunStarted(['C:\P\Lib.dproj', 'C:\P\App.dproj', 'C:\P\Tests.dproj'], 0);
    Assert.IsTrue(mBuild.Running);
    Assert.IsTrue(mBuild.InRun('c:\p\app.dpr'), '.dpr und .dproj sind dasselbe Projekt');
    Assert.IsFalse(mBuild.InRun('C:\P\Fremd.dproj'));
    mBuild.ProjectFinished('C:\P\Lib.dproj', True);
    mBuild.ProjectFinished('C:\P\Fremd.dproj', False);
    Assert.IsFalse(mBuild.RunComplete);
    mBuild.ProjectFinished('C:\P\App.dproj', False);
    mBuild.ProjectCancelled('C:\P\Tests.dproj', 'Release-Wächter');
    Assert.IsFalse(mBuild.RunComplete, 'abgebrochen hat kein Ergebnis');
    Assert.IsFalse(mBuild.RunOverdue(TAtlasOpenBuild.cMaxRunMs));
    Assert.IsTrue(mBuild.RunOverdue(TAtlasOpenBuild.cMaxRunMs + 1));
    mOutcome := mBuild.RunFinished;
    Assert.IsFalse(mBuild.Running);
    Assert.AreEqual(3, mOutcome.Total);
    Assert.AreEqual(1, mOutcome.Succeeded);
    Assert.AreEqual(1, mOutcome.Failed);
    Assert.AreEqual(1, mOutcome.NotBuilt);
    Assert.AreEqual('App', mOutcome.FailedNames[0]);
    Assert.AreEqual('Tests', mOutcome.NotBuiltNames[0]);
    Assert.AreEqual('Release-Wächter', mOutcome.CancelReason);
    Assert.IsFalse(mOutcome.AllSucceeded);
    mBuild.RunStarted(['C:\P\Lib.dproj'], 0);
    mBuild.ProjectFinished('C:\P\Lib.dproj', True);
    Assert.IsTrue(mBuild.RunComplete);
    mOutcome := mBuild.RunFinished;
    Assert.IsTrue(mOutcome.AllSucceeded);
    Assert.AreEqual('', mOutcome.CancelReason);
  finally
    mBuild.Free;
  end;
end;

procedure TAtlasOpenBuildTests.KeysAndProjectFiles;
begin
  Assert.AreEqual('c:\p\app', TAtlasOpenBuild.KeyOf(' C:\P\App.dproj '));
  Assert.AreEqual(TAtlasOpenBuild.KeyOf('C:\P\App.dpr'), TAtlasOpenBuild.KeyOf('c:\p\APP.DPROJ'));
  Assert.IsTrue(TAtlasOpenBuild.IsGroupFile('C:\P\Atlas.GROUPPROJ'));
  Assert.IsFalse(TAtlasOpenBuild.IsGroupFile('C:\P\App.dproj'));
  Assert.IsTrue(TAtlasOpenBuild.IsProjectFile('C:\P\Pkg.dpk'));
  Assert.IsFalse(TAtlasOpenBuild.IsProjectFile('C:\P\Unit1.pas'));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasOpenBuildTests);

end.
