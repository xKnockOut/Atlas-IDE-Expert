unit Atlas.Common.Rules.SettingsCatalog.Tests;

// Tests für den Katalog der Regeln auf der Einstellungsseite (#227): Sprache, Gruppen, Optionen und experimentelle
// Regeln (#909).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TRuleSettingsCatalogTests = class
  public
    [Test]
    procedure ListsRuleCatalogInLanguage;
    [Test]
    procedure CatalogCarriesGroupOptionsAndExperimental;
  end;

implementation

uses
  System.Generics.Collections,
  System.SysUtils,
  System.JSON,
  Atlas.Common.Rules.Catalog,
  Atlas.Common.Rules.SettingsCatalog;

{ TRuleSettingsCatalogTests }

procedure TRuleSettingsCatalogTests.ListsRuleCatalogInLanguage;
var
  mEntries: TArray<TRuleCatalogEntry>;
  mAnswer: TJSONObject;
  mRules: TJSONArray;
  mIndex: Integer;
  mFound: Boolean;
begin
  mEntries := TRuleSettingsCatalog.Entries('de');
  Assert.IsTrue(Length(mEntries) > 10);
  mAnswer := TRuleSettingsCatalog.Json(mEntries, 'C:\Users\x\AppData\Roaming\Atlas\settings.json');
  try
    mRules := mAnswer.GetValue('rules') as TJSONArray;
    Assert.AreEqual(Integer(Length(mEntries)), mRules.Count);
    mFound := False;
    for mIndex := 0 to mRules.Count - 1 do
    begin
      if mRules.Items[mIndex].GetValue<string>('id') = 'syntax' then
      begin
        mFound := True;
        Assert.AreEqual('error', mRules.Items[mIndex].GetValue<string>('severity'));
        Assert.AreEqual('bug', mRules.Items[mIndex].GetValue<string>('category'));
        Assert.AreNotEqual('', mRules.Items[mIndex].GetValue<string>('name'));
      end;
    end;
    Assert.IsTrue(mFound);
    Assert.AreEqual('C:\Users\x\AppData\Roaming\Atlas\settings.json', mAnswer.GetValue<string>('globalFile'));
    Assert.AreNotEqual('', mAnswer.GetValue<string>('version'));
  finally
    mAnswer.Free;
  end;
end;

/// <summary>metric-method-length: Gruppe style, nicht experimentell, eine Option max mit Vorgabe 60.</summary>
procedure AssertMethodLengthEntry(const ARule: TJSONValue);
var
  mOptions: TJSONArray;
  mOption: TJSONValue;
begin
  Assert.AreEqual('style', ARule.GetValue<string>('group'));
  Assert.IsNull(ARule.FindValue('experimental'));
  mOptions := ARule.GetValue<TJSONArray>('options');
  Assert.AreEqual(1, mOptions.Count);
  mOption := mOptions.Items[0];
  Assert.AreEqual('max', mOption.GetValue<string>('name'));
  Assert.AreEqual('integer', mOption.GetValue<string>('type'));
  Assert.AreEqual(60, mOption.GetValue<Integer>('default'));
  Assert.AreNotEqual('', mOption.GetValue<string>('description'));
  Assert.AreNotEqual('', ARule.GetValue<string>('bad'));
end;

/// <summary>Tabelle der Symbole (#1133): Spalten, Listen markiert.</summary>
procedure AssertForbiddenSymbolColumns(const ARule: TJSONValue);
var
  mOption: TJSONValue;
begin
  mOption := ARule.GetValue<TJSONArray>('options').Items[0];
  Assert.AreEqual('object-list', mOption.GetValue<string>('type'));
  Assert.AreEqual('name', mOption.GetValue<TJSONArray>('columns').Items[0].GetValue<string>('name'));
  Assert.IsNull(mOption.GetValue<TJSONArray>('columns').Items[0].FindValue('list'));
  Assert.IsTrue(mOption.GetValue<TJSONArray>('columns').Items[5].GetValue<Boolean>('list'));
end;

/// <summary>Prüft einen Eintrag des Katalogs und merkt, ob Metrik, syntax und magic-number vorkamen.</summary>
procedure CheckCatalogRule(const ARule: TJSONValue; var ASeenMetric, ASeenSyntax, ASeenMagic: Boolean);
var
  mOverrides: TJSONArray;
begin
  Assert.AreNotEqual('', ARule.GetValue<string>('group'), ARule.GetValue<string>('id'));
  if ARule.GetValue<string>('id') = 'metric-method-length' then
  begin
    ASeenMetric := True;
    AssertMethodLengthEntry(ARule);
  end;
  // Tabelle der Symbole (#1133): Spalten, Listen markiert.
  if ARule.GetValue<string>('id') = 'forbidden-symbol' then
  begin
    AssertForbiddenSymbolColumns(ARule);
  end;
  // Experimentell laut "profiles" des Katalogs (#145).
  if ARule.GetValue<string>('id') = 'magic-number' then
  begin
    ASeenMagic := True;
    Assert.IsTrue(ARule.GetValue<Boolean>('experimental'));
  end;
  // Gegenregel (#1025).
  if ARule.GetValue<string>('id') = 'redundant-begin-end' then
  begin
    mOverrides := ARule.GetValue<TJSONArray>('overriddenBy');
    Assert.AreEqual(1, Integer(mOverrides.Count));
    Assert.AreEqual('missing-begin-end', mOverrides.Items[0].Value);
  end;
  if ARule.GetValue<string>('id') = 'syntax' then
  begin
    ASeenSyntax := True;
    Assert.IsNull(ARule.FindValue('experimental'));
    Assert.IsNull(ARule.FindValue('overriddenBy'));
    Assert.AreEqual(0, ARule.GetValue<TJSONArray>('options').Count);
  end;
end;

procedure TRuleSettingsCatalogTests.CatalogCarriesGroupOptionsAndExperimental;
var
  mEntries: TArray<TRuleCatalogEntry>;
  mAnswer: TJSONObject;
  mRules: TJSONArray;
  mRule: TJSONValue;
  mIndex: Integer;
  mSeenMetric: Boolean;
  mSeenSyntax: Boolean;
  mSeenMagic: Boolean;
begin
  mEntries := TRuleSettingsCatalog.Entries('de');
  mAnswer := TRuleSettingsCatalog.Json(mEntries, '');
  try
    mRules := mAnswer.GetValue('rules') as TJSONArray;
    mSeenMetric := False;
    mSeenSyntax := False;
    mSeenMagic := False;
    for mIndex := 0 to mRules.Count - 1 do
    begin
      mRule := mRules.Items[mIndex];
      CheckCatalogRule(mRule, mSeenMetric, mSeenSyntax, mSeenMagic);
    end;
    Assert.IsTrue(mSeenMetric);
    Assert.IsTrue(mSeenSyntax);
    Assert.IsTrue(mSeenMagic);
  finally
    mAnswer.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TRuleSettingsCatalogTests);

end.
