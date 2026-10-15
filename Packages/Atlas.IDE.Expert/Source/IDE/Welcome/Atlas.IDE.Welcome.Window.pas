unit Atlas.IDE.Welcome.Window;

// Andockbares Fenster „Atlas-Start“ (#753, Menü Ansicht › Atlas-Start): zeigt
// dieselben Atlas-Bereiche wie die Willkommensseite untereinander, wenn die
// IDE keine Schnittstelle für die Willkommensseite anbietet oder
// welcomePage.host = dockWindow ist. Aufbau wie das Ergebnisfenster (#400):
// INTAServices.CreateDockableForm mit TAtlasWelcomeBoardFrame, IDE-Thema,
// Atlas-Symbol (#751) im Fenstertitel. OnFrame meldet einen neuen Frame,
// damit die Steuerung ihn füllt.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Forms,
  Atlas.UI.Welcome.Board;

type
  TAtlasIdeWelcomeWindow = class
  public class var
    /// <summary>Ein neuer Frame ist entstanden; setzt die Steuerung.</summary>
    OnFrame: TProc<TAtlasWelcomeBoardFrame>;
  public
    /// <summary>Fenster zeigen (bei Bedarf anlegen); nil, wenn die IDE keine andockbaren Fenster anbietet.</summary>
    class function Show: TAtlasWelcomeBoardFrame; static;
    /// <summary>Frame, falls das Fenster existiert; legt nichts an.</summary>
    class function ExistingBoard: TAtlasWelcomeBoardFrame; static;
    class function Visible: Boolean; static;
    class procedure Hide; static;
    class procedure UpdateIcon; static;
    class procedure ApplyTheme; static;
    class procedure Release; static;
  end;

implementation

uses
  Winapi.Windows,
  System.IniFiles,
  Vcl.ActnList,
  Vcl.ImgList,
  Vcl.Menus,
  Vcl.ComCtrls,
  Vcl.Graphics,
  DesignIntf,
  ToolsAPI,
  Atlas.UI.Strings,
  Atlas.UI.Style.Symbol,
  Atlas.IDE.Style.Symbol;

type
  TStartDock = class(TInterfacedObject, INTACustomDockableForm)
  public
    function GetCaption: string;
    function GetIdentifier: string;
    function GetFrameClass: TCustomFrameClass;
    procedure FrameCreated(AFrame: TCustomFrame);
    function GetMenuActionList: TCustomActionList;
    function GetMenuImageList: TCustomImageList;
    procedure CustomizePopupMenu(PopupMenu: TPopupMenu);
    function GetToolbarActionList: TCustomActionList;
    function GetToolbarImageList: TCustomImageList;
    procedure CustomizeToolBar(ToolBar: TToolBar);
    procedure SaveWindowState(Desktop: TCustomIniFile; const Section: string; IsProject: Boolean);
    procedure LoadWindowState(Desktop: TCustomIniFile; const Section: string);
    function GetEditState: TEditState;
    function EditAction(Action: TEditAction): Boolean;
  end;

  TWatch = class(TComponent)
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  end;

var
  Dock: INTACustomDockableForm;
  Form: TCustomForm;
  Board: TAtlasWelcomeBoardFrame;
  Watch: TWatch;

procedure Theme(AFrame: TCustomFrame);
var
  Theming: IOTAIDEThemingServices;
begin
  if (AFrame <> nil) and Supports(BorlandIDEServices, IOTAIDEThemingServices, Theming) and
    Theming.IDEThemingEnabled then
    Theming.ApplyTheme(AFrame);
end;

{ TStartDock }

function TStartDock.GetCaption: string;
begin
  Result := TAtlasStrings.Text(TAtlasTextId.WelcomeStartCaption);
end;

function TStartDock.GetIdentifier: string;
begin
  Result := 'AtlasStart';
end;

function TStartDock.GetFrameClass: TCustomFrameClass;
begin
  Result := TAtlasWelcomeBoardFrame;
end;

