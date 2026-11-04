unit Atlas.Core.Settings.ProblemsUpdate.Tests;

// Tests für die Werte von problems.update und problems.liveDelayMs: Namen,
// Unbekanntes, Übernahme von problems.live und Grenzen der Verzögerung.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasProblemsUpdateSettingTests = class
  public
    [Test]
    procedure NamesRoundTrip;
    [Test]
    procedure UnknownValueIsLive;
    [Test]
    procedure FormerLiveMapsToLiveOrSave;
    [Test]
    procedure DelayIsClamped;
  end;

implementation

uses
  Atlas.Core.Settings.ProblemsUpdate;

procedure TAtlasProblemsUpdateSettingTests.NamesRoundTrip;
var
  mMode: TAtlasProblemsUpdate;
begin
  for mMode := Low(TAtlasProblemsUpdate) to High(TAtlasProblemsUpdate) do
  begin
    Assert.IsTrue(TAtlasProblemsUpdateSetting.Parse(TAtlasProblemsUpdateSetting.Name(mMode)) = mMode);
  end;
  Assert.AreEqual('live', TAtlasProblemsUpdateSetting.Name(TAtlasProblemsUpdate.Live));
  Assert.AreEqual('save', TAtlasProblemsUpdateSetting.Name(TAtlasProblemsUpdate.Save));
  Assert.AreEqual('manual', TAtlasProblemsUpdateSetting.Name(TAtlasProblemsUpdate.Manual));
end;

procedure TAtlasProblemsUpdateSettingTests.UnknownValueIsLive;
begin
  Assert.IsTrue(TAtlasProblemsUpdateSetting.Parse('') = TAtlasProblemsUpdate.Live);
  Assert.IsTrue(TAtlasProblemsUpdateSetting.Parse('manuell') = TAtlasProblemsUpdate.Live);
  Assert.IsTrue(TAtlasProblemsUpdateSetting.Parse(' MANUAL ') = TAtlasProblemsUpdate.Manual);
  Assert.AreEqual('save', TAtlasProblemsUpdateSetting.Normalize('Save'));
  Assert.AreEqual('live', TAtlasProblemsUpdateSetting.Normalize('unsinn'));
end;

procedure TAtlasProblemsUpdateSettingTests.FormerLiveMapsToLiveOrSave;
begin
  Assert.AreEqual('live', TAtlasProblemsUpdateSetting.FromLive(True));
  Assert.AreEqual('save', TAtlasProblemsUpdateSetting.FromLive(False));
end;

procedure TAtlasProblemsUpdateSettingTests.DelayIsClamped;
begin
  Assert.AreEqual(100, TAtlasProblemsUpdateSetting.ClampDelay(0));
  Assert.AreEqual(100, TAtlasProblemsUpdateSetting.ClampDelay(-5));
  Assert.AreEqual(400, TAtlasProblemsUpdateSetting.ClampDelay(400));
  Assert.AreEqual(10000, TAtlasProblemsUpdateSetting.ClampDelay(60000));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasProblemsUpdateSettingTests);

end.
