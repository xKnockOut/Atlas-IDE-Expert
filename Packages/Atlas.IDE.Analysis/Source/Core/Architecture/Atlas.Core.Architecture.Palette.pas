unit Atlas.Core.Architecture.Palette;

// Farben der Teilsysteme im Fenster „Atlas-Architektur“ wie in der HTML-Karte, je für helle und dunkle Themen,
// ohne VCL und OTA: die Teile eines nachgeteilten Teilsystems (#1364) teilen eine Farbe in helleren und dunkleren
// Tönen, das Teilsystem „Fundament“ (#1365) ist neutral wie --muted der HTML-Karte.

interface

type
  TAtlasArchitecturePalette = class
  public const
    cCount = 10;
    /// <summary>Höchstens so weit wird ein Ton zu Weiß bzw. Schwarz gemischt.</summary>
    cMaxShadeMix = 0.6;
    /// <summary>Mischanteil je Tonstufe.</summary>
    cShadeStep = 0.22;
  public
    /// <summary>Farbe des Teilsystems ASubsystem als $00BBGGRR (wie TColor).</summary>
    class function Color(ASubsystem: Integer; ADark: Boolean): Cardinal; overload; static;
    /// <summary>Farbe ASlot im Ton AShade (#1364): positiv heller, negativ dunkler, wie color-mix der HTML-Karte.
    /// </summary>
    class function Color(ASlot, AShade: Integer; ADark: Boolean): Cardinal; overload; static;
    /// <summary>Neutrale Farbe des Teilsystems „Fundament“ (#1365), wie --muted der HTML-Karte.</summary>
    class function FoundationColor(ADark: Boolean): Cardinal; static;
    /// <summary>Hintergrund ($00BBGGRR) ist dunkel: Helligkeit unter der Hälfte.</summary>
    class function IsDark(ABackground: Cardinal): Boolean; static;
  end;

implementation

uses
  System.Math;

const
  /// <summary>Lage der Kanäle in $00BBGGRR bzw. #RRGGBB.</summary>
  cChannelBits = 8;
  cGreenShift = 8;
  cBlueShift = 16;
  cGreenMask = $FF00;
  cChannelMax = 255;
  /// <summary>Helligkeit nach ITU-R BT.601 in Tausendsteln; dunkel unter der Hälfte.</summary>
  cLumaRed = 299;
  cLumaGreen = 587;
  cLumaBlue = 114;
  cLumaScale = 1000;
  cDarkBelow = 128;
  /// <summary>Teilsystem „Fundament“: #9AA2B2 (dunkles Thema) bzw. #5D6576 als $00BBGGRR.</summary>
  cFoundationDark = $B2A29A;
  cFoundationLight = $76655D;
  // Wie --c0 … --c9 der HTML-Karte (#RRGGBB), hell bzw. dunkel.
  cLightColors: array[0..TAtlasArchitecturePalette.cCount - 1] of Cardinal = ($2F6FB3, $7A4FB0, $2E7D4F, $B07A1D,
    $A33C5A, $1B8A8F, $6B6F1D, $C2571A, $4A5AB8, $8A4F3A);
  cDarkColors: array[0..TAtlasArchitecturePalette.cCount - 1] of Cardinal = ($6AA6E6, $B28BE0, $6CC293, $E0B257,
    $E07A98, $5CC6C9, $C3C75A, $F0945A, $94A0F0, $D09A83);

{ TAtlasArchitecturePalette }

class function TAtlasArchitecturePalette.Color(ASubsystem: Integer; ADark: Boolean): Cardinal;
var
  mRgb: Cardinal;
  mSlot: Integer;
begin
  mSlot := Abs(ASubsystem) mod cCount;
  if ADark then
  begin
    mRgb := cDarkColors[mSlot];
  end
  else
  begin
    mRgb := cLightColors[mSlot];
  end;
  // #RRGGBB → $00BBGGRR.
  Result := ((mRgb and $FF) shl cBlueShift) or (mRgb and cGreenMask) or ((mRgb shr cBlueShift) and $FF);
end;

class function TAtlasArchitecturePalette.Color(ASlot, AShade: Integer; ADark: Boolean): Cardinal;
var
  mBase: Cardinal;
  mMix: Double;
  mShift, mChannel: Integer;
begin
  mBase := Color(ASlot, ADark);
  if AShade = 0 then
  begin
    Exit(mBase);
  end;
  mMix := Min(cMaxShadeMix, cShadeStep * Abs(AShade));
  Result := 0;
  mShift := 0;
  while mShift <= cBlueShift do
  begin
    mChannel := (mBase shr mShift) and $FF;
    if AShade > 0 then
    begin
      mChannel := Round(mChannel + (cChannelMax - mChannel) * mMix);
    end
    else
    begin
      mChannel := Round(mChannel * (1 - mMix));
    end;
    Result := Result or (Cardinal(EnsureRange(mChannel, 0, cChannelMax)) shl mShift);
    Inc(mShift, cChannelBits);
  end;
end;

class function TAtlasArchitecturePalette.FoundationColor(ADark: Boolean): Cardinal;
begin
  if ADark then
  begin
    Result := cFoundationDark;
  end
  else
  begin
    Result := cFoundationLight;
  end;
end;

class function TAtlasArchitecturePalette.IsDark(ABackground: Cardinal): Boolean;
var
  mRed, mGreen, mBlue: Integer;
begin
  mRed := ABackground and $FF;
  mGreen := (ABackground shr cGreenShift) and $FF;
  mBlue := (ABackground shr cBlueShift) and $FF;
  Result := (mRed * cLumaRed + mGreen * cLumaGreen + mBlue * cLumaBlue) div cLumaScale < cDarkBelow;
end;

end.
