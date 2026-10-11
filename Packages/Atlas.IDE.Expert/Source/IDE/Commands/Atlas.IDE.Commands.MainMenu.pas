unit Atlas.IDE.Commands.MainMenu;

// Hauptmenü „Atlas“ hinter „Tools“ (#227): Schnellschalter für die häufigsten
// Funktionen, darunter die Projekt-Einstellungen (atlas.json) und „Optionen…“,
// das die Seite Atlas unter Tools > Optionen öffnet. Die Schalter ändern die
// Plugin-Einstellungen wie die Optionsseite (Speichern, Strukturhervorhebung
// und Help Insight der IDE abgleichen); ihre Häkchen werden beim Öffnen des
// Menüs aus den aktuellen Einstellungen gesetzt.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Menus,
  Atlas.Core.Settings.Plugin;

type
{$SCOPEDENUMS ON}
  TAtlasToggle = (Enabled, HoverTooltip, PairColors, PairGuides, Problems);
{$SCOPEDENUMS OFF}

  TAtlasMainMenu = class
  private
    FRoot: TMenuItem;
    FToggles: array[TAtlasToggle] of TMenuItem;
    FEnableAll: TMenuItem;
    procedure EnableAllClick(Sender: TObject);
    procedure RootClick(Sender: TObject);
    procedure ToggleClick(Sender: TObject);
    procedure ProjectClick(Sender: TObject);
    procedure OptionsClick(Sender: TObject);
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Wert eines Schalters in ASettings.</summary>
    class function Get(const ASettings: TAtlasPluginSettings; AToggle: TAtlasToggle): Boolean; static;
    class procedure Put(var ASettings: TAtlasPluginSettings; AToggle: TAtlasToggle; AValue: Boolean); static;
  end;

implementation

uses
  Atlas.Core.Diagnostics.Guard,
  ToolsAPI,
  Atlas.UI.Strings,
  Atlas.IDE.Settings.Store,
  Atlas.IDE.Settings.Project,
  Atlas.IDE.Editor.Structure;

const
  // Name des Menüs „Tools“ in der IDE; Atlas steht dahinter, sonst am Ende.
  ToolsMenu = 'ToolsMenu';

function ToggleText(AToggle: TAtlasToggle): string;
begin
  case AToggle of
    TAtlasToggle.Enabled:
      Result := TAtlasStrings.Text(TAtlasTextId.MenuToggleEnabled);
    TAtlasToggle.HoverTooltip:
      Result := TAtlasStrings.Text(TAtlasTextId.MenuToggleHover);
    TAtlasToggle.PairColors:
      Result := TAtlasStrings.Text(TAtlasTextId.MenuTogglePairs);
    TAtlasToggle.PairGuides:
      Result := TAtlasStrings.Text(TAtlasTextId.MenuToggleGuides);
  else
    Result := TAtlasStrings.Text(TAtlasTextId.MenuToggleProblems);
  end;
end;

{ TAtlasMainMenu }

constructor TAtlasMainMenu.Create;
var
  Services: INTAServices;
  Toggle: TAtlasToggle;
  Item: TMenuItem;
  Index, Position: Integer;
begin
  inherited Create;
  if not Supports(BorlandIDEServices, INTAServices, Services) or (Services.MainMenu = nil) then
    Exit;
  FRoot := TMenuItem.Create(nil);
  FRoot.Name := 'AtlasMainMenu';
  FRoot.Caption := TAtlasStrings.Text(TAtlasTextId.MenuAtlas);
  FRoot.OnClick := RootClick;
  for Toggle := Low(TAtlasToggle) to High(TAtlasToggle) do
  begin
    Item := TMenuItem.Create(FRoot);
    Item.Caption := ToggleText(Toggle);
    Item.Tag := Ord(Toggle);
    Item.OnClick := ToggleClick;
    FRoot.Add(Item);
    FToggles[Toggle] := Item;
  end;
  FRoot.Add(NewLine);
  Item := TMenuItem.Create(FRoot);
  Item.Caption := TAtlasStrings.Text(TAtlasTextId.ProjectSettingsMenu);
  Item.OnClick := ProjectClick;
  FRoot.Add(Item);
  Item := TMenuItem.Create(FRoot);
  Item.Caption := TAtlasStrings.Text(TAtlasTextId.MenuOptions);
  Item.OnClick := OptionsClick;
  FRoot.Add(Item);
  // Nur sichtbar, wenn die Sicherung etwas abgeschaltet hat (#493).
  FEnableAll := TMenuItem.Create(FRoot);
  FEnableAll.OnClick := EnableAllClick;
  FEnableAll.Visible := False;
  FRoot.Add(FEnableAll);
  Position := Services.MainMenu.Items.Count;
  for Index := 0 to Services.MainMenu.Items.Count - 1 do
    if SameText(Services.MainMenu.Items[Index].Name, ToolsMenu) then
      Position := Index + 1;
  Services.MainMenu.Items.Insert(Position, FRoot);
