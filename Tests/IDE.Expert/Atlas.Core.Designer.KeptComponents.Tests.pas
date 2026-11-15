unit Atlas.Core.Designer.KeptComponents.Tests;

// Tests der gemerkten Komponenten über einen Dialog hinweg (F-104):
// gleiches Formular, gelöschte, umbenannte und verschachtelte Komponenten,
// anderes Formular, Erreichbarkeit und Vergleich zweier Gruppen.

interface

uses
  DUnitX.TestFramework,
  System.Classes,
  Atlas.Core.Designer.KeptComponents;

type
  [TestFixture]
  [Category('Atlas.IDE.Designer')]
  TAtlasKeptComponentsTests = class
  private
    FRoot: TComponent;
    FFirst: TComponent;
    FSecond: TComponent;
    FNested: TComponent;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure UnchangedFormHolds;
    [Test]
    procedure DeletedComponentFails;
    [Test]
    procedure RenamedComponentFails;
    [Test]
    procedure OtherRootFails;
    [Test]
    procedure NilRootFails;
    [Test]
    procedure NestedComponentHolds;
    [Test]
    procedure RootOnlyHolds;
    [Test]
    procedure ReachableFollowsOwners;
    [Test]
    procedure SameAsComparesGroups;
  end;

implementation

function Named(AOwner: TComponent; const AName: string): TComponent;
begin
  Result := TComponent.Create(AOwner);
  Result.Name := AName;
end;

procedure TAtlasKeptComponentsTests.Setup;
begin
  FRoot := Named(nil, 'Form1');
  FFirst := Named(FRoot, 'Edit1');
  FSecond := Named(FRoot, 'Panel1');
  // Wie eine Komponente in einem eingebetteten Frame: gehört dem Frame, nicht dem Formular.
  FNested := Named(FSecond, 'Button1');
end;

procedure TAtlasKeptComponentsTests.TearDown;
begin
  FRoot.Free;
  FRoot := nil;
  FFirst := nil;
  FSecond := nil;
  FNested := nil;
end;

procedure TAtlasKeptComponentsTests.UnchangedFormHolds;
var
  mKept: TAtlasKeptComponents;
begin
  mKept := TAtlasKeptComponents.Take(FRoot);
  mKept.Add(FFirst);
  mKept.Add(FSecond);
  Assert.AreEqual(2, mKept.Count);
  Assert.IsTrue(mKept.Alive(FRoot));
end;

procedure TAtlasKeptComponentsTests.DeletedComponentFails;
var
  mKept: TAtlasKeptComponents;
begin
  mKept := TAtlasKeptComponents.Take(FRoot);
  mKept.Add(FFirst);
  mKept.Add(FNested);
  FNested.Free;
  FNested := nil;
  Assert.IsFalse(mKept.Alive(FRoot));
end;

procedure TAtlasKeptComponentsTests.RenamedComponentFails;
var
  mKept: TAtlasKeptComponents;
begin
  mKept := TAtlasKeptComponents.Take(FRoot);
  mKept.Add(FFirst);
  FFirst.Name := 'Edit2';
  Assert.IsFalse(mKept.Alive(FRoot));
end;

procedure TAtlasKeptComponentsTests.OtherRootFails;
var
  mKept: TAtlasKeptComponents;
  mOther: TComponent;
begin
  mKept := TAtlasKeptComponents.Take(FRoot);
  mKept.Add(FFirst);
  mOther := Named(nil, 'Form1');
  try
    Assert.IsFalse(mKept.Alive(mOther));
  finally
    mOther.Free;
  end;
end;

procedure TAtlasKeptComponentsTests.NilRootFails;
var
  mKept: TAtlasKeptComponents;
begin
  mKept := TAtlasKeptComponents.Take(FRoot);
  Assert.IsFalse(mKept.Alive(nil));
end;

procedure TAtlasKeptComponentsTests.NestedComponentHolds;
var
  mKept: TAtlasKeptComponents;
begin
  mKept := TAtlasKeptComponents.Take(FRoot);
  mKept.Add(FNested);
  mKept.Add(FRoot);
  mKept.Add(nil);
  Assert.AreEqual(2, mKept.Count);
  Assert.IsTrue(mKept.Alive(FRoot));
end;

procedure TAtlasKeptComponentsTests.RootOnlyHolds;
var
  mKept: TAtlasKeptComponents;
begin
  mKept := TAtlasKeptComponents.Take(FRoot);
  Assert.AreEqual(0, mKept.Count);
  Assert.IsTrue(mKept.Alive(FRoot));
  FRoot.Name := 'Form2';
  Assert.IsFalse(mKept.Alive(FRoot));
end;

procedure TAtlasKeptComponentsTests.ReachableFollowsOwners;
var
  mLoose: TComponent;
begin
  Assert.IsTrue(TAtlasKeptComponents.Reachable(FRoot, FRoot));
  Assert.IsTrue(TAtlasKeptComponents.Reachable(FRoot, FNested));
  mLoose := Named(nil, 'Loose1');
  try
    Assert.IsFalse(TAtlasKeptComponents.Reachable(FRoot, mLoose));
    Assert.IsFalse(TAtlasKeptComponents.Reachable(FRoot, nil));
    Assert.IsFalse(TAtlasKeptComponents.Reachable(nil, FFirst));
  finally
    mLoose.Free;
  end;
end;

procedure TAtlasKeptComponentsTests.SameAsComparesGroups;
var
  mBefore, mAfter: TAtlasKeptComponents;
begin
  mBefore := TAtlasKeptComponents.Take(FRoot);
  mBefore.Add(FFirst);
  mBefore.Add(FSecond);
  mAfter := TAtlasKeptComponents.Take(FRoot);
  mAfter.Add(FFirst);
  mAfter.Add(FSecond);
  Assert.IsTrue(mBefore.SameAs(mAfter));
  mAfter := TAtlasKeptComponents.Take(FRoot);
  mAfter.Add(FSecond);
  mAfter.Add(FFirst);
  Assert.IsFalse(mBefore.SameAs(mAfter), 'Reihenfolge');
  mAfter := TAtlasKeptComponents.Take(FRoot);
  mAfter.Add(FFirst);
  Assert.IsFalse(mBefore.SameAs(mAfter), 'Anzahl');
  mAfter := TAtlasKeptComponents.Take(FSecond);
  mAfter.Add(FFirst);
  mAfter.Add(FSecond);
  Assert.IsFalse(mBefore.SameAs(mAfter), 'Formular');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasKeptComponentsTests);

end.
