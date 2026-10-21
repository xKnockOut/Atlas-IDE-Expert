unit Atlas.IDE.Foundation.EditorStyle;

// Aussehen der Atlas-Fenster in der IDE (#411, #412, #445): Hell oder Dunkel
// nach dem aktiven IDE-Thema, ersatzweise nach der Windows-Einstellung
// „App-Modus“; Schrift aus den Editoroptionen; Pixeldichte des Monitors am
// Caret mal Zoom des Editors (aus der Caret-Höhe, TAtlasScaling). Wird bei
// jedem Öffnen eines Fensters abgefragt, sodass Thema, Monitor und Zoom ohne
// Neustart wirken.

interface

uses
  Winapi.Windows,
  System.Types,
  Vcl.Graphics,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.UI.Popup.Window;

type
  TAtlasIdeStyle = class
  public
    /// <summary>Farben passend zum IDE-Thema bzw. zu Windows.</summary>
    class function Colors: TAtlasColors; static;
    /// <summary>Farben für Leisten im Rahmen der IDE (Brotkrumenleiste): Fläche und Schrift wie die
    /// Werkzeugleisten des IDE-Themas (clBtnFace/clBtnText), ohne Thema die von Windows.</summary>
    class function ChromeColors: TAtlasColors; static;
    /// <summary>Farben, Editorschrift und Skalierung auf AWindow übertragen. ACaret: Caret-Rechteck in
    /// Bildschirmkoordinaten (Monitor und Zoom). Liefert eine Zeile für das Diagnoseprotokoll.</summary>
    class function Apply(AWindow: TAtlasPopupWindow; const ACaret: TRect): string; static;
    /// <summary>Texthöhe der Editorschrift bei 96 dpi ohne Zoom (Bezug für Linienbreiten, #653).</summary>
    class function BaseTextHeight: Integer; static;
    /// <summary>ARect halb durchsichtig mit AColor überziehen; der Text darunter bleibt lesbar.</summary>
    class procedure Blend(ADC: HDC; const ARect: TRect; AColor: COLORREF; AAlpha: Byte); static;
    /// <summary>Hintergrund des Editors an X, Y; ersatzweise die Pinselfarbe der Zeichenfläche.</summary>
    class function SampleBack(ACanvas: TCanvas; X, Y: Integer): TAtlasColor; static;
  end;

implementation

uses
  System.SysUtils,
  System.Win.Registry,
  ToolsAPI,
  Atlas.Core.Style.Scaling;

function WindowsUsesLightApps: Boolean;
var
  Registry: TRegistry;
begin
  Result := True;
  Registry := TRegistry.Create(KEY_READ);
  try
    Registry.RootKey := HKEY_CURRENT_USER;
    if Registry.OpenKeyReadOnly('Software\Microsoft\Windows\CurrentVersion\Themes\Personalize') and
      Registry.ValueExists('AppsUseLightTheme') then
      Result := Registry.ReadInteger('AppsUseLightTheme') <> 0;
  finally
    Registry.Free;
  end;
end;

/// <summary>Texthöhe der Schrift bei APPI ohne Zoom, in Gerätepixeln.</summary>
function TextHeightAt(const AFontName: string; AFontSize, APPI: Integer): Integer;
var
  Bitmap: TBitmap;
begin
  Bitmap := TBitmap.Create;
  try
    Bitmap.Canvas.Font.Name := AFontName;
    Bitmap.Canvas.Font.PixelsPerInch := APPI;
    Bitmap.Canvas.Font.Size := AFontSize;
    Result := Bitmap.Canvas.TextHeight('Wg');
  finally
    Bitmap.Free;
  end;
end;

{ TAtlasIdeStyle }

class procedure TAtlasIdeStyle.Blend(ADC: HDC; const ARect: TRect; AColor: COLORREF; AAlpha: Byte);
var
  Memory: HDC;
  Bitmap, Old: HBITMAP;
  Func: TBlendFunction;
