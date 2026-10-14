unit Atlas.IDE.Editor.Style;

// Aussehen der Atlas-Fenster in der IDE (#411, #412, #445): Hell oder Dunkel
// nach dem aktiven IDE-Thema, ersatzweise nach der Windows-Einstellung
// „App-Modus“; Schrift aus den Editoroptionen; Pixeldichte des Monitors am
// Caret mal Zoom des Editors (aus der Caret-Höhe, TAtlasScaling). Wird bei
// jedem Öffnen eines Fensters abgefragt, sodass Thema, Monitor und Zoom ohne
// Neustart wirken.

interface

uses
  System.Types,
  Atlas.Core.Style.Palette,
  Atlas.UI.Popup.Window;

type
  TAtlasIdeStyle = class
  public
    /// <summary>Farben passend zum IDE-Thema bzw. zu Windows.</summary>
    class function Colors: TAtlasColors; static;
    /// <summary>Farben, Editorschrift und Skalierung auf AWindow übertragen. ACaret: Caret-Rechteck in
    /// Bildschirmkoordinaten (Monitor und Zoom). Liefert eine Zeile für das Diagnoseprotokoll.</summary>
    class function Apply(AWindow: TAtlasPopupWindow; const ACaret: TRect): string; static;
    /// <summary>Texthöhe der Editorschrift bei 96 dpi ohne Zoom (Bezug für Linienbreiten, #653).</summary>
    class function BaseTextHeight: Integer; static;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.Win.Registry,
  Vcl.Graphics,
  ToolsAPI,
  Atlas.Core.Style.Color,
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
