unit BDLsp.Common.Lsp.DocWiki.Tests;

// Tests für die DocWiki-Links im Hover (#27).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDocWikiTests = class
  public
    [Test]
    procedure MapsVersionsToReleases;
    [Test]
    procedure UnknownVersionUsesNewest;
    [Test]
    procedure RecognizesLibraryUnits;
    [Test]
    procedure BuildsUrls;
  end;

implementation

uses
  BDLsp.Common.Lsp.DocWiki;

procedure TDocWikiTests.MapsVersionsToReleases;
begin
  Assert.AreEqual('Athens', TDocWiki.ReleaseName('23.0'));
  Assert.AreEqual('Alexandria', TDocWiki.ReleaseName('22.0'));
  Assert.AreEqual('Rio', TDocWiki.ReleaseName(' 20.0 '));
  Assert.AreEqual('Florence', TDocWiki.ReleaseName('37.0'));
end;

procedure TDocWikiTests.UnknownVersionUsesNewest;
begin
  Assert.AreEqual('Florence', TDocWiki.ReleaseName(''));
  Assert.AreEqual('Florence', TDocWiki.ReleaseName('99.0'));
end;

procedure TDocWikiTests.RecognizesLibraryUnits;
begin
  Assert.IsTrue(TDocWiki.IsLibraryUnit('System.SysUtils'));
  Assert.IsTrue(TDocWiki.IsLibraryUnit('vcl.forms'));
  Assert.IsTrue(TDocWiki.IsLibraryUnit('System'));
  Assert.IsFalse(TDocWiki.IsLibraryUnit('SystemTools'));
  Assert.IsFalse(TDocWiki.IsLibraryUnit('MyApp.Main'));
end;

procedure TDocWikiTests.BuildsUrls;
begin
  Assert.AreEqual('https://docwiki.embarcadero.com/Libraries/Athens/en/System.SysUtils.IntToStr',
    TDocWiki.Url('23.0', 'System.SysUtils', '', 'IntToStr'));
  Assert.AreEqual('https://docwiki.embarcadero.com/Libraries/Athens/en/Vcl.Forms.TForm.Show',
    TDocWiki.Url('23.0', 'Vcl.Forms', 'TForm', 'Show'));
  Assert.AreEqual('https://docwiki.embarcadero.com/Libraries/Athens/en/Vcl.Forms',
    TDocWiki.Url('23.0', 'Vcl.Forms', '', ''));
  Assert.AreEqual('', TDocWiki.Url('23.0', 'MyApp.Main', 'TFoo', 'Bar'));
end;

initialization
  TDUnitX.RegisterTestFixture(TDocWikiTests);

end.
