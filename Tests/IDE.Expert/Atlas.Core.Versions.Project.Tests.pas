unit Atlas.Core.Versions.Project.Tests;

// Tests für die Versionsnummer eines Projekts (#533, #1455).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasProjectVersionTests = class
  public
    [Test]
    procedure IsOnReadsOptionValues;
    [Test]
    procedure FileVersionFromKeys;
    [Test]
    procedure SinglePartsWithDefaults;
    [Test]
    procedure WithoutVersionInfoEmpty;
  end;

implementation

uses
  Atlas.Core.Versions.Project;

procedure TAtlasProjectVersionTests.IsOnReadsOptionValues;
begin
  Assert.IsTrue(TAtlasProjectVersion.IsOn('True', False));
  Assert.IsTrue(TAtlasProjectVersion.IsOn(' 2 ', False));
  Assert.IsFalse(TAtlasProjectVersion.IsOn('0', True));
  Assert.IsTrue(TAtlasProjectVersion.IsOn('$(Unbekannt)', True));
  Assert.IsFalse(TAtlasProjectVersion.IsOn('', False));
end;

procedure TAtlasProjectVersionTests.FileVersionFromKeys;
begin
  Assert.AreEqual('1.2.0.0', TAtlasProjectVersion.FromOptions('true', 'CompanyName=;FileVersion=1.2.0.0;ProductName=', '3',
    '4', '5', '6'));
end;

procedure TAtlasProjectVersionTests.SinglePartsWithDefaults;
begin
  // Ohne FileVersion bzw. mit Makro: Einzelwerte, fehlende mit Vorgabe 1.0.0.0.
  Assert.AreEqual('1.4.0.17', TAtlasProjectVersion.FromOptions('true', 'FileVersion=$(MajorVer).$(MinorVer)', '', '4', '',
    '17'));
  Assert.AreEqual('1.0.0.0', TAtlasProjectVersion.FromOptions('1', '', '', '', '', ''));
end;

procedure TAtlasProjectVersionTests.WithoutVersionInfoEmpty;
begin
  Assert.AreEqual('', TAtlasProjectVersion.FromOptions('false', 'FileVersion=1.2.0.0', '1', '2', '0', '0'));
  Assert.AreEqual('', TAtlasProjectVersion.FromOptions('', 'FileVersion=1.2.0.0', '1', '2', '0', '0'));
end;

end.
