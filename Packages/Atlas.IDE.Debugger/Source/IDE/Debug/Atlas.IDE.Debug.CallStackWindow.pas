unit Atlas.IDE.Debug.CallStackWindow;

// Andockbares Seitenfenster „Atlas-Aufrufstapel“ (#843): verankerbar wie die
// Lesezeichen (#622) über INTAServices.CreateDockableForm, Inhalt
// TAtlasDebugCallStackFrame, IDE-Thema, Atlas-Symbol (#751) im Fenstertitel.
// OnFrame meldet einen neuen Frame, damit TAtlasIdeDebugCallStack ihn
// verdrahtet und füllt.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Forms,
  Atlas.UI.Debug.CallStackFrame;

type
  TAtlasIdeDebugCallStackWindow = class
  public class var
    /// <summary>Ein neuer Frame ist entstanden; setzt TAtlasIdeDebugCallStack.</summary>
    OnFrame: TProc<TAtlasDebugCallStackFrame>;
  public
    /// <summary>Fenster zeigen (bei Bedarf anlegen); nil, wenn die IDE keine andockbaren Fenster anbietet.</summary>
    class function Show: TAtlasDebugCallStackFrame; static;
    /// <summary>Frame, falls das Fenster existiert; legt nichts an.</summary>
    class function ExistingFrame: TAtlasDebugCallStackFrame; static;
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
  TCallStackDock = class(TInterfacedObject, INTACustomDockableForm)
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

{ TCallStackDock }

function TCallStackDock.GetCaption: string;
begin
  Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.CallStackCaption);
end;

function TCallStackDock.GetIdentifier: string;
begin
  Result := 'AtlasDebugCallStack';
end;

function TCallStackDock.GetFrameClass: TCustomFrameClass;
begin
  Result := TAtlasDebugCallStackFrame;
end;

procedure TCallStackDock.FrameCreated(AFrame: TCustomFrame);
var
  mFrame: TAtlasDebugCallStackFrame;
begin
  if not (AFrame is TAtlasDebugCallStackFrame) then
  begin
    Exit;
  end;
  if Host <> nil then
  begin
    Host.FrameCreated(AFrame);
  end;
  mFrame := TAtlasDebugCallStackFrame(AFrame);
  TAtlasIdeDockWindow.UpdateIcon(Host);
  Theme(mFrame);
  if Assigned(TAtlasIdeDebugCallStackWindow.OnFrame) then
  begin
    TAtlasIdeDebugCallStackWindow.OnFrame(mFrame);
  end;
end;

function TCallStackDock.GetMenuActionList: TCustomActionList;
begin
  Result := nil;
end;

function TCallStackDock.GetMenuImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TCallStackDock.CustomizePopupMenu(PopupMenu: TPopupMenu);
begin
end;

function TCallStackDock.GetToolbarActionList: TCustomActionList;
begin
  Result := nil;
end;

function TCallStackDock.GetToolbarImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TCallStackDock.CustomizeToolBar(ToolBar: TToolBar);
begin
end;

procedure TCallStackDock.SaveWindowState(Desktop: TCustomIniFile; const Section: string; IsProject: Boolean);
begin
end;

procedure TCallStackDock.LoadWindowState(Desktop: TCustomIniFile; const Section: string);
begin
end;

function TCallStackDock.GetEditState: TEditState;
begin
  Result := [];
end;

function TCallStackDock.EditAction(Action: TEditAction): Boolean;
begin
  Result := False;
end;

procedure EnsureHost;
begin
  if Host = nil then
  begin
    Host := TAtlasIdeDockWindow.Create(TCallStackDock.Create, True);
  end;
end;

{ TAtlasIdeDebugCallStackWindow }

class function TAtlasIdeDebugCallStackWindow.Show: TAtlasDebugCallStackFrame;
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

class function TAtlasIdeDebugCallStackWindow.ExistingFrame: TAtlasDebugCallStackFrame;
begin
  Result := nil;
  if (Host <> nil) and (Host.Frame is TAtlasDebugCallStackFrame) then
  begin
    Result := TAtlasDebugCallStackFrame(Host.Frame);
  end;
end;

class function TAtlasIdeDebugCallStackWindow.Visible: Boolean;
begin
  // Angedockt in verstecktem Gastgeber zählt nicht als sichtbar.
  Result := (Host <> nil) and Host.Shown;
end;

class procedure TAtlasIdeDebugCallStackWindow.Hide;
begin
  if Host <> nil then
  begin
    Host.Hide;
  end;
end;

class procedure TAtlasIdeDebugCallStackWindow.ApplyTheme;
var
  mFrame: TAtlasDebugCallStackFrame;
begin
  mFrame := ExistingFrame;
  if mFrame <> nil then
  begin
    Theme(mFrame);
  end;
  TAtlasIdeDockWindow.UpdateIcon(Host);
end;

class procedure TAtlasIdeDebugCallStackWindow.Prepare;
begin
  EnsureHost;
end;

class procedure TAtlasIdeDebugCallStackWindow.Release;
begin
  OnFrame := nil;
  // Meldet ab und gibt die Form nur frei, wenn die IDE sie nicht schon zerstört hat.
  FreeAndNil(Host);
end;

end.
