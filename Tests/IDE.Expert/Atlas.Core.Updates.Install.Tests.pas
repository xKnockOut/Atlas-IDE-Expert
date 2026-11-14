unit Atlas.Core.Updates.Install.Tests;

// Update installieren im Plugin (#1519) ohne Prozesse: Modus, Kanal, wann das
// Plugin nicht selbst installiert, Aufrufe von prepare und apply, Auswahl
// der Module.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasUpdateInstallTests = class
  public
    [Test]
    procedure ReadsInstallMode;
    [Test]
    procedure ChoosesChannel;
    [Test]
    procedure BlocksGetItAndForeignFolders;
    [Test]
    procedure PreparesWithoutAskingOnlyInAutoWithinMajor;
    [Test]
    procedure BuildsPrepareArguments;
    [Test]
    procedure BuildsApplyArgumentsFromSelection;
    [Test]
    procedure ChoiceKeepsRequiredPackages;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Text.Updates,
  Atlas.Text.UpdateRun,
  Atlas.Core.Updates.Install;

const
  cPluginDir = 'C:\Users\Ich\AppData\Local\Programs\Atlas\Win32\';
  cRoot = 'C:\Users\Ich\AppData\Local\Atlas\Updates';

function Environment: TAtlasUpdateEnvironment;
begin
  Result := Default(TAtlasUpdateEnvironment);
  Result.PluginDir := cPluginDir;
  Result.Platform := 'Win32';
  Result.Ide := '37.0';
  Result.RegistryKey := 'Software\Embarcadero\BDS\37.0';
  Result.Installed := '2.0.0';
  Result.UpdaterExists := True;
end;

function Candidate(const AName: string; ARequired, ASelected, AIsNew: Boolean): TUpdateCandidate;
begin
  Result := Default(TUpdateCandidate);
  Result.Name := AName;
  Result.Required := ARequired;
  Result.Selected := ASelected;
  Result.IsNew := AIsNew;
  Result.Installed := not AIsNew;
end;

function ReadyStage: TUpdateStage;
begin
  Result := Default(TUpdateStage);
  Result.Phase := TUpdatePhase.Ready;
  Result.Version := '2.1.0';
  Result.AskSelection := True;
  Result.Candidates := [Candidate('Atlas.IDE.Base', True, True, False),
    Candidate('Atlas.IDE.Debugger', False, True, False), Candidate('Atlas.IDE.Notes', False, False, True)];
end;

{ TAtlasUpdateInstallTests }

procedure TAtlasUpdateInstallTests.ReadsInstallMode;
begin
  Assert.AreEqual<TAtlasUpdateInstallMode>(TAtlasUpdateInstallMode.Auto, TAtlasUpdateInstall.ModeOf('auto'));
  Assert.AreEqual<TAtlasUpdateInstallMode>(TAtlasUpdateInstallMode.Off, TAtlasUpdateInstall.ModeOf('OFF'));
  Assert.AreEqual<TAtlasUpdateInstallMode>(TAtlasUpdateInstallMode.Ask, TAtlasUpdateInstall.ModeOf('ask'));
  Assert.AreEqual<TAtlasUpdateInstallMode>(TAtlasUpdateInstallMode.Ask,
    TAtlasUpdateInstall.ModeOf('irgendwie'), 'unbekannt: anbieten');
end;

procedure TAtlasUpdateInstallTests.ChoosesChannel;
begin
  Assert.AreEqual(TUpdateChannels.cStableUrl, TAtlasUpdateInstall.ChannelUrl('stable', '2.0.0'));
  Assert.AreEqual(TUpdateChannels.cPrereleaseUrl, TAtlasUpdateInstall.ChannelUrl('prerelease', '2.0.0'));
  // Eine installierte Vorabversion erfährt auch von der nächsten.
  Assert.AreEqual(TUpdateChannels.cPrereleaseUrl, TAtlasUpdateInstall.ChannelUrl('stable', '2.0.0-beta.1'));
end;

procedure TAtlasUpdateInstallTests.BlocksGetItAndForeignFolders;
var
  mEnvironment: TAtlasUpdateEnvironment;