procedure TStartDock.FrameCreated(AFrame: TCustomFrame);
begin
  if not (AFrame is TAtlasWelcomeBoardFrame) then
    Exit;
  Board := TAtlasWelcomeBoardFrame(AFrame);
  Board.FreeNotification(Watch);
  Theme(Board);
  if Assigned(TAtlasIdeWelcomeWindow.OnFrame) then
    TAtlasIdeWelcomeWindow.OnFrame(Board);
end;

function TStartDock.GetMenuActionList: TCustomActionList;
begin
  Result := nil;
end;

function TStartDock.GetMenuImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TStartDock.CustomizePopupMenu(PopupMenu: TPopupMenu);
begin
end;

function TStartDock.GetToolbarActionList: TCustomActionList;
begin
  Result := nil;
end;

function TStartDock.GetToolbarImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TStartDock.CustomizeToolBar(ToolBar: TToolBar);
begin
end;

procedure TStartDock.SaveWindowState(Desktop: TCustomIniFile; const Section: string; IsProject: Boolean);
begin
end;

procedure TStartDock.LoadWindowState(Desktop: TCustomIniFile; const Section: string);
begin
end;

function TStartDock.GetEditState: TEditState;
begin
  Result := [];
end;

function TStartDock.EditAction(Action: TEditAction): Boolean;
begin
  Result := False;
end;

{ TWatch }

procedure TWatch.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if Operation <> opRemove then
    Exit;
  if AComponent = Board then
    Board := nil;
  if AComponent = Form then
  begin
    Form := nil;
    Board := nil;
  end;
end;

const
  // Fenstergröße beim ersten Öffnen (logische Pixel).
  DefaultWidth = 410;
  DefaultHeight = 530;

{ TAtlasIdeWelcomeWindow }

class function TAtlasIdeWelcomeWindow.Show: TAtlasWelcomeBoardFrame;
var
  Services: INTAServices;
begin
  if Form = nil then
  begin
    if not Supports(BorlandIDEServices, INTAServices, Services) then
      Exit(nil);
    if Watch = nil then
      Watch := TWatch.Create(nil);
    Dock := TStartDock.Create;
    Form := Services.CreateDockableForm(Dock);
    if Form <> nil then
    begin
      Form.FreeNotification(Watch);
      // Vorgabe für das frei schwebende Fenster: alle Bereiche ohne Scrollen (410 × 530 bei 100 %).
      if Form.Floating then
      begin
        Form.Width := MulDiv(DefaultWidth, Screen.PixelsPerInch, 96);
        Form.Height := MulDiv(DefaultHeight, Screen.PixelsPerInch, 96);
      end;
      UpdateIcon;
    end;
  end;
  if Form <> nil then
  begin
    Form.Show;
    Form.BringToFront;
  end;
  Result := Board;
end;

class function TAtlasIdeWelcomeWindow.ExistingBoard: TAtlasWelcomeBoardFrame;
begin
  Result := nil;
  if Form <> nil then
    Result := Board;
end;

class function TAtlasIdeWelcomeWindow.Visible: Boolean;
begin
  Result := (Form <> nil) and Form.Visible;
end;

class procedure TAtlasIdeWelcomeWindow.Hide;
begin
  if Form <> nil then
    Form.Hide;
end;

class procedure TAtlasIdeWelcomeWindow.UpdateIcon;
var
  Icon: TIcon;
begin
  if Form = nil then
    Exit;
  Icon := TAtlasSymbolImages.Icon(TAtlasIdeSymbol.Current);
  try
    // Icon ist erst in TForm öffentlich.
    TForm(Form).Icon.Assign(Icon);
  finally
    Icon.Free;
  end;
end;

class procedure TAtlasIdeWelcomeWindow.ApplyTheme;
begin
  if Board <> nil then
  begin
    Theme(Board);
    Board.UpdateContent;
  end;
  UpdateIcon;
end;

class procedure TAtlasIdeWelcomeWindow.Release;
begin
  OnFrame := nil;
  Board := nil;
  FreeAndNil(Form);
  Dock := nil;
  FreeAndNil(Watch);
end;

end.
