unit Atlas.UI.Analysis.FormLayout.Tests;

// Maße der Eingabedialoge des Moduls Analyse: bei 96 dpi die logischen Werte, bei höherer DPI gerundet
// hochgerechnet; Feldkante und Innenbreite folgen aus den Teilen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Analysis')]
  TAtlasFormLayoutTests = class
  public
    [Test]
    procedure At96DpiKeepsLogicalValues;
    [Test]
    procedure At144DpiScalesEveryValue;
    [Test]
    procedure FieldLeftAndClientWidthFollowParts;
  end;

implementation

uses
  Atlas.UI.Analysis.FormLayout;

const
  cEditWidth = 320;
  cBasePpi = 96;
  cHighPpi = 144;

{ TAtlasFormLayoutTests }

procedure TAtlasFormLayoutTests.At96DpiKeepsLogicalValues;
var
  mLayout: TAtlasFormLayout;
begin
  mLayout := TAtlasFormLayout.Create(cEditWidth, cBasePpi);
  Assert.AreEqual(TAtlasFormLayout.cGap, mLayout.Gap);
  Assert.AreEqual(TAtlasFormLayout.cLabelWidth, mLayout.LabelWidth);
  Assert.AreEqual(cEditWidth, mLayout.EditWidth);
  Assert.AreEqual(TAtlasFormLayout.cSpacing, mLayout.Spacing);
  Assert.AreEqual(TAtlasFormLayout.cLabelOffset, mLayout.LabelOffset);
end;

procedure TAtlasFormLayoutTests.At144DpiScalesEveryValue;
var
  mLayout: TAtlasFormLayout;
begin
  mLayout := TAtlasFormLayout.Create(cEditWidth, cHighPpi);
  Assert.AreEqual(18, mLayout.Gap);
  Assert.AreEqual(195, mLayout.LabelWidth);
  Assert.AreEqual(480, mLayout.EditWidth);
  Assert.AreEqual(12, mLayout.Spacing);
  // 4,5 rundet kaufmännisch auf.
  Assert.AreEqual(5, mLayout.LabelOffset);
end;

procedure TAtlasFormLayoutTests.FieldLeftAndClientWidthFollowParts;
var
  mLayout: TAtlasFormLayout;
begin
  mLayout := TAtlasFormLayout.Create(cEditWidth, cBasePpi);
  Assert.AreEqual(TAtlasFormLayout.cGap + TAtlasFormLayout.cLabelWidth, mLayout.FieldLeft);
  Assert.AreEqual(2 * TAtlasFormLayout.cGap + TAtlasFormLayout.cLabelWidth + cEditWidth, mLayout.ClientWidth);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasFormLayoutTests);

end.
