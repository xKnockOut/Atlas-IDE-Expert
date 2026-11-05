unit Atlas.Core.Problems.Explanation.Tests;

// „Regel erklären“ (#909, #1755): Katalogtext einer Regel aus der Antwort von atlas.server.settingsCatalog.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasRuleExplanationTests = class
  public
    [Test]
    procedure FindsRuleIgnoringCase;
    [Test]
    procedure MissingRuleOrCatalogIsFalse;
  end;

implementation

uses
  System.JSON,
  Atlas.Core.Problems.Explanation;

const
  cCatalog = '{"rules": [{"id": "no-with", "name": "Kein with"},' +
    ' {"id": "empty-except", "name": "Leerer except-Block", "description": "Fehler werden verschluckt.",' +
    ' "bad": "except end;", "good": "except raise; end;", "experimental": true}]}';

procedure TAtlasRuleExplanationTests.FindsRuleIgnoringCase;
var
  mCatalog: TJSONValue;
  mExplanation: TAtlasRuleExplanation;
begin
  mCatalog := TJSONObject.ParseJSONValue(cCatalog);
  try
    Assert.IsTrue(TAtlasRuleExplanation.Find(mCatalog, 'Empty-Except', mExplanation));
    Assert.AreEqual('empty-except', mExplanation.Id);
    Assert.AreEqual('Leerer except-Block', mExplanation.Name);
    Assert.AreEqual('Fehler werden verschluckt.', mExplanation.Description);
    Assert.AreEqual('except end;', mExplanation.Bad);
    Assert.AreEqual('except raise; end;', mExplanation.Good);
    Assert.IsTrue(mExplanation.Experimental);
    // Fehlende Felder bleiben leer.
    Assert.IsTrue(TAtlasRuleExplanation.Find(mCatalog, 'no-with', mExplanation));
    Assert.AreEqual('', mExplanation.Bad);
    Assert.IsFalse(mExplanation.Experimental);
  finally
    mCatalog.Free;
  end;
end;

procedure TAtlasRuleExplanationTests.MissingRuleOrCatalogIsFalse;
var
  mCatalog: TJSONValue;
  mExplanation: TAtlasRuleExplanation;
begin
  Assert.IsFalse(TAtlasRuleExplanation.Find(nil, 'no-with', mExplanation), 'ohne Katalog (Server läuft nicht)');
  Assert.AreEqual('', mExplanation.Id);
  mCatalog := TJSONObject.ParseJSONValue(cCatalog);
  try
    Assert.IsFalse(TAtlasRuleExplanation.Find(mCatalog, 'unbekannt', mExplanation));
    Assert.IsFalse(TAtlasRuleExplanation.Find(mCatalog, '', mExplanation), 'Compilermeldung ohne Regel');
  finally
    mCatalog.Free;
  end;
  mCatalog := TJSONObject.ParseJSONValue('{"rules": 1}');
  try
    Assert.IsFalse(TAtlasRuleExplanation.Find(mCatalog, 'no-with', mExplanation), '"rules" keine Liste');
  finally
    mCatalog.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasRuleExplanationTests);

end.
