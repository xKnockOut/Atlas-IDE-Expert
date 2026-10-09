unit Argus.IDE.Editor.Style;

// Aussehen der Argus-Fenster in der IDE (#411, #412, #445): Hell oder Dunkel
// nach dem aktiven IDE-Thema, ersatzweise nach der Windows-Einstellung
// „App-Modus“; Schrift aus den Editoroptionen; Pixeldichte des Monitors am
// Caret mal Zoom des Editors (aus der Caret-Höhe, TArgusScaling). Wird bei
// jedem Öffnen eines Fensters abgefragt, sodass Thema, Monitor und Zoom ohne
// Neustart wirken.

interface

uses
  System.Types,
  Argus.Core.Style.Palette,
  Argus.UI.Popup.Window;

type
  TArgusIdeStyle = class
  public
    /// <summary>Farben passend zum IDE-Thema bzw. zu Windows.</summary>
    class function Colors: TArgusColors; static;
    /// <summary>Farben, Editorschrift und Skalierung auf AWindow übertragen. ACaret: Caret-Rechteck in
    /// Bildschirmkoordinaten (Monitor und Zoom). Liefert eine Zeile für das Diagnoseprotokoll.</summary>
    class function Apply(AWindow: TArgusPopupWindow; const ACaret: TRect): string; static;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.Win.Registry,
  Vcl.Graphics,
  ToolsAPI,
  Argus.Core.Style.Color,
  Argus.Core.Style.Scaling;

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

{ TArgusIdeStyle }

class function TArgusIdeStyle.Colors: TArgusColors;
var
  Theming: IOTAIDEThemingServices;
begin
  if Supports(BorlandIDEServices, IOTAIDEThemingServices, Theming) and Theming.IDEThemingEnabled then
    Exit(TArgusColors.ForBackground(TArgusColor(ColorToRGB(Theming.StyleServices.GetSystemColor(clWindow)))));
  if WindowsUsesLightApps then
    Result := TArgusColors.Light
  else
    Result := TArgusColors.Dark;
end;

class function TArgusIdeStyle.Apply(AWindow: TArgusPopupWindow; const ACaret: TRect): string;
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
  MonitorPPI := TArgusPopupWindow.MonitorPPI(ACaret.CenterPoint);
  TextHeight := TextHeightAt(FontName, FontSize, MonitorPPI);
  Zoom := TArgusScaling.ZoomFromCaret(ACaret.Height, TextHeight);
  AWindow.SetScaling(MonitorPPI, Zoom, FontName, FontSize);
  Result := Format('Darstellung: %s %d pt, Monitor %d dpi, Caret %d px, Text %d px, Zoom %.2f',
    [FontName, FontSize, MonitorPPI, ACaret.Height, TextHeight, Zoom]);
end;

end.
