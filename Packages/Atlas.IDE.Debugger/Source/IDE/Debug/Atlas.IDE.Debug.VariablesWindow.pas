unit Atlas.IDE.Debug.VariablesWindow;

// Andockbares Fenster „Variablen“ (#853): verankerbar wie „Auswerten“ (#784)
// über INTACustomDockableForm und TAtlasIdeDockWindow, Inhalt
// TAtlasDebugVariablesFrame, IDE-Thema, Atlas-Symbol im Fenstertitel.
// OnFrame meldet einen neuen Frame, damit TAtlasIdeDebugVariables ihn
// verdrahtet und füllt.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Forms,
  Atlas.UI.Debug.VariablesFrame;

type
  TAtlasIdeDebugVariablesWindow = class
  public class var
    /// <summary>Ein neuer Frame ist entstanden; setzt TAtlasIdeDebugVariables.</summary>
    OnFrame: TProc<TAtlasDebugVariablesFrame>;
  public
    /// <summary>Fenster zeigen (bei Bedarf anlegen); nil, wenn die IDE keine andockbaren Fenster anbietet.</summary>
    class function Show: TAtlasDebugVariablesFrame; static;
    /// <summary>Frame, falls das Fenster existiert; legt nichts an.</summary>
    class function ExistingFrame: TAtlasDebugVariablesFrame; static;
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
  TVariablesDock = class(TInterfacedObject, INTACustomDockableForm)
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

{ TVariablesDock }

function TVariablesDock.GetCaption: string;
begin
  Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.VariablesCaption);
end;

function TVariablesDock.GetIdentifier: string;
begin
  Result := 'AtlasVariables';
end;

function TVariablesDock.GetFrameClass: TCustomFrameClass;
begin
  Result := TAtlasDebugVariablesFrame;
end;

procedure TVariablesDock.FrameCreated(AFrame: TCustomFrame);
var
  mFrame: TAtlasDebugVariablesFrame;
begin
  if not (AFrame is TAtlasDebugVariablesFrame) then
  begin
    Exit;
  end;
  if Host <> nil then
  begin
    Host.FrameCreated(AFrame);
  end;
  mFrame := TAtlasDebugVariablesFrame(AFrame);
  TAtlasIdeDockWindow.UpdateIcon(Host);
  Theme(mFrame);
  if Assigned(TAtlasIdeDebugVariablesWindow.OnFrame) then
  begin
    TAtlasIdeDebugVariablesWindow.OnFrame(mFrame);
  end;
end;

function TVariablesDock.GetMenuActionList: TCustomActionList;
begin
  Result := nil;
end;

function TVariablesDock.GetMenuImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TVariablesDock.CustomizePopupMenu(PopupMenu: TPopupMenu);
begin
end;

function TVariablesDock.GetToolbarActionList: TCustomActionList;
begin
  Result := nil;
end;

function TVariablesDock.GetToolbarImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TVariablesDock.CustomizeToolBar(ToolBar: TToolBar);
begin
end;

procedure TVariablesDock.SaveWindowState(Desktop: TCustomIniFile; const Section: string; IsProject: Boolean);
begin
end;

procedure TVariablesDock.LoadWindowState(Desktop: TCustomIniFile; const Section: string);
begin
end;

function TVariablesDock.GetEditState: TEditState;
begin
  Result := [];
end;

function TVariablesDock.EditAction(Action: TEditAction): Boolean;
begin
  Result := False;
end;

procedure EnsureHost;
begin
  if Host = nil then
  begin
    Host := TAtlasIdeDockWindow.Create(TVariablesDock.Create, True);
  end;
end;

{ TAtlasIdeDebugVariablesWindow }

class function TAtlasIdeDebugVariablesWindow.Show: TAtlasDebugVariablesFrame;
begin
  // Lebt die Form noch (X versteckt nur), wird sie samt Gastgebern gezeigt; sonst neu angelegt.
  EnsureHost;
  Host.Present;
  Result := ExistingFrame;
end;

class function TAtlasIdeDebugVariablesWindow.ExistingFrame: TAtlasDebugVariablesFrame;
begin
  Result := nil;
  if (Host <> nil) and (Host.Frame is TAtlasDebugVariablesFrame) then
  begin
    Result := TAtlasDebugVariablesFrame(Host.Frame);
  end;
end;

class function TAtlasIdeDebugVariablesWindow.Visible: Boolean;
begin
  Result := TAtlasIdeDockWindow.IsShown(Host);
end;

class procedure TAtlasIdeDebugVariablesWindow.Hide;
begin
  TAtlasIdeDockWindow.HideIfAny(Host);
end;

class procedure TAtlasIdeDebugVariablesWindow.ApplyTheme;
var
  mFrame: TAtlasDebugVariablesFrame;
begin
  mFrame := ExistingFrame;
  if mFrame <> nil then
  begin
    Theme(mFrame);
  end;
  TAtlasIdeDockWindow.UpdateIcon(Host);
end;

class procedure TAtlasIdeDebugVariablesWindow.Prepare;
begin
  EnsureHost;
end;

class procedure TAtlasIdeDebugVariablesWindow.Release;
begin
  OnFrame := nil;
  // Meldet ab und gibt die Form nur frei, wenn die IDE sie nicht schon zerstört hat.
  FreeAndNil(Host);
end;

end.
