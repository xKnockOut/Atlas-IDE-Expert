unit BDLsp.Common.Documents.Uris.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDocumentUrisTests = class
  public
    [Test]
    procedure ConvertsWindowsPaths;
    [Test]
    procedure ConvertsUncAndUnixPaths;
    [Test]
    procedure DecodesUtf8;
    [Test]
    procedure IgnoresOtherSchemes;
    [Test]
    procedure NormalizesPaths;
    [Test]
    procedure SameKeyForAllSpellings;
    [Test]
    procedure KeyUsesCanonicalizer;
    [Test]
    procedure KeepsCaseOfUnixPaths;
  end;

implementation

uses
  System.SysUtils,
  BDLsp.Common.Documents.Uris;

{ TDocumentUrisTests }

procedure TDocumentUrisTests.ConvertsWindowsPaths;
begin
  Assert.AreEqual('c:\Projekt\A B.pas', TDocumentUris.ToPath('file:///c%3A/Projekt/A%20B.pas'));
  Assert.AreEqual('C:\Projekt\A.pas', TDocumentUris.ToPath('file:///C:/Projekt/A.pas'));
  Assert.AreEqual('file:///c%3A/Projekt/A%20B.pas', TDocumentUris.FromPath('C:\Projekt\A B.pas'));
  Assert.IsTrue(TDocumentUris.SameFile('file:///c%3A/Projekt/A.pas', 'file:///C:/projekt/a.pas'));
end;

procedure TDocumentUrisTests.ConvertsUncAndUnixPaths;
begin
  Assert.AreEqual('\\server\share\A.pas', TDocumentUris.ToPath('file://server/share/A.pas'));
  Assert.AreEqual('file://server/share/A.pas', TDocumentUris.FromPath('\\server\share\A.pas'));
  Assert.AreEqual('/home/a/A.pas', TDocumentUris.ToPath('file:///home/a/A.pas'));
end;

procedure TDocumentUrisTests.DecodesUtf8;
begin
  Assert.AreEqual('c:\Gr' + #$00FC + 'n.pas', TDocumentUris.ToPath('file:///c%3A/Gr%C3%BCn.pas'));
  Assert.AreEqual('file:///c%3A/Gr%C3%BCn.pas', TDocumentUris.FromPath('c:\Gr' + #$00FC + 'n.pas'));
end;

procedure TDocumentUrisTests.IgnoresOtherSchemes;
begin
  Assert.AreEqual('', TDocumentUris.ToPath('untitled:Untitled-1'));
end;

procedure TDocumentUrisTests.NormalizesPaths;
begin
  Assert.AreEqual('C:\Projekt\A.pas', TDocumentUris.NormalizePath('c:/Projekt/./Sub/../A.pas'));
  Assert.AreEqual('C:\Projekt\A.pas', TDocumentUris.NormalizePath('\\?\C:\Projekt\\A.pas'));
  Assert.AreEqual('\\server\share\A.pas', TDocumentUris.NormalizePath('\\?\UNC\server\share\A.pas'));
  Assert.AreEqual('/home/a/A.pas', TDocumentUris.NormalizePath('/home/a/b/../A.pas'));
  Assert.AreEqual('..\A.pas', TDocumentUris.NormalizePath('..\A.pas'));
end;

procedure TDocumentUrisTests.SameKeyForAllSpellings;
var
  Key: string;
begin
  // Abnahme aus #176: kodiertes ":" und kodierter Umlaut gegen Klartext.
  Key := TDocumentUris.Key('file:///c%3A/Projekt/' + #$00C4 + '.pas');
  Assert.AreEqual(Key, TDocumentUris.Key('file:///C:/Projekt/%C3%84.pas'));
  Assert.AreEqual(Key, TDocumentUris.Key('file:///c:/projekt/%C3%A4.pas'));
  Assert.AreEqual(Key, TDocumentUris.Key('file:///C:/Projekt/Sub/../%C3%84.pas'));
  Assert.AreNotEqual(Key, TDocumentUris.Key('file:///C:/Projekt/B.pas'));
  Assert.AreEqual(TDocumentUris.Key('file://server/share/A.pas'), TDocumentUris.Key('file://SERVER/Share/a.pas'));
  Assert.AreEqual('untitled:Untitled-1', TDocumentUris.Key('untitled:Untitled-1'));
end;

procedure TDocumentUrisTests.KeyUsesCanonicalizer;
var
  Canonicalize: TPathCanonicalizer;
begin
  // Junction C:\Link zeigt auf D:\Ziel.
  Canonicalize :=
    function(const APath: string): string
    begin
      Result := StringReplace(APath, 'C:\Link', 'D:\Ziel', [rfIgnoreCase]);
    end;
  Assert.AreEqual(TDocumentUris.Key('file:///d%3A/Ziel/A.pas', Canonicalize),
    TDocumentUris.Key('file:///c%3A/Link/A.pas', Canonicalize));
  Assert.AreNotEqual(TDocumentUris.Key('file:///d%3A/Ziel/A.pas'), TDocumentUris.Key('file:///c%3A/Link/A.pas'));
end;

procedure TDocumentUrisTests.KeepsCaseOfUnixPaths;
begin
  Assert.AreNotEqual(TDocumentUris.Key('file:///home/a/A.pas'), TDocumentUris.Key('file:///home/a/a.pas'));
end;

initialization
  TDUnitX.RegisterTestFixture(TDocumentUrisTests);

end.
