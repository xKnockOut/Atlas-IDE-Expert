unit Atlas.Core.Designer.Structure.Tests;

// Tests für das Fenster „Atlas-Struktur“ (#609): Art nach Klasse und
// Vorfahren, Baum der Steuerelemente, Gruppen nach Klasse und nach Art,
// Verknüpfungen und Befunde auf einer Fixture-DFM, Filter, freie Stelle am
// unteren Rand.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Designer')]
  TAtlasStructureTests = class
  public
    [Test]
    procedure Kinds;
    [Test]
    procedure ControlTree;
    [Test]
    procedure GroupsByClass;
    [Test]
    procedure GroupsByKind;
    [Test]
    procedure LinksOfPopupMenu;
    [Test]
    procedure Findings;
    [Test]
    procedure Filter;
    [Test]
    procedure FreePositionBottomEdge;
    [Test]
    procedure FreePositionNextToOthers;
    [Test]
    procedure FreePositionFull;
  end;

implementation

uses
  System.Types,
  System.SysUtils,
  Atlas.Core.Designer.FormModel,
  Atlas.Core.Designer.Structure;

const
  cFixture =
    'object MainForm: TMainForm' + #13#10 +
    '  PopupMenu = PopupMenu1' + #13#10 +
    '  object CenterPanel: TPanel' + #13#10 +
    '    Width = 400' + #13#10 +
    '  end' + #13#10 +
    '  object ToolbarPanel: TPanel' + #13#10 +
    '    Width = 400' + #13#10 +
    '    object SchemaPanel: TPanel' + #13#10 +
    '      Width = 200' + #13#10 +
    '      object SchemaCombo: TComboBox' + #13#10 +
    '        Width = 120' + #13#10 +
    '        PopupMenu = PopupMenu2' + #13#10 +
    '      end' + #13#10 +
    '      object SchemaLabel: TLabel' + #13#10 +
    '        Width = 40' + #13#10 +
    '        PopupMenu = PopupMenu2' + #13#10 +
    '      end' + #13#10 +
    '    end' + #13#10 +
    '  end' + #13#10 +
    '  object PopupMenu1: TPopupMenu' + #13#10 +
    '  end' + #13#10 +
    '  object PopupMenu2: TPopupMenu' + #13#10 +
    '    Images = ImageList1' + #13#10 +
    '  end' + #13#10 +
    '  object PopupMenu3: TPopupMenu' + #13#10 +
    '  end' + #13#10 +
    '  object ImageList1: TImageList' + #13#10 +
    '  end' + #13#10 +
    '  object SQLConnection1: TSQLConnection' + #13#10 +
    '  end' + #13#10 +
    '  object KKKKKK: TSQLQuery' + #13#10 +
    '    SQLConnection = SQLConnection1' + #13#10 +
    '  end' + #13#10 +
    '  object SQLQuery1: TSQLQuery' + #13#10 +
    '  end' + #13#10 +
    '  object dsKKKKKK: TDataSource' + #13#10 +
    '    DataSet = KKKKKK' + #13#10 +
    '  end' + #13#10 +
    'end';

/// <summary>Komponenten der Fixture: Steuerelemente haben Width, Verweise sind Werte mit dem Namen einer
/// Komponente, Vorfahren wie die IDE sie liefert. Leere Verweise stehen nicht in der DFM; wie in der IDE
/// bekommt SQLQuery1 ein leeres SQLConnection.</summary>
function FixtureItems: TArray<TAtlasStructureItem>;
var
  mObjects: TArray<TAtlasFormObject>;
  mObject: TAtlasFormObject;
  mValue: TAtlasFormValue;
  mItem: TAtlasStructureItem;
  mDummy: string;
begin
  Result := nil;
  mObjects := TAtlasFormModel.Parse(cFixture);
  for mObject in mObjects do
  begin
    mItem := Default(TAtlasStructureItem);
    mItem.Name := mObject.Name;
    mItem.ClassChain := [mObject.TypeName];
    if mObject.TypeName = 'TSQLQuery' then
    begin
      mItem.ClassChain := mItem.ClassChain + ['TCustomSQLDataSet', 'TDataSet'];
    end
    else if mObject.TypeName = 'TSQLConnection' then
    begin
      mItem.ClassChain := mItem.ClassChain + ['TCustomConnection'];
    end;
    mItem.IsControl := (mObject.Depth = 0) or mObject.ValueOf('Width', mDummy);
    mItem.Parent := mObject.OwnerName;
    for mValue in mObject.Values do
    begin
      if TAtlasFormModel.IndexOf(mObjects, mValue.Value) >= 0 then
      begin
        mItem.Refs := mItem.Refs + [TAtlasStructureRef.Create(mValue.Path, mValue.Value)];
      end;
    end;
    if mItem.Name = 'SQLQuery1' then
    begin
      mItem.Refs := [TAtlasStructureRef.Create('SQLConnection', ''), TAtlasStructureRef.Create('Tag', '')];
    end;
    Result := Result + [mItem];
  end;
