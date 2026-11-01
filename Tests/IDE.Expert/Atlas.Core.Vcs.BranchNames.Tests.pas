unit Atlas.Core.Vcs.BranchNames.Tests;

// Tests für Branch-Namen und Basen (#1286, #1288; bis #1455 in Atlas.Core.Tracker.Naming).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasVcsBranchNamesTests = class
  public
    [Test]
    procedure ValidFollowsCheckRefFormat;
    /// <summary>#1286: issues.branchBase, sonst Hauptbranch des Projekts, sonst geraten.</summary>
    [Test]
    procedure BasesPreferBranchBaseThenMainBranch;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Vcs.BranchNames;

procedure TAtlasVcsBranchNamesTests.ValidFollowsCheckRefFormat;
begin
  Assert.IsTrue(TAtlasVcsBranchNames.Valid('feature/753-x'));
  Assert.IsFalse(TAtlasVcsBranchNames.Valid(''));
  Assert.IsFalse(TAtlasVcsBranchNames.Valid('-x'));
  Assert.IsFalse(TAtlasVcsBranchNames.Valid('a/.b'));
  Assert.IsFalse(TAtlasVcsBranchNames.Valid('a.lock'));
  Assert.IsFalse(TAtlasVcsBranchNames.Valid('a b'));
  Assert.IsFalse(TAtlasVcsBranchNames.Valid('a@{b'));
  Assert.IsFalse(TAtlasVcsBranchNames.Valid('@'));
  Assert.IsFalse(TAtlasVcsBranchNames.Valid('a//b'));
  Assert.IsFalse(TAtlasVcsBranchNames.Valid('a/'));
end;

procedure TAtlasVcsBranchNamesTests.BasesPreferBranchBaseThenMainBranch;
var
  mBases: TArray<string>;
begin
  mBases := TAtlasVcsBranchNames.Bases(False, '', '');
  Assert.AreEqual(2, Integer(Length(mBases)));
  Assert.AreEqual('main', mBases[0]);
  Assert.AreEqual('master', mBases[1]);
  mBases := TAtlasVcsBranchNames.Bases(True, '', '');
  Assert.AreEqual('trunk', string.Join(',', mBases));
  Assert.AreEqual('develop', string.Join(',', TAtlasVcsBranchNames.Bases(False, '', ' develop ')));
  Assert.AreEqual('develop', string.Join(',', TAtlasVcsBranchNames.Bases(True, '', 'develop')));
  Assert.AreEqual('release', string.Join(',', TAtlasVcsBranchNames.Bases(False, 'release', 'develop')));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasVcsBranchNamesTests);

end.
