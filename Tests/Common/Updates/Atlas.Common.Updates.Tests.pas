unit Atlas.Common.Updates.Tests;

// Tests der Bausteine des Update-Installers (#1519): IDE-Versionen und
// Profile, Known Packages, Auswahl der Packages, sicheres Entpacken, Bau aus
// dem Quelltext und Dateitausch mit Rückfall.

interface

uses
  DUnitX.TestFramework,
  Atlas.Tests.UpdateFakes;

type
  [TestFixture]
  TCommonUpdatesTests = class
  private
    FFake: TFakeUpdateSystem;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure KnowsIdeVersions;
    [Test]
    procedure ListsProfilesDefaultFirst;
    [Test]
    procedure ListsInstalledIdes;
    [Test]
    procedure PlansKnownPackages;
    [Test]
    procedure PlanRemovesLegacyAndDisabled;
    [Test]
    procedure RevertRestoresRegistry;
    [Test]
    procedure FindsUseInOtherProfile;
    [Test]
    procedure ProposesSelection;
    [Test]
    procedure ResolvesSelection;
    [Test]
    procedure RemembersDeclined;
    [Test]
    procedure RejectsUnsafeEntries;
    [Test]
    procedure ExtractsArchive;
    [Test]
    procedure OrdersSourceProjects;
    [Test]
    procedure SwapsAndRollsBack;
    [Test]
    procedure MovesLockedExeAside;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Text.UpdateRun,
  Atlas.Common.Updates.Contract,
  Atlas.Common.Updates.Ides,
  Atlas.Common.Updates.KnownPackages,
  Atlas.Common.Updates.Selection,
  Atlas.Common.Updates.Archive,
  Atlas.Common.Updates.SourceBuild,
  Atlas.Common.Updates.FileSwap;

const
  cKey = 'Software\Embarcadero\BDS\37.0';
  cKnown = cKey + '\Known Packages';
  cDir = 'C:\Atlas\Win32';

procedure TCommonUpdatesTests.Setup;
begin
  FFake := TFakeUpdateSystem.Create;
end;

procedure TCommonUpdatesTests.TearDown;
begin
  FreeAndNil(FFake);
end;

function Target: TUpdatePackageTarget;
begin
  Result := Default(TUpdatePackageTarget);
  Result.RegistryKey := cKey;
  Result.Platform := TUpdateIdes.cWin32;
  Result.PackageDir := cDir;
  Result.Suffix := '370';
end;

procedure TCommonUpdatesTests.KnowsIdeVersions;
var
  mVersion: TUpdateIdeVersion;
  mProfile: TUpdateIdeProfile;
