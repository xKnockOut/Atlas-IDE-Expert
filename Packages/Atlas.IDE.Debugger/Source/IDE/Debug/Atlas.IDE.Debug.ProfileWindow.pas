unit Atlas.IDE.Debug.ProfileWindow;

// Andockbares Fenster „Atlas: Profil“ (#2057) wie „Schrittfilter“ (#850):
// verankerbar über INTACustomDockableForm, Inhalt TAtlasDebugProfileFrame,
// IDE-Thema (hell und dunkel), Atlas-Symbol im Fenstertitel. OnFrame meldet
// einen neuen Frame, damit TAtlasIdeDebugProfiler ihn verdrahtet und
// füllt.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Forms,
  Atlas.UI.Debug.ProfileFrame;

type
  TAtlasIdeDebugProfileWindow = class
  public class var
    /// <summary>Ein neuer Frame ist entstanden; setzt TAtlasIdeDebugProfiler.</summary>
    OnFrame: TProc<TAtlasDebugProfileFrame>;
  public
    /// <summary>Fenster zeigen (bei Bedarf anlegen); nil, wenn die IDE keine andockbaren Fenster anbietet.</summary>
    class function Show: TAtlasDebugProfileFrame; static;
    /// <summary>Frame, falls das Fenster existiert; legt nichts an.</summary>
    class function ExistingFrame: TAtlasDebugProfileFrame; static;
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
  Atlas.UI.Debug.Profile.Strings,
  Atlas.UI.Style.Symbol,
  Atlas.IDE.Foundation.DockWindow;

type
  TProfileDock = class(TInterfacedObject, INTACustomDockableForm)
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

{ TProfileDock }

function TProfileDock.GetCaption: string;
begin
  Result := TAtlasProfileStrings.Text(TAtlasProfileTextId.ProfileCaption);
end;

function TProfileDock.GetIdentifier: string;
begin
  Result := 'AtlasProfiler';
end;

function TProfileDock.GetFrameClass: TCustomFrameClass;
begin
  Result := TAtlasDebugProfileFrame;
end;

procedure TProfileDock.FrameCreated(AFrame: TCustomFrame);
var
  mFrame: TAtlasDebugProfileFrame;
begin
  if not (AFrame is TAtlasDebugProfileFrame) then
  begin
    Exit;
  end;
  if Host <> nil then
  begin
    Host.FrameCreated(AFrame);
  end;
  mFrame := TAtlasDebugProfileFrame(AFrame);
  TAtlasIdeDockWindow.UpdateIcon(Host);
  Theme(mFrame);
  if Assigned(TAtlasIdeDebugProfileWindow.OnFrame) then
  begin
    TAtlasIdeDebugProfileWindow.OnFrame(mFrame);
  end;
end;

function TProfileDock.GetMenuActionList: TCustomActionList;
begin
  Result := nil;
end;

function TProfileDock.GetMenuImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TProfileDock.CustomizePopupMenu(PopupMenu: TPopupMenu);
begin
end;

function TProfileDock.GetToolbarActionList: TCustomActionList;
begin
  Result := nil;
end;

function TProfileDock.GetToolbarImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TProfileDock.CustomizeToolBar(ToolBar: TToolBar);
begin
end;

procedure TProfileDock.SaveWindowState(Desktop: TCustomIniFile; const Section: string; IsProject: Boolean);
begin
end;

procedure TProfileDock.LoadWindowState(Desktop: TCustomIniFile; const Section: string);
begin
end;

function TProfileDock.GetEditState: TEditState;
begin
  Result := [];
end;

function TProfileDock.EditAction(Action: TEditAction): Boolean;
begin
  Result := False;
end;

procedure EnsureHost;
begin
  if Host = nil then
  begin
    Host := TAtlasIdeDockWindow.Create(TProfileDock.Create, True);
  end;
end;

{ TAtlasIdeDebugProfileWindow }

class function TAtlasIdeDebugProfileWindow.Show: TAtlasDebugProfileFrame;
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

class function TAtlasIdeDebugProfileWindow.ExistingFrame: TAtlasDebugProfileFrame;
begin
  Result := nil;
  if (Host <> nil) and (Host.Frame is TAtlasDebugProfileFrame) then
  begin
    Result := TAtlasDebugProfileFrame(Host.Frame);
  end;
end;

class function TAtlasIdeDebugProfileWindow.Visible: Boolean;
begin
  // Angedockt in verstecktem Gastgeber zählt nicht als sichtbar.
  Result := (Host <> nil) and Host.Shown;
end;

class procedure TAtlasIdeDebugProfileWindow.Hide;
begin
  if Host <> nil then
  begin
    Host.Hide;
  end;
end;

class procedure TAtlasIdeDebugProfileWindow.ApplyTheme;
var
  mFrame: TAtlasDebugProfileFrame;
begin
  mFrame := ExistingFrame;
  if mFrame <> nil then
  begin
    Theme(mFrame);
  end;
  TAtlasIdeDockWindow.UpdateIcon(Host);
end;

class procedure TAtlasIdeDebugProfileWindow.Prepare;
begin
  EnsureHost;
end;

class procedure TAtlasIdeDebugProfileWindow.Release;
begin
  OnFrame := nil;
  // Meldet ab und gibt die Form nur frei, wenn die IDE sie nicht schon zerstört hat.
  FreeAndNil(Host);
end;

end.
