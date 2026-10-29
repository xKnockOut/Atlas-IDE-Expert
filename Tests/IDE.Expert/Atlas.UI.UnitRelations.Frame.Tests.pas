unit Atlas.UI.UnitRelations.Frame.Tests;

// Fenster „Unit-Beziehungen“ (#593), Fensterinhalt: Abschnitte mit Zahlen,
// Bibliothek eingeklappt, Zyklus mit Rundweg im Hinweis, Kosten in der
// Infozeile, Filter samt Vorfahren, Öffnen von Unit und uses-Eintrag,
// Kontextmenü nur dort, wo es passt, Aufklappen und Auswahl bleiben bei
// neuen Daten, Umschalter der Tiefe; Verwender nach interface- und
// implementation-uses und verschiebbare interface-Einträge (#554).

interface

uses
  DUnitX.TestFramework,
  Vcl.Forms,
  Atlas.Core.UnitRelations.Model,
  Atlas.UI.UnitRelations.Frame;

type
  [TestFixture]
  TAtlasUnitRelationsFrameTests = class
  private
    FForm: TForm;
    FFrame: TAtlasUnitRelationsFrame;
    FOpened: string;
    FLine: Integer;
    FMoved: string;
    FRemoved: string;
    FDepth: Integer;
    procedure Load;
  public
    [Setup]
    procedure SetUp;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ShowsSectionsAndLibraryGroup;
    [Test]
    procedure MarksCycleAndCost;
    [Test]
    procedure FilterKeepsAncestors;
    [Test]
    procedure OpensUnitOrUsesEntry;
    [Test]
    procedure MenuFitsTheEntry;
    [Test]
    procedure KeepsStateOnNewData;
    [Test]
    procedure DepthToggleReports;
    [Test]
    procedure ShowsMovableEntries;
  end;

implementation

uses
  Vcl.Controls,
  System.SysUtils,
  Vcl.ComCtrls,
  Atlas.UI.Strings,
  Atlas.Core.UnitRelations.Model.Tests;

procedure TAtlasUnitRelationsFrameTests.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 400, 600);
  FFrame := TAtlasUnitRelationsFrame.Create(FForm);
  FFrame.Parent := FForm;
  FFrame.Align := alClient;
  FOpened := '';
  FLine := -2;
  FMoved := '';
  FRemoved := '';
  FDepth := -1;
  FFrame.OnOpen :=
    procedure(const AFileName: string; ALine, ACharacter: Integer)
    begin
      FOpened := AFileName;
      FLine := ALine;
    end;
  FFrame.OnMove :=
    procedure(const AUnit: string; AToInterface: Boolean)
    begin
      FMoved := AUnit + '>' + BoolToStr(AToInterface, True);
    end;
  FFrame.OnRemove :=
    procedure(const AUnit: string)
    begin
      FRemoved := AUnit;
    end;
  FFrame.OnDepthChanged :=
    procedure(AAllLevels: Boolean)
    begin
      FDepth := Ord(AAllLevels);
    end;
end;

procedure TAtlasUnitRelationsFrameTests.TearDown;
begin
  FForm.Free;
  FForm := nil;
  FFrame := nil;
  FOpened := '';
  FMoved := '';
  FRemoved := '';
end;

procedure TAtlasUnitRelationsFrameTests.Load;
var
  Relations: TAtlasUnitRelations;
begin
  Assert.IsTrue(TAtlasUnitRelationsModel.Parse(SampleAnswer, Relations));
  FFrame.SetRelations(Relations);
end;

procedure TAtlasUnitRelationsFrameTests.ShowsSectionsAndLibraryGroup;
var
  Uses_, UsedBy, Library_: TTreeNode;
begin
  Load;
  Uses_ := FFrame.Tree.Items.GetFirstNode;
  UsedBy := Uses_.GetNextSibling;
  Assert.IsNull(UsedBy.GetNextSibling, 'zwei Abschnitte');
  Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.UnitRelationsUses, [3]), Uses_.Text);
  Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.UnitRelationsUsedBy, [2]), UsedBy.Text);
  Assert.IsTrue(Uses_.Expanded);
  Assert.IsTrue(UsedBy.Expanded);
  // Projekt-Units zuerst, die Bibliothek als eingeklappte Gruppe dahinter.
  Assert.AreEqual(3, Uses_.Count, 'B, C, Bibliothek');
  Library_ := Uses_.Item[2];
  Assert.IsTrue(FFrame.IsLibraryGroup(Library_));
  Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.UnitRelationsLibrary, [1]), Library_.Text);
  Assert.IsFalse(Library_.Expanded, 'Bibliothek eingeklappt');
  Assert.IsTrue(Library_.Item[0].Text.StartsWith('System  intf'));
  Assert.IsTrue(Library_.Item[0].Text.EndsWith(TAtlasStrings.Text(TAtlasTextId.UnitRelationsUnused)));
  // Verwender nach Abschnitt (#554), beide Gruppen offen.
  Assert.AreEqual(2, UsedBy.Count);
  Assert.IsTrue(FFrame.IsUsedByGroup(UsedBy.Item[0]));
  Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.UnitRelationsUsedByInterface, [1]), UsedBy.Item[0].Text);
  Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.UnitRelationsUsedByImplementation, [1]), UsedBy.Item[1].Text);
  Assert.IsTrue(UsedBy.Item[0].Expanded);
  Assert.IsTrue(UsedBy.Item[1].Expanded);
  Assert.AreEqual('E  intf', UsedBy.Item[0].Item[0].Text);
  Assert.AreEqual('F  impl', UsedBy.Item[1].Item[0].Text);
  // Alle Ebenen: C hat Daten darunter, B die Wurzel A als „siehe oben“.
  Assert.AreEqual(1, Uses_.Item[1].Count);
  Assert.IsTrue(Uses_.Item[0].Item[0].Text.EndsWith(TAtlasStrings.Text(TAtlasTextId.UnitRelationsRepeated)));
  Assert.IsTrue(FFrame.AllLevels, 'Antwort mit depth 0');
