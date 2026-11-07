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
    cSizeCount = 9;
    /// <summary>Logische Größen: Menü und Statusfeld, Startbildschirm, Seitenkopf, Info-Dialog.</summary>
    cMenuSize = 16;
    cSplashSize = 24;
    cHeaderSize = 32;
    cAboutSize = 48;
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
  cSizes: array[0..TAtlasSymbol.cSizeCount - 1] of Integer = (16, 20, 24, 32, 40, 48, 64, 128, 256);

function VariantText(AVariant: TAtlasSymbolVariant): string;
begin
  if AVariant = TAtlasSymbolVariant.Dark then
  begin
    Result := 'DUNKEL';
  end
  else
  begin
    Result := 'HELL';
  end;
end;

{ TAtlasSymbol }

class function TAtlasSymbol.Size(AIndex: Integer): Integer;
begin
  Result := cSizes[AIndex];
end;

class function TAtlasSymbol.PixelSize(ALogicalSize, APixelsPerInch: Integer): Integer;
begin
  if APixelsPerInch <= 0 then
  begin
    APixelsPerInch := 96;
  end;
  // Kaufmännisch gerundet wie MulDiv: 16 px bei 150 % sind 24 px.
  Result := (ALogicalSize * APixelsPerInch + 48) div 96;
end;

class function TAtlasSymbol.SizeFor(ALogicalSize, APixelsPerInch: Integer): Integer;
var
  mNeeded, mIndex: Integer;
begin
  mNeeded := PixelSize(ALogicalSize, APixelsPerInch);
  for mIndex := Low(cSizes) to High(cSizes) do
  begin
    if cSizes[mIndex] >= mNeeded then
    begin
      Exit(cSizes[mIndex]);
    end;
  end;
  Result := cSizes[High(cSizes)];
end;

class function TAtlasSymbol.VariantFor(ABackground: TAtlasColor): TAtlasSymbolVariant;
begin
  Result := VariantFor(TAtlasColorMath.IsDark(ABackground));
end;

class function TAtlasSymbol.VariantFor(ADarkTheme: Boolean): TAtlasSymbolVariant;
begin
  if ADarkTheme then
  begin
    Result := TAtlasSymbolVariant.Dark;
  end
  else
  begin
    Result := TAtlasSymbolVariant.Light;
  end;
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
