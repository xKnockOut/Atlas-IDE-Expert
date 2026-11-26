unit Lsp.SettingsCommands.Tests;

// Tests für die Prüfung der Einstellungen im Einstellungsdialog (#227); den Katalog der Regeln prüft
// Rules.SettingsCatalog.Tests.

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
  end;

implementation

uses
  System.Generics.Collections,
  System.SysUtils,
  System.JSON,
  Lsp.SettingsCommands;

function Arguments(const AText: string): TJSONArray;
begin
  Result := TJSONArray.Create;
  Result.Add(AText);
end;

{ TLspSettingsCommandsTests }

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

initialization
  TDUnitX.RegisterTestFixture(TLspSettingsCommandsTests);

end.
