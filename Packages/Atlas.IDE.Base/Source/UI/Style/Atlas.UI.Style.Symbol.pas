unit Atlas.UI.Style.Symbol;

// Atlas-Symbol G1a in der VCL (#751). Die PNG-Ressourcen aus
// Resources\Symbol\Atlas.Symbol.rc werden mit WIC gelesen (TWICImage, ohne
// zusätzliches Package). TAtlasSymbolImages liefert sie als Bild, als
// HBITMAP mit vormultipliziertem Alphakanal (Startbildschirm und Info-Dialog
// der IDE), als TImageCollection für eine TVirtualImageList (Menü) und als
// Symbol für Fenster. TAtlasSymbolImage zeigt das Symbol in Seitenkopf,
// Ergebnisfenster und Update-Hinweis: Größe nach der Pixeldichte des
// Steuerelements, Variante nach der Hintergrundfarbe des aktiven Stils, beides
// bei jedem Zeichnen neu bestimmt, sodass Monitorwechsel und Themenwechsel ohne
// Neustart wirken. Bilder werden je Name einmal geladen und beim Entladen
// freigegeben.

interface

uses
  Winapi.Windows,
  System.Classes,
  Vcl.Graphics,
  Vcl.Controls,
  Vcl.ImageCollection,
  Atlas.Core.Style.Symbol;

type
  TAtlasSymbolImages = class
  public const
    /// <summary>Namen der Einträge in Collection, in dieser Reihenfolge.</summary>
    LightName = 'Atlas.Hell';
    DarkName = 'Atlas.Dunkel';
  public
    /// <summary>Gibt es die PNG-Ressource für AVariant in ASize?</summary>
    class function Exists(AVariant: TAtlasSymbolVariant; ASize: Integer): Boolean; static;
    /// <summary>Neues Bild aus der Ressource (Aufrufer gibt es frei); nil ohne Ressource.</summary>
    class function Load(AVariant: TAtlasSymbolVariant; ASize: Integer): TWICImage; static;
    /// <summary>Geteiltes Bild für ALogicalSize bei APixelsPerInch; nicht freigeben.</summary>
    class function Cached(AVariant: TAtlasSymbolVariant; ALogicalSize, APixelsPerInch: Integer): TWICImage; static;
    /// <summary>32-Bit-DIB mit vormultipliziertem Alpha; 0 ohne Ressource. Der Empfänger besitzt das Handle.</summary>
    class function Bitmap(AVariant: TAtlasSymbolVariant; ALogicalSize, APixelsPerInch: Integer): HBITMAP; static;
    /// <summary>Beide Varianten in allen Größen (LightName, DarkName).</summary>
    class function Collection(AOwner: TComponent): TImageCollection; static;
    /// <summary>Fenstersymbol aus der ICO-Ressource (alle Größen); Aufrufer gibt es frei.</summary>
    class function Icon(AVariant: TAtlasSymbolVariant): TIcon; static;
    /// <summary>Variante zum Hintergrund von AControl im aktiven Stil.</summary>
    class function VariantOf(AControl: TControl): TAtlasSymbolVariant; static;
    /// <summary>Beim Entladen: geteilte Bilder freigeben.</summary>
    class procedure ReleaseCache; static;
  end;

  /// <summary>Symbol als Steuerelement; LogicalSize bei 96 dpi.</summary>
  TAtlasSymbolImage = class(TGraphicControl)
  private
    FLogicalSize: Integer;
    FShownVariant: TAtlasSymbolVariant;
    FShownSize: Integer;
    procedure SetLogicalSize(AValue: Integer);
    procedure UpdateSize;
  protected
    procedure Paint; override;
    procedure ChangeScale(M, D: Integer; isDpiChange: Boolean); override;
  public
    constructor Create(AOwner: TComponent); override;
    property LogicalSize: Integer read FLogicalSize write SetLogicalSize;
    /// <summary>Zuletzt gezeichnete Variante und Bildgröße (für Tests).</summary>
    property ShownVariant: TAtlasSymbolVariant read FShownVariant;
    property ShownSize: Integer read FShownSize;
  end;

