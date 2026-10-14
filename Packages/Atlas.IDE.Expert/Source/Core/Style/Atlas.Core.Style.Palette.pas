unit Atlas.Core.Style.Palette;

// Farbrollen von Atlas (#411, #421) nach dem Entwurf "Atlas-Oberfläche":
// fester Akzent in griechischem Blau, alles andere je nach Hell- oder
// Dunkelmodus. Auswahl und Flächen ergeben sich wie im Entwurf durch Mischen
// des Akzents mit dem Hintergrund. Die Oberfläche verwendet nur diese Rollen,
// keine fest verdrahteten Farben.

interface

uses
  Atlas.Core.Style.Color;

type
  /// <summary>Art eines Badges in der Liste (#421); bestimmt dessen Farben.</summary>
  TAtlasBadgeKind = (Function_, Procedure_, Property_, Field, Event, Constant, Type_, Variable, Unit_, Snippet,
    Keyword, XmlDoc);

  TAtlasBadgeColors = record
    Background: TAtlasColor;
    Text: TAtlasColor;
  end;

  TAtlasColors = record
    IsDark: Boolean;
    /// <summary>Fläche der Fenster.</summary>
    Surface: TAtlasColor;
    /// <summary>Abgesetzte Fläche: Fußzeile, Detailpanel, Doku-Zeile im Hint.</summary>
    Gutter: TAtlasColor;
    Text: TAtlasColor;
    /// <summary>Gedämpfter Text: Signaturen, Units, Beschreibungen.</summary>
    Muted: TAtlasColor;
    /// <summary>Trennlinien, Ränder der Tags, Scrollleiste.</summary>
    Line: TAtlasColor;
    /// <summary>Rahmen der Fenster, getroffene Zeichen, aktiver Parameter.</summary>
    Accent: TAtlasColor;
    AccentSoft: TAtlasColor;
    /// <summary>Gewählte Zeile: Akzent zu 12 % (hell) bzw. 15 % (dunkel) über Surface.</summary>
    Selection: TAtlasColor;
    Keyword: TAtlasColor;
    StringLiteral: TAtlasColor;
    Comment: TAtlasColor;
    Add: TAtlasColor;
    AddSoft: TAtlasColor;
    Warn: TAtlasColor;
    WarnSoft: TAtlasColor;
    Error: TAtlasColor;
    ErrorSoft: TAtlasColor;
    Badges: array[TAtlasBadgeKind] of TAtlasBadgeColors;
    /// <summary>Klammer- und Blockpaare je Tiefe, zyklisch (#514).</summary>
    Pairs: array[0..4] of TAtlasColor;
    class function Light: TAtlasColors; static;
    class function Dark: TAtlasColors; static;
    /// <summary>Light oder Dark, je nachdem ob ABackground (Fensterfarbe der IDE) dunkel ist.</summary>
    class function ForBackground(ABackground: TAtlasColor): TAtlasColors; static;
  end;

implementation

function Hex(const AHex: string): TAtlasColor;
begin
  Result := TAtlasColorMath.FromHex(AHex);
end;

function Badge(const ABackground, AText: string): TAtlasBadgeColors;
begin
  Result.Background := Hex(ABackground);
  Result.Text := Hex(AText);
end;

{ TAtlasColors }

class function TAtlasColors.Light: TAtlasColors;
begin
  Result := Default(TAtlasColors);
  Result.IsDark := False;
  Result.Surface := Hex('#FFFFFF');
  Result.Gutter := Hex('#F3F5F8');
  Result.Text := Hex('#1B2230');
  Result.Muted := Hex('#586274');
  Result.Line := Hex('#DCE2EA');
  Result.Accent := Hex('#0D5EAF');
  Result.AccentSoft := Hex('#E3EEF9');
  Result.Selection := TAtlasColorMath.Mix(Result.Accent, Result.Surface, 0.12);
  Result.Keyword := Hex('#0D5EAF');
  Result.StringLiteral := Hex('#8A4A0B');
  Result.Comment := Hex('#6A7384');
  Result.Add := Hex('#1E6B3A');
  Result.AddSoft := Hex('#E3F3E8');
  Result.Warn := Hex('#9A5B00');
  Result.WarnSoft := Hex('#FDF1DC');
  Result.Error := Hex('#B42318');
  Result.ErrorSoft := Hex('#FDE8E6');
  Result.Badges[TAtlasBadgeKind.Function_] := Badge('#E3EEF9', '#0D4C8C');
  Result.Badges[TAtlasBadgeKind.Procedure_] := Badge('#E6F0EC', '#24634B');
  Result.Badges[TAtlasBadgeKind.Property_] := Badge('#FCEBDD', '#9A3412');
  Result.Badges[TAtlasBadgeKind.Field] := Badge('#E7F1F3', '#245A66');
  Result.Badges[TAtlasBadgeKind.Event] := Badge('#F1E8FA', '#6B2FA0');
  Result.Badges[TAtlasBadgeKind.Constant] := Badge('#FBF3D6', '#7A5A00');
  Result.Badges[TAtlasBadgeKind.Type_] := Badge('#CCDDF2', '#0A3F75');
  Result.Badges[TAtlasBadgeKind.Variable] := Badge('#E7F1F3', '#245A66');
  Result.Badges[TAtlasBadgeKind.Unit_] := Badge('#ECEFF3', '#3E4756');
  Result.Badges[TAtlasBadgeKind.Snippet] := Badge('#ECEFF3', '#3E4756');
  Result.Badges[TAtlasBadgeKind.Keyword] := Badge('#ECEFF3', '#3E4756');
  Result.Badges[TAtlasBadgeKind.XmlDoc] := Badge('#ECEFF3', '#3E4756');
  // Kräftig und gesättigt (#653): vom schwarzen bzw. dunkelblauen Text der Schlüsselwörter klar
  // verschieden (ΔE2000 ≥ 30), untereinander ≥ 30, gegen Weiß ≥ 4,5 : 1. Tiefe 0 nicht blau, weil
  // die IDE Schlüsselwörter im hellen Schema dunkelblau zeichnet; kein Rot neben der Fehlerfarbe.
  Result.Pairs[0] := Hex('#C000E0');
  Result.Pairs[1] := Hex('#008700');
  Result.Pairs[2] := Hex('#0071E3');
  Result.Pairs[3] := Hex('#9E6900');
  Result.Pairs[4] := Hex('#007C8A');
