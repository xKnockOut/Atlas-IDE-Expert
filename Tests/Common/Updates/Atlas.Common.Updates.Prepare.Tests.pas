unit Atlas.Common.Updates.Prepare.Tests;

// Tests der Vorbereitung eines Updates (#1519, Befehl prepare): Paket der
// IDE laden und prüfen, Bau aus dem Quelltext für Delphi 12, Signaturen und
// Fehler mit Kennung in state.json.

interface

uses
  DUnitX.TestFramework,
  Atlas.Text.UpdateRun,
  Atlas.Tests.UpdateFakes;

type
  [TestFixture]
  TCommonUpdatesPrepareTests = class
  private
    FFake: TFakeUpdateSystem;
    function Args(const AIde: string): TUpdateArguments;
    procedure Release(const APackageSha: string);
    function Prepare(const AIde: string): TUpdateStage;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure PreparesPackageOfIde;
    [Test]
    procedure RejectsWrongHash;
    [Test]
    procedure RejectsChangedVersion;
    [Test]
    procedure BuildsFromSourceForDelphi12;
    [Test]
    procedure NeedsCompilerForSource;
    [Test]
    procedure ReportsFailedBuild;
    [Test]
    procedure RequiresSameSignerWhenSigned;
    [Test]
    procedure AcceptsSignedPackage;
    [Test]
    procedure SkipsNewModulesOnRequest;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Updates.Prepare;

const
  cManifestUrl = 'https://example.org/atlas-version.json';
  cStaging = 'C:\Local\Atlas\Updates\2.0.1';
  cTarget = 'C:\Atlas';
  cKey = 'Software\Embarcadero\BDS\37.0';
  cUpdater = 'C:\Atlas\AtlasUpdate.exe';

procedure TCommonUpdatesPrepareTests.Setup;
begin
  FFake := TFakeUpdateSystem.Create;
end;

procedure TCommonUpdatesPrepareTests.TearDown;
begin
  FreeAndNil(FFake);
end;

function TCommonUpdatesPrepareTests.Args(const AIde: string): TUpdateArguments;
begin
  Result := Default(TUpdateArguments);
  Result.Command := 'prepare';
  Result.ManifestUrl := cManifestUrl;
  Result.Version := '2.0.1';
  Result.Previous := '2.0.0';
  Result.Ide := AIde;
  Result.Platform := 'Win32';
  Result.RegistryKey := cKey;
  Result.Target := cTarget;
  Result.Staging := cStaging;
  Result.NewModules := TUpdateNewModules.Ask;
end;

procedure TCommonUpdatesPrepareTests.Release(const APackageSha: string);
begin
  FFake.Archive.Add('pkg', 'AtlasServer.exe', 'server 2.0.1');
  FFake.Archive.Add('pkg', 'AtlasUpdate.exe', 'update 2.0.1');
  FFake.Archive.Add('pkg', 'Win32/Atlas.IDE.Base370.bpl', 'base 2.0.1');
  FFake.Archive.Add('pkg', 'Win32/Atlas.IDE.Base370.map', 'map');
  FFake.Archive.Add('pkg', 'Win32/Atlas.IDE.Debugger370.bpl', 'debugger 2.0.1');
  FFake.Archive.Add('pkg', 'Win32/Atlas.IDE.Search370.bpl', 'search 2.0.1');
  FFake.Archive.Add('src', 'Packages/Atlas.IDE.Base/Atlas.IDE.Base.dproj', '');
  FFake.Archive.Add('src', 'Packages/Atlas.IDE.Debugger/Atlas.IDE.Debugger.dproj', '');
  FFake.Network.Serve('https://example.org/pkg.zip', 'pkg');
  FFake.Network.Serve('https://example.org/src.zip', 'src');
  FFake.Network.Serve(cManifestUrl, '{"version": "2.0.1", "packages": {"37.0": {"url": "https://example.org/pkg.zip",' +
    ' "sha256": "' + APackageSha + '"}}, "source": {"url": "https://example.org/src.zip", "sha256": "' +
    TFakeTrust.HashOf('src') + '"}}');
  // Installiert: 2.0.0 mit Kern und Debugger.
  FFake.Files.WriteText(cTarget + '\Win32\Atlas.IDE.Base370.bpl', 'base 2.0.0');
  FFake.Files.WriteText(cTarget + '\Win32\Atlas.IDE.Debugger370.bpl', 'debugger 2.0.0');
  FFake.Registry.WriteValue(cKey + '\Known Packages', cTarget + '\Win32\Atlas.IDE.Base370.bpl', 'Atlas Base');
  FFake.Registry.WriteValue(cKey + '\Known Packages', cTarget + '\Win32\Atlas.IDE.Debugger370.bpl', 'Atlas Debugger');
