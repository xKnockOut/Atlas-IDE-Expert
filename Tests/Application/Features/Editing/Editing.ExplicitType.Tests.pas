unit Editing.ExplicitType.Tests;

// Tests für „Typ ausschreiben“ (#453): Typ hinter dem Namen und uses-Eintrag
// für die Unit des Typs.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver;

type
  [TestFixture]
  TExplicitTypeTests = class
  private
    FIndex: ISymbolIndex;
    FResolver: TNameResolver;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>#453: „Typ ausschreiben“ mit uses-Eintrag für die Unit des Typs.</summary>
    [Test]
    procedure ExplicitTypeWritesTypeAndUses;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.CodeActions.Contract,
  Editing.ExplicitType,
  Atlas.Common.Semantics.InferredTypes.TestSupport;

{ TExplicitTypeTests }

procedure TExplicitTypeTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FResolver := TNameResolver.Create(FIndex);
end;

procedure TExplicitTypeTests.TearDown;
begin
  FResolver.Free;
  FResolver := nil;
  FIndex := nil;
end;

procedure TExplicitTypeTests.ExplicitTypeWritesTypeAndUses;
var
  mTree: TSyntaxTree;
  mAction: TCodeAction;
begin
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitDaten, cDatenFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitQuelle, cQuelleFile, nil));
  mTree := TPascalParser.Parse(cUnitNutzer);
  try
    // Auf dem Namen X: ": TDaten" und uses Daten, weil Nutzer nur Quelle einbindet.
    Assert.IsTrue(TExplicitType.Action(FResolver, mTree, cNutzerFile, TTextPosition.Create(9, 6), #10,
      mAction));
    Assert.AreEqual('Typ ausschreiben', mAction.Title);
    Assert.AreEqual(2, Integer(Length(mAction.Edits)));
    Assert.AreEqual(': TDaten', mAction.Edits[0].NewText);
    Assert.AreEqual(9, mAction.Edits[0].Range.StartPos.Line);
    Assert.AreEqual(7, mAction.Edits[0].Range.StartPos.Character);
    Assert.IsTrue(mAction.Edits[1].NewText.Contains('Daten'), mAction.Edits[1].NewText);
    // Integer braucht keine Unit.
    Assert.IsTrue(TExplicitType.Action(FResolver, mTree, cNutzerFile, TTextPosition.Create(10, 10), #10,
      mAction));
    Assert.AreEqual(1, Integer(Length(mAction.Edits)));
    Assert.AreEqual(': Integer', mAction.Edits[0].NewText);
    // Mit Typ bzw. neben dem Namen nichts.
    Assert.IsFalse(TExplicitType.Action(FResolver, mTree, cNutzerFile, TTextPosition.Create(17, 10), #10,
      mAction));
    Assert.IsFalse(TExplicitType.Action(FResolver, mTree, cNutzerFile, TTextPosition.Create(9, 12), #10,
      mAction));
  finally
    mTree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TExplicitTypeTests);

end.
