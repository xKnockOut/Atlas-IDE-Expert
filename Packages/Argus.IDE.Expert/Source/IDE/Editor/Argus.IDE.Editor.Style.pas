unit Argus.IDE.Editor.Style;

// Aussehen der Argus-Fenster in der IDE (#411, #445): Hell oder Dunkel nach
// dem aktiven IDE-Thema, ersatzweise nach der Windows-Einstellung „App-Modus“;
// Schrift aus den Editoroptionen. Wird bei jedem Öffnen eines Fensters
// abgefragt, sodass ein Themawechsel ohne Neustart wirkt.

interface

uses
  Argus.Core.Style.Palette,
  Argus.UI.Popup.Window;

type
  TArgusIdeStyle = class
  public
    /// <summary>Farben passend zum IDE-Thema bzw. zu Windows.</summary>
    class function Colors: TArgusColors; static;
    /// <summary>Farben und Editorschrift auf AWindow übertragen.</summary>
    class procedure Apply(AWindow: TArgusPopupWindow); static;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.Win.Registry,
  Vcl.Graphics,
  ToolsAPI,
  Argus.Core.Style.Color;

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

class procedure TArgusIdeStyle.Apply(AWindow: TArgusPopupWindow);
var
  Editor: IOTAEditorServices;
begin
  AWindow.Colors := Colors;
  if Supports(BorlandIDEServices, IOTAEditorServices, Editor) and (Editor.EditOptions <> nil) then
  begin
    AWindow.Font.Name := Editor.EditOptions.FontName;
    AWindow.Font.Size := Editor.EditOptions.FontSize;
  end;
end;

end.
