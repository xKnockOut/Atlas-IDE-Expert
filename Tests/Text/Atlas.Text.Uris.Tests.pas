unit Atlas.Text.Uris.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTextUrisTests = class
  public
    [Test]
    procedure ConvertsDrivePaths;
    [Test]
    procedure ConvertsUncPaths;
    [Test]
    procedure KeepsPosixPaths;
    [Test]
    procedure DecodesPercentSequences;
    [Test]
    procedure EncodesSpecialCharacters;
    [Test]
    procedure IgnoresOtherSchemes;
    [Test]
    procedure NormalizesPaths;
    [Test]
    procedure RoundTrip;
  end;

implementation

uses
  Atlas.Text.Uris;

procedure TTextUrisTests.ConvertsDrivePaths;
begin
  Assert.AreEqual('file:///c%3A/Projekt/A%20B.pas', TTextUris.FromPath('C:\Projekt\A B.pas'));
  Assert.AreEqual('c:\Projekt\A B.pas', TTextUris.ToPath('file:///c%3A/Projekt/A%20B.pas'));
  Assert.AreEqual('C:\Projekt\A.pas', TTextUris.ToPath('file:///C:/Projekt/A.pas'));
end;

procedure TTextUrisTests.ConvertsUncPaths;
begin
  Assert.AreEqual('file://server/share/A.pas', TTextUris.FromPath('\\server\share\A.pas'));
  Assert.AreEqual('\\server\share\A.pas', TTextUris.ToPath('file://server/share/A.pas'));
  Assert.AreEqual('c:\x', TTextUris.ToPath('file://localhost/c:/x'));
end;

procedure TTextUrisTests.KeepsPosixPaths;
begin
  Assert.AreEqual('/home/a/A.pas', TTextUris.ToPath('file:///home/a/A.pas'));
  Assert.AreEqual('file:///home/a/A.pas', TTextUris.FromPath('/home/a/A.pas'));
end;

procedure TTextUrisTests.DecodesPercentSequences;
begin
  Assert.AreEqual('c:\Gr' + #$00FC + 'n.pas', TTextUris.ToPath('file:///c%3A/Gr%C3%BCn.pas'));
  Assert.AreEqual('a#b c', TTextUris.PercentDecode('a%23b%20c'));
  // Unvollständige oder ungültige Folgen bleiben stehen.
  Assert.AreEqual('100%', TTextUris.PercentDecode('100%'));
  Assert.AreEqual('%zz', TTextUris.PercentDecode('%zz'));
end;

procedure TTextUrisTests.EncodesSpecialCharacters;
begin
  Assert.AreEqual('file:///c%3A/Gr%C3%BCn.pas', TTextUris.FromPath('c:\Gr' + #$00FC + 'n.pas'));
  Assert.AreEqual('a%23b%20c%25', TTextUris.PercentEncode('a#b c%'));
  Assert.AreEqual('A-z_0.~/', TTextUris.PercentEncode('A-z_0.~/'));
end;

procedure TTextUrisTests.IgnoresOtherSchemes;
begin
  Assert.AreEqual('', TTextUris.ToPath('untitled:Untitled-1'));
  Assert.AreEqual('', TTextUris.ToPath('https://x.de/a'));
end;

procedure TTextUrisTests.NormalizesPaths;
begin
  Assert.AreEqual('C:\Projekt\A.pas', TTextUris.NormalizePath('c:/Projekt/./Sub/../A.pas'));
  Assert.AreEqual('C:\Projekt\A.pas', TTextUris.NormalizePath('\\?\C:\Projekt\\A.pas'));
  Assert.AreEqual('\\server\share\A.pas', TTextUris.NormalizePath('\\?\UNC\server\share\A.pas'));
  Assert.AreEqual('/home/a/A.pas', TTextUris.NormalizePath('/home/a/b/../A.pas'));
  Assert.AreEqual('..\A.pas', TTextUris.NormalizePath('..\A.pas'));
end;

procedure TTextUrisTests.RoundTrip;
const
  Paths: array[0..3] of string = ('C:\Mein Projekt\' + #$00DC + 'bung.pas', '\\server\share\a b\#1.pas',
    '/home/a/x%y.pas', 'd:\x\.\y\..\z.inc');
var
  Path: string;
begin
  for Path in Paths do
    Assert.AreEqual(TTextUris.NormalizePath(Path), TTextUris.NormalizePath(TTextUris.ToPath(TTextUris.FromPath(Path))),
      Path);
end;

initialization
  TDUnitX.RegisterTestFixture(TTextUrisTests);

end.