end;

destructor TAtlasMainMenu.Destroy;
begin
  // Freigeben nimmt den Eintrag auch aus dem Hauptmenü.
  FreeAndNil(FRoot);
  inherited;
end;

class function TAtlasMainMenu.Get(const ASettings: TAtlasPluginSettings; AToggle: TAtlasToggle): Boolean;
begin
  case AToggle of
    TAtlasToggle.Enabled:
      Result := ASettings.Enabled;
    TAtlasToggle.HoverTooltip:
      Result := ASettings.HoverTooltip;
    TAtlasToggle.PairColors:
      Result := ASettings.PairColors;
    TAtlasToggle.PairGuides:
      Result := ASettings.PairGuides;
  else
    Result := ASettings.Problems;
  end;
end;

class procedure TAtlasMainMenu.Put(var ASettings: TAtlasPluginSettings; AToggle: TAtlasToggle; AValue: Boolean);
begin
  case AToggle of
    TAtlasToggle.Enabled:
      ASettings.Enabled := AValue;
    TAtlasToggle.HoverTooltip:
      ASettings.HoverTooltip := AValue;
    TAtlasToggle.PairColors:
      ASettings.PairColors := AValue;
    TAtlasToggle.PairGuides:
      ASettings.PairGuides := AValue;
  else
    ASettings.Problems := AValue;
  end;
end;

procedure TAtlasMainMenu.RootClick(Sender: TObject);
var
  Toggle: TAtlasToggle;
  Settings: TAtlasPluginSettings;
  Feature: TAtlasFeature;
  Names: string;
begin
  try
    Settings := TAtlasIdeSettings.Current;
    for Toggle := Low(TAtlasToggle) to High(TAtlasToggle) do
      FToggles[Toggle].Checked := Get(Settings, Toggle);
    Names := '';
    for Feature in TAtlasGuard.DisabledSet do
      if Names = '' then
        Names := TAtlasGuard.FeatureName(Feature)
      else
        Names := Names + ', ' + TAtlasGuard.FeatureName(Feature);
    FEnableAll.Visible := Names <> '';
    FEnableAll.Caption := TAtlasStrings.Fmt(TAtlasTextId.MenuEnableAll, [Names]);
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Menu, E);
  end;
end;

procedure TAtlasMainMenu.ToggleClick(Sender: TObject);
var
  Toggle: TAtlasToggle;
  Settings: TAtlasPluginSettings;
begin
  try
    Toggle := TAtlasToggle(TMenuItem(Sender).Tag);
    Settings := TAtlasIdeSettings.Current;
    Put(Settings, Toggle, not Get(Settings, Toggle));
    TAtlasIdeSettings.Update(Settings);
    // Wie beim Schließen der Optionsseite: Strukturhervorhebung und Help Insight der IDE abgleichen.
    TAtlasIdeStructureSwitch.Sync;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Menu, E);
  end;
end;

procedure TAtlasMainMenu.EnableAllClick(Sender: TObject);
begin
  TAtlasGuard.EnableAll;
end;

procedure TAtlasMainMenu.ProjectClick(Sender: TObject);
begin
  try
    TAtlasProjectSettings.Execute;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Settings, E);
  end;
end;

procedure TAtlasMainMenu.OptionsClick(Sender: TObject);
var
  Options: IOTAEnvironmentOptions140;
  Services: IOTAServices;
begin
  try
    if Supports(BorlandIDEServices, IOTAServices, Services) and
      Supports(Services.GetEnvironmentOptions, IOTAEnvironmentOptions140, Options) then
      Options.EditOptions('', 'Atlas');
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Settings, E);
  end;
end;

end.
