unit Atlas.IDE.Debug.StepFilterWindow;

// Andockbares Fenster „Schrittfilter“ (#850): verankerbar wie die Lesezeichen
// (#622) über INTACustomDockableForm, Inhalt TAtlasDebugStepFilterFrame,
// IDE-Thema (hell und dunkel), Atlas-Symbol (#751) im Fenstertitel. OnFrame
// meldet einen neuen Frame, damit TAtlasIdeDebugStepFilter ihn verdrahtet und
// füllt.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Forms,
  Atlas.UI.Debug.StepFilterFrame;

type
  TAtlasIdeDebugStepFilterWindow = class
  public class var
    /// <summary>Ein neuer Frame ist entstanden; setzt TAtlasIdeDebugStepFilter.</summary>
    OnFrame: TProc<TAtlasDebugStepFilterFrame>;
  public
    /// <summary>Fenster zeigen (bei Bedarf anlegen); nil, wenn die IDE keine andockbaren Fenster anbietet.</summary>
    class function Show: TAtlasDebugStepFilterFrame; static;
    /// <summary>Frame, falls das Fenster existiert; legt nichts an.</summary>
    class function ExistingFrame: TAtlasDebugStepFilterFrame; static;
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
  TStepFilterDock = class(TInterfacedObject, INTACustomDockableForm)
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

{ TStepFilterDock }

function TStepFilterDock.GetCaption: string;
begin
  Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.StepFilterCaption);
end;

function TStepFilterDock.GetIdentifier: string;
begin
  Result := 'AtlasStepFilter';
end;

function TStepFilterDock.GetFrameClass: TCustomFrameClass;
begin
  Result := TAtlasDebugStepFilterFrame;
end;

procedure TStepFilterDock.FrameCreated(AFrame: TCustomFrame);
var
  mFrame: TAtlasDebugStepFilterFrame;
begin
  if not (AFrame is TAtlasDebugStepFilterFrame) then
  begin
    Exit;
  end;
  if Host <> nil then
  begin
    Host.FrameCreated(AFrame);
  end;
  mFrame := TAtlasDebugStepFilterFrame(AFrame);
  TAtlasIdeDockWindow.UpdateIcon(Host);
  Theme(mFrame);
  if Assigned(TAtlasIdeDebugStepFilterWindow.OnFrame) then
  begin
    TAtlasIdeDebugStepFilterWindow.OnFrame(mFrame);
  end;
end;

function TStepFilterDock.GetMenuActionList: TCustomActionList;
begin
  Result := nil;
end;

function TStepFilterDock.GetMenuImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TStepFilterDock.CustomizePopupMenu(PopupMenu: TPopupMenu);
begin
end;

function TStepFilterDock.GetToolbarActionList: TCustomActionList;
begin
  Result := nil;
end;

function TStepFilterDock.GetToolbarImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TStepFilterDock.CustomizeToolBar(ToolBar: TToolBar);
begin
end;

procedure TStepFilterDock.SaveWindowState(Desktop: TCustomIniFile; const Section: string; IsProject: Boolean);
begin
end;

procedure TStepFilterDock.LoadWindowState(Desktop: TCustomIniFile; const Section: string);
begin
end;

function TStepFilterDock.GetEditState: TEditState;
begin
  Result := [];
end;

function TStepFilterDock.EditAction(Action: TEditAction): Boolean;
begin
  Result := False;
end;

procedure EnsureHost;
begin
  if Host = nil then
  begin
    Host := TAtlasIdeDockWindow.Create(TStepFilterDock.Create, True);
  end;
end;

{ TAtlasIdeDebugStepFilterWindow }

class function TAtlasIdeDebugStepFilterWindow.Show: TAtlasDebugStepFilterFrame;
begin
  // Lebt die Form noch (X versteckt nur), wird sie samt Gastgebern gezeigt; sonst neu angelegt.
  EnsureHost;
  Host.Present;
  Result := ExistingFrame;
end;

class function TAtlasIdeDebugStepFilterWindow.ExistingFrame: TAtlasDebugStepFilterFrame;
begin
  Result := nil;
  if (Host <> nil) and (Host.Frame is TAtlasDebugStepFilterFrame) then
  begin
    Result := TAtlasDebugStepFilterFrame(Host.Frame);
  end;
end;

class function TAtlasIdeDebugStepFilterWindow.Visible: Boolean;
begin
  Result := TAtlasIdeDockWindow.IsShown(Host);
end;

class procedure TAtlasIdeDebugStepFilterWindow.Hide;
begin
  TAtlasIdeDockWindow.HideIfAny(Host);
end;

class procedure TAtlasIdeDebugStepFilterWindow.ApplyTheme;
var
  mFrame: TAtlasDebugStepFilterFrame;
begin
  mFrame := ExistingFrame;
  if mFrame <> nil then
  begin
    Theme(mFrame);
  end;
  TAtlasIdeDockWindow.UpdateIcon(Host);
end;

class procedure TAtlasIdeDebugStepFilterWindow.Prepare;
begin
  EnsureHost;
end;

class procedure TAtlasIdeDebugStepFilterWindow.Release;
begin
  OnFrame := nil;
  // Meldet ab und gibt die Form nur frei, wenn die IDE sie nicht schon zerstört hat.
  FreeAndNil(Host);
end;

end.