implementation

uses
  System.SysUtils,
  System.Types,
  System.Generics.Collections,
  Winapi.Wincodec,
  Vcl.Themes,
  Atlas.Core.Style.Color;

var
  Cache: TObjectDictionary<string, TWICImage>;

function ResourceModule: HINST;
begin
  Result := FindClassHInstance(TAtlasSymbolImages);
end;

function ColorOf(AColor: TColor): TAtlasColor;
begin
  Result := TAtlasColor(ColorToRGB(AColor));
end;

{ TAtlasSymbolImages }

class function TAtlasSymbolImages.Exists(AVariant: TAtlasSymbolVariant; ASize: Integer): Boolean;
begin
  Result := FindResource(ResourceModule, PChar(TAtlasSymbol.ResourceName(AVariant, ASize)), RT_RCDATA) <> 0;
end;

class function TAtlasSymbolImages.Load(AVariant: TAtlasSymbolVariant; ASize: Integer): TWICImage;
var
  Stream: TResourceStream;
begin
  Result := nil;
  if not Exists(AVariant, ASize) then
    Exit;
  Stream := TResourceStream.Create(ResourceModule, TAtlasSymbol.ResourceName(AVariant, ASize), RT_RCDATA);
  try
    Result := TWICImage.Create;
    try
      Result.LoadFromStream(Stream);
    except
      FreeAndNil(Result);
      raise;
    end;
  finally
    Stream.Free;
  end;
end;

class function TAtlasSymbolImages.Cached(AVariant: TAtlasSymbolVariant; ALogicalSize,
  APixelsPerInch: Integer): TWICImage;
var
  Size: Integer;
  Name: string;
begin
  Size := TAtlasSymbol.SizeFor(ALogicalSize, APixelsPerInch);
  Name := TAtlasSymbol.ResourceName(AVariant, Size);
  if Cache = nil then
    Cache := TObjectDictionary<string, TWICImage>.Create([doOwnsValues]);
  if not Cache.TryGetValue(Name, Result) then
  begin
    Result := Load(AVariant, Size);
    if Result <> nil then
      Cache.Add(Name, Result);
  end;
end;

class function TAtlasSymbolImages.Bitmap(AVariant: TAtlasSymbolVariant; ALogicalSize,
  APixelsPerInch: Integer): HBITMAP;
var
  Image: TWICImage;
  Converter: IWICFormatConverter;
  Info: TBitmapInfo;
  Bits: Pointer;
  Width, Height: Integer;
begin
  Result := 0;
  Image := Load(AVariant, TAtlasSymbol.SizeFor(ALogicalSize, APixelsPerInch));
  if Image = nil then
    Exit;
  try
    if Failed(TWICImage.ImagingFactory.CreateFormatConverter(Converter)) then
      Exit;
    if Failed(Converter.Initialize(Image.Handle, GUID_WICPixelFormat32bppPBGRA, WICBitmapDitherTypeNone, nil, 0,
      WICBitmapPaletteTypeCustom)) then
      Exit;
    Width := Image.Width;
    Height := Image.Height;
    FillChar(Info, SizeOf(Info), 0);
    Info.bmiHeader.biSize := SizeOf(TBitmapInfoHeader);
    Info.bmiHeader.biWidth := Width;
    // Negativ: Zeilen von oben nach unten wie bei WIC.
    Info.bmiHeader.biHeight := -Height;
    Info.bmiHeader.biPlanes := 1;
    Info.bmiHeader.biBitCount := 32;
    Info.bmiHeader.biCompression := BI_RGB;
    Bits := nil;
    Result := CreateDIBSection(0, Info, DIB_RGB_COLORS, Bits, 0, 0);
    if (Result <> 0) and Failed(Converter.CopyPixels(nil, Width * 4, Width * Height * 4, PByte(Bits))) then
    begin
      DeleteObject(Result);
      Result := 0;
    end;
  finally
    Image.Free;
  end;
