unit Atlas.IDE.Debug.EventLogWindow;

// Andockbares Seitenfenster „Ereignisprotokoll“ (#580): verankerbar wie der
// Exception-Verlauf über TAtlasIdeDockWindow, Inhalt
// TAtlasDebugEventLogFrame, IDE-Thema, Atlas-Symbol im Fenstertitel. OnFrame
// meldet einen neuen Frame, damit TAtlasIdeDebugEventLog ihn verdrahtet und
// füllt.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Forms,
  Atlas.UI.Debug.EventLogFrame;

type
  TAtlasIdeDebugEventLogWindow = class
  public class var
    /// <summary>Ein neuer Frame ist entstanden; setzt TAtlasIdeDebugEventLog.</summary>
    OnFrame: TProc<TAtlasDebugEventLogFrame>;
  public
    /// <summary>Fenster zeigen (bei Bedarf anlegen); nil, wenn die IDE keine andockbaren Fenster anbietet.</summary>
    class function Show: TAtlasDebugEventLogFrame; static;
    /// <summary>Frame, falls das Fenster existiert; legt nichts an.</summary>
    class function ExistingFrame: TAtlasDebugEventLogFrame; static;
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
  Atlas.UI.Debug.Strings,
  Atlas.UI.Style.Symbol,
  Atlas.IDE.Foundation.DockWindow;

type
  TEventLogDock = class(TInterfacedObject, INTACustomDockableForm)
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

{ TEventLogDock }

function TEventLogDock.GetCaption: string;
begin
  Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugEventLogCaption);
end;

function TEventLogDock.GetIdentifier: string;
begin
  Result := 'AtlasDebugEventLog';
end;

function TEventLogDock.GetFrameClass: TCustomFrameClass;
begin
  Result := TAtlasDebugEventLogFrame;
end;

procedure TEventLogDock.FrameCreated(AFrame: TCustomFrame);
var
  mFrame: TAtlasDebugEventLogFrame;
begin
  if not (AFrame is TAtlasDebugEventLogFrame) then
  begin
    Exit;
  end;
  if Host <> nil then
  begin
    Host.FrameCreated(AFrame);
  end;
  mFrame := TAtlasDebugEventLogFrame(AFrame);
  TAtlasIdeDockWindow.UpdateIcon(Host);
  Theme(mFrame);
  if Assigned(TAtlasIdeDebugEventLogWindow.OnFrame) then
  begin
    TAtlasIdeDebugEventLogWindow.OnFrame(mFrame);
  end;
end;

function TEventLogDock.GetMenuActionList: TCustomActionList;
begin
  Result := nil;
end;

function TEventLogDock.GetMenuImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TEventLogDock.CustomizePopupMenu(PopupMenu: TPopupMenu);
begin
end;

function TEventLogDock.GetToolbarActionList: TCustomActionList;
begin
  Result := nil;
end;

function TEventLogDock.GetToolbarImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TEventLogDock.CustomizeToolBar(ToolBar: TToolBar);
begin
end;

procedure TEventLogDock.SaveWindowState(Desktop: TCustomIniFile; const Section: string; IsProject: Boolean);
begin
end;

procedure TEventLogDock.LoadWindowState(Desktop: TCustomIniFile; const Section: string);
begin
end;

function TEventLogDock.GetEditState: TEditState;
begin
  Result := [];
end;

function TEventLogDock.EditAction(Action: TEditAction): Boolean;
begin
  Result := False;
end;

procedure EnsureHost;
begin
  if Host = nil then
  begin
    Host := TAtlasIdeDockWindow.Create(TEventLogDock.Create, True);
  end;
end;

{ TAtlasIdeDebugEventLogWindow }

class function TAtlasIdeDebugEventLogWindow.Show: TAtlasDebugEventLogFrame;
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

class function TAtlasIdeDebugEventLogWindow.ExistingFrame: TAtlasDebugEventLogFrame;
begin
  Result := nil;
  if (Host <> nil) and (Host.Frame is TAtlasDebugEventLogFrame) then
  begin
    Result := TAtlasDebugEventLogFrame(Host.Frame);
  end;
end;

class function TAtlasIdeDebugEventLogWindow.Visible: Boolean;
begin
  // Angedockt in verstecktem Gastgeber zählt nicht als sichtbar.
  Result := (Host <> nil) and Host.Shown;
end;

class procedure TAtlasIdeDebugEventLogWindow.Hide;
begin
  if Host <> nil then
  begin
    Host.Hide;
  end;
end;

class procedure TAtlasIdeDebugEventLogWindow.ApplyTheme;
var
  mFrame: TAtlasDebugEventLogFrame;
begin
  mFrame := ExistingFrame;
  if mFrame <> nil then
  begin
    Theme(mFrame);
  end;
  TAtlasIdeDockWindow.UpdateIcon(Host);
end;

class procedure TAtlasIdeDebugEventLogWindow.Prepare;
begin
  EnsureHost;
end;

class procedure TAtlasIdeDebugEventLogWindow.Release;
begin
  OnFrame := nil;
  // Meldet ab und gibt die Form nur frei, wenn die IDE sie nicht schon zerstört hat.
  FreeAndNil(Host);
end;

end.
