unit Atlas.IDE.Welcome.Window;

// Andockbares Fenster „Atlas-Start“ (#753, Menü Ansicht › Atlas-Start): die
// Atlas-Willkommensseite mit allen Atlas-Bereichen, unabhängig von den
// Atlas-Bereichen auf der Willkommensseite der IDE (welcomePage.ideWelcomePage,
// #761). Es öffnet auf Wunsch (Menü, Palette, Desktop der IDE) bzw. mit
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
    class procedure ApplyTheme; static;
    /// <summary>Früh (Register): bei der IDE anmelden, damit der Desktop das Fenster speichert und wiederherstellt
    /// (#879).</summary>
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
  Atlas.UI.Welcome.Strings,
  Atlas.UI.Style.Symbol,
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
begin
  TAtlasIdeDockWindow.ApplyIdeTheme(AFrame);
end;

{ TStartDock }

function TStartDock.GetCaption: string;
begin
  Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeStartCaption);
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
  mBoard: TAtlasWelcomeBoardFrame;
begin
  if not (AFrame is TAtlasWelcomeBoardFrame) then
  begin
    Exit;
  end;
  if Host <> nil then
  begin
    Host.FrameCreated(AFrame);
  end;
  mBoard := TAtlasWelcomeBoardFrame(AFrame);
  TAtlasIdeDockWindow.UpdateIcon(Host);
  Theme(mBoard);
  if Assigned(TAtlasIdeWelcomeWindow.OnFrame) then
  begin
    TAtlasIdeWelcomeWindow.OnFrame(mBoard);
  end;
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
  cDefaultWidth = 410;
  cDefaultHeight = 530;

procedure EnsureHost;
begin
  if Host = nil then
  begin
    Host := TAtlasIdeDockWindow.Create(TStartDock.Create, True);
  end;
end;

{ TAtlasIdeWelcomeWindow }

class function TAtlasIdeWelcomeWindow.Show: TAtlasWelcomeBoardFrame;
var
  mCreated: Boolean;
begin
  // Lebt die Form noch (X versteckt nur), wird sie samt Gastgebern gezeigt; sonst neu angelegt.
  EnsureHost;
  Host.Show(mCreated);
  if mCreated then
  begin
    // Vorgabe für das frei schwebende Fenster: alle Bereiche ohne Scrollen (410 × 530 bei 100 %).
    if Host.Form.Floating then
    begin
      Host.Form.Width := MulDiv(cDefaultWidth, Screen.PixelsPerInch, 96);
      Host.Form.Height := MulDiv(cDefaultHeight, Screen.PixelsPerInch, 96);
    end;
  end;
  Result := ExistingBoard;
end;

class function TAtlasIdeWelcomeWindow.ExistingBoard: TAtlasWelcomeBoardFrame;
begin
  Result := nil;
  if (Host <> nil) and (Host.Frame is TAtlasWelcomeBoardFrame) then
  begin
    Result := TAtlasWelcomeBoardFrame(Host.Frame);
  end;
end;

class function TAtlasIdeWelcomeWindow.Visible: Boolean;
begin
  Result := TAtlasIdeDockWindow.IsShown(Host);
end;

class procedure TAtlasIdeWelcomeWindow.Hide;
begin
  TAtlasIdeDockWindow.HideIfAny(Host);
end;

class procedure TAtlasIdeWelcomeWindow.ApplyTheme;
var
  mBoard: TAtlasWelcomeBoardFrame;
begin
  mBoard := ExistingBoard;
  if mBoard <> nil then
  begin
    Theme(mBoard);
    mBoard.UpdateContent;
  end;
  TAtlasIdeDockWindow.UpdateIcon(Host);
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
