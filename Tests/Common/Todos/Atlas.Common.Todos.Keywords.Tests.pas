unit Atlas.Common.Todos.Keywords.Tests;

// Tests der Marken offener TODO-Einträge (#68): Option "keywords", Vorgaben, gültige Marken, Einstellungen bei
// abgeschalteter Regel.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTodoKeywordsTests = class
  public
    [Test]
    procedure KeywordsFromOptions;
    [Test]
    procedure KeywordsFromSettings;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Todos.Keywords;

{ TTodoKeywordsTests }

procedure TTodoKeywordsTests.KeywordsFromOptions;
begin
  Assert.AreEqual('TODO FIXME', string.Join(' ', TTodoKeywords.FromOptions('')));
  Assert.AreEqual('TODO FIXME', string.Join(' ', TTodoKeywords.FromOptions('{"keywords": []}')));
  Assert.AreEqual('TODO FIXME', string.Join(' ', TTodoKeywords.FromOptions('{"keywords": "HACK"}')));
  Assert.AreEqual('HACK XXX', string.Join(' ',
    TTodoKeywords.FromOptions('{"keywords": ["hack", " XXX ", "DONE", "TO-DO", 1]}')));
  Assert.IsTrue(TTodoKeywords.IsValid('Note'));
  Assert.IsFalse(TTodoKeywords.IsValid('done'));
  Assert.IsFalse(TTodoKeywords.IsValid(''));
  Assert.IsFalse(TTodoKeywords.IsValid('TO DO'));
end;

procedure TTodoKeywordsTests.KeywordsFromSettings;
var
  mIssues: TArray<TConfigurationIssue>;
  mSettings: TServerSettings;
begin
  Assert.AreEqual('TODO FIXME', string.Join(' ', TTodoKeywords.FromSettings(TServerSettings.Default)));
  // Die Marken gelten auch bei abgeschalteter Regel (für get_todos und --todos).
  mSettings := TConfigurationParser.Parse('{"rules": {"todo-comment": {"severity": "off", "keywords": ["NOTE"]}}}',
    mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.AreEqual('NOTE', string.Join(' ', TTodoKeywords.FromSettings(mSettings)));
end;

end.