end;

class function TAtlasColors.Dark: TAtlasColors;
begin
  Result := Default(TAtlasColors);
  Result.IsDark := True;
  Result.Surface := Hex('#1A1E25');
  Result.Gutter := Hex('#15181D');
  Result.Text := Hex('#E3E7ED');
  Result.Muted := Hex('#9AA3B2');
  Result.Line := Hex('#2B313B');
  Result.Accent := Hex('#5B9BE6');
  Result.AccentSoft := Hex('#1B2D45');
  // 15 % statt 18 % wie im Entwurf: sonst hat der Akzent darauf weniger als 4,5 : 1.
  Result.Selection := TAtlasColorMath.Mix(Result.Accent, Result.Surface, 0.15);
  Result.Keyword := Hex('#7FB0EE');
  Result.StringLiteral := Hex('#E3B27A');
  Result.Comment := Hex('#8A93A3');
  Result.Add := Hex('#7FD39A');
  Result.AddSoft := Hex('#1D3325');
  Result.Warn := Hex('#F0C06A');
  Result.WarnSoft := Hex('#3A2E17');
  Result.Error := Hex('#F59A8F');
  Result.ErrorSoft := Hex('#3E201E');
  Result.Badges[TAtlasBadgeKind.Function_] := Badge('#1B2D45', '#9CC3F2');
  Result.Badges[TAtlasBadgeKind.Procedure_] := Badge('#1C3329', '#86D0AE');
  Result.Badges[TAtlasBadgeKind.Property_] := Badge('#43301F', '#F5B783');
  Result.Badges[TAtlasBadgeKind.Field] := Badge('#1F3338', '#8FCAD6');
  Result.Badges[TAtlasBadgeKind.Event] := Badge('#36264A', '#CBA6F2');
  Result.Badges[TAtlasBadgeKind.Constant] := Badge('#3B3218', '#E8C96A');
  Result.Badges[TAtlasBadgeKind.Type_] := Badge('#2A4670', '#B8D5F7');
  Result.Badges[TAtlasBadgeKind.Variable] := Badge('#1F3338', '#8FCAD6');
  Result.Badges[TAtlasBadgeKind.Unit_] := Badge('#272D36', '#B9C1CC');
  Result.Badges[TAtlasBadgeKind.Snippet] := Badge('#272D36', '#B9C1CC');
  Result.Badges[TAtlasBadgeKind.Keyword] := Badge('#272D36', '#B9C1CC');
  Result.Badges[TAtlasBadgeKind.XmlDoc] := Badge('#272D36', '#B9C1CC');
  // #653: Die bisherigen Pastelltöne lagen zu nah am hellen Text (Kontrast unter 1,8 : 1 und
  // ΔE2000 unter 30); dieselben Farbtöne wie hell, gesättigt und mittelhell.
  Result.Pairs[0] := Hex('#E250FF');
  Result.Pairs[1] := Hex('#24AA24');
  Result.Pairs[2] := Hex('#3C94FF');
  Result.Pairs[3] := Hex('#D47F00');
  Result.Pairs[4] := Hex('#00A4A4');
end;

class function TAtlasColors.ForBackground(ABackground: TAtlasColor): TAtlasColors;
begin
  if TAtlasColorMath.IsDark(ABackground) then
    Result := Dark
  else
    Result := Light;
end;

end.
