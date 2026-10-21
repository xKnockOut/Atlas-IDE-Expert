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
  Atlas.Common.Rules.Catalog,
  Atlas.Common.Rules.Catalog.Data;

const
  Base = '{"rules":[{"id":"a-rule","name":"A rule","category":"code-smell","severity":"warning",' +
    '"description":"Text","bad":"X;","good":"Y;"}]}';

procedure ExpectCatalogError(const AJson: string);
var
  Raised: Boolean;
begin
  Raised := False;
  try
    TRuleCatalog.Create(AJson).Free;
  except
    on ERuleCatalog do
      Raised := True;
  end;
  Assert.IsTrue(Raised, AJson);
end;

{ TRuleCatalogTests }

procedure TRuleCatalogTests.ReadsBaseEntry;
var
  Catalog: TRuleCatalog;
  Entry: TRuleCatalogEntry;
begin
  Catalog := TRuleCatalog.Create(Base);
  try
    Assert.IsTrue(Catalog.TryFind('A-RULE', Entry));
    Assert.AreEqual('A rule', Entry.Name);
    Assert.AreEqual(Ord(TRuleCategory.CodeSmell), Ord(Entry.Category));
    Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Entry.DefaultSeverity));
    Assert.AreEqual('Text', Entry.Description);
    Assert.AreEqual('X;', Entry.Bad);
    Assert.AreEqual('Y;', Entry.Good);
    Assert.IsFalse(Catalog.TryFind('other', Entry));
  finally
    Catalog.Free;
  end;
end;

procedure TRuleCatalogTests.OverlayReplacesNameAndDescriptionOnly;
var
  Catalog: TRuleCatalog;
  Entry: TRuleCatalogEntry;
begin
  Catalog := TRuleCatalog.Create(Base, '{"rules":[{"id":"a-rule","name":"Eine Regel","description":"Beschreibung"}]}');
  try
    Assert.IsTrue(Catalog.TryFind('a-rule', Entry));
    Assert.AreEqual('Eine Regel', Entry.Name);
    Assert.AreEqual('Beschreibung', Entry.Description);
    Assert.AreEqual(Ord(TRuleCategory.CodeSmell), Ord(Entry.Category));
    Assert.AreEqual('X;', Entry.Bad);
  finally
    Catalog.Free;
  end;
end;

procedure TRuleCatalogTests.OverlayIgnoresUnknownRules;
var
  Catalog: TRuleCatalog;
begin
  Catalog := TRuleCatalog.Create(Base, '{"rules":[{"id":"missing","name":"Fehlt"}]}');
  try
    Assert.AreEqual<NativeInt>(1, Length(Catalog.Entries));
  finally
    Catalog.Free;
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
  Assert.AreEqual(RuleDocumentationBaseUri + 'bidi-control', TRuleCatalog.HelpUri('Bidi-Control'));
end;

procedure TRuleCatalogTests.BuiltinRulesAreInCatalogWithSameSeverity;
var
  Catalog: TRuleCatalog;
  Entry: TRuleCatalogEntry;
  Rule: IRule;
begin
  Catalog := TRuleCatalog.Create(RuleCatalogBaseJson);
  try
    for Rule in BuiltinRules do
    begin
      Assert.IsTrue(Catalog.TryFind(Rule.Descriptor.Id, Entry), Rule.Descriptor.Id);
      Assert.AreEqual(Ord(Rule.Descriptor.DefaultSeverity), Ord(Entry.DefaultSeverity), Rule.Descriptor.Id);
    end;
    Assert.IsTrue(Catalog.TryFind(TFileChecker.SyntaxDescriptor.Id, Entry));
    Assert.IsTrue(Catalog.TryFind(UnusedSuppressionRuleId, Entry));
  finally
    Catalog.Free;
  end;
end;

procedure TRuleCatalogTests.EmbeddedCatalogIsCompleteInGerman;
var
  English, German: TRuleCatalog;
  Entry, Translated: TRuleCatalogEntry;
