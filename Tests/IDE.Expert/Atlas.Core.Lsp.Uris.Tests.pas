unit Atlas.Core.Lsp.Uris.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspUrisTests = class
  public
    [Test]
    procedure PathToUri;
    [Test]
    procedure UriToWindowsPath;
    [Test]
    procedure OtherSchemesAreEmpty;
  end;

implementation

uses
  Atlas.Core.Lsp.Uris;

procedure TLspUrisTests.PathToUri;
begin
  Assert.AreEqual('file:///c%3A/Mein%20Projekt/%C3%9Cbung.pas', TLspUris.FromPath('C:\Mein Projekt\Übung.pas'));
  Assert.AreEqual('file://server/share/a.pas', TLspUris.FromPath('\\server\share\a.pas'));
end;

procedure TLspUrisTests.UriToWindowsPath;
begin
  Assert.AreEqual('C:\Mein Projekt\Übung.pas', TLspUris.ToPath('file:///C%3A/Mein%20Projekt/%C3%9Cbung.pas'));
  Assert.AreEqual('c:\x\a.pas', TLspUris.ToPath('file:///c:/x/a.pas'));
  Assert.AreEqual('\\server\share\a.pas', TLspUris.ToPath('file://server/share/a.pas'));
end;

procedure TLspUrisTests.OtherSchemesAreEmpty;
begin
  Assert.AreEqual('', TLspUris.ToPath('untitled:1'));
end;

initialization
  TDUnitX.RegisterTestFixture(TLspUrisTests);

end.
