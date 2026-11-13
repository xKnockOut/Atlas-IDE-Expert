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
// zeichnet der VCL-Stil, den sie über StyleName vom Elternteil erben. Die
// geerbte Kette kann nach einem Themenwechsel noch den alten Stil liefern
// (Fenster bleiben hell bzw. dunkel). Deshalb steht der Stil der IDE ausdrücklich an der
// Wurzel des Atlas-Fensters, alle Kinder erben; ein geänderter Name legt die
// Fenster mit dem neuen Stil neu an. Liefert die Wurzel danach trotzdem einen
// anderen Stil, steht die Kette im Protokoll.
// OnFrameCreated meldet jeden neu angelegten Frame mit der Kennung des Fensters; so hängen andere Teile von
// Base (F1-Hilfe, #1886) etwas an, ohne dass die Grundlage sie kennt.

interface

uses
  Winapi.Messages,
  System.Classes,
  System.SysUtils,
  Vcl.Controls,
  Vcl.Forms,
  ToolsAPI,
  Atlas.UI.Foundation.WndProcHook;

type
  TAtlasIdeDockWindow = class(TComponent)
  private
    FDock: INTACustomDockableForm;
    FRegistered: Boolean;
    FForm: TCustomForm;
    FFrame: TCustomFrame;
    /// <summary>Eingehängte Fensterprozedur der Form (WM_CREATE beim Ab- und Andocken); nil ohne Form.</summary>
    FWndHook: TAtlasWndProcHook;
    /// <summary>Formen aller Atlas-Dockfenster: Nur sie bekommen das Thema auch an der Form (schwebend).
    /// </summary>
    class var FDockForms: TArray<TCustomForm>;
    class var FOnFrameCreated: TProc<string, TCustomFrame>;
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
    /// <summary>Atlas-Symbol (#751) als Icon der Form von AHost (Fenstertitel, schwebend); nichts ohne Fenster
    /// oder Form.</summary>
    class procedure UpdateIcon(AHost: TAtlasIdeDockWindow); static;
    /// <summary>Aus INTACustomDockableForm.FrameCreated aufrufen: merkt Frame und Form.</summary>
    procedure FrameCreated(AFrame: TCustomFrame);
    /// <summary>Fenster zeigen, bei Bedarf (neu) anlegen, ein neues mit Atlas-Symbol; ACreated: neu angelegt.
    /// False ohne Frame.</summary>
    function Show(out ACreated: Boolean): Boolean;
    /// <summary>Wie Show, ohne zu fragen, ob neu angelegt.</summary>
    procedure Present;
    /// <summary>Lebende Form oder nil.</summary>
    function Form: TCustomForm;
    /// <summary>Lebender Frame oder nil (nil auch, wenn die Form schon weg ist).</summary>
    function Frame: TCustomFrame;
    /// <summary>Wirklich zu sehen: Form und alle Gastgeber sichtbar, Reiterseite aktiv.</summary>
    function Shown: Boolean;
    procedure Hide;
    /// <summary>Shown von AHost; False ohne AHost (Fenster nie angelegt).</summary>
    class function IsShown(AHost: TAtlasIdeDockWindow): Boolean; static;
    /// <summary>AHost verstecken; nichts ohne AHost.</summary>
    class procedure HideIfAny(AHost: TAtlasIdeDockWindow); static;
    /// <summary>Thema der IDE auf AControl anwenden (beim Anlegen und bei jedem Themenwechsel).</summary>
    class procedure ApplyIdeTheme(AControl: TWinControl); static;
    /// <summary>Rückruf für jeden neuen Frame (Kennung des Fensters, Frame); nur im Hauptthread.</summary>
    class property OnFrameCreated: TProc<string, TCustomFrame> read FOnFrameCreated write FOnFrameCreated;
  end;

implementation

uses
  Winapi.Windows,
  Winapi.Dwmapi,
  Vcl.Graphics,
  Vcl.Themes,
  Vcl.ComCtrls,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Dock.Plan,
  Atlas.UI.Style.Symbol,
  Atlas.IDE.Foundation.Symbol;

type
  // Zugriff auf das geschützte Color von TCustomForm.
  TFormAccess = class(TCustomForm);

{ TAtlasIdeDockWindow }

class procedure TAtlasIdeDockWindow.UpdateIcon(AHost: TAtlasIdeDockWindow);
var
  mIcon: TIcon;
