unit Atlas.Text.Encoding.Tests;

interface

uses
  System.SysUtils,
  DUnitX.TestFramework;

type
  [TestFixture]
  TTextEncodingProbeTests = class
  public
    [Test]
    procedure Utf8RejectsOverlong2Byte;
    [Test]
    procedure Utf8RejectsOverlong3Byte;
    [Test]
    procedure Utf8RejectsSurrogate;
    [Test]
    procedure Utf8RejectsAbove10FFFF;
    [Test]
    procedure Utf8RejectsTruncatedSequence;
    [Test]
    procedure Utf8AcceptsValid4Byte;
    [Test]
    procedure Utf8ReportsNonAscii;
    [Test]
    procedure BomDetection;
    [Test]
    procedure ParseCodePageVariants;
    [Test]
    procedure BinaryFormWithResourceHeader;
    [Test]
    procedure Cp1252RoundTrip;
    [Test]
    procedure AsciiOnly;
  end;

implementation

uses
  Atlas.Text.Encoding;

procedure TTextEncodingProbeTests.Utf8RejectsOverlong2Byte;
begin
  Assert.IsFalse(TTextEncodingProbe.IsValidUtf8(TBytes.Create($C0, $AF), 0));
end;

procedure TTextEncodingProbeTests.Utf8RejectsOverlong3Byte;
begin
  Assert.IsFalse(TTextEncodingProbe.IsValidUtf8(TBytes.Create($E0, $80, $80), 0));
end;

procedure TTextEncodingProbeTests.Utf8RejectsSurrogate;
begin
  Assert.IsFalse(TTextEncodingProbe.IsValidUtf8(TBytes.Create($ED, $A0, $80), 0));
end;

procedure TTextEncodingProbeTests.Utf8RejectsAbove10FFFF;
begin
  Assert.IsFalse(TTextEncodingProbe.IsValidUtf8(TBytes.Create($F4, $90, $80, $80), 0));
end;

procedure TTextEncodingProbeTests.Utf8RejectsTruncatedSequence;
begin
  Assert.IsFalse(TTextEncodingProbe.IsValidUtf8(TBytes.Create(Ord('a'), $C3), 0));
end;

procedure TTextEncodingProbeTests.Utf8AcceptsValid4Byte;
begin
  // U+1F600 und U+10FFFF
  Assert.IsTrue(TTextEncodingProbe.IsValidUtf8(TBytes.Create($F0, $9F, $98, $80), 0));
  Assert.IsTrue(TTextEncodingProbe.IsValidUtf8(TBytes.Create($F4, $8F, $BF, $BF), 0));
  // Ab AStart: die ungültige BOM-Hälfte davor zählt nicht.
  Assert.IsTrue(TTextEncodingProbe.IsValidUtf8(TBytes.Create($FF, Ord('a')), 1));
end;

procedure TTextEncodingProbeTests.Utf8ReportsNonAscii;
var
  HasNonAscii: Boolean;
begin
  Assert.IsTrue(TTextEncodingProbe.IsValidUtf8(TBytes.Create(Ord('a'), Ord('b')), 0, HasNonAscii));
  Assert.IsFalse(HasNonAscii);
  Assert.IsTrue(TTextEncodingProbe.IsValidUtf8(TBytes.Create($C3, $A4), 0, HasNonAscii));
  Assert.IsTrue(HasNonAscii);
end;

procedure TTextEncodingProbeTests.BomDetection;
begin
  Assert.IsTrue(TTextEncodingProbe.BomOf(TBytes.Create($EF, $BB, $BF, Ord('a'))) = TTextBom.Utf8);
  Assert.IsTrue(TTextEncodingProbe.BomOf(TBytes.Create($FF, $FE)) = TTextBom.Utf16LE);
  Assert.IsTrue(TTextEncodingProbe.BomOf(TBytes.Create($FE, $FF)) = TTextBom.Utf16BE);
  Assert.IsTrue(TTextEncodingProbe.BomOf(TBytes.Create($EF, $BB)) = TTextBom.None);
  Assert.IsTrue(TTextEncodingProbe.BomOf(nil) = TTextBom.None);
  Assert.AreEqual<Integer>(3, TTextEncodingProbe.BomLength(TTextBom.Utf8));
  Assert.AreEqual<Integer>(2, TTextEncodingProbe.BomLength(TTextBom.Utf16BE));
  Assert.AreEqual<Integer>(0, TTextEncodingProbe.BomLength(TTextBom.None));
