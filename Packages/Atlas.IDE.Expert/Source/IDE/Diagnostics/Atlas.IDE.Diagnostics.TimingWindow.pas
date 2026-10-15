unit Atlas.IDE.Diagnostics.TimingWindow;

// Andockbares Fenster „Atlas-Diagnose“ (#479): klein, verankerbar wie das
// Ergebnisfenster (#400) über INTAServices.CreateDockableForm, Inhalt
// TAtlasTimingFrame, IDE-Thema, Atlas-Symbol (#751) im Fenstertitel. OnFrame
// meldet einen neuen Frame, damit TAtlasIdeDiagnosticMode ihn füllt.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Forms,
  Atlas.UI.Diagnostics.TimingFrame;

type
  TAtlasIdeTimingWindow = class
  public class var
    /// <summary>Ein neuer Frame ist entstanden; setzt der Diagnosemodus.</summary>
    OnFrame: TProc<TAtlasTimingFrame>;
  public
    /// <summary>Fenster zeigen (bei Bedarf anlegen); nil, wenn die IDE keine andockbaren Fenster anbietet.</summary>
    class function Show: TAtlasTimingFrame; static;
    /// <summary>Frame, falls das Fenster existiert; legt nichts an.</summary>
    class function ExistingFrame: TAtlasTimingFrame; static;
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
  TTimingDock = class(TInterfacedObject, INTACustomDockableForm)
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
  Frame: TAtlasTimingFrame;
  Watch: TWatch;

procedure Theme(AFrame: TCustomFrame);
var
  Theming: IOTAIDEThemingServices;
begin
  if (AFrame <> nil) and Supports(BorlandIDEServices, IOTAIDEThemingServices, Theming) and
    Theming.IDEThemingEnabled then
    Theming.ApplyTheme(AFrame);
end;

{ TTimingDock }

function TTimingDock.GetCaption: string;
begin
  Result := TAtlasStrings.Text(TAtlasTextId.DiagnosticCaption);
end;

function TTimingDock.GetIdentifier: string;
begin
  Result := 'AtlasDiagnostics';
end;

function TTimingDock.GetFrameClass: TCustomFrameClass;
begin
  Result := TAtlasTimingFrame;
end;

procedure TTimingDock.FrameCreated(AFrame: TCustomFrame);
begin
  if not (AFrame is TAtlasTimingFrame) then
    Exit;
  Frame := TAtlasTimingFrame(AFrame);
  Frame.FreeNotification(Watch);
  Theme(Frame);
  if Assigned(TAtlasIdeTimingWindow.OnFrame) then
    TAtlasIdeTimingWindow.OnFrame(Frame);
end;

function TTimingDock.GetMenuActionList: TCustomActionList;
begin
  Result := nil;
end;

function TTimingDock.GetMenuImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TTimingDock.CustomizePopupMenu(PopupMenu: TPopupMenu);
begin
end;

function TTimingDock.GetToolbarActionList: TCustomActionList;
begin
  Result := nil;
end;

function TTimingDock.GetToolbarImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TTimingDock.CustomizeToolBar(ToolBar: TToolBar);
begin
end;

procedure TTimingDock.SaveWindowState(Desktop: TCustomIniFile; const Section: string; IsProject: Boolean);
begin
end;

procedure TTimingDock.LoadWindowState(Desktop: TCustomIniFile; const Section: string);
begin
end;

function TTimingDock.GetEditState: TEditState;
begin
  Result := [];
end;

function TTimingDock.EditAction(Action: TEditAction): Boolean;
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

{ TAtlasIdeTimingWindow }

class function TAtlasIdeTimingWindow.Show: TAtlasTimingFrame;
var
  Services: INTAServices;
begin
  if Form = nil then
  begin
    if not Supports(BorlandIDEServices, INTAServices, Services) then
      Exit(nil);
    if Watch = nil then
      Watch := TWatch.Create(nil);
    Dock := TTimingDock.Create;
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

class function TAtlasIdeTimingWindow.ExistingFrame: TAtlasTimingFrame;
begin
  Result := nil;
  if Form <> nil then
    Result := Frame;
end;

class function TAtlasIdeTimingWindow.Visible: Boolean;
begin
  Result := (Form <> nil) and Form.Visible;
end;

class procedure TAtlasIdeTimingWindow.Hide;
begin
  if Form <> nil then
    Form.Hide;
end;

class procedure TAtlasIdeTimingWindow.UpdateIcon;
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

class procedure TAtlasIdeTimingWindow.ApplyTheme;
begin
  if Frame <> nil then
    Theme(Frame);
  UpdateIcon;
end;

class procedure TAtlasIdeTimingWindow.Release;
begin
  OnFrame := nil;
  Frame := nil;
  FreeAndNil(Form);
  Dock := nil;
  FreeAndNil(Watch);
end;

end.
