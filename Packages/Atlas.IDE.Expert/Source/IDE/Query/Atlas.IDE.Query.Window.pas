unit Atlas.IDE.Query.Window;

// Andockbares Fenster „Atlas-Abfrage“ (#1351): verankerbar wie die
// Lesezeichen (#622) über INTAServices.CreateDockableForm, Inhalt
// TAtlasCodeQueryFrame, IDE-Thema, Atlas-Symbol (#751) im Fenstertitel.
// OnFrame meldet einen neuen Frame, damit TAtlasIdeCodeQuery ihn verdrahtet.
// Beim ersten Öffnen schwebt das Fenster; danach stellt die IDE die Lage aus
// ihrem Desktop wieder her.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Forms,
  Atlas.UI.Query.Frame;

type
  TAtlasIdeCodeQueryWindow = class
  public class var
    /// <summary>Ein neuer Frame ist entstanden; setzt TAtlasIdeCodeQuery.</summary>
    OnFrame: TProc<TAtlasCodeQueryFrame>;
  public
    /// <summary>Fenster zeigen (bei Bedarf anlegen); nil, wenn die IDE keine andockbaren Fenster anbietet.</summary>
    class function Show: TAtlasCodeQueryFrame; static;
    /// <summary>Frame, falls das Fenster existiert; legt nichts an.</summary>
    class function ExistingFrame: TAtlasCodeQueryFrame; static;
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
  Vcl.Controls,
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
  TCodeQueryDock = class(TInterfacedObject, INTACustomDockableForm)
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

{ TCodeQueryDock }

function TCodeQueryDock.GetCaption: string;
begin
  Result := TAtlasStrings.Text(TAtlasTextId.QueryCaption);
end;

function TCodeQueryDock.GetIdentifier: string;
begin
  Result := 'AtlasQuery';
end;

function TCodeQueryDock.GetFrameClass: TCustomFrameClass;
begin
  Result := TAtlasCodeQueryFrame;
end;

procedure TCodeQueryDock.FrameCreated(AFrame: TCustomFrame);
var
  Frame: TAtlasCodeQueryFrame;
begin
  if not (AFrame is TAtlasCodeQueryFrame) then
    Exit;
  if Host <> nil then
    Host.FrameCreated(AFrame);
  Frame := TAtlasCodeQueryFrame(AFrame);
  TAtlasIdeCodeQueryWindow.UpdateIcon;
  Theme(Frame);
  if Assigned(TAtlasIdeCodeQueryWindow.OnFrame) then
    TAtlasIdeCodeQueryWindow.OnFrame(Frame);
end;

function TCodeQueryDock.GetMenuActionList: TCustomActionList;
begin
  Result := nil;
end;

function TCodeQueryDock.GetMenuImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TCodeQueryDock.CustomizePopupMenu(PopupMenu: TPopupMenu);
begin
end;

function TCodeQueryDock.GetToolbarActionList: TCustomActionList;
begin
  Result := nil;
end;

function TCodeQueryDock.GetToolbarImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TCodeQueryDock.CustomizeToolBar(ToolBar: TToolBar);
begin
end;

procedure TCodeQueryDock.SaveWindowState(Desktop: TCustomIniFile; const Section: string; IsProject: Boolean);
begin
end;

procedure TCodeQueryDock.LoadWindowState(Desktop: TCustomIniFile; const Section: string);
begin
end;

function TCodeQueryDock.GetEditState: TEditState;
begin
  Result := [];
end;

function TCodeQueryDock.EditAction(Action: TEditAction): Boolean;
begin
  Result := False;
end;

procedure EnsureHost;
begin
  if Host = nil then
    Host := TAtlasIdeDockWindow.Create(TCodeQueryDock.Create, True);
end;

{ TAtlasIdeCodeQueryWindow }

class function TAtlasIdeCodeQueryWindow.Show: TAtlasCodeQueryFrame;
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

class function TAtlasIdeCodeQueryWindow.ExistingFrame: TAtlasCodeQueryFrame;
begin
  Result := nil;
  if (Host <> nil) and (Host.Frame is TAtlasCodeQueryFrame) then
    Result := TAtlasCodeQueryFrame(Host.Frame);
end;

class function TAtlasIdeCodeQueryWindow.Visible: Boolean;
begin
  // Angedockt in verstecktem Gastgeber zählt nicht als sichtbar.
  Result := (Host <> nil) and Host.Shown;
end;

class procedure TAtlasIdeCodeQueryWindow.Hide;
begin
  if Host <> nil then
    Host.Hide;
end;

class procedure TAtlasIdeCodeQueryWindow.UpdateIcon;
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

class procedure TAtlasIdeCodeQueryWindow.ApplyTheme;
var
  Frame: TAtlasCodeQueryFrame;
begin
  Frame := ExistingFrame;
  if Frame <> nil then
    Theme(Frame);
  UpdateIcon;
end;

class procedure TAtlasIdeCodeQueryWindow.Prepare;
begin
  EnsureHost;
end;

class procedure TAtlasIdeCodeQueryWindow.Release;
begin
  OnFrame := nil;
  // Meldet ab und gibt die Form nur frei, wenn die IDE sie nicht schon zerstört hat.
  FreeAndNil(Host);
end;

end.
