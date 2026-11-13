unit Atlas.IDE.Tracker.FlowWindow;

// Andockbares Fenster „Atlas-Ablauf“ (#2125): verankerbar wie „Atlas-Board“
// (#1272) über TAtlasIdeDockWindow, Inhalt TAtlasFlowFrame, IDE-Thema,
// Atlas-Symbol (#751) im Fenstertitel; die IDE speichert es im Desktop
// (#879). OnFrame meldet einen neuen Frame, damit TAtlasIdeFlowMap ihn
// verdrahtet und füllt.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Forms,
  Atlas.UI.Tracker.FlowFrame;

type
  TAtlasIdeFlowWindow = class
  public class var
    /// <summary>Ein neuer Frame ist entstanden; setzt TAtlasIdeFlowMap.</summary>
    OnFrame: TProc<TAtlasFlowFrame>;
  public
    /// <summary>Fenster zeigen (bei Bedarf anlegen); nil, wenn die IDE keine andockbaren Fenster anbietet.</summary>
    class function Show: TAtlasFlowFrame; static;
    /// <summary>Frame, falls das Fenster existiert; legt nichts an.</summary>
    class function ExistingFrame: TAtlasFlowFrame; static;
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
  System.IniFiles,
  Vcl.ActnList,
  Vcl.ImgList,
  Vcl.Menus,
  Vcl.ComCtrls,
  Vcl.Graphics,
  DesignIntf,
  ToolsAPI,
  Atlas.UI.Tracker.Flow.Strings,
  Atlas.UI.Style.Symbol,
  Atlas.IDE.Foundation.DockWindow;

type
  TFlowDock = class(TInterfacedObject, INTACustomDockableForm)
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

{ TFlowDock }

function TFlowDock.GetCaption: string;
begin
  Result := TAtlasFlowStrings.Text(TAtlasFlowTextId.FlowCaption);
end;

function TFlowDock.GetIdentifier: string;
begin
  Result := 'AtlasFlowMap';
end;

function TFlowDock.GetFrameClass: TCustomFrameClass;
begin
  Result := TAtlasFlowFrame;
end;

procedure TFlowDock.FrameCreated(AFrame: TCustomFrame);
var
  mFrame: TAtlasFlowFrame;
begin
  if not (AFrame is TAtlasFlowFrame) then
  begin
    Exit;
  end;
  if Host <> nil then
  begin
    Host.FrameCreated(AFrame);
  end;
  mFrame := TAtlasFlowFrame(AFrame);
  TAtlasIdeDockWindow.UpdateIcon(Host);
  Theme(mFrame);
  if Assigned(TAtlasIdeFlowWindow.OnFrame) then
  begin
    TAtlasIdeFlowWindow.OnFrame(mFrame);
  end;
end;

function TFlowDock.GetMenuActionList: TCustomActionList;
begin
  Result := nil;
end;

function TFlowDock.GetMenuImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TFlowDock.CustomizePopupMenu(PopupMenu: TPopupMenu);
begin
end;

function TFlowDock.GetToolbarActionList: TCustomActionList;
begin
  Result := nil;
end;

function TFlowDock.GetToolbarImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TFlowDock.CustomizeToolBar(ToolBar: TToolBar);
begin
end;

procedure TFlowDock.SaveWindowState(Desktop: TCustomIniFile; const Section: string; IsProject: Boolean);
begin
end;

procedure TFlowDock.LoadWindowState(Desktop: TCustomIniFile; const Section: string);
begin
end;

function TFlowDock.GetEditState: TEditState;
begin
  Result := [];
end;

function TFlowDock.EditAction(Action: TEditAction): Boolean;
begin
  Result := False;
end;

procedure EnsureHost;
begin
  if Host = nil then
  begin
    Host := TAtlasIdeDockWindow.Create(TFlowDock.Create, True);
  end;
end;

{ TAtlasIdeFlowWindow }

class function TAtlasIdeFlowWindow.Show: TAtlasFlowFrame;
var
  mCreated: Boolean;
begin
  // Lebt die Form noch (X versteckt nur), wird sie samt Gastgebern gezeigt; sonst neu angelegt.
  EnsureHost;
  Host.Show(mCreated);
  if mCreated then
  begin
    TAtlasIdeDockWindow.UpdateIcon(Host);
  end;
  Result := ExistingFrame;
end;

class function TAtlasIdeFlowWindow.ExistingFrame: TAtlasFlowFrame;
begin
  Result := nil;
  if (Host <> nil) and (Host.Frame is TAtlasFlowFrame) then
  begin
    Result := TAtlasFlowFrame(Host.Frame);
  end;
end;

class function TAtlasIdeFlowWindow.Visible: Boolean;
begin
  // Angedockt in verstecktem Gastgeber zählt nicht als sichtbar.
  Result := (Host <> nil) and Host.Shown;
end;

class procedure TAtlasIdeFlowWindow.Hide;
begin
  if Host <> nil then
  begin
    Host.Hide;
  end;
end;

class procedure TAtlasIdeFlowWindow.ApplyTheme;
var
  mFrame: TAtlasFlowFrame;
begin
  mFrame := ExistingFrame;
  if mFrame <> nil then
  begin
    Theme(mFrame);
  end;
  TAtlasIdeDockWindow.UpdateIcon(Host);
end;

class procedure TAtlasIdeFlowWindow.Prepare;
begin
  EnsureHost;
end;

class procedure TAtlasIdeFlowWindow.Release;
begin
  OnFrame := nil;
  // Meldet ab und gibt die Form nur frei, wenn die IDE sie nicht schon zerstört hat.
  FreeAndNil(Host);
end;

end.
