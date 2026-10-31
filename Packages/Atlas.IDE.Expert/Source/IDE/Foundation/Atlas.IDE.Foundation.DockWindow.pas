unit Atlas.IDE.Foundation.DockWindow;

// Gemeinsame Verwaltung der Atlas-Dockfenster (#879) über
// INTAServices.CreateDockableForm: Ergebnisfenster, Atlas-Diagnose,
// Lesezeichen, Atlas-Start.
// - Die IDE gibt Dockfenster auch selbst frei (Entladen des Packages,
//   Desktop-Wechsel, Beenden). FreeNotification auf Form UND Frame setzt die
//   Zeiger zurück; Show legt dann neu an statt einen toten Frame zu benutzen.
// - Das X versteckt die Form, angedockt oft samt Dock-Gastgeber (Reiterseite,
//   Dock-Fenster). Form.Show allein bringt sie dann nicht zurück; Reveal macht
//   die ganze Gastgeberkette sichtbar und wählt die Reiterseite.
// - Persistent: RegisterDockableForm, damit die IDE das Fenster im Desktop
//   speichert und beim Laden selbst anlegt; die Form kommt dann über
//   FrameCreated herein. Registrieren muss früh geschehen (Register des
//   Experten), sonst kennt die IDE beim Laden des Start-Desktops die Kennung
//   noch nicht.
// Die Entscheidungen ohne VCL/OTA liegen in Atlas.Core.Dock.Plan (getestet).
// ApplyIdeTheme: Thema der IDE auf den Inhalt eines Atlas-Fensters, beim
// Anlegen und bei jedem Themenwechsel. ApplyTheme färbt nur Steuerelemente
// ohne Style-Hook (Labels, Panels); Listen, Felder, Combos und Kästchen
// zeichnet der VCL-Stil, den sie über StyleName vom Elternteil erben. Nach
// einem Wechsel lieferte diese Kette noch den alten Stil (Fenster blieben
// hell bzw. dunkel). Deshalb steht der Stil der IDE ausdrücklich an der
// Wurzel des Atlas-Fensters, alle Kinder erben; ein geänderter Name legt die
// Fenster mit dem neuen Stil neu an. Liefert die Wurzel danach trotzdem einen
// anderen Stil, steht die Kette im Protokoll.

interface

uses
  Winapi.Messages,
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  ToolsAPI;

type
  TAtlasIdeDockWindow = class(TComponent)
  private
    FDock: INTACustomDockableForm;
    FRegistered: Boolean;
    FForm: TCustomForm;
    FFrame: TCustomFrame;
    /// <summary>Ursprüngliche Fensterprozedur der Form (Haken für WM_CREATE beim Ab- und Andocken).</summary>
    FOldWndProc: TWndMethod;
    /// <summary>Formen aller Atlas-Dockfenster: Nur sie bekommen das Thema auch an der Form (schwebend).
    /// </summary>
    class var FDockForms: TArray<TCustomForm>;
    class function IsDockForm(AForm: TCustomForm): Boolean; static;
    /// <summary>Thema der IDE an der Form: Grund per ApplyTheme, bei dunklem Thema eine dunkle Titelleiste von
    /// Windows. Kein VCL-Stil an der Form: Der zeichnete die Titelleiste selbst und verlor beim Ziehen die
    /// Schaltflächen.</summary>
    class procedure ThemeForm(AForm: TCustomForm); static;
    /// <summary>Dunkle Titelleiste (DWM), solange das IDE-Thema dunkel ist; schwebend sichtbar.</summary>
    class procedure ApplyDarkCaption(AForm: TCustomForm); static;
    procedure FormWndProc(var AMessage: TMessage);
    procedure SetForm(AForm: TCustomForm);
    procedure FreeForm;
    procedure Reveal;
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    /// <summary>APersistent: bei der IDE registrieren (Desktop speichern/laden).</summary>
    constructor Create(const ADock: INTACustomDockableForm; APersistent: Boolean); reintroduce;
    /// <summary>Abmelden und die Form freigeben, falls sie noch lebt.</summary>
    destructor Destroy; override;
    /// <summary>Aus INTACustomDockableForm.FrameCreated aufrufen: merkt Frame und Form.</summary>
    procedure FrameCreated(AFrame: TCustomFrame);
    /// <summary>Fenster zeigen, bei Bedarf (neu) anlegen; ACreated: neu angelegt. False ohne Frame.</summary>
    function Show(out ACreated: Boolean): Boolean;
    /// <summary>Lebende Form oder nil.</summary>
    function Form: TCustomForm;
    /// <summary>Lebender Frame oder nil (nil auch, wenn die Form schon weg ist).</summary>
    function Frame: TCustomFrame;
    /// <summary>Wirklich zu sehen: Form und alle Gastgeber sichtbar, Reiterseite aktiv.</summary>
    function Shown: Boolean;
    procedure Hide;
    /// <summary>Thema der IDE auf AControl anwenden (beim Anlegen und bei jedem Themenwechsel).</summary>
    class procedure ApplyIdeTheme(AControl: TWinControl); static;
  end;

