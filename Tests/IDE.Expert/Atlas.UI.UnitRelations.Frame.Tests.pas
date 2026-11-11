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
  [Category('Atlas.IDE.Analysis')]
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
    [Test]
    procedure MovedEntryStaysSelected;
  end;

implementation

uses
  Vcl.Controls,
  System.SysUtils,
  Vcl.ComCtrls,
  Atlas.UI.Analysis.Strings,
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
  mRelations: TAtlasUnitRelations;
begin
  Assert.IsTrue(TAtlasUnitRelationsModel.Parse(SampleAnswer, mRelations));
  FFrame.SetRelations(mRelations);
end;

procedure TAtlasUnitRelationsFrameTests.ShowsSectionsAndLibraryGroup;
var
  mUses_, mUsedBy, mLibrary_, mInterface, mImplementation: TTreeNode;
begin
  Load;
  mUses_ := FFrame.Tree.Items.GetFirstNode;
  mUsedBy := mUses_.GetNextSibling;
  Assert.IsNull(mUsedBy.GetNextSibling, 'zwei Abschnitte');
  Assert.AreEqual(TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.UnitRelationsUses, [3]), mUses_.Text);
  Assert.AreEqual(TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.UnitRelationsUsedBy, [2]), mUsedBy.Text);
  Assert.IsTrue(mUses_.Expanded);
  Assert.IsTrue(mUsedBy.Expanded);
  // Verwendet nach dem eigenen Abschnitt, beide Gruppen offen.
  Assert.AreEqual(2, mUses_.Count, 'Interface, Implementation');
  mInterface := mUses_.Item[0];
  mImplementation := mUses_.Item[1];
  Assert.IsTrue(FFrame.IsSectionGroup(mInterface));
  Assert.IsTrue(FFrame.IsSectionGroup(mImplementation));
  Assert.AreEqual(TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.UnitRelationsUsesInterface, [2]), mInterface.Text);
  Assert.AreEqual(TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.UnitRelationsUsesImplementation, [1]),
    mImplementation.Text);
  Assert.IsTrue(mInterface.Expanded);
  Assert.IsTrue(mImplementation.Expanded);
  // Projekt-Units zuerst, die Bibliothek als eingeklappte Gruppe dahinter; ohne intf/impl hinter dem Namen.
  Assert.AreEqual(2, mInterface.Count, 'B, Bibliothek');
  Assert.AreEqual('B  ' + TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.UnitRelationsCycle), mInterface.Item[0].Text);
  mLibrary_ := mInterface.Item[1];
  Assert.IsTrue(FFrame.IsLibraryGroup(mLibrary_));
  Assert.AreEqual(TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.UnitRelationsLibrary, [1]), mLibrary_.Text);
  Assert.IsFalse(mLibrary_.Expanded, 'Bibliothek eingeklappt');
  Assert.AreEqual('System  ' + TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.UnitRelationsUnused),
    mLibrary_.Item[0].Text);
  Assert.AreEqual(1, mImplementation.Count, 'C ohne Bibliothek');
  Assert.AreEqual('C', mImplementation.Item[0].Text);
  // Verwender nach Abschnitt (#554), beide Gruppen offen.
  Assert.AreEqual(2, mUsedBy.Count);
  Assert.IsTrue(FFrame.IsSectionGroup(mUsedBy.Item[0]));
  Assert.AreEqual(TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.UnitRelationsUsedByInterface, [1]),
    mUsedBy.Item[0].Text);
  Assert.AreEqual(TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.UnitRelationsUsedByImplementation, [1]),
    mUsedBy.Item[1].Text);
  Assert.IsTrue(mUsedBy.Item[0].Expanded);
  Assert.IsTrue(mUsedBy.Item[1].Expanded);
  Assert.AreEqual('E', mUsedBy.Item[0].Item[0].Text);
  Assert.AreEqual('F', mUsedBy.Item[1].Item[0].Text);
  // Alle Ebenen: C hat Daten darunter, B die Wurzel A als „siehe oben“; tiefere Ebenen mit intf/impl.
  Assert.AreEqual(1, mImplementation.Item[0].Count);
  Assert.AreEqual('Daten  ' + TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.UnitRelationsInterface),
    mImplementation.Item[0].Item[0].Text);
  Assert.AreEqual('A  ' + TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.UnitRelationsInterface) + ' · ' +
    TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.UnitRelationsRepeated), mInterface.Item[0].Item[0].Text);
  Assert.IsTrue(FFrame.AllLevels, 'Antwort mit depth 0');
end;

procedure TAtlasUnitRelationsFrameTests.MarksCycleAndCost;
var
  B: TTreeNode;
begin
  Load;
  Assert.AreEqual('A', FFrame.Title.Caption);
  Assert.IsTrue(string(FFrame.Info.Caption).StartsWith(TAtlasAnalysisStrings.Fmt(
    TAtlasAnalysisTextId.UnitRelationsRecompile, [4])));
  Assert.IsTrue(string(FFrame.Info.Caption).EndsWith(TAtlasAnalysisStrings.Text(
    TAtlasAnalysisTextId.UnitRelationsCycle)));
  Assert.AreEqual('A - B - A', FFrame.Info.Hint);
  B := FFrame.FindEntry('B', True);
  Assert.IsNotNull(B);
  Assert.AreEqual('B  ' + TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.UnitRelationsCycle), B.Text);
  Assert.AreEqual(TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.UnitRelationsCyclePath, ['A - B - A']),
    FFrame.HintOf(B));
  Assert.AreEqual('C:\P\C.pas', FFrame.HintOf(FFrame.FindEntry('C', True)), 'sonst die Datei');
  Assert.AreEqual('', FFrame.HintOf(FFrame.Tree.Items.GetFirstNode), 'Abschnitt ohne Hinweis');
  FFrame.SetMessage('keine Datei');
  Assert.AreEqual(0, FFrame.Tree.Items.Count);
  Assert.AreEqual('keine Datei', FFrame.Info.Caption);
  Assert.IsFalse(FFrame.HasRelations);