begin
  if (AHost = nil) or (AHost.Form = nil) then
  begin
    Exit;
  end;
  mIcon := TAtlasSymbolImages.Icon(TAtlasIdeSymbol.Current);
  try
    // Icon ist erst in TForm öffentlich.
    TForm(AHost.Form).Icon.Assign(mIcon);
  finally
    mIcon.Free;
  end;
end;

constructor TAtlasIdeDockWindow.Create(const ADock: INTACustomDockableForm; APersistent: Boolean);
var
  mServices: INTAServices;
begin
  inherited Create(nil);
  FDock := ADock;
  if APersistent and Supports(BorlandIDEServices, INTAServices, mServices) then
  begin
    mServices.RegisterDockableForm(FDock);
    FRegistered := True;
  end;
end;

destructor TAtlasIdeDockWindow.Destroy;
var
  mServices: INTAServices;
begin
  if FRegistered and Supports(BorlandIDEServices, INTAServices, mServices) then
  begin
    mServices.UnregisterDockableForm(FDock);
  end;
  FRegistered := False;
  FreeForm;
  FDock := nil;
  inherited;
end;

procedure TAtlasIdeDockWindow.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if Operation <> opRemove then
  begin
    Exit;
  end;
  if AComponent = FFrame then
  begin
    FFrame := nil;
  end;
  if AComponent = FForm then
  begin
    // Die IDE hat die Form freigegeben; ihr Frame ist mit ihr gegangen.
    SetForm(nil);
    FFrame := nil;
  end;
end;

class function TAtlasIdeDockWindow.IsDockForm(AForm: TCustomForm): Boolean;
var
  mForm: TCustomForm;
begin
  Result := False;
  if AForm = nil then
  begin
    Exit;
  end;
  for mForm in FDockForms do
  begin
    if mForm = AForm then
    begin
      Exit(True);
    end;
  end;
end;

procedure TAtlasIdeDockWindow.SetForm(AForm: TCustomForm);
var
  mIndex: Integer;
begin
  if AForm = FForm then
  begin
    Exit;
  end;
  if FForm <> nil then
  begin
    FForm.RemoveFreeNotification(Self);
    // Liegt eine fremde Prozedur darüber, bleibt der Haken als Durchreicher in deren Kette; Unhook kennzeichnet
    // das Entladen dann als unsicher (Protokoll, Diagnose, Neustart).
    TAtlasWndProcHook.Unhook(FWndHook);
    for mIndex := High(FDockForms) downto 0 do
    begin
      if FDockForms[mIndex] = FForm then
      begin
        Delete(FDockForms, mIndex, 1);
      end;
    end;
  end;
  FForm := AForm;
  if FForm <> nil then
  begin
    FForm.FreeNotification(Self);
    if not IsDockForm(FForm) then
    begin
      FDockForms := FDockForms + [FForm];
    end;
    // Beim Ab- und Andocken legt die IDE das Fenster neu an; die Titelleiste muss dann neu dunkel werden.
    FWndHook := TAtlasWndProcHook.Create(FForm, FormWndProc);
    ThemeForm(FForm);
  end;
end;

procedure TAtlasIdeDockWindow.FrameCreated(AFrame: TCustomFrame);
var
  mParentForm: TCustomForm;
begin
  if AFrame = nil then
  begin
    Exit;
  end;
  if (FFrame <> nil) and (FFrame <> AFrame) then
  begin
    FFrame.RemoveFreeNotification(Self);
  end;
  if (FFrame <> AFrame) and Assigned(FOnFrameCreated) and (FDock <> nil) then
  begin
    FOnFrameCreated(FDock.GetIdentifier, AFrame);
  end;
  FFrame := AFrame;
  FFrame.FreeNotification(Self);
  // Legt die IDE die Form selbst an (Desktop laden), kennen wir sie nur über den Frame.
  if AFrame.Owner is TCustomForm then
  begin
    mParentForm := TCustomForm(AFrame.Owner);
  end
  else
  begin
    mParentForm := GetParentForm(AFrame, False);
  end;
  if mParentForm <> nil then
  begin
    SetForm(mParentForm);
  end;
end;

procedure TAtlasIdeDockWindow.FreeForm;
var
  mOld: TCustomForm;
begin
  mOld := FForm;
  if FFrame <> nil then
  begin
    FFrame.RemoveFreeNotification(Self);
  end;
  FFrame := nil;
  SetForm(nil);
  // Nur freigeben, was noch lebt: Hat die IDE die Form schon zerstört, ist Old hier nil.
  mOld.Free;
end;

