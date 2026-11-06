unit Atlas.Common.Editing.Inlining.Types.Tests;

// Tests für die Typen von „Einbetten“ (#103, Teil A): Datei, eingebettete
// Methode und Vorgaben der Optionen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TInlineTypesTests = class
  public
    [Test]
    procedure SourceKeepsFileTextAndTree;
    [Test]
    procedure CalleeKeepsSourceAndRoutine;
    [Test]
    procedure DefaultOptionsUseInlineVariables;
  end;

implementation

uses
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.Inlining.Types;

procedure TInlineTypesTests.SourceKeepsFileTextAndTree;
var
  mTree: TSyntaxTree;
  mSource: TInlineSource;
begin
  mTree := TPascalParser.Parse('unit U; interface implementation end.');
  try
    mSource := TInlineSource.Create('u.pas', 'unit U;', mTree);
    Assert.AreEqual('u.pas', mSource.FileName);
    Assert.AreEqual('unit U;', mSource.Text);
    Assert.IsTrue(mSource.Tree = mTree);
  finally
    mTree.Free;
  end;
end;

procedure TInlineTypesTests.CalleeKeepsSourceAndRoutine;
var
  mTree: TSyntaxTree;
  mCallee: TInlineCallee;
begin
  mTree := TPascalParser.Parse('unit U; interface implementation end.');
  try
    mCallee := TInlineCallee.Create(TInlineSource.Create('c.pas', 'x', mTree), mTree.Root);
    Assert.AreEqual('c.pas', mCallee.Source.FileName);
    Assert.IsTrue(mCallee.Routine = mTree.Root);
  finally
    mTree.Free;
  end;
end;

procedure TInlineTypesTests.DefaultOptionsUseInlineVariables;
var
  mOptions: TInlineOptions;
begin
  mOptions := TInlineOptions.Default;
  Assert.IsTrue(mOptions.InlineVar);
  Assert.IsFalse(Assigned(mOptions.Lookup));
  Assert.AreEqual('Result', cInlineResultSuffix);
end;

initialization
  TDUnitX.RegisterTestFixture(TInlineTypesTests);

end.
