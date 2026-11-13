unit Atlas.IDE.Debug.ParallelStacksWindow;

// Andockbares Seitenfenster „Parallele Aufrufstapel“ (#837): verankerbar wie die
// Lesezeichen (#622) über INTAServices.CreateDockableForm, Inhalt
// TAtlasDebugParallelStacksFrame, IDE-Thema, Atlas-Symbol (#751) im Fenstertitel.
// OnFrame meldet einen neuen Frame, damit TAtlasIdeDebugParallelStacks ihn
// verdrahtet und füllt.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Forms,
  Atlas.UI.Debug.ParallelStacksFrame;

type
  TAtlasIdeDebugParallelStacksWindow = class
  public class var
    /// <summary>Ein neuer Frame ist entstanden; setzt TAtlasIdeDebugParallelStacks.</summary>
    OnFrame: TProc<TAtlasDebugParallelStacksFrame>;
  public
    /// <summary>Fenster zeigen (bei Bedarf anlegen); nil, wenn die IDE keine andockbaren Fenster anbietet.</summary>
    class function Show: TAtlasDebugParallelStacksFrame; static;
    /// <summary>Frame, falls das Fenster existiert; legt nichts an.</summary>
    class function ExistingFrame: TAtlasDebugParallelStacksFrame; static;
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
  TParallelStacksDock = class(TInterfacedObject, INTACustomDockableForm)
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

{ TParallelStacksDock }

function TParallelStacksDock.GetCaption: string;
begin
  Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.ParallelStacksCaption);
end;

function TParallelStacksDock.GetIdentifier: string;
begin
  Result := 'AtlasDebugParallelStacks';
end;

function TParallelStacksDock.GetFrameClass: TCustomFrameClass;
begin
  Result := TAtlasDebugParallelStacksFrame;
end;

procedure TParallelStacksDock.FrameCreated(AFrame: TCustomFrame);
var
  mFrame: TAtlasDebugParallelStacksFrame;
begin
  if not (AFrame is TAtlasDebugParallelStacksFrame) then
  begin
    Exit;
  end;
  if Host <> nil then
  begin
    Host.FrameCreated(AFrame);
  end;
  mFrame := TAtlasDebugParallelStacksFrame(AFrame);
  TAtlasIdeDockWindow.UpdateIcon(Host);
  Theme(mFrame);
  if Assigned(TAtlasIdeDebugParallelStacksWindow.OnFrame) then
  begin
    TAtlasIdeDebugParallelStacksWindow.OnFrame(mFrame);
  end;
end;

function TParallelStacksDock.GetMenuActionList: TCustomActionList;
begin
  Result := nil;
end;

function TParallelStacksDock.GetMenuImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TParallelStacksDock.CustomizePopupMenu(PopupMenu: TPopupMenu);
begin
end;

function TParallelStacksDock.GetToolbarActionList: TCustomActionList;
begin
  Result := nil;
end;

function TParallelStacksDock.GetToolbarImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TParallelStacksDock.CustomizeToolBar(ToolBar: TToolBar);
begin
end;

procedure TParallelStacksDock.SaveWindowState(Desktop: TCustomIniFile; const Section: string; IsProject: Boolean);
begin
end;

procedure TParallelStacksDock.LoadWindowState(Desktop: TCustomIniFile; const Section: string);
begin
end;

function TParallelStacksDock.GetEditState: TEditState;
begin
  Result := [];
end;

function TParallelStacksDock.EditAction(Action: TEditAction): Boolean;
begin
  Result := False;
end;

procedure EnsureHost;
begin
  if Host = nil then
  begin
    Host := TAtlasIdeDockWindow.Create(TParallelStacksDock.Create, True);
  end;
end;

{ TAtlasIdeDebugParallelStacksWindow }

class function TAtlasIdeDebugParallelStacksWindow.Show: TAtlasDebugParallelStacksFrame;
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

class function TAtlasIdeDebugParallelStacksWindow.ExistingFrame: TAtlasDebugParallelStacksFrame;
begin
  Result := nil;
  if (Host <> nil) and (Host.Frame is TAtlasDebugParallelStacksFrame) then
  begin
    Result := TAtlasDebugParallelStacksFrame(Host.Frame);
  end;
end;

class function TAtlasIdeDebugParallelStacksWindow.Visible: Boolean;
begin
  // Angedockt in verstecktem Gastgeber zählt nicht als sichtbar.
  Result := (Host <> nil) and Host.Shown;
end;

class procedure TAtlasIdeDebugParallelStacksWindow.Hide;
begin
  if Host <> nil then
  begin
    Host.Hide;
  end;
end;

class procedure TAtlasIdeDebugParallelStacksWindow.ApplyTheme;
var
  mFrame: TAtlasDebugParallelStacksFrame;
begin
  mFrame := ExistingFrame;
  if mFrame <> nil then
  begin
    Theme(mFrame);
  end;
  TAtlasIdeDockWindow.UpdateIcon(Host);
end;

class procedure TAtlasIdeDebugParallelStacksWindow.Prepare;
begin
  EnsureHost;
end;

class procedure TAtlasIdeDebugParallelStacksWindow.Release;
begin
  OnFrame := nil;
  // Meldet ab und gibt die Form nur frei, wenn die IDE sie nicht schon zerstört hat.
  FreeAndNil(Host);
end;

end.
