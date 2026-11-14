unit Atlas.Core.Designer.Neighbours.Tests;

// Tests der räumlichen Navigation im Designer (#745): alle Richtungen,
// Gewichtung, Überlappung, Containerwechsel, Elternelement und erstes Kind,
// nichtvisuelle Komponenten.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Designer.Neighbours;

type
  [TestFixture]
  [Category('Atlas.IDE.Designer')]
  TAtlasNeighboursTests = class
  private
    FItems: TArray<TAtlasNeighbourItem>;
    function Go(const AFrom: string; ADirection: TAtlasNeighbourDirection): string; overload;
    function Go(const AFrom: string; ADirection: TAtlasNeighbourDirection; ACross: Boolean): string; overload;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure AllDirections;
    [Test]
    procedure BelowBeatsFurtherRight;
    [Test]
    procedure OverlapGoesFirst;
    [Test]
    procedure EdgeOfFormHasNoNeighbour;
    [Test]
    procedure CrossesIntoNextPanel;
    [Test]
    procedure StaysInPanelWithoutCross;
    [Test]
    procedure ParentAndFirstChild;
    [Test]
    procedure NextContainer;
    [Test]
    procedure NonVisualStayApart;
  end;

implementation

uses
  System.Types;

procedure TAtlasNeighboursTests.Setup;
begin
  FItems := [
    TAtlasNeighbourItem.Create('edtVorname', '', Rect(10, 10, 90, 30), True, False),
    TAtlasNeighbourItem.Create('edtNachname', '', Rect(100, 10, 180, 30), True, False),
    TAtlasNeighbourItem.Create('edtFirma', '', Rect(190, 10, 270, 30), True, False),
    TAtlasNeighbourItem.Create('edtStrasse', '', Rect(100, 40, 180, 60), True, False),
    TAtlasNeighbourItem.Create('edtOrt', '', Rect(300, 50, 380, 70), True, False),
    TAtlasNeighbourItem.Create('pnlLinks', '', Rect(0, 100, 200, 200), True, True),
    TAtlasNeighbourItem.Create('e1', 'pnlLinks', Rect(10, 110, 90, 130), True, False),
    TAtlasNeighbourItem.Create('e2', 'pnlLinks', Rect(100, 110, 190, 130), True, False),
    TAtlasNeighbourItem.Create('pnlRechts', '', Rect(210, 100, 400, 200), True, True),
    TAtlasNeighbourItem.Create('f1', 'pnlRechts', Rect(220, 140, 300, 160), True, False),
    TAtlasNeighbourItem.Create('f2', 'pnlRechts', Rect(220, 110, 300, 130), True, False),
    TAtlasNeighbourItem.Create('dsKunden', '', Rect(10, 10, 38, 38), False, False),
    TAtlasNeighbourItem.Create('dsLager', '', Rect(60, 10, 88, 38), False, False)];
end;

procedure TAtlasNeighboursTests.TearDown;
begin
  FItems := nil;
end;

function TAtlasNeighboursTests.Go(const AFrom: string; ADirection: TAtlasNeighbourDirection): string;
begin
  Result := Go(AFrom, ADirection, True);
end;

function TAtlasNeighboursTests.Go(const AFrom: string; ADirection: TAtlasNeighbourDirection;
  ACross: Boolean): string;
var
  mIndex: Integer;
begin
  mIndex := TAtlasNeighbours.Find(FItems, TAtlasNeighbours.IndexOf(FItems, AFrom), ADirection, ACross);
  Result := '';
  if mIndex >= 0 then
  begin
    Result := FItems[mIndex].Name;
  end;
end;

procedure TAtlasNeighboursTests.AllDirections;
begin
  Assert.AreEqual('edtFirma', Go('edtNachname', TAtlasNeighbourDirection.Right));
  Assert.AreEqual('edtVorname', Go('edtNachname', TAtlasNeighbourDirection.Left));
  Assert.AreEqual('edtStrasse', Go('edtNachname', TAtlasNeighbourDirection.Down));
  Assert.AreEqual('edtNachname', Go('edtStrasse', TAtlasNeighbourDirection.Up));
end;