end;

procedure TTextEncodingProbeTests.ParseCodePageVariants;
var
  CodePage: Integer;
begin
  Assert.IsTrue(TTextEncodingProbe.ParseCodePage(' UTF-8 ', CodePage));
  Assert.AreEqual<Integer>(65001, CodePage);
  Assert.IsTrue(TTextEncodingProbe.ParseCodePage('utf8', CodePage));
  Assert.AreEqual<Integer>(65001, CodePage);
  Assert.IsTrue(TTextEncodingProbe.ParseCodePage('65001', CodePage));
  Assert.IsTrue(TTextEncodingProbe.ParseCodePage('windows-1250', CodePage));
  Assert.AreEqual<Integer>(1250, CodePage);
  Assert.IsTrue(TTextEncodingProbe.ParseCodePage('CP1251', CodePage));
  Assert.AreEqual<Integer>(1251, CodePage);
  Assert.IsTrue(TTextEncodingProbe.ParseCodePage('1252', CodePage));
  Assert.IsFalse(TTextEncodingProbe.ParseCodePage('932', CodePage));
  Assert.AreEqual<Integer>(0, CodePage);
  Assert.IsFalse(TTextEncodingProbe.ParseCodePage('latin', CodePage));
  Assert.AreEqual<Integer>(0, CodePage);
end;

procedure TTextEncodingProbeTests.BinaryFormWithResourceHeader;
begin
  Assert.IsTrue(TTextEncodingProbe.IsBinaryForm(TBytes.Create(Ord('T'), Ord('P'), Ord('F'), Ord('0'), 1)));
  Assert.IsTrue(TTextEncodingProbe.IsBinaryForm(TBytes.Create($FF, $0A, $00, 1)));
  Assert.IsFalse(TTextEncodingProbe.IsBinaryForm(TEncoding.ASCII.GetBytes('object Form1: TForm1')));
  Assert.IsFalse(TTextEncodingProbe.IsBinaryForm(nil));
end;

procedure TTextEncodingProbeTests.Cp1252RoundTrip;
var
  Bytes: TBytes;
  Text: string;
begin
  Bytes := TBytes.Create($80, $E4, $9F, Ord('x'));
  Text := TTextEncodingProbe.DecodeCp1252(Bytes, 0);
  Assert.AreEqual(#$20AC#$00E4#$0178'x', Text);
  Assert.AreEqual<Integer>(4, Length(TTextEncodingProbe.EncodeCp1252(Text)));
  Assert.AreEqual<Byte>($80, TTextEncodingProbe.EncodeCp1252(Text)[0]);
  Assert.AreEqual<Byte>($9F, TTextEncodingProbe.EncodeCp1252(Text)[2]);
  Assert.AreEqual<Byte>(Ord('?'), TTextEncodingProbe.EncodeCp1252(#$0416)[0]);
  Assert.AreEqual('x', TTextEncodingProbe.DecodeCp1252(Bytes, 3));
  Assert.AreEqual('', TTextEncodingProbe.DecodeCp1252(Bytes, 4));
end;

procedure TTextEncodingProbeTests.AsciiOnly;
begin
  Assert.IsTrue(TTextEncodingProbe.IsAscii(TEncoding.ASCII.GetBytes('abc')));
  Assert.IsTrue(TTextEncodingProbe.IsAscii(nil));
  Assert.IsFalse(TTextEncodingProbe.IsAscii(TBytes.Create(Ord('a'), $C3, $A4)));
end;

initialization
  TDUnitX.RegisterTestFixture(TTextEncodingProbeTests);

end.