end;

procedure TAtlasUnitRelationsFrameTests.MarksCycleAndCost;
var
  B: TTreeNode;
begin
  Load;
  Assert.AreEqual('A', FFrame.Title.Caption);
  Assert.IsTrue(string(FFrame.Info.Caption).StartsWith(TAtlasStrings.Fmt(TAtlasTextId.UnitRelationsRecompile, [4])));
  Assert.IsTrue(string(FFrame.Info.Caption).EndsWith(TAtlasStrings.Text(TAtlasTextId.UnitRelationsCycle)));
  Assert.AreEqual('A - B - A', FFrame.Info.Hint);
  B := FFrame.FindEntry('B', True);
  Assert.IsNotNull(B);
  Assert.AreEqual('B  intf · ' + TAtlasStrings.Text(TAtlasTextId.UnitRelationsCycle), B.Text);
  Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.UnitRelationsCyclePath, ['A - B - A']), FFrame.HintOf(B));
  Assert.AreEqual('C:\P\C.pas', FFrame.HintOf(FFrame.FindEntry('C', True)), 'sonst die Datei');
  Assert.AreEqual('', FFrame.HintOf(FFrame.Tree.Items.GetFirstNode), 'Abschnitt ohne Hinweis');
  FFrame.SetMessage('keine Datei');
  Assert.AreEqual(0, FFrame.Tree.Items.Count);
  Assert.AreEqual('keine Datei', FFrame.Info.Caption);
  Assert.IsFalse(FFrame.HasRelations);
end;

procedure TAtlasUnitRelationsFrameTests.FilterKeepsAncestors;
var
  Uses_: TTreeNode;
begin
  Load;
  FFrame.Filter.Text := 'dat';
  Uses_ := FFrame.Tree.Items.GetFirstNode;
  Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.UnitRelationsUses, [1]), Uses_.Text);
  Assert.AreEqual(1, Uses_.Count);
  Assert.IsTrue(Uses_.Item[0].Text.StartsWith('C  impl'));
  Assert.IsTrue(Uses_.Item[0].Expanded, 'mit Filter aufgeklappt');
  Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.UnitRelationsUsedBy, [0]), Uses_.GetNextSibling.Text);
  FFrame.Filter.Text := '';
  Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.UnitRelationsUses, [3]), FFrame.Tree.Items.GetFirstNode.Text);
end;

procedure TAtlasUnitRelationsFrameTests.OpensUnitOrUsesEntry;
begin
  Load;
  FFrame.OpenNode(FFrame.FindEntry('B', True), False);
  Assert.AreEqual('C:\P\B.pas', FOpened);
  Assert.AreEqual(-1, FLine, 'nur die Unit');
  FFrame.OpenNode(FFrame.FindEntry('B', True), True);
  Assert.AreEqual('C:\P\A.pas', FOpened, 'Strg: zum uses-Eintrag in A');
  Assert.AreEqual(3, FLine);
  // System hat keine Datei: auch ohne Strg zum Eintrag.
  FFrame.OpenNode(FFrame.FindEntry('System', True), False);
  Assert.AreEqual('C:\P\A.pas', FOpened);
  FOpened := '';
  FFrame.OpenNode(FFrame.Tree.Items.GetFirstNode, False);
  Assert.AreEqual('', FOpened, 'Abschnitt öffnet nichts');
end;

