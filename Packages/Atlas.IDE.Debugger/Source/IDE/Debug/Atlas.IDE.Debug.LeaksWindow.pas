unit Atlas.IDE.Debug.LeaksWindow;

// Andockbares Seitenfenster „Atlas-Lecks“ (#1875): verankerbar wie die
// Lesezeichen (#622) über TAtlasIdeDockWindow, Inhalt TAtlasDebugLeaksFrame,
// IDE-Thema, Atlas-Symbol (#751) im Fenstertitel. OnFrame meldet einen neuen
// Frame, damit TAtlasIdeDebugLeaks ihn verdrahtet und füllt.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Forms,
  Atlas.UI.Debug.LeaksFrame;

type
  TAtlasIdeDebugLeaksWindow = class
  public class var
    /// <summary>Ein neuer Frame ist entstanden; setzt TAtlasIdeDebugLeaks.</summary>
    OnFrame: TProc<TAtlasDebugLeaksFrame>;
  public
    /// <summary>Fenster zeigen (bei Bedarf anlegen); nil, wenn die IDE keine andockbaren Fenster anbietet.</summary>
    class function Show: TAtlasDebugLeaksFrame; static;
    /// <summary>Frame, falls das Fenster existiert; legt nichts an.</summary>
    class function ExistingFrame: TAtlasDebugLeaksFrame; static;
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
  TLeaksDock = class(TInterfacedObject, INTACustomDockableForm)
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

{ TLeaksDock }

function TLeaksDock.GetCaption: string;
begin
  Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.LeaksCaption);
end;

function TLeaksDock.GetIdentifier: string;
begin
  Result := 'AtlasDebugLeaks';
end;

function TLeaksDock.GetFrameClass: TCustomFrameClass;
begin
  Result := TAtlasDebugLeaksFrame;
end;

procedure TLeaksDock.FrameCreated(AFrame: TCustomFrame);
var
  mFrame: TAtlasDebugLeaksFrame;
begin
  if not (AFrame is TAtlasDebugLeaksFrame) then
  begin
    Exit;
  end;
  if Host <> nil then
  begin
    Host.FrameCreated(AFrame);
  end;
  mFrame := TAtlasDebugLeaksFrame(AFrame);
  TAtlasIdeDockWindow.UpdateIcon(Host);
  Theme(mFrame);
  if Assigned(TAtlasIdeDebugLeaksWindow.OnFrame) then
  begin
    TAtlasIdeDebugLeaksWindow.OnFrame(mFrame);
  end;
end;

function TLeaksDock.GetMenuActionList: TCustomActionList;
begin
  Result := nil;
end;

function TLeaksDock.GetMenuImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TLeaksDock.CustomizePopupMenu(PopupMenu: TPopupMenu);
begin
end;

function TLeaksDock.GetToolbarActionList: TCustomActionList;
begin
  Result := nil;
end;

function TLeaksDock.GetToolbarImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TLeaksDock.CustomizeToolBar(ToolBar: TToolBar);
begin
end;

procedure TLeaksDock.SaveWindowState(Desktop: TCustomIniFile; const Section: string; IsProject: Boolean);
begin
end;

procedure TLeaksDock.LoadWindowState(Desktop: TCustomIniFile; const Section: string);
begin
end;

function TLeaksDock.GetEditState: TEditState;
begin
  Result := [];
end;

function TLeaksDock.EditAction(Action: TEditAction): Boolean;
begin
  Result := False;
end;

procedure EnsureHost;
begin
  if Host = nil then
  begin
    Host := TAtlasIdeDockWindow.Create(TLeaksDock.Create, True);
  end;
end;

{ TAtlasIdeDebugLeaksWindow }

class function TAtlasIdeDebugLeaksWindow.Show: TAtlasDebugLeaksFrame;
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

class function TAtlasIdeDebugLeaksWindow.ExistingFrame: TAtlasDebugLeaksFrame;
begin
  Result := nil;
  if (Host <> nil) and (Host.Frame is TAtlasDebugLeaksFrame) then
  begin
    Result := TAtlasDebugLeaksFrame(Host.Frame);
  end;
end;

class function TAtlasIdeDebugLeaksWindow.Visible: Boolean;
begin
  // Angedockt in verstecktem Gastgeber zählt nicht als sichtbar.
  Result := (Host <> nil) and Host.Shown;
end;

class procedure TAtlasIdeDebugLeaksWindow.Hide;
begin
  if Host <> nil then
  begin
    Host.Hide;
  end;
end;

class procedure TAtlasIdeDebugLeaksWindow.ApplyTheme;
var
  mFrame: TAtlasDebugLeaksFrame;
begin
  mFrame := ExistingFrame;
  if mFrame <> nil then
  begin
    Theme(mFrame);
  end;
  TAtlasIdeDockWindow.UpdateIcon(Host);
end;

class procedure TAtlasIdeDebugLeaksWindow.Prepare;
begin
  EnsureHost;
end;

class procedure TAtlasIdeDebugLeaksWindow.Release;
begin
  OnFrame := nil;
  // Meldet ab und gibt die Form nur frei, wenn die IDE sie nicht schon zerstört hat.
  FreeAndNil(Host);
end;

end.
