unit Atlas.Core.Problems.Explanation.Tests;

// „Regel erklären“ (#909, #1755): Katalogtext einer Regel aus der Antwort von atlas.server.settingsCatalog;
// Compilermeldungen nach ihrer Nummer (#54).

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
    [Test]
    procedure FindsCompilerMessageByCode;
    [Test]
    procedure MessageCodeFromCodeOrText;
    [Test]
    procedure KeyPrefersMessageCodeThenRule;
  end;

implementation

uses
  System.JSON,
  Atlas.Core.Lsp.Contract,
  Atlas.Core.Problems.Explanation;

const
  cCatalog = '{"rules": [{"id": "no-with", "name": "Kein with"},' +
    ' {"id": "empty-except", "name": "Leerer except-Block", "description": "Fehler werden verschluckt.",' +
    ' "bad": "except end;", "good": "except raise; end;", "experimental": true}],' +
    ' "messages": [{"code": "E2003", "name": "Undeklarierter Bezeichner", "description": "Unbekannt.",' +
    ' "cause": "Unit fehlt in uses.", "bad": "x := 1;", "good": "var x: Integer;",' +
    ' "docWiki": "https://docwiki.embarcadero.com/RADStudio/Athens/e/index.php?search=E2003"}]}';

function Problem(const ASource, ACode, AMessage: string): TAtlasProblem;
begin
  Result := Default(TAtlasProblem);
  Result.Source := ASource;
  Result.Code := ACode;
  Result.Message := AMessage;
end;

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

procedure TAtlasRuleExplanationTests.FindsCompilerMessageByCode;
var
  mCatalog: TJSONValue;
  mExplanation: TAtlasRuleExplanation;
begin
  mCatalog := TJSONObject.ParseJSONValue(cCatalog);
  try
    Assert.IsTrue(TAtlasRuleExplanation.Find(mCatalog, 'e2003', mExplanation));
    Assert.AreEqual('E2003', mExplanation.Id);
    Assert.AreEqual('Undeklarierter Bezeichner', mExplanation.Name);
    Assert.AreEqual('Unit fehlt in uses.', mExplanation.Cause);
    Assert.AreEqual('var x: Integer;', mExplanation.Good);
    Assert.IsTrue(Pos('search=E2003', mExplanation.DocWiki) > 0);
    // Regeln haben weder Ursache noch DocWiki.
    Assert.IsTrue(TAtlasRuleExplanation.Find(mCatalog, 'empty-except', mExplanation));
    Assert.AreEqual('', mExplanation.Cause);
    Assert.AreEqual('', mExplanation.DocWiki);
    Assert.IsFalse(TAtlasRuleExplanation.Find(mCatalog, 'E2004', mExplanation));
  finally
    mCatalog.Free;
  end;
end;

procedure TAtlasRuleExplanationTests.MessageCodeFromCodeOrText;
begin
  Assert.AreEqual('E2003', TAtlasRuleExplanation.MessageCode(Problem('dcc', 'e2003', 'Undeklarierter Bezeichner')));
  Assert.AreEqual('W1036', TAtlasRuleExplanation.MessageCode(Problem('dcc', '',
    '[dcc32 Warnung] W1036 Variable X ist möglicherweise nicht initialisiert')));
  Assert.AreEqual('E2010', TAtlasRuleExplanation.MessageCode(Problem('IDE', '', 'E2010 Inkompatible Typen')));
  // Teil eines Worts ist keine Nummer.
  Assert.AreEqual('', TAtlasRuleExplanation.MessageCode(Problem('dcc', '', 'Feld XE20031 fehlt')));
  // Regelbefunde haben keine Meldungsnummer, auch wenn der Text eine nennt.
  Assert.AreEqual('', TAtlasRuleExplanation.MessageCode(Problem('Atlas', 'exit-array-literal', 'wie E2010')));
end;

procedure TAtlasRuleExplanationTests.KeyPrefersMessageCodeThenRule;
begin
  Assert.AreEqual('E2003', TAtlasRuleExplanation.Key(Problem('dcc', 'E2003', '')));
  Assert.AreEqual('empty-except', TAtlasRuleExplanation.Key(Problem('Atlas', 'empty-except', '')));
  Assert.AreEqual('', TAtlasRuleExplanation.Key(Problem('dcc', '', 'Fatal: kein Code')));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasRuleExplanationTests);

end.
