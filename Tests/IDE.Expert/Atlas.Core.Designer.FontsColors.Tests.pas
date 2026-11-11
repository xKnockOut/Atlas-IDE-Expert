unit Atlas.Core.Designer.FontsColors.Tests;

// Tests für Schriften und Farben eines Formulars (#741): Gruppierung,
// Ausreißer, Teilersetzung, ParentFont-Regel über mehrere Ebenen, Höhe aus
// der Größe und ignorierte Farben.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Designer')]
  TAtlasFontsColorsTests = class
  public
    [Test]
    procedure Grouping;
    [Test]
    procedure Outliers;
    [Test]
    procedure OnlyName;
    [Test]
    procedure RestoreParent;
    [Test]
    procedure RestoreParentNested;
    [Test]
    procedure CopyWithoutRestore;
    [Test]
    procedure OnlySelected;
    [Test]
    procedure Heights;
    [Test]
    procedure IgnoredColors;
    [Test]
    procedure ColorToParent;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Designer.FontsColors;

const
  cForm = 'frmMain';
  cAll = [TAtlasFontPart.Name, TAtlasFontPart.Size, TAtlasFontPart.Style, TAtlasFontPart.Color];
  cNameSize = [TAtlasFontPart.Name, TAtlasFontPart.Size];

function Segoe: TAtlasFontKey;
begin
  Result := TAtlasFontKey.Create('Segoe UI', 9, 0, 'clWindowText');
end;

function Tahoma: TAtlasFontKey;
begin
  Result := TAtlasFontKey.Create('Tahoma', 8, 0, 'clWindowText');
end;

function Use(const AName, AParent: string; const AFont: TAtlasFontKey; AParentFont: Boolean;
  const AColor: string = 'clBtnFace'; AParentColor: Boolean = True): TAtlasFontUse;
begin
  Result.Component := AName;
  Result.ParentName := AParent;
  Result.Font := AFont;
  Result.ParentFont := AParentFont;
  Result.Color := AColor;
  Result.ParentColor := AParentColor;
  Result.HasColor := True;
end;

/// <summary>Formular in Segoe UI 9, 14 Edits in Tahoma 8, zwei erbende Labels.</summary>
function Sample: TArray<TAtlasFontUse>;
var
  mIndex: Integer;
begin
  Result := [Use(cForm, '', Segoe, False, 'clBtnFace', False)];
  for mIndex := 1 to 14 do
  begin
    Result := Result + [Use('edt' + IntToStr(mIndex), cForm, Tahoma, False)];
  end;
  Result := Result + [Use('lblA', cForm, Segoe, True), Use('lblB', cForm, Segoe, True)];
end;

procedure TAtlasFontsColorsTests.Grouping;
var
  mRows: TArray<TAtlasFontRow>;
begin
  mRows := TAtlasFontsColors.FontRows(Sample, cForm);
  Assert.AreEqual(2, Integer(Length(mRows)));
  Assert.IsTrue(mRows[0].IsFormFont, 'Formularschrift markiert');
  Assert.AreEqual(1, Integer(Length(mRows[0].Own)));
  Assert.AreEqual(2, Integer(Length(mRows[0].Inherits)));
  Assert.AreEqual(14, Integer(Length(mRows[1].Own)));
  Assert.AreEqual('Segoe UI 9 fett', TAtlasFontsColors.FontText(TAtlasFontKey.Create('Segoe UI', 9, 1, ''),
    ['fett', 'kursiv']));
end;

procedure TAtlasFontsColorsTests.Outliers;
var
  mUses: TArray<TAtlasFontUse>;
  mRows: TArray<TAtlasFontRow>;
begin
  mUses := Sample + [Use('lblOdd', cForm, TAtlasFontKey.Create('MS Sans Serif', 8, 0, 'clWindowText'), False)];
  mRows := TAtlasFontsColors.FontRows(mUses, cForm);
  Assert.AreEqual(3, Integer(Length(mRows)));
  Assert.IsFalse(mRows[0].Outlier, 'Formularschrift nie');
  Assert.IsFalse(mRows[1].Outlier, '14 Komponenten');
  Assert.IsTrue(mRows[2].Outlier, 'eine Komponente');
end;

procedure TAtlasFontsColorsTests.OnlyName;
var
  mPlan: TArray<TAtlasFontChange>;
begin
  mPlan := TAtlasFontsColors.FontPlan(Sample, TAtlasFontRule.Create(Tahoma, Segoe, cAll, [TAtlasFontPart.Name]), True,
    nil);
  Assert.AreEqual(14, Integer(Length(mPlan)));
  Assert.AreEqual('Segoe UI', mPlan[0].Font.Name);
  Assert.AreEqual(8, mPlan[0].Font.Size, 'Größe behalten');
  Assert.IsFalse(mPlan[0].ToParent, 'Segoe UI 8 ist nicht die Schrift des Parents');
end;

procedure TAtlasFontsColorsTests.RestoreParent;
var
  mPlan: TArray<TAtlasFontChange>;
  mChange: TAtlasFontChange;
