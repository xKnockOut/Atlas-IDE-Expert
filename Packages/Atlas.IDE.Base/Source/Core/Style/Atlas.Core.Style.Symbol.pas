unit Atlas.Core.Style.Symbol;

// Atlas-Symbol G1a (#751): welche Bildgröße und welche Variante wo gezeigt
// wird. Die Bilder liegen als PNG-Ressourcen (RCDATA) im Plugin, je Variante
// in den Größen aus Sizes; die Namen bildet ResourceName. Die Größe richtet
// sich nach der logischen Größe (bei 96 dpi) und der Pixeldichte: die
// kleinste vorhandene, die mindestens so groß ist; über 256 px die größte.
// Hell und Dunkel nach dem Hintergrund (TAtlasColorMath.IsDark): auf dunklem
// Grund die dunkle Variante (helles A).

interface

uses
  Atlas.Core.Style.Color;

type
{$SCOPEDENUMS ON}
  TAtlasSymbolVariant = (Light, Dark);
{$SCOPEDENUMS OFF}

  TAtlasSymbol = class
  public const
    SizeCount = 9;
    /// <summary>Ressource des Programmsymbols (ICO) für den Server.</summary>
    MainIcon = 'MAINICON';
    /// <summary>Logische Größen: Menü und Statusfeld, Startbildschirm, Seitenkopf, Info-Dialog.</summary>
    MenuSize = 16;
    SplashSize = 24;
    HeaderSize = 32;
    AboutSize = 48;
  public
    /// <summary>Vorhandene Bildgröße Nummer AIndex (0 bis SizeCount - 1), aufsteigend.</summary>
    class function Size(AIndex: Integer): Integer; static;
    /// <summary>Benötigte Pixelgröße für ALogicalSize bei APixelsPerInch (96 = 100 %).</summary>
    class function PixelSize(ALogicalSize, APixelsPerInch: Integer): Integer; static;
    /// <summary>Kleinste vorhandene Größe ab PixelSize, sonst die größte.</summary>
    class function SizeFor(ALogicalSize, APixelsPerInch: Integer): Integer; static;
    /// <summary>Dunkel auf dunklem Hintergrund, sonst Hell.</summary>
    class function VariantFor(ABackground: TAtlasColor): TAtlasSymbolVariant; overload; static;
    class function VariantFor(ADarkTheme: Boolean): TAtlasSymbolVariant; overload; static;
    /// <summary>Name der PNG-Ressource, z. B. ATLAS_DUNKEL_32.</summary>
    class function ResourceName(AVariant: TAtlasSymbolVariant; ASize: Integer): string; static;
    /// <summary>Name der ICO-Ressource je Variante, z. B. ATLAS_ICON_HELL.</summary>
    class function IconName(AVariant: TAtlasSymbolVariant): string; static;
  end;

implementation

uses
  System.SysUtils;

const
  Sizes: array[0..TAtlasSymbol.SizeCount - 1] of Integer = (16, 20, 24, 32, 40, 48, 64, 128, 256);

function VariantText(AVariant: TAtlasSymbolVariant): string;
begin
  if AVariant = TAtlasSymbolVariant.Dark then
    Result := 'DUNKEL'
  else
    Result := 'HELL';
end;

{ TAtlasSymbol }

class function TAtlasSymbol.Size(AIndex: Integer): Integer;
begin
  Result := Sizes[AIndex];
end;

class function TAtlasSymbol.PixelSize(ALogicalSize, APixelsPerInch: Integer): Integer;
begin
  if APixelsPerInch <= 0 then
    APixelsPerInch := 96;
  // Kaufmännisch gerundet wie MulDiv: 16 px bei 150 % sind 24 px.
  Result := (ALogicalSize * APixelsPerInch + 48) div 96;
end;

class function TAtlasSymbol.SizeFor(ALogicalSize, APixelsPerInch: Integer): Integer;
var
  Needed, Index: Integer;
begin
  Needed := PixelSize(ALogicalSize, APixelsPerInch);
  for Index := Low(Sizes) to High(Sizes) do
    if Sizes[Index] >= Needed then
      Exit(Sizes[Index]);
  Result := Sizes[High(Sizes)];
end;

class function TAtlasSymbol.VariantFor(ABackground: TAtlasColor): TAtlasSymbolVariant;
begin
  Result := VariantFor(TAtlasColorMath.IsDark(ABackground));
end;

class function TAtlasSymbol.VariantFor(ADarkTheme: Boolean): TAtlasSymbolVariant;
begin
  if ADarkTheme then
    Result := TAtlasSymbolVariant.Dark
  else
    Result := TAtlasSymbolVariant.Light;
end;

class function TAtlasSymbol.ResourceName(AVariant: TAtlasSymbolVariant; ASize: Integer): string;
begin
  Result := Format('ATLAS_%s_%d', [VariantText(AVariant), ASize]);
end;

class function TAtlasSymbol.IconName(AVariant: TAtlasSymbolVariant): string;
begin
  Result := 'ATLAS_ICON_' + VariantText(AVariant);
end;

end.
