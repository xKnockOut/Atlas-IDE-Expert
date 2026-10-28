unit Atlas.IDE.Outline.Window;

// Andockbares Seitenfenster „Gliederung“ (#537): verankerbar wie das
// Diagnosefenster (#479) über INTAServices.CreateDockableForm, Inhalt
// TAtlasOutlineFrame, IDE-Thema, Atlas-Symbol (#751) im Fenstertitel.
// Form, Frame, Wächter und Abbau verwaltet TAtlasIdeDockWindow wie bei allen
// Atlas-Fenstern (#1248; Tools/Check-DockWindows.ps1 prüft das).
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
  Atlas.IDE.Foundation.Symbol,
  Atlas.IDE.Foundation.DockWindow;

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

var
  // Verwaltet Form, Frame und Anmeldung bei der IDE (#879).
  Host: TAtlasIdeDockWindow;

procedure Theme(AFrame: TCustomFrame);
begin
  TAtlasIdeDockWindow.ApplyIdeTheme(AFrame);
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
  if Host <> nil then
    Host.FrameCreated(AFrame);
  TAtlasIdeOutlineWindow.UpdateIcon;
  Theme(AFrame);
  if Assigned(TAtlasIdeOutlineWindow.OnFrame) then
    TAtlasIdeOutlineWindow.OnFrame(TAtlasOutlineFrame(AFrame));
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

procedure EnsureHost;
begin
  if Host = nil then
    Host := TAtlasIdeDockWindow.Create(TOutlineDock.Create, False);
end;

{ TAtlasIdeOutlineWindow }

class function TAtlasIdeOutlineWindow.Show: TAtlasOutlineFrame;
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

class function TAtlasIdeOutlineWindow.ExistingFrame: TAtlasOutlineFrame;
begin
  Result := nil;
  if (Host <> nil) and (Host.Frame is TAtlasOutlineFrame) then
    Result := TAtlasOutlineFrame(Host.Frame);
end;

class function TAtlasIdeOutlineWindow.Visible: Boolean;
begin
  // Angedockt in verstecktem Gastgeber zählt nicht als sichtbar.
  Result := (Host <> nil) and Host.Shown;
end;

class procedure TAtlasIdeOutlineWindow.Hide;
begin
  if Host <> nil then
    Host.Hide;
end;

class procedure TAtlasIdeOutlineWindow.UpdateIcon;
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

class procedure TAtlasIdeOutlineWindow.ApplyTheme;
var
  Frame: TAtlasOutlineFrame;
begin
  Frame := ExistingFrame;
  if Frame <> nil then
    Theme(Frame);
  UpdateIcon;
end;

class procedure TAtlasIdeOutlineWindow.Release;
begin
  OnFrame := nil;
  // Meldet ab und gibt die Form nur frei, wenn die IDE sie nicht schon zerstört hat.
  FreeAndNil(Host);
end;

end.
