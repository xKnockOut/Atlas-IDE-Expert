unit Atlas.Core.Tasks.OutputGroup.Tests;

// Tests für das Register „Atlas-Aufgaben“ beim Leeren (#900): ohne
// angelegte Gruppe kein Aufruf der IDE, beim Beenden der IDE nur vergessen,
// sonst entfernen; danach gilt die Gruppe als nicht angelegt.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
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
  Group: TAtlasTaskOutputGroup;
begin
  Group := Default(TAtlasTaskOutputGroup);
  Assert.IsFalse(Group.Created);
  Assert.IsTrue(Group.Release(False) = TAtlasTaskOutputRelease.None);
  // Abbau beim Beenden der IDE ohne gelaufene Aufgabe: kein Aufruf des Meldungsfensters.
  Assert.IsTrue(Group.Release(True) = TAtlasTaskOutputRelease.None);
end;

procedure TAtlasTaskOutputGroupTests.IdeClosingOnlyForgets;
var
  Group: TAtlasTaskOutputGroup;
begin
  Group := Default(TAtlasTaskOutputGroup);
  Group.Used;
  Assert.IsTrue(Group.Release(True) = TAtlasTaskOutputRelease.Forget);
  Assert.IsFalse(Group.Created);
end;

procedure TAtlasTaskOutputGroupTests.RunningIdeRemovesOnce;
var
  Group: TAtlasTaskOutputGroup;
begin
  Group := Default(TAtlasTaskOutputGroup);
  Group.Used;
  Group.Used;
  Assert.IsTrue(Group.Created);
  Assert.IsTrue(Group.Release(False) = TAtlasTaskOutputRelease.Remove);
  Assert.IsTrue(Group.Release(False) = TAtlasTaskOutputRelease.None);
end;

end.
