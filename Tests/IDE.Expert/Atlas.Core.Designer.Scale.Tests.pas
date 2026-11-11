unit Atlas.Core.Designer.Scale.Tests;

// Tests für die Vorschau in anderen Skalierungen (#607): Rundung wie MulDiv
// bzw. ChangeScale, lange Texte, Skalierungsliste, abgeschnittene Texte mit
// fester Textbreite (ohne GDI), mitwachsende AutoSize-Labels, Bildschirm samt
// Rahmen und Taskleiste und Scaled = False.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Designer')]
  TAtlasFormScaleTests = class
  public
    [Test]
    procedure ValueRoundsLikeMulDiv;
    [Test]
    procedure NodesScaleSeparately;
    [Test]
    procedure LongText;
    [Test]
    procedure ParseLevels;
    [Test]
    procedure LabelClippedAt150;
    [Test]
    procedure LongTextClipsButton;
    [Test]
    procedure AutoSizeLabelGrowsOut;
    [Test]
    procedure FormTooLargeForScreen;
    [Test]
    procedure NotScaledKeepsLayout;
    [Test]
    procedure WordWrapIsNotChecked;
  end;

implementation

uses
  System.Types,
  System.SysUtils,
  Atlas.Core.Designer.Layout,
  Atlas.Core.Designer.Scale;

const
  cCharWidth = 6;

function Node(const AName: string; AParent, ALeft, ATop, AWidth, AHeight: Integer): TAtlasLayoutNode;
begin
  Result := TAtlasLayoutNode.Create(AName, 'TControl', AParent, Bounds(ALeft, ATop, AWidth, AHeight));
end;

function Text(const AText: string; AExtra: Integer): TAtlasScaleText;
begin
  Result := Default(TAtlasScaleText);
  Result.Text := AText;
  Result.Extra := AExtra;
end;

function Setup(APpi, AWidth, AHeight: Integer): TAtlasScaleSetup;
begin
  Result := Default(TAtlasScaleSetup);
  Result.DesignPpi := TAtlasFormScale.cBasePpi;
  Result.Ppi := APpi;
  Result.Scaled := True;
  Result.Client := TSize.Create(AWidth, AHeight);
end;

/// <summary>Feste Breite je Zeichen; über 100 % ein Pixel mehr, wie Schriften, die stärker wachsen als die Lage.
/// </summary>
function FixedWidth: TAtlasTextWidth;
begin
  Result :=
    function(const AText: TAtlasScaleText; const ALine: string; APpi: Integer): Integer
    var
      mChar: Integer;
    begin
      mChar := cCharWidth * APpi div TAtlasFormScale.cBasePpi;
      if APpi > TAtlasFormScale.cBasePpi then
      begin
        Inc(mChar);
      end;
      Result := Length(ALine) * mChar;
    end;
end;

function Has(const AFindings: TArray<TAtlasLayoutFinding>; ANode: Integer; AProblem: TAtlasLayoutProblem;
  out AFinding: TAtlasLayoutFinding): Boolean;
var
  mFinding: TAtlasLayoutFinding;
begin
  for mFinding in AFindings do
  begin
    if (mFinding.Node = ANode) and (mFinding.Problem = AProblem) then
    begin
      AFinding := mFinding;
      Exit(True);
    end;
  end;
  AFinding := Default(TAtlasLayoutFinding);
  Result := False;
end;

procedure AssertRect(const AExpected, AActual: TRect);
begin
  Assert.AreEqual(AExpected.Left, AActual.Left, 'Left');
  Assert.AreEqual(AExpected.Top, AActual.Top, 'Top');
  Assert.AreEqual(AExpected.Right, AActual.Right, 'Right');
  Assert.AreEqual(AExpected.Bottom, AActual.Bottom, 'Bottom');
end;

{ TAtlasFormScaleTests }