end;

procedure TAtlasUnitRelationsFrameTests.FilterKeepsAncestors;
var
  mUses_: TTreeNode;
begin
  Load;
  FFrame.Filter.Text := 'dat';
  mUses_ := FFrame.Tree.Items.GetFirstNode;
  Assert.AreEqual(TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.UnitRelationsUses, [1]), mUses_.Text);
  Assert.AreEqual(1, mUses_.Count, 'nur Implementation');
  Assert.AreEqual(TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.UnitRelationsUsesImplementation, [1]),
    mUses_.Item[0].Text);
  Assert.AreEqual('C', mUses_.Item[0].Item[0].Text);
  Assert.IsTrue(mUses_.Item[0].Item[0].Expanded, 'mit Filter aufgeklappt');
  Assert.AreEqual(TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.UnitRelationsUsedBy, [0]), mUses_.GetNextSibling.Text);
  FFrame.Filter.Text := '';
  Assert.AreEqual(TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.UnitRelationsUses, [3]),
    FFrame.Tree.Items.GetFirstNode.Text);
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
  mRelations: TAtlasUnitRelations;
  mLibrary_: TTreeNode;
  mRelation: TAtlasUnitRelation;
begin
  Load;
  mLibrary_ := FFrame.Tree.Items.GetFirstNode.Item[0].Item[1];
  mLibrary_.Expand(False);
  FFrame.Tree.Selected := FFrame.FindEntry('F', False);
  // Dieselbe Unit, neue Antwort: Bibliothek bleibt offen, F bleibt gewählt.
  Assert.IsTrue(TAtlasUnitRelationsModel.Parse(SampleAnswer, mRelations));
  mRelations.RecompileCount := 9;
  FFrame.SetRelations(mRelations);
  Assert.IsTrue(FFrame.Tree.Items.GetFirstNode.Item[0].Item[1].Expanded);
  Assert.IsTrue(FFrame.EntryOf(FFrame.Tree.Selected, mRelation));
  Assert.AreEqual('F', mRelation.Name);
  // Andere Unit: Vorgaben.
  mRelations.FileName := 'C:\P\Z.pas';
  FFrame.SetRelations(mRelations);
  Assert.IsFalse(FFrame.Tree.Items.GetFirstNode.Item[0].Item[1].Expanded);
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
  mRelations: TAtlasUnitRelations;
  B, mUsedBy: TTreeNode;
begin
  Assert.IsTrue(TAtlasUnitRelationsModel.Parse('{"found":true,"unit":"A","file":"C:\\P\\A.pas",' +
    '"recompileCount":2,"uses":[{"name":"B","file":"C:\\P\\B.pas","section":"interface",' +
    '"onlyImplementation":true},{"name":"C","file":"C:\\P\\C.pas","section":"interface"}],' +
    '"usedBy":[{"name":"D","file":"C:\\P\\D.pas","section":"implementation"}],"depth":1}', mRelations));
  FFrame.SetRelations(mRelations);
  Assert.AreEqual(TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.UnitRelationsRecompile, [2]) + ' · ' +
    TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.UnitRelationsMovable, [1]), FFrame.Info.Caption);
  B := FFrame.FindEntry('B', True);
  Assert.AreEqual('B  ' + TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.UnitRelationsOnlyImplementation), B.Text);
  Assert.AreEqual(TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.UnitRelationsOnlyImplementationHint, ['B']),
    FFrame.HintOf(B));
  Assert.AreEqual('C', FFrame.FindEntry('C', True).Text);
  Assert.AreEqual(1, FFrame.Tree.Items.GetFirstNode.Count, 'nur Interface');
  FFrame.Tree.Selected := B;
  FFrame.UpdateMenu;
  Assert.IsTrue(FFrame.MoveImplementationItem.Visible, 'ins implementation-uses verschieben');
  FFrame.MoveImplementationItem.Click;
  Assert.AreEqual('B>False', FMoved);
  // Nur Verwender über implementation-uses: eine Gruppe.
  mUsedBy := FFrame.Tree.Items.GetFirstNode.GetNextSibling;
  Assert.AreEqual(1, mUsedBy.Count);
  Assert.AreEqual(TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.UnitRelationsUsedByImplementation, [1]),
    mUsedBy.Item[0].Text);
end;

procedure TAtlasUnitRelationsFrameTests.MovedEntryStaysSelected;
var
  mRelations: TAtlasUnitRelations;
  mRelation: TAtlasUnitRelation;
begin
  Load;
  FFrame.Tree.Selected := FFrame.FindEntry('B', True);
  // B ins implementation-uses verschoben: neue Gruppe, Auswahl bleibt.
  Assert.IsTrue(TAtlasUnitRelationsModel.Parse(SampleAnswer, mRelations));
  mRelations.Uses_[0].InInterface := False;
  FFrame.SetRelations(mRelations);
  Assert.IsTrue(FFrame.EntryOf(FFrame.Tree.Selected, mRelation));
  Assert.AreEqual('B', mRelation.Name);
  Assert.AreEqual(TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.UnitRelationsUsesImplementation, [2]),
    FFrame.Tree.Selected.Parent.Text);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasUnitRelationsFrameTests);

end.