end;

function NodeOf(const ANodes: TArray<TAtlasStructureNode>; const AKey: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(ANodes) do
  begin
    if ANodes[mIndex].Key = AKey then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

function Fixture(AByKind: Boolean; const AFilter: string = ''): TArray<TAtlasStructureNode>;
begin
  Result := TAtlasStructure.Nodes(FixtureItems, 'MainForm', AByKind, AFilter);
end;

{ TAtlasStructureTests }

procedure TAtlasStructureTests.Kinds;
begin
  Assert.IsTrue(TAtlasStructure.KindOf(['TMyQuery', 'TFDCustomQuery', 'TFDDataSet', 'TDataSet']) =
    TAtlasStructureKind.Data, 'über den Vorfahren');
  Assert.IsTrue(TAtlasStructure.KindOf(['TFDConnection']) = TAtlasStructureKind.Data, 'Verbindung');
  Assert.IsTrue(TAtlasStructure.KindOf(['TActionList', 'TCustomActionList']) = TAtlasStructureKind.Actions);
  Assert.IsTrue(TAtlasStructure.KindOf(['TPopupMenu', 'TMenu']) = TAtlasStructureKind.Actions, 'Menü');
  Assert.IsTrue(TAtlasStructure.KindOf(['TSaveDialog', 'TOpenDialog', 'TCommonDialog']) =
    TAtlasStructureKind.Dialogs);
  Assert.IsTrue(TAtlasStructure.KindOf(['TVirtualImageList', 'TCustomImageList']) = TAtlasStructureKind.Images);
  Assert.IsTrue(TAtlasStructure.KindOf(['TTimer', 'TComponent']) = TAtlasStructureKind.Other);
  Assert.AreEqual('dialogs', TAtlasStructure.KindKey(TAtlasStructureKind.Dialogs));
end;

procedure TAtlasStructureTests.ControlTree;
var
  mNodes: TArray<TAtlasStructureNode>;
begin
  mNodes := Fixture(False);
  Assert.IsTrue(mNodes[0].Kind = TAtlasStructureNodeKind.Controls);
  Assert.AreEqual(5, mNodes[0].Count, 'ohne das Formular');
  Assert.AreEqual('MainForm', mNodes[1].Name);
  Assert.AreEqual(1, mNodes[1].Level);
  Assert.AreEqual('CenterPanel', mNodes[2].Name);
  Assert.AreEqual(2, mNodes[2].Level);
  Assert.AreEqual('ToolbarPanel', mNodes[3].Name);
  Assert.AreEqual('SchemaPanel', mNodes[4].Name);
  Assert.AreEqual(3, mNodes[4].Level);
  Assert.AreEqual('SchemaCombo', mNodes[5].Name);
  Assert.AreEqual(4, mNodes[5].Level);
  Assert.AreEqual('TComboBox', mNodes[5].ClassName);
  Assert.AreEqual('SchemaLabel', mNodes[6].Name);
  Assert.IsTrue(mNodes[7].Kind = TAtlasStructureNodeKind.NonVisual);
  Assert.AreEqual(8, mNodes[7].Count);
end;

procedure TAtlasStructureTests.GroupsByClass;
var
  mNodes: TArray<TAtlasStructureNode>;
  mPopup, mQuery: Integer;
begin
  mNodes := Fixture(False);
  mPopup := NodeOf(mNodes, 'class:tpopupmenu');
  mQuery := NodeOf(mNodes, 'class:tsqlquery');
  Assert.IsTrue(NodeOf(mNodes, 'class:tdatasource') < NodeOf(mNodes, 'class:timagelist'), 'nach Klassennamen');
  Assert.IsTrue(mPopup < NodeOf(mNodes, 'class:tsqlconnection'));
  Assert.IsTrue(mNodes[mPopup].Kind = TAtlasStructureNodeKind.Group);
  Assert.AreEqual('TPopupMenu', mNodes[mPopup].ClassName);
  Assert.AreEqual(3, mNodes[mPopup].Count);
  Assert.AreEqual(2, mNodes[mQuery].Count);
  Assert.AreEqual('PopupMenu1', mNodes[mPopup + 1].Name, 'in der Gruppe nach Namen');
  Assert.AreEqual(2, mNodes[mPopup + 1].Level);
  Assert.AreEqual('KKKKKK', mNodes[mQuery + 1].Name);
end;

procedure TAtlasStructureTests.GroupsByKind;
var
  mNodes: TArray<TAtlasStructureNode>;
  mData: Integer;
begin
  mNodes := Fixture(True);
  mData := NodeOf(mNodes, 'kind:data');
  Assert.IsTrue(mData < NodeOf(mNodes, 'kind:actions'), 'Daten vor Aktionen');
  Assert.IsTrue(NodeOf(mNodes, 'kind:actions') < NodeOf(mNodes, 'kind:images'));
  Assert.AreEqual(4, mNodes[mData].Count, 'Verbindung, zwei Abfragen, DataSource');
  Assert.IsTrue(mNodes[mData].StructureKind = TAtlasStructureKind.Data);
  Assert.AreEqual(-1, NodeOf(mNodes, 'class:tsqlquery'));
end;

procedure TAtlasStructureTests.LinksOfPopupMenu;
var
  mLinks: TArray<TAtlasStructureNode>;
begin
  mLinks := TAtlasStructure.Links(FixtureItems, 'PopupMenu2', 3);
  Assert.AreEqual(3, Integer(Length(mLinks)));
  Assert.IsFalse(mLinks[0].Incoming, 'eigene Verweise zuerst');
  Assert.AreEqual('Images', mLinks[0].Prop);
  Assert.AreEqual('ImageList1', mLinks[0].Name);
  Assert.AreEqual('TImageList', mLinks[0].ClassName);
  Assert.IsTrue(mLinks[1].Incoming);
  Assert.AreEqual('PopupMenu', mLinks[1].Prop);
  Assert.AreEqual('SchemaCombo', mLinks[1].Name);
  Assert.AreEqual('SchemaLabel', mLinks[2].Name);
  Assert.AreEqual(3, mLinks[2].Level);
  Assert.IsTrue(mLinks[2].Kind = TAtlasStructureNodeKind.Link);
  Assert.AreNotEqual(mLinks[1].Key, mLinks[2].Key);
end;

procedure TAtlasStructureTests.Findings;
var
  mItems: TArray<TAtlasStructureItem>;
  mLinks: TArray<TAtlasStructureNode>;
begin
  mItems := FixtureItems;
  mLinks := TAtlasStructure.Links(mItems, 'SQLQuery1', 3);
  Assert.AreEqual(1, Integer(Length(mLinks)), 'leeres Tag ist kein Pflichtverweis');
  Assert.AreEqual('SQLConnection', mLinks[0].Prop);
  Assert.AreEqual('', mLinks[0].Name);
  Assert.IsTrue(mLinks[0].Finding = TAtlasStructureFinding.Empty);
  Assert.IsTrue(TAtlasStructure.FindingOf(mItems, 'PopupMenu3') = TAtlasStructureFinding.Unused);
  Assert.IsTrue(TAtlasStructure.FindingOf(mItems, 'dsKKKKKK') = TAtlasStructureFinding.Unused);
  Assert.IsTrue(TAtlasStructure.FindingOf(mItems, 'PopupMenu1') = TAtlasStructureFinding.None,
    'vom Formular verwendet');
  Assert.IsTrue(TAtlasStructure.FindingOf(mItems, 'SQLConnection1') = TAtlasStructureFinding.None,
    'Verbindungen ohne Befund');
  Assert.IsTrue(Fixture(False)[NodeOf(Fixture(False), 'item:popupmenu3')].Finding =
    TAtlasStructureFinding.Unused);
end;

procedure TAtlasStructureTests.Filter;
var
  mNodes: TArray<TAtlasStructureNode>;
begin
  mNodes := Fixture(False, ' SQL ');
  Assert.AreEqual(0, mNodes[0].Count, 'kein Steuerelement');
  Assert.AreEqual(3, mNodes[1].Count, 'Name oder Klasse: SQLConnection1, KKKKKK, SQLQuery1');
  mNodes := Fixture(False, 'combo');
  Assert.AreEqual(1, mNodes[0].Count);
  Assert.AreEqual('SchemaCombo', mNodes[1].Name);
  Assert.AreEqual(1, mNodes[1].Level, 'ohne Baum');
  Assert.AreEqual(0, mNodes[2].Count);
end;

procedure TAtlasStructureTests.FreePositionBottomEdge;
var
  mPoint: TPoint;
begin
  mPoint := TAtlasStructure.FreePosition(nil, TSize.Create(400, 300));
  Assert.AreEqual(8, mPoint.X);
  Assert.AreEqual(300 - 28 - 8, mPoint.Y);
end;

procedure TAtlasStructureTests.FreePositionNextToOthers;
var
  mPoint: TPoint;
begin
  mPoint := TAtlasStructure.FreePosition([Point(8, 264), Point(44, 264), Point(80, 264), Point(200, 120)],
    TSize.Create(400, 300));
  Assert.AreEqual(116, mPoint.X, 'nächste freie Stelle rechts daneben');
  Assert.AreEqual(264, mPoint.Y);
end;

procedure TAtlasStructureTests.FreePositionFull;
var
  mPoint: TPoint;
begin
  // Untere Reihe voll (Platz für zwei Symbole): eine Reihe darüber.
  mPoint := TAtlasStructure.FreePosition([Point(8, 64), Point(44, 64)], TSize.Create(90, 100));
  Assert.AreEqual(8, mPoint.X);
  Assert.AreEqual(64 - 36, mPoint.Y);
  // Kein Platz: links oben.
  mPoint := TAtlasStructure.FreePosition(nil, TSize.Create(20, 20));
  Assert.AreEqual(8, mPoint.X);
  Assert.AreEqual(8, mPoint.Y);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasStructureTests);

end.