procedure TAtlasFormScaleTests.ValueRoundsLikeMulDiv;
begin
  Assert.AreEqual(113, TAtlasFormScale.Value(75, 96, 144));
  Assert.AreEqual(-18, TAtlasFormScale.Value(-12, 96, 144));
  Assert.AreEqual(-17, TAtlasFormScale.Value(-11, 96, 144), 'halbe Pixel von der Null weg');
  Assert.AreEqual(1, TAtlasFormScale.Value(1, 96, 120));
  Assert.AreEqual(5, TAtlasFormScale.Value(5, 96, 96));
  Assert.AreEqual(5, TAtlasFormScale.Value(5, 0, 144), 'ohne PixelsPerInch bleibt der Wert');
end;

procedure TAtlasFormScaleTests.NodesScaleSeparately;
var
  mNodes: TArray<TAtlasLayoutNode>;
begin
  mNodes := [Node('btn', -1, 10, 10, 75, 25)];
  mNodes[0].Margins := Rect(3, 3, 3, 3);
  mNodes[0].MinWidth := 50;
  mNodes := TAtlasFormScale.Nodes(mNodes, 96, 144);
  // Breite 112,5 → 113 und Höhe 37,5 → 38 einzeln gerundet.
  AssertRect(Rect(15, 15, 128, 53), mNodes[0].Bounds);
  AssertRect(Rect(5, 5, 5, 5), mNodes[0].Margins);
  Assert.AreEqual(75, mNodes[0].MinWidth);
end;

procedure TAtlasFormScaleTests.LongText;
begin
  Assert.AreEqual('SpeichernSpe', TAtlasFormScale.LongText('Speichern', 30));
  Assert.AreEqual('OKO', TAtlasFormScale.LongText('OK', 30));
  Assert.AreEqual('Speichern', TAtlasFormScale.LongText('Speichern', 0));
  Assert.AreEqual('ababab', TAtlasFormScale.LongText('ab', 200), 'kurzer Text wird wiederholt');
end;

procedure TAtlasFormScaleTests.ParseLevels;
var
  mLevels: TArray<Integer>;
begin
  mLevels := TAtlasFormScale.ParseLevels('100, 125 %; 30, kaputt, 200');
  Assert.AreEqual(3, Integer(Length(mLevels)));
  Assert.AreEqual(125, mLevels[1]);
  Assert.AreEqual(200, mLevels[2]);
  mLevels := TAtlasFormScale.ParseLevels('');
  Assert.AreEqual(1, Integer(Length(mLevels)));
  Assert.AreEqual(100, mLevels[0]);
end;

procedure TAtlasFormScaleTests.LabelClippedAt150;
var
  mView: TAtlasScaleView;
  mFinding: TAtlasLayoutFinding;
begin
  // 9 Zeichen: bei 100 % 54 px in 56 px, bei 150 % 90 px in 84 px.
  mView := TAtlasFormScale.View([Node('lbl', -1, 8, 8, 56, 13)], [Text('Speichern', 0)], Setup(96, 300, 200),
    FixedWidth());
  Assert.IsFalse(Has(mView.Findings, 0, TAtlasLayoutProblem.Clipped, mFinding), '100 %');
  mView := TAtlasFormScale.View([Node('lbl', -1, 8, 8, 56, 13)], [Text('Speichern', 0)], Setup(144, 300, 200),
    FixedWidth());
  Assert.IsTrue(Has(mView.Findings, 0, TAtlasLayoutProblem.Clipped, mFinding), '150 %');
  Assert.AreEqual(6, mFinding.Amount);
  Assert.AreEqual(450, mView.Client.cx);
end;

procedure TAtlasFormScaleTests.LongTextClipsButton;
var
  mSetup: TAtlasScaleSetup;
  mView: TAtlasScaleView;
  mFinding: TAtlasLayoutFinding;
begin
  mSetup := Setup(96, 300, 200);
  mView := TAtlasFormScale.View([Node('btn', -1, 8, 8, 75, 25)], [Text('&Speichern', 16)], mSetup, FixedWidth());
  Assert.AreEqual('Speichern', mView.Texts[0], '„&“ zählt nicht');
  Assert.IsFalse(Has(mView.Findings, 0, TAtlasLayoutProblem.Clipped, mFinding), 'Original passt');
  mSetup.LongFactor := 30;
  mView := TAtlasFormScale.View([Node('btn', -1, 8, 8, 75, 25)], [Text('&Speichern', 16)], mSetup, FixedWidth());
  Assert.AreEqual('SpeichernSpe', mView.Texts[0]);
  Assert.IsTrue(Has(mView.Findings, 0, TAtlasLayoutProblem.Clipped, mFinding), 'lang');
  Assert.AreEqual(13, mFinding.Amount);
