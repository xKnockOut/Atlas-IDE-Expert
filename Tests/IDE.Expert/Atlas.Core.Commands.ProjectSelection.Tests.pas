unit Atlas.Core.Commands.ProjectSelection.Tests;

// Tests der Auswahl im Kontextmenü der Projektverwaltung (#1817): Units aus
// Dateien, Formulardateien, Ordnern und Projekten, ohne Doppelte; Auswahl
// beim Aufbau des Menüs nur nach Art; Kontext nur zwischen Enter und Leave.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasProjectSelectionTests = class
  public
    [Test]
    procedure KindFollowsExtension;
    [Test]
    procedure UnitStaysItself;
    /// <summary>Akzeptanz: Formulardatei ohne Unit trägt nichts bei.</summary>
    [Test]
    procedure FormBecomesItsUnit;
    /// <summary>Akzeptanz: Ordner prüft alle enthaltenen Units.</summary>
    [Test]
    procedure FolderTakesUnitsBelow;
    [Test]
    procedure ProjectTakesAllUnits;
    /// <summary>Akzeptanz: Mehrfachauswahl ohne Doppelte, Reihenfolge der Auswahl.</summary>
    [Test]
    procedure MultipleWithoutDuplicates;
    /// <summary>Knoten aus zwei Projekten.</summary>
    [Test]
    procedure MergeAddsOtherProject;
    [Test]
    procedure KindsOnlyIsUnresolved;
    /// <summary>Akzeptanz: Projekt ohne Units hat keinen Eintrag.</summary>
    [Test]
    procedure ProjectWithoutUnitsHasNone;
    [Test]
    procedure SingleUnitNeedsOneNode;
    [Test]
    procedure ContextOnlyBetweenEnterAndLeave;
    /// <summary>Rechtsklick auf ein Projekt mit über 2000 Units darf die IDE nicht anhalten (früher quadratisch).
    /// </summary>
    [Test]
    [Category('Benchmark')]
    procedure LargeProjectResolvesQuickly;
  end;

implementation

uses
  System.SysUtils,
  System.Diagnostics,
  Atlas.Core.Commands.ProjectSelection;

function ProjectFiles: TArray<string>;
begin
  Result := ['C:\P\App.dpr', 'C:\P\Main.pas', 'C:\P\Main.dfm', 'C:\P\Core\Model.pas', 'C:\P\Core\Store.pas',
    'C:\P\CoreTools\Tool.pas', 'C:\P\App.res'];
end;

