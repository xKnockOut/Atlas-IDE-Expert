unit Atlas.Common.Rules.Catalog.Tests;

// Tests für den Regelkatalog (#145): Lesen, Übersetzungen, ungültige Einträge
// und Abgleich mit den eingebauten Regeln; Gruppen und Optionen (#909).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TRuleCatalogTests = class
  public
    /// <summary>Legt die geteilten Kataloge (englisch und deutsch) einmal an: Sie leben bis zum Prozessende,
    /// der Leckmonitor zählte ihren ersten Gebrauch sonst im Test.</summary>
    [SetupFixture]
    procedure CreateSharedCatalogs;
    [Test]
    procedure ReadsBaseEntry;
    [Test]
    procedure OverlayReplacesNameAndDescriptionOnly;
    [Test]
    procedure OverlayIgnoresUnknownRules;
    [Test]
    procedure RejectsEntryWithoutId;
    [Test]
    procedure RejectsUnknownCategory;
    [Test]
    procedure RejectsUnknownSeverity;
    [Test]
    procedure RejectsDuplicateId;
    [Test]
    procedure HelpUriPointsToAnchor;
    [Test]
    procedure ExplanationHasExamplesAndLink;
    /// <summary>#1458: Erklärung und Katalog in der Sprache der Texte.</summary>
    [Test]
    procedure ExplanationFollowsLanguage;
    [Test]
    procedure LocalizedCatalogFollowsLanguage;
    [Test]
    procedure BuiltinRulesAreInCatalogWithSameSeverity;
    [Test]
    procedure EmbeddedCatalogIsCompleteInGerman;
    [Test]
    procedure UnknownLanguageHasNoOverlay;
    [Test]
    procedure ReadsGroupAndOptions;
    [Test]
    procedure GroupFollowsCategoryWithoutField;
    [Test]
    procedure RejectsUnknownGroup;
    [Test]
    procedure RejectsOptionWithUnknownType;
    [Test]
    procedure OverlayTranslatesOptionDescriptions;
    [Test]
    procedure EveryEmbeddedRuleHasExactlyOneGroup;
    [Test]
    procedure GroupNamesRoundTrip;
    [Test]
    procedure SharedCatalogIsReadOnce;
    [Test]
    procedure ReadsCompilerCodes;
    [Test]
    procedure ReadsOverriddenBy;
    /// <summary>#1352: sichere Sammelkorrektur.</summary>
    [Test]
    procedure ReadsSafeFix;
    /// <summary>#145: Jede Regel des eingebetteten Katalogs nennt "category" und "safeFix" ausdrücklich.</summary>
    [Test]
    procedure EveryEmbeddedRuleNamesCategoryAndSafeFix;
    /// <summary>#145: "profiles" (standard, strict); ohne standard ist die Regel experimentell.</summary>
    [Test]
    procedure ReadsProfiles;
    [Test]
    procedure RejectsInvalidProfiles;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Checker,
  Atlas.Common.Rules.Engine,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Localization.Texts,
  Atlas.Common.Rules.Catalog,
  Atlas.Common.Rules.Catalog.Data;

const
  cBase = '{"rules":[{"id":"a-rule","name":"A rule","category":"code-smell","severity":"warning",' +
    '"description":"Text","bad":"X;","good":"Y;"}]}';

procedure ExpectCatalogError(const AJson: string);
var
  mRaised: Boolean;
begin
  mRaised := False;
  try
    TRuleCatalog.Create(AJson).Free;
  except
    on ERuleCatalog do
      mRaised := True;
  end;
  Assert.IsTrue(mRaised, AJson);
end;

{ TRuleCatalogTests }

procedure TRuleCatalogTests.ReadsBaseEntry;
var
  mCatalog: TRuleCatalog;
  mEntry: TRuleCatalogEntry;
begin
  mCatalog := TRuleCatalog.Create(cBase);
  try
    Assert.IsTrue(mCatalog.TryFind('A-RULE', mEntry));
    Assert.AreEqual('A rule', mEntry.Name);
    Assert.AreEqual(Ord(TRuleCategory.CodeSmell), Ord(mEntry.Category));
    Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(mEntry.DefaultSeverity));
    Assert.AreEqual('Text', mEntry.Description);
    Assert.AreEqual('X;', mEntry.Bad);
    Assert.AreEqual('Y;', mEntry.Good);
    Assert.IsFalse(mCatalog.TryFind('other', mEntry));
  finally
    mCatalog.Free;
  end;