begin
  Assert.IsTrue(TUpdateIdes.ByCompilerVersion('36.0', mVersion));
  Assert.AreEqual('23.0', mVersion.BdsVersion);
  Assert.AreEqual('290', TUpdateIdes.PackageSuffix('36.0'));
  Assert.AreEqual('370', TUpdateIdes.PackageSuffix('37.0'));
  Assert.AreEqual('380', TUpdateIdes.PackageSuffix('38.0'));
  Assert.IsFalse(TUpdateIdes.ByCompilerVersion('35.0', mVersion));
  Assert.AreEqual('37.0', TUpdateIdes.Catalog[0].CompilerVersion);
  Assert.AreEqual('37.0', TUpdateIdes.BdsVersionOf('Software\Embarcadero\BDS\37.0\'));
  Assert.AreEqual('', TUpdateIdes.BdsVersionOf('Software\Embarcadero\BDS'));
  Assert.AreEqual(cKey + '\Known Packages x64', TUpdateIdes.KnownPackagesKey(cKey, 'win64'));
  mProfile := Default(TUpdateIdeProfile);
  mProfile.BdsVersion := '37.0';
  mProfile.Profile := 'Atlas';
  Assert.AreEqual('Delphi 13 Florence (Atlas)', mProfile.Caption);
end;

procedure TCommonUpdatesTests.ListsProfilesDefaultFirst;
var
  mProfiles: TArray<TUpdateIdeProfile>;
begin
  FFake.Registry.WriteValue('Software\Embarcadero\Atlas\37.0\Known Packages', 'x', 'y');
  FFake.Registry.WriteValue('Software\Embarcadero\BDS\37.0\Known Packages', 'x', 'y');
  FFake.Registry.WriteValue('Software\Embarcadero\BDS\23.0\Known Packages', 'x', 'y');
  mProfiles := TUpdateIdes.Profiles(FFake.Registry, '37.0');
  Assert.AreEqual(2, Integer(Length(mProfiles)));
  Assert.AreEqual('BDS', mProfiles[0].Profile);
  Assert.AreEqual('Software\Embarcadero\Atlas\37.0', mProfiles[1].RegistryKey);
end;

procedure TCommonUpdatesTests.ListsInstalledIdes;
var
  mChoices: TArray<TUpdateIdeChoice>;
begin
  FFake.Registry.WriteValue('Software\Embarcadero\BDS\37.0\Known Packages', 'x', 'y');
  FFake.Registry.WriteValue('Software\Embarcadero\Atlas\37.0\Known Packages', 'x', 'y');
  FFake.Registry.WriteValue('Software\Embarcadero\BDS\23.0\Known Packages', 'x', 'y');
  FFake.Registry.SetRootDir('37.0', 'C:\D13');
  FFake.Registry.SetRootDir('23.0', 'C:\D12');
  FFake.Files.WriteText('C:\D13\bin64\bds.exe', '');
  mChoices := TUpdateIdes.Choices(FFake.Registry, FFake.Files);
  Assert.AreEqual(5, Integer(Length(mChoices)));
  Assert.AreEqual('Win64', mChoices[1].Platform);
  Assert.AreEqual('Delphi 13 Florence (Atlas)', mChoices[2].Caption);
  Assert.AreEqual('36.0', mChoices[4].CompilerVersion);
  Assert.AreEqual('Software\Embarcadero\BDS\23.0', mChoices[4].Profile.RegistryKey);
end;

procedure TCommonUpdatesTests.PlansKnownPackages;
var
  mChanges: TArray<TUpdateRegistryChange>;
begin
  FFake.Registry.WriteValue(cKnown, cDir + '\Atlas.IDE.Base370.bpl', 'Atlas Base');
  FFake.Registry.WriteValue(cKnown, cDir + '\Atlas.IDE.Debugger370.bpl', 'Atlas Debugger');
  FFake.Registry.WriteValue(cKnown, 'C:\Fremd\Anderer370.bpl', 'Fremd');
  // Gleicher Name aus einem anderen Ordner: wird ersetzt.
  FFake.Registry.WriteValue(cKnown, 'D:\Alt\Atlas.IDE.Search370.bpl', 'Atlas Search');
  mChanges := TUpdateKnownPackages.Plan(FFake.Registry, Target, TArray<string>.Create('Atlas.IDE.Search',
    'Atlas.IDE.Base'));
  TUpdateKnownPackages.Apply(FFake.Registry, mChanges);
  Assert.AreEqual(cDir + '\Atlas.IDE.Base370.bpl=Atlas Base;C:\Fremd\Anderer370.bpl=Fremd;' + cDir +
    '\Atlas.IDE.Search370.bpl=Atlas Search;', FFake.Registry.Dump(cKnown));
  Assert.AreEqual(2, Integer(Length(TUpdateKnownPackages.Registered(FFake.Registry, Target))));
end;

procedure TCommonUpdatesTests.PlanRemovesLegacyAndDisabled;
var
  mChanges: TArray<TUpdateRegistryChange>;
begin
  FFake.Registry.WriteValue(cKnown, 'C:\Tools\Atlas.IDE.Expert370.bpl', 'Atlas 1.x');
  FFake.Registry.WriteValue(cKey + '\Disabled Packages', cDir + '\Atlas.IDE.Base370.bpl', 'Atlas Base');
  FFake.Registry.WriteValue(cKey + '\Disabled Packages', 'C:\Fremd\Anderer370.bpl', 'Fremd');
  mChanges := TUpdateKnownPackages.Plan(FFake.Registry, Target, TArray<string>.Create('Atlas.IDE.Base'));
  TUpdateKnownPackages.Apply(FFake.Registry, mChanges);
  Assert.AreEqual(cDir + '\Atlas.IDE.Base370.bpl=Atlas Base;', FFake.Registry.Dump(cKnown));
  Assert.AreEqual('C:\Fremd\Anderer370.bpl=Fremd;', FFake.Registry.Dump(cKey + '\Disabled Packages'));
end;

/// <summary>Werte ohne Reihenfolge: Der Rückfall stellt Inhalt her, nicht die Reihenfolge.</summary>
function Sorted(const ADump: string): string;
var
  mParts: TArray<string>;
begin
  mParts := ADump.Split([';'], TStringSplitOptions.ExcludeEmpty);
  TArray.Sort<string>(mParts);
  Result := string.Join(';', mParts);
end;

procedure TCommonUpdatesTests.RevertRestoresRegistry;
var
  mChanges: TArray<TUpdateRegistryChange>;
  mBefore: string;
begin
  FFake.Registry.WriteValue(cKnown, cDir + '\Atlas.IDE.Debugger370.bpl', 'Atlas Debugger');
  FFake.Registry.WriteValue(cKnown, 'C:\Tools\BetterDelphiLSP290.bpl', 'Alt');
  mBefore := Sorted(FFake.Registry.Dump(cKnown));
  mChanges := TUpdateKnownPackages.Plan(FFake.Registry, Target, TArray<string>.Create('Atlas.IDE.Base'));
  TUpdateKnownPackages.Apply(FFake.Registry, mChanges);
  Assert.AreNotEqual(mBefore, Sorted(FFake.Registry.Dump(cKnown)));
  TUpdateKnownPackages.Revert(FFake.Registry, mChanges);
  Assert.AreEqual(mBefore, Sorted(FFake.Registry.Dump(cKnown)));
end;

procedure TCommonUpdatesTests.FindsUseInOtherProfile;
begin
  FFake.Registry.WriteValue(cKnown, cDir + '\Atlas.IDE.Debugger370.bpl', 'Atlas Debugger');
  Assert.IsFalse(TUpdateKnownPackages.UsedElsewhere(FFake.Registry, cDir + '\Atlas.IDE.Debugger370.bpl', cKey));
  FFake.Registry.WriteValue('Software\Embarcadero\Test\37.0\Known Packages', cDir + '\Atlas.IDE.Debugger370.bpl',
    'Atlas Debugger');
  Assert.IsTrue(TUpdateKnownPackages.UsedElsewhere(FFake.Registry, cDir + '\atlas.ide.debugger370.bpl', cKey));
end;

function Input(ANewModules: TUpdateNewModules): TUpdateSelectionInput;
begin
  Result := Default(TUpdateSelectionInput);
  Result.Staged := TArray<string>.Create('Atlas.IDE.Base', 'Atlas.IDE.Debugger', 'Atlas.IDE.Search',
    'Atlas.IDE.Tracker', 'Atlas.IDE.Welcome');
  Result.Registered := TArray<string>.Create('Atlas.IDE.Base', 'Atlas.IDE.Debugger');
  // Tracker liegt im Ordner, ist aber nicht eingetragen (früher abgewählt).
  Result.Present := TArray<string>.Create('Atlas.IDE.Base', 'Atlas.IDE.Debugger', 'Atlas.IDE.Tracker');
  Result.Declined := TArray<string>.Create('Atlas.IDE.Welcome');
  Result.NewModules := ANewModules;
end;

procedure TCommonUpdatesTests.ProposesSelection;
var
  mCandidates: TArray<TUpdateCandidate>;
begin
  mCandidates := TUpdateSelection.Candidates(Input(TUpdateNewModules.Ask));
  Assert.IsTrue(mCandidates[0].Required and mCandidates[0].Selected);
  Assert.IsTrue(mCandidates[1].Installed and mCandidates[1].Selected);
  Assert.IsTrue(mCandidates[2].IsNew and mCandidates[2].Selected);
  Assert.IsFalse(mCandidates[3].IsNew or mCandidates[3].Selected);
  Assert.IsTrue(mCandidates[4].Declined and not mCandidates[4].Selected);
  Assert.IsTrue(TUpdateSelection.MustAsk(mCandidates, TUpdateNewModules.Ask));
  mCandidates := TUpdateSelection.Candidates(Input(TUpdateNewModules.Skip));
  Assert.IsFalse(mCandidates[2].Selected);
  Assert.IsFalse(TUpdateSelection.MustAsk(mCandidates, TUpdateNewModules.Skip));
end;

procedure TCommonUpdatesTests.ResolvesSelection;
var
  mCandidates: TArray<TUpdateCandidate>;
  mSelected: TArray<string>;
begin
  mCandidates := TUpdateSelection.Candidates(Input(TUpdateNewModules.Install));
  mSelected := TUpdateSelection.Resolve(mCandidates, nil);
  Assert.AreEqual('Atlas.IDE.Base,Atlas.IDE.Debugger,Atlas.IDE.Search', string.Join(',', mSelected));
  // Der Kern bleibt, auch wenn er fehlt.
  mSelected := TUpdateSelection.Resolve(mCandidates, TArray<string>.Create('Atlas.IDE.Tracker'));
  Assert.AreEqual('Atlas.IDE.Base,Atlas.IDE.Tracker', string.Join(',', mSelected));
  Assert.WillRaise(
    procedure
    begin
      TUpdateSelection.Resolve(mCandidates, TArray<string>.Create('Atlas.IDE.Unbekannt'));
    end, EUpdateError);
end;

procedure TCommonUpdatesTests.RemembersDeclined;
var
  mCandidates: TArray<TUpdateCandidate>;
  mDeclined: TArray<string>;
begin
  mCandidates := TUpdateSelection.Candidates(Input(TUpdateNewModules.Ask));
  mDeclined := TUpdateSelection.Declined(TArray<string>.Create('Atlas.IDE.Welcome', 'Atlas.IDE.Alt'), mCandidates,
    TArray<string>.Create('Atlas.IDE.Base', 'Atlas.IDE.Welcome'));
  Assert.AreEqual('Atlas.IDE.Alt,Atlas.IDE.Search', string.Join(',', mDeclined));
  Assert.AreEqual('a,b', string.Join(',', TUpdateSelection.ParseLines(' a '#13#10#13#10'b')));
  Assert.AreEqual('a'#13#10'b'#13#10, TUpdateSelection.JoinLines(TArray<string>.Create('a', 'b')));
end;

procedure TCommonUpdatesTests.RejectsUnsafeEntries;
begin
  Assert.IsTrue(TUpdateArchives.IsSafeEntry('Win32/Atlas.IDE.Base370.bpl'));
  Assert.IsTrue(TUpdateArchives.IsSafeEntry('Doku/a..b.html'));
  Assert.IsFalse(TUpdateArchives.IsSafeEntry('../böse.exe'));
  Assert.IsFalse(TUpdateArchives.IsSafeEntry('Win32\..\..\böse.exe'));
  Assert.IsFalse(TUpdateArchives.IsSafeEntry('/etc/x'));
  Assert.IsFalse(TUpdateArchives.IsSafeEntry('C:\Windows\x.dll'));
  Assert.IsFalse(TUpdateArchives.IsSafeEntry('a'#9'b'));
  Assert.IsFalse(TUpdateArchives.IsSafeEntry(''));
end;

procedure TCommonUpdatesTests.ExtractsArchive;
begin
  FFake.Archive.Add('zip1', 'Win32/', '');
  FFake.Archive.Add('zip1', 'Win32/Atlas.IDE.Base370.bpl', 'base');
  FFake.Archive.Add('zip1', 'AtlasServer.exe', 'server');
  FFake.Files.WriteText('C:\S\p.zip', 'zip1');
  TUpdateArchives.ExtractAll(FFake.System.Archive, 'C:\S\p.zip', 'C:\S\files');
  Assert.AreEqual('base', FFake.Files.ReadText('C:\S\files\Win32\Atlas.IDE.Base370.bpl'));
  Assert.AreEqual('server', FFake.Files.ReadText('C:\S\files\AtlasServer.exe'));
  FFake.Archive.Add('zip2', 'gut.txt', 'gut');
  FFake.Archive.Add('zip2', '../böse.txt', 'böse');
  FFake.Files.WriteText('C:\S\q.zip', 'zip2');
  Assert.WillRaise(
    procedure
    begin
      TUpdateArchives.ExtractAll(FFake.System.Archive, 'C:\S\q.zip', 'C:\S\q');
    end, EUpdateError);
  // Nichts geschrieben, bevor das ganze Archiv geprüft ist.
  Assert.IsFalse(FFake.Files.FileExists('C:\S\q\gut.txt'));
end;

procedure TCommonUpdatesTests.OrdersSourceProjects;
var
  mProjects: TArray<string>;
begin
  mProjects := TUpdateSourceBuild.Projects(TArray<string>.Create('Packages\Atlas.IDE.Search\Atlas.IDE.Search.dproj',
    'Packages\Atlas.Text\Atlas.Text.dproj', 'Packages\Atlas.IDE.Base\Atlas.IDE.Base.dproj',
    'Packages\Atlas.IDE.Debugger\Atlas.IDE.Debugger.dproj', 'Packages\Atlas.IDE.Base\Source\X.dproj',
    'Packages\Atlas.IDE.Contracts\Atlas.IDE.Contracts.dproj'));
  Assert.AreEqual('Packages\Atlas.IDE.Base\Atlas.IDE.Base.dproj,' +
    'Packages\Atlas.IDE.Contracts\Atlas.IDE.Contracts.dproj,' +
    'Packages\Atlas.IDE.Debugger\Atlas.IDE.Debugger.dproj,Packages\Atlas.IDE.Search\Atlas.IDE.Search.dproj',
    string.Join(',', mProjects));
end;

procedure TCommonUpdatesTests.SwapsAndRollsBack;
var
  mSwap: TUpdateFileSwap;
begin
  FFake.Files.WriteText('C:\Atlas\a.txt', 'alt');
  FFake.Files.WriteText('C:\Atlas\weg.txt', 'weg');
  FFake.Files.WriteText('C:\New\a.txt', 'neu');
  FFake.Files.WriteText('C:\New\b.txt', 'neu b');
  mSwap := TUpdateFileSwap.Create(FFake.System.Files, 'C:\Atlas', 'C:\Backup');
  try
    mSwap.CopyIn('C:\New\a.txt', 'a.txt');
    mSwap.CopyIn('C:\New\b.txt', 'b.txt');
    mSwap.Remove('weg.txt');
    mSwap.Remove('gibtsnicht.txt');
    Assert.AreEqual('neu', FFake.Files.ReadText('C:\Atlas\a.txt'));
    Assert.IsFalse(FFake.Files.FileExists('C:\Atlas\weg.txt'));
    Assert.AreEqual(3, Integer(Length(mSwap.Steps)));
    mSwap.Rollback(FFake.System.Log);
  finally
    mSwap.Free;
  end;
  Assert.AreEqual('alt', FFake.Files.ReadText('C:\Atlas\a.txt'));
  Assert.AreEqual('weg', FFake.Files.ReadText('C:\Atlas\weg.txt'));
  Assert.IsFalse(FFake.Files.FileExists('C:\Atlas\b.txt'));
end;

procedure TCommonUpdatesTests.MovesLockedExeAside;
var
  mSwap: TUpdateFileSwap;
begin
  FFake.Files.WriteText('C:\Atlas\AtlasServer.exe', 'alt');
  FFake.Files.Lock('C:\Atlas\AtlasServer.exe');
  FFake.Files.WriteText('C:\New\AtlasServer.exe', 'neu');
  mSwap := TUpdateFileSwap.Create(FFake.System.Files, 'C:\Atlas', 'C:\Backup');
  try
    mSwap.CopyIn('C:\New\AtlasServer.exe', 'AtlasServer.exe');
  finally
    mSwap.Free;
  end;
  Assert.AreEqual('neu', FFake.Files.ReadText('C:\Atlas\AtlasServer.exe'));
  Assert.AreEqual('alt', FFake.Files.ReadText('C:\Atlas\AtlasServer.exe' + TUpdateLayout.OldSuffix));
  // Noch gesperrt: bleibt bis zum nächsten Update.
  TUpdateFileSwap.CleanupOld(FFake.System.Files, 'C:\Atlas', FFake.System.Log);
  Assert.IsTrue(FFake.Files.FileExists('C:\Atlas\AtlasServer.exe' + TUpdateLayout.OldSuffix));
  FFake.Files.Unlock('C:\Atlas\AtlasServer.exe' + TUpdateLayout.OldSuffix);
  TUpdateFileSwap.CleanupOld(FFake.System.Files, 'C:\Atlas', FFake.System.Log);
  Assert.IsFalse(FFake.Files.FileExists('C:\Atlas\AtlasServer.exe' + TUpdateLayout.OldSuffix));
end;

end.
