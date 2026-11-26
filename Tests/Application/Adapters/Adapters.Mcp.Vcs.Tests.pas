unit Adapters.Mcp.Vcs.Tests;

// Tests für den Host-Adapter zwischen Mcp und der Versionsverwaltung: Ohne Arbeitskopie und mit vcs.provider = off
// melden Änderungen, Hotspots und Symbolverlauf den Grund statt eines Ergebnisses.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMcpVcsAdapterTests = class
  private
    FFolder: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure WithoutWorkingCopyGivesReason;
    [Test]
    procedure ProviderOffGivesReason;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.History.Contract,
  Atlas.Common.Hotspots.Contract,
  Mcp.Contract.Vcs,
  Adapters.Mcp.Vcs,
  Core.VersionControlChanges,
  Atlas.Tests.TempFolder,
  Shell.Composition.Platform;

function PlatformAccess: TCoreVcsAccess;
begin
  Result := TShellPlatformAdapters.VcsAccess;
end;

/// <summary>Alle drei Abfragen für AFolder: jeweils False mit Grund, der AExpected enthält.</summary>
procedure AssertAllRefused(const AFolder: string; const ASettings: TServerSettings; const AExpected: string);
var
  mVcs: IMcpVcs;
  mChanges: IMcpVcsChanges;
  mHotspots: IHotspotVcs;
  mHistory: ISymbolHistoryVcs;
  mError: string;
begin
  mVcs := TMcpVcsAdapter.New(PlatformAccess);
  Assert.IsFalse(mVcs.Changes(AFolder, '', ASettings, mChanges, mError), 'Änderungen');
  Assert.IsNull(mChanges);
  Assert.Contains(mError, AExpected);
  Assert.IsFalse(mVcs.Hotspots(AFolder, ASettings, mHotspots, mError), 'Hotspots');
  Assert.IsNull(mHotspots);
  Assert.Contains(mError, AExpected);
  Assert.IsFalse(mVcs.SymbolHistory(AFolder, ASettings, mHistory, mError), 'Symbolverlauf');
  Assert.IsNull(mHistory);
  Assert.Contains(mError, AExpected);
end;

procedure TMcpVcsAdapterTests.Setup;
begin
  FFolder := TPath.Combine(TPath.GetTempPath, 'Atlas-McpVcs-' + IntToStr(Random(MaxInt)));
  TDirectory.CreateDirectory(FFolder);
end;

procedure TMcpVcsAdapterTests.TearDown;
begin
  TTestTempFolder.Remove(FFolder);
end;

procedure TMcpVcsAdapterTests.WithoutWorkingCopyGivesReason;
begin
  AssertAllRefused(FFolder, TServerSettings.Default, 'SVN');
end;

procedure TMcpVcsAdapterTests.ProviderOffGivesReason;
var
  mSettings: TServerSettings;
begin
  mSettings := TServerSettings.Default;
  mSettings.VcsProvider := 'off';
  AssertAllRefused(FFolder, mSettings, 'vcs.provider');
end;

initialization
  TDUnitX.RegisterTestFixture(TMcpVcsAdapterTests);

end.
