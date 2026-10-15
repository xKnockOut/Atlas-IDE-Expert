unit Atlas.Common.Lsp.SettingsCommands.Tests;

// Tests für die Befehle des Einstellungsdialogs (#227).

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
  Args := Arguments('{"rules": {}, "memoryBudgetMb": 512}');
  try
    Answer := TLspSettingsCommands.Check(Args);
    try
      Assert.IsTrue((Answer.GetValue('valid') as TJSONBool).AsBoolean);
      Issues := TJSONArray(Answer.GetValue('issues'));
      Assert.AreEqual(1, Issues.Count);
      Assert.Contains((Issues.Items[0] as TJSONObject).GetValue<string>('message'), '"memoryBudgetMb"');
      Assert.IsFalse(((Issues.Items[0] as TJSONObject).GetValue('error') as TJSONBool).AsBoolean);
    finally
      Answer.Free;
    end;
    // Als globale Datei: rules gehört zum Projekt.
    Args.Add('global');
    Answer := TLspSettingsCommands.Check(Args);
    try
      Issues := TJSONArray(Answer.GetValue('issues'));
      Assert.AreEqual(1, Issues.Count);
      Assert.Contains((Issues.Items[0] as TJSONObject).GetValue<string>('message'), '"rules"');
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

initialization
  TDUnitX.RegisterTestFixture(TLspSettingsCommandsTests);

end.