procedure TAtlasNeighboursTests.BelowBeatsFurtherRight;
begin
  // edtOrt liegt tiefer, aber weit rechts: der Versatz quer zählt doppelt.
  Assert.AreEqual('edtStrasse', Go('edtNachname', TAtlasNeighbourDirection.Down));
end;

procedure TAtlasNeighboursTests.OverlapGoesFirst;
var
  mItems: TArray<TAtlasNeighbourItem>;
begin
  mItems := [
    TAtlasNeighbourItem.Create('A', '', Rect(0, 0, 50, 20), True, False),
    TAtlasNeighbourItem.Create('B', '', Rect(200, 0, 250, 20), True, False),
    TAtlasNeighbourItem.Create('C', '', Rect(60, 30, 110, 50), True, False)];
  Assert.AreEqual(1, TAtlasNeighbours.Find(mItems, 0, TAtlasNeighbourDirection.Right, False), 'gleiche Zeile');
  Assert.AreEqual(2, TAtlasNeighbours.Find(mItems, 0, TAtlasNeighbourDirection.Down, False));
end;

procedure TAtlasNeighboursTests.EdgeOfFormHasNoNeighbour;
begin
  Assert.AreEqual('', Go('edtVorname', TAtlasNeighbourDirection.Left));
  Assert.AreEqual('', Go('edtVorname', TAtlasNeighbourDirection.Up));
end;

procedure TAtlasNeighboursTests.CrossesIntoNextPanel;
begin
  Assert.AreEqual('f2', Go('e2', TAtlasNeighbourDirection.Right), 'in die gleiche Zeile des Nachbarpanels');
  Assert.AreEqual('e2', Go('f2', TAtlasNeighbourDirection.Left));
  Assert.AreEqual('e1', Go('e2', TAtlasNeighbourDirection.Left), 'im Panel zuerst');
end;

procedure TAtlasNeighboursTests.StaysInPanelWithoutCross;
begin
  Assert.AreEqual('', Go('e2', TAtlasNeighbourDirection.Right, False));
end;

procedure TAtlasNeighboursTests.ParentAndFirstChild;
var
  mPanel: Integer;
begin
  mPanel := TAtlasNeighbours.ParentOf(FItems, TAtlasNeighbours.IndexOf(FItems, 'e2'));
  Assert.AreEqual('pnlLinks', FItems[mPanel].Name);
  Assert.AreEqual('e1', FItems[TAtlasNeighbours.FirstChild(FItems, mPanel)].Name);
  Assert.AreEqual('f2', FItems[TAtlasNeighbours.FirstChild(FItems, TAtlasNeighbours.IndexOf(FItems,
    'pnlRechts'))].Name, 'oben links');
  Assert.AreEqual(-1, TAtlasNeighbours.ParentOf(FItems, 0), 'auf dem Formular');
  Assert.AreEqual(-1, TAtlasNeighbours.FirstChild(FItems, 0), 'kein Container');
end;

procedure TAtlasNeighboursTests.NextContainer;
begin
  Assert.AreEqual('f2', FItems[TAtlasNeighbours.NextContainer(FItems, TAtlasNeighbours.IndexOf(FItems, 'e1'),
    True)].Name);
  Assert.AreEqual('e1', FItems[TAtlasNeighbours.NextContainer(FItems, TAtlasNeighbours.IndexOf(FItems, 'f1'),
    False)].Name);
  Assert.AreEqual(-1, TAtlasNeighbours.NextContainer(FItems, TAtlasNeighbours.IndexOf(FItems, 'f1'), True),
    'letzter Container');
  Assert.AreEqual(-1, TAtlasNeighbours.NextContainer(FItems, 0, True), 'kein Container um edtVorname');
end;

procedure TAtlasNeighboursTests.NonVisualStayApart;
begin
  Assert.AreEqual('dsLager', Go('dsKunden', TAtlasNeighbourDirection.Right));
  Assert.AreEqual('edtNachname', Go('edtVorname', TAtlasNeighbourDirection.Right), 'keine Datenquelle');
  Assert.AreEqual('', Go('dsKunden', TAtlasNeighbourDirection.Down));
end;

end.
