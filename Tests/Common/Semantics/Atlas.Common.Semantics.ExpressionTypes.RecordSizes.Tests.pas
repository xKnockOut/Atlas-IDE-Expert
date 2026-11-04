unit Atlas.Common.Semantics.ExpressionTypes.RecordSizes.Tests;

// Tests von TRecordSizes (#689): Ausrichtung wie {$A8}, packed, mehrere Namen je Feld, geschachtelte Records,
// Variantenteile und unbekannte Feldtypen ohne Größe, Tiefenschranke.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TRecordSizesTests = class
  public
    [Test]
    procedure AlignedFields;
    [Test]
    procedure PackedRecord;
    [Test]
    procedure NestedRecord;
    [Test]
    procedure NoSize;
    [Test]
    procedure DepthLimit;
    [Test]
    procedure LayoutPadding;
  end;

implementation

uses
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Semantics.ExpressionTypes.RecordSizes;

const
  cLineBreak = #13#10;
  cSource =
    'unit Haupt;' + cLineBreak +
    'interface' + cLineBreak +
    'type' + cLineBreak +
    '  TRec = record' + cLineBreak +
    '    A: Integer;' + cLineBreak +
    '    B: Byte;' + cLineBreak +
    '    C: Int64;' + cLineBreak +
    '  end;' + cLineBreak +
    '  TPacked = packed record' + cLineBreak +
    '    A: Byte;' + cLineBreak +
    '    B, C: Integer;' + cLineBreak +
    '  end;' + cLineBreak +
    '  TAussen = record' + cLineBreak +
    '    X: Byte;' + cLineBreak +
    '    Innen: TRec;' + cLineBreak +
    '  end;' + cLineBreak +
    '  TVariante = record' + cLineBreak +
    '    case Integer of' + cLineBreak +
    '      0: (A: Integer);' + cLineBreak +
    '  end;' + cLineBreak +
    '  TFremd = record' + cLineBreak +
    '    K: TKunde;' + cLineBreak +
    '  end;' + cLineBreak +
    'implementation' + cLineBreak +
    'end.';

function SizeOfRecord(const AName: string; ADepth: Integer; out ASize, AAlign: Integer): Boolean;
var
  mTree: TSyntaxTree;
  mSizes: TRecordSizes;
begin
  mTree := TPascalParser.Parse(cSource);
  try
    mSizes := TRecordSizes.Create(mTree, ADepth);
    try
      Result := mSizes.RecordSize(AName, ASize, AAlign);
    finally
      mSizes.Free;
    end;
  finally
    mTree.Free;
  end;
end;

procedure TRecordSizesTests.AlignedFields;
var
  mSize, mAlign: Integer;
begin
  Assert.IsTrue(SizeOfRecord('TRec', 0, mSize, mAlign));
  Assert.AreEqual(16, mSize);
  Assert.AreEqual(8, mAlign);
end;

procedure TRecordSizesTests.PackedRecord;
var
  mSize, mAlign: Integer;
begin
  Assert.IsTrue(SizeOfRecord('TPacked', 0, mSize, mAlign));
  Assert.AreEqual(9, mSize, 'B, C zählen zweimal');
  Assert.AreEqual(1, mAlign);
end;

procedure TRecordSizesTests.NestedRecord;
var
  mSize, mAlign: Integer;
begin
  Assert.IsTrue(SizeOfRecord('TAussen', 0, mSize, mAlign));
  Assert.AreEqual(24, mSize);
  Assert.AreEqual(8, mAlign);
end;

procedure TRecordSizesTests.NoSize;
var
  mSize, mAlign: Integer;
begin
  Assert.IsFalse(SizeOfRecord('TVariante', 0, mSize, mAlign), 'Variantenteil');
  Assert.IsFalse(SizeOfRecord('TFremd', 0, mSize, mAlign), 'unbekannter Feldtyp');
  Assert.IsFalse(SizeOfRecord('TFehlt', 0, mSize, mAlign), 'keine Deklaration');
  Assert.AreEqual(0, mSize);
end;

procedure TRecordSizesTests.DepthLimit;
var
  mSize, mAlign: Integer;
begin
  Assert.IsTrue(SizeOfRecord('TRec', 64, mSize, mAlign));
  Assert.IsFalse(SizeOfRecord('TRec', 65, mSize, mAlign), 'über der Tiefenschranke');
end;

procedure TRecordSizesTests.LayoutPadding;
var
  mLayout: TRecordLayout;
  mSize, mAlign: Integer;
begin
  mLayout := Default(TRecordLayout);
  mLayout.Align := 1;
  mLayout.Add(1, 1, 1);
  mLayout.Add(4, 4, 2);
  mLayout.Finish(mSize, mAlign);
  Assert.AreEqual(12, mSize);
  Assert.AreEqual(4, mAlign);
end;

end.