begin
  mPlan := TAtlasFontsColors.FontPlan(Sample, TAtlasFontRule.Create(Tahoma, Segoe, cAll, cNameSize), True, nil);
  Assert.AreEqual(14, Integer(Length(mPlan)));
  for mChange in mPlan do
  begin
    Assert.IsTrue(mChange.ToParent, mChange.Component);
  end;
end;

procedure TAtlasFontsColorsTests.RestoreParentNested;
var
  mUses: TArray<TAtlasFontUse>;
  mPlan: TArray<TAtlasFontChange>;
begin
  // Panel in Tahoma 8 mit einem Edit in Tahoma 8 und einem erbenden Label: beide Ebenen ändern sich.
  mUses := [Use(cForm, '', Segoe, False), Use('pnlA', cForm, Tahoma, False), Use('edtA', 'pnlA', Tahoma, False),
    Use('lblA', 'pnlA', Tahoma, True)];
  mPlan := TAtlasFontsColors.FontPlan(mUses, TAtlasFontRule.Create(Tahoma, Segoe, cNameSize, cNameSize), True, nil);
  Assert.AreEqual(2, Integer(Length(mPlan)));
  Assert.AreEqual('pnlA', mPlan[0].Component);
  Assert.IsTrue(mPlan[0].ToParent, 'Panel erbt vom Formular');
  Assert.IsTrue(mPlan[1].ToParent, 'Edit erbt vom geänderten Panel');
end;

procedure TAtlasFontsColorsTests.CopyWithoutRestore;
var
  mPlan: TArray<TAtlasFontChange>;
begin
  mPlan := TAtlasFontsColors.FontPlan(Sample, TAtlasFontRule.Create(Tahoma, Segoe, [TAtlasFontPart.Name], cNameSize),
    False, nil);
  Assert.AreEqual(14, Integer(Length(mPlan)));
  Assert.IsFalse(mPlan[0].ToParent);
  Assert.IsTrue(mPlan[0].Font.Same(Segoe));
end;

procedure TAtlasFontsColorsTests.OnlySelected;
var
  mPlan: TArray<TAtlasFontChange>;
begin
  mPlan := TAtlasFontsColors.FontPlan(Sample, TAtlasFontRule.Create(Tahoma, Segoe, [TAtlasFontPart.Name],
    [TAtlasFontPart.Name]), True, ['edt3', 'edt7']);
  Assert.AreEqual(2, Integer(Length(mPlan)));
  Assert.AreEqual('edt7', mPlan[1].Component);
end;

procedure TAtlasFontsColorsTests.Heights;
begin
  Assert.AreEqual(-12, TAtlasFontsColors.HeightOf(9, 96));
  Assert.AreEqual(-11, TAtlasFontsColors.HeightOf(8, 96));
  Assert.AreEqual(-18, TAtlasFontsColors.HeightOf(9, 144));
end;

procedure TAtlasFontsColorsTests.IgnoredColors;
var
  mUses: TArray<TAtlasFontUse>;
  mRows: TArray<TAtlasColorRow>;
begin
  mUses := Sample + [Use('pnlRed', cForm, TAtlasFontKey.Create('Segoe UI', 9, 0, 'clRed'), False, 'clRed', False),
    Use('lblRed', cForm, TAtlasFontKey.Create('Segoe UI', 9, 0, 'clRed'), False)];
  mRows := TAtlasFontsColors.ColorRows(mUses, TAtlasFontsColors.cDefaultIgnore);
  Assert.AreEqual(1, Integer(Length(mRows)), 'nur clRed');
  Assert.AreEqual('clRed', mRows[0].Color);
  Assert.AreEqual(2, Integer(Length(mRows[0].Components)), 'pnlRed einmal gezählt');
  Assert.IsTrue(mRows[0].Outlier);
  Assert.AreEqual(3, Integer(Length(TAtlasFontsColors.ColorRows(mUses, ''))), 'mit clBtnFace und clWindowText');
end;

procedure TAtlasFontsColorsTests.ColorToParent;
var
  mUses: TArray<TAtlasFontUse>;
  mPlan: TArray<TAtlasColorChange>;
begin
  mUses := [Use(cForm, '', Segoe, False, 'clBtnFace', False), Use('pnlA', cForm, Segoe, True, '$00F0F0F0', False),
    Use('pnlB', 'pnlA', Segoe, True, '$00F0F0F0', False)];
  mPlan := TAtlasFontsColors.ColorPlan(mUses, '$00F0F0F0', 'clBtnFace', True, nil);
  Assert.AreEqual(2, Integer(Length(mPlan)));
  Assert.IsTrue(mPlan[0].ToParent, 'wie das Formular');
  Assert.IsTrue(mPlan[1].ToParent, 'wie das geänderte Panel');
  mPlan := TAtlasFontsColors.ColorPlan(mUses, '$00F0F0F0', 'clRed', True, nil);
  Assert.IsFalse(mPlan[0].ToParent);
  Assert.IsTrue(mPlan[1].ToParent, 'Panel wird auch rot');
end;

end.
