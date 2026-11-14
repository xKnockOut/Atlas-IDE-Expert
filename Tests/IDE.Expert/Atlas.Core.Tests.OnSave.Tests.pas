unit Atlas.Core.Tests.OnSave.Tests;

// Tests der betroffenen Tests nach dem Speichern (#1775) ohne IDE: Warteschlange
// mit höchstens einem Folgelauf, Sperrgründe, Entscheidung nach dem Ermitteln
// und die Dateien, die zählen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tests')]
  TAtlasTestsOnSaveTests = class
  public
    [Test]
    procedure FirstSaveStartsARun;
    [Test]
    procedure SavesDuringARunGiveOneFollowUp;
    [Test]
    procedure SameFileWaitsOnce;
    [Test]
    procedure ClearDropsWaitingFiles;
    [Test]
    procedure OffByDefaultAndWithAffectedOff;
    [Test]
    procedure DebuggingBuildingAndBusyBlock;
    [Test]
    procedure VerdictByCountAndLimit;
    [Test]
    procedure OnlySourcesCount;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Tests.OnSave;

procedure TAtlasTestsOnSaveTests.FirstSaveStartsARun;
var
  mQueue: TAtlasTestsOnSaveQueue;
  mFiles: TArray<string>;
begin
  mQueue := TAtlasTestsOnSaveQueue.Create;
  try
    Assert.IsTrue(mQueue.Add('C:\Src\Kasse.pas'), 'kein Lauf im Gange: beginnen');
    mFiles := mQueue.Take;
    Assert.AreEqual(1, Integer(Length(mFiles)));
    Assert.AreEqual('C:\Src\Kasse.pas', mFiles[0]);
    Assert.IsTrue(mQueue.Active);
    Assert.IsFalse(mQueue.Finish, 'nichts wartet');
    Assert.IsFalse(mQueue.Active);
  finally
    mQueue.Free;
  end;
end;

procedure TAtlasTestsOnSaveTests.SavesDuringARunGiveOneFollowUp;
var
  mQueue: TAtlasTestsOnSaveQueue;
  mFiles: TArray<string>;
begin
  mQueue := TAtlasTestsOnSaveQueue.Create;
  try
    mQueue.Add('C:\Src\Kasse.pas');
    mQueue.Take;
    Assert.IsFalse(mQueue.Add('C:\Src\Lager.pas'), 'während des Laufs: warten');
    Assert.IsFalse(mQueue.Add('C:\Src\Kasse.pas'), 'auch dieselbe Datei wartet');
    Assert.IsTrue(mQueue.Finish, 'Folgelauf');
    mFiles := mQueue.Take;
    Assert.AreEqual(2, Integer(Length(mFiles)), 'ein Folgelauf mit allen bis dahin gespeicherten Dateien');
    Assert.AreEqual('C:\Src\Lager.pas', mFiles[0]);
    Assert.AreEqual('C:\Src\Kasse.pas', mFiles[1]);
    Assert.IsFalse(mQueue.Finish, 'danach kein weiterer');
  finally
    mQueue.Free;
  end;
end;

procedure TAtlasTestsOnSaveTests.SameFileWaitsOnce;
var
  mQueue: TAtlasTestsOnSaveQueue;
begin
  mQueue := TAtlasTestsOnSaveQueue.Create;
  try
    mQueue.Add('C:\Src\Kasse.pas');
    mQueue.Add('c:\src\KASSE.pas');
    Assert.AreEqual(1, Integer(Length(mQueue.Pending)));
  finally
    mQueue.Free;
  end;
end;

procedure TAtlasTestsOnSaveTests.ClearDropsWaitingFiles;
var
  mQueue: TAtlasTestsOnSaveQueue;
begin
  mQueue := TAtlasTestsOnSaveQueue.Create;
  try
    mQueue.Add('C:\Src\Kasse.pas');
    mQueue.Take;
    mQueue.Add('C:\Src\Lager.pas');
    mQueue.Clear;
    Assert.IsTrue(mQueue.Active, 'der laufende Lauf bleibt');
    Assert.IsFalse(mQueue.Finish, 'kein Folgelauf');
  finally
    mQueue.Free;
  end;