end;

procedure TRuleCatalogTests.OverlayReplacesNameAndDescriptionOnly;
var
  mCatalog: TRuleCatalog;
  mEntry: TRuleCatalogEntry;
begin
  mCatalog := TRuleCatalog.Create(cBase, '{"rules":[{"id":"a-rule","name":"Eine Regel","description":"Beschreibung"}]}');
  try
    Assert.IsTrue(mCatalog.TryFind('a-rule', mEntry));
    Assert.AreEqual('Eine Regel', mEntry.Name);
    Assert.AreEqual('Beschreibung', mEntry.Description);
    Assert.AreEqual(Ord(TRuleCategory.CodeSmell), Ord(mEntry.Category));
    Assert.AreEqual('X;', mEntry.Bad);
  finally
    mCatalog.Free;
  end;
end;

procedure TRuleCatalogTests.OverlayIgnoresUnknownRules;
var
  mCatalog: TRuleCatalog;
begin
  mCatalog := TRuleCatalog.Create(cBase, '{"rules":[{"id":"missing","name":"Fehlt"}]}');
  try
    Assert.AreEqual<NativeInt>(1, Length(mCatalog.Entries));
  finally
    mCatalog.Free;
  end;
end;

procedure TRuleCatalogTests.RejectsEntryWithoutId;
begin
  ExpectCatalogError('{"rules":[{"name":"x","category":"bug","severity":"error"}]}');
end;

procedure TRuleCatalogTests.RejectsUnknownCategory;
begin
  ExpectCatalogError('{"rules":[{"id":"x","category":"style","severity":"error"}]}');
end;

procedure TRuleCatalogTests.RejectsUnknownSeverity;
begin
  ExpectCatalogError('{"rules":[{"id":"x","category":"bug","severity":"fatal"}]}');
end;

procedure TRuleCatalogTests.RejectsDuplicateId;
begin
  ExpectCatalogError('{"rules":[{"id":"x","category":"bug","severity":"error"},' +
    '{"id":"X","category":"bug","severity":"error"}]}');
end;

procedure TRuleCatalogTests.HelpUriPointsToAnchor;
begin
  Assert.AreEqual(cRuleDocumentationBaseUri + 'bidi-control', TRuleCatalog.HelpUri('Bidi-Control'));
end;

procedure TRuleCatalogTests.BuiltinRulesAreInCatalogWithSameSeverity;
var
  mCatalog: TRuleCatalog;
  mEntry: TRuleCatalogEntry;
  mRule: IRule;
begin
  mCatalog := TRuleCatalog.Create(RuleCatalogBaseJson);
  try
    for mRule in BuiltinRules do
    begin
      Assert.IsTrue(mCatalog.TryFind(mRule.Descriptor.Id, mEntry), mRule.Descriptor.Id);
      Assert.AreEqual(Ord(mRule.Descriptor.DefaultSeverity), Ord(mEntry.DefaultSeverity), mRule.Descriptor.Id);
    end;
    Assert.IsTrue(mCatalog.TryFind(TFileChecker.SyntaxDescriptor.Id, mEntry));
    Assert.IsTrue(mCatalog.TryFind(cUnusedSuppressionRuleId, mEntry));
  finally
    mCatalog.Free;
  end;
end;

procedure TRuleCatalogTests.EmbeddedCatalogIsCompleteInGerman;
var
  mEnglish, mGerman: TRuleCatalog;
  mEntry, mTranslated: TRuleCatalogEntry;
begin
  mEnglish := TRuleCatalog.Create(RuleCatalogBaseJson);
  mGerman := TRuleCatalog.Create(RuleCatalogBaseJson, RuleCatalogOverlayJson('de'));
  try
    for mEntry in mEnglish.Entries do
    begin
      Assert.IsTrue(mGerman.TryFind(mEntry.Id, mTranslated));
      Assert.AreNotEqual(mEntry.Description, mTranslated.Description, mEntry.Id);
      Assert.AreNotEqual('', mEntry.Bad, mEntry.Id);
      Assert.AreNotEqual('', mEntry.Good, mEntry.Id);
    end;
  finally
    mGerman.Free;
    mEnglish.Free;
  end;
end;

procedure TRuleCatalogTests.UnknownLanguageHasNoOverlay;
begin
  Assert.AreEqual('', RuleCatalogOverlayJson('xx'));