implementation

uses
  Winapi.Windows,
  Winapi.Dwmapi,
  System.SysUtils,
  Vcl.Graphics,
  Vcl.Themes,
  Vcl.ComCtrls,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Dock.Plan;

type
  // Zugriff auf das geschützte Color von TCustomForm.
  TFormAccess = class(TCustomForm);

{ TAtlasIdeDockWindow }

constructor TAtlasIdeDockWindow.Create(const ADock: INTACustomDockableForm; APersistent: Boolean);
var
  Services: INTAServices;
begin
  inherited Create(nil);
  FDock := ADock;
  if APersistent and Supports(BorlandIDEServices, INTAServices, Services) then
  begin
    Services.RegisterDockableForm(FDock);
    FRegistered := True;
  end;
end;

destructor TAtlasIdeDockWindow.Destroy;
var
  Services: INTAServices;
begin
  if FRegistered and Supports(BorlandIDEServices, INTAServices, Services) then
    Services.UnregisterDockableForm(FDock);
  FRegistered := False;
  FreeForm;
  FDock := nil;
  inherited;
end;

procedure TAtlasIdeDockWindow.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if Operation <> opRemove then
    Exit;
  if AComponent = FFrame then
    FFrame := nil;
  if AComponent = FForm then
  begin
    // Die IDE hat die Form freigegeben; ihr Frame ist mit ihr gegangen.
    SetForm(nil);
    FFrame := nil;
  end;
end;

class function TAtlasIdeDockWindow.IsDockForm(AForm: TCustomForm): Boolean;
var
  Form: TCustomForm;
begin
  Result := False;
  if AForm = nil then
    Exit;
  for Form in FDockForms do
    if Form = AForm then
      Exit(True);
end;

procedure TAtlasIdeDockWindow.SetForm(AForm: TCustomForm);
var
  Index: Integer;
begin
  if AForm = FForm then
    Exit;
  if FForm <> nil then
  begin
    FForm.RemoveFreeNotification(Self);
    if Assigned(FOldWndProc) then
      FForm.WindowProc := FOldWndProc;
    FOldWndProc := nil;
    for Index := High(FDockForms) downto 0 do
      if FDockForms[Index] = FForm then
        Delete(FDockForms, Index, 1);
  end;
  FForm := AForm;
  if FForm <> nil then
  begin
    FForm.FreeNotification(Self);
    if not IsDockForm(FForm) then
      FDockForms := FDockForms + [FForm];
    // Beim Ab- und Andocken legt die IDE das Fenster neu an; die Titelleiste muss dann neu dunkel werden.
    FOldWndProc := FForm.WindowProc;
    FForm.WindowProc := FormWndProc;
    ThemeForm(FForm);
  end;
end;

procedure TAtlasIdeDockWindow.FrameCreated(AFrame: TCustomFrame);
var
  ParentForm: TCustomForm;
begin
  if AFrame = nil then
    Exit;
  if (FFrame <> nil) and (FFrame <> AFrame) then
    FFrame.RemoveFreeNotification(Self);
  FFrame := AFrame;
  FFrame.FreeNotification(Self);
  // Legt die IDE die Form selbst an (Desktop laden), kennen wir sie nur über den Frame.
  if AFrame.Owner is TCustomForm then
    ParentForm := TCustomForm(AFrame.Owner)
  else
    ParentForm := GetParentForm(AFrame, False);
  if ParentForm <> nil then
    SetForm(ParentForm);