end;

procedure TAtlasTestsOnSaveTests.OffByDefaultAndWithAffectedOff;
var
  mSettings: TAtlasPluginSettings;
  mSituation: TAtlasOnSaveSituation;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  mSituation := Default(TAtlasOnSaveSituation);
  Assert.AreEqual<TAtlasOnSaveBlock>(TAtlasOnSaveBlock.Off,
    TAtlasTestsOnSave.Block(mSettings, mSituation), 'Vorgabe aus');
  mSettings.TestsOnSave := True;
  Assert.AreEqual<TAtlasOnSaveBlock>(TAtlasOnSaveBlock.None, TAtlasTestsOnSave.Block(mSettings, mSituation));
  mSettings.TestsAffected := False;
  Assert.AreEqual<TAtlasOnSaveBlock>(TAtlasOnSaveBlock.Off,
    TAtlasTestsOnSave.Block(mSettings, mSituation), 'tests.affected aus');
  mSettings.TestsAffected := True;
  mSettings.TestRun := False;
  Assert.AreEqual<TAtlasOnSaveBlock>(TAtlasOnSaveBlock.Off,
    TAtlasTestsOnSave.Block(mSettings, mSituation), 'tests.run aus');
end;

procedure TAtlasTestsOnSaveTests.DebuggingBuildingAndBusyBlock;
var
  mSettings: TAtlasPluginSettings;
  mSituation: TAtlasOnSaveSituation;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  mSettings.TestsOnSave := True;
  mSituation := Default(TAtlasOnSaveSituation);
  mSituation.TestsBusy := True;
  Assert.AreEqual<TAtlasOnSaveBlock>(TAtlasOnSaveBlock.TestsBusy, TAtlasTestsOnSave.Block(mSettings, mSituation));
  mSituation.Building := True;
  Assert.AreEqual<TAtlasOnSaveBlock>(TAtlasOnSaveBlock.Building, TAtlasTestsOnSave.Block(mSettings, mSituation));
  mSituation.Debugging := True;
  Assert.AreEqual<TAtlasOnSaveBlock>(TAtlasOnSaveBlock.Debugging,
    TAtlasTestsOnSave.Block(mSettings, mSituation), 'Debuggen zuerst');
end;

procedure TAtlasTestsOnSaveTests.VerdictByCountAndLimit;
begin
  Assert.AreEqual<TAtlasOnSaveVerdict>(TAtlasOnSaveVerdict.NoTests, TAtlasTestsOnSave.Verdict(0, False, 50));
  Assert.AreEqual<TAtlasOnSaveVerdict>(TAtlasOnSaveVerdict.Run, TAtlasTestsOnSave.Verdict(3, False, 50));
  Assert.AreEqual<TAtlasOnSaveVerdict>(TAtlasOnSaveVerdict.Run,
    TAtlasTestsOnSave.Verdict(50, False, 50), 'genau die Grenze');
  Assert.AreEqual<TAtlasOnSaveVerdict>(TAtlasOnSaveVerdict.TooMany, TAtlasTestsOnSave.Verdict(51, False, 50));
  Assert.AreEqual<TAtlasOnSaveVerdict>(TAtlasOnSaveVerdict.AllNeeded,
    TAtlasTestsOnSave.Verdict(0, True, 50), 'alle nötig: kein Lauf');
end;

procedure TAtlasTestsOnSaveTests.OnlySourcesCount;
begin
  Assert.IsTrue(TAtlasTestsOnSave.Counts('C:\Src\Kasse.pas'));
  Assert.IsTrue(TAtlasTestsOnSave.Counts('C:\Src\Kasse.DFM'));
  Assert.IsTrue(TAtlasTestsOnSave.Counts('C:\Src\Haupt.fmx'));
  Assert.IsTrue(TAtlasTestsOnSave.Counts('C:\Src\Version.inc'));
  Assert.IsFalse(TAtlasTestsOnSave.Counts('C:\Src\Kasse.dproj'), 'Projektdatei');
  Assert.IsFalse(TAtlasTestsOnSave.Counts('C:\Src\Liesmich.md'));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTestsOnSaveTests);

end.
