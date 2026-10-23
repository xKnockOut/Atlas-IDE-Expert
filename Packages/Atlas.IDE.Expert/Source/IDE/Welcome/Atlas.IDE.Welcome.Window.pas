unit Atlas.IDE.Welcome.Window;

// Andockbares Fenster „Atlas-Start“ (#753, Menü Ansicht › Atlas-Start): die
// Atlas-Willkommensseite mit allen Atlas-Bereichen. Seit #1114 der einzige
// Ort dafür; auf der Willkommensseite der IDE meldet Atlas nichts mehr an.
// Es öffnet auf Wunsch (Menü, Palette, Desktop der IDE) bzw. mit
// welcomePage.openOnStart beim Start. Aufbau wie das Ergebnisfenster (#400):
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
    /// <summary>Früh (Register): bei der IDE anmelden, damit der Desktop das Fenster speichert und wiederherstellt (#879).</summary>
    class procedure Prepare; static;
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
  Atlas.IDE.Foundation.Symbol,
  Atlas.IDE.Foundation.DockWindow;

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

var
  // Verwaltet Form, Frame und Anmeldung bei der IDE (#879).
  Host: TAtlasIdeDockWindow;

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
var
  Board: TAtlasWelcomeBoardFrame;
begin
  if not (AFrame is TAtlasWelcomeBoardFrame) then
    Exit;
  if Host <> nil then
    Host.FrameCreated(AFrame);
  Board := TAtlasWelcomeBoardFrame(AFrame);
  TAtlasIdeWelcomeWindow.UpdateIcon;
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

const
  // Fenstergröße beim ersten Öffnen (logische Pixel).
  DefaultWidth = 410;
  DefaultHeight = 530;

procedure EnsureHost;
begin
  if Host = nil then
    Host := TAtlasIdeDockWindow.Create(TStartDock.Create, True);
end;

{ TAtlasIdeWelcomeWindow }

class function TAtlasIdeWelcomeWindow.Show: TAtlasWelcomeBoardFrame;
var
  Created: Boolean;
begin
  // Lebt die Form noch (X versteckt nur), wird sie samt Gastgebern gezeigt; sonst neu angelegt.
  EnsureHost;
  Host.Show(Created);
  if Created then
  begin
    // Vorgabe für das frei schwebende Fenster: alle Bereiche ohne Scrollen (410 × 530 bei 100 %).
    if Host.Form.Floating then
    begin
      Host.Form.Width := MulDiv(DefaultWidth, Screen.PixelsPerInch, 96);
      Host.Form.Height := MulDiv(DefaultHeight, Screen.PixelsPerInch, 96);
    end;
    UpdateIcon;
  end;
  Result := ExistingBoard;
end;

class function TAtlasIdeWelcomeWindow.ExistingBoard: TAtlasWelcomeBoardFrame;
begin
  Result := nil;
  if (Host <> nil) and (Host.Frame is TAtlasWelcomeBoardFrame) then
    Result := TAtlasWelcomeBoardFrame(Host.Frame);
end;

class function TAtlasIdeWelcomeWindow.Visible: Boolean;
begin
  // Angedockt in verstecktem Gastgeber zählt nicht als sichtbar.
  Result := (Host <> nil) and Host.Shown;
end;

class procedure TAtlasIdeWelcomeWindow.Hide;
begin
  if Host <> nil then
    Host.Hide;
end;

class procedure TAtlasIdeWelcomeWindow.UpdateIcon;
var
  Icon: TIcon;
begin
  if (Host = nil) or (Host.Form = nil) then
    Exit;
  Icon := TAtlasSymbolImages.Icon(TAtlasIdeSymbol.Current);
  try
    // Icon ist erst in TForm öffentlich.
    TForm(Host.Form).Icon.Assign(Icon);
  finally
    Icon.Free;
  end;
end;

class procedure TAtlasIdeWelcomeWindow.ApplyTheme;
var
  Board: TAtlasWelcomeBoardFrame;
begin
  Board := ExistingBoard;
  if Board <> nil then
  begin
    Theme(Board);
    Board.UpdateContent;
  end;
  UpdateIcon;
end;

class procedure TAtlasIdeWelcomeWindow.Prepare;
begin
  EnsureHost;
end;

class procedure TAtlasIdeWelcomeWindow.Release;
begin
  OnFrame := nil;
  // Meldet ab und gibt die Form nur frei, wenn die IDE sie nicht schon zerstört hat.
  FreeAndNil(Host);
end;

end.
