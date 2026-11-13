unit Atlas.IDE.Debug.MemoryWindow;

// Andockbares Fenster „Atlas: Speicher“ (#858) wie „Schrittfilter“ (#850):
// verankerbar über INTACustomDockableForm, Inhalt TAtlasDebugMemoryFrame,
// IDE-Thema (hell und dunkel), Atlas-Symbol im Fenstertitel. OnFrame meldet
// einen neuen Frame, damit TAtlasIdeDebugMemoryTimeline ihn verdrahtet und
// füllt.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Forms,
  Atlas.UI.Debug.MemoryFrame;

type
  TAtlasIdeDebugMemoryWindow = class
  public class var
    /// <summary>Ein neuer Frame ist entstanden; setzt TAtlasIdeDebugMemoryTimeline.</summary>
    OnFrame: TProc<TAtlasDebugMemoryFrame>;
  public
    /// <summary>Fenster zeigen (bei Bedarf anlegen); nil, wenn die IDE keine andockbaren Fenster anbietet.</summary>
    class function Show: TAtlasDebugMemoryFrame; static;
    /// <summary>Frame, falls das Fenster existiert; legt nichts an.</summary>
    class function ExistingFrame: TAtlasDebugMemoryFrame; static;
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
  TMemoryDock = class(TInterfacedObject, INTACustomDockableForm)
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

{ TMemoryDock }

function TMemoryDock.GetCaption: string;
begin
  Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.MemoryCaption);
end;

function TMemoryDock.GetIdentifier: string;
begin
  Result := 'AtlasMemoryTimeline';
end;

function TMemoryDock.GetFrameClass: TCustomFrameClass;
begin
  Result := TAtlasDebugMemoryFrame;
end;

procedure TMemoryDock.FrameCreated(AFrame: TCustomFrame);
var
  mFrame: TAtlasDebugMemoryFrame;
begin
  if not (AFrame is TAtlasDebugMemoryFrame) then
  begin
    Exit;
  end;
  if Host <> nil then
  begin
    Host.FrameCreated(AFrame);
  end;
  mFrame := TAtlasDebugMemoryFrame(AFrame);
  TAtlasIdeDockWindow.UpdateIcon(Host);
  Theme(mFrame);
  if Assigned(TAtlasIdeDebugMemoryWindow.OnFrame) then
  begin
    TAtlasIdeDebugMemoryWindow.OnFrame(mFrame);
  end;
end;

function TMemoryDock.GetMenuActionList: TCustomActionList;
begin
  Result := nil;
end;

function TMemoryDock.GetMenuImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TMemoryDock.CustomizePopupMenu(PopupMenu: TPopupMenu);
begin
end;

function TMemoryDock.GetToolbarActionList: TCustomActionList;
begin
  Result := nil;
end;

function TMemoryDock.GetToolbarImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TMemoryDock.CustomizeToolBar(ToolBar: TToolBar);
begin
end;

procedure TMemoryDock.SaveWindowState(Desktop: TCustomIniFile; const Section: string; IsProject: Boolean);
begin
end;

procedure TMemoryDock.LoadWindowState(Desktop: TCustomIniFile; const Section: string);
begin
end;

function TMemoryDock.GetEditState: TEditState;
begin
  Result := [];
end;

function TMemoryDock.EditAction(Action: TEditAction): Boolean;
begin
  Result := False;
end;

procedure EnsureHost;
begin
  if Host = nil then
  begin
    Host := TAtlasIdeDockWindow.Create(TMemoryDock.Create, True);
  end;
end;

{ TAtlasIdeDebugMemoryWindow }

class function TAtlasIdeDebugMemoryWindow.Show: TAtlasDebugMemoryFrame;
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

class function TAtlasIdeDebugMemoryWindow.ExistingFrame: TAtlasDebugMemoryFrame;
begin
  Result := nil;
  if (Host <> nil) and (Host.Frame is TAtlasDebugMemoryFrame) then
  begin
    Result := TAtlasDebugMemoryFrame(Host.Frame);
  end;
end;

class function TAtlasIdeDebugMemoryWindow.Visible: Boolean;
begin
  // Angedockt in verstecktem Gastgeber zählt nicht als sichtbar.
  Result := (Host <> nil) and Host.Shown;
end;

class procedure TAtlasIdeDebugMemoryWindow.Hide;
begin
  if Host <> nil then
  begin
    Host.Hide;
  end;
end;

class procedure TAtlasIdeDebugMemoryWindow.ApplyTheme;
var
  mFrame: TAtlasDebugMemoryFrame;
begin
  mFrame := ExistingFrame;
  if mFrame <> nil then
  begin
    Theme(mFrame);
  end;
  TAtlasIdeDockWindow.UpdateIcon(Host);
end;

class procedure TAtlasIdeDebugMemoryWindow.Prepare;
begin
  EnsureHost;
end;

class procedure TAtlasIdeDebugMemoryWindow.Release;
begin
  OnFrame := nil;
  // Meldet ab und gibt die Form nur frei, wenn die IDE sie nicht schon zerstört hat.
  FreeAndNil(Host);
end;

end.
