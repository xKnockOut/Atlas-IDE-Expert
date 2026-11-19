unit Atlas.IDE.Debug.LogpointValuesWindow;

// Andockbares Fenster „Atlas: Logpunkt-Verlauf“ (#2552) wie „Atlas: Speicher“
// (#858): verankerbar über INTACustomDockableForm, Inhalt
// TAtlasDebugLogpointValuesFrame, IDE-Thema (hell und dunkel), Atlas-Symbol im
// Fenstertitel. OnFrame meldet einen neuen Frame, damit
// TAtlasIdeLogpointValues ihn verdrahtet und füllt.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Forms,
  Atlas.UI.Debug.LogpointValuesFrame;

type
  TAtlasIdeLogpointValuesWindow = class
  public class var
    /// <summary>Ein neuer Frame ist entstanden; setzt TAtlasIdeLogpointValues.</summary>
    OnFrame: TProc<TAtlasDebugLogpointValuesFrame>;
  public
    /// <summary>Fenster zeigen (bei Bedarf anlegen); nil, wenn die IDE keine andockbaren Fenster anbietet.</summary>
    class function Show: TAtlasDebugLogpointValuesFrame; static;
    /// <summary>Frame, falls das Fenster existiert; legt nichts an.</summary>
    class function ExistingFrame: TAtlasDebugLogpointValuesFrame; static;
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
  Atlas.UI.Debug.Logpoints.Strings,
  Atlas.UI.Style.Symbol,
  Atlas.IDE.Foundation.DockWindow;

type
  TValuesDock = class(TInterfacedObject, INTACustomDockableForm)
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

{ TValuesDock }

function TValuesDock.GetCaption: string;
begin
  Result := TAtlasLogpointsStrings.Text(TAtlasLogpointsTextId.ValuesCaption);
end;

function TValuesDock.GetIdentifier: string;
begin
  Result := 'AtlasLogpointValues';
end;

function TValuesDock.GetFrameClass: TCustomFrameClass;
begin
  Result := TAtlasDebugLogpointValuesFrame;
end;

procedure TValuesDock.FrameCreated(AFrame: TCustomFrame);
var
  mFrame: TAtlasDebugLogpointValuesFrame;
begin
  if not (AFrame is TAtlasDebugLogpointValuesFrame) then
  begin
    Exit;
  end;
  if Host <> nil then
  begin
    Host.FrameCreated(AFrame);
  end;
  mFrame := TAtlasDebugLogpointValuesFrame(AFrame);
  TAtlasIdeDockWindow.UpdateIcon(Host);
  Theme(mFrame);
  if Assigned(TAtlasIdeLogpointValuesWindow.OnFrame) then
  begin
    TAtlasIdeLogpointValuesWindow.OnFrame(mFrame);
  end;
end;

function TValuesDock.GetMenuActionList: TCustomActionList;
begin
  Result := nil;
end;

function TValuesDock.GetMenuImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TValuesDock.CustomizePopupMenu(PopupMenu: TPopupMenu);
begin
end;

function TValuesDock.GetToolbarActionList: TCustomActionList;
begin
  Result := nil;
end;

function TValuesDock.GetToolbarImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TValuesDock.CustomizeToolBar(ToolBar: TToolBar);
begin
end;

procedure TValuesDock.SaveWindowState(Desktop: TCustomIniFile; const Section: string; IsProject: Boolean);
begin
end;

procedure TValuesDock.LoadWindowState(Desktop: TCustomIniFile; const Section: string);
begin
end;

function TValuesDock.GetEditState: TEditState;
begin
  Result := [];
end;

function TValuesDock.EditAction(Action: TEditAction): Boolean;
begin
  Result := False;
end;

function MakeHost: TAtlasIdeDockWindow;
begin
  Result := TAtlasIdeDockWindow.Create(TValuesDock.Create, True);
end;

{ TAtlasIdeLogpointValuesWindow }

class function TAtlasIdeLogpointValuesWindow.Show: TAtlasDebugLogpointValuesFrame;
var
  mFrame: TCustomFrame;
begin
  Result := nil;
  mFrame := TAtlasIdeDockWindow.PresentFrame(Host, MakeHost);
  if mFrame is TAtlasDebugLogpointValuesFrame then
  begin
    Result := TAtlasDebugLogpointValuesFrame(mFrame);
  end;
end;

class function TAtlasIdeLogpointValuesWindow.ExistingFrame: TAtlasDebugLogpointValuesFrame;
begin
  Result := nil;
  if (Host <> nil) and (Host.Frame is TAtlasDebugLogpointValuesFrame) then
  begin
    Result := TAtlasDebugLogpointValuesFrame(Host.Frame);
  end;
end;

class function TAtlasIdeLogpointValuesWindow.Visible: Boolean;
begin
  // Angedockt in verstecktem Gastgeber zählt nicht als sichtbar.
  Result := TAtlasIdeDockWindow.IsShown(Host);
end;

class procedure TAtlasIdeLogpointValuesWindow.Hide;
begin
  TAtlasIdeDockWindow.HideIfAny(Host);
end;

class procedure TAtlasIdeLogpointValuesWindow.ApplyTheme;
var
  mFrame: TAtlasDebugLogpointValuesFrame;
begin
  mFrame := ExistingFrame;
  if mFrame <> nil then
  begin
    Theme(mFrame);
  end;
  TAtlasIdeDockWindow.UpdateIcon(Host);
end;

class procedure TAtlasIdeLogpointValuesWindow.Prepare;
begin
  if Host = nil then
  begin
    Host := MakeHost;
  end;
end;

class procedure TAtlasIdeLogpointValuesWindow.Release;
begin
  OnFrame := nil;
  // Meldet ab und gibt die Form nur frei, wenn die IDE sie nicht schon zerstört hat.
  FreeAndNil(Host);
end;

end.
