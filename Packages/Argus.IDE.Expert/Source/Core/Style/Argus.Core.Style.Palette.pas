unit Argus.Core.Style.Palette;

// Farbrollen von Argus (#411, #421) nach dem Entwurf "Argus-Oberfläche":
// fester Akzent in griechischem Blau, alles andere je nach Hell- oder
// Dunkelmodus. Auswahl und Flächen ergeben sich wie im Entwurf durch Mischen
// des Akzents mit dem Hintergrund. Die Oberfläche verwendet nur diese Rollen,
// keine fest verdrahteten Farben.

interface

uses
  Argus.Core.Style.Color;

type
  /// <summary>Art eines Badges in der Liste (#421); bestimmt dessen Farben.</summary>
  TArgusBadgeKind = (Function_, Procedure_, Property_, Field, Event, Constant, Type_, Variable, Unit_, Snippet,
    Keyword, XmlDoc);

  TArgusBadgeColors = record
    Background: TArgusColor;
    Text: TArgusColor;
  end;

  TArgusColors = record
    IsDark: Boolean;
    /// <summary>Fläche der Fenster.</summary>
    Surface: TArgusColor;
    /// <summary>Abgesetzte Fläche: Fußzeile, Detailpanel, Doku-Zeile im Hint.</summary>
    Gutter: TArgusColor;
    Text: TArgusColor;
    /// <summary>Gedämpfter Text: Signaturen, Units, Beschreibungen.</summary>
    Muted: TArgusColor;
    /// <summary>Trennlinien, Ränder der Tags, Scrollleiste.</summary>
    Line: TArgusColor;
    /// <summary>Rahmen der Fenster, getroffene Zeichen, aktiver Parameter.</summary>
    Accent: TArgusColor;
    AccentSoft: TArgusColor;
    /// <summary>Gewählte Zeile: Akzent zu 12 % (hell) bzw. 15 % (dunkel) über Surface.</summary>
    Selection: TArgusColor;
    Keyword: TArgusColor;
    StringLiteral: TArgusColor;
    Comment: TArgusColor;
    Add: TArgusColor;
    AddSoft: TArgusColor;
    Warn: TArgusColor;
    WarnSoft: TArgusColor;
    Error: TArgusColor;
    ErrorSoft: TArgusColor;
    Badges: array[TArgusBadgeKind] of TArgusBadgeColors;
    /// <summary>Klammer- und Blockpaare je Tiefe, zyklisch (#514).</summary>
    Pairs: array[0..4] of TArgusColor;
    class function Light: TArgusColors; static;
    class function Dark: TArgusColors; static;
    /// <summary>Light oder Dark, je nachdem ob ABackground (Fensterfarbe der IDE) dunkel ist.</summary>
    class function ForBackground(ABackground: TArgusColor): TArgusColors; static;
  end;

implementation

function Hex(const AHex: string): TArgusColor;
begin
  Result := TArgusColorMath.FromHex(AHex);
end;

function Badge(const ABackground, AText: string): TArgusBadgeColors;
begin
  Result.Background := Hex(ABackground);
  Result.Text := Hex(AText);
end;

{ TArgusColors }