end;

function TCommonUpdatesPrepareTests.Prepare(const AIde: string): TUpdateStage;
var
  mPreparation: TUpdatePreparation;
begin
  mPreparation := TUpdatePreparation.Create(FFake.System, Args(AIde), cUpdater);
  try
    mPreparation.Run;
  finally
    mPreparation.Free;
  end;
  Result := TUpdateStage.FromJson(FFake.Files.ReadText(cStaging + '\state.json'));
end;

procedure TCommonUpdatesPrepareTests.PreparesPackageOfIde;
var
  mStage: TUpdateStage;
begin
  Release(TFakeTrust.HashOf('pkg'));
  mStage := Prepare('37.0');
  Assert.IsTrue(mStage.Phase = TUpdatePhase.Ready, mStage.Error + ' ' + mStage.Detail);
  Assert.AreEqual('2.0.1', mStage.Version);
  Assert.AreEqual('2.0.0', mStage.Previous);
  Assert.IsFalse(mStage.FromSource);
  Assert.AreEqual(cStaging + '\files\AtlasUpdate.exe', mStage.Updater);
  Assert.AreEqual('base 2.0.1', FFake.Files.ReadText(cStaging + '\files\Win32\Atlas.IDE.Base370.bpl'));
  Assert.AreEqual(3, Integer(Length(mStage.Candidates)));
  Assert.AreEqual('Atlas.IDE.Search', mStage.Candidates[2].Name);
  Assert.IsTrue(mStage.Candidates[2].IsNew);
  Assert.IsTrue(mStage.AskSelection);
  // Der Download wird nicht mehr gebraucht; der Atlas-Ordner ist unverändert.
  Assert.IsFalse(FFake.Files.DirectoryExists(cStaging + '\download'));
  Assert.AreEqual('base 2.0.0', FFake.Files.ReadText(cTarget + '\Win32\Atlas.IDE.Base370.bpl'));
end;

procedure TCommonUpdatesPrepareTests.RejectsWrongHash;
var
  mStage: TUpdateStage;
begin
  Release(TFakeTrust.HashOf('anders'));
  mStage := Prepare('37.0');
  Assert.IsTrue(mStage.Phase = TUpdatePhase.Failed);
  Assert.AreEqual(TUpdateErrors.cHash, mStage.Error);
  Assert.IsFalse(FFake.Files.FileExists(cStaging + '\files\AtlasServer.exe'));
end;

procedure TCommonUpdatesPrepareTests.RejectsChangedVersion;
var
  mStage: TUpdateStage;
begin
  Release(TFakeTrust.HashOf('pkg'));
  FFake.Network.Serve(cManifestUrl, '{"version": "2.0.2"}');
  mStage := Prepare('37.0');
  Assert.AreEqual(TUpdateErrors.cVersionChanged, mStage.Error);
  Assert.AreEqual('2.0.2', mStage.Detail);
end;

procedure TCommonUpdatesPrepareTests.BuildsFromSourceForDelphi12;
var
  mStage: TUpdateStage;
begin
  Release(TFakeTrust.HashOf('pkg'));
  mStage := Prepare('36.0');
  Assert.IsTrue(mStage.Phase = TUpdatePhase.Ready, mStage.Error + ' ' + mStage.Detail);
  Assert.IsTrue(mStage.FromSource);
  Assert.AreEqual('Atlas.IDE.Base,Atlas.IDE.Debugger', string.Join(',', FFake.Builder.Projects));
  // Die BPLs für Delphi 13 und ihre Maps sind ersetzt; Server und Daten kommen aus dem Paket.
  Assert.AreEqual('built Atlas.IDE.Base', FFake.Files.ReadText(cStaging + '\files\Win32\Atlas.IDE.Base290.bpl'));
  Assert.IsFalse(FFake.Files.FileExists(cStaging + '\files\Win32\Atlas.IDE.Base370.bpl'));
  Assert.IsFalse(FFake.Files.FileExists(cStaging + '\files\Win32\Atlas.IDE.Base370.map'));
  Assert.AreEqual('server 2.0.1', FFake.Files.ReadText(cStaging + '\files\AtlasServer.exe'));
