unit Atlas.Common.Lsp.WinApiDocs.Tests;

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
  Atlas.Common.Lsp.WinApiDocs;

procedure TWinApiDocsTests.WinApiUnitsRecognized;
begin
  Assert.IsTrue(TWinApiDocs.IsWinApiUnit('Winapi.Windows'));
  Assert.IsTrue(TWinApiDocs.IsWinApiUnit('winapi.messages'));
  Assert.IsFalse(TWinApiDocs.IsWinApiUnit('System.SysUtils'));
end;

procedure TWinApiDocsTests.KnownFunctionLinksWideVariant;
begin
  Assert.IsTrue(TWinApiDocs.IsKnown('SendMessage'));
  Assert.AreEqual(TWinApiDocs.cApiBase + 'winuser/nf-winuser-sendmessagew', TWinApiDocs.Url('SendMessage'));
end;

procedure TWinApiDocsTests.UnknownNameUsesSearch;
begin
  Assert.IsFalse(TWinApiDocs.IsKnown('GibtEsNicht'));
  Assert.AreEqual(TWinApiDocs.cSearchBase + 'GibtEsNicht', TWinApiDocs.Url('GibtEsNicht'));
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
  mText: string;
begin
  mText := TWinApiDocs.HoverText('SetWindowLong');
  Assert.IsTrue(StartsStr('[Microsoft-Dokumentation](', mText), mText);
  Assert.IsTrue(Pos('SetWindowLongPtr', mText) > 0, mText);
end;

procedure TWinApiDocsTests.KnownUrlsWellFormed;
var
  mUrl: string;
begin
  Assert.IsTrue(Length(TWinApiDocs.KnownUrls) > 0);
  for mUrl in TWinApiDocs.KnownUrls do
  begin
    Assert.IsTrue(StartsStr(TWinApiDocs.cApiBase, mUrl), mUrl);
    Assert.AreEqual(0, Pos(' ', mUrl), mUrl);
    Assert.AreEqual(LowerCase(mUrl), mUrl);
    Assert.IsTrue(ContainsStr(mUrl, '/nf-') or ContainsStr(mUrl, '/ns-'), mUrl);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TWinApiDocsTests);

end.
