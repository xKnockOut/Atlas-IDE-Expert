unit Atlas.Core.Tasks.OutputGroup.Tests;

// Tests für das Register „Atlas-Aufgaben“ beim Leeren (#900): ohne
// angelegte Gruppe kein Aufruf der IDE, beim Beenden der IDE nur vergessen,
// sonst entfernen; danach gilt die Gruppe als nicht angelegt.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Build')]
  TAtlasTaskOutputGroupTests = class
  public
    [Test]
    procedure WithoutGroupNothingToDo;
    [Test]
    procedure IdeClosingOnlyForgets;
    [Test]
    procedure RunningIdeRemovesOnce;
  end;

implementation

uses
  Atlas.Core.Tasks.OutputGroup;

{ TAtlasTaskOutputGroupTests }

procedure TAtlasTaskOutputGroupTests.WithoutGroupNothingToDo;
var
  mGroup: TAtlasTaskOutputGroup;
begin
  mGroup := Default(TAtlasTaskOutputGroup);
  Assert.IsFalse(mGroup.Created);
  Assert.IsTrue(mGroup.Release(False) = TAtlasTaskOutputRelease.None);
  // Abbau beim Beenden der IDE ohne gelaufene Aufgabe: kein Aufruf des Meldungsfensters.
  Assert.IsTrue(mGroup.Release(True) = TAtlasTaskOutputRelease.None);
end;

procedure TAtlasTaskOutputGroupTests.IdeClosingOnlyForgets;
var
  mGroup: TAtlasTaskOutputGroup;
begin
  mGroup := Default(TAtlasTaskOutputGroup);
  mGroup.Used;
  Assert.IsTrue(mGroup.Release(True) = TAtlasTaskOutputRelease.Forget);
  Assert.IsFalse(mGroup.Created);
end;

procedure TAtlasTaskOutputGroupTests.RunningIdeRemovesOnce;
var
  mGroup: TAtlasTaskOutputGroup;
begin
  mGroup := Default(TAtlasTaskOutputGroup);
  mGroup.Used;
  mGroup.Used;
  Assert.IsTrue(mGroup.Created);
  Assert.IsTrue(mGroup.Release(False) = TAtlasTaskOutputRelease.Remove);
  Assert.IsTrue(mGroup.Release(False) = TAtlasTaskOutputRelease.None);
end;

end.