begin
  if (ARect.Right <= ARect.Left) or (ARect.Bottom <= ARect.Top) then
    Exit;
  Memory := CreateCompatibleDC(ADC);
  Bitmap := CreateCompatibleBitmap(ADC, 1, 1);
  Old := SelectObject(Memory, Bitmap);
  try
    SetPixel(Memory, 0, 0, AColor);
    Func.BlendOp := AC_SRC_OVER;
    Func.BlendFlags := 0;
    Func.SourceConstantAlpha := AAlpha;
    Func.AlphaFormat := 0;
    AlphaBlend(ADC, ARect.Left, ARect.Top, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top, Memory, 0, 0, 1, 1,
      Func);
  finally
    SelectObject(Memory, Old);
    DeleteObject(Bitmap);
    DeleteDC(Memory);
  end;
end;

class function TAtlasIdeStyle.SampleBack(ACanvas: TCanvas; X, Y: Integer): TAtlasColor;
var
  Sample: COLORREF;
begin
  Sample := GetPixel(ACanvas.Handle, X, Y);
  if Sample = CLR_INVALID then
    Result := TAtlasColor(ColorToRGB(ACanvas.Brush.Color))
  else
    Result := TAtlasColor(Sample);
end;

class function TAtlasIdeStyle.Colors: TAtlasColors;
var
  Theming: IOTAIDEThemingServices;
begin
  if Supports(BorlandIDEServices, IOTAIDEThemingServices, Theming) and Theming.IDEThemingEnabled then
    Exit(TAtlasColors.ForBackground(TAtlasColor(ColorToRGB(Theming.StyleServices.GetSystemColor(clWindow)))));
  if WindowsUsesLightApps then
    Result := TAtlasColors.Light
  else
    Result := TAtlasColors.Dark;
end;

class function TAtlasIdeStyle.ChromeColors: TAtlasColors;
var
  Theming: IOTAIDEThemingServices;
begin
  if Supports(BorlandIDEServices, IOTAIDEThemingServices, Theming) and Theming.IDEThemingEnabled then
    Exit(TAtlasColors.ForChrome(TAtlasColor(ColorToRGB(Theming.StyleServices.GetSystemColor(clBtnFace))),
      TAtlasColor(ColorToRGB(Theming.StyleServices.GetSystemColor(clBtnText)))));
  Result := TAtlasColors.ForChrome(TAtlasColor(ColorToRGB(clBtnFace)), TAtlasColor(ColorToRGB(clBtnText)));
end;

class function TAtlasIdeStyle.BaseTextHeight: Integer;
var
  Editor: IOTAEditorServices;
begin
  if Supports(BorlandIDEServices, IOTAEditorServices, Editor) and (Editor.EditOptions <> nil) then
    Result := TextHeightAt(Editor.EditOptions.FontName, Editor.EditOptions.FontSize, 96)
  else
    Result := 16;
end;

class function TAtlasIdeStyle.Apply(AWindow: TAtlasPopupWindow; const ACaret: TRect): string;
var
  Editor: IOTAEditorServices;
  FontName: string;
  FontSize, MonitorPPI, TextHeight: Integer;
  Zoom: Double;
begin
  AWindow.Colors := Colors;
  FontName := AWindow.Font.Name;
  FontSize := AWindow.Font.Size;
  if Supports(BorlandIDEServices, IOTAEditorServices, Editor) and (Editor.EditOptions <> nil) then
  begin
    FontName := Editor.EditOptions.FontName;
    FontSize := Editor.EditOptions.FontSize;
  end;
  MonitorPPI := TAtlasPopupWindow.MonitorPPI(ACaret.CenterPoint);
  TextHeight := TextHeightAt(FontName, FontSize, MonitorPPI);
  Zoom := TAtlasScaling.ZoomFromCaret(ACaret.Height, TextHeight);
  AWindow.SetScaling(MonitorPPI, Zoom, FontName, FontSize);
  Result := Format('Darstellung: %s %d pt, Monitor %d dpi, Caret %d px, Text %d px, Zoom %.2f',
    [FontName, FontSize, MonitorPPI, ACaret.Height, TextHeight, Zoom]);
end;

end.