end;

procedure TRuleCatalogTests.ExplanationHasExamplesAndLink;
var
  mCatalog: TRuleCatalog;
  mEntry: TRuleCatalogEntry;
begin
  // #300: /explain zeigt Beschreibung, falsch/richtig und den Link.
  mCatalog := TRuleCatalog.Create(cBase);
  try
    Assert.IsTrue(mCatalog.TryFind('a-rule', mEntry));
    Assert.AreEqual('a-rule: A rule'#10'Text'#10#10'Falsch:'#10'X;'#10#10'Richtig:'#10'Y;'#10#10'Mehr: ' +
      TRuleCatalog.HelpUri('a-rule'), TRuleCatalog.Explanation(mEntry, #10));
    mEntry.Bad := '';
    mEntry.Good := '';
    Assert.AreEqual('a-rule: A rule'#10'Text'#10#10'Mehr: ' + TRuleCatalog.HelpUri('a-rule'),
      TRuleCatalog.Explanation(mEntry, #10));
  finally
    mCatalog.Free;
  end;
end;

procedure TRuleCatalogTests.ExplanationFollowsLanguage;
var
  mCatalog: TRuleCatalog;
  mEntry: TRuleCatalogEntry;
  mSaved: TTextLanguage;
begin
  mSaved := TAtlasLocale.Language;
  mCatalog := TRuleCatalog.Create(cBase);
  try
    Assert.IsTrue(mCatalog.TryFind('a-rule', mEntry));
    mEntry.CompilerCodes := ['W1036'];
    mEntry.OverriddenBy := ['x', 'y'];
    TAtlasLocale.Use(TTextLanguage.English);
    Assert.AreEqual('a-rule: A rule'#10'Text'#10#10'Wrong:'#10'X;'#10#10'Right:'#10'Y;'#10#10 +
      'Corresponds to compiler message W1036.'#10#10'Silent while x or y is on.'#10#10'More: ' +
      TRuleCatalog.HelpUri('a-rule'), TRuleCatalog.Explanation(mEntry, #10));
    TAtlasLocale.Use(TTextLanguage.German);
    Assert.IsTrue(Pos('Schweigt, solange x oder y an ist.', TRuleCatalog.Explanation(mEntry, #10)) > 0);
  finally
    TAtlasLocale.Use(mSaved);
    mCatalog.Free;
  end;
end;

procedure TRuleCatalogTests.CreateSharedCatalogs;
var
  mSaved: TTextLanguage;
begin
  mSaved := TAtlasLocale.Language;
  try
    TAtlasLocale.Use(TTextLanguage.German);
    TRuleCatalog.Localized;
    TRuleCatalog.Shared;
  finally
    TAtlasLocale.Use(mSaved);
  end;
end;

procedure TRuleCatalogTests.LocalizedCatalogFollowsLanguage;
var
  mGerman, mEnglish: TRuleCatalogEntry;
  mSaved: TTextLanguage;
begin
  mSaved := TAtlasLocale.Language;
  try
    TAtlasLocale.Use(TTextLanguage.English);
    Assert.AreSame(TRuleCatalog.Shared, TRuleCatalog.Localized);
    Assert.IsTrue(TRuleCatalog.Localized.TryFind('empty-except', mEnglish));
    TAtlasLocale.Use(TTextLanguage.German);
    Assert.IsTrue(TRuleCatalog.Localized.TryFind('empty-except', mGerman));
    Assert.AreNotEqual(mEnglish.Name, mGerman.Name);
  finally
    TAtlasLocale.Use(mSaved);
  end;
end;

procedure TRuleCatalogTests.ReadsGroupAndOptions;
var
  mCatalog: TRuleCatalog;
  mEntry: TRuleCatalogEntry;
begin
  mCatalog := TRuleCatalog.Create('{"rules":[{"id":"m","name":"M","category":"code-smell","severity":"hint",' +
    '"group":"style","description":"D","bad":"B","good":"G","options":[{"name":"max","type":"integer",' +
    '"default":40,"description":"Limit"},{"name":"names","type":"string-list","default":["Count"],' +
    '"description":"Names"},{"name":"flag","type":"boolean","description":"No default"}]}]}');
  try
    Assert.IsTrue(mCatalog.TryFind('m', mEntry));
    Assert.AreEqual(Ord(TRuleGroup.Style), Ord(mEntry.Group));
    Assert.AreEqual(3, Integer(Length(mEntry.Options)));
    Assert.AreEqual('max', mEntry.Options[0].Name);
    Assert.AreEqual('integer', mEntry.Options[0].Kind);
    Assert.AreEqual('40', mEntry.Options[0].DefaultJson);
    Assert.AreEqual('Limit', mEntry.Options[0].Description);
    Assert.AreEqual('["Count"]', mEntry.Options[1].DefaultJson);
    Assert.AreEqual('', mEntry.Options[2].DefaultJson);
    Assert.AreEqual(0, Integer(Length(mEntry.Options[0].Columns)));
  finally
    mCatalog.Free;
  end;
  // Tabelle (#1133): Spalten mit Listen.
  mCatalog := TRuleCatalog.Create('{"rules":[{"id":"t","category":"code-smell","severity":"warning","options":[' +
    '{"name":"symbols","type":"object-list","columns":[{"name":"name"},{"name":"units","list":true}],' +
    '"default":[],"description":"Table"}]}]}');
  try
    Assert.IsTrue(mCatalog.TryFind('t', mEntry));
    Assert.AreEqual('object-list', mEntry.Options[0].Kind);
    Assert.AreEqual(2, Integer(Length(mEntry.Options[0].Columns)));
    Assert.AreEqual('units', mEntry.Options[0].Columns[1].Name);
    Assert.IsFalse(mEntry.Options[0].Columns[0].List);
    Assert.IsTrue(mEntry.Options[0].Columns[1].List);
  finally
    mCatalog.Free;
  end;
end;

procedure TRuleCatalogTests.GroupFollowsCategoryWithoutField;
var
  mCatalog: TRuleCatalog;
  mEntry: TRuleCatalogEntry;
begin
  mCatalog := TRuleCatalog.Create('{"rules":[{"id":"a","category":"bug","severity":"error"},' +
    '{"id":"b","category":"vulnerability","severity":"error"},{"id":"c","category":"security-hotspot",' +
    '"severity":"hint"},{"id":"d","category":"code-smell","severity":"hint"}]}');
  try
    Assert.IsTrue(mCatalog.TryFind('a', mEntry));
    Assert.AreEqual(Ord(TRuleGroup.FindBugs), Ord(mEntry.Group));
    Assert.IsTrue(mCatalog.TryFind('b', mEntry));
    Assert.AreEqual(Ord(TRuleGroup.Security), Ord(mEntry.Group));
    Assert.IsTrue(mCatalog.TryFind('c', mEntry));
    Assert.AreEqual(Ord(TRuleGroup.Security), Ord(mEntry.Group));
    Assert.IsTrue(mCatalog.TryFind('d', mEntry));
    Assert.AreEqual(Ord(TRuleGroup.Style), Ord(mEntry.Group));
    Assert.AreEqual(0, Integer(Length(mEntry.Options)));
  finally
    mCatalog.Free;
  end;
end;

procedure TRuleCatalogTests.RejectsUnknownGroup;
begin
  ExpectCatalogError('{"rules":[{"id":"x","category":"bug","severity":"error","group":"misc"}]}');
end;

procedure TRuleCatalogTests.ReadsCompilerCodes;
var
  mCatalog: TRuleCatalog;
  mEntry: TRuleCatalogEntry;
begin
  mCatalog := TRuleCatalog.Create('{"rules":[{"id":"x","category":"code-smell","severity":"hint",' +
    '"compilerCodes":["F2069","W1036"]},{"id":"y","category":"bug","severity":"error"}]}');
  try
    Assert.IsTrue(mCatalog.TryFind('x', mEntry));
    Assert.AreEqual('F2069,W1036', string.Join(',', mEntry.CompilerCodes));
    Assert.IsTrue(Pos('Entspricht der Compilermeldung F2069, W1036.', TRuleCatalog.Explanation(mEntry, #10)) > 0);
    Assert.IsTrue(mCatalog.TryFind('y', mEntry));
    Assert.AreEqual(0, Integer(Length(mEntry.CompilerCodes)));
    Assert.IsFalse(Pos('Compilermeldung', TRuleCatalog.Explanation(mEntry, #10)) > 0);
  finally
    mCatalog.Free;
  end;
  // Eingebauter Katalog: line-length entspricht F2069 (#938).
  Assert.IsTrue(TRuleCatalog.Shared.TryFind('line-length', mEntry));
  Assert.AreEqual('F2069', string.Join(',', mEntry.CompilerCodes));
  // Delphi 13 meldet W1008, die Delphi-Hilfe nennt X1008 (#1382).
  Assert.IsTrue(TRuleCatalog.Shared.TryFind('hresult-integer-mix', mEntry));
  Assert.AreEqual('W1008', string.Join(',', mEntry.CompilerCodes));
  // X-Codes (Vorab-Prüfungen des Compilers, #1040) sind gültig.
  mCatalog := TRuleCatalog.Create('{"rules":[{"id":"x","category":"bug","severity":"warning",' +
    '"compilerCodes":["X1008"]}]}');
  try
    Assert.IsTrue(mCatalog.TryFind('x', mEntry));
    Assert.AreEqual('X1008', string.Join(',', mEntry.CompilerCodes));
  finally
    mCatalog.Free;
  end;
  ExpectCatalogError('{"rules":[{"id":"x","category":"bug","severity":"error","compilerCodes":"F2069"}]}');
  ExpectCatalogError('{"rules":[{"id":"x","category":"bug","severity":"error","compilerCodes":["Y2069"]}]}');
  ExpectCatalogError('{"rules":[{"id":"x","category":"bug","severity":"error","compilerCodes":["F206"]}]}');
  ExpectCatalogError('{"rules":[{"id":"x","category":"bug","severity":"error","compilerCodes":[2069]}]}');
  // Stufe der Compilerregeln (#1024).
  mCatalog := TRuleCatalog.Create('{"rules":[{"id":"x","category":"bug","severity":"error","level":"T"},' +
    '{"id":"y","category":"bug","severity":"error"}]}');
  try
    Assert.IsTrue(mCatalog.TryFind('x', mEntry));
    Assert.AreEqual('T', mEntry.Level);
    Assert.IsTrue(mCatalog.TryFind('y', mEntry));
    Assert.AreEqual('', mEntry.Level);
  finally
    mCatalog.Free;
  end;
  ExpectCatalogError('{"rules":[{"id":"x","category":"bug","severity":"error","level":"C"}]}');
  Assert.IsTrue(TRuleCatalog.Shared.TryFind('argument-count-mismatch', mEntry));
  Assert.AreEqual('T', mEntry.Level);
  Assert.IsTrue(TRuleCatalog.Shared.TryFind('duplicate-case-label', mEntry));
  Assert.AreEqual('B', mEntry.Level);
end;

procedure TRuleCatalogTests.ReadsOverriddenBy;
var
  mCatalog: TRuleCatalog;
  mEntry: TRuleCatalogEntry;
begin
  mCatalog := TRuleCatalog.Create('{"rules":[{"id":"x","category":"code-smell","severity":"hint",' +
    '"overriddenBy":["y"]},{"id":"y","category":"code-smell","severity":"hint"}]}');
  try
    Assert.IsTrue(mCatalog.TryFind('x', mEntry));
    Assert.AreEqual('y', string.Join(',', mEntry.OverriddenBy));
    Assert.IsTrue(Pos('Schweigt, solange y an ist.', TRuleCatalog.Explanation(mEntry, #10)) > 0);
    Assert.IsTrue(mCatalog.TryFind('y', mEntry));
    Assert.AreEqual(0, Integer(Length(mEntry.OverriddenBy)));
  finally
    mCatalog.Free;
  end;
  // Eingebauter Katalog: redundant-begin-end schweigt bei missing-begin-end (#1025).
  Assert.IsTrue(TRuleCatalog.Shared.TryFind('redundant-begin-end', mEntry));
  Assert.AreEqual('missing-begin-end', string.Join(',', mEntry.OverriddenBy));
  ExpectCatalogError('{"rules":[{"id":"x","category":"bug","severity":"error","overriddenBy":"y"}]}');
  ExpectCatalogError('{"rules":[{"id":"x","category":"bug","severity":"error","overriddenBy":[1]}]}');
  ExpectCatalogError('{"rules":[{"id":"x","category":"bug","severity":"error","overriddenBy":[""]}]}');
end;

procedure TRuleCatalogTests.ReadsSafeFix;
var
  mCatalog: TRuleCatalog;
  mEntry: TRuleCatalogEntry;
begin
  mCatalog := TRuleCatalog.Create('{"rules":[{"id":"x","category":"code-smell","severity":"hint","safeFix":true},' +
    '{"id":"y","category":"code-smell","severity":"hint"}]}');
  try
    Assert.IsTrue(mCatalog.TryFind('x', mEntry));
    Assert.IsTrue(mEntry.SafeFix);
    Assert.IsTrue(mCatalog.TryFind('y', mEntry));
    Assert.IsFalse(mEntry.SafeFix);
  finally
    mCatalog.Free;
  end;
  // Eingebauter Katalog: Umwandlung entfernen ist sicher, leeres except nicht.
  Assert.IsTrue(TRuleCatalog.Shared.TryFind('redundant-cast', mEntry));
  Assert.IsTrue(mEntry.SafeFix);
  Assert.IsTrue(TRuleCatalog.Shared.TryFind('empty-except', mEntry));
  Assert.IsFalse(mEntry.SafeFix);
  ExpectCatalogError('{"rules":[{"id":"x","category":"bug","severity":"error","safeFix":"ja"}]}');
end;

procedure TRuleCatalogTests.EveryEmbeddedRuleNamesCategoryAndSafeFix;
var
  mRoot, mItem: TJSONValue;
  mCategory: TRuleCategory;
  mId: string;
begin
  mRoot := TJSONObject.ParseJSONValue(RuleCatalogBaseJson);
  try
    for mItem in TJSONArray(TJSONObject(mRoot).GetValue('rules')) do
    begin
      mId := TJSONObject(mItem).GetValue<string>('id');
      Assert.IsTrue(TRuleCatalog.TryParseCategory(TJSONObject(mItem).GetValue<string>('category', ''), mCategory), mId);
      Assert.IsTrue(TJSONObject(mItem).GetValue('safeFix') is TJSONBool, mId);
    end;
  finally
    mRoot.Free;
  end;
end;

procedure TRuleCatalogTests.ReadsProfiles;
var
  mCatalog: TRuleCatalog;
  mEntry: TRuleCatalogEntry;
begin
  mCatalog := TRuleCatalog.Create('{"rules":[{"id":"x","category":"code-smell","severity":"hint",' +
    '"profiles":["strict"]},{"id":"y","category":"code-smell","severity":"hint"},' +
    '{"id":"z","category":"bug","severity":"error","profiles":["Standard","strict"]}]}');
  try
    Assert.IsTrue(mCatalog.TryFind('x', mEntry));
    Assert.AreEqual('strict', string.Join(',', mEntry.Profiles));
    Assert.IsTrue(mEntry.Experimental);
    Assert.IsTrue(mEntry.InProfile('strict'));
    Assert.IsFalse(mEntry.InProfile('standard'));
    Assert.IsTrue(mCatalog.TryFind('y', mEntry));
    Assert.AreEqual(0, Integer(Length(mEntry.Profiles)));
    Assert.IsFalse(mEntry.Experimental);
    Assert.IsTrue(mEntry.InProfile('standard'));
    Assert.IsTrue(mEntry.InProfile('STRICT'));
    // Kategorie-Profile stehen nicht in "profiles".
    Assert.IsFalse(mEntry.InProfile('fast'));
    Assert.IsTrue(mCatalog.TryFind('z', mEntry));
    Assert.IsFalse(mEntry.Experimental);
  finally
    mCatalog.Free;
  end;
  // Eingebauter Katalog: magic-number läuft nur unter strict, empty-except überall.
  Assert.IsTrue(TRuleCatalog.Shared.TryFind('magic-number', mEntry));
  Assert.IsTrue(mEntry.Experimental);
  Assert.IsTrue(TRuleCatalog.Shared.TryFind('empty-except', mEntry));
  Assert.IsFalse(mEntry.Experimental);
end;

procedure TRuleCatalogTests.RejectsInvalidProfiles;
begin
  ExpectCatalogError('{"rules":[{"id":"x","category":"bug","severity":"error","profiles":"strict"}]}');
  ExpectCatalogError('{"rules":[{"id":"x","category":"bug","severity":"error","profiles":[]}]}');
  ExpectCatalogError('{"rules":[{"id":"x","category":"bug","severity":"error","profiles":["standard"]}]}');
  ExpectCatalogError('{"rules":[{"id":"x","category":"bug","severity":"error","profiles":["strict","fast"]}]}');
  ExpectCatalogError('{"rules":[{"id":"x","category":"bug","severity":"error","profiles":[1]}]}');
end;

procedure TRuleCatalogTests.RejectsOptionWithUnknownType;
begin
  ExpectCatalogError('{"rules":[{"id":"x","category":"bug","severity":"error","options":[{"name":"a",' +
    '"type":"float"}]}]}');
  ExpectCatalogError('{"rules":[{"id":"x","category":"bug","severity":"error","options":[{"type":"integer"}]}]}');
  ExpectCatalogError('{"rules":[{"id":"x","category":"bug","severity":"error","options":{"name":"a"}}]}');
  // object-list braucht Spalten mit Namen (#1133).
  ExpectCatalogError('{"rules":[{"id":"x","category":"bug","severity":"error","options":[{"name":"a",' +
    '"type":"object-list"}]}]}');
  ExpectCatalogError('{"rules":[{"id":"x","category":"bug","severity":"error","options":[{"name":"a",' +
    '"type":"object-list","columns":[{"list":true}]}]}]}');
end;

procedure TRuleCatalogTests.OverlayTranslatesOptionDescriptions;
var
  mCatalog: TRuleCatalog;
  mEntry: TRuleCatalogEntry;
begin
  mCatalog := TRuleCatalog.Create('{"rules":[{"id":"m","category":"code-smell","severity":"hint","options":' +
    '[{"name":"max","type":"integer","default":4,"description":"Limit"},{"name":"min","type":"integer",' +
    '"description":"Lower"}]}]}', '{"rules":[{"id":"m","options":[{"name":"MAX","description":"Grenze"},' +
    '{"name":"unknown","description":"Fehlt"}]}]}');
  try
    Assert.IsTrue(mCatalog.TryFind('m', mEntry));
    Assert.AreEqual('Grenze', mEntry.Options[0].Description);
    Assert.AreEqual('Lower', mEntry.Options[1].Description);
    Assert.AreEqual('4', mEntry.Options[0].DefaultJson);
  finally
    mCatalog.Free;
  end;
end;

procedure TRuleCatalogTests.EveryEmbeddedRuleHasExactlyOneGroup;
var
  mRoot, mItem: TJSONValue;
  mGroup: TRuleGroup;
  mSeen: TArray<string>;
  mId: string;
begin
  // Jede Regel nennt ihre Gruppe ausdrücklich (nicht über die Kategorie) und steht nur einmal im Katalog.
  mRoot := TJSONObject.ParseJSONValue(RuleCatalogBaseJson);
  try
    mSeen := nil;
    for mItem in TJSONArray(TJSONObject(mRoot).GetValue('rules')) do
    begin
      mId := TJSONObject(mItem).GetValue<string>('id');
      Assert.IsNotNull(TJSONObject(mItem).GetValue('group'), mId);
      Assert.IsTrue(TRuleCatalog.TryParseGroup(TJSONObject(mItem).GetValue<string>('group'), mGroup), mId);
      Assert.IsFalse(MatchText(mId, mSeen), mId);
      mSeen := mSeen + [mId];
    end;
    Assert.IsTrue(Length(mSeen) > 0);
  finally
    mRoot.Free;
  end;
end;

procedure TRuleCatalogTests.GroupNamesRoundTrip;
var
  mGroup, mParsed: TRuleGroup;
begin
  for mGroup := Low(TRuleGroup) to High(TRuleGroup) do
  begin
    Assert.IsTrue(TRuleCatalog.TryParseGroup(TRuleCatalog.GroupName(mGroup), mParsed));
    Assert.AreEqual(Ord(mGroup), Ord(mParsed));
  end;
  Assert.AreEqual('find-bugs', TRuleCatalog.GroupName(TRuleGroup.FindBugs));
  Assert.AreEqual('migration', TRuleCatalog.GroupName(TRuleGroup.Migration));
  Assert.IsFalse(TRuleCatalog.TryParseGroup('', mParsed));
end;

procedure TRuleCatalogTests.SharedCatalogIsReadOnce;
var
  mEntry: TRuleCatalogEntry;
begin
  Assert.AreSame(TRuleCatalog.Shared, TRuleCatalog.Shared);
  Assert.IsTrue(TRuleCatalog.Shared.TryFind('empty-except', mEntry));
  Assert.AreEqual(Ord(TRuleGroup.Exceptions), Ord(mEntry.Group));
end;

initialization
  TDUnitX.RegisterTestFixture(TRuleCatalogTests);

end.