end;

procedure TAtlasIdeDockWindow.FreeForm;
var
  Old: TCustomForm;
begin
  Old := FForm;
  if FFrame <> nil then
    FFrame.RemoveFreeNotification(Self);
  FFrame := nil;
  SetForm(nil);
  // Nur freigeben, was noch lebt: Hat die IDE die Form schon zerstört, ist Old hier nil.
  Old.Free;
end;

function TAtlasIdeDockWindow.Show(out ACreated: Boolean): Boolean;
var
  Services: INTAServices;
  HasServices: Boolean;
  Step: TAtlasDockStep;
  Created: TCustomForm;
begin
  ACreated := False;
  HasServices := Supports(BorlandIDEServices, INTAServices, Services);
  Step := TAtlasDockPlan.ShowStep(HasServices, FForm <> nil, FFrame <> nil);
  if Step = TAtlasDockStep.Unavailable then
    Exit(False);
  if Step = TAtlasDockStep.RecreateForm then
    FreeForm;
  if Step <> TAtlasDockStep.RevealForm then
  begin
    // FrameCreated läuft schon während CreateDockableForm und setzt Frame und Form.
    Created := Services.CreateDockableForm(FDock);
    if Created = nil then
      Exit(False);
    SetForm(Created);
    ACreated := True;
  end;
  Reveal;
  Result := Frame <> nil;
end;

procedure TAtlasIdeDockWindow.Reveal;
var
  Host: TWinControl;
  Sheet: TTabSheet;
begin
  if FForm = nil then
    Exit;
  FForm.Visible := True;
  // Angedockt: Reiterseite wählen und versteckte Gastgeber (Dock-Fenster, Leisten) wieder zeigen.
  Host := FForm.Parent;
  while Host <> nil do
  begin
    if Host is TTabSheet then
    begin
      Sheet := TTabSheet(Host);
      if Sheet.PageControl <> nil then
        Sheet.PageControl.ActivePage := Sheet;
    end
    else if not Host.Visible then
      Host.Visible := True;
    Host := Host.Parent;
  end;
  FForm.BringToFront;
end;

function TAtlasIdeDockWindow.Form: TCustomForm;
begin
  Result := FForm;
end;

function TAtlasIdeDockWindow.Frame: TCustomFrame;
begin
  Result := nil;
  if TAtlasDockPlan.FrameUsable(FForm <> nil, FFrame <> nil) then
    Result := FFrame;
end;

function TAtlasIdeDockWindow.Shown: Boolean;
var
  Hosts: TArray<Boolean>;
  Host: TWinControl;
begin
  if FForm = nil then
    Exit(False);
  Hosts := nil;
  Host := FForm.Parent;
  while Host <> nil do
  begin
    Hosts := Hosts + [Host.Visible];
    Host := Host.Parent;
  end;
  Result := TAtlasDockPlan.Shown(FForm.Visible, Hosts);
end;

procedure TAtlasIdeDockWindow.Hide;
begin
  if FForm <> nil then
    FForm.Hide;
end;

class procedure TAtlasIdeDockWindow.ApplyIdeTheme(AControl: TWinControl);
var
  Theming: IOTAIDEThemingServices;
  Style: TCustomStyleServices;

  procedure ResetColors(AParent: TWinControl);
  var
    Index: Integer;
    Child: TControl;
  begin
    for Index := 0 to AParent.ControlCount - 1 do
    begin
      Child := AParent.Controls[Index];
      if Child is TListView then
      begin
        TListView(Child).Color := clWindow;
        TListView(Child).Font.Color := clWindowText;
      end
      else if Child is TTreeView then
      begin
        TTreeView(Child).Color := clWindow;
        TTreeView(Child).Font.Color := clWindowText;
      end;
      if Child is TWinControl then
        ResetColors(TWinControl(Child));
    end;
  end;

  procedure Inherit(AParent: TWinControl);
  var
    Index: Integer;
    Child: TControl;
  begin
    for Index := 0 to AParent.ControlCount - 1 do
    begin
      Child := AParent.Controls[Index];
      Child.StyleName := '';
      if Child is TWinControl then
        Inherit(TWinControl(Child));
    end;
  end;

  function Chain: string;
  var
    Control: TControl;
  begin
    Result := '';
    Control := AControl;
    while Control <> nil do
    begin
      Result := Result + Format(' < %s "%s"', [Control.ClassName, Control.StyleName]);
      Control := Control.Parent;
    end;
  end;

