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
    cLightName = 'Atlas.Hell';
    cDarkName = 'Atlas.Dunkel';
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
  mStream: TResourceStream;
begin
  Result := nil;
  if not Exists(AVariant, ASize) then
  begin
    Exit;
  end;
  mStream := TResourceStream.Create(ResourceModule, TAtlasSymbol.ResourceName(AVariant, ASize), RT_RCDATA);
  try
    Result := TWICImage.Create;
    try
      Result.LoadFromStream(mStream);
    except
      FreeAndNil(Result);
      raise;
    end;
  finally
    mStream.Free;
  end;
end;

class function TAtlasSymbolImages.Cached(AVariant: TAtlasSymbolVariant; ALogicalSize,
  APixelsPerInch: Integer): TWICImage;
var
  mSize: Integer;
  mName: string;
begin
  mSize := TAtlasSymbol.SizeFor(ALogicalSize, APixelsPerInch);
  mName := TAtlasSymbol.ResourceName(AVariant, mSize);
  if Cache = nil then
  begin
    Cache := TObjectDictionary<string, TWICImage>.Create([doOwnsValues]);
  end;
  if not Cache.TryGetValue(mName, Result) then
  begin
    Result := Load(AVariant, mSize);
    if Result <> nil then
    begin
      Cache.Add(mName, Result);
    end;
  end;
end;

class function TAtlasSymbolImages.Bitmap(AVariant: TAtlasSymbolVariant; ALogicalSize,
  APixelsPerInch: Integer): HBITMAP;
var
  mImage: TWICImage;
  mConverter: IWICFormatConverter;
  mInfo: TBitmapInfo;
  mBits: Pointer;
  mWidth, mHeight: Integer;
begin
  Result := 0;
  mImage := Load(AVariant, TAtlasSymbol.SizeFor(ALogicalSize, APixelsPerInch));
  if mImage = nil then
  begin
    Exit;
  end;
  try
    if Failed(TWICImage.ImagingFactory.CreateFormatConverter(mConverter)) then
    begin
      Exit;
    end;
    if Failed(mConverter.Initialize(mImage.Handle, GUID_WICPixelFormat32bppPBGRA, WICBitmapDitherTypeNone, nil, 0,
      WICBitmapPaletteTypeCustom)) then
    begin
      Exit;
    end;
    mWidth := mImage.Width;
    mHeight := mImage.Height;
    FillChar(mInfo, SizeOf(mInfo), 0);
    mInfo.bmiHeader.biSize := SizeOf(TBitmapInfoHeader);
    mInfo.bmiHeader.biWidth := mWidth;
    // Negativ: Zeilen von oben nach unten wie bei WIC.
    mInfo.bmiHeader.biHeight := -mHeight;
    mInfo.bmiHeader.biPlanes := 1;
    mInfo.bmiHeader.biBitCount := 32;
    mInfo.bmiHeader.biCompression := BI_RGB;
    mBits := nil;
    Result := CreateDIBSection(0, mInfo, DIB_RGB_COLORS, mBits, 0, 0);
    if (Result <> 0) and Failed(mConverter.CopyPixels(nil, mWidth * 4, mWidth * mHeight * 4, PByte(mBits))) then
    begin
      DeleteObject(Result);
      Result := 0;
    end;
  finally
    mImage.Free;
  end;
end;

class function TAtlasSymbolImages.Collection(AOwner: TComponent): TImageCollection;

  procedure AddVariant(AVariant: TAtlasSymbolVariant; const AName: string);
  var
    mItem: TImageCollectionItem;
    mIndex: Integer;
    mStream: TResourceStream;
  begin
    mItem := Result.Images.Add;
    mItem.Name := AName;
    for mIndex := 0 to TAtlasSymbol.cSizeCount - 1 do
    begin
      if not Exists(AVariant, TAtlasSymbol.Size(mIndex)) then
      begin
        Continue;
      end;
      mStream := TResourceStream.Create(ResourceModule, TAtlasSymbol.ResourceName(AVariant, TAtlasSymbol.Size(mIndex)),
        RT_RCDATA);
      try
        mItem.SourceImages.Add.Image.LoadFromStream(mStream);
      finally
        mStream.Free;
      end;
    end;
  end;

begin
  Result := TImageCollection.Create(AOwner);
  AddVariant(TAtlasSymbolVariant.Light, cLightName);
  AddVariant(TAtlasSymbolVariant.Dark, cDarkName);
end;

class function TAtlasSymbolImages.Icon(AVariant: TAtlasSymbolVariant): TIcon;
begin
  Result := TIcon.Create;
  if FindResource(ResourceModule, PChar(TAtlasSymbol.IconName(AVariant)), RT_GROUP_ICON) <> 0 then
  begin
    Result.LoadFromResourceName(ResourceModule, TAtlasSymbol.IconName(AVariant));
  end;
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
  FLogicalSize := TAtlasSymbol.cHeaderSize;
  UpdateSize;
end;

procedure TAtlasSymbolImage.SetLogicalSize(AValue: Integer);
begin
  if AValue = FLogicalSize then
  begin
    Exit;
  end;
  FLogicalSize := AValue;
  UpdateSize;
  Invalidate;
end;

procedure TAtlasSymbolImage.UpdateSize;
var
  mPixels: Integer;
begin
  mPixels := TAtlasSymbol.PixelSize(FLogicalSize, CurrentPPI);
  SetBounds(Left, Top, mPixels, mPixels);
end;

procedure TAtlasSymbolImage.ChangeScale(M, D: Integer; isDpiChange: Boolean);
begin
  inherited ChangeScale(M, D, isDpiChange);
  UpdateSize;
end;

procedure TAtlasSymbolImage.Paint;
var
  mImage: TWICImage;
  mPixels: Integer;
  mTarget: TRect;
begin
  FShownVariant := TAtlasSymbolImages.VariantOf(Self);
  mImage := TAtlasSymbolImages.Cached(FShownVariant, FLogicalSize, CurrentPPI);
  if mImage = nil then
  begin
    Exit;
  end;
  FShownSize := mImage.Width;
  mPixels := TAtlasSymbol.PixelSize(FLogicalSize, CurrentPPI);
  mTarget := Rect(0, 0, mPixels, mPixels);
  OffsetRect(mTarget, (Width - mPixels) div 2, (Height - mPixels) div 2);
  // Gleich groß: ungestreckt und damit scharf; sonst die nächstgrößere Datei verkleinert.
  if mImage.Width = mPixels then
  begin
    Canvas.Draw(mTarget.Left, mTarget.Top, mImage);
  end
  else
  begin
    Canvas.StretchDraw(mTarget, mImage);
  end;
end;

initialization

finalization
  TAtlasSymbolImages.ReleaseCache;

end.