begin
  mEnvironment := Environment;
  Assert.AreEqual<TAtlasUpdateBlock>(TAtlasUpdateBlock.None, TAtlasUpdateInstall.Blocked(mEnvironment));
  Assert.AreEqual('C:\Users\Ich\AppData\Local\Programs\Atlas', TAtlasUpdateInstall.TargetOf(cPluginDir));
  Assert.AreEqual('C:\Users\Ich\AppData\Local\Programs\Atlas\AtlasUpdate.exe',
    TAtlasUpdateInstall.UpdaterOf(cPluginDir));
  mEnvironment.UpdaterExists := False;
  Assert.AreEqual<TAtlasUpdateBlock>(TAtlasUpdateBlock.NoUpdater, TAtlasUpdateInstall.Blocked(mEnvironment));
  // Ausgabeordner des Repos statt <Ziel>\Win32.
  mEnvironment := Environment;
  mEnvironment.PluginDir := 'D:\Atlas\Output\Win32\Debug\Bpl\';
  Assert.AreEqual<TAtlasUpdateBlock>(TAtlasUpdateBlock.NoReleaseFolder, TAtlasUpdateInstall.Blocked(mEnvironment));
  mEnvironment.PluginDir := 'C:\Users\Public\Documents\Embarcadero\Studio\37.0\CatalogRepository\Atlas-2.0\Win32\';
  Assert.AreEqual<TAtlasUpdateBlock>(TAtlasUpdateBlock.GetIt, TAtlasUpdateInstall.Blocked(mEnvironment));
end;

procedure TAtlasUpdateInstallTests.PreparesWithoutAskingOnlyInAutoWithinMajor;
begin
  Assert.IsTrue(TAtlasUpdateInstall.PrepareWithoutAsking(TAtlasUpdateInstallMode.Auto, '2.0.0', '2.1.0'));
  Assert.IsFalse(TAtlasUpdateInstall.PrepareWithoutAsking(TAtlasUpdateInstallMode.Auto, '2.1.0', '3.0.0'),
    'neue Hauptversion nur nach Frage');
  Assert.IsFalse(TAtlasUpdateInstall.PrepareWithoutAsking(TAtlasUpdateInstallMode.Ask, '2.0.0', '2.1.0'));
  Assert.IsFalse(TAtlasUpdateInstall.PrepareWithoutAsking(TAtlasUpdateInstallMode.Off, '2.0.0', '2.1.0'));
  Assert.IsTrue(TAtlasUpdateInstall.IsMajorJump('1.2.0', '2.0.0-beta.1'));
end;

procedure TAtlasUpdateInstallTests.BuildsPrepareArguments;
var
  mArgs, mParsed: TUpdateArguments;
begin
  mArgs := TAtlasUpdateInstall.PrepareArgs(Environment, cRoot, '2.1.0', TUpdateChannels.cStableUrl, 'skip');
  mParsed := TUpdateArguments.Parse(mArgs.ToArgs);
  Assert.AreEqual('prepare', mParsed.Command);
  Assert.AreEqual('2.1.0', mParsed.Version);
  Assert.AreEqual('2.0.0', mParsed.Previous);
  Assert.AreEqual(TUpdateChannels.cStableUrl, mParsed.ManifestUrl);
  Assert.AreEqual('C:\Users\Ich\AppData\Local\Programs\Atlas', mParsed.Target);
  Assert.AreEqual(cRoot + '\2.1.0', mParsed.Staging);
  Assert.AreEqual('Software\Embarcadero\BDS\37.0', mParsed.RegistryKey);
  Assert.AreEqual<TUpdateNewModules>(TUpdateNewModules.Skip, mParsed.NewModules);
end;

procedure TAtlasUpdateInstallTests.BuildsApplyArgumentsFromSelection;
var
  mArgs: TUpdateArguments;
begin
  mArgs := TAtlasUpdateInstall.ApplyArgs(Environment, cRoot, ReadyStage, 4711);
  Assert.AreEqual('apply', mArgs.Command);
  Assert.AreEqual(Cardinal(4711), mArgs.WaitPid);
  Assert.AreEqual(cRoot + '\2.1.0', mArgs.Staging);
  Assert.AreEqual('Atlas.IDE.Base,Atlas.IDE.Debugger', string.Join(',', mArgs.Select));
  Assert.IsTrue(TAtlasUpdateInstall.IsFinished(ReadyStage));
end;

procedure TAtlasUpdateInstallTests.ChoiceKeepsRequiredPackages;
var
  mStage: TUpdateStage;
begin
  mStage := TAtlasUpdateInstall.Choose(ReadyStage, TArray<string>.Create('atlas.ide.notes', 'Unbekannt'));
  Assert.IsFalse(mStage.AskSelection, 'gewählt: nicht mehr fragen');
  Assert.AreEqual('Atlas.IDE.Base,Atlas.IDE.Notes', string.Join(',', mStage.SelectedNames));
  Assert.IsTrue(ReadyStage.Candidates[1].Selected, 'Vorlage unverändert');
  mStage.Phase := TUpdatePhase.Downloading;
  Assert.IsFalse(TAtlasUpdateInstall.IsFinished(mStage));
end;

end.
