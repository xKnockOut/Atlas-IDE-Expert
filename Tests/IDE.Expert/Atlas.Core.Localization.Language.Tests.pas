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
    /// <summary>Code liefert die Kennung für initialize.locale und --locale.</summary>
    [Test]
    procedure CodeFollowsLanguage;
  end;

  /// <summary>Erkennung der Sprache der IDE (#446, #1458): ohne "language" in settings.json bestimmt sie auch die
  /// Sprache der Serverbefunde.</summary>
  [TestFixture]
  TAtlasIdeLanguageTests = class
  public
    /// <summary>Die geladenen Ressourcen der IDE entscheiden vor Registry und Windows.</summary>
    [Test]
    procedure ResourcesDecideFirst;
    /// <summary>Ohne Ressourcen-DLL entscheidet der Eintrag unter Locales, auch in anderer Schreibweise.</summary>
    [Test]
    procedure RegistryCodesInAnyForm;
    /// <summary>Ohne Ressourcen und Eintrag: Windows auf Deutsch → Deutsch, sonst Englisch.</summary>
    [Test]
    procedure WindowsThenFallback;
    /// <summary>Andere Sprachen der IDE (Französisch, Japanisch) gelten als Englisch.</summary>
    [Test]
    procedure OtherLanguagesAreEnglish;
    [Test]
    procedure DescribeNamesSourceAndValue;
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
    Assert.AreEqual<TAtlasLanguage>(TAtlasLanguage.German, TAtlasStrings.Language);
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

procedure TAtlasTextLanguageTests.CodeFollowsLanguage;
var
  mSaved: TAtlasLanguage;
begin
  mSaved := TAtlasTextLanguage.Current;
  try
    TAtlasTextLanguage.Current := TAtlasLanguage.English;
    Assert.AreEqual('en', TAtlasTextLanguage.Code);
    TAtlasTextLanguage.Current := TAtlasLanguage.German;
    Assert.AreEqual('de', TAtlasTextLanguage.Code);
  finally
    TAtlasTextLanguage.Current := mSaved;
  end;
end;

{ TAtlasIdeLanguageTests }

procedure TAtlasIdeLanguageTests.ResourcesDecideFirst;
var
  mResult: TAtlasIdeLanguage;
begin
  mResult := TAtlasIdeLanguage.Decide(TArray<string>.Create('DE'), 'EN', False);
  Assert.AreEqual<TAtlasLanguage>(TAtlasLanguage.German, mResult.Language);
  Assert.AreEqual<TAtlasIdeLanguageSource>(TAtlasIdeLanguageSource.Resources, mResult.Source);
  Assert.AreEqual('DE', mResult.Value);
  mResult := TAtlasIdeLanguage.Decide(TArray<string>.Create('', 'en'), 'DE', True);
  Assert.AreEqual<TAtlasLanguage>(TAtlasLanguage.English, mResult.Language);
  Assert.AreEqual<TAtlasIdeLanguageSource>(TAtlasIdeLanguageSource.Resources, mResult.Source);
end;

procedure TAtlasIdeLanguageTests.RegistryCodesInAnyForm;
var
  mCode: string;
  mResult: TAtlasIdeLanguage;
begin
  for mCode in TArray<string>.Create('DE', 'de', ' DE ', 'DEU', 'de-DE', 'de_AT') do
  begin
    mResult := TAtlasIdeLanguage.Decide(nil, mCode, False);
    Assert.AreEqual<TAtlasLanguage>(TAtlasLanguage.German, mResult.Language, mCode);
    Assert.AreEqual<TAtlasIdeLanguageSource>(TAtlasIdeLanguageSource.Registry, mResult.Source, mCode);
  end;
  mResult := TAtlasIdeLanguage.Decide(nil, 'EN', True);
  Assert.AreEqual<TAtlasLanguage>(TAtlasLanguage.English, mResult.Language);
  Assert.AreEqual<TAtlasIdeLanguageSource>(TAtlasIdeLanguageSource.Registry, mResult.Source);
end;

procedure TAtlasIdeLanguageTests.WindowsThenFallback;
var
  mResult: TAtlasIdeLanguage;
begin
  mResult := TAtlasIdeLanguage.Decide(nil, '', True);
  Assert.AreEqual<TAtlasLanguage>(TAtlasLanguage.German, mResult.Language);
  Assert.AreEqual<TAtlasIdeLanguageSource>(TAtlasIdeLanguageSource.Windows, mResult.Source);
  mResult := TAtlasIdeLanguage.Decide(nil, ' ', False);
  Assert.AreEqual<TAtlasLanguage>(TAtlasLanguage.English, mResult.Language);
  Assert.AreEqual<TAtlasIdeLanguageSource>(TAtlasIdeLanguageSource.Fallback, mResult.Source);
  Assert.AreEqual('', mResult.Value);
end;

procedure TAtlasIdeLanguageTests.OtherLanguagesAreEnglish;
begin
  Assert.AreEqual<TAtlasLanguage>(TAtlasLanguage.English,
    TAtlasIdeLanguage.Decide(TArray<string>.Create('FR'), '', True).Language);
  Assert.AreEqual<TAtlasLanguage>(TAtlasLanguage.English, TAtlasIdeLanguage.Decide(nil, 'JA', True).Language);
end;

procedure TAtlasIdeLanguageTests.DescribeNamesSourceAndValue;
begin
  Assert.AreEqual('de (Ressourcen: DE)', TAtlasIdeLanguage.Decide(TArray<string>.Create('DE'), '', False).Describe);
  Assert.AreEqual('en (Registry Locales: EN)', TAtlasIdeLanguage.Decide(nil, 'EN', True).Describe);
  Assert.AreEqual('de (Windows)', TAtlasIdeLanguage.Decide(nil, '', True).Describe);
  Assert.AreEqual('en (Vorgabe)', TAtlasIdeLanguage.Decide(nil, '', False).Describe);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTextLanguageTests);
  TDUnitX.RegisterTestFixture(TAtlasIdeLanguageTests);

end.
