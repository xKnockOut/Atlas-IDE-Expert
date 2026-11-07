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
    class function SampleBack(ACanvas: TCanvas; AX, AY: Integer): TAtlasColor; static;
  end;

implementation

uses
  System.SysUtils,
  System.Win.Registry,
  ToolsAPI,
  Atlas.Core.Style.Scaling;

function WindowsUsesLightApps: Boolean;
var
  mRegistry: TRegistry;
begin
  Result := True;
  mRegistry := TRegistry.Create(KEY_READ);
  try
    mRegistry.RootKey := HKEY_CURRENT_USER;
    if mRegistry.OpenKeyReadOnly('Software\Microsoft\Windows\CurrentVersion\Themes\Personalize') and
      mRegistry.ValueExists('AppsUseLightTheme') then
    begin
      Result := mRegistry.ReadInteger('AppsUseLightTheme') <> 0;
    end;
  finally
    mRegistry.Free;
  end;
end;

/// <summary>Texthöhe der Schrift bei APPI ohne Zoom, in Gerätepixeln.</summary>
function TextHeightAt(const AFontName: string; AFontSize, APPI: Integer): Integer;
var
  mBitmap: TBitmap;
begin
  mBitmap := TBitmap.Create;
  try
    mBitmap.Canvas.Font.Name := AFontName;
    mBitmap.Canvas.Font.PixelsPerInch := APPI;
    mBitmap.Canvas.Font.Size := AFontSize;
    Result := mBitmap.Canvas.TextHeight('Wg');
  finally
    mBitmap.Free;
  end;
end;

{ TAtlasIdeStyle }

class procedure TAtlasIdeStyle.Blend(ADC: HDC; const ARect: TRect; AColor: COLORREF; AAlpha: Byte);
var
  mMemory: HDC;
  mBitmap, mOld: HBITMAP;
  mFunc: TBlendFunction;
begin
  if (ARect.Right <= ARect.Left) or (ARect.Bottom <= ARect.Top) then
  begin
    Exit;
  end;
  mMemory := CreateCompatibleDC(ADC);
  mBitmap := CreateCompatibleBitmap(ADC, 1, 1);
  mOld := SelectObject(mMemory, mBitmap);
  try
    SetPixel(mMemory, 0, 0, AColor);
    mFunc.BlendOp := AC_SRC_OVER;
    mFunc.BlendFlags := 0;
    mFunc.SourceConstantAlpha := AAlpha;
    mFunc.AlphaFormat := 0;
    AlphaBlend(ADC, ARect.Left, ARect.Top, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top, mMemory, 0, 0, 1, 1,
      mFunc);
  finally
    SelectObject(mMemory, mOld);
    DeleteObject(mBitmap);
    DeleteDC(mMemory);
  end;
end;

class function TAtlasIdeStyle.SampleBack(ACanvas: TCanvas; AX, AY: Integer): TAtlasColor;
var
  mSample: COLORREF;
begin
  mSample := GetPixel(ACanvas.Handle, AX, AY);
  if mSample = CLR_INVALID then
  begin
    Result := TAtlasColor(ColorToRGB(ACanvas.Brush.Color));
  end
  else
  begin
    Result := TAtlasColor(mSample);
  end;
end;

class function TAtlasIdeStyle.Colors: TAtlasColors;
var
  mTheming: IOTAIDEThemingServices;
begin
  if Supports(BorlandIDEServices, IOTAIDEThemingServices, mTheming) and mTheming.IDEThemingEnabled then
  begin
    Exit(TAtlasColors.ForBackground(TAtlasColor(ColorToRGB(mTheming.StyleServices.GetSystemColor(clWindow)))));
  end;
  if WindowsUsesLightApps then
  begin
    Result := TAtlasColors.Light;
  end
  else
  begin
    Result := TAtlasColors.Dark;
  end;
end;

class function TAtlasIdeStyle.ChromeColors: TAtlasColors;
var
  mTheming: IOTAIDEThemingServices;
begin
  if Supports(BorlandIDEServices, IOTAIDEThemingServices, mTheming) and mTheming.IDEThemingEnabled then
  begin
    Exit(TAtlasColors.ForChrome(TAtlasColor(ColorToRGB(mTheming.StyleServices.GetSystemColor(clBtnFace))),
      TAtlasColor(ColorToRGB(mTheming.StyleServices.GetSystemColor(clBtnText)))));
  end;
  Result := TAtlasColors.ForChrome(TAtlasColor(ColorToRGB(clBtnFace)), TAtlasColor(ColorToRGB(clBtnText)));
end;

class function TAtlasIdeStyle.BaseTextHeight: Integer;
var
  mEditor: IOTAEditorServices;
begin
  if Supports(BorlandIDEServices, IOTAEditorServices, mEditor) and (mEditor.EditOptions <> nil) then
  begin
    Result := TextHeightAt(mEditor.EditOptions.FontName, mEditor.EditOptions.FontSize, 96);
  end
  else
  begin
    Result := 16;
  end;
end;

class function TAtlasIdeStyle.Apply(AWindow: TAtlasPopupWindow; const ACaret: TRect): string;
var
  mEditor: IOTAEditorServices;
  mFontName: string;
  mFontSize, mMonitorPPI, mTextHeight: Integer;
  mZoom: Double;
begin
  AWindow.Colors := Colors;
  mFontName := AWindow.Font.Name;
  mFontSize := AWindow.Font.Size;
  if Supports(BorlandIDEServices, IOTAEditorServices, mEditor) and (mEditor.EditOptions <> nil) then
  begin
    mFontName := mEditor.EditOptions.FontName;
    mFontSize := mEditor.EditOptions.FontSize;
  end;
  mMonitorPPI := TAtlasPopupWindow.MonitorPPI(ACaret.CenterPoint);
  mTextHeight := TextHeightAt(mFontName, mFontSize, mMonitorPPI);
  mZoom := TAtlasScaling.ZoomFromCaret(ACaret.Height, mTextHeight);
  AWindow.SetScaling(mMonitorPPI, mZoom, mFontName, mFontSize);
  Result := Format('Darstellung: %s %d pt, Monitor %d dpi, Caret %d px, Text %d px, Zoom %.2f',
    [mFontName, mFontSize, mMonitorPPI, ACaret.Height, mTextHeight, mZoom], TFormatSettings.Invariant);
end;

end.
