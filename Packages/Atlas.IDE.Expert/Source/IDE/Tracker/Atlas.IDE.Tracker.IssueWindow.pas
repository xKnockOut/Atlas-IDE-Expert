unit Atlas.IDE.Tracker.IssueWindow;

// Andockbares Fenster „Atlas-Issue“ (#1264): verankerbar wie „Lesezeichen“
// (#622) über INTAServices.CreateDockableForm, Inhalt TAtlasIssueFrame,
// IDE-Thema, Atlas-Symbol (#751) im Fenstertitel; die IDE speichert es im
// Desktop (#879). OnFrame meldet einen neuen Frame, damit
// TAtlasIdeIssuePreview ihn verdrahtet und füllt.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Forms,
  Atlas.UI.Tracker.IssueFrame;

type
  TAtlasIdeIssueWindow = class
  public class var
    /// <summary>Ein neuer Frame ist entstanden; setzt TAtlasIdeIssuePreview.</summary>
    OnFrame: TProc<TAtlasIssueFrame>;
  public
    /// <summary>Fenster zeigen (bei Bedarf anlegen); nil, wenn die IDE keine andockbaren Fenster anbietet.</summary>
    class function Show: TAtlasIssueFrame; static;
    /// <summary>Frame, falls das Fenster existiert; legt nichts an.</summary>
    class function ExistingFrame: TAtlasIssueFrame; static;
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
  TIssueDock = class(TInterfacedObject, INTACustomDockableForm)
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

{ TIssueDock }

function TIssueDock.GetCaption: string;
begin
  Result := TAtlasStrings.Text(TAtlasTextId.IssuePreviewCaption);
end;

function TIssueDock.GetIdentifier: string;
begin
  Result := 'AtlasIssue';
end;

function TIssueDock.GetFrameClass: TCustomFrameClass;
begin
  Result := TAtlasIssueFrame;
end;

procedure TIssueDock.FrameCreated(AFrame: TCustomFrame);
var
  Frame: TAtlasIssueFrame;
begin
  if not (AFrame is TAtlasIssueFrame) then
    Exit;
  if Host <> nil then
    Host.FrameCreated(AFrame);
  Frame := TAtlasIssueFrame(AFrame);
  TAtlasIdeIssueWindow.UpdateIcon;
  Theme(Frame);
  if Assigned(TAtlasIdeIssueWindow.OnFrame) then
    TAtlasIdeIssueWindow.OnFrame(Frame);
end;

function TIssueDock.GetMenuActionList: TCustomActionList;
begin
  Result := nil;
end;

function TIssueDock.GetMenuImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TIssueDock.CustomizePopupMenu(PopupMenu: TPopupMenu);
begin
end;

function TIssueDock.GetToolbarActionList: TCustomActionList;
begin
  Result := nil;
end;

function TIssueDock.GetToolbarImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TIssueDock.CustomizeToolBar(ToolBar: TToolBar);
begin
end;

procedure TIssueDock.SaveWindowState(Desktop: TCustomIniFile; const Section: string; IsProject: Boolean);
begin
end;

procedure TIssueDock.LoadWindowState(Desktop: TCustomIniFile; const Section: string);
begin
end;

function TIssueDock.GetEditState: TEditState;
begin
  Result := [];
end;

function TIssueDock.EditAction(Action: TEditAction): Boolean;
begin
  Result := False;
end;

procedure EnsureHost;
begin
  if Host = nil then
    Host := TAtlasIdeDockWindow.Create(TIssueDock.Create, True);
end;

{ TAtlasIdeIssueWindow }

class function TAtlasIdeIssueWindow.Show: TAtlasIssueFrame;
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

class function TAtlasIdeIssueWindow.ExistingFrame: TAtlasIssueFrame;
begin
  Result := nil;
  if (Host <> nil) and (Host.Frame is TAtlasIssueFrame) then
    Result := TAtlasIssueFrame(Host.Frame);
end;

class function TAtlasIdeIssueWindow.Visible: Boolean;
begin
  // Angedockt in verstecktem Gastgeber zählt nicht als sichtbar.
  Result := (Host <> nil) and Host.Shown;
end;

class procedure TAtlasIdeIssueWindow.Hide;
begin
  if Host <> nil then
    Host.Hide;
end;

class procedure TAtlasIdeIssueWindow.UpdateIcon;
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

class procedure TAtlasIdeIssueWindow.ApplyTheme;
var
  Frame: TAtlasIssueFrame;
begin
  Frame := ExistingFrame;
  if Frame <> nil then
    Theme(Frame);
  UpdateIcon;
end;

class procedure TAtlasIdeIssueWindow.Prepare;
begin
  EnsureHost;
end;

class procedure TAtlasIdeIssueWindow.Release;
begin
  OnFrame := nil;
  // Meldet ab und gibt die Form nur frei, wenn die IDE sie nicht schon zerstört hat.
  FreeAndNil(Host);
end;

end.
