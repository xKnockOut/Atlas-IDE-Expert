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
  Atlas.IDE.Commands.Keys,
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
  Atlas.IDE.Settings.Store,
  Atlas.IDE.Settings.Project,
  Atlas.IDE.Editor.Structure,
  Atlas.IDE.Editor.Style;

const
  AnswerSession = 100;
  AnswerProject = 101;

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
    FInstance := nil;
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
    FWindow := nil;
end;

procedure TAtlasIdeQuickToggles.Rebind;
var
  Settings: TAtlasPluginSettings;
begin
  Settings := TAtlasIdeSettings.Current;
  FKey.Rebind(Word(Settings.QuickToggleKey), Settings.QuickToggleKeyPriority,
    TAtlasStrings.Text(TAtlasTextId.SettingsQuickToggleKey));
end;

class function TAtlasIdeQuickToggles.Items: TArray<TAtlasQuickToggleItem>;
var
  Project: TJSONObject;
begin
  Project := nil;
  try
    try
      Project := TAtlasProjectSettings.ReadProject;
    except
      // Unlesbare Datei: Schalter ohne Projektwerte.
      on Exception do
        Project := nil;
    end;
    Result := TAtlasQuickToggles.Items(TAtlasIdeSettings.QuickToggles, TAtlasIdeSettings.Stored,
      TAtlasIdeSettings.Session, Project);
  finally
    Project.Free;
  end;
end;

class function TAtlasIdeQuickToggles.Checked(const AKey: string): Boolean;
var
  Item: TAtlasQuickToggleItem;
begin
  for Item in Items do
    if SameText(Item.Toggle.Key, AKey) then
      Exit(Item.Checked);
  Result := False;
end;

class function TAtlasIdeQuickToggles.AskTarget(const AItem: TAtlasQuickToggleItem;
  out ATarget: TAtlasToggleTarget): Boolean;
var
  Dialog: TTaskDialog;
  Button: TTaskDialogBaseButtonItem;
begin
  ATarget := TAtlasToggleTarget.Session;
  Dialog := TTaskDialog.Create(nil);
  try
    Dialog.Caption := 'Atlas';
    Dialog.Title := AItem.Toggle.Caption;
    Dialog.Text := TAtlasStrings.Fmt(TAtlasTextId.QuickToggleAskText, [AItem.Toggle.Caption]);
    Dialog.CommonButtons := [tcbCancel];
    Button := Dialog.Buttons.Add;
    Button.Caption := TAtlasStrings.Text(TAtlasTextId.QuickToggleAskSession);
    Button.ModalResult := AnswerSession;
    Button.Default := True;
    Button := Dialog.Buttons.Add;
    Button.Caption := TAtlasStrings.Text(TAtlasTextId.QuickToggleAskProject);
    Button.ModalResult := AnswerProject;
    Result := Dialog.Execute;
    if not Result then
      Exit;
    case Dialog.ModalResult of
      AnswerSession:
        ATarget := TAtlasToggleTarget.Session;
      AnswerProject:
        ATarget := TAtlasToggleTarget.Project;
    else
      Result := False;
    end;
  finally
    Dialog.Free;
  end;
end;

class procedure TAtlasIdeQuickToggles.SwitchItem(const AItem: TAtlasQuickToggleItem);
var
  Target: TAtlasToggleTarget;
  Stored: TAtlasPluginSettings;
  Session: TAtlasToggleSession;
  Json: string;
begin
  Target := TAtlasToggleTarget.Global;
  // Sitzungswert über einem Projektwert: ein weiterer Klick gilt wieder nur für die Sitzung.
  if AItem.Session then
    Target := TAtlasToggleTarget.Session
  else if AItem.Project and not AskTarget(AItem, Target) then
    Exit;
  Stored := TAtlasIdeSettings.Stored;
  Session := TAtlasIdeSettings.Session;
  Json := TAtlasQuickToggles.Toggle(AItem, Target, Stored, Session);
  if Target = TAtlasToggleTarget.Project then
    try
      TAtlasProjectSettings.WriteValue(AItem.Toggle.ProjectPath, Json);
    except
      on E: Exception do
      begin
        TAtlasGuard.Log(TAtlasStrings.Fmt(TAtlasTextId.QuickToggleWriteFailed, [E.ClassName]));
        MessageBox(Application.Handle, PChar(TAtlasStrings.Fmt(TAtlasTextId.QuickToggleWriteFailed, [E.Message])),
          'Atlas', MB_ICONWARNING or MB_OK);
        Exit;
      end;
    end;
  if Target = TAtlasToggleTarget.Global then
    TAtlasIdeSettings.Update(Stored);
  TAtlasIdeSettings.SetSession(Session);
  Applied;
end;

class procedure TAtlasIdeQuickToggles.Switch(const AKey: string);
var
  Item: TAtlasQuickToggleItem;
begin
  for Item in Items do
    if SameText(Item.Toggle.Key, AKey) then
    begin
      SwitchItem(Item);
      Exit;
    end;
end;

class procedure TAtlasIdeQuickToggles.ToggleAllOff;
var
  Session: TAtlasToggleSession;
begin
  Session := TAtlasIdeSettings.Session;
  Session.AllOff := not Session.AllOff;
  TAtlasIdeSettings.SetSession(Session);
  Applied;
end;

class procedure TAtlasIdeQuickToggles.Applied;
var
  Services: INTACodeEditorServices;
begin
  // Wie beim Schließen der Optionsseite: Strukturhervorhebung der IDE abgleichen, dann neu zeichnen.
  TAtlasIdeStructureSwitch.Sync;
  if Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    Services.InvalidateTopEditor;
  if FInstance <> nil then
    FInstance.Refresh;
end;

procedure TAtlasIdeQuickToggles.Refresh;
begin
  if FWindow <> nil then
    FWindow.SetItems(Items, TAtlasIdeSettings.Session.AllOff);
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
  Anchor: TPoint;
  Area: TRect;
begin
  Anchor := Point(MaxInt, MaxInt);
  if Assigned(FOnAnchor) then
    Anchor := FOnAnchor();
  if Anchor.X = MaxInt then
  begin
    // Ohne Statusfeld: unten links im aktiven Fenster.
    if Screen.ActiveForm <> nil then
      Area := Screen.ActiveForm.BoundsRect
    else if Application.MainForm <> nil then
      Area := Application.MainForm.BoundsRect
    else
      Area := Screen.WorkAreaRect;
    Anchor := Point(Area.Left + 40, Area.Bottom - 40);
  end;
  Show(Anchor);
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
  Toggle: TAtlasQuickToggle;
begin
  ARegistry.RegisterCommand('Atlas.QuickToggles', TAtlasStrings.Text(TAtlasTextId.QuickTogglePaletteOpen), '',
    procedure
    begin
      Show;
    end);
  ARegistry.RegisterCommand('Atlas.QuickToggles.AllOff', TAtlasStrings.Text(TAtlasTextId.QuickTogglesAllOff),
    TAtlasStrings.Text(TAtlasTextId.QuickTogglePaletteHint),
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.Settings,
        procedure
        begin
          ToggleAllOff;
        end);
    end);
  for Toggle in TAtlasIdeSettings.QuickToggles do
    ARegistry.RegisterCommand('Atlas.QuickToggles.' + Toggle.Key,
      TAtlasStrings.Fmt(TAtlasTextId.QuickTogglePalette, [Toggle.Caption]),
      TAtlasStrings.Text(TAtlasTextId.QuickTogglePaletteHint), SwitchCommand(Toggle.Key));
end;

end.
