unit Atlas.Common.Semantics.ComponentRoots.Tests;

// Tests für die Vorfahren der Komponenten und Steuerelemente.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TComponentRootsTests = class
  public
    [Test]
    procedure ChainWithComponentDescends;
    [Test]
    procedure IgnoresCase;
    [Test]
    procedure EmptyChainDoesNotDescend;
    [Test]
    procedure DataModuleIsNoControl;
  end;

implementation

uses
  Atlas.Common.Semantics.ComponentRoots;

procedure TComponentRootsTests.ChainWithComponentDescends;
begin
  Assert.IsTrue(DescendsFrom(TArray<string>.Create('TMeinRahmen', 'TPersistent', 'TComponent'), cComponentRoots));
end;

procedure TComponentRootsTests.IgnoresCase;
begin
  Assert.IsTrue(DescendsFrom(TArray<string>.Create('twincontrol'), cControlRoots));
end;

procedure TComponentRootsTests.EmptyChainDoesNotDescend;
begin
  Assert.IsFalse(DescendsFrom(nil, cComponentRoots));
end;

procedure TComponentRootsTests.DataModuleIsNoControl;
begin
  Assert.IsTrue(DescendsFrom(TArray<string>.Create('TDataModule'), cComponentRoots));
  Assert.IsFalse(DescendsFrom(TArray<string>.Create('TDataModule'), cControlRoots));
end;

initialization
  TDUnitX.RegisterTestFixture(TComponentRootsTests);

end.
