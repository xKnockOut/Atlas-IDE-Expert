unit Atlas.IDE.Settings.QuickToggles;

// Schnellschalter für Atlas-Funktionen (#604) in der IDE:
// - Fenster TAtlasQuickToggleWindow über dem Atlas-Statusfeld (Rechtsklick
//   auf das Feld) oder über das Tastenkürzel (Vorgabe Strg+Umschalt+Alt+A,
//   änderbar auf der Seite „Tastenkonflikte“, #494).
// - In der Befehlspalette je Schalter „Atlas: … ein/aus“, dazu „Alles aus
//   für diese Sitzung“ und „Schnellschalter öffnen“.
// - Ein Schalter schreibt dieselbe globale Einstellung wie die Optionsseite
//   (Registry) und wirkt sofort. Setzt atlas.json des aktiven Projekts den
//   Wert, fragt Atlas, ob die Änderung nur für diese Sitzung oder im Projekt
//   gelten soll.
// - „Alles aus für diese Sitzung“ schaltet alle Zeichnungen (x-drawing) ab,
//   ohne die gespeicherten Einstellungen zu ändern; der nächste Klick stellt
//   sie wieder her.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Atlas.Core.Settings.QuickToggles,
  Atlas.UI.Settings.QuickToggles,
  Atlas.IDE.Foundation.Keys,
  Atlas.Core.Commands.Palette;

type
  TAtlasIdeQuickToggles = class(TComponent)
  private class var
    FInstance: TAtlasIdeQuickToggles;
  private
    FKey: TAtlasIdeKeyBinding;
    FWindow: TAtlasQuickToggleWindow;
    FOnAnchor: TFunc<TPoint>;
    procedure Refresh;
    class procedure Applied; static;
    class function AskTarget(const AItem: TAtlasQuickToggleItem; out ATarget: TAtlasToggleTarget): Boolean; static;
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>Schalter mit Zustand: gespeicherte Werte, atlas.json des aktiven Projekts, Sitzungswerte.</summary>
    class function Items: TArray<TAtlasQuickToggleItem>; static;
    /// <summary>Schalter AKey umschalten (Palette, Menü Atlas); bei Projektwert mit Nachfrage.</summary>
    class procedure Switch(const AKey: string); static;
    class procedure SwitchItem(const AItem: TAtlasQuickToggleItem); static;
    /// <summary>„Alles aus für diese Sitzung“ bzw. wieder an.</summary>
    class procedure ToggleAllOff; static;
    /// <summary>Wirksamer Zustand von AKey wie im Fenster (Sitzung, Projekt, gespeichert).</summary>
    class function Checked(const AKey: string): Boolean; static;
    /// <summary>Tastenkürzel nach den Einstellungen (neu) belegen (#494).</summary>
    procedure Rebind;
    /// <summary>Fenster mit der linken unteren Ecke an AAnchor öffnen; offen: schließen.</summary>
    procedure Show(const AAnchor: TPoint); overload;
    /// <summary>Über dem Statusfeld (OnAnchor), sonst unten links im aktiven Fenster.</summary>
    procedure Show; overload;
    /// <summary>Befehle in der Palette anmelden; ARegistry nicht speichern.</summary>
    procedure RegisterCommands(const ARegistry: IAtlasCommandRegistry);
    /// <summary>Linke Oberkante des Statusfelds im obersten Editorfenster; (MaxInt, MaxInt) ohne Feld.</summary>
    property OnAnchor: TFunc<TPoint> read FOnAnchor write FOnAnchor;
  end;

implementation

uses
  Winapi.Windows,
  System.JSON,
  Vcl.Forms,
  Vcl.Dialogs,
  Vcl.Controls,
  ToolsAPI,
  ToolsAPI.Editor,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Diagnostics.Guard,
  Atlas.UI.Strings,
  Atlas.UI.Settings.Strings,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Settings.Project,
  Atlas.IDE.Foundation.StructureSwitch,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.EditorRefresh,
  Atlas.IDE.Settings.Options;

const
  cAnswerSession = 100;
  cAnswerProject = 101;

{ TAtlasIdeQuickToggles }

constructor TAtlasIdeQuickToggles.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FInstance := Self;
  FKey := TAtlasIdeKeyBinding.Create('Atlas.QuickToggles', 'Atlas-Schnellschalter', TAtlasFeature.Settings,
    procedure
    begin
      Show;
    end);
  Rebind;
end;

destructor TAtlasIdeQuickToggles.Destroy;
begin
  if FInstance = Self then
  begin
    FInstance := nil;
  end;
  FreeAndNil(FKey);
  if FWindow <> nil then
  begin
    FWindow.RemoveFreeNotification(Self);
    FreeAndNil(FWindow);
  end;
  inherited;
end;

procedure TAtlasIdeQuickToggles.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if (Operation = opRemove) and (AComponent = FWindow) then
  begin
    FWindow := nil;
  end;
