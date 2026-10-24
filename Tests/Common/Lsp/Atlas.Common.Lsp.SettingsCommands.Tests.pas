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
  Args: TJSONArray;
  Answer: TJSONObject;
  Issue: TJSONObject;
begin
  Args := Arguments('{'#10'  "logLevel": "laut"'#10'}');
  try
    Answer := TLspSettingsCommands.Check(Args);
    try
      Assert.IsFalse((Answer.GetValue('valid') as TJSONBool).AsBoolean);
      Issue := TJSONArray(Answer.GetValue('issues')).Items[0] as TJSONObject;
      Assert.AreEqual(1, Issue.GetValue<Integer>('line'));
      Assert.Contains(Issue.GetValue<string>('message'), '"debug"');
      Assert.IsTrue((Issue.GetValue('error') as TJSONBool).AsBoolean);
    finally
      Answer.Free;
    end;
  finally
    Args.Free;
  end;
  Args := Arguments('// Kommentar'#10'{"rules": {"empty-except": "off"}}');
  try
    Answer := TLspSettingsCommands.Check(Args);
    try
      Assert.IsTrue((Answer.GetValue('valid') as TJSONBool).AsBoolean);
      Assert.AreEqual(0, TJSONArray(Answer.GetValue('issues')).Count);
    finally
      Answer.Free;
    end;
  finally
    Args.Free;
  end;
end;

procedure TLspSettingsCommandsTests.ReportsKeysAtTheWrongPlace;
var
  Args: TJSONArray;
  Answer: TJSONObject;
  Issues: TJSONArray;
begin
  // Als atlas.json (Vorgabe): der globale Schlüssel ist eine Warnung, der Text bleibt gültig.
  Args := Arguments('{"rules": {}, "platform": "Win64", "memoryBudgetMb": 512}');
  try
    Answer := TLspSettingsCommands.Check(Args);
    try
      Assert.IsTrue((Answer.GetValue('valid') as TJSONBool).AsBoolean);
      Issues := TJSONArray(Answer.GetValue('issues'));
      Assert.AreEqual(1, Integer(Issues.Count));
      Assert.Contains((Issues.Items[0] as TJSONObject).GetValue<string>('message'), '"memoryBudgetMb"');
      Assert.IsFalse(((Issues.Items[0] as TJSONObject).GetValue('error') as TJSONBool).AsBoolean);
    finally
      Answer.Free;
    end;
    // Als globale Datei: platform gehört zum Projekt; rules geht an beiden Orten.
    Args.Add('global');
    Answer := TLspSettingsCommands.Check(Args);
    try
      Issues := TJSONArray(Answer.GetValue('issues'));
      Assert.AreEqual(1, Integer(Issues.Count));
      Assert.Contains((Issues.Items[0] as TJSONObject).GetValue<string>('message'), '"platform"');
    finally
      Answer.Free;
    end;
  finally
    Args.Free;
  end;
end;

procedure TLspSettingsCommandsTests.ListsRuleCatalogInLanguage;
var
  Args: TJSONArray;
  Entries: TArray<TRuleCatalogEntry>;
  Answer: TJSONObject;
  Rules: TJSONArray;
  Index: Integer;
  Found: Boolean;
begin
  Args := Arguments('de');
  try
    Entries := TLspSettingsCommands.CatalogEntries(Args);
  finally
    Args.Free;
  end;
  Assert.IsTrue(Length(Entries) > 10);
  Answer := TLspSettingsCommands.Catalog(Entries, 'C:\Users\x\AppData\Roaming\Atlas\settings.json');
  try
    Rules := Answer.GetValue('rules') as TJSONArray;
    Assert.AreEqual(Integer(Length(Entries)), Rules.Count);
    Found := False;
    for Index := 0 to Rules.Count - 1 do
      if Rules.Items[Index].GetValue<string>('id') = 'syntax' then
      begin
        Found := True;
        Assert.AreEqual('error', Rules.Items[Index].GetValue<string>('severity'));
        Assert.AreEqual('bug', Rules.Items[Index].GetValue<string>('category'));
        Assert.IsTrue(Rules.Items[Index].GetValue<string>('name') <> '');
      end;
    Assert.IsTrue(Found);
    Assert.AreEqual('C:\Users\x\AppData\Roaming\Atlas\settings.json', Answer.GetValue<string>('globalFile'));
    Assert.IsTrue(Answer.GetValue<string>('version') <> '');
  finally
    Answer.Free;
  end;
end;

procedure TLspSettingsCommandsTests.CatalogCarriesGroupOptionsAndExperimental;
var
  Args: TJSONArray;
  Entries: TArray<TRuleCatalogEntry>;
  Answer: TJSONObject;
  Rules: TJSONArray;
  Rule: TJSONValue;
  Options, Overrides: TJSONArray;
  Option: TJSONValue;
  Index: Integer;
  SeenMetric: Boolean;
  SeenSyntax: Boolean;
begin
  Args := Arguments('de');
  try
    Entries := TLspSettingsCommands.CatalogEntries(Args);
  finally
    Args.Free;
  end;
  Answer := TLspSettingsCommands.Catalog(Entries, '', ['metric-method-length']);
  try
    Rules := Answer.GetValue('rules') as TJSONArray;
    SeenMetric := False;
    SeenSyntax := False;
    for Index := 0 to Rules.Count - 1 do
    begin
      Rule := Rules.Items[Index];
      Assert.IsTrue(Rule.GetValue<string>('group') <> '', Rule.GetValue<string>('id'));
      if Rule.GetValue<string>('id') = 'metric-method-length' then
      begin
        SeenMetric := True;
        Assert.AreEqual('style', Rule.GetValue<string>('group'));
        Assert.IsTrue(Rule.GetValue<Boolean>('experimental'));
        Options := Rule.GetValue<TJSONArray>('options');
        Assert.AreEqual(1, Options.Count);
        Option := Options.Items[0];
        Assert.AreEqual('max', Option.GetValue<string>('name'));
        Assert.AreEqual('integer', Option.GetValue<string>('type'));
        Assert.AreEqual(60, Option.GetValue<Integer>('default'));
        Assert.IsTrue(Option.GetValue<string>('description') <> '');
        Assert.IsTrue(Rule.GetValue<string>('bad') <> '');
      end;
      // Tabelle der Symbole (#1133): Spalten, Listen markiert.
      if Rule.GetValue<string>('id') = 'forbidden-symbol' then
      begin
        Option := Rule.GetValue<TJSONArray>('options').Items[0];
        Assert.AreEqual('object-list', Option.GetValue<string>('type'));
        Assert.AreEqual('name', Option.GetValue<TJSONArray>('columns').Items[0].GetValue<string>('name'));
        Assert.IsNull(Option.GetValue<TJSONArray>('columns').Items[0].FindValue('list'));
        Assert.IsTrue(Option.GetValue<TJSONArray>('columns').Items[5].GetValue<Boolean>('list'));
      end;
      // Gegenregel (#1025).
      if Rule.GetValue<string>('id') = 'redundant-begin-end' then
      begin
        Overrides := Rule.GetValue<TJSONArray>('overriddenBy');
        Assert.AreEqual(1, Integer(Overrides.Count));
        Assert.AreEqual('missing-begin-end', Overrides.Items[0].Value);
      end;
      if Rule.GetValue<string>('id') = 'syntax' then
      begin
        SeenSyntax := True;
        Assert.IsNull(Rule.FindValue('experimental'));
        Assert.IsNull(Rule.FindValue('overriddenBy'));
        Assert.AreEqual(0, Rule.GetValue<TJSONArray>('options').Count);
      end;
    end;
    Assert.IsTrue(SeenMetric);
    Assert.IsTrue(SeenSyntax);
  finally
    Answer.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspSettingsCommandsTests);

end.
