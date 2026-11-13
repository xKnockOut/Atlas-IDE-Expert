unit Atlas.IDE.Designer.PaletteImages;

// Symbole der Komponentenpalette als 16-px-Bildliste für die Atlas-Struktur
// (#609) und die Brotkrumenleiste der Datenbindung (#610).
// - Symbol einer Klasse: Bitmap-Ressource mit dem Klassennamen in Großbuchstaben
//   im Package der Klasse oder in einem anderen geladenen Package (die VCL-
//   Symbole liegen in den Entwurfszeit-Packages), sonst die des nächsten
//   Vorfahren; verkleinert auf 16 px, je Klasse einmal geladen.
// - Remember merkt sich die Klasse zum Namen; IndexOfName findet so das Symbol
//   zu einem Klassennamen aus dem Kern (der nur Namen kennt).
// Nur im Hauptthread.

interface

uses
  System.Classes,
  System.Generics.Collections,
  Vcl.Controls;

type
  TAtlasPaletteImages = class
  private
    FImages: TImageList;
    FLoaded: TStringList;
    FClasses: TDictionary<string, TClass>;
    /// <summary>Symbol aus der Palette selbst (INTAPalettePaintIcon); -1, wenn die Palette die Klasse nicht kennt.
    /// </summary>
    function PaintedIndex(const AClassName: string): Integer;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Klasse zum Namen merken (für IndexOfName).</summary>
    procedure Remember(AClass: TClass);
    /// <summary>Gemerkte Klassen vergessen (neues Formular); geladene Symbole bleiben.</summary>
    procedure Forget;
    /// <summary>Index des Symbols der Klasse; -1 ohne Ressource.</summary>
    function IndexOf(AClass: TClass): Integer;
    /// <summary>Index des Symbols zu einem gemerkten Klassennamen; -1 ohne.</summary>
    function IndexOfName(const AClassName: string): Integer;
    property Images: TImageList read FImages;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.Types,
  Vcl.Graphics,
  Vcl.ImgList,
  ToolsAPI,
  PaletteAPI,
  Atlas.Core.Designer.IconAlpha;

const
  cImageSize = 16;

/// <summary>Modul mit einer Bitmap-Ressource AName: zuerst das Package der Klasse, sonst jedes geladene Modul.
/// Die Palettensymbole der VCL-Komponenten (TPanel, TComboBox …) liegen nicht in vcl370.bpl, sondern in den
/// Entwurfszeit-Packages (dclstd370.bpl u. a.); nur im eigenen Package gesucht, fehlten sie alle.</summary>
function ModuleWithBitmap(AOwn: HMODULE; const AName: string): HMODULE;
var
  mModule: PLibModule;
begin
  if (AOwn <> 0) and (FindResource(AOwn, PChar(AName), RT_BITMAP) <> 0) then
  begin
    Exit(AOwn);
  end;
  mModule := LibModuleList;
  while mModule <> nil do
  begin
    if FindResource(mModule.ResInstance, PChar(AName), RT_BITMAP) <> 0 then
    begin
      Exit(mModule.ResInstance);
    end;
    mModule := mModule.Next;
  end;
  Result := 0;
end;

/// <summary>Bitmap der Palette (meist 24 Pixel) auf die Größe der Bildliste verkleinert.</summary>
function Shrunk(ABitmap: TBitmap; ASize: Integer): TBitmap;
begin
  Result := TBitmap.Create;
  Result.SetSize(ASize, ASize);
  Result.Canvas.StretchDraw(Rect(0, 0, ASize, ASize), ABitmap);
end;

{ TAtlasPaletteImages }

constructor TAtlasPaletteImages.Create;
begin
  inherited Create;
  FLoaded := TStringList.Create;
  FClasses := TDictionary<string, TClass>.Create;
  FImages := TImageList.Create(nil);
  FImages.ColorDepth := cd32Bit;
  FImages.SetSize(cImageSize, cImageSize);
end;

destructor TAtlasPaletteImages.Destroy;
begin
  FImages.Free;
  FClasses.Free;
  FLoaded.Free;
  inherited Destroy;
end;

/// <summary>Eintrag der Komponente AClassName unter AGroup (rekursiv); nil ohne.</summary>
/// <remarks>Nur für den Moment des Malens: Ein Eintrag gehört dem Package der Komponente. Festgehalten zeigte er nach
/// dem Entladen des Packages (oder nach dem Abbau der Palette beim Beenden) in fremden Speicher (Review 2.1.0, M1).
/// </remarks>
function FindPaletteItem(const AGroup: IOTAPaletteGroup; const AClassName: string): IOTABasePaletteItem;
var
  mIndex: Integer;
  mItem: IOTABasePaletteItem;
  mGroup: IOTAPaletteGroup;
  mComponent: IOTAComponentPaletteItem;
begin
  Result := nil;
  for mIndex := 0 to AGroup.Count - 1 do
  begin
    mItem := AGroup.Items[mIndex];
    if Supports(mItem, IOTAPaletteGroup, mGroup) then
    begin
      Result := FindPaletteItem(mGroup, AClassName);
    end
    else if Supports(mItem, IOTAComponentPaletteItem, mComponent) and SameText(mComponent.ClassName, AClassName) then
    begin
      Result := mItem;
    end;
    if Result <> nil then
    begin
      Exit;
    end;
  end;
end;