end;

procedure TAtlasIdeQuickToggles.Rebind;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  FKey.Rebind(Word(mSettings.QuickToggleKey), mSettings.QuickToggleKeyPriority,
    TAtlasStrings.Text(TAtlasTextId.SettingsQuickToggleKey));
end;

class function TAtlasIdeQuickToggles.Items: TArray<TAtlasQuickToggleItem>;
var
  mProject: TJSONObject;
begin
  mProject := nil;
  try
    try
      mProject := TAtlasProjectSettings.ReadProject;
    except
      // Unlesbare Datei: Schalter ohne Projektwerte.
      on Exception do
        mProject := nil;
    end;
    Result := TAtlasQuickToggles.Items(TAtlasIdeSettings.QuickToggles, TAtlasIdeSettings.Stored,
      TAtlasIdeSettings.Session, mProject);
  finally
    mProject.Free;
  end;
end;

class function TAtlasIdeQuickToggles.Checked(const AKey: string): Boolean;
var
  mItem: TAtlasQuickToggleItem;
begin
  for mItem in Items do
  begin
    if SameText(mItem.Toggle.Key, AKey) then
    begin
      Exit(mItem.Checked);
    end;
  end;
  Result := False;
end;

class function TAtlasIdeQuickToggles.AskTarget(const AItem: TAtlasQuickToggleItem;
  out ATarget: TAtlasToggleTarget): Boolean;
var
  mDialog: TTaskDialog;
  mButton: TTaskDialogBaseButtonItem;
begin
  ATarget := TAtlasToggleTarget.Session;
  mDialog := TTaskDialog.Create(nil);
  try
    mDialog.Caption := 'Atlas';
    mDialog.Title := AItem.Toggle.Caption;
    mDialog.Text := TAtlasSettingsStrings.Fmt(TAtlasSettingsTextId.QuickToggleAskText, [AItem.Toggle.Caption]);
    mDialog.CommonButtons := [tcbCancel];
    mButton := mDialog.Buttons.Add;
    mButton.Caption := TAtlasSettingsStrings.Text(TAtlasSettingsTextId.QuickToggleAskSession);
    mButton.ModalResult := cAnswerSession;
    mButton.Default := True;
    mButton := mDialog.Buttons.Add;
    mButton.Caption := TAtlasSettingsStrings.Text(TAtlasSettingsTextId.QuickToggleAskProject);
    mButton.ModalResult := cAnswerProject;
    Result := mDialog.Execute;
    if not Result then
    begin
      Exit;
    end;
    case mDialog.ModalResult of
      cAnswerSession:
        ATarget := TAtlasToggleTarget.Session;
      cAnswerProject:
        ATarget := TAtlasToggleTarget.Project;
    else
      Result := False;
    end;
  finally
    mDialog.Free;
  end;
end;

class procedure TAtlasIdeQuickToggles.SwitchItem(const AItem: TAtlasQuickToggleItem);
var
  mTarget: TAtlasToggleTarget;
  mStored: TAtlasPluginSettings;
  mSession: TAtlasToggleSession;
  mJson: string;
begin
  mTarget := TAtlasToggleTarget.Global;
  // Sitzungswert über einem Projektwert: ein weiterer Klick gilt wieder nur für die Sitzung.
  if AItem.Session then
  begin
    mTarget := TAtlasToggleTarget.Session;
  end
  else if AItem.Project and not AskTarget(AItem, mTarget) then
  begin
    Exit;
  end;
  mStored := TAtlasIdeSettings.Stored;
  mSession := TAtlasIdeSettings.Session;
  mJson := TAtlasQuickToggles.Toggle(AItem, mTarget, mStored, mSession);
  if mTarget = TAtlasToggleTarget.Project then
    try
      TAtlasProjectSettings.WriteValue(AItem.Toggle.ProjectPath, mJson);
    except
      on E: Exception do
      begin
        TAtlasGuard.Log(TAtlasSettingsStrings.Fmt(TAtlasSettingsTextId.QuickToggleWriteFailed, [E.ClassName]));
        MessageBox(Application.Handle, PChar(TAtlasSettingsStrings.Fmt(TAtlasSettingsTextId.QuickToggleWriteFailed,
          [E.Message])),
          'Atlas', MB_ICONWARNING or MB_OK);
        Exit;
      end;
    end;
  if mTarget = TAtlasToggleTarget.Global then
  begin
    TAtlasIdeSettings.Update(mStored);
  end;
  TAtlasIdeSettings.SetSession(mSession);
  Applied;
end;

class procedure TAtlasIdeQuickToggles.Switch(const AKey: string);
var
  mItem: TAtlasQuickToggleItem;
begin
  for mItem in Items do
  begin
    if SameText(mItem.Toggle.Key, AKey) then
    begin
      SwitchItem(mItem);
      Exit;
    end;
  end;
