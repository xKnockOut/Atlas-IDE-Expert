unit Platform.Server.Tests;

// Tests für die Plattformdienste des Servers (#1109): Ersetzendes Umbenennen,
// kanonische Pfade und eigene Prozessnummer.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TServerPlatformTests = class
  private
    FFolder: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure MoveReplacingOverwritesTarget;
    [Test]
    procedure CanonicalizePathKeepsExistingFile;
    [Test]
    procedure CurrentProcessIdIsRunning;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Platform.Server,
  Atlas.Tests.TempFolder;

{ TServerPlatformTests }

procedure TServerPlatformTests.Setup;
begin
  FFolder := TPath.Combine(TPath.GetTempPath, 'AtlasPlatform-' + TGUID.NewGuid.ToString.Substring(1, 8));
  TDirectory.CreateDirectory(FFolder);
end;

procedure TServerPlatformTests.TearDown;
begin
  TTestTempFolder.Remove(FFolder);
end;

procedure TServerPlatformTests.MoveReplacingOverwritesTarget;
var
  mSource, mTarget: string;
begin
  mSource := TPath.Combine(FFolder, 'neu.txt');
  mTarget := TPath.Combine(FFolder, 'alt.txt');
  TFile.WriteAllText(mSource, 'neu');
  TFile.WriteAllText(mTarget, 'alt');
  Assert.IsTrue(TServerPlatform.MoveReplacing(mSource, mTarget), 'ersetzt');
  Assert.IsFalse(TFile.Exists(mSource), 'Quelle weg');
  Assert.AreEqual('neu', TFile.ReadAllText(mTarget, TEncoding.UTF8));
  Assert.IsFalse(TServerPlatform.MoveReplacing(mSource, mTarget), 'fehlende Quelle');
end;

procedure TServerPlatformTests.CanonicalizePathKeepsExistingFile;
var
  mFileName, mCanonical: string;
begin
  mFileName := TPath.Combine(FFolder, 'Unit1.pas');
  TFile.WriteAllText(mFileName, 'unit Unit1;');
  mCanonical := TServerPlatform.CanonicalizePath(mFileName);
  Assert.IsTrue(TFile.Exists(mCanonical), mCanonical);
  Assert.AreEqual(mCanonical, TServerPlatform.CanonicalizePath(mCanonical), 'stabil');
  Assert.AreEqual('Unit1.pas', ExtractFileName(mCanonical));
end;

procedure TServerPlatformTests.CurrentProcessIdIsRunning;
begin
  Assert.IsTrue(TServerPlatform.CurrentProcessId > 0);
  Assert.IsTrue(TProcessInstances.Running(TServerPlatform.CurrentProcessId));
end;

initialization
  TDUnitX.RegisterTestFixture(TServerPlatformTests);

end.
