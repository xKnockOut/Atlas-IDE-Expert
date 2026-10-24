unit Atlas.IDE.Debug.EvaluateWindow;

// Andockbares Fenster „Auswerten“ (#784): verankerbar wie die Lesezeichen
// (#622) über INTAServices.CreateDockableForm, Inhalt
// TAtlasDebugEvaluateFrame, IDE-Thema (hell und dunkel), Atlas-Symbol (#751)
// im Fenstertitel. OnFrame meldet einen neuen Frame, damit
// TAtlasIdeDebugEvaluate ihn verdrahtet und füllt.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Forms,
  Atlas.UI.Debug.EvaluateFrame;

type
  TAtlasIdeDebugEvaluateWindow = class
  public class var
    /// <summary>Ein neuer Frame ist entstanden; setzt TAtlasIdeDebugEvaluate.</summary>
    OnFrame: TProc<TAtlasDebugEvaluateFrame>;
  public
    /// <summary>Fenster zeigen (bei Bedarf anlegen); nil, wenn die IDE keine andockbaren Fenster anbietet.</summary>
    class function Show: TAtlasDebugEvaluateFrame; static;
    /// <summary>Frame, falls das Fenster existiert; legt nichts an.</summary>
    class function ExistingFrame: TAtlasDebugEvaluateFrame; static;
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
  TEvaluateDock = class(TInterfacedObject, INTACustomDockableForm)
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

{ TEvaluateDock }

function TEvaluateDock.GetCaption: string;
begin
  Result := TAtlasStrings.Text(TAtlasTextId.DebugEvaluateCaption);
end;

function TEvaluateDock.GetIdentifier: string;
begin
  Result := 'AtlasEvaluate';
end;

function TEvaluateDock.GetFrameClass: TCustomFrameClass;
begin
  Result := TAtlasDebugEvaluateFrame;
end;

procedure TEvaluateDock.FrameCreated(AFrame: TCustomFrame);
var
  Frame: TAtlasDebugEvaluateFrame;
begin
  if not (AFrame is TAtlasDebugEvaluateFrame) then
    Exit;
  if Host <> nil then
    Host.FrameCreated(AFrame);
  Frame := TAtlasDebugEvaluateFrame(AFrame);
  TAtlasIdeDebugEvaluateWindow.UpdateIcon;
  Theme(Frame);
  if Assigned(TAtlasIdeDebugEvaluateWindow.OnFrame) then
    TAtlasIdeDebugEvaluateWindow.OnFrame(Frame);
end;

function TEvaluateDock.GetMenuActionList: TCustomActionList;
begin
  Result := nil;
end;

function TEvaluateDock.GetMenuImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TEvaluateDock.CustomizePopupMenu(PopupMenu: TPopupMenu);
begin
end;

function TEvaluateDock.GetToolbarActionList: TCustomActionList;
begin
  Result := nil;
end;

function TEvaluateDock.GetToolbarImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TEvaluateDock.CustomizeToolBar(ToolBar: TToolBar);
begin
end;

procedure TEvaluateDock.SaveWindowState(Desktop: TCustomIniFile; const Section: string; IsProject: Boolean);
begin
end;

procedure TEvaluateDock.LoadWindowState(Desktop: TCustomIniFile; const Section: string);
begin
end;

function TEvaluateDock.GetEditState: TEditState;
begin
  Result := [];
end;

function TEvaluateDock.EditAction(Action: TEditAction): Boolean;
begin
  Result := False;
end;

procedure EnsureHost;
begin
  if Host = nil then
    Host := TAtlasIdeDockWindow.Create(TEvaluateDock.Create, True);
end;

{ TAtlasIdeDebugEvaluateWindow }

class function TAtlasIdeDebugEvaluateWindow.Show: TAtlasDebugEvaluateFrame;
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

class function TAtlasIdeDebugEvaluateWindow.ExistingFrame: TAtlasDebugEvaluateFrame;
begin
  Result := nil;
  if (Host <> nil) and (Host.Frame is TAtlasDebugEvaluateFrame) then
    Result := TAtlasDebugEvaluateFrame(Host.Frame);
end;

class function TAtlasIdeDebugEvaluateWindow.Visible: Boolean;
begin
  // Angedockt in verstecktem Gastgeber zählt nicht als sichtbar.
  Result := (Host <> nil) and Host.Shown;
end;

class procedure TAtlasIdeDebugEvaluateWindow.Hide;
begin
  if Host <> nil then
    Host.Hide;
end;

class procedure TAtlasIdeDebugEvaluateWindow.UpdateIcon;
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

class procedure TAtlasIdeDebugEvaluateWindow.ApplyTheme;
var
  Frame: TAtlasDebugEvaluateFrame;
begin
  Frame := ExistingFrame;
  if Frame <> nil then
    Theme(Frame);
  UpdateIcon;
end;

class procedure TAtlasIdeDebugEvaluateWindow.Prepare;
begin
  EnsureHost;
end;

class procedure TAtlasIdeDebugEvaluateWindow.Release;
begin
  OnFrame := nil;
  // Meldet ab und gibt die Form nur frei, wenn die IDE sie nicht schon zerstört hat.
  FreeAndNil(Host);
end;

end.
