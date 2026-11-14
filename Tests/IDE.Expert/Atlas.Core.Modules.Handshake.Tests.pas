unit Atlas.Core.Modules.Handshake.Tests;

// Versions-Handschlag zwischen Base und Modul (#1455, Regel 7): Das
// Testprogramm bindet Atlas.Core.Modules.Handshake ein und exportiert damit
// AtlasCoreContractVersion selbst; Windows-Module ohne den Export stehen für
// ein Base, das fehlt oder kein Atlas ist.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TContractHandshakeTests = class
  public
    [Test]
    procedure CompareCoversAllOutcomes;
    [Test]
    procedure QueryFindsOwnExport;
    [Test]
    procedure QueryWithoutExportFails;
    [Test]
    procedure CheckReportsMismatch;
  end;

implementation

uses
  Winapi.Windows,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Modules.Handshake;

{ TContractHandshakeTests }

procedure TContractHandshakeTests.CompareCoversAllOutcomes;
begin
  Assert.AreEqual<TAtlasContractCheck>(ccMatch, TAtlasContractHandshake.Compare(True, 3, 3));
  Assert.AreEqual<TAtlasContractCheck>(ccMismatch, TAtlasContractHandshake.Compare(True, 2, 3));
  Assert.AreEqual<TAtlasContractCheck>(ccMismatch, TAtlasContractHandshake.Compare(True, 4, 3));
  Assert.AreEqual<TAtlasContractCheck>(ccMissing, TAtlasContractHandshake.Compare(False, 3, 3));
end;

procedure TContractHandshakeTests.QueryFindsOwnExport;
var
  mVersion: Integer;
begin
  Assert.AreEqual(cAtlasCoreContractVersion, AtlasCoreContractVersion());
  Assert.IsTrue(TAtlasContractHandshake.Query(HInstance, mVersion));
  Assert.AreEqual(cAtlasCoreContractVersion, mVersion);
  Assert.AreEqual<TAtlasContractCheck>(ccMatch, TAtlasContractHandshake.Check(HInstance, cAtlasCoreContractVersion));
end;

procedure TContractHandshakeTests.QueryWithoutExportFails;
var
  mVersion: Integer;
begin
  Assert.IsFalse(TAtlasContractHandshake.Query(GetModuleHandle('kernel32.dll'), mVersion));
  Assert.AreEqual(0, mVersion);
  Assert.IsFalse(TAtlasContractHandshake.Query(0, mVersion), 'kein Modul');
  Assert.AreEqual<TAtlasContractCheck>(ccMissing,
    TAtlasContractHandshake.Check(GetModuleHandle('kernel32.dll'), cAtlasCoreContractVersion));
end;

procedure TContractHandshakeTests.CheckReportsMismatch;
begin
  Assert.AreEqual<TAtlasContractCheck>(ccMismatch,
    TAtlasContractHandshake.Check(HInstance, cAtlasCoreContractVersion + 1));
end;

initialization
  TDUnitX.RegisterTestFixture(TContractHandshakeTests);

end.
