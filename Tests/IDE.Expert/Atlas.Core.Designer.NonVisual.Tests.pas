unit Atlas.Core.Designer.NonVisual.Tests;

// Tests für die Leiste nichtvisueller Komponenten (#609): Gruppen nach Klasse
// und Vorfahren, Reihenfolge und Filter auf einer Fixture-DFM, freie Stelle
// am unteren Rand.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Designer')]
  TAtlasNonVisualTrayTests = class
  public
    [Test]
    procedure Groups;
    [Test]
    procedure FixtureRows;
    [Test]
    procedure Filter;
    [Test]
    procedure FreePositionBottomEdge;
    [Test]
    procedure FreePositionFixture;
    [Test]
    procedure FreePositionFull;
  end;

implementation

uses
  System.Types,
  System.SysUtils,
  Atlas.Core.Designer.FormModel,
  Atlas.Core.Designer.NonVisual;

const
  cFixture =
    'object frmKunden: TfrmKunden' + #13#10 +
    '  ClientHeight = 300' + #13#10 +
    '  ClientWidth = 400' + #13#10 +
    '  object edtName: TEdit' + #13#10 +
    '    Left = 16' + #13#10 +
    '    Top = 16' + #13#10 +
    '    Width = 121' + #13#10 +
    '    Height = 21' + #13#10 +
    '  end' + #13#10 +
    '  object qryKunden: TFDQuery' + #13#10 +
    '    Left = 8' + #13#10 +
    '    Top = 264' + #13#10 +
    '  end' + #13#10 +
    '  object dsKunden: TDataSource' + #13#10 +
    '    DataSet = qryKunden' + #13#10 +
    '    Left = 44' + #13#10 +
    '    Top = 264' + #13#10 +
    '  end' + #13#10 +
    '  object tmrRefresh: TTimer' + #13#10 +
    '    Left = 200' + #13#10 +
    '    Top = 120' + #13#10 +
    '  end' + #13#10 +
    '  object dlgOpen: TOpenDialog' + #13#10 +
    '    Left = 80' + #13#10 +
    '    Top = 264' + #13#10 +
    '  end' + #13#10 +
    'end';

/// <summary>Nichtvisuelle Komponenten der Fixture: Objekte ohne Width.</summary>
function FixtureItems(out AClient: TSize): TArray<TAtlasTrayItem>;
var
  mObjects: TArray<TAtlasFormObject>;
  mObject: TAtlasFormObject;
  mItem: TAtlasTrayItem;
  mValue: string;
begin
  Result := nil;
  mObjects := TAtlasFormModel.Parse(cFixture);
  mObjects[0].ValueOf('ClientWidth', mValue);
  AClient.cx := StrToInt(mValue);
  mObjects[0].ValueOf('ClientHeight', mValue);
  AClient.cy := StrToInt(mValue);
  for mObject in mObjects do
  begin
    if (mObject.Depth <> 1) or mObject.ValueOf('Width', mValue) then
    begin
      Continue;
    end;
    mItem := Default(TAtlasTrayItem);
    mItem.Name := mObject.Name;
    mItem.ClassChain := [mObject.TypeName];
    mObject.ValueOf('Left', mValue);
    mItem.Position.X := StrToInt(mValue);
    mObject.ValueOf('Top', mValue);
    mItem.Position.Y := StrToInt(mValue);
    Result := Result + [mItem];
  end;
end;

function Positions(const AItems: TArray<TAtlasTrayItem>): TArray<TPoint>;
var
  mItem: TAtlasTrayItem;
begin
  Result := nil;
  for mItem in AItems do
  begin
    Result := Result + [mItem.Position];
  end;
end;

{ TAtlasNonVisualTrayTests }

