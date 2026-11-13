unit Atlas.IDE.Tests.ExplorerWindow;

// Andockbares Fenster „Atlas-Tests“ (#1776): verankerbar wie die Lesezeichen
// (#622) über TAtlasIdeDockWindow, im Desktop gespeichert und beim Laden
// wiederhergestellt (#879), Inhalt TAtlasTestsExplorerFrame, IDE-Thema,
// Atlas-Symbol (#751) im Fenstertitel. OnFrame meldet einen neuen Frame,
// damit TAtlasIdeTestExplorer ihn verdrahtet und füllt.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Forms,
  Atlas.UI.Tests.ExplorerFrame;

type
  TAtlasIdeTestsExplorerWindow = class
  public class var
    /// <summary>Ein neuer Frame ist entstanden; setzt TAtlasIdeTestExplorer.</summary>
    OnFrame: TProc<TAtlasTestsExplorerFrame>;
  public
    /// <summary>Fenster zeigen (bei Bedarf anlegen); nil, wenn die IDE keine andockbaren Fenster anbietet.</summary>
    class function Show: TAtlasTestsExplorerFrame; static;
    /// <summary>Frame, falls das Fenster existiert; legt nichts an.</summary>
    class function ExistingFrame: TAtlasTestsExplorerFrame; static;
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
  Atlas.UI.Tests.Strings,
  Atlas.UI.Style.Symbol,
  Atlas.IDE.Foundation.DockWindow;

type
  TExplorerDock = class(TInterfacedObject, INTACustomDockableForm)
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

{ TExplorerDock }

function TExplorerDock.GetCaption: string;
begin
  Result := TAtlasTestsStrings.Text(TAtlasTestsTextId.ExplorerCommand);
end;

function TExplorerDock.GetIdentifier: string;
begin
  Result := 'AtlasTestsExplorer';
end;

function TExplorerDock.GetFrameClass: TCustomFrameClass;
begin
  Result := TAtlasTestsExplorerFrame;
end;

procedure TExplorerDock.FrameCreated(AFrame: TCustomFrame);
var
  mFrame: TAtlasTestsExplorerFrame;
begin
  if not (AFrame is TAtlasTestsExplorerFrame) then
  begin
    Exit;
  end;
  if Host <> nil then
  begin
    Host.FrameCreated(AFrame);
  end;
  mFrame := TAtlasTestsExplorerFrame(AFrame);
  TAtlasIdeDockWindow.UpdateIcon(Host);
  Theme(mFrame);
  if Assigned(TAtlasIdeTestsExplorerWindow.OnFrame) then
  begin
    TAtlasIdeTestsExplorerWindow.OnFrame(mFrame);
  end;
end;

function TExplorerDock.GetMenuActionList: TCustomActionList;
begin
  Result := nil;
end;

function TExplorerDock.GetMenuImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TExplorerDock.CustomizePopupMenu(PopupMenu: TPopupMenu);
begin
end;

function TExplorerDock.GetToolbarActionList: TCustomActionList;
begin
  Result := nil;
end;

function TExplorerDock.GetToolbarImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TExplorerDock.CustomizeToolBar(ToolBar: TToolBar);
begin
end;

procedure TExplorerDock.SaveWindowState(Desktop: TCustomIniFile; const Section: string; IsProject: Boolean);
begin
end;

procedure TExplorerDock.LoadWindowState(Desktop: TCustomIniFile; const Section: string);
begin
end;

function TExplorerDock.GetEditState: TEditState;
begin
  Result := [];
end;

function TExplorerDock.EditAction(Action: TEditAction): Boolean;
begin
  Result := False;
end;

procedure EnsureHost;
begin
  if Host = nil then
  begin
    Host := TAtlasIdeDockWindow.Create(TExplorerDock.Create, True);
  end;
end;

{ TAtlasIdeTestsExplorerWindow }

class function TAtlasIdeTestsExplorerWindow.Show: TAtlasTestsExplorerFrame;
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

class function TAtlasIdeTestsExplorerWindow.ExistingFrame: TAtlasTestsExplorerFrame;
begin
  Result := nil;
  if (Host <> nil) and (Host.Frame is TAtlasTestsExplorerFrame) then
  begin
    Result := TAtlasTestsExplorerFrame(Host.Frame);
  end;
end;

class function TAtlasIdeTestsExplorerWindow.Visible: Boolean;
begin
  // Angedockt in verstecktem Gastgeber zählt nicht als sichtbar.
  Result := (Host <> nil) and Host.Shown;
end;

class procedure TAtlasIdeTestsExplorerWindow.Hide;
begin
  if Host <> nil then
  begin
    Host.Hide;
  end;
end;

class procedure TAtlasIdeTestsExplorerWindow.ApplyTheme;
var
  mFrame: TAtlasTestsExplorerFrame;
begin
  mFrame := ExistingFrame;
  if mFrame <> nil then
  begin
    Theme(mFrame);
  end;
  TAtlasIdeDockWindow.UpdateIcon(Host);
end;

class procedure TAtlasIdeTestsExplorerWindow.Prepare;
begin
  EnsureHost;
end;

class procedure TAtlasIdeTestsExplorerWindow.Release;
begin
  OnFrame := nil;
  // Meldet ab und gibt die Form nur frei, wenn die IDE sie nicht schon zerstört hat.
  FreeAndNil(Host);
end;

end.