function TAtlasIdeDockWindow.Show(out ACreated: Boolean): Boolean;
var
  mServices: INTAServices;
  mHasServices: Boolean;
  mStep: TAtlasDockStep;
  mCreated: TCustomForm;
begin
  ACreated := False;
  mHasServices := Supports(BorlandIDEServices, INTAServices, mServices);
  mStep := TAtlasDockPlan.ShowStep(mHasServices, FForm <> nil, FFrame <> nil);
  if mStep = TAtlasDockStep.Unavailable then
  begin
    Exit(False);
  end;
  if mStep = TAtlasDockStep.RecreateForm then
  begin
    FreeForm;
  end;
  if mStep <> TAtlasDockStep.RevealForm then
  begin
    // FrameCreated läuft schon während CreateDockableForm und setzt Frame und Form.
    mCreated := mServices.CreateDockableForm(FDock);
    if mCreated = nil then
    begin
      Exit(False);
    end;
    SetForm(mCreated);
    ACreated := True;
    UpdateIcon(Self);
  end;
  Reveal;
  Result := Frame <> nil;
end;

procedure TAtlasIdeDockWindow.Reveal;
var
  mHost: TWinControl;
  mSheet: TTabSheet;
begin
  if FForm = nil then
  begin
    Exit;
  end;
  FForm.Visible := True;
  // Angedockt: Reiterseite wählen und versteckte Gastgeber (Dock-Fenster, Leisten) wieder zeigen.
  mHost := FForm.Parent;
  while mHost <> nil do
  begin
    if mHost is TTabSheet then
    begin
      mSheet := TTabSheet(mHost);
      if mSheet.PageControl <> nil then
      begin
        mSheet.PageControl.ActivePage := mSheet;
      end;
    end
    else if not mHost.Visible then
    begin
      mHost.Visible := True;
    end;
    mHost := mHost.Parent;
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
  begin
    Result := FFrame;
  end;
end;

function TAtlasIdeDockWindow.Shown: Boolean;
var
  mHosts: TArray<Boolean>;
  mHost: TWinControl;
begin
  if FForm = nil then
  begin
    Exit(False);
  end;
  mHosts := nil;
  mHost := FForm.Parent;
  while mHost <> nil do
  begin
    mHosts := mHosts + [mHost.Visible];
    mHost := mHost.Parent;
  end;
  Result := TAtlasDockPlan.Shown(FForm.Visible, mHosts);
end;

procedure TAtlasIdeDockWindow.Present;
var
  mCreated: Boolean;
begin
  Show(mCreated);
end;

procedure TAtlasIdeDockWindow.Hide;
begin
  if FForm <> nil then
  begin
    FForm.Hide;
  end;
end;

class function TAtlasIdeDockWindow.IsShown(AHost: TAtlasIdeDockWindow): Boolean;
begin
  // Angedockt in verstecktem Gastgeber zählt nicht als sichtbar.
  Result := (AHost <> nil) and AHost.Shown;
end;

class procedure TAtlasIdeDockWindow.HideIfAny(AHost: TAtlasIdeDockWindow);
begin
  if AHost <> nil then
  begin
    AHost.Hide;
  end;
end;

class procedure TAtlasIdeDockWindow.ApplyIdeTheme(AControl: TWinControl);
var
  mTheming: IOTAIDEThemingServices;
  mStyle: TCustomStyleServices;

  procedure ResetColors(AParent: TWinControl);
  var
    mIndex: Integer;
    mChild: TControl;
  begin
    for mIndex := 0 to AParent.ControlCount - 1 do
    begin
      mChild := AParent.Controls[mIndex];
      if mChild is TListView then
      begin
        TListView(mChild).Color := clWindow;
        TListView(mChild).Font.Color := clWindowText;
      end
      else if mChild is TTreeView then
      begin
        TTreeView(mChild).Color := clWindow;
        TTreeView(mChild).Font.Color := clWindowText;
      end;
      if mChild is TWinControl then
      begin
        ResetColors(TWinControl(mChild));
      end;
    end;
  end;

  procedure Inherit(AParent: TWinControl);
  var
    mIndex: Integer;
    mChild: TControl;
  begin
    for mIndex := 0 to AParent.ControlCount - 1 do
    begin
      mChild := AParent.Controls[mIndex];
      mChild.StyleName := '';
      if mChild is TWinControl then
      begin
        Inherit(TWinControl(mChild));
      end;
    end;
  end;

  function Chain: string;
  var
    mControl: TControl;
  begin
    Result := '';
    mControl := AControl;
    while mControl <> nil do
    begin
      Result := Result + Format(' < %s "%s"', [mControl.ClassName, mControl.StyleName]);
      mControl := mControl.Parent;
    end;
  end;

