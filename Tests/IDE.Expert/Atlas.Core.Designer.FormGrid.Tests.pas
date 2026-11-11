unit Atlas.Core.Designer.FormGrid.Tests;

// Tests für „Als Formularraster anordnen“ (#731): Paare nach FocusControl und
// nach Lage, Zeilen mit zwei Feldern (PLZ/Ort), Einzel-Controls, Memo, alle
// Varianten der Labellage, zwei Paare je Zeile, gleiche Feldbreite und
// TabOrder.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Designer')]
  TAtlasFormGridTests = class
  public
    [Test]
    procedure PartnersByFocusAndPosition;
    [Test]
    procedure EntriesKeepZipAndCity;
    [Test]
    procedure ScatteredPairsBecomeGrid;
    [Test]
    procedure RightAligned;
    [Test]
    procedure LabelsAbove;
    [Test]
    procedure SingleControlAndMemo;
    [Test]
    procedure TwoPerRow;
    [Test]
    procedure EqualWidth;
  end;

implementation

uses
  System.Types,
  Atlas.Core.Designer.FormGrid;

const
  cLabelAscent = 12;
  cFieldBaseline = 16;

function Lbl(const AName: string; ALeft, ATop, AWidth: Integer; const APartner: string = ''): TAtlasGridItem;
begin
  Result := TAtlasGridItem.Create(AName, Bounds(ALeft, ATop, AWidth, 15), True, APartner, cLabelAscent);
end;

function Fld(const AName: string; ALeft, ATop, AWidth: Integer; AHeight: Integer = 23): TAtlasGridItem;
var
  mBaseline: Integer;
begin
  mBaseline := cFieldBaseline;
  if AHeight > 40 then
  begin
    mBaseline := -1;
  end;
  Result := TAtlasGridItem.Create(AName, Bounds(ALeft, ATop, AWidth, AHeight), False, '', mBaseline);
end;

function Options(AAlign: TAtlasGridLabelAlign = TAtlasGridLabelAlign.Left): TAtlasGridOptions;
begin
  Result.RowGap := 8;
  Result.LabelGap := 8;
  Result.LabelAlign := AAlign;
  Result.EqualWidth := False;
  Result.TwoPerRow := False;
end;

/// <summary>Adresse: Name, Straße, PLZ/Ort, Telefon, verstreut.</summary>
function Address: TArray<TAtlasGridItem>;
begin
  Result := [Lbl('lblName', 10, 12, 40), Fld('edtName', 60, 8, 150), Lbl('lblStrasse', 14, 45, 48),
    Fld('edtStrasse', 70, 40, 150), Lbl('lblPlz', 8, 80, 60), Fld('edtPlz', 76, 75, 50), Fld('edtOrt', 132, 77, 100),
    Lbl('lblTelefon', 12, 112, 70, 'edtTelefon'), Fld('edtTelefon', 90, 110, 120)];
end;

procedure TAtlasFormGridTests.PartnersByFocusAndPosition;
var
  mPartners: TArray<Integer>;
begin
  mPartners := TAtlasFormGrid.Partners(Address);
  Assert.AreEqual(1, mPartners[0], 'Name rechts daneben');
  Assert.AreEqual(3, mPartners[2]);
  Assert.AreEqual(5, mPartners[4], 'PLZ: nächstes Feld');
  Assert.AreEqual(8, mPartners[7], 'FocusControl');
  Assert.AreEqual(-1, mPartners[1], 'Felder ohne Partner');
  mPartners := TAtlasFormGrid.Partners([Lbl('lblA', 8, 8, 40), Fld('edtA', 8, 26, 120)]);
  Assert.AreEqual(1, mPartners[0], 'Feld darunter');
end;

procedure TAtlasFormGridTests.EntriesKeepZipAndCity;
var
  mEntries: TArray<TAtlasGridEntry>;
begin
  mEntries := TAtlasFormGrid.Entries(Address);
  Assert.AreEqual(4, Integer(Length(mEntries)));
  Assert.AreEqual(4, mEntries[2].LabelIndex);
  Assert.AreEqual(2, Integer(Length(mEntries[2].Fields)), 'PLZ und Ort zusammen');
  Assert.AreEqual(6, mEntries[2].Fields[1]);
  Assert.AreEqual(7, mEntries[3].LabelIndex);
end;

procedure TAtlasFormGridTests.ScatteredPairsBecomeGrid;
var
  mResult: TAtlasGridResult;
