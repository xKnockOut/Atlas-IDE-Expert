unit Atlas.Core.Lsp.Contract.Tests;

// Werttypen des Lsp-Features: direkt und über die Aliase in Problems.Contract und Results.Model.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspContractTests = class
  public
    [Test]
    procedure ProblemFromJsonViaLspContract;
    [Test]
    procedure AliasesAreTheSameTypes;
    [Test]
    procedure SyntaxErrorsCannotBeSuppressed;
    /// <summary>atlasConfidence (#1119): erschlossen mit Grund; ohne Feld sicher.</summary>
    [Test]
    procedure ConfidenceFromJson;
    /// <summary>relatedInformation (#896): Stellen eines Unit-Zyklus.</summary>
    [Test]
    procedure RelatedFromJson;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Core.Lsp.Contract,
  Atlas.Core.Problems.Contract,
  Atlas.Core.Results.Model;

procedure TLspContractTests.ProblemFromJsonViaLspContract;
var
  mJson: TJSONObject;
  mProblem: Atlas.Core.Lsp.Contract.TAtlasProblem;
begin
  mJson := TJSONObject.ParseJSONValue('{"range":{"start":{"line":2,"character":4},"end":{"line":2,' +
    '"character":9}},"severity":2,"code":"W1000","source":"Atlas","message":"Achtung"}') as TJSONObject;
  try
    mProblem := Atlas.Core.Lsp.Contract.TAtlasProblem.FromJson(mJson);
  finally
    mJson.Free;
  end;
  Assert.AreEqual(2, mProblem.StartLine);
  Assert.AreEqual(9, mProblem.EndCharacter);
  Assert.AreEqual<Atlas.Core.Lsp.Contract.TAtlasProblemSeverity>(Atlas.Core.Lsp.Contract.TAtlasProblemSeverity.Warning,
    mProblem.Severity);
  Assert.AreEqual('Achtung (W1000)', mProblem.Caption);
end;

procedure TLspContractTests.RelatedFromJson;
var
  mJson: TJSONObject;
  mProblem: Atlas.Core.Lsp.Contract.TAtlasProblem;
begin
  mJson := TJSONObject.ParseJSONValue('{"range":{"start":{"line":3,"character":2},"end":{"line":3,"character":4}},' +
    '"severity":1,"code":"uses-cycle","source":"Atlas","message":"Zyklus","relatedInformation":[' +
    '{"location":{"uri":"file:///c%3A/p/B.pas","range":{"start":{"line":5,"character":2},"end":{"line":5,' +
    '"character":4}}},"message":"uC"},{"location":{"uri":"","range":{}},"message":"leer"},' +
    '{"location":{"uri":"file:///c%3A/p/C.pas","range":{"start":{"line":3,"character":2},"end":{"line":3,' +
    '"character":4}}},"message":"uA"}]}') as TJSONObject;
  try
    mProblem := Atlas.Core.Lsp.Contract.TAtlasProblem.FromJson(mJson);
  finally
    mJson.Free;
  end;
  // Einträge ohne URI fallen weg.
  Assert.AreEqual(2, Integer(Length(mProblem.Related)));
  Assert.AreEqual('uC', mProblem.Related[0].Message);
  Assert.AreEqual('file:///c%3A/p/B.pas', mProblem.Related[0].Uri);
  Assert.AreEqual(5, mProblem.Related[0].Line);
  Assert.AreEqual(2, mProblem.Related[0].Character);
  Assert.AreEqual('uA', mProblem.Related[1].Message);
  mProblem.Related := nil;
end;

procedure TLspContractTests.ConfidenceFromJson;
var
  mJson: TJSONValue;
  mConfidence: TAtlasConfidence;
begin
  mJson := TJSONObject.ParseJSONValue('{"uri":"file:///c%3A/a.pas","atlasConfidence":{"level":"inferred",' +
    '"reason":"interface","detail":"Aufruf über I.M"}}');
  try
    mConfidence := TAtlasConfidence.FromJson(mJson);
  finally
    mJson.Free;
  end;
  Assert.IsTrue(mConfidence.Inferred);
  Assert.AreEqual('interface', mConfidence.Reason);
  Assert.AreEqual('Aufruf über I.M', mConfidence.Explanation);
  mJson := TJSONObject.ParseJSONValue('{"atlasConfidence":{"level":"sure"}}');
  try
    mConfidence := TAtlasConfidence.FromJson(mJson);
  finally
    mJson.Free;
  end;
  Assert.IsFalse(mConfidence.Inferred);
  Assert.AreEqual('', mConfidence.Reason);
  // Ältere Server ohne Feld, und kein Objekt.
  mJson := TJSONObject.ParseJSONValue('{"uri":"file:///c%3A/a.pas"}');
  try
    Assert.IsFalse(TAtlasConfidence.FromJson(mJson).Inferred);
  finally
    mJson.Free;
  end;
  Assert.IsFalse(TAtlasConfidence.FromJson(nil).Inferred);
end;

procedure TLspContractTests.AliasesAreTheSameTypes;
var
  mProblem: Atlas.Core.Problems.Contract.TAtlasProblem;
  mDirect: Atlas.Core.Lsp.Contract.TAtlasProblem;
  mItem: Atlas.Core.Results.Model.TAtlasHierarchyItem;
  mSymbol: Atlas.Core.Results.Model.TAtlasSymbol;
begin
  mDirect := Default(Atlas.Core.Lsp.Contract.TAtlasProblem);
  mDirect.Message := 'x';
  mDirect.Severity := Atlas.Core.Problems.Contract.TAtlasProblemSeverity.Hint;
  mProblem := mDirect;
  Assert.AreEqual('x', mProblem.Caption);
  Assert.AreEqual<Atlas.Core.Lsp.Contract.TAtlasProblemSeverity>(Atlas.Core.Lsp.Contract.TAtlasProblemSeverity.Hint,
    mProblem.Severity);
  mItem := Default(Atlas.Core.Lsp.Contract.TAtlasHierarchyItem);
  mItem.Name := 'Run';
  Assert.AreEqual('Run', mItem.Name);
  mSymbol := Default(Atlas.Core.Lsp.Contract.TAtlasSymbol);
  mSymbol.Kind := 12;
  Assert.AreEqual(12, mSymbol.Kind);
  Assert.IsTrue(TAtlasResults.IsCallHierarchy(Atlas.Core.Results.Model.TAtlasHierarchyDirection.Incoming));
end;

procedure TLspContractTests.SyntaxErrorsCannotBeSuppressed;
var
  mProblem: Atlas.Core.Lsp.Contract.TAtlasProblem;
begin
  mProblem := Default(Atlas.Core.Lsp.Contract.TAtlasProblem);
  mProblem.Code := 'empty-except';
  Assert.IsTrue(mProblem.CanSuppress);
  mProblem.Code := 'syntax';
  Assert.IsFalse(mProblem.CanSuppress);
  mProblem.Code := 'language-feature';
  Assert.IsFalse(mProblem.CanSuppress);
  mProblem.Code := '';
  Assert.IsFalse(mProblem.CanSuppress);
end;

initialization
  TDUnitX.RegisterTestFixture(TLspContractTests);

end.
