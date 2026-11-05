unit Atlas.Core.Localization.Language.Tests;

// Tests für die Sprache der Plugin-Texte und die Texttabellen der Units (#1458).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasTextLanguageTests = class
  public
    /// <summary>Jede angemeldete Tabelle: beide Sprachen gleich lang, kein leerer Text, gleiche Platzhalter.
    /// </summary>
    [Test]
    procedure EveryTableIsCompleteInBothLanguages;
    /// <summary>TAtlasStrings.Language und TAtlasTextLanguage.Current sind dieselbe Sprache.</summary>
    [Test]
    procedure UiLanguageIsTheCoreLanguage;
    [Test]
    procedure AddTableKeepsTheTexts;
    /// <summary>Feste Namen aus Core folgen der Sprache: Kodierung, Zeilenende, Neuladen, Funktion, Doku.</summary>
    [Test]
    procedure CoreNamesFollowLanguage;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Documentation.Layout,
  Atlas.Core.Files.ExternalChanges,
  Atlas.Core.Files.Format,
  Atlas.Core.Localization.Language,
  Atlas.UI.Strings,
  Atlas.UI.Strings.Tests;

procedure TAtlasTextLanguageTests.EveryTableIsCompleteInBothLanguages;
var
  mTable: TAtlasTextTableEntry;
  mIndex: Integer;
begin
  for mTable in TAtlasTextLanguage.Tables do
  begin
    Assert.AreEqual(Integer(Length(mTable.German)), Integer(Length(mTable.English)), mTable.Name);
    for mIndex := 0 to High(mTable.German) do
    begin
      AssertTextPair(mTable.German[mIndex], mTable.English[mIndex], mIndex);
    end;
  end;
end;

procedure TAtlasTextLanguageTests.UiLanguageIsTheCoreLanguage;
var
  mSaved: TAtlasLanguage;
begin
  mSaved := TAtlasTextLanguage.Current;
  try
    TAtlasStrings.Language := TAtlasLanguage.English;
    Assert.IsTrue(TAtlasTextLanguage.IsEnglish);
    TAtlasTextLanguage.Current := TAtlasLanguage.German;
    Assert.IsTrue(TAtlasStrings.Language = TAtlasLanguage.German);
  finally
    TAtlasTextLanguage.Current := mSaved;
  end;
end;

procedure TAtlasTextLanguageTests.AddTableKeepsTheTexts;
var
  mBefore: Integer;
  mTable: TAtlasTextTableEntry;
begin
  mBefore := Length(TAtlasTextLanguage.Tables);
  TAtlasTextLanguage.AddTable('Probe', ['Datei %s'], ['File %s']);
  Assert.AreEqual(mBefore + 1, Integer(Length(TAtlasTextLanguage.Tables)));
  mTable := TAtlasTextLanguage.Tables[mBefore];
  Assert.AreEqual('Probe', mTable.Name);
  Assert.AreEqual('Datei %s', mTable.German[0]);
  Assert.AreEqual('File %s', mTable.English[0]);
end;

procedure TAtlasTextLanguageTests.CoreNamesFollowLanguage;
var
  mSaved: TAtlasLanguage;
begin
  mSaved := TAtlasTextLanguage.Current;
  try
    TAtlasTextLanguage.Current := TAtlasLanguage.English;
    Assert.AreEqual('UTF-8 without BOM', TAtlasFileFormats.EncodingText(TAtlasFileEncoding.Utf8));
    Assert.AreEqual('mixed line breaks', TAtlasFileFormats.LineBreakText(TAtlasLineBreak.Mixed));
    Assert.AreEqual('deleted', TAtlasExternalChanges.ActionText(TAtlasReloadAction.Deleted));
    Assert.AreEqual('Sticky scroll', TAtlasGuard.FeatureName(TAtlasFeature.StickyScroll));
    Assert.AreEqual(TAtlasDocLabels.ForLanguage(TAtlasLanguage.English).Params, TAtlasDocLabels.Current.Params);
    TAtlasTextLanguage.Current := TAtlasLanguage.German;
    Assert.AreEqual('UTF-8 ohne BOM', TAtlasFileFormats.EncodingText(TAtlasFileEncoding.Utf8));
    Assert.AreEqual('gelöscht', TAtlasExternalChanges.ActionText(TAtlasReloadAction.Deleted));
    Assert.AreEqual(TAtlasDocLabels.German.Params, TAtlasDocLabels.Current.Params);
  finally
    TAtlasTextLanguage.Current := mSaved;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTextLanguageTests);

end.