end;

procedure TAtlasFormScaleTests.AutoSizeLabelGrowsOut;
var
  mTexts: TArray<TAtlasScaleText>;
  mView: TAtlasScaleView;
  mFinding: TAtlasLayoutFinding;
begin
  mTexts := [Default(TAtlasScaleText), Text('Sehr langer Text', 0)];
  mTexts[1].AutoSize := True;
  mView := TAtlasFormScale.View([Node('pnl', -1, 0, 0, 150, 50), Node('lbl', 0, 100, 10, 30, 13)], mTexts,
    Setup(96, 300, 200), FixedWidth());
  Assert.AreEqual(196, mView.Bounds[1].Right, 'wächst mit dem Text');
  Assert.IsFalse(Has(mView.Findings, 1, TAtlasLayoutProblem.Clipped, mFinding), 'AutoSize schneidet nicht ab');
  Assert.IsTrue(Has(mView.Findings, 1, TAtlasLayoutProblem.OutRight, mFinding));
  Assert.AreEqual(46, mFinding.Amount);
end;

procedure TAtlasFormScaleTests.FormTooLargeForScreen;
var
  mSetup: TAtlasScaleSetup;
  mView: TAtlasScaleView;
  mFinding: TAtlasLayoutFinding;
begin
  mSetup := Setup(96, 600, 800);
  mSetup.Frame := TSize.Create(16, 39);
  mSetup.Screen := TSize.Create(1366, 768);
  mView := TAtlasFormScale.View([], [], mSetup, FixedWidth());
  Assert.AreEqual(681, mView.Usable.cy, 'ohne Rahmen und Taskleiste');
  Assert.IsTrue(Has(mView.Findings, -1, TAtlasLayoutProblem.ScreenHeight, mFinding));
  Assert.AreEqual(119, mFinding.Amount);
  Assert.IsFalse(Has(mView.Findings, -1, TAtlasLayoutProblem.ScreenWidth, mFinding));
  mSetup.Screen := TSize.Create(0, 0);
  mView := TAtlasFormScale.View([], [], mSetup, FixedWidth());
  Assert.AreEqual(0, Integer(Length(mView.Findings)), 'kein Limit');
end;

procedure TAtlasFormScaleTests.NotScaledKeepsLayout;
var
  mSetup: TAtlasScaleSetup;
  mView: TAtlasScaleView;
  mFinding: TAtlasLayoutFinding;
begin
  mSetup := Setup(144, 600, 600);
  mSetup.Scaled := False;
  mSetup.Frame := TSize.Create(16, 40);
  mSetup.Screen := TSize.Create(1366, 768);
  mView := TAtlasFormScale.View([Node('btn', -1, 10, 10, 75, 25)], [Default(TAtlasScaleText)], mSetup,
    FixedWidth());
  AssertRect(Rect(10, 10, 85, 35), mView.Bounds[0]);
  Assert.AreEqual(600, mView.Client.cy);
  // Rahmen 60 und Taskleiste 72 wachsen trotzdem: 768 - 132 = 636 reicht.
  Assert.AreEqual(636, mView.Usable.cy);
  Assert.IsFalse(Has(mView.Findings, -1, TAtlasLayoutProblem.ScreenHeight, mFinding));
end;

procedure TAtlasFormScaleTests.WordWrapIsNotChecked;
var
  mTexts: TArray<TAtlasScaleText>;
  mView: TAtlasScaleView;
  mFinding: TAtlasLayoutFinding;
begin
  mTexts := [Text('Ein sehr langer Hinweistext', 0)];
  mTexts[0].WordWrap := True;
  mView := TAtlasFormScale.View([Node('lbl', -1, 8, 8, 50, 40)], mTexts, Setup(96, 300, 200), FixedWidth());
  Assert.IsFalse(Has(mView.Findings, 0, TAtlasLayoutProblem.Clipped, mFinding));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasFormScaleTests);

end.
