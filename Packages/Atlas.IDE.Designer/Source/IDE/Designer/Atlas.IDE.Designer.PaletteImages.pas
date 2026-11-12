unit Atlas.IDE.Designer.PaletteImages;

// Symbole der Komponentenpalette als 16-px-Bildliste für die Atlas-Struktur
// (#609) und die Brotkrumenleiste der Datenbindung (#610).
// - Symbol einer Klasse: Bitmap-Ressource mit dem Klassennamen in Großbuchstaben
//   im Package der Klasse, sonst die des nächsten Vorfahren; verkleinert auf
//   16 px, je Klasse einmal geladen.
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
  Vcl.ImgList;

const
  cImageSize = 16;

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
    mInstance := FindClassHInstance(mClass);
    if (mInstance <> 0) and (FindResource(mInstance, PChar(UpperCase(mClass.ClassName)), RT_BITMAP) <> 0) then
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