/// <summary>Symbol von APaint auf deckendem Grund AColor (32 Bit) als Pixel BGRA.</summary>
function PaintOn(const APaint: INTAPalettePaintIcon; AColor: TColor): TArray<Cardinal>;
var
  mBitmap: TBitmap;
  mRow: PCardinal;
  mY, mX: Integer;
begin
  mBitmap := TBitmap.Create;
  try
    mBitmap.PixelFormat := pf32bit;
    mBitmap.SetSize(cImageSize, cImageSize);
    mBitmap.Canvas.Brush.Color := AColor;
    mBitmap.Canvas.FillRect(Rect(0, 0, cImageSize, cImageSize));
    APaint.Paint(mBitmap.Canvas, 0, 0, pi16x16);
    SetLength(Result, cImageSize * cImageSize);
    for mY := 0 to cImageSize - 1 do
    begin
      mRow := mBitmap.ScanLine[mY];
      for mX := 0 to cImageSize - 1 do
      begin
        Result[mY * cImageSize + mX] := mRow^ and $00FFFFFF;
        Inc(mRow);
      end;
    end;
  finally
    mBitmap.Free;
  end;
end;

function TAtlasPaletteImages.PaintedIndex(const AClassName: string): Integer;
var
  mPalette: IOTAPaletteServices;
  mItem: IOTABasePaletteItem;
  mPaint: INTAPalettePaintIcon;
  mPixels: TArray<Cardinal>;
  mBitmap: TBitmap;
  mRow: PCardinal;
  mY, mX: Integer;
begin
  Result := -1;
  // Ohne IDE (Tests) gibt es keine Palette; dann nur die Ressourcen. Die Palette jedes Mal neu durchsuchen (nur für
  // Klassen ohne gemerktes Bild): So bekommen auch danach installierte Komponenten ihr Symbol.
  if (BorlandIDEServices = nil) or not Supports(BorlandIDEServices, IOTAPaletteServices, mPalette) or
    (mPalette.BaseGroup = nil) then
  begin
    Exit;
  end;
  mItem := FindPaletteItem(mPalette.BaseGroup, AClassName);
  if (mItem = nil) or not Supports(mItem, INTAPalettePaintIcon, mPaint) then
  begin
    Exit;
  end;
  // Die IDE malt mit Kantenglättung auf den Grund. Auf Schwarz und auf Weiß gemalt ergibt sich die echte
  // Durchsicht je Pixel; mit einer Schlüsselfarbe (vorher Magenta) behielten die Kanten deren Stich.
  mPixels := TAtlasIconAlpha.Combine(PaintOn(mPaint, clBlack), PaintOn(mPaint, clWhite));
  mBitmap := TBitmap.Create;
  try
    mBitmap.PixelFormat := pf32bit;
    mBitmap.SetSize(cImageSize, cImageSize);
    for mY := 0 to cImageSize - 1 do
    begin
      mRow := mBitmap.ScanLine[mY];
      for mX := 0 to cImageSize - 1 do
      begin
        mRow^ := mPixels[mY * cImageSize + mX];
        Inc(mRow);
      end;
    end;
    mBitmap.AlphaFormat := afDefined;
    Result := FImages.Add(mBitmap, nil);
  finally
    mBitmap.Free;
  end;
end;

procedure TAtlasPaletteImages.Remember(AClass: TClass);
begin
  FClasses.AddOrSetValue(AClass.ClassName.ToLower, AClass);
end;

procedure TAtlasPaletteImages.Forget;
begin
  FClasses.Clear;
end;

function TAtlasPaletteImages.IndexOfName(const AClassName: string): Integer;
var
  mClass: TClass;
begin
  Result := -1;
  if (AClassName <> '') and FClasses.TryGetValue(AClassName.ToLower, mClass) then
  begin
    Result := IndexOf(mClass);
  end;
end;

function TAtlasPaletteImages.IndexOf(AClass: TClass): Integer;
var
  mIndex: Integer;
  mClass: TClass;
  mBitmap, mSmall: TBitmap;
  mInstance: HMODULE;
begin
  mIndex := FLoaded.IndexOf(AClass.ClassName);
  if mIndex >= 0 then
  begin
    Exit(Integer(FLoaded.Objects[mIndex]));
  end;
  Result := -1;
  mClass := AClass;
  while (Result < 0) and (mClass <> nil) and (mClass <> TComponent) do
  begin
    // Zuerst wie die Palette selbst zeichnen lassen (Delphi 13 hält die Symbole nicht als RT_BITMAP vor).
    Result := PaintedIndex(mClass.ClassName);
    if Result >= 0 then
    begin
      Break;
    end;
    mInstance := ModuleWithBitmap(FindClassHInstance(mClass), UpperCase(mClass.ClassName));
    if mInstance <> 0 then
    begin
      mBitmap := TBitmap.Create;
      try
        mBitmap.LoadFromResourceName(mInstance, UpperCase(mClass.ClassName));
        mSmall := Shrunk(mBitmap, FImages.Width);
        try
          Result := FImages.AddMasked(mSmall, mBitmap.Canvas.Pixels[0, mBitmap.Height - 1]);
        finally
          mSmall.Free;
        end;
      finally
        mBitmap.Free;
      end;
    end;
    mClass := mClass.ClassParent;
  end;
  FLoaded.AddObject(AClass.ClassName, TObject(Result));
end;

end.
