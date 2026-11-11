unit Atlas.Core.Designer.FitText.Tests;

// Tests der Breite nach Text (#730): Maximum, Mindestbreite, Reihe mit fester
// rechter bzw. linker Kante, Spalte, Align und AutoSize, „&“ und mehrzeilige
// Beschriftungen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Designer')]
  TAtlasFitTextTests = class
  public
    [Test]
    procedure MaximumAndMinimum;
    [Test]
    procedure RowKeepsRightEdge;
    [Test]
    procedure RowKeepsLeftEdge;
    [Test]
    procedure ColumnKeepsLeftOrRight;
    [Test]
    procedure FixedKeepsWidth;
    [Test]
    procedure Accelerators;
    [Test]
    procedure LongestLine;
  end;

implementation

uses
  System.Types,
  Atlas.Core.Designer.FitText;

procedure TAtlasFitTextTests.MaximumAndMinimum;
var
  mItems: TArray<TAtlasFitItem>;
begin
  mItems := [TAtlasFitItem.Create(Rect(0, 0, 75, 25), 70, 0, False, False),
    TAtlasFitItem.Create(Rect(0, 30, 75, 55), 12, 0, False, False)];
  Assert.AreEqual(86, TAtlasFitText.Width(mItems, 16, 75), 'längster Text plus Innenabstand');
  mItems := [TAtlasFitItem.Create(Rect(0, 0, 75, 25), 12, 0, False, False)];
  Assert.AreEqual(75, TAtlasFitText.Width(mItems, 16, 75), 'nie schmaler als die Mindestbreite');
  mItems := [TAtlasFitItem.Create(Rect(0, 0, 75, 25), 70, 17, False, False)];
  Assert.AreEqual(103, TAtlasFitText.Width(mItems, 16, 75), 'Kästchen der Checkbox');
end;

procedure TAtlasFitTextTests.RowKeepsRightEdge;
var
  mItems: TArray<TAtlasFitItem>;
  mNew: TArray<TRect>;
begin
  // Übernehmen, OK, Abbrechen rechts unten, 6 px Abstand, OK mit akRight.
  mItems := [TAtlasFitItem.Create(Rect(150, 200, 225, 225), 60, 0, False, False),
    TAtlasFitItem.Create(Rect(231, 200, 306, 225), 15, 0, False, False),
    TAtlasFitItem.Create(Rect(312, 201, 387, 226), 50, 0, False, True)];
  mNew := TAtlasFitText.Apply(mItems, 90, 500);
  Assert.AreEqual(387, mNew[2].Right, 'rechte Kante bleibt');
  Assert.AreEqual(297, mNew[2].Left);
  Assert.AreEqual(291, mNew[1].Right, 'Abstand bleibt');
  Assert.AreEqual(201, mNew[1].Left);
  Assert.AreEqual(105, mNew[0].Left);
  Assert.AreEqual(201, mNew[2].Top, 'Oberkante bleibt');
end;

procedure TAtlasFitTextTests.RowKeepsLeftEdge;
var
  mItems: TArray<TAtlasFitItem>;
  mNew: TArray<TRect>;
begin
  mItems := [TAtlasFitItem.Create(Rect(110, 10, 185, 35), 0, 0, False, False),
    TAtlasFitItem.Create(Rect(10, 10, 85, 35), 0, 0, False, False)];
  mNew := TAtlasFitText.Apply(mItems, 90, 500);
  Assert.AreEqual(10, mNew[1].Left, 'linke Kante der Reihe bleibt');
  Assert.AreEqual(100, mNew[1].Right);
  Assert.AreEqual(125, mNew[0].Left, 'Abstand 25 bleibt');
  Assert.AreEqual(215, mNew[0].Right);
end;

procedure TAtlasFitTextTests.ColumnKeepsLeftOrRight;
var
  mItems: TArray<TAtlasFitItem>;
  mNew: TArray<TRect>;
begin
  mItems := [TAtlasFitItem.Create(Rect(10, 10, 85, 35), 0, 0, False, False),
    TAtlasFitItem.Create(Rect(20, 40, 95, 65), 0, 0, False, True)];
  Assert.IsFalse(TAtlasFitText.IsRow(mItems));
  mNew := TAtlasFitText.Apply(mItems, 100, 500);
  Assert.AreEqual(10, mNew[0].Left);
  Assert.AreEqual(110, mNew[0].Right);
  Assert.AreEqual(95, mNew[1].Right, 'akRight: rechte Kante bleibt');
  Assert.AreEqual(-5, mNew[1].Left);
end;

procedure TAtlasFitTextTests.FixedKeepsWidth;
var
  mItems: TArray<TAtlasFitItem>;
  mNew: TArray<TRect>;
begin
  mItems := [TAtlasFitItem.Create(Rect(10, 10, 60, 35), 120, 0, True, False),
    TAtlasFitItem.Create(Rect(70, 10, 145, 35), 20, 0, False, False)];
  Assert.AreEqual(136, TAtlasFitText.Width(mItems, 16, 75), 'AutoSize zählt beim Maximum mit');
  mNew := TAtlasFitText.Apply(mItems, 136, 500);
  Assert.AreEqual(50, mNew[0].Width, 'behält die Breite');
  Assert.AreEqual(70, mNew[1].Left);
  Assert.AreEqual(136, mNew[1].Width);
end;

procedure TAtlasFitTextTests.Accelerators;
begin
  Assert.AreEqual('Abbrechen', TAtlasFitText.StripAccel('&Abbrechen'));
  Assert.AreEqual('Laden & Speichern', TAtlasFitText.StripAccel('Laden && &Speichern'));
  Assert.AreEqual('Ende', TAtlasFitText.StripAccel('Ende&'));
end;

procedure TAtlasFitTextTests.LongestLine;
var
  mLines: TArray<string>;
begin
  mLines := TAtlasFitText.Lines('&Erste' + #13#10 + 'zweite Zeile' + #10 + 'drei');
  Assert.AreEqual(3, Length(mLines));
  Assert.AreEqual('Erste', mLines[0]);
  Assert.AreEqual('zweite Zeile', mLines[1]);
  Assert.AreEqual(1, Length(TAtlasFitText.Lines('')));
end;

end.
