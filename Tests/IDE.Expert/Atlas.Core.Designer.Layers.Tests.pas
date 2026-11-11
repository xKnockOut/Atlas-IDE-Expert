unit Atlas.Core.Designer.Layers.Tests;

// Tests für Ebenen im Designer (#749): Stapel, eine Ebene vor und zurück,
// nicht überlappende Nachbarn, fensterlose unter fensterbehafteten und ganz
// nach vorn/hinten.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Designer')]
  TAtlasLayersTests = class
  public
    [Test]
    procedure StackTopmostFirst;
    [Test]
    procedure StepBackBetweenTwo;
    [Test]
    procedure StepForward;
    [Test]
    procedure StepSkipsNonOverlapping;
    [Test]
    procedure NoOverlapNoChange;
    [Test]
    procedure GraphicStaysBelowWindowed;
    [Test]
    procedure ExtremeWithinKind;
  end;

implementation

uses
  System.Types,
  System.SysUtils,
  Atlas.Core.Designer.Layers;

function OrderText(const AOrder: TArray<Integer>): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex in AOrder do
  begin
    Result := Result + IntToStr(mIndex);
  end;
end;

function Panels: TArray<TAtlasLayerItem>;
begin
  Result := [TAtlasLayerItem.Create('pnlA', Bounds(0, 0, 100, 100), True),
    TAtlasLayerItem.Create('pnlB', Bounds(20, 20, 100, 100), True),
    TAtlasLayerItem.Create('pnlC', Bounds(40, 40, 100, 100), True)];
end;

procedure TAtlasLayersTests.StackTopmostFirst;
var
  mItems: TArray<TAtlasLayerItem>;
begin
  // Bild (fensterlos) unter Label (fensterlos, später), daneben ein Edit weit weg.
  mItems := [TAtlasLayerItem.Create('imgLogo', Bounds(10, 10, 200, 60), False),
    TAtlasLayerItem.Create('lblTitel', Bounds(20, 20, 80, 15), False),
    TAtlasLayerItem.Create('edtName', Bounds(300, 10, 100, 21), True)];
  Assert.AreEqual('10', OrderText(TAtlasLayers.Stack(mItems, Bounds(25, 25, 1, 1))));
  Assert.AreEqual('210', OrderText(TAtlasLayers.Stack(mItems, Bounds(0, 0, 500, 100))));
end;

procedure TAtlasLayersTests.StepBackBetweenTwo;
begin
  // Oberstes (pnlC) eine Ebene zurück: zwischen pnlA und pnlB.
  Assert.AreEqual('021', OrderText(TAtlasLayers.Step(Panels, 2, False)));
end;

procedure TAtlasLayersTests.StepForward;
begin
  Assert.AreEqual('102', OrderText(TAtlasLayers.Step(Panels, 0, True)));
  Assert.AreEqual('', OrderText(TAtlasLayers.Step(Panels, 2, True)), 'schon oben');
end;

procedure TAtlasLayersTests.StepSkipsNonOverlapping;
var
  mItems: TArray<TAtlasLayerItem>;
begin
  mItems := Panels;
  mItems[1].Bounds := Bounds(500, 500, 10, 10);
  Assert.AreEqual('120', OrderText(TAtlasLayers.Step(mItems, 0, True)), 'über pnlC, pnlB zählt nicht');
end;

procedure TAtlasLayersTests.NoOverlapNoChange;
var
  mItems: TArray<TAtlasLayerItem>;
begin
  mItems := [TAtlasLayerItem.Create('a', Bounds(0, 0, 10, 10), True),
    TAtlasLayerItem.Create('b', Bounds(10, 0, 10, 10), True)];
  Assert.AreEqual(0, Length(TAtlasLayers.Step(mItems, 0, True)), 'nur berührend');
  Assert.AreEqual(0, Length(TAtlasLayers.Step(mItems, 1, False)));
end;

procedure TAtlasLayersTests.GraphicStaysBelowWindowed;
var
  mItems: TArray<TAtlasLayerItem>;
begin
  mItems := [TAtlasLayerItem.Create('lblName', Bounds(0, 0, 100, 20), False),
    TAtlasLayerItem.Create('edtName', Bounds(10, 5, 100, 21), True)];
  Assert.AreEqual(0, Length(TAtlasLayers.Step(mItems, 0, True)));
  Assert.AreEqual(0, Length(TAtlasLayers.Step(mItems, 1, False)));
  Assert.AreEqual(0, Length(TAtlasLayers.Extreme(mItems, 0, True)));
end;

procedure TAtlasLayersTests.ExtremeWithinKind;
var
  mItems: TArray<TAtlasLayerItem>;
begin
  mItems := [TAtlasLayerItem.Create('lbl1', Bounds(0, 0, 10, 10), False),
    TAtlasLayerItem.Create('lbl2', Bounds(0, 0, 10, 10), False),
    TAtlasLayerItem.Create('pnl1', Bounds(0, 0, 10, 10), True),
    TAtlasLayerItem.Create('pnl2', Bounds(0, 0, 10, 10), True)];
  Assert.AreEqual('1023', OrderText(TAtlasLayers.Extreme(mItems, 0, True)));
  Assert.AreEqual('0132', OrderText(TAtlasLayers.Extreme(mItems, 3, False)));
  Assert.AreEqual(0, Length(TAtlasLayers.Extreme(mItems, 3, True)));
end;

end.