begin
  if (AControl = nil) or not Supports(BorlandIDEServices, IOTAIDEThemingServices, Theming) or
    not Theming.IDEThemingEnabled then
    Exit;
  ResetColors(AControl);
  Theming.ApplyTheme(AControl);
  Style := Theming.StyleServices;
  if Style = nil then
    Exit;
  Inherit(AControl);
  if TStyleManager.Style[Style.Name] = Style then
    AControl.StyleName := Style.Name;
  if StyleServices(AControl) <> Style then
    TAtlasGuard.Log(Format('Thema: %s zeichnet mit Stil "%s" statt "%s";%s', [AControl.ClassName,
      StyleServices(AControl).Name, Style.Name, Chain]));
  // Auch die Form eines Atlas-Dockfensters (schwebend sonst Titelleiste und Grund im Systemstil).
  if not (AControl is TCustomForm) and IsDockForm(GetParentForm(AControl, False)) then
    ThemeForm(GetParentForm(AControl, False));
end;

class procedure TAtlasIdeDockWindow.ApplyDarkCaption(AForm: TCustomForm);
const
  // Fehlt in Delphi 12 (Winapi.Dwmapi): ab Windows 10 20H1.
  DWMWA_USE_IMMERSIVE_DARK_MODE = 20;
var
  Theming: IOTAIDEThemingServices;
  Window: TColor;
  Dark: BOOL;
begin
  if (AForm = nil) or not AForm.HandleAllocated or
    not Supports(BorlandIDEServices, IOTAIDEThemingServices, Theming) or not Theming.IDEThemingEnabled or
    (Theming.StyleServices = nil) then
    Exit;
  // Dunkel, wenn der Fenstergrund des IDE-Stils dunkel ist (Helligkeit nach Rec. 601).
  Window := ColorToRGB(Theming.StyleServices.GetSystemColor(clWindow));
  Dark := (GetRValue(Window) * 299 + GetGValue(Window) * 587 + GetBValue(Window) * 114) div 1000 < 128;
  // Ältere Windows-Versionen kennen den Wert nicht und lehnen ihn ab: dann bleibt die Titelleiste hell.
  DwmSetWindowAttribute(AForm.Handle, DWMWA_USE_IMMERSIVE_DARK_MODE, @Dark, SizeOf(Dark));
end;

procedure TAtlasIdeDockWindow.FormWndProc(var AMessage: TMessage);
begin
  if Assigned(FOldWndProc) then
    FOldWndProc(AMessage);
  // Neu angelegtes Fenster (Ab- oder Andocken): Titelleiste wieder dunkel.
  if (AMessage.Msg = WM_CREATE) and (FForm <> nil) then
    try
      ApplyDarkCaption(FForm);
    except
      on E: Exception do
        TAtlasGuard.Log('Dunkle Titelleiste: ' + E.ClassName + ': ' + E.Message);
    end;
end;

class procedure TAtlasIdeDockWindow.ThemeForm(AForm: TCustomForm);
var
  Theming: IOTAIDEThemingServices;
begin
  if (AForm = nil) or not Supports(BorlandIDEServices, IOTAIDEThemingServices, Theming) or
    not Theming.IDEThemingEnabled then
    Exit;
  try
    Theming.ApplyTheme(AForm);
    // Der Frame ist durchsichtig und zeigt den Grund der Form; ApplyTheme setzt ihn nicht (schwebend hellgrau
    // unter weißer Schrift).
    if Theming.StyleServices <> nil then
      TFormAccess(AForm).Color := Theming.StyleServices.GetSystemColor(clBtnFace);
    ApplyDarkCaption(AForm);
  except
    // Thema ist Kosmetik: ein Fehler darf das Fenster nicht verhindern.
    on E: Exception do
      TAtlasGuard.Log(Format('Thema der Form %s: %s: %s', [AForm.ClassName, E.ClassName, E.Message]));
  end;
end;

end.
