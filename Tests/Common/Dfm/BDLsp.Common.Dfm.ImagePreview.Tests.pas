unit BDLsp.Common.Dfm.ImagePreview.Tests;

// Tests für die Bildvorschau im Hover über Binärdaten einer DFM (#271).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDfmImagePreviewTests = class
  public
    [Test]
    procedure DecodesHexAcrossLines;
    [Test]
    procedure EncodesBase64;
    [Test]
    procedure DetectsBitmapWithSizeField;
    [Test]
    procedure DetectsPngWithClassPrefix;
    [Test]
    procedure ConvertsBmpToPng;
    [Test]
    procedure HoverShowsImage;
    [Test]
    procedure LargeImageShowsOnlySize;
    [Test]
    procedure OtherPropertiesHaveNoPreview;
  end;

implementation

uses
  System.SysUtils,
  BDLsp.Common.Documents.Contract,
  BDLsp.Common.Dfm.ImagePreview;

const
  // TBitmap.Data: Längenfeld und BMP mit 2 × 2 Pixeln, 24 Bit.
  GlyphHex = '46000000424D460000000000000036000000280000000200000002000000010018000000000010000000000000000000' +
    '000000000000000000000000FF00FF000000FF0000FFFFFF0000';
  // TPicture.Data: #9'TPngImage' und PNG mit 1 × 1 Pixel.
  PictureHex = '0954506E67496D61676589504E470D0A1A0A0000000D4948445200000001000000010802000000907753DE0000000C' +
    '49444154789C63F8CFC0000003010100C9FE92EF0000000049454E44AE426082';
  // Nur Signatur und Kopf eines PNG mit 300 × 200 Pixeln.
  BigHex = '89504E470D0A1A0A0000000D494844520000012C000000C80802000000DDBD4B02';

function Form(const AHex: string): string;
begin
  Result := 'object Form1: TForm1'#10 +                     // 0
    '  Caption = ''Bild'''#10 +                             // 1
    '  object SpeedButton1: TSpeedButton'#10 +              // 2
    '    Glyph.Data = {'#10 +                               // 3
    '      ' + Copy(AHex, 1, 64) + #10 +                    // 4
    '      ' + Copy(AHex, 65, MaxInt) + '}'#10 +            // 5
    '  end'#10 +
    'end';
end;

procedure TDfmImagePreviewTests.DecodesHexAcrossLines;
var
  Data: TBytes;
begin
  Data := TDfmImagePreview.DecodeHex('{'#10'  0A ff'#13#10'  10}');
  Assert.AreEqual(3, Integer(Length(Data)));
  Assert.AreEqual(10, Integer(Data[0]));
  Assert.AreEqual(255, Integer(Data[1]));
  Assert.AreEqual(16, Integer(Data[2]));
end;

procedure TDfmImagePreviewTests.EncodesBase64;
begin
  Assert.AreEqual('TWFu', TDfmImagePreview.Base64(TEncoding.ASCII.GetBytes('Man')));
  Assert.AreEqual('TWE=', TDfmImagePreview.Base64(TEncoding.ASCII.GetBytes('Ma')));
  Assert.AreEqual('TQ==', TDfmImagePreview.Base64(TEncoding.ASCII.GetBytes('M')));
  Assert.AreEqual('', TDfmImagePreview.Base64(nil));
end;

procedure TDfmImagePreviewTests.DetectsBitmapWithSizeField;
var
  Image: TDfmImage;
begin
  Image := TDfmImagePreview.Detect(TDfmImagePreview.DecodeHex(GlyphHex));
  Assert.AreEqual(Ord(TDfmImageFormat.Bmp), Ord(Image.Format));
  Assert.AreEqual('', Image.ClassName);
  Assert.AreEqual(2, Image.Width);
  Assert.AreEqual(2, Image.Height);
  Assert.AreEqual(Ord('B'), Integer(Image.Data[0]));
end;

procedure TDfmImagePreviewTests.DetectsPngWithClassPrefix;
var
  Image: TDfmImage;
begin
  Image := TDfmImagePreview.Detect(TDfmImagePreview.DecodeHex(PictureHex));
  Assert.AreEqual(Ord(TDfmImageFormat.Png), Ord(Image.Format));
  Assert.AreEqual('TPngImage', Image.ClassName);
  Assert.AreEqual(1, Image.Width);
  Assert.AreEqual($89, Integer(Image.Data[0]));
end;

procedure TDfmImagePreviewTests.ConvertsBmpToPng;
var
  Png: TBytes;
  Image: TDfmImage;
begin
  Png := TDfmImagePreview.BmpToPng(TDfmImagePreview.Detect(TDfmImagePreview.DecodeHex(GlyphHex)).Data);
  Image := TDfmImagePreview.Detect(Png);
  Assert.AreEqual(Ord(TDfmImageFormat.Png), Ord(Image.Format));
  Assert.AreEqual(2, Image.Width);
  Assert.AreEqual(2, Image.Height);
  // Erste Zeile (oben) ist die letzte im BMP: Blau, dann Weiß als RGBA; Kopf 8 + IHDR 25 + IDAT-Kopf 8 + zlib 2 + Block 5 + Filter 1.
  Assert.AreEqual(0, Integer(Png[49]));
  Assert.AreEqual(255, Integer(Png[51]));
  Assert.IsNull(Pointer(TDfmImagePreview.BmpToPng(TEncoding.ASCII.GetBytes('kein Bild'))));
end;

procedure TDfmImagePreviewTests.HoverShowsImage;
var
  Markdown: string;
begin
  Markdown := TDfmImagePreview.HoverAt(Form(GlyphHex), TTextPosition.Create(4, 8));
  Assert.IsTrue(Markdown.StartsWith('**Glyph.Data**: BMP, 2 × 2'), Markdown);
  Assert.IsTrue(Pos('](data:image/png;base64,iVBORw0KGgo', Markdown) > 0, Markdown);
  Markdown := TDfmImagePreview.HoverAt(Form(PictureHex), TTextPosition.Create(3, 6));
  Assert.IsTrue(Pos('PNG, 1 × 1 (TPngImage)', Markdown) > 0, Markdown);
end;

procedure TDfmImagePreviewTests.LargeImageShowsOnlySize;
var
  Markdown: string;
begin
  Markdown := TDfmImagePreview.HoverAt(Form(BigHex), TTextPosition.Create(5, 8));
  Assert.IsTrue(Pos('300 × 200', Markdown) > 0, Markdown);
  Assert.AreEqual(0, Pos('data:', Markdown));
end;

procedure TDfmImagePreviewTests.OtherPropertiesHaveNoPreview;
begin
  Assert.AreEqual('', TDfmImagePreview.HoverAt(Form(GlyphHex), TTextPosition.Create(1, 4)));
  Assert.AreEqual('', TDfmImagePreview.HoverAt(Form('00112233445566778899'), TTextPosition.Create(4, 8)));
end;

initialization
  TDUnitX.RegisterTestFixture(TDfmImagePreviewTests);

end.
