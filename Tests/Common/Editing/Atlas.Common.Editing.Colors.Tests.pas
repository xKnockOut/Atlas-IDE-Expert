unit Atlas.Common.Editing.Colors.Tests;

// Tests für Farbvorschau und Farbwähler (#26).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TSourceColorsTests = class
  public
    [Test]
    procedure FindsHexInBgrOrder;
    [Test]
    procedure IgnoresShortHexAndMasks;
    [Test]
    procedure FindsRgbCall;
    [Test]
    procedure IgnoresIncompleteRgbCall;
    [Test]
    procedure FindsNamedColorsCaseInsensitive;
    [Test]
    procedure SystemColorUsesProviderOrDefault;
    [Test]
    procedure PresentationKeepsHexFormat;
    [Test]
    procedure PresentationKeepsRgbFormat;
    [Test]
    procedure PresentationKeepsNameWhenItMatches;
    [Test]
    procedure SystemColorBecomesHex;
    [Test]
    procedure LspColorRoundTrip;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Editing.Colors,
  Atlas.Common.Lsp.Colors;

function Rgb(AR, AG, AB: Byte): TRgbColor;
begin
  Result := TRgbColor.Create(AR, AG, AB);
end;

// "R,G,B" für Assert.AreEqual: Records vergleicht AreEqual binär, die Meldung zeigte nur "(record)".
function RgbText(const AColor: TRgbColor): string;
begin
  Result := Format('%d,%d,%d', [AColor.R, AColor.G, AColor.B]);
end;

function GreenForBtnFace(AIndex: Integer; out AColor: TRgbColor): Boolean;
begin
  Result := AIndex = 15;
  if Result then
  begin
    AColor := Rgb(0, 255, 0);
  end;
end;

{ TSourceColorsTests }

procedure TSourceColorsTests.FindsHexInBgrOrder;
var
  mFound: TArray<TColorMatch>;
begin
  mFound := TSourceColors.Find('Color := $00FF8000;');
  Assert.AreEqual<NativeInt>(1, Length(mFound));
  Assert.AreEqual('0,128,255', RgbText(mFound[0].Color));
  Assert.AreEqual(Ord(TColorFormat.Hex), Ord(mFound[0].Format));
  Assert.AreEqual(9, mFound[0].Range.StartPos.Character);
  Assert.AreEqual(18, mFound[0].Range.EndPos.Character);
  Assert.AreEqual('$00FF8000', mFound[0].Text);
end;

procedure TSourceColorsTests.IgnoresShortHexAndMasks;
begin
  Assert.AreEqual<NativeInt>(0, Length(TSourceColors.Find('X := $FF8000 or $FFFFFFFF or $10FF8000 or 255;')));
end;

procedure TSourceColorsTests.FindsRgbCall;
var
  mFound: TArray<TColorMatch>;
begin
  mFound := TSourceColors.Find('C := RGB(255, { rot } 128, 0);');
  Assert.AreEqual<NativeInt>(1, Length(mFound));
  Assert.AreEqual('255,128,0', RgbText(mFound[0].Color));
  Assert.AreEqual(Ord(TColorFormat.Rgb), Ord(mFound[0].Format));
  Assert.AreEqual(5, mFound[0].Range.StartPos.Character);
  Assert.AreEqual(29, mFound[0].Range.EndPos.Character);
  Assert.AreEqual('RGB(255, { rot } 128, 0)', mFound[0].Text);
end;

procedure TSourceColorsTests.IgnoresIncompleteRgbCall;
begin
  Assert.AreEqual<NativeInt>(0, Length(TSourceColors.Find('C := RGB(R, G, B); D := RGB(300, 0, 0); E := RGB(1, 2')));
end;

procedure TSourceColorsTests.FindsNamedColorsCaseInsensitive;
var
  mFound: TArray<TColorMatch>;
begin
  mFound := TSourceColors.Find('A := clRed; B := CLNAVY; C := clUnbekannt;');
  Assert.AreEqual<NativeInt>(2, Length(mFound));
  Assert.AreEqual('255,0,0', RgbText(mFound[0].Color));
  Assert.AreEqual('0,0,128', RgbText(mFound[1].Color));
  Assert.AreEqual(Ord(TColorFormat.Named), Ord(mFound[1].Format));
end;

procedure TSourceColorsTests.SystemColorUsesProviderOrDefault;
var
  mFound: TArray<TColorMatch>;
begin
  mFound := TSourceColors.Find('A := clBtnFace; B := clWindow;', GreenForBtnFace);
  Assert.AreEqual<NativeInt>(2, Length(mFound));
  Assert.AreEqual(Ord(TColorFormat.SystemColor), Ord(mFound[0].Format));
  Assert.AreEqual('0,255,0', RgbText(mFound[0].Color));
  // Ohne Wert vom Provider: Standardwert von Windows 10.
  Assert.AreEqual('255,255,255', RgbText(mFound[1].Color));
end;

procedure TSourceColorsTests.PresentationKeepsHexFormat;
var
  mPresentations: TArray<TColorPresentation>;
begin
  mPresentations := TSourceColors.Presentations(Rgb($12, $34, $56), TColorFormat.Hex);
  Assert.AreEqual<NativeInt>(2, Length(mPresentations));
  Assert.AreEqual('$00563412', mPresentations[0].Text);
  Assert.AreEqual('RGB(18, 52, 86)', mPresentations[1].Text);
end;

procedure TSourceColorsTests.PresentationKeepsRgbFormat;
begin
  Assert.AreEqual('RGB(1, 2, 3)', TSourceColors.Presentations(Rgb(1, 2, 3), TColorFormat.Rgb)[0].Text);
end;

procedure TSourceColorsTests.PresentationKeepsNameWhenItMatches;
var
  mPresentations: TArray<TColorPresentation>;
begin
  mPresentations := TSourceColors.Presentations(Rgb(255, 0, 0), TColorFormat.Named);
  Assert.AreEqual('clRed', mPresentations[0].Text);
  Assert.AreEqual('$000000FF', mPresentations[1].Text);
  // Kein Name für diese Farbe: Hex zuerst.
  Assert.AreEqual('$00030201', TSourceColors.Presentations(Rgb(1, 2, 3), TColorFormat.Named)[0].Text);
  // Hex mit passendem Namen bietet den Namen zusätzlich an.
  Assert.AreEqual('clRed', TSourceColors.Presentations(Rgb(255, 0, 0), TColorFormat.Hex)[2].Text);
end;

procedure TSourceColorsTests.SystemColorBecomesHex;
begin
  Assert.AreEqual('$00F0F0F0', TSourceColors.Presentations(Rgb($F0, $F0, $F0), TColorFormat.SystemColor)[0].Text);
end;

procedure TSourceColorsTests.LspColorRoundTrip;
var
  mJson: TJSONObject;
  mColor: TRgbColor;
begin
  mJson := TLspColors.ColorToJson(Rgb(255, 128, 0));
  try
    Assert.IsTrue(TLspColors.TryReadColor(mJson, mColor));
    Assert.AreEqual('255,128,0', RgbText(mColor));
  finally
    mJson.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TSourceColorsTests);

end.