begin
  mResult := TAtlasFormGrid.Arrange(Address, Options);
  // Labelspalte: breitestes Label 70 + 8 → Felder ab 8 + 78 = 86; Zeilen 23 + 8.
  Assert.AreEqual(86, mResult.Bounds[1].Left);
  Assert.AreEqual(86, mResult.Bounds[3].Left);
  Assert.AreEqual(86, mResult.Bounds[5].Left);
  Assert.AreEqual(144, mResult.Bounds[6].Left, 'Ort nach PLZ (86 + 50 + 8)');
  Assert.AreEqual(8, mResult.Bounds[1].Top);
  Assert.AreEqual(39, mResult.Bounds[3].Top);
  Assert.AreEqual(70, mResult.Bounds[5].Top);
  Assert.AreEqual(70, mResult.Bounds[6].Top, 'eine Zeile');
  Assert.AreEqual(101, mResult.Bounds[8].Top);
  Assert.AreEqual(8, mResult.Bounds[0].Left, 'Labels links bündig');
  Assert.AreEqual(8, mResult.Bounds[7].Left);
  Assert.AreEqual(8 + cFieldBaseline - cLabelAscent, mResult.Bounds[0].Top, 'Grundlinie');
  Assert.AreEqual(4, Integer(Length(mResult.TabOrder)) - 1, 'fünf Felder');
  Assert.AreEqual(1, mResult.TabOrder[0]);
  Assert.AreEqual(5, mResult.TabOrder[2]);
  Assert.AreEqual(6, mResult.TabOrder[3]);
  Assert.AreEqual(8, mResult.TabOrder[4]);
end;

procedure TAtlasFormGridTests.RightAligned;
var
  mResult: TAtlasGridResult;
begin
  mResult := TAtlasFormGrid.Arrange(Address, Options(TAtlasGridLabelAlign.Right));
  Assert.AreEqual(8 + 70 - 40, mResult.Bounds[0].Left, 'rechte Kante bei 78');
  Assert.AreEqual(78, mResult.Bounds[7].Right);
  Assert.AreEqual(86, mResult.Bounds[1].Left);
end;

procedure TAtlasFormGridTests.LabelsAbove;
var
  mResult: TAtlasGridResult;
begin
  mResult := TAtlasFormGrid.Arrange(Address, Options(TAtlasGridLabelAlign.Above));
  Assert.AreEqual(8, mResult.Bounds[0].Left);
  Assert.AreEqual(8, mResult.Bounds[0].Top);
  Assert.AreEqual(8, mResult.Bounds[1].Left, 'einspaltig');
  Assert.AreEqual(8 + 15 + TAtlasFormGrid.cAboveGap, mResult.Bounds[1].Top);
  Assert.AreEqual(8 + 15 + 3 + 23 + 8, mResult.Bounds[2].Top, 'nächstes Label nach der Zeile');
end;

procedure TAtlasFormGridTests.SingleControlAndMemo;
var
  mResult: TAtlasGridResult;
begin
  mResult := TAtlasFormGrid.Arrange([Lbl('lblName', 8, 12, 40), Fld('edtName', 60, 8, 150),
    Fld('chkAktiv', 70, 40, 100, 17), Lbl('lblNotiz', 8, 70, 40), Fld('memNotiz', 60, 66, 200, 80)], Options);
  Assert.AreEqual(56, mResult.Bounds[2].Left, 'Checkbox in der Feldspalte');
  Assert.AreEqual(39, mResult.Bounds[2].Top);
  Assert.AreEqual(64, mResult.Bounds[4].Top);
  Assert.AreEqual(64, mResult.Bounds[3].Top, 'Label am Memo oben bündig');
  Assert.AreEqual(3, Integer(Length(mResult.TabOrder)));
end;

procedure TAtlasFormGridTests.TwoPerRow;
var
  mOptions: TAtlasGridOptions;
  mResult: TAtlasGridResult;
begin
  mOptions := Options;
  mOptions.TwoPerRow := True;
  mResult := TAtlasFormGrid.Arrange(Address, mOptions);
  // Spalte: 78 Labels + 158 (PLZ 50 + 8 + Ort 100) = 236; zweite Spalte ab 8 + 236 + 16 = 260.
  Assert.AreEqual(8, mResult.Bounds[1].Top);
  Assert.AreEqual(8, mResult.Bounds[3].Top, 'Straße neben Name');
  Assert.AreEqual(260, mResult.Bounds[2].Left);
  Assert.AreEqual(338, mResult.Bounds[3].Left);
  Assert.AreEqual(39, mResult.Bounds[5].Top);
  Assert.AreEqual(39, mResult.Bounds[8].Top);
end;

procedure TAtlasFormGridTests.EqualWidth;
var
  mOptions: TAtlasGridOptions;
  mResult: TAtlasGridResult;
begin
  mOptions := Options;
  mOptions.EqualWidth := True;
  mResult := TAtlasFormGrid.Arrange(Address, mOptions);
  Assert.AreEqual(150, mResult.Bounds[1].Width);
  Assert.AreEqual(150, mResult.Bounds[8].Width, 'Telefon so breit wie Name');
  Assert.AreEqual(50, mResult.Bounds[5].Width, 'PLZ/Ort bleiben');
end;

end.
