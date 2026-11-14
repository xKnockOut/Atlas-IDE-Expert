unit Atlas.Common.Lsp.SettingsCommands.Tests;

// Tests für die Befehle des Einstellungsdialogs (#227); Gruppen, Optionen
// und experimentelle Regeln im Katalog (#909).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspSettingsCommandsTests = class
  public
    [Test]
    procedure ChecksTextWithServerParser;
    [Test]
    procedure ReportsKeysAtTheWrongPlace;
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
  Atlas.Common.Lsp.SettingsCommands;

function Arguments(const AText: string): TJSONArray;
begin
  Result := TJSONArray.Create;
  Result.Add(AText);
end;

procedure TLspSettingsCommandsTests.ChecksTextWithServerParser;
var
  mArgs: TJSONArray;
  mAnswer: TJSONObject;
  mIssue: TJSONObject;
begin
  mArgs := Arguments('{'#10'  "logLevel": "laut"'#10'}');
  try
    mAnswer := TLspSettingsCommands.Check(mArgs);
    try
      Assert.IsFalse((mAnswer.GetValue('valid') as TJSONBool).AsBoolean);
      mIssue := TJSONArray(mAnswer.GetValue('issues')).Items[0] as TJSONObject;
      Assert.AreEqual(1, mIssue.GetValue<Integer>('line'));
      Assert.Contains(mIssue.GetValue<string>('message'), '"debug"');
      Assert.IsTrue((mIssue.GetValue('error') as TJSONBool).AsBoolean);
    finally
      mAnswer.Free;
    end;
  finally
    mArgs.Free;
  end;
  mArgs := Arguments('// Kommentar'#10'{"rules": {"empty-except": "off"}}');
  try
    mAnswer := TLspSettingsCommands.Check(mArgs);
    try
      Assert.IsTrue((mAnswer.GetValue('valid') as TJSONBool).AsBoolean);
      Assert.AreEqual(0, TJSONArray(mAnswer.GetValue('issues')).Count);
    finally
      mAnswer.Free;
    end;
  finally
    mArgs.Free;
  end;
end;

procedure TLspSettingsCommandsTests.ReportsKeysAtTheWrongPlace;
var
  mArgs: TJSONArray;
  mAnswer: TJSONObject;
  mIssues: TJSONArray;
begin
  // Als atlas.json (Vorgabe): der globale Schlüssel ist eine Warnung, der Text bleibt gültig.
  mArgs := Arguments('{"rules": {}, "platform": "Win64", "memoryBudgetMb": 512}');
  try
    mAnswer := TLspSettingsCommands.Check(mArgs);
    try
      Assert.IsTrue((mAnswer.GetValue('valid') as TJSONBool).AsBoolean);
      mIssues := TJSONArray(mAnswer.GetValue('issues'));
      Assert.AreEqual(1, Integer(mIssues.Count));
      Assert.Contains((mIssues.Items[0] as TJSONObject).GetValue<string>('message'), '"memoryBudgetMb"');
      Assert.IsFalse(((mIssues.Items[0] as TJSONObject).GetValue('error') as TJSONBool).AsBoolean);
    finally
      mAnswer.Free;
    end;
    // Als globale Datei: platform gehört zum Projekt; rules geht an beiden Orten.
    mArgs.Add('global');
    mAnswer := TLspSettingsCommands.Check(mArgs);
    try
      mIssues := TJSONArray(mAnswer.GetValue('issues'));
      Assert.AreEqual(1, Integer(mIssues.Count));
      Assert.Contains((mIssues.Items[0] as TJSONObject).GetValue<string>('message'), '"platform"');
    finally
      mAnswer.Free;
    end;
  finally
    mArgs.Free;
  end;
end;

procedure TLspSettingsCommandsTests.ListsRuleCatalogInLanguage;
var
  mArgs: TJSONArray;
  mEntries: TArray<TRuleCatalogEntry>;
  mAnswer: TJSONObject;
  mRules: TJSONArray;
  mIndex: Integer;
  mFound: Boolean;
begin
  mArgs := Arguments('de');
  try
    mEntries := TLspSettingsCommands.CatalogEntries(mArgs);
  finally
    mArgs.Free;
  end;
  Assert.IsTrue(Length(mEntries) > 10);
  mAnswer := TLspSettingsCommands.Catalog(mEntries, 'C:\Users\x\AppData\Roaming\Atlas\settings.json');
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

procedure TLspSettingsCommandsTests.CatalogCarriesGroupOptionsAndExperimental;
var
  mArgs: TJSONArray;
  mEntries: TArray<TRuleCatalogEntry>;
  mAnswer: TJSONObject;
  mRules: TJSONArray;
  mRule: TJSONValue;
  mOverrides: TJSONArray;
  mIndex: Integer;
  mSeenMetric: Boolean;
  mSeenSyntax: Boolean;
  mSeenMagic: Boolean;
begin
  mArgs := Arguments('de');
  try
    mEntries := TLspSettingsCommands.CatalogEntries(mArgs);
  finally
    mArgs.Free;
  end;
  mAnswer := TLspSettingsCommands.Catalog(mEntries, '');
  try
    mRules := mAnswer.GetValue('rules') as TJSONArray;
    mSeenMetric := False;
    mSeenSyntax := False;
    mSeenMagic := False;
    for mIndex := 0 to mRules.Count - 1 do
    begin
      mRule := mRules.Items[mIndex];
      Assert.AreNotEqual('', mRule.GetValue<string>('group'), mRule.GetValue<string>('id'));
      if mRule.GetValue<string>('id') = 'metric-method-length' then
      begin
        mSeenMetric := True;
        AssertMethodLengthEntry(mRule);
      end;
      // Tabelle der Symbole (#1133): Spalten, Listen markiert.
      if mRule.GetValue<string>('id') = 'forbidden-symbol' then
      begin
        AssertForbiddenSymbolColumns(mRule);
      end;
      // Experimentell laut "profiles" des Katalogs (#145).
      if mRule.GetValue<string>('id') = 'magic-number' then
      begin
        mSeenMagic := True;
        Assert.IsTrue(mRule.GetValue<Boolean>('experimental'));
      end;
      // Gegenregel (#1025).
      if mRule.GetValue<string>('id') = 'redundant-begin-end' then
      begin
        mOverrides := mRule.GetValue<TJSONArray>('overriddenBy');
        Assert.AreEqual(1, Integer(mOverrides.Count));
        Assert.AreEqual('missing-begin-end', mOverrides.Items[0].Value);
      end;
      if mRule.GetValue<string>('id') = 'syntax' then
      begin
        mSeenSyntax := True;
        Assert.IsNull(mRule.FindValue('experimental'));
        Assert.IsNull(mRule.FindValue('overriddenBy'));
        Assert.AreEqual(0, mRule.GetValue<TJSONArray>('options').Count);
      end;
    end;
    Assert.IsTrue(mSeenMetric);
    Assert.IsTrue(mSeenSyntax);
    Assert.IsTrue(mSeenMagic);
  finally
    mAnswer.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspSettingsCommandsTests);

end.
