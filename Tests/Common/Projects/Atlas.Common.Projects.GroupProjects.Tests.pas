unit Atlas.Common.Projects.GroupProjects.Tests;

// Tests für ein Projekt der Gruppe als Wert: Art und Testprojekt aus dem Hauptquelltext.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TGroupProjectsTests = class
  public
    [Test]
    procedure KindAndTestsFromMainSource;
  end;

implementation

uses
  Atlas.Common.Projects.Contract.Group,
  Atlas.Common.Projects.GroupProjects;

{ TGroupProjectsTests }

procedure TGroupProjectsTests.KindAndTestsFromMainSource;
begin
  Assert.AreEqual<TGroupProjectKind>(TGroupProjectKind.Application, TGroupProjects.KindOfSource('App.dpr',
    '{ Kopf }'#10'program App;'#10'begin'#10'end.'));
  Assert.AreEqual<TGroupProjectKind>(TGroupProjectKind.Library_, TGroupProjects.KindOfSource('Dll.dpr', 'library Dll;'#10'begin'#10'end.'));
  Assert.AreEqual<TGroupProjectKind>(TGroupProjectKind.Package, TGroupProjects.KindOfSource('Pak.dpk', ''));
  Assert.AreEqual<TGroupProjectKind>(TGroupProjectKind.Package, TGroupProjects.KindOfSource('Pak.dpr', 'package Pak;'#10'end.'));
  Assert.AreEqual<TGroupProjectKind>(TGroupProjectKind.Unknown, TGroupProjects.KindOfSource('X.pas', 'unit X;'));
  Assert.IsTrue(TGroupProjects.IsTestSource('program T;'#10'uses'#10'  DUnitX.TestFramework;'#10'begin'#10'end.'));
  Assert.IsFalse(TGroupProjects.IsTestSource('program App;'#10'uses'#10'  Vcl.Forms;'#10'begin'#10'end.'));
end;

initialization
  TDUnitX.RegisterTestFixture(TGroupProjectsTests);

end.