end;

class function TAtlasSymbolImages.Collection(AOwner: TComponent): TImageCollection;

  procedure AddVariant(AVariant: TAtlasSymbolVariant; const AName: string);
  var
    Item: TImageCollectionItem;
    Index: Integer;
    Stream: TResourceStream;
  begin
    Item := Result.Images.Add;
    Item.Name := AName;
    for Index := 0 to TAtlasSymbol.SizeCount - 1 do
    begin
      if not Exists(AVariant, TAtlasSymbol.Size(Index)) then
        Continue;
      Stream := TResourceStream.Create(ResourceModule, TAtlasSymbol.ResourceName(AVariant, TAtlasSymbol.Size(Index)),
        RT_RCDATA);
      try
        Item.SourceImages.Add.Image.LoadFromStream(Stream);
      finally
        Stream.Free;
      end;
    end;
  end;

begin
  Result := TImageCollection.Create(AOwner);
  AddVariant(TAtlasSymbolVariant.Light, LightName);
  AddVariant(TAtlasSymbolVariant.Dark, DarkName);
end;

class function TAtlasSymbolImages.Icon(AVariant: TAtlasSymbolVariant): TIcon;
begin
  Result := TIcon.Create;
  if FindResource(ResourceModule, PChar(TAtlasSymbol.IconName(AVariant)), RT_GROUP_ICON) <> 0 then
    Result.LoadFromResourceName(ResourceModule, TAtlasSymbol.IconName(AVariant));
end;

class function TAtlasSymbolImages.VariantOf(AControl: TControl): TAtlasSymbolVariant;
begin
  Result := TAtlasSymbol.VariantFor(ColorOf(StyleServices(AControl).GetSystemColor(clBtnFace)));
end;

class procedure TAtlasSymbolImages.ReleaseCache;
begin
  FreeAndNil(Cache);
end;

{ TAtlasSymbolImage }

constructor TAtlasSymbolImage.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FLogicalSize := TAtlasSymbol.HeaderSize;
  UpdateSize;
end;

procedure TAtlasSymbolImage.SetLogicalSize(AValue: Integer);
begin
  if AValue = FLogicalSize then
    Exit;
  FLogicalSize := AValue;
  UpdateSize;
  Invalidate;
end;

procedure TAtlasSymbolImage.UpdateSize;
var
  Pixels: Integer;
begin
  Pixels := TAtlasSymbol.PixelSize(FLogicalSize, CurrentPPI);
  SetBounds(Left, Top, Pixels, Pixels);
end;

procedure TAtlasSymbolImage.ChangeScale(M, D: Integer; isDpiChange: Boolean);
begin
  inherited ChangeScale(M, D, isDpiChange);
  UpdateSize;
end;

procedure TAtlasSymbolImage.Paint;
var
  Image: TWICImage;
  Pixels: Integer;
  Target: TRect;
begin
  FShownVariant := TAtlasSymbolImages.VariantOf(Self);
  Image := TAtlasSymbolImages.Cached(FShownVariant, FLogicalSize, CurrentPPI);
  if Image = nil then
    Exit;
  FShownSize := Image.Width;
  Pixels := TAtlasSymbol.PixelSize(FLogicalSize, CurrentPPI);
  Target := Rect(0, 0, Pixels, Pixels);
  OffsetRect(Target, (Width - Pixels) div 2, (Height - Pixels) div 2);
  // Gleich groß: ungestreckt und damit scharf; sonst die nächstgrößere Datei verkleinert.
  if Image.Width = Pixels then
    Canvas.Draw(Target.Left, Target.Top, Image)
  else
    Canvas.StretchDraw(Target, Image);
end;

initialization

finalization
  TAtlasSymbolImages.ReleaseCache;

end.
