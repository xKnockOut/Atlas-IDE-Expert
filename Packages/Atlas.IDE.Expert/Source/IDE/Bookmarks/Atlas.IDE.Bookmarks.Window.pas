unit Atlas.IDE.Bookmarks.Window;

// Andockbares Seitenfenster „Lesezeichen“ (#622): verankerbar wie das
// Diagnosefenster (#479) über INTAServices.CreateDockableForm, Inhalt
// TAtlasBookmarksFrame, IDE-Thema, Atlas-Symbol (#751) im Fenstertitel.
// OnFrame meldet einen neuen Frame, damit TAtlasIdeBookmarks ihn verdrahtet
// und füllt.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Forms,
  Atlas.UI.Bookmarks.Frame;

type
  TAtlasIdeBookmarksWindow = class
  public class var
    /// <summary>Ein neuer Frame ist entstanden; setzt TAtlasIdeBookmarks.</summary>
    OnFrame: TProc<TAtlasBookmarksFrame>;
  public
    /// <summary>Fenster zeigen (bei Bedarf anlegen); nil, wenn die IDE keine andockbaren Fenster anbietet.</summary>
    class function Show: TAtlasBookmarksFrame; static;
    /// <summary>Frame, falls das Fenster existiert; legt nichts an.</summary>
    class function ExistingFrame: TAtlasBookmarksFrame; static;
    class function Visible: Boolean; static;
    class procedure Hide; static;
    class procedure UpdateIcon; static;
    class procedure ApplyTheme; static;
    /// <summary>Früh (Register): bei der IDE anmelden, damit der Desktop das Fenster speichert und wiederherstellt (#879).</summary>
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
  Atlas.UI.Strings,
  Atlas.UI.Style.Symbol,
  Atlas.IDE.Foundation.Symbol,
  Atlas.IDE.Foundation.DockWindow;

type
  TBookmarksDock = class(TInterfacedObject, INTACustomDockableForm)
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

{ TBookmarksDock }

function TBookmarksDock.GetCaption: string;
begin
  Result := TAtlasStrings.Text(TAtlasTextId.BookmarksCaption);
end;

function TBookmarksDock.GetIdentifier: string;
begin
  Result := 'AtlasBookmarks';
end;

function TBookmarksDock.GetFrameClass: TCustomFrameClass;
begin
  Result := TAtlasBookmarksFrame;
end;

procedure TBookmarksDock.FrameCreated(AFrame: TCustomFrame);
var
  Frame: TAtlasBookmarksFrame;
begin
  if not (AFrame is TAtlasBookmarksFrame) then
    Exit;
  if Host <> nil then
    Host.FrameCreated(AFrame);
  Frame := TAtlasBookmarksFrame(AFrame);
  TAtlasIdeBookmarksWindow.UpdateIcon;
  Theme(Frame);
  if Assigned(TAtlasIdeBookmarksWindow.OnFrame) then
    TAtlasIdeBookmarksWindow.OnFrame(Frame);
end;

function TBookmarksDock.GetMenuActionList: TCustomActionList;
begin
  Result := nil;
end;

function TBookmarksDock.GetMenuImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TBookmarksDock.CustomizePopupMenu(PopupMenu: TPopupMenu);
begin
end;

function TBookmarksDock.GetToolbarActionList: TCustomActionList;
begin
  Result := nil;
end;

function TBookmarksDock.GetToolbarImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TBookmarksDock.CustomizeToolBar(ToolBar: TToolBar);
begin
end;

procedure TBookmarksDock.SaveWindowState(Desktop: TCustomIniFile; const Section: string; IsProject: Boolean);
begin
end;

procedure TBookmarksDock.LoadWindowState(Desktop: TCustomIniFile; const Section: string);
begin
end;

function TBookmarksDock.GetEditState: TEditState;
begin
  Result := [];
end;

function TBookmarksDock.EditAction(Action: TEditAction): Boolean;
begin
  Result := False;
end;

procedure EnsureHost;
begin
  if Host = nil then
    Host := TAtlasIdeDockWindow.Create(TBookmarksDock.Create, True);
end;

{ TAtlasIdeBookmarksWindow }

class function TAtlasIdeBookmarksWindow.Show: TAtlasBookmarksFrame;
var
  Created: Boolean;
begin
  // Lebt die Form noch (X versteckt nur), wird sie samt Gastgebern gezeigt; sonst neu angelegt.
  EnsureHost;
  Host.Show(Created);
  if Created then
    UpdateIcon;
  Result := ExistingFrame;
end;

class function TAtlasIdeBookmarksWindow.ExistingFrame: TAtlasBookmarksFrame;
begin
  Result := nil;
  if (Host <> nil) and (Host.Frame is TAtlasBookmarksFrame) then
    Result := TAtlasBookmarksFrame(Host.Frame);
end;

class function TAtlasIdeBookmarksWindow.Visible: Boolean;
begin
  // Angedockt in verstecktem Gastgeber zählt nicht als sichtbar.
  Result := (Host <> nil) and Host.Shown;
end;

class procedure TAtlasIdeBookmarksWindow.Hide;
begin
  if Host <> nil then
    Host.Hide;
end;

class procedure TAtlasIdeBookmarksWindow.UpdateIcon;
var
  Icon: TIcon;
begin
  if (Host = nil) or (Host.Form = nil) then
    Exit;
  Icon := TAtlasSymbolImages.Icon(TAtlasIdeSymbol.Current);
  try
    // Icon ist erst in TForm öffentlich.
    TForm(Host.Form).Icon.Assign(Icon);
  finally
    Icon.Free;
  end;
end;

class procedure TAtlasIdeBookmarksWindow.ApplyTheme;
var
  Frame: TAtlasBookmarksFrame;
begin
  Frame := ExistingFrame;
  if Frame <> nil then
    Theme(Frame);
  UpdateIcon;
end;

class procedure TAtlasIdeBookmarksWindow.Prepare;
begin
  EnsureHost;
end;

class procedure TAtlasIdeBookmarksWindow.Release;
begin
  OnFrame := nil;
  // Meldet ab und gibt die Form nur frei, wenn die IDE sie nicht schon zerstört hat.
  FreeAndNil(Host);
end;

end.