begin
  English := TRuleCatalog.Create(RuleCatalogBaseJson);
  German := TRuleCatalog.Create(RuleCatalogBaseJson, RuleCatalogOverlayJson('de'));
  try
    for Entry in English.Entries do
    begin
      Assert.IsTrue(German.TryFind(Entry.Id, Translated));
      Assert.AreNotEqual(Entry.Description, Translated.Description, Entry.Id);
      Assert.AreNotEqual('', Entry.Bad, Entry.Id);
      Assert.AreNotEqual('', Entry.Good, Entry.Id);
    end;
  finally
    German.Free;
    English.Free;
  end;
end;

procedure TRuleCatalogTests.UnknownLanguageHasNoOverlay;
begin
  Assert.AreEqual('', RuleCatalogOverlayJson('xx'));
end;

procedure TRuleCatalogTests.ExplanationHasExamplesAndLink;
var
  Catalog: TRuleCatalog;
  Entry: TRuleCatalogEntry;
begin
  // #300: /explain zeigt Beschreibung, falsch/richtig und den Link.
  Catalog := TRuleCatalog.Create(Base);
  try
    Assert.IsTrue(Catalog.TryFind('a-rule', Entry));
    Assert.AreEqual('a-rule: A rule'#10'Text'#10#10'Falsch:'#10'X;'#10#10'Richtig:'#10'Y;'#10#10'Mehr: ' +
      TRuleCatalog.HelpUri('a-rule'), TRuleCatalog.Explanation(Entry, #10));
    Entry.Bad := '';
    Entry.Good := '';
    Assert.AreEqual('a-rule: A rule'#10'Text'#10#10'Mehr: ' + TRuleCatalog.HelpUri('a-rule'),
      TRuleCatalog.Explanation(Entry, #10));
  finally
    Catalog.Free;
  end;
end;

procedure TRuleCatalogTests.ReadsGroupAndOptions;
var
  Catalog: TRuleCatalog;
  Entry: TRuleCatalogEntry;
begin
  Catalog := TRuleCatalog.Create('{"rules":[{"id":"m","name":"M","category":"code-smell","severity":"hint",' +
    '"group":"style","description":"D","bad":"B","good":"G","options":[{"name":"max","type":"integer",' +
    '"default":40,"description":"Limit"},{"name":"names","type":"string-list","default":["Count"],' +
    '"description":"Names"},{"name":"flag","type":"boolean","description":"No default"}]}]}');
  try
    Assert.IsTrue(Catalog.TryFind('m', Entry));
    Assert.AreEqual(Ord(TRuleGroup.Style), Ord(Entry.Group));
    Assert.AreEqual(3, Integer(Length(Entry.Options)));
    Assert.AreEqual('max', Entry.Options[0].Name);
    Assert.AreEqual('integer', Entry.Options[0].Kind);
    Assert.AreEqual('40', Entry.Options[0].DefaultJson);
    Assert.AreEqual('Limit', Entry.Options[0].Description);
    Assert.AreEqual('["Count"]', Entry.Options[1].DefaultJson);
    Assert.AreEqual('', Entry.Options[2].DefaultJson);
  finally
    Catalog.Free;
  end;
end;

procedure TRuleCatalogTests.GroupFollowsCategoryWithoutField;
var
  Catalog: TRuleCatalog;
  Entry: TRuleCatalogEntry;
begin
  Catalog := TRuleCatalog.Create('{"rules":[{"id":"a","category":"bug","severity":"error"},' +
    '{"id":"b","category":"vulnerability","severity":"error"},{"id":"c","category":"security-hotspot",' +
    '"severity":"hint"},{"id":"d","category":"code-smell","severity":"hint"}]}');
  try
    Assert.IsTrue(Catalog.TryFind('a', Entry));
    Assert.AreEqual(Ord(TRuleGroup.FindBugs), Ord(Entry.Group));
    Assert.IsTrue(Catalog.TryFind('b', Entry));
    Assert.AreEqual(Ord(TRuleGroup.Security), Ord(Entry.Group));
    Assert.IsTrue(Catalog.TryFind('c', Entry));
    Assert.AreEqual(Ord(TRuleGroup.Security), Ord(Entry.Group));
    Assert.IsTrue(Catalog.TryFind('d', Entry));
    Assert.AreEqual(Ord(TRuleGroup.Style), Ord(Entry.Group));
    Assert.AreEqual(0, Integer(Length(Entry.Options)));
  finally
    Catalog.Free;
  end;
end;

procedure TRuleCatalogTests.RejectsUnknownGroup;
begin
  ExpectCatalogError('{"rules":[{"id":"x","category":"bug","severity":"error","group":"misc"}]}');
end;

procedure TRuleCatalogTests.RejectsOptionWithUnknownType;
begin
  ExpectCatalogError('{"rules":[{"id":"x","category":"bug","severity":"error","options":[{"name":"a",' +
    '"type":"float"}]}]}');
  ExpectCatalogError('{"rules":[{"id":"x","category":"bug","severity":"error","options":[{"type":"integer"}]}]}');
  ExpectCatalogError('{"rules":[{"id":"x","category":"bug","severity":"error","options":{"name":"a"}}]}');
end;

procedure TRuleCatalogTests.OverlayTranslatesOptionDescriptions;
var
  Catalog: TRuleCatalog;
  Entry: TRuleCatalogEntry;
begin
  Catalog := TRuleCatalog.Create('{"rules":[{"id":"m","category":"code-smell","severity":"hint","options":' +
    '[{"name":"max","type":"integer","default":4,"description":"Limit"},{"name":"min","type":"integer",' +
    '"description":"Lower"}]}]}', '{"rules":[{"id":"m","options":[{"name":"MAX","description":"Grenze"},' +
    '{"name":"unknown","description":"Fehlt"}]}]}');
  try
    Assert.IsTrue(Catalog.TryFind('m', Entry));
    Assert.AreEqual('Grenze', Entry.Options[0].Description);
    Assert.AreEqual('Lower', Entry.Options[1].Description);
    Assert.AreEqual('4', Entry.Options[0].DefaultJson);
  finally
    Catalog.Free;
  end;
end;

procedure TRuleCatalogTests.EveryEmbeddedRuleHasExactlyOneGroup;
var
  Root, Item: TJSONValue;
  Group: TRuleGroup;
  Seen: TArray<string>;
  Id: string;
begin
  // Jede Regel nennt ihre Gruppe ausdrücklich (nicht über die Kategorie) und steht nur einmal im Katalog.
  Root := TJSONObject.ParseJSONValue(RuleCatalogBaseJson);
  try
    Seen := nil;
    for Item in TJSONArray(TJSONObject(Root).GetValue('rules')) do
    begin
      Id := TJSONObject(Item).GetValue<string>('id');
      Assert.IsTrue(TJSONObject(Item).GetValue('group') <> nil, Id);
      Assert.IsTrue(TRuleCatalog.TryParseGroup(TJSONObject(Item).GetValue<string>('group'), Group), Id);
      Assert.IsFalse(MatchText(Id, Seen), Id);
      Seen := Seen + [Id];
    end;
    Assert.IsTrue(Length(Seen) > 0);
  finally
    Root.Free;
  end;
end;

procedure TRuleCatalogTests.GroupNamesRoundTrip;
var
  Group, Parsed: TRuleGroup;
begin
  for Group := Low(TRuleGroup) to High(TRuleGroup) do
  begin
    Assert.IsTrue(TRuleCatalog.TryParseGroup(TRuleCatalog.GroupName(Group), Parsed));
    Assert.AreEqual(Ord(Group), Ord(Parsed));
  end;
  Assert.AreEqual('find-bugs', TRuleCatalog.GroupName(TRuleGroup.FindBugs));
  Assert.IsFalse(TRuleCatalog.TryParseGroup('', Parsed));
end;

procedure TRuleCatalogTests.SharedCatalogIsReadOnce;
var
  Entry: TRuleCatalogEntry;
begin
  Assert.IsTrue(TRuleCatalog.Shared = TRuleCatalog.Shared);
  Assert.IsTrue(TRuleCatalog.Shared.TryFind('empty-except', Entry));
  Assert.AreEqual(Ord(TRuleGroup.Exceptions), Ord(Entry.Group));
end;

initialization
  TDUnitX.RegisterTestFixture(TRuleCatalogTests);

end.