end;

class procedure TAtlasIdeQuickToggles.ToggleAllOff;
var
  mSession: TAtlasToggleSession;
begin
  mSession := TAtlasIdeSettings.Session;
  mSession.AllOff := not mSession.AllOff;
  TAtlasIdeSettings.SetSession(mSession);
  Applied;
end;

class procedure TAtlasIdeQuickToggles.Applied;
var
  mServices: INTACodeEditorServices;
begin
  // Wie beim Schließen der Optionsseite: Strukturhervorhebung der IDE abgleichen, dann neu zeichnen.
  TAtlasIdeStructureSwitch.Sync;
  if Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    TAtlasIdeEditorRefresh.InvalidateTop(mServices);
  end;
  if FInstance <> nil then
  begin
    FInstance.Refresh;
  end;
end;

procedure TAtlasIdeQuickToggles.Refresh;
begin
  if FWindow <> nil then
  begin
    FWindow.SetItems(Items, TAtlasIdeSettings.Session.AllOff);
  end;
end;

procedure TAtlasIdeQuickToggles.Show(const AAnchor: TPoint);
begin
  // Zweiter Aufruf schließt.
  if FWindow <> nil then
  begin
    FWindow.Dismiss;
    Exit;
  end;
  FWindow := TAtlasQuickToggleWindow.CreateToggles(Application, TAtlasIdeStyle.Colors);
  FWindow.FreeNotification(Self);
  FWindow.OnToggle :=
    procedure(AItem: TAtlasQuickToggleItem)
    begin
      TAtlasGuard.Run(TAtlasFeature.Settings,
        procedure
        begin
          SwitchItem(AItem);
        end);
    end;
  // Symbol rechts: Tools › Optionen › Atlas an dieser Einstellung öffnen und markieren (#628).
  FWindow.OnOpenSetting :=
    procedure(AItem: TAtlasQuickToggleItem)
    begin
      TAtlasGuard.Run(TAtlasFeature.Settings,
        procedure
        begin
          TAtlasOptionsRegistration.ShowSetting(AItem.Toggle.Key);
        end);
    end;
  FWindow.OnAllOff :=
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.Settings,
        procedure
        begin
          ToggleAllOff;
        end);
    end;
  FWindow.SetItems(Items, TAtlasIdeSettings.Session.AllOff);
  FWindow.ShowAbove(AAnchor);
end;

procedure TAtlasIdeQuickToggles.Show;
var
  mAnchor: TPoint;
  mArea: TRect;
begin
  mAnchor := Point(MaxInt, MaxInt);
  if Assigned(FOnAnchor) then
  begin
    mAnchor := FOnAnchor();
  end;
  if mAnchor.X = MaxInt then
  begin
    // Ohne Statusfeld: unten links im aktiven Fenster.
    if Screen.ActiveForm <> nil then
    begin
      mArea := Screen.ActiveForm.BoundsRect;
    end
    else if Application.MainForm <> nil then
    begin
      mArea := Application.MainForm.BoundsRect;
    end
    else
    begin
      mArea := Screen.WorkAreaRect;
    end;
    mAnchor := Point(mArea.Left + 40, mArea.Bottom - 40);
  end;
  Show(mAnchor);
end;

/// <summary>Befehl für einen Schalter; eigene Funktion, damit jeder Befehl seinen Schlüssel festhält.</summary>
function SwitchCommand(const AKey: string): TProc;
begin
  Result :=
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.Settings,
        procedure
        begin
          TAtlasIdeQuickToggles.Switch(AKey);
        end);
    end;
end;

procedure TAtlasIdeQuickToggles.RegisterCommands(const ARegistry: IAtlasCommandRegistry);
var
  mToggle: TAtlasQuickToggle;
begin
  ARegistry.RegisterCommand('Atlas.QuickToggles',
    TAtlasSettingsStrings.Text(TAtlasSettingsTextId.QuickTogglePaletteOpen), '',
    procedure
    begin
      Show;
    end);
  ARegistry.RegisterCommand('Atlas.QuickToggles.AllOff',
    TAtlasSettingsStrings.Text(TAtlasSettingsTextId.QuickTogglesAllOff),
    TAtlasSettingsStrings.Text(TAtlasSettingsTextId.QuickTogglePaletteHint),
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.Settings,
        procedure
        begin
          ToggleAllOff;
        end);
    end);
  for mToggle in TAtlasIdeSettings.QuickToggles do
  begin
    ARegistry.RegisterCommand('Atlas.QuickToggles.' + mToggle.Key,
      TAtlasSettingsStrings.Fmt(TAtlasSettingsTextId.QuickTogglePalette, [mToggle.Caption]),
      TAtlasSettingsStrings.Text(TAtlasSettingsTextId.QuickTogglePaletteHint), SwitchCommand(mToggle.Key));
  end;
end;

end.