procedure TAtlasNonVisualTrayTests.Groups;
begin
  Assert.IsTrue(TAtlasNonVisualTray.GroupOf(['TMyQuery', 'TFDCustomQuery', 'TFDDataSet', 'TDataSet']) =
    TAtlasTrayGroup.Data, 'über den Vorfahren');
  Assert.IsTrue(TAtlasNonVisualTray.GroupOf(['TFDConnection']) = TAtlasTrayGroup.Data, 'Verbindung');
  Assert.IsTrue(TAtlasNonVisualTray.GroupOf(['TActionList', 'TCustomActionList']) = TAtlasTrayGroup.Actions);
  Assert.IsTrue(TAtlasNonVisualTray.GroupOf(['TPopupMenu', 'TMenu']) = TAtlasTrayGroup.Actions, 'Menü');
  Assert.IsTrue(TAtlasNonVisualTray.GroupOf(['TSaveDialog', 'TOpenDialog', 'TCommonDialog']) =
    TAtlasTrayGroup.Dialogs);
  Assert.IsTrue(TAtlasNonVisualTray.GroupOf(['TVirtualImageList', 'TCustomImageList']) = TAtlasTrayGroup.Images);
  Assert.IsTrue(TAtlasNonVisualTray.GroupOf(['TTimer', 'TComponent']) = TAtlasTrayGroup.Other);
  Assert.AreEqual('dialogs', TAtlasNonVisualTray.GroupKey(TAtlasTrayGroup.Dialogs));
end;

procedure TAtlasNonVisualTrayTests.FixtureRows;
var
  mClient: TSize;
  mRows: TArray<TAtlasTrayItem>;
begin
  mRows := TAtlasNonVisualTray.Rows(FixtureItems(mClient), '');
  Assert.AreEqual(4, Integer(Length(mRows)), 'das Edit gehört nicht dazu');
  Assert.AreEqual('dsKunden', mRows[0].Name);
  Assert.IsTrue(mRows[0].Group = TAtlasTrayGroup.Data);
  Assert.AreEqual('qryKunden', mRows[1].Name);
  Assert.IsTrue(mRows[1].Group = TAtlasTrayGroup.Data);
  Assert.AreEqual('dlgOpen', mRows[2].Name);
  Assert.IsTrue(mRows[2].Group = TAtlasTrayGroup.Dialogs);
  Assert.AreEqual('tmrRefresh', mRows[3].Name);
  Assert.IsTrue(mRows[3].Group = TAtlasTrayGroup.Other);
  Assert.AreEqual('TFDQuery', mRows[1].ClassName);
end;

procedure TAtlasNonVisualTrayTests.Filter;
var
  mClient: TSize;
  mRows: TArray<TAtlasTrayItem>;
begin
  mRows := TAtlasNonVisualTray.Rows(FixtureItems(mClient), ' KUNDEN ');
  Assert.AreEqual(2, Integer(Length(mRows)));
  Assert.AreEqual('dsKunden', mRows[0].Name);
  Assert.AreEqual('qryKunden', mRows[1].Name);
  Assert.AreEqual(0, Integer(Length(TAtlasNonVisualTray.Rows(FixtureItems(mClient), 'xyz'))));
end;

procedure TAtlasNonVisualTrayTests.FreePositionBottomEdge;
var
  mPoint: TPoint;
begin
  mPoint := TAtlasNonVisualTray.FreePosition(nil, TSize.Create(400, 300));
  Assert.AreEqual(8, mPoint.X);
  Assert.AreEqual(300 - 28 - 8, mPoint.Y);
end;

procedure TAtlasNonVisualTrayTests.FreePositionFixture;
var
  mClient: TSize;
  mPoint: TPoint;
begin
  // Unten liegen qryKunden (8), dsKunden (44) und dlgOpen (80) bei Top 264.
  mPoint := TAtlasNonVisualTray.FreePosition(Positions(FixtureItems(mClient)), mClient);
  Assert.AreEqual(116, mPoint.X, 'nächste freie Stelle rechts daneben');
  Assert.AreEqual(264, mPoint.Y);
end;

procedure TAtlasNonVisualTrayTests.FreePositionFull;
var
  mPoint: TPoint;
begin
  // Untere Reihe voll (Platz für zwei Symbole): eine Reihe darüber.
  mPoint := TAtlasNonVisualTray.FreePosition([Point(8, 64), Point(44, 64)], TSize.Create(90, 100));
  Assert.AreEqual(8, mPoint.X);
  Assert.AreEqual(64 - 36, mPoint.Y);
  // Kein Platz: links oben.
  mPoint := TAtlasNonVisualTray.FreePosition(nil, TSize.Create(20, 20));
  Assert.AreEqual(8, mPoint.X);
  Assert.AreEqual(8, mPoint.Y);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasNonVisualTrayTests);

end.
