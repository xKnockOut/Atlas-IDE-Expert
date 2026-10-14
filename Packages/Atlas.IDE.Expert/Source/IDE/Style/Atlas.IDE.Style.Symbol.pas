unit Atlas.IDE.Style.Symbol;

// Atlas-Symbol G1a in der IDE (#751): Eintrag mit Symbol und Version im
// Startbildschirm (IOTASplashScreenServices) und im Info-Dialog
// (IOTAAboutBoxServices), Bilder für Menüs in der Bildliste der IDE
// (TVirtualImageList über einer TImageCollection, damit die IDE je
// Skalierung die passende Größe wählt) und Meldung bei einem Themenwechsel
// (INTAIDEThemingServicesNotifier). Die Variante richtet sich nach dem
// IDE-Thema (TAtlasIdeStyle); OnThemeChanged lässt Menü und Statusfeld
// umschalten. Der Startbildschirm ist in RAD Studio 12 und 13 dunkel und
// bekommt immer die dunkle Variante.

interface

uses
  System.SysUtils,
  Atlas.Core.Style.Symbol;

type
  TAtlasIdeSymbol = class
  public class var
    /// <summary>Nach einem Themenwechsel der IDE; setzt die Composition.</summary>
    OnThemeChanged: TProc;
  public
    /// <summary>Variante zum aktiven IDE-Thema.</summary>
    class function Current: TAtlasSymbolVariant; static;
    /// <summary>Bildindex des Symbols in der Bildliste der IDE für das aktive Thema; -1 ohne Bildliste.</summary>
    class function MenuImage: Integer; static;
    /// <summary>Startbildschirm, Info-Dialog, Bildliste und Themen-Notifier anmelden.</summary>
    class procedure Register; static;
    class procedure Unregister; static;
  end;

implementation

uses
  Winapi.Windows,
  System.Classes,
  Vcl.Forms,
  Vcl.ImageCollection,
  Vcl.VirtualImageList,
  ToolsAPI,
  Atlas.Core.Product.Version,
  Atlas.Core.Diagnostics.Guard,
  Atlas.UI.Strings,
  Atlas.UI.Style.Symbol,
  Atlas.IDE.Editor.Style;

type
  TThemeNotifier = class(TNotifierObject, INTAIDEThemingServicesNotifier)
  public
    procedure ChangingTheme;
    procedure ChangedTheme;
  end;

var
  Collection: TImageCollection;
  Images: TVirtualImageList;
  FirstImage: Integer = -1;
  AboutIndex: Integer = -1;
  ThemeNotifier: Integer = -1;
  SplashDone: Boolean;

function Title: string;
begin
  Result := TAtlasStrings.Fmt(TAtlasTextId.SymbolTitle, [TAtlasPluginVersion.Version]);
end;

{ TThemeNotifier }

procedure TThemeNotifier.ChangingTheme;
begin
end;

procedure TThemeNotifier.ChangedTheme;
begin
  try
    if Assigned(TAtlasIdeSymbol.OnThemeChanged) then
      TAtlasIdeSymbol.OnThemeChanged();
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Status, E);
  end;
end;

{ TAtlasIdeSymbol }

class function TAtlasIdeSymbol.Current: TAtlasSymbolVariant;
begin
  Result := TAtlasSymbol.VariantFor(TAtlasIdeStyle.Colors.IsDark);
end;

class function TAtlasIdeSymbol.MenuImage: Integer;
begin
  Result := FirstImage;
  if (Result >= 0) and (Current = TAtlasSymbolVariant.Dark) then
    Inc(Result);
end;

procedure AddSplash;
var
  Bitmap: HBITMAP;
begin
  if SplashDone or (SplashScreenServices = nil) then
    Exit;
  SplashDone := True;
  Bitmap := TAtlasSymbolImages.Bitmap(TAtlasSymbolVariant.Dark, TAtlasSymbol.SplashSize, Screen.PixelsPerInch);
  if Bitmap <> 0 then
    SplashScreenServices.AddPluginBitmap(Title, Bitmap);
end;

procedure AddAbout;
var
  Services: IOTAAboutBoxServices;
  Bitmap: HBITMAP;
begin
  if (AboutIndex >= 0) or not Supports(BorlandIDEServices, IOTAAboutBoxServices, Services) then
    Exit;
  Bitmap := TAtlasSymbolImages.Bitmap(TAtlasIdeSymbol.Current, TAtlasSymbol.AboutSize, Screen.PixelsPerInch);
  AboutIndex := Services.AddPluginInfo(Title, TAtlasStrings.Text(TAtlasTextId.SymbolDescription), Bitmap);
end;

procedure AddImages;
var
  Services: INTAServices;
begin
  if (Images <> nil) or not Supports(BorlandIDEServices, INTAServices, Services) then
    Exit;
  Collection := TAtlasSymbolImages.Collection(nil);
  Images := TVirtualImageList.Create(nil);
  Images.SetSize(TAtlasSymbol.MenuSize, TAtlasSymbol.MenuSize);
  Images.ImageCollection := Collection;
  // Hell und Dunkel in der Reihenfolge der Sammlung.
  Images.AutoFill := True;
  FirstImage := Services.AddImages(Images, 'AtlasSymbol');
end;

procedure AddThemeNotifier;
var
  Theming: IOTAIDEThemingServices;
begin
  if (ThemeNotifier < 0) and Supports(BorlandIDEServices, IOTAIDEThemingServices, Theming) then
    ThemeNotifier := Theming.AddNotifier(TThemeNotifier.Create);
end;

class procedure TAtlasIdeSymbol.Register;
begin
  // Jeder Teil für sich: ein fehlender Dienst verhindert die übrigen nicht.
  try
    AddSplash;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Status, E);
  end;
  try
    AddAbout;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Status, E);
  end;
  try
    AddImages;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Status, E);
  end;
  try
    AddThemeNotifier;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Status, E);
  end;
end;

class procedure TAtlasIdeSymbol.Unregister;
var
  About: IOTAAboutBoxServices;
  Theming: IOTAIDEThemingServices;
begin
  OnThemeChanged := nil;
  if (ThemeNotifier >= 0) and Supports(BorlandIDEServices, IOTAIDEThemingServices, Theming) then
    Theming.RemoveNotifier(ThemeNotifier);
  ThemeNotifier := -1;
  if (AboutIndex >= 0) and Supports(BorlandIDEServices, IOTAAboutBoxServices, About) then
    About.RemovePluginInfo(AboutIndex);
  AboutIndex := -1;
  // Die Bilder bleiben in der Bildliste der IDE (sie lassen sich nicht entfernen); die Menüeinträge sind dann weg.
  FirstImage := -1;
  FreeAndNil(Images);
  FreeAndNil(Collection);
  TAtlasSymbolImages.ReleaseCache;
end;

end.