procedure TAtlasUnitRelationsFrameTests.MenuFitsTheEntry;
begin
  Load;
  FFrame.Tree.Selected := FFrame.FindEntry('B', True);
  FFrame.UpdateMenu;
  Assert.IsTrue(FFrame.MoveImplementationItem.Visible, 'B steht im interface');
  Assert.IsFalse(FFrame.MoveInterfaceItem.Visible);
  Assert.IsFalse(FFrame.RemoveItem.Visible, 'B wird verwendet');
  Assert.IsTrue(FFrame.CopyPathItem.Visible);
  FFrame.MoveImplementationItem.Click;
  Assert.AreEqual('B>False', FMoved);
  FFrame.Tree.Selected := FFrame.FindEntry('C', True);
  FFrame.UpdateMenu;
  Assert.IsTrue(FFrame.MoveInterfaceItem.Visible);
  FFrame.MoveInterfaceItem.Click;
  Assert.AreEqual('C>True', FMoved);
  FFrame.Tree.Selected := FFrame.FindEntry('System', True);
  FFrame.UpdateMenu;
  Assert.IsTrue(FFrame.RemoveItem.Visible, 'ungenutzt');
  Assert.IsFalse(FFrame.CopyPathItem.Visible, 'ohne Datei');
  FFrame.RemoveItem.Click;
  Assert.AreEqual('System', FRemoved);
  // Wird verwendet von und tiefere Ebenen: nur „Pfad kopieren“.
  FFrame.Tree.Selected := FFrame.FindEntry('E', False);
  FFrame.UpdateMenu;
  Assert.IsFalse(FFrame.MoveImplementationItem.Visible);
  Assert.IsFalse(FFrame.MoveInterfaceItem.Visible);
  Assert.IsFalse(FFrame.RemoveItem.Visible);
  Assert.IsTrue(FFrame.CopyPathItem.Visible);
  FFrame.Tree.Selected := FFrame.FindEntry('C', True).Item[0];
  FFrame.UpdateMenu;
  Assert.IsFalse(FFrame.MoveImplementationItem.Visible, 'Daten gehört nicht zu den uses von A');
  Assert.IsFalse(FFrame.MoveInterfaceItem.Visible);
end;

procedure TAtlasUnitRelationsFrameTests.KeepsStateOnNewData;
var
  Relations: TAtlasUnitRelations;
  Library_: TTreeNode;
  Relation: TAtlasUnitRelation;
begin
  Load;
  Library_ := FFrame.Tree.Items.GetFirstNode.Item[2];
  Library_.Expand(False);
  FFrame.Tree.Selected := FFrame.FindEntry('F', False);
  // Dieselbe Unit, neue Antwort: Bibliothek bleibt offen, F bleibt gewählt.
  Assert.IsTrue(TAtlasUnitRelationsModel.Parse(SampleAnswer, Relations));
  Relations.RecompileCount := 9;
  FFrame.SetRelations(Relations);
  Assert.IsTrue(FFrame.Tree.Items.GetFirstNode.Item[2].Expanded);
  Assert.IsTrue(FFrame.EntryOf(FFrame.Tree.Selected, Relation));
  Assert.AreEqual('F', Relation.Name);
  // Andere Unit: Vorgaben.
  Relations.FileName := 'C:\P\Z.pas';
  FFrame.SetRelations(Relations);
  Assert.IsFalse(FFrame.Tree.Items.GetFirstNode.Item[2].Expanded);
end;

procedure TAtlasUnitRelationsFrameTests.DepthToggleReports;
begin
  Load;
  Assert.AreEqual(-1, FDepth, 'SetRelations meldet nichts');
  FFrame.DirectButton.Checked := True;
  Assert.AreEqual(0, FDepth);
  FFrame.AllLevelsButton.Checked := True;
  Assert.AreEqual(1, FDepth);
  FDepth := -1;
  FFrame.AllLevels := False;
  Assert.AreEqual(-1, FDepth, 'von außen gesetzt');
  Assert.IsTrue(FFrame.DirectButton.Checked);
end;

procedure TAtlasUnitRelationsFrameTests.ShowsMovableEntries;
var
  Relations: TAtlasUnitRelations;
  B, UsedBy: TTreeNode;
begin
  Assert.IsTrue(TAtlasUnitRelationsModel.Parse('{"found":true,"unit":"A","file":"C:\\P\\A.pas",' +
    '"recompileCount":2,"uses":[{"name":"B","file":"C:\\P\\B.pas","section":"interface",' +
    '"onlyImplementation":true},{"name":"C","file":"C:\\P\\C.pas","section":"interface"}],' +
    '"usedBy":[{"name":"D","file":"C:\\P\\D.pas","section":"implementation"}],"depth":1}', Relations));
  FFrame.SetRelations(Relations);
  Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.UnitRelationsRecompile, [2]) + ' · ' +
    TAtlasStrings.Fmt(TAtlasTextId.UnitRelationsMovable, [1]), FFrame.Info.Caption);
  B := FFrame.FindEntry('B', True);
  Assert.AreEqual('B  intf · ' + TAtlasStrings.Text(TAtlasTextId.UnitRelationsOnlyImplementation), B.Text);
  Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.UnitRelationsOnlyImplementationHint, ['B']), FFrame.HintOf(B));
  Assert.AreEqual('C  intf', FFrame.FindEntry('C', True).Text);
  FFrame.Tree.Selected := B;
  FFrame.UpdateMenu;
  Assert.IsTrue(FFrame.MoveImplementationItem.Visible, 'ins implementation-uses verschieben');
  FFrame.MoveImplementationItem.Click;
  Assert.AreEqual('B>False', FMoved);
  // Nur Verwender über implementation-uses: eine Gruppe.
  UsedBy := FFrame.Tree.Items.GetFirstNode.GetNextSibling;
  Assert.AreEqual(1, UsedBy.Count);
  Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.UnitRelationsUsedByImplementation, [1]), UsedBy.Item[0].Text);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasUnitRelationsFrameTests);

end.
