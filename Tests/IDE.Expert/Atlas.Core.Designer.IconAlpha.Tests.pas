unit Atlas.Core.Designer.IconAlpha.Tests;

// Tests für die Transparenz der Palettensymbole aus zwei Malvorgängen (auf Schwarz und auf Weiß).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Designer')]
  TAtlasIconAlphaTests = class
  public
    [Test]
    procedure OpaquePixelKeepsColor;
    [Test]
    procedure BackgroundBecomesTransparent;
    [Test]
    procedure HalfTransparentEdgeKeepsTrueColor;
    [Test]
    procedure DifferentLengthsGiveEmpty;
  end;

implementation

uses
  Atlas.Core.Designer.IconAlpha;

function Pixel(ARed, AGreen, ABlue: Byte): Cardinal;
begin
  Result := Cardinal(ABlue) or (Cardinal(AGreen) shl 8) or (Cardinal(ARed) shl 16);
end;

procedure TAtlasIconAlphaTests.OpaquePixelKeepsColor;
var
  mResult: TArray<Cardinal>;
begin
  mResult := TAtlasIconAlpha.Combine(TArray<Cardinal>.Create(Pixel(30, 90, 200)),
    TArray<Cardinal>.Create(Pixel(30, 90, 200)));
  Assert.AreEqual(Integer(1), Integer(Length(mResult)));
  Assert.AreEqual(Cardinal($FF000000) or Pixel(30, 90, 200), mResult[0]);
end;

procedure TAtlasIconAlphaTests.BackgroundBecomesTransparent;
var
  mResult: TArray<Cardinal>;
begin
  mResult := TAtlasIconAlpha.Combine(TArray<Cardinal>.Create(Pixel(0, 0, 0)),
    TArray<Cardinal>.Create(Pixel(255, 255, 255)));
  Assert.AreEqual(Cardinal(0), mResult[0]);
end;

procedure TAtlasIconAlphaTests.HalfTransparentEdgeKeepsTrueColor;
var
  mResult: TArray<Cardinal>;
begin
  // Blau (0, 0, 200) zu 50 % deckend: auf Schwarz (0, 0, 100), auf Weiß (128, 128, 228).
  mResult := TAtlasIconAlpha.Combine(TArray<Cardinal>.Create(Pixel(0, 0, 100)),
    TArray<Cardinal>.Create(Pixel(128, 128, 228)));
  Assert.AreEqual(Integer(127), Integer(mResult[0] shr 24));
  Assert.AreEqual(Integer(0), Integer((mResult[0] shr 16) and $FF));
  Assert.AreEqual(Integer(0), Integer((mResult[0] shr 8) and $FF));
  Assert.AreEqual(Integer(201), Integer(mResult[0] and $FF));
end;

procedure TAtlasIconAlphaTests.DifferentLengthsGiveEmpty;
begin
  Assert.AreEqual(Integer(0), Integer(Length(TAtlasIconAlpha.Combine(TArray<Cardinal>.Create(0),
    TArray<Cardinal>.Create(0, 0)))));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasIconAlphaTests);

end.
