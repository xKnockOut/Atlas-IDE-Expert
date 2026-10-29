unit Atlas.IDE.Tracker.BoardWindow;

// Andockbares Fenster „Atlas-Board“ (#1272): verankerbar wie „Atlas-Issue“
// (#1264) über INTAServices.CreateDockableForm, Inhalt TAtlasBoardFrame,
// IDE-Thema, Atlas-Symbol (#751) im Fenstertitel; die IDE speichert es im
// Desktop (#879). OnFrame meldet einen neuen Frame, damit TAtlasIdeBoard ihn
// verdrahtet und füllt.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Forms,
  Atlas.UI.Tracker.BoardFrame;

type
  TAtlasIdeBoardWindow = class
  public class var
    /// <summary>Ein neuer Frame ist entstanden; setzt TAtlasIdeBoard.</summary>
    OnFrame: TProc<TAtlasBoardFrame>;
  public
    /// <summary>Fenster zeigen (bei Bedarf anlegen); nil, wenn die IDE keine andockbaren Fenster anbietet.</summary>
    class function Show: TAtlasBoardFrame; static;
    /// <summary>Frame, falls das Fenster existiert; legt nichts an.</summary>
    class function ExistingFrame: TAtlasBoardFrame; static;
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
  TBoardDock = class(TInterfacedObject, INTACustomDockableForm)
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

{ TBoardDock }

function TBoardDock.GetCaption: string;
begin
  Result := TAtlasStrings.Text(TAtlasTextId.BoardCaption);
end;

function TBoardDock.GetIdentifier: string;
begin
  Result := 'AtlasBoard';
end;

function TBoardDock.GetFrameClass: TCustomFrameClass;
begin
  Result := TAtlasBoardFrame;
end;

procedure TBoardDock.FrameCreated(AFrame: TCustomFrame);
var
  Frame: TAtlasBoardFrame;
begin
  if not (AFrame is TAtlasBoardFrame) then
    Exit;
  if Host <> nil then
    Host.FrameCreated(AFrame);
  Frame := TAtlasBoardFrame(AFrame);
  TAtlasIdeBoardWindow.UpdateIcon;
  Theme(Frame);
  if Assigned(TAtlasIdeBoardWindow.OnFrame) then
    TAtlasIdeBoardWindow.OnFrame(Frame);
end;

function TBoardDock.GetMenuActionList: TCustomActionList;
begin
  Result := nil;
end;

function TBoardDock.GetMenuImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TBoardDock.CustomizePopupMenu(PopupMenu: TPopupMenu);
begin
end;

function TBoardDock.GetToolbarActionList: TCustomActionList;
begin
  Result := nil;
end;

function TBoardDock.GetToolbarImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TBoardDock.CustomizeToolBar(ToolBar: TToolBar);
begin
end;

procedure TBoardDock.SaveWindowState(Desktop: TCustomIniFile; const Section: string; IsProject: Boolean);
begin
end;

procedure TBoardDock.LoadWindowState(Desktop: TCustomIniFile; const Section: string);
begin
end;

function TBoardDock.GetEditState: TEditState;
begin
  Result := [];
end;

function TBoardDock.EditAction(Action: TEditAction): Boolean;
begin
  Result := False;
end;

procedure EnsureHost;
begin
  if Host = nil then
    Host := TAtlasIdeDockWindow.Create(TBoardDock.Create, True);
end;

{ TAtlasIdeBoardWindow }

class function TAtlasIdeBoardWindow.Show: TAtlasBoardFrame;
var
  Created: Boolean;
begin
  // Lebt die Form noch (X versteckt nur), wird sie samt Gastgebern gezeigt; sonst neu angelegt.
  EnsureHost;
  Host.Show(Created);
  if Created then
    UpdateIcon;
  Result := ExistingFrame;
end;

class function TAtlasIdeBoardWindow.ExistingFrame: TAtlasBoardFrame;
begin
  Result := nil;
  if (Host <> nil) and (Host.Frame is TAtlasBoardFrame) then
    Result := TAtlasBoardFrame(Host.Frame);
end;

class function TAtlasIdeBoardWindow.Visible: Boolean;
begin
  // Angedockt in verstecktem Gastgeber zählt nicht als sichtbar.
  Result := (Host <> nil) and Host.Shown;
end;

class procedure TAtlasIdeBoardWindow.Hide;
begin
  if Host <> nil then
    Host.Hide;
end;

class procedure TAtlasIdeBoardWindow.UpdateIcon;
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

class procedure TAtlasIdeBoardWindow.ApplyTheme;
var
  Frame: TAtlasBoardFrame;
begin
  Frame := ExistingFrame;
  if Frame <> nil then
    Theme(Frame);
  UpdateIcon;
end;

class procedure TAtlasIdeBoardWindow.Prepare;
begin
  EnsureHost;
end;

class procedure TAtlasIdeBoardWindow.Release;
begin
  OnFrame := nil;
  // Meldet ab und gibt die Form nur frei, wenn die IDE sie nicht schon zerstört hat.
  FreeAndNil(Host);
end;

end.