class function TArgusColors.Light: TArgusColors;
begin
  Result := Default(TArgusColors);
  Result.IsDark := False;
  Result.Surface := Hex('#FFFFFF');
  Result.Gutter := Hex('#F3F5F8');
  Result.Text := Hex('#1B2230');
  Result.Muted := Hex('#586274');
  Result.Line := Hex('#DCE2EA');
  Result.Accent := Hex('#0D5EAF');
  Result.AccentSoft := Hex('#E3EEF9');
  Result.Selection := TArgusColorMath.Mix(Result.Accent, Result.Surface, 0.12);
  Result.Keyword := Hex('#0D5EAF');
  Result.StringLiteral := Hex('#8A4A0B');
  Result.Comment := Hex('#6A7384');
  Result.Add := Hex('#1E6B3A');
  Result.AddSoft := Hex('#E3F3E8');
  Result.Warn := Hex('#9A5B00');
  Result.WarnSoft := Hex('#FDF1DC');
  Result.Error := Hex('#B42318');
  Result.ErrorSoft := Hex('#FDE8E6');
  Result.Badges[TArgusBadgeKind.Function_] := Badge('#E3EEF9', '#0D4C8C');
  Result.Badges[TArgusBadgeKind.Procedure_] := Badge('#E6F0EC', '#24634B');
  Result.Badges[TArgusBadgeKind.Property_] := Badge('#FCEBDD', '#9A3412');
  Result.Badges[TArgusBadgeKind.Field] := Badge('#E7F1F3', '#245A66');
  Result.Badges[TArgusBadgeKind.Event] := Badge('#F1E8FA', '#6B2FA0');
  Result.Badges[TArgusBadgeKind.Constant] := Badge('#FBF3D6', '#7A5A00');
  Result.Badges[TArgusBadgeKind.Type_] := Badge('#CCDDF2', '#0A3F75');
  Result.Badges[TArgusBadgeKind.Variable] := Badge('#E7F1F3', '#245A66');
  Result.Badges[TArgusBadgeKind.Unit_] := Badge('#ECEFF3', '#3E4756');
  Result.Badges[TArgusBadgeKind.Snippet] := Badge('#ECEFF3', '#3E4756');
  Result.Badges[TArgusBadgeKind.Keyword] := Badge('#ECEFF3', '#3E4756');
  Result.Badges[TArgusBadgeKind.XmlDoc] := Badge('#ECEFF3', '#3E4756');
  Result.Pairs[0] := Hex('#0D5EAF');
  Result.Pairs[1] := Hex('#7B3FB0');
  Result.Pairs[2] := Hex('#9A5B00');
  Result.Pairs[3] := Hex('#1E6B3A');
  Result.Pairs[4] := Hex('#B0306A');
end;

class function TArgusColors.Dark: TArgusColors;
begin
  Result := Default(TArgusColors);
  Result.IsDark := True;
  Result.Surface := Hex('#1A1E25');
  Result.Gutter := Hex('#15181D');
  Result.Text := Hex('#E3E7ED');
  Result.Muted := Hex('#9AA3B2');
  Result.Line := Hex('#2B313B');
  Result.Accent := Hex('#5B9BE6');
  Result.AccentSoft := Hex('#1B2D45');
  // 15 % statt 18 % wie im Entwurf: sonst hat der Akzent darauf weniger als 4,5 : 1.
  Result.Selection := TArgusColorMath.Mix(Result.Accent, Result.Surface, 0.15);
  Result.Keyword := Hex('#7FB0EE');
  Result.StringLiteral := Hex('#E3B27A');
  Result.Comment := Hex('#8A93A3');
  Result.Add := Hex('#7FD39A');
  Result.AddSoft := Hex('#1D3325');
  Result.Warn := Hex('#F0C06A');
  Result.WarnSoft := Hex('#3A2E17');
  Result.Error := Hex('#F59A8F');
  Result.ErrorSoft := Hex('#3E201E');
  Result.Badges[TArgusBadgeKind.Function_] := Badge('#1B2D45', '#9CC3F2');
  Result.Badges[TArgusBadgeKind.Procedure_] := Badge('#1C3329', '#86D0AE');
  Result.Badges[TArgusBadgeKind.Property_] := Badge('#43301F', '#F5B783');
  Result.Badges[TArgusBadgeKind.Field] := Badge('#1F3338', '#8FCAD6');
  Result.Badges[TArgusBadgeKind.Event] := Badge('#36264A', '#CBA6F2');
  Result.Badges[TArgusBadgeKind.Constant] := Badge('#3B3218', '#E8C96A');
  Result.Badges[TArgusBadgeKind.Type_] := Badge('#2A4670', '#B8D5F7');
  Result.Badges[TArgusBadgeKind.Variable] := Badge('#1F3338', '#8FCAD6');
  Result.Badges[TArgusBadgeKind.Unit_] := Badge('#272D36', '#B9C1CC');
  Result.Badges[TArgusBadgeKind.Snippet] := Badge('#272D36', '#B9C1CC');
  Result.Badges[TArgusBadgeKind.Keyword] := Badge('#272D36', '#B9C1CC');
  Result.Badges[TArgusBadgeKind.XmlDoc] := Badge('#272D36', '#B9C1CC');
  Result.Pairs[0] := Hex('#7FB0EE');
  Result.Pairs[1] := Hex('#C79BF2');
  Result.Pairs[2] := Hex('#F0C06A');
  Result.Pairs[3] := Hex('#7FD39A');
  Result.Pairs[4] := Hex('#F28DB6');
end;

class function TArgusColors.ForBackground(ABackground: TArgusColor): TArgusColors;
begin
  if TArgusColorMath.IsDark(ABackground) then
    Result := Dark
  else
    Result := Light;
end;

end.
