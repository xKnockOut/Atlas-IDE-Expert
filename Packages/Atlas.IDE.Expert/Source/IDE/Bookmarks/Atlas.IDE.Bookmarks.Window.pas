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
  Atlas.IDE.Style.Symbol;

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

  TWatch = class(TComponent)
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  end;

var
  Dock: INTACustomDockableForm;
  Form: TCustomForm;
  Frame: TAtlasBookmarksFrame;
  Watch: TWatch;

procedure Theme(AFrame: TCustomFrame);
var
  Theming: IOTAIDEThemingServices;
begin
  if (AFrame <> nil) and Supports(BorlandIDEServices, IOTAIDEThemingServices, Theming) and
    Theming.IDEThemingEnabled then
    Theming.ApplyTheme(AFrame);
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
begin
  if not (AFrame is TAtlasBookmarksFrame) then
    Exit;
  Frame := TAtlasBookmarksFrame(AFrame);
  Frame.FreeNotification(Watch);
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

{ TWatch }

procedure TWatch.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if Operation <> opRemove then
    Exit;
  if AComponent = Frame then
    Frame := nil;
  if AComponent = Form then
  begin
    Form := nil;
    Frame := nil;
  end;
end;

{ TAtlasIdeBookmarksWindow }

class function TAtlasIdeBookmarksWindow.Show: TAtlasBookmarksFrame;
var
  Services: INTAServices;
begin
  if Form = nil then
  begin
    if not Supports(BorlandIDEServices, INTAServices, Services) then
      Exit(nil);
    if Watch = nil then
      Watch := TWatch.Create(nil);
    Dock := TBookmarksDock.Create;
    Form := Services.CreateDockableForm(Dock);
    if Form <> nil then
    begin
      Form.FreeNotification(Watch);
      UpdateIcon;
    end;
  end;
  if Form <> nil then
  begin
    Form.Show;
    Form.BringToFront;
  end;
  Result := Frame;
end;

class function TAtlasIdeBookmarksWindow.ExistingFrame: TAtlasBookmarksFrame;
begin
  Result := nil;
  if Form <> nil then
    Result := Frame;
end;

class function TAtlasIdeBookmarksWindow.Visible: Boolean;
begin
  Result := (Form <> nil) and Form.Visible;
end;

class procedure TAtlasIdeBookmarksWindow.Hide;
begin
  if Form <> nil then
    Form.Hide;
end;

class procedure TAtlasIdeBookmarksWindow.UpdateIcon;
var
  Icon: TIcon;
begin
  if Form = nil then
    Exit;
  Icon := TAtlasSymbolImages.Icon(TAtlasIdeSymbol.Current);
  try
    // Icon ist erst in TForm öffentlich.
    TForm(Form).Icon.Assign(Icon);
  finally
    Icon.Free;
  end;
end;

class procedure TAtlasIdeBookmarksWindow.ApplyTheme;
begin
  if Frame <> nil then
    Theme(Frame);
  UpdateIcon;
end;

class procedure TAtlasIdeBookmarksWindow.Release;
begin
  OnFrame := nil;
  Frame := nil;
  FreeAndNil(Form);
  Dock := nil;
  FreeAndNil(Watch);
end;

end.