end;

procedure TCommonUpdatesPrepareTests.NeedsCompilerForSource;
var
  mStage: TUpdateStage;
begin
  Release(TFakeTrust.HashOf('pkg'));
  FFake.Builder.Available := False;
  mStage := Prepare('36.0');
  Assert.AreEqual(TUpdateErrors.cNoCompiler, mStage.Error);
  Assert.AreEqual('dcc32 fehlt', mStage.Detail);
end;

procedure TCommonUpdatesPrepareTests.ReportsFailedBuild;
var
  mStage: TUpdateStage;
begin
  Release(TFakeTrust.HashOf('pkg'));
  FFake.Builder.FailOn := 'Atlas.IDE.Debugger';
  mStage := Prepare('36.0');
  Assert.AreEqual(TUpdateErrors.cBuild, mStage.Error);
  Assert.Contains(mStage.Detail, 'Atlas.IDE.Debugger.dproj');
  Assert.Contains(FFake.LogText, 'Erzeuge Atlas.IDE.Debugger');
end;

procedure TCommonUpdatesPrepareTests.RequiresSameSignerWhenSigned;
var
  mStage: TUpdateStage;
begin
  Release(TFakeTrust.HashOf('pkg'));
  FFake.Trust.Sign(cUpdater, 'Atlas');
  mStage := Prepare('37.0');
  Assert.AreEqual(TUpdateErrors.cUnsigned, mStage.Error);
  FFake.Trust.Sign(cStaging + '\files\AtlasServer.exe', 'Fremd');
  FFake.Trust.Sign(cStaging + '\files\AtlasUpdate.exe', 'Atlas');
  FFake.Trust.Sign(cStaging + '\files\Win32\Atlas.IDE.Base370.bpl', 'Atlas');
  FFake.Trust.Sign(cStaging + '\files\Win32\Atlas.IDE.Debugger370.bpl', 'Atlas');
  FFake.Trust.Sign(cStaging + '\files\Win32\Atlas.IDE.Search370.bpl', 'Atlas');
  mStage := Prepare('37.0');
  Assert.AreEqual(TUpdateErrors.cSignature, mStage.Error);
  Assert.AreEqual('AtlasServer.exe', mStage.Detail);
end;

procedure TCommonUpdatesPrepareTests.AcceptsSignedPackage;
var
  mStage: TUpdateStage;
begin
  Release(TFakeTrust.HashOf('pkg'));
  FFake.Trust.Sign(cUpdater, 'Atlas');
  FFake.Trust.Sign(cStaging + '\files\AtlasServer.exe', 'Atlas');
  FFake.Trust.Sign(cStaging + '\files\AtlasUpdate.exe', 'Atlas');
  FFake.Trust.Sign(cStaging + '\files\Win32\Atlas.IDE.Base370.bpl', 'Atlas');
  FFake.Trust.Sign(cStaging + '\files\Win32\Atlas.IDE.Debugger370.bpl', 'Atlas');
  FFake.Trust.Sign(cStaging + '\files\Win32\Atlas.IDE.Search370.bpl', 'Atlas');
  mStage := Prepare('37.0');
  Assert.IsTrue(mStage.Phase = TUpdatePhase.Ready, mStage.Error + ' ' + mStage.Detail);
end;

procedure TCommonUpdatesPrepareTests.SkipsNewModulesOnRequest;
var
  mStage: TUpdateStage;
  mArgs: TUpdateArguments;
  mPreparation: TUpdatePreparation;
begin
  Release(TFakeTrust.HashOf('pkg'));
  mArgs := Args('37.0');
  mArgs.NewModules := TUpdateNewModules.Skip;
  mPreparation := TUpdatePreparation.Create(FFake.System, mArgs, cUpdater);
  try
    Assert.AreEqual(0, mPreparation.Run);
    mStage := mPreparation.Stage;
  finally
    mPreparation.Free;
  end;
  Assert.IsFalse(mStage.AskSelection);
  Assert.AreEqual('Atlas.IDE.Base,Atlas.IDE.Debugger', string.Join(',', mStage.SelectedNames));
end;

end.
