unit Atlas.Common.Monitor.Texts.Tests;

// Tests für die Texte der Oberfläche von AtlasMonitor (#1901): jeder Text in beiden Sprachen, Platzhalter.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMonitorTextsTests = class
  public
    [TearDown]
    procedure TearDown;
    [Test]
    procedure EveryTextExistsInBothLanguages;
    [Test]
    procedure FormatsPlaceholders;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Localization.Texts,
  Atlas.Common.Monitor.Texts;

procedure TMonitorTextsTests.TearDown;
begin
  TAtlasLocale.Use(TTextLanguage.German);
end;

procedure TMonitorTextsTests.EveryTextExistsInBothLanguages;
var
  mText: TMonitorText;
  mLanguage: TTextLanguage;
begin
  for mLanguage := Low(TTextLanguage) to High(TTextLanguage) do
  begin
    TAtlasLocale.Use(mLanguage);
    for mText := Low(TMonitorText) to High(TMonitorText) do
    begin
      Assert.AreNotEqual('', TMonitorTexts.Text(mText).Trim, IntToStr(Ord(mText)));
    end;
  end;
end;

procedure TMonitorTextsTests.FormatsPlaceholders;
begin
  TAtlasLocale.Use(TTextLanguage.German);
  Assert.AreEqual('Alle 3 Atlas-Server beenden?', TMonitorTexts.Fmt(TMonitorText.ConfirmStopAll, [3]));
  TAtlasLocale.Use(TTextLanguage.English);
  Assert.AreEqual('Could not stop server 42.', TMonitorTexts.Fmt(TMonitorText.StopFailed, [42]));
end;

initialization
  TDUnitX.RegisterTestFixture(TMonitorTextsTests);

end.
