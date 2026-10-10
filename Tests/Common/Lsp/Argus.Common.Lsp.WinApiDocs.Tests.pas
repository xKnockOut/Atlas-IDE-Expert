unit Argus.Common.Lsp.WinApiDocs.Tests;

// Tests für die Microsoft-Links im Hover bei Windows-API-Funktionen (#120).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TWinApiDocsTests = class
  public
    [Test]
    procedure WinApiUnitsRecognized;
    [Test]
    procedure KnownFunctionLinksWideVariant;
    [Test]
    procedure UnknownNameUsesSearch;
    [Test]
    procedure PtrVariantForSetWindowLong;
    [Test]
    procedure HoverTextNamesReplacement;
    [Test]
    procedure KnownUrlsWellFormed;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Argus.Common.Lsp.WinApiDocs;

procedure TWinApiDocsTests.WinApiUnitsRecognized;
begin
  Assert.IsTrue(TWinApiDocs.IsWinApiUnit('Winapi.Windows'));
  Assert.IsTrue(TWinApiDocs.IsWinApiUnit('winapi.messages'));
  Assert.IsFalse(TWinApiDocs.IsWinApiUnit('System.SysUtils'));
end;

procedure TWinApiDocsTests.KnownFunctionLinksWideVariant;
begin
  Assert.IsTrue(TWinApiDocs.IsKnown('SendMessage'));
  Assert.AreEqual(TWinApiDocs.ApiBase + 'winuser/nf-winuser-sendmessagew', TWinApiDocs.Url('SendMessage'));
end;

procedure TWinApiDocsTests.UnknownNameUsesSearch;
begin
  Assert.IsFalse(TWinApiDocs.IsKnown('GibtEsNicht'));
  Assert.AreEqual(TWinApiDocs.SearchBase + 'GibtEsNicht', TWinApiDocs.Url('GibtEsNicht'));
end;

procedure TWinApiDocsTests.PtrVariantForSetWindowLong;
begin
  Assert.AreEqual('SetWindowLongPtr', TWinApiDocs.PtrVariant('SetWindowLong'));
  Assert.AreEqual('SetWindowLongPtr', TWinApiDocs.PtrVariant('SetWindowLongW'));
  Assert.AreEqual('', TWinApiDocs.PtrVariant('SendMessage'));
  Assert.IsTrue(Length(TWinApiDocs.PtrVariants) >= 4);
end;

procedure TWinApiDocsTests.HoverTextNamesReplacement;
var
  Text: string;
begin
  Text := TWinApiDocs.HoverText('SetWindowLong');
  Assert.IsTrue(StartsStr('[Microsoft-Dokumentation](', Text), Text);
  Assert.IsTrue(Pos('SetWindowLongPtr', Text) > 0, Text);
end;

procedure TWinApiDocsTests.KnownUrlsWellFormed;
var
  Url: string;
begin
  Assert.IsTrue(Length(TWinApiDocs.KnownUrls) > 0);
  for Url in TWinApiDocs.KnownUrls do
  begin
    Assert.IsTrue(StartsStr(TWinApiDocs.ApiBase, Url), Url);
    Assert.IsTrue(Pos(' ', Url) = 0, Url);
    Assert.AreEqual(LowerCase(Url), Url);
    Assert.IsTrue(ContainsStr(Url, '/nf-') or ContainsStr(Url, '/ns-'), Url);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TWinApiDocsTests);

end.
