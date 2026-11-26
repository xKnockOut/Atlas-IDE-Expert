unit Atlas.Common.Pascal.CallSites.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TPascalCallSitesTests = class
  public
    /// <summary>Name und aktiver Parameter des offenen Aufrufs; hinter ")" und ";" keiner.</summary>
    [Test]
    procedure FindsCallSiteAndActiveParameter;
    /// <summary>Innere Aufrufe, Indizes und Klammern um Ausdrücke zählen als ein Argument.</summary>
    [Test]
    procedure NestedCallsAndBracketsAreSkipped;
    /// <summary>Token der bisherigen Argumente, das leere letzte eingeschlossen.</summary>
    [Test]
    procedure CollectsArgumentTokens;
  end;

implementation

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Pascal.CallSites;

{ TPascalCallSitesTests }

procedure TPascalCallSitesTests.FindsCallSiteAndActiveParameter;
var
  mTree: TSyntaxTree;
  mSite: TPascalCallSite;
begin
  mTree := TPascalParser.Parse('begin Rechne(1, 2, ');
  try
    mSite := TPascalCallSites.At(mTree, TTextPosition.Create(0, 19));
    Assert.IsTrue(mSite.Found);
    Assert.AreEqual(6, mSite.NamePosition.Character);
    Assert.AreEqual(2, mSite.ActiveParameter);
    // Hinter der schließenden Klammer und nach ; ist kein Aufruf mehr offen.
    Assert.IsFalse(TPascalCallSites.At(mTree, TTextPosition.Create(0, 5)).Found);
  finally
    mTree.Free;
  end;
  mTree := TPascalParser.Parse('begin Rechne(1); X');
  try
    Assert.IsFalse(TPascalCallSites.At(mTree, TTextPosition.Create(0, 18)).Found);
    Assert.IsFalse(TPascalCallSites.At(mTree, TTextPosition.Create(0, 15)).Found);
  finally
    mTree.Free;
  end;
end;

procedure TPascalCallSitesTests.NestedCallsAndBracketsAreSkipped;
var
  mTree: TSyntaxTree;
  mSite: TPascalCallSite;
begin
  mTree := TPascalParser.Parse('begin Rechne(Liste[1, 2], (3 + 4), Max(5, 6), ');
  try
    mSite := TPascalCallSites.At(mTree, TTextPosition.Create(0, 46));
    Assert.IsTrue(mSite.Found);
    Assert.AreEqual(6, mSite.NamePosition.Character);
    Assert.AreEqual(3, mSite.ActiveParameter);
    mSite := TPascalCallSites.At(mTree, TTextPosition.Create(0, 42));
    Assert.AreEqual(35, mSite.NamePosition.Character);
    Assert.AreEqual(1, mSite.ActiveParameter);
  finally
    mTree.Free;
  end;
end;

procedure TPascalCallSitesTests.CollectsArgumentTokens;
var
  mTree: TSyntaxTree;
  mSite: TPascalCallSite;
begin
  mTree := TPascalParser.Parse('begin P(1, X, ');
  try
    mSite := TPascalCallSites.At(mTree, TTextPosition.Create(0, 14));
    Assert.IsTrue(mSite.Found);
    Assert.AreEqual(3, Integer(Length(mSite.ArgumentFirst)));
    Assert.AreEqual('1', mTree.Tokens[mSite.ArgumentFirst[0]].Text);
    Assert.AreEqual('X', mTree.Tokens[mSite.ArgumentLast[1]].Text);
    Assert.IsTrue(mSite.ArgumentFirst[2] > mSite.ArgumentLast[2], 'leeres letztes Argument');
  finally
    mTree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TPascalCallSitesTests);

end.
