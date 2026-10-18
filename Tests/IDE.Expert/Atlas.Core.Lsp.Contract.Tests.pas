unit Atlas.Core.Lsp.Contract.Tests;

// Werttypen des Lsp-Features (A-09): direkt und über die Aliase in Problems.Contract und Results.Model.

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
  Json: TJSONObject;
  Problem: Atlas.Core.Lsp.Contract.TAtlasProblem;
begin
  Json := TJSONObject.ParseJSONValue('{"range":{"start":{"line":2,"character":4},"end":{"line":2,' +
    '"character":9}},"severity":2,"code":"W1000","source":"Atlas","message":"Achtung"}') as TJSONObject;
  try
    Problem := Atlas.Core.Lsp.Contract.TAtlasProblem.FromJson(Json);
  finally
    Json.Free;
  end;
  Assert.AreEqual(2, Problem.StartLine);
  Assert.AreEqual(9, Problem.EndCharacter);
  Assert.IsTrue(Problem.Severity = Atlas.Core.Lsp.Contract.TAtlasProblemSeverity.Warning);
  Assert.AreEqual('Achtung (W1000)', Problem.Caption);
end;

procedure TLspContractTests.AliasesAreTheSameTypes;
var
  Problem: Atlas.Core.Problems.Contract.TAtlasProblem;
  Direct: Atlas.Core.Lsp.Contract.TAtlasProblem;
  Item: Atlas.Core.Results.Model.TAtlasHierarchyItem;
  Symbol: Atlas.Core.Results.Model.TAtlasSymbol;
begin
  Direct := Default(Atlas.Core.Lsp.Contract.TAtlasProblem);
  Direct.Message := 'x';
  Direct.Severity := Atlas.Core.Problems.Contract.TAtlasProblemSeverity.Hint;
  Problem := Direct;
  Assert.AreEqual('x', Problem.Caption);
  Assert.IsTrue(Problem.Severity = Atlas.Core.Lsp.Contract.TAtlasProblemSeverity.Hint);
  Item := Default(Atlas.Core.Lsp.Contract.TAtlasHierarchyItem);
  Item.Name := 'Run';
  Assert.AreEqual('Run', Item.Name);
  Symbol := Default(Atlas.Core.Lsp.Contract.TAtlasSymbol);
  Symbol.Kind := 12;
  Assert.AreEqual(12, Symbol.Kind);
  Assert.IsTrue(TAtlasResults.IsCallHierarchy(Atlas.Core.Results.Model.TAtlasHierarchyDirection.Incoming));
end;

initialization
  TDUnitX.RegisterTestFixture(TLspContractTests);

end.
