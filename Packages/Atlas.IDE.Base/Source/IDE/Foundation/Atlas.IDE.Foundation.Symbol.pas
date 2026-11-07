unit Atlas.IDE.Foundation.Symbol;

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
  Vcl.ExtCtrls,
  Vcl.ImageCollection,
  Vcl.VirtualImageList,
  ToolsAPI,
  Atlas.Core.Product.Version,
  Atlas.Core.Style.Color,
  Atlas.Core.Diagnostics.Guard,
  Atlas.UI.Strings,
  Atlas.UI.Style.Symbol,
  Atlas.IDE.Foundation.EditorStyle;

type
  TThemeNotifier = class(TNotifierObject, INTAIDEThemingServicesNotifier)
  public
    procedure ChangingTheme;
    procedure ChangedTheme;
  end;

  /// <summary>Zweiter Durchlauf nach dem Themenwechsel.</summary>
  TLater = class
    procedure Tick(Sender: TObject);
  end;

const
  cLaterMs = 400;

var
  Later: TTimer;
  Later_: TLater;
  Collection: TImageCollection;
  Images: TVirtualImageList;
  FirstImage: Integer = -1;
  AboutIndex: Integer = -1;
  ThemeNotifier: Integer = -1;
  SplashDone: Boolean;

function Title: string;
begin
  Result := TAtlasStrings.Fmt(TAtlasTextId.SymbolTitle, [TAtlasPluginVersion.cVersion]);
end;

/// <summary>Ein Durchlauf AMs nach der Meldung; die Zeile im Protokoll zeigt, welches Thema die IDE da liefert.
/// </summary>
procedure Run(AMs: Integer);
var
  mTheming: IOTAIDEThemingServices;
  mName: string;
begin
  try
    mName := '';
    if Supports(BorlandIDEServices, IOTAIDEThemingServices, mTheming) then
    begin
      mName := mTheming.ActiveTheme;
    end;
    TAtlasGuard.Log(Format('Themenwechsel +%d ms: %s, Hintergrund %s', [AMs, mName,
      TAtlasColorMath.ToHex(TAtlasIdeStyle.Colors.Surface)]));
    if Assigned(TAtlasIdeSymbol.OnThemeChanged) then
    begin
      TAtlasIdeSymbol.OnThemeChanged();
    end;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Status, E);
  end;
end;

{ TThemeNotifier }

procedure TThemeNotifier.ChangingTheme;
begin
end;

procedure TThemeNotifier.ChangedTheme;
begin
  Run(0);
  // Die IDE meldet den Wechsel, bevor ihre StyleServices das neue Thema liefern: Hell/Dunkel wäre noch das
  // alte (Logo im Menü, Farben der Panels). Kurz danach noch einmal; ein Eintrag in der Warteschlange kam noch
  // zu früh.
  if Later = nil then
  begin
    if Later_ = nil then
    begin
      Later_ := TLater.Create;
    end;
    Later := TTimer.Create(nil);
    Later.OnTimer := Later_.Tick;
  end;
  Later.Enabled := False;
  Later.Interval := cLaterMs;
  Later.Enabled := True;
end;

{ TLater }

procedure TLater.Tick(Sender: TObject);
begin
  Later.Enabled := False;
  Run(cLaterMs);
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
  begin
    Inc(Result);
  end;
end;

procedure AddSplash;
var
  mBitmap: HBITMAP;
begin
  if SplashDone or (SplashScreenServices = nil) then
  begin
    Exit;
  end;
  SplashDone := True;
  mBitmap := TAtlasSymbolImages.Bitmap(TAtlasSymbolVariant.Dark, TAtlasSymbol.cSplashSize, Screen.PixelsPerInch);
  if mBitmap <> 0 then
  begin
    SplashScreenServices.AddPluginBitmap(Title, mBitmap);
  end;
end;

procedure AddAbout;
var
  mServices: IOTAAboutBoxServices;
  mBitmap: HBITMAP;
begin
  if (AboutIndex >= 0) or not Supports(BorlandIDEServices, IOTAAboutBoxServices, mServices) then
  begin
    Exit;
  end;
  mBitmap := TAtlasSymbolImages.Bitmap(TAtlasIdeSymbol.Current, TAtlasSymbol.cAboutSize, Screen.PixelsPerInch);
  AboutIndex := mServices.AddPluginInfo(Title, TAtlasStrings.Text(TAtlasTextId.SymbolDescription), mBitmap);
end;

procedure AddImages;
var
  mServices: INTAServices;
begin
  if (Images <> nil) or not Supports(BorlandIDEServices, INTAServices, mServices) then
  begin
    Exit;
  end;
  Collection := TAtlasSymbolImages.Collection(nil);
  Images := TVirtualImageList.Create(nil);
  Images.SetSize(TAtlasSymbol.cMenuSize, TAtlasSymbol.cMenuSize);
  Images.ImageCollection := Collection;
  // Hell und Dunkel in der Reihenfolge der Sammlung.
  Images.AutoFill := True;
  FirstImage := mServices.AddImages(Images, 'AtlasSymbol');
end;

procedure AddThemeNotifier;
var
  mTheming: IOTAIDEThemingServices;
begin
  if (ThemeNotifier < 0) and Supports(BorlandIDEServices, IOTAIDEThemingServices, mTheming) then
  begin
    ThemeNotifier := mTheming.AddNotifier(TThemeNotifier.Create);
  end;
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
  mAbout: IOTAAboutBoxServices;
  mTheming: IOTAIDEThemingServices;
begin
  OnThemeChanged := nil;
  FreeAndNil(Later);
  FreeAndNil(Later_);
  if (ThemeNotifier >= 0) and Supports(BorlandIDEServices, IOTAIDEThemingServices, mTheming) then
  begin
    mTheming.RemoveNotifier(ThemeNotifier);
  end;
  ThemeNotifier := -1;
  if (AboutIndex >= 0) and Supports(BorlandIDEServices, IOTAAboutBoxServices, mAbout) then
  begin
    mAbout.RemovePluginInfo(AboutIndex);
  end;
  AboutIndex := -1;
  // Die Bilder bleiben in der Bildliste der IDE (sie lassen sich nicht entfernen); die Menüeinträge sind dann weg.
  FirstImage := -1;
  FreeAndNil(Images);
  FreeAndNil(Collection);
  TAtlasSymbolImages.ReleaseCache;
end;

end.