begin
  if (AControl = nil) or not Supports(BorlandIDEServices, IOTAIDEThemingServices, mTheming) or
    not mTheming.IDEThemingEnabled then
  begin
    Exit;
  end;
  ResetColors(AControl);
  mTheming.ApplyTheme(AControl);
  mStyle := mTheming.StyleServices;
  if mStyle = nil then
  begin
    Exit;
  end;
  Inherit(AControl);
  if TStyleManager.Style[mStyle.Name] = mStyle then
  begin
    AControl.StyleName := mStyle.Name;
  end;
  if StyleServices(AControl) <> mStyle then
  begin
    TAtlasGuard.Log(Format('Thema: %s zeichnet mit Stil "%s" statt "%s";%s', [AControl.ClassName,
      StyleServices(AControl).Name, mStyle.Name, Chain]));
  end;
  // Auch die Form eines Atlas-Dockfensters (schwebend sonst Titelleiste und Grund im Systemstil).
  if not (AControl is TCustomForm) and IsDockForm(GetParentForm(AControl, False)) then
  begin
    ThemeForm(GetParentForm(AControl, False));
  end;
end;

class procedure TAtlasIdeDockWindow.ApplyDarkCaption(AForm: TCustomForm);
const
  // Fehlt in Delphi 12 (Winapi.Dwmapi): ab Windows 10 20H1.
  cDWMWA_USE_IMMERSIVE_DARK_MODE = 20;
var
  mTheming: IOTAIDEThemingServices;
  mWindow: TColor;
  mDark: BOOL;
begin
  if (AForm = nil) or not AForm.HandleAllocated or
    not Supports(BorlandIDEServices, IOTAIDEThemingServices, mTheming) or not mTheming.IDEThemingEnabled or
    (mTheming.StyleServices = nil) then
  begin
    Exit;
  end;
  // Dunkel, wenn der Fenstergrund des IDE-Stils dunkel ist (Helligkeit nach Rec. 601).
  mWindow := ColorToRGB(mTheming.StyleServices.GetSystemColor(clWindow));
  mDark := (GetRValue(mWindow) * 299 + GetGValue(mWindow) * 587 + GetBValue(mWindow) * 114) div 1000 < 128;
  // Ältere Windows-Versionen kennen den Wert nicht und lehnen ihn ab: dann bleibt die Titelleiste hell.
  DwmSetWindowAttribute(AForm.Handle, cDWMWA_USE_IMMERSIVE_DARK_MODE, @mDark, SizeOf(mDark));
end;

procedure TAtlasIdeDockWindow.FormWndProc(var AMessage: TMessage);
begin
  if FWndHook <> nil then
  begin
    FWndHook.CallOld(AMessage);
  end;
  // Neu angelegtes Fenster (Ab- oder Andocken): Titelleiste wieder dunkel.
  if (AMessage.Msg = WM_CREATE) and (FForm <> nil) then
    try
      ApplyDarkCaption(FForm);
    except
      on E: Exception do
        TAtlasGuard.Log('Dunkle Titelleiste: ' + TAtlasGuard.ErrorText(E));
    end;
end;

class procedure TAtlasIdeDockWindow.ThemeForm(AForm: TCustomForm);
var
  mTheming: IOTAIDEThemingServices;
begin
  if (AForm = nil) or not Supports(BorlandIDEServices, IOTAIDEThemingServices, mTheming) or
    not mTheming.IDEThemingEnabled then
  begin
    Exit;
  end;
  try
    mTheming.ApplyTheme(AForm);
    // Der Frame ist durchsichtig und zeigt den Grund der Form; ApplyTheme setzt ihn nicht (schwebend hellgrau
    // unter weißer Schrift).
    if mTheming.StyleServices <> nil then
    begin
      TFormAccess(AForm).Color := mTheming.StyleServices.GetSystemColor(clBtnFace);
    end;
    ApplyDarkCaption(AForm);
  except
    // Thema ist Kosmetik: ein Fehler darf das Fenster nicht verhindern.
    on E: Exception do
      TAtlasGuard.Log(Format('Thema der Form %s: %s: %s', [AForm.ClassName, E.ClassName,
        TAtlasGuard.MessageText(E.Message)]));
  end;
end;

end.
