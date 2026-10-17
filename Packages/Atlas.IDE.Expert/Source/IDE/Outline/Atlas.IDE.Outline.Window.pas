unit Atlas.IDE.Outline.Window;

// Andockbares Seitenfenster „Gliederung“ (#537): verankerbar wie das
// Diagnosefenster (#479) über INTAServices.CreateDockableForm, Inhalt
// TAtlasOutlineFrame, IDE-Thema, Atlas-Symbol (#751) im Fenstertitel.
// OnFrame meldet einen neuen Frame, damit TAtlasIdeOutline ihn verdrahtet
// und füllt.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Forms,
  Atlas.UI.Outline.Frame;

type
  TAtlasIdeOutlineWindow = class
  public class var
    /// <summary>Ein neuer Frame ist entstanden; setzt TAtlasIdeOutline.</summary>
    OnFrame: TProc<TAtlasOutlineFrame>;
  public
    /// <summary>Fenster zeigen (bei Bedarf anlegen); nil, wenn die IDE keine andockbaren Fenster anbietet.</summary>
    class function Show: TAtlasOutlineFrame; static;
    /// <summary>Frame, falls das Fenster existiert; legt nichts an.</summary>
    class function ExistingFrame: TAtlasOutlineFrame; static;
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
  Atlas.IDE.Foundation.Symbol;

type
  TOutlineDock = class(TInterfacedObject, INTACustomDockableForm)
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
  Frame: TAtlasOutlineFrame;
  Watch: TWatch;

procedure Theme(AFrame: TCustomFrame);
var
  Theming: IOTAIDEThemingServices;
begin
  if (AFrame <> nil) and Supports(BorlandIDEServices, IOTAIDEThemingServices, Theming) and
    Theming.IDEThemingEnabled then
    Theming.ApplyTheme(AFrame);
end;

{ TOutlineDock }

function TOutlineDock.GetCaption: string;
begin
  Result := TAtlasStrings.Text(TAtlasTextId.OutlineCaption);
end;

function TOutlineDock.GetIdentifier: string;
begin
  Result := 'AtlasOutline';
end;

function TOutlineDock.GetFrameClass: TCustomFrameClass;
begin
  Result := TAtlasOutlineFrame;
end;

procedure TOutlineDock.FrameCreated(AFrame: TCustomFrame);
begin
  if not (AFrame is TAtlasOutlineFrame) then
    Exit;
  Frame := TAtlasOutlineFrame(AFrame);
  Frame.FreeNotification(Watch);
  Theme(Frame);
  if Assigned(TAtlasIdeOutlineWindow.OnFrame) then
    TAtlasIdeOutlineWindow.OnFrame(Frame);
end;

function TOutlineDock.GetMenuActionList: TCustomActionList;
begin
  Result := nil;
end;

function TOutlineDock.GetMenuImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TOutlineDock.CustomizePopupMenu(PopupMenu: TPopupMenu);
begin
end;

function TOutlineDock.GetToolbarActionList: TCustomActionList;
begin
  Result := nil;
end;

function TOutlineDock.GetToolbarImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TOutlineDock.CustomizeToolBar(ToolBar: TToolBar);
begin
end;

procedure TOutlineDock.SaveWindowState(Desktop: TCustomIniFile; const Section: string; IsProject: Boolean);
begin
end;

procedure TOutlineDock.LoadWindowState(Desktop: TCustomIniFile; const Section: string);
begin
end;

function TOutlineDock.GetEditState: TEditState;
begin
  Result := [];
end;

function TOutlineDock.EditAction(Action: TEditAction): Boolean;
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

{ TAtlasIdeOutlineWindow }

class function TAtlasIdeOutlineWindow.Show: TAtlasOutlineFrame;
var
  Services: INTAServices;
begin
  if Form = nil then
  begin
    if not Supports(BorlandIDEServices, INTAServices, Services) then
      Exit(nil);
    if Watch = nil then
      Watch := TWatch.Create(nil);
    Dock := TOutlineDock.Create;
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

class function TAtlasIdeOutlineWindow.ExistingFrame: TAtlasOutlineFrame;
begin
  Result := nil;
  if Form <> nil then
    Result := Frame;
end;

class function TAtlasIdeOutlineWindow.Visible: Boolean;
begin
  Result := (Form <> nil) and Form.Visible;
end;

class procedure TAtlasIdeOutlineWindow.Hide;
begin
  if Form <> nil then
    Form.Hide;
end;

class procedure TAtlasIdeOutlineWindow.UpdateIcon;
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

class procedure TAtlasIdeOutlineWindow.ApplyTheme;
begin
  if Frame <> nil then
    Theme(Frame);
  UpdateIcon;
end;

class procedure TAtlasIdeOutlineWindow.Release;
begin
  OnFrame := nil;
  Frame := nil;
  FreeAndNil(Form);
  Dock := nil;
  FreeAndNil(Watch);
end;

end.
