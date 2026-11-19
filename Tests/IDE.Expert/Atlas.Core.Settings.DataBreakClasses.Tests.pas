unit Atlas.Core.Settings.DataBreakClasses.Tests;

// Tests für die Liste der beobachteten Klassen (#870, debug.dataBreaks.classes): Vorgabe, Zerlegen, Arten,
// Normalisieren.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasDataBreakSettingsTests = class
  public
    [Test]
    procedure EntriesWithKinds;
    [Test]
    procedure NormalizeDropsDuplicatesAndUnknownKinds;
    [Test]
    procedure DefaultsOfDebugSettings;
  end;

implementation

uses
  Atlas.Core.Settings.DataBreakClasses,
  Atlas.Core.Settings.Plugin.Debug;

{ TAtlasDataBreakSettingsTests }

procedure TAtlasDataBreakSettingsTests.EntriesWithKinds;
var
  mEntries: TArray<TAtlasDataBreakClassEntry>;
begin
  mEntries := TAtlasDataBreakSettings.Entries(' TFDQuery ;TMeineAbfrage = SQL,'#13#10'TMeinClient=http, TX=ftp');
  Assert.AreEqual(4, Integer(Length(mEntries)));
  Assert.AreEqual('TFDQuery', mEntries[0].Name);
  Assert.AreEqual('', mEntries[0].Kind);
  Assert.AreEqual('TMeineAbfrage', mEntries[1].Name);
  Assert.AreEqual('sql', mEntries[1].Kind);
  Assert.AreEqual('http', mEntries[2].Kind);
  Assert.AreEqual('TX', mEntries[3].Name);
  Assert.AreEqual('', mEntries[3].Kind);
end;

procedure TAtlasDataBreakSettingsTests.NormalizeDropsDuplicatesAndUnknownKinds;
begin
  Assert.AreEqual('TFDQuery, TMeineAbfrage=sql',
    TAtlasDataBreakSettings.NormalizeClasses('TFDQuery,, tfdquery=http; TMeineAbfrage=Sql ; =sql'));
  Assert.AreEqual('', TAtlasDataBreakSettings.NormalizeClasses('  '));
  Assert.AreEqual(TAtlasDataBreakSettings.cDefaultClasses,
    TAtlasDataBreakSettings.NormalizeClasses(TAtlasDataBreakSettings.cDefaultClasses));
end;

procedure TAtlasDataBreakSettingsTests.DefaultsOfDebugSettings;
var
  mSettings: TAtlasPluginDebugSettings;
begin
  mSettings := TAtlasPluginDebugSettings.Defaults;
  Assert.IsTrue(mSettings.DebugDataBreaks);
  Assert.AreEqual(TAtlasDataBreakSettings.cDefaultClasses, mSettings.DebugDataBreaksClasses);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasDataBreakSettingsTests);

end.
