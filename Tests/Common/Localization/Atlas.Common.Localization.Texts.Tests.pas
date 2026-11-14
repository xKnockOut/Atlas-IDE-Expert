unit Atlas.Common.Localization.Texts.Tests;

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Localization.Texts;

type
  [TestFixture]
  TLocalizationTextsTests = class
  private
    FSaved: TTextLanguage;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure TextFollowsLanguage;
    [Test]
    procedure FmtFillsPlaceholders;
    [Test]
    procedure ParseAcceptsRegionAndCase;
    [Test]
    procedure ParseRejectsOtherLanguages;
    /// <summary>Einstellung vor Client, Client vor Englisch (#1458).</summary>
    [Test]
    procedure ResolveOrder;
    [Test]
    procedure PlaceholdersFollowFormat;
    [Test]
    procedure ProblemsFindMissingAndMismatch;
    /// <summary>Alle angemeldeten Tabellen sind vollständig übersetzt: Fehlender Eintrag = Übersetzungsfehler.
    /// </summary>
    [Test]
    procedure AllTablesComplete;
  end;

implementation

uses
  System.SysUtils;

procedure TLocalizationTextsTests.Setup;
begin
  FSaved := TAtlasLocale.Language;
end;

procedure TLocalizationTextsTests.TearDown;
begin
  TAtlasLocale.Use(FSaved);
end;

function Pair(const ADe, AEn: string): TAtlasText;
begin
  Result.De := ADe;
  Result.En := AEn;
end;

procedure TLocalizationTextsTests.TextFollowsLanguage;
var
  mText: TAtlasText;
begin
  mText := Pair('Datei fehlt', 'File missing');
  TAtlasLocale.Use(TTextLanguage.German);
  Assert.AreEqual('Datei fehlt', mText.Text);
  TAtlasLocale.Use(TTextLanguage.English);
  Assert.AreEqual('File missing', mText.Text);
  Assert.AreEqual('Datei fehlt', mText.TextIn(TTextLanguage.German));
end;

procedure TLocalizationTextsTests.FmtFillsPlaceholders;
var
  mText: TAtlasText;
begin
  mText := Pair('%s fehlt in %d Units', '%s is missing in %d units');
  TAtlasLocale.Use(TTextLanguage.English);
  Assert.AreEqual('X is missing in 2 units', mText.Fmt(['X', 2]));
  TAtlasLocale.Use(TTextLanguage.German);
  Assert.AreEqual('X fehlt in 2 Units', mText.Fmt(['X', 2]));
end;

procedure TLocalizationTextsTests.ParseAcceptsRegionAndCase;
var
  mLanguage: TTextLanguage;
begin
  Assert.IsTrue(TAtlasLocale.TryParse('de', mLanguage));
  Assert.AreEqual<TTextLanguage>(TTextLanguage.German, mLanguage);
  Assert.IsTrue(TAtlasLocale.TryParse(' DE-at ', mLanguage));
  Assert.AreEqual<TTextLanguage>(TTextLanguage.German, mLanguage);
  Assert.IsTrue(TAtlasLocale.TryParse('de_CH', mLanguage));
  Assert.AreEqual<TTextLanguage>(TTextLanguage.German, mLanguage);
  Assert.IsTrue(TAtlasLocale.TryParse('en-US', mLanguage));
  Assert.AreEqual<TTextLanguage>(TTextLanguage.English, mLanguage);
  Assert.AreEqual('de', TAtlasLocale.Code(TTextLanguage.German));
  Assert.AreEqual('en', TAtlasLocale.Code(TTextLanguage.English));
end;

procedure TLocalizationTextsTests.ParseRejectsOtherLanguages;
var
  mLanguage: TTextLanguage;
begin
  Assert.IsFalse(TAtlasLocale.TryParse('fr-FR', mLanguage));
  Assert.IsFalse(TAtlasLocale.TryParse('', mLanguage));
  Assert.IsFalse(TAtlasLocale.TryParse('deu', mLanguage));
end;

procedure TLocalizationTextsTests.ResolveOrder;
begin
  Assert.AreEqual<TTextLanguage>(TTextLanguage.German, TAtlasLocale.Resolve('de', 'en-US'));
  Assert.AreEqual<TTextLanguage>(TTextLanguage.English, TAtlasLocale.Resolve('en', 'de'));
  Assert.AreEqual<TTextLanguage>(TTextLanguage.German, TAtlasLocale.Resolve('', 'de-DE'));
  Assert.AreEqual<TTextLanguage>(TTextLanguage.English, TAtlasLocale.Resolve('', 'ja'));
  Assert.AreEqual<TTextLanguage>(TTextLanguage.English, TAtlasLocale.Resolve('', ''));
end;

procedure TLocalizationTextsTests.PlaceholdersFollowFormat;
begin
  Assert.AreEqual('', TAtlasTextTables.Placeholders('100 %% sicher'));
  Assert.AreEqual('0:s 1:d', TAtlasTextTables.Placeholders('%s hat %d'));
  // Andere Reihenfolge über Indizes ist gleichwertig.
  Assert.AreEqual(TAtlasTextTables.Placeholders('%s hat %d'), TAtlasTextTables.Placeholders('%1:d in %0:s'));
  Assert.AreEqual('0:s', TAtlasTextTables.Placeholders('%s oder %0:s'));
  Assert.AreEqual('0:d', TAtlasTextTables.Placeholders('%-5d'));
  Assert.AreEqual('0:f', TAtlasTextTables.Placeholders('%.2f'));
end;

procedure TLocalizationTextsTests.ProblemsFindMissingAndMismatch;
var
  mTable: TAtlasTextTable;
begin
  mTable.Name := 'Probe';
  mTable.Texts := [Pair('Gut %s', 'Good %s')];
  Assert.AreEqual(Integer(0), Integer(Length(TAtlasTextTables.Problems(mTable))));
  mTable.Texts := [Pair('Gut %s', 'Good %s'), Pair('Fehlt', ''), Pair('%s und %d', '%s and %s')];
  Assert.AreEqual(Integer(2), Integer(Length(TAtlasTextTables.Problems(mTable))));
  mTable.Texts := nil;
end;

procedure TLocalizationTextsTests.AllTablesComplete;
var
  mTable: TAtlasTextTable;
  mProblems: TArray<string>;
begin
  mProblems := nil;
  for mTable in TAtlasTextTables.Tables do
  begin
    mProblems := mProblems + TAtlasTextTables.Problems(mTable);
  end;
  Assert.AreEqual('', string.Join(sLineBreak, mProblems));
end;

initialization
  TDUnitX.RegisterTestFixture(TLocalizationTextsTests);

end.
