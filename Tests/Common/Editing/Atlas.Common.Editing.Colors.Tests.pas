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
  Atlas.Common.Editing.Colors,
  Atlas.Common.Lsp.Colors;

function Rgb(R, G, B: Byte): TRgbColor;
begin
  Result := TRgbColor.Create(R, G, B);
end;

function GreenForBtnFace(AIndex: Integer; out AColor: TRgbColor): Boolean;
begin
  Result := AIndex = 15;
  if Result then
    AColor := Rgb(0, 255, 0);
end;

{ TSourceColorsTests }

procedure TSourceColorsTests.FindsHexInBgrOrder;
var
  Found: TArray<TColorMatch>;
begin
  Found := TSourceColors.Find('Color := $00FF8000;');
  Assert.AreEqual<NativeInt>(1, Length(Found));
  Assert.IsTrue(Found[0].Color = Rgb($00, $80, $FF));
  Assert.AreEqual(Ord(TColorFormat.Hex), Ord(Found[0].Format));
  Assert.AreEqual(9, Found[0].Range.StartPos.Character);
  Assert.AreEqual(18, Found[0].Range.EndPos.Character);
  Assert.AreEqual('$00FF8000', Found[0].Text);
end;

procedure TSourceColorsTests.IgnoresShortHexAndMasks;
begin
  Assert.AreEqual<NativeInt>(0, Length(TSourceColors.Find('X := $FF8000 or $FFFFFFFF or $10FF8000 or 255;')));
end;

procedure TSourceColorsTests.FindsRgbCall;
var
  Found: TArray<TColorMatch>;
begin
  Found := TSourceColors.Find('C := RGB(255, { rot } 128, 0);');
  Assert.AreEqual<NativeInt>(1, Length(Found));
  Assert.IsTrue(Found[0].Color = Rgb(255, 128, 0));
  Assert.AreEqual(Ord(TColorFormat.Rgb), Ord(Found[0].Format));
  Assert.AreEqual(5, Found[0].Range.StartPos.Character);
  Assert.AreEqual(29, Found[0].Range.EndPos.Character);
  Assert.AreEqual('RGB(255, { rot } 128, 0)', Found[0].Text);
end;

procedure TSourceColorsTests.IgnoresIncompleteRgbCall;
begin
  Assert.AreEqual<NativeInt>(0, Length(TSourceColors.Find('C := RGB(R, G, B); D := RGB(300, 0, 0); E := RGB(1, 2')));
end;

procedure TSourceColorsTests.FindsNamedColorsCaseInsensitive;
var
  Found: TArray<TColorMatch>;
begin
  Found := TSourceColors.Find('A := clRed; B := CLNAVY; C := clUnbekannt;');
  Assert.AreEqual<NativeInt>(2, Length(Found));
  Assert.IsTrue(Found[0].Color = Rgb(255, 0, 0));
  Assert.IsTrue(Found[1].Color = Rgb(0, 0, 128));
  Assert.AreEqual(Ord(TColorFormat.Named), Ord(Found[1].Format));
end;

procedure TSourceColorsTests.SystemColorUsesProviderOrDefault;
var
  Found: TArray<TColorMatch>;
begin
  Found := TSourceColors.Find('A := clBtnFace; B := clWindow;', GreenForBtnFace);
  Assert.AreEqual<NativeInt>(2, Length(Found));
  Assert.AreEqual(Ord(TColorFormat.SystemColor), Ord(Found[0].Format));
  Assert.IsTrue(Found[0].Color = Rgb(0, 255, 0));
  // Ohne Wert vom Provider: Standardwert von Windows 10.
  Assert.IsTrue(Found[1].Color = Rgb(255, 255, 255));
end;

procedure TSourceColorsTests.PresentationKeepsHexFormat;
var
  Presentations: TArray<TColorPresentation>;
begin
  Presentations := TSourceColors.Presentations(Rgb($12, $34, $56), TColorFormat.Hex);
  Assert.AreEqual<NativeInt>(2, Length(Presentations));
  Assert.AreEqual('$00563412', Presentations[0].Text);
  Assert.AreEqual('RGB(18, 52, 86)', Presentations[1].Text);
end;

procedure TSourceColorsTests.PresentationKeepsRgbFormat;
begin
  Assert.AreEqual('RGB(1, 2, 3)', TSourceColors.Presentations(Rgb(1, 2, 3), TColorFormat.Rgb)[0].Text);
end;

procedure TSourceColorsTests.PresentationKeepsNameWhenItMatches;
var
  Presentations: TArray<TColorPresentation>;
begin
  Presentations := TSourceColors.Presentations(Rgb(255, 0, 0), TColorFormat.Named);
  Assert.AreEqual('clRed', Presentations[0].Text);
  Assert.AreEqual('$000000FF', Presentations[1].Text);
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
  Json: TJSONObject;
  Color: TRgbColor;
begin
  Json := TLspColors.ColorToJson(Rgb(255, 128, 0));
  try
    Assert.IsTrue(TLspColors.TryReadColor(Json, Color));
    Assert.IsTrue(Color = Rgb(255, 128, 0));
  finally
    Json.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TSourceColorsTests);

end.