procedure TAtlasProjectSelectionTests.KindFollowsExtension;
begin
  Assert.AreEqual<TAtlasProjectNodeKind>(TAtlasProjectNodeKind.SourceFile,
    TAtlasProjectSelection.KindOf('C:\P\Main.PAS'));
  Assert.AreEqual<TAtlasProjectNodeKind>(TAtlasProjectNodeKind.FormFile,
    TAtlasProjectSelection.KindOf('C:\P\Main.dfm'));
  Assert.AreEqual<TAtlasProjectNodeKind>(TAtlasProjectNodeKind.FormFile,
    TAtlasProjectSelection.KindOf('C:\P\Main.fmx'));
  Assert.AreEqual<TAtlasProjectNodeKind>(TAtlasProjectNodeKind.Project,
    TAtlasProjectSelection.KindOf('C:\P\App.dproj'));
  Assert.AreEqual<TAtlasProjectNodeKind>(TAtlasProjectNodeKind.Folder, TAtlasProjectSelection.KindOf('C:\P\Core'));
  Assert.AreEqual<TAtlasProjectNodeKind>(TAtlasProjectNodeKind.Folder, TAtlasProjectSelection.KindOf('C:\P\v1.2\'));
  Assert.AreEqual<TAtlasProjectNodeKind>(TAtlasProjectNodeKind.OtherFile,
    TAtlasProjectSelection.KindOf('C:\P\App.res'));
end;

procedure TAtlasProjectSelectionTests.UnitStaysItself;
var
  Selection: TAtlasProjectSelection;
begin
  Selection := TAtlasProjectSelection.Resolve(['C:\Other\Extra.pas'], 'C:\P\App.dproj', ProjectFiles);
  Assert.IsTrue(Selection.Resolved);
  Assert.AreEqual(1, Integer(Length(Selection.Units)));
  Assert.AreEqual('C:\Other\Extra.pas', Selection.Units[0], 'auch außerhalb des Projekts');
end;

procedure TAtlasProjectSelectionTests.FormBecomesItsUnit;
var
  Selection: TAtlasProjectSelection;
begin
  Selection := TAtlasProjectSelection.Resolve(['c:\p\main.dfm'], 'C:\P\App.dproj', ProjectFiles);
  Assert.AreEqual(1, Integer(Length(Selection.Units)));
  Assert.AreEqual('C:\P\Main.pas', Selection.Units[0], 'Schreibweise des Projekts');
  Selection := TAtlasProjectSelection.Resolve(['C:\P\Lonely.dfm'], 'C:\P\App.dproj', ProjectFiles);
  Assert.IsFalse(Selection.HasUnits);
end;

procedure TAtlasProjectSelectionTests.FolderTakesUnitsBelow;
var
  Selection: TAtlasProjectSelection;
begin
  Selection := TAtlasProjectSelection.Resolve(['C:\P\Core'], 'C:\P\App.dproj', ProjectFiles);
  Assert.AreEqual(2, Integer(Length(Selection.Units)), 'CoreTools gehört nicht dazu');
  Assert.AreEqual('C:\P\Core\Model.pas', Selection.Units[0]);
  Assert.AreEqual('C:\P\Core\Store.pas', Selection.Units[1]);
end;

procedure TAtlasProjectSelectionTests.ProjectTakesAllUnits;
var
  Selection: TAtlasProjectSelection;
begin
  Selection := TAtlasProjectSelection.Resolve(['C:\P\App.dproj'], 'C:\P\App.dproj', ProjectFiles);
  Assert.AreEqual(4, Integer(Length(Selection.Units)), 'nur .pas, ohne .dpr, .dfm und .res');
  Assert.IsTrue(TAtlasProjectNodeKind.Project in Selection.Kinds);
end;

procedure TAtlasProjectSelectionTests.MultipleWithoutDuplicates;
var
  Selection: TAtlasProjectSelection;
begin
  Selection := TAtlasProjectSelection.Resolve(['C:\P\Core\Store.pas', 'C:\P\Main.dfm', 'c:\p\main.pas',
    'C:\P\Core'], 'C:\P\App.dproj', ProjectFiles);
  Assert.IsTrue(Selection.Multiple);
  Assert.AreEqual(3, Integer(Length(Selection.Units)));
  Assert.AreEqual('C:\P\Core\Store.pas', Selection.Units[0]);
  Assert.AreEqual('C:\P\Main.pas', Selection.Units[1]);
  Assert.AreEqual('C:\P\Core\Model.pas', Selection.Units[2]);
end;

procedure TAtlasProjectSelectionTests.MergeAddsOtherProject;
var
  Selection: TAtlasProjectSelection;
begin
  Selection := TAtlasProjectSelection.Merge(
    TAtlasProjectSelection.Resolve(['C:\P\Main.pas'], 'C:\P\App.dproj', ProjectFiles),
    TAtlasProjectSelection.Resolve(['C:\Q\Tests.dproj'], 'C:\Q\Tests.dproj', ['C:\Q\T.pas', 'C:\P\Main.pas']));
  Assert.AreEqual('C:\P\App.dproj', Selection.ProjectFile);
  Assert.IsTrue(Selection.Multiple);
  Assert.IsTrue(Selection.Resolved);
  Assert.AreEqual(2, Integer(Length(Selection.Units)));
  Assert.AreEqual('C:\Q\T.pas', Selection.Units[1]);
end;

procedure TAtlasProjectSelectionTests.KindsOnlyIsUnresolved;
var
  Selection: TAtlasProjectSelection;
begin
  Selection := TAtlasProjectSelection.OfKinds([TAtlasProjectNodeKind.SourceFile], False, 'C:\P\App.dproj',
    ProjectFiles);
  Assert.IsFalse(Selection.Resolved);
  Assert.IsTrue(Selection.HasUnits);
  Selection := TAtlasProjectSelection.OfKinds([TAtlasProjectNodeKind.OtherFile], False, 'C:\P\App.dproj',
    ProjectFiles);
  Assert.IsFalse(Selection.HasUnits, 'Ressource ohne Unit');
  Selection := TAtlasProjectSelection.OfKinds([TAtlasProjectNodeKind.Project], False, 'C:\P\App.dproj',
    ProjectFiles);
  Assert.IsTrue(Selection.Resolved, 'einzelnes Projekt: Units bekannt');
  Assert.AreEqual(4, Integer(Length(Selection.Units)));
end;

procedure TAtlasProjectSelectionTests.ProjectWithoutUnitsHasNone;
var
  Selection: TAtlasProjectSelection;
begin
  Selection := TAtlasProjectSelection.OfKinds([TAtlasProjectNodeKind.Project], False, 'C:\Q\Empty.dproj',
    ['C:\Q\Empty.dpr']);
  Assert.IsFalse(Selection.HasUnits);
  Selection := TAtlasProjectSelection.OfKinds([TAtlasProjectNodeKind.Folder], False, 'C:\Q\Empty.dproj',
    ['C:\Q\Empty.dpr']);
  Assert.IsFalse(Selection.HasUnits);
end;

procedure TAtlasProjectSelectionTests.SingleUnitNeedsOneNode;
var
  Selection: TAtlasProjectSelection;
  FileName: string;
begin
  Selection := TAtlasProjectSelection.Resolve(['C:\P\Main.dfm'], 'C:\P\App.dproj', ProjectFiles);
  Assert.IsTrue(Selection.SingleUnit(FileName));
  Assert.AreEqual('C:\P\Main.pas', FileName);
  Selection := TAtlasProjectSelection.Resolve(['C:\P\Core'], 'C:\P\App.dproj', ProjectFiles);
  Assert.IsFalse(Selection.SingleUnit(FileName));
  Selection := TAtlasProjectSelection.OfKinds([TAtlasProjectNodeKind.SourceFile], True, 'C:\P\App.dproj',
    ProjectFiles);
  Assert.IsFalse(Selection.SingleUnit(FileName), 'mehrere Units gewählt');
  Selection := TAtlasProjectSelection.OfKinds([TAtlasProjectNodeKind.SourceFile], False, 'C:\P\App.dproj',
    ProjectFiles);
  Assert.IsTrue(Selection.SingleUnit(FileName));
  Assert.AreEqual('', FileName, 'Datei erst beim Ausführen bekannt');
end;

procedure TAtlasProjectSelectionTests.ContextOnlyBetweenEnterAndLeave;
begin
  Assert.IsFalse(TAtlasProjectContext.Active);
  TAtlasProjectContext.Enter(TAtlasProjectSelection.Resolve(['C:\P\Main.pas'], 'C:\P\App.dproj', ProjectFiles));
  try
    Assert.IsTrue(TAtlasProjectContext.Active);
    TAtlasProjectContext.Enter(TAtlasProjectSelection.Resolve(['C:\P\Core'], 'C:\P\App.dproj', ProjectFiles));
    TAtlasProjectContext.Leave;
    Assert.IsTrue(TAtlasProjectContext.Active, 'verschachtelt');
    Assert.AreEqual('C:\P\Main.pas', TAtlasProjectContext.Current.Units[0], 'vorige Auswahl zurück');
  finally
    TAtlasProjectContext.Leave;
  end;
  Assert.IsFalse(TAtlasProjectContext.Active);
  Assert.AreEqual(0, Integer(Length(TAtlasProjectContext.Current.Units)));
  TAtlasProjectContext.Leave;
  Assert.IsFalse(TAtlasProjectContext.Active, 'überzähliges Leave schadet nicht');
end;

procedure TAtlasProjectSelectionTests.LargeProjectResolvesQuickly;
var
  mFiles: TArray<string>;
  mIndex: Integer;
  mWatch: TStopwatch;
  mSelection: TAtlasProjectSelection;
begin
  SetLength(mFiles, 5000);
  for mIndex := 0 to High(mFiles) do
  begin
    mFiles[mIndex] := 'C:\Projekte\Atlas\Packages\Atlas.IDE.Base\Source\Core\Commands\Atlas.Core.Commands.Teil' +
      IntToStr(mIndex) + '.pas';
  end;
  mWatch := TStopwatch.StartNew;
  mSelection := TAtlasProjectSelection.Resolve(['C:\Projekte\Atlas\Atlas.Tests.dproj'],
    'C:\Projekte\Atlas\Atlas.Tests.dproj', mFiles);
  mSelection := TAtlasProjectSelection.Merge(mSelection, mSelection);
  mWatch.Stop;
  Assert.AreEqual(5000, Integer(Length(mSelection.Units)));
  Assert.IsTrue(mWatch.ElapsedMilliseconds < 500, Format('%d ms', [mWatch.ElapsedMilliseconds]));
  mFiles := nil;
  mSelection := Default(TAtlasProjectSelection);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasProjectSelectionTests);

end.
