unit Atlas.IDE.Debug.StepFilterWindow;

// Andockbares Fenster „Schrittfilter“ (#850): verankerbar wie die Lesezeichen
// (#622) über INTACustomDockableForm, Inhalt TAtlasDebugStepFilterFrame,
// IDE-Thema (hell und dunkel), Atlas-Symbol (#751) im Fenstertitel. OnFrame
// meldet einen neuen Frame, damit TAtlasIdeDebugStepFilter ihn verdrahtet und
// füllt.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Forms,
  Atlas.UI.Debug.StepFilterFrame;

type
  TAtlasIdeDebugStepFilterWindow = class
  public class var
    /// <summary>Ein neuer Frame ist entstanden; setzt TAtlasIdeDebugStepFilter.</summary>
    OnFrame: TProc<TAtlasDebugStepFilterFrame>;
  public
    /// <summary>Fenster zeigen (bei Bedarf anlegen); nil, wenn die IDE keine andockbaren Fenster anbietet.</summary>
    class function Show: TAtlasDebugStepFilterFrame; static;
    /// <summary>Frame, falls das Fenster existiert; legt nichts an.</summary>
    class function ExistingFrame: TAtlasDebugStepFilterFrame; static;
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
  TStepFilterDock = class(TInterfacedObject, INTACustomDockableForm)
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

{ TStepFilterDock }

function TStepFilterDock.GetCaption: string;
begin
  Result := TAtlasStrings.Text(TAtlasTextId.StepFilterCaption);
end;

function TStepFilterDock.GetIdentifier: string;
begin
  Result := 'AtlasStepFilter';
end;

function TStepFilterDock.GetFrameClass: TCustomFrameClass;
begin
  Result := TAtlasDebugStepFilterFrame;
end;

procedure TStepFilterDock.FrameCreated(AFrame: TCustomFrame);
var
  Frame: TAtlasDebugStepFilterFrame;
begin
  if not (AFrame is TAtlasDebugStepFilterFrame) then
    Exit;
  if Host <> nil then
    Host.FrameCreated(AFrame);
  Frame := TAtlasDebugStepFilterFrame(AFrame);
  TAtlasIdeDebugStepFilterWindow.UpdateIcon;
  Theme(Frame);
  if Assigned(TAtlasIdeDebugStepFilterWindow.OnFrame) then
    TAtlasIdeDebugStepFilterWindow.OnFrame(Frame);
end;

function TStepFilterDock.GetMenuActionList: TCustomActionList;
begin
  Result := nil;
end;

function TStepFilterDock.GetMenuImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TStepFilterDock.CustomizePopupMenu(PopupMenu: TPopupMenu);
begin
end;

function TStepFilterDock.GetToolbarActionList: TCustomActionList;
begin
  Result := nil;
end;

function TStepFilterDock.GetToolbarImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TStepFilterDock.CustomizeToolBar(ToolBar: TToolBar);
begin
end;

procedure TStepFilterDock.SaveWindowState(Desktop: TCustomIniFile; const Section: string; IsProject: Boolean);
begin
end;

procedure TStepFilterDock.LoadWindowState(Desktop: TCustomIniFile; const Section: string);
begin
end;

function TStepFilterDock.GetEditState: TEditState;
begin
  Result := [];
end;

function TStepFilterDock.EditAction(Action: TEditAction): Boolean;
begin
  Result := False;
end;

procedure EnsureHost;
begin
  if Host = nil then
    Host := TAtlasIdeDockWindow.Create(TStepFilterDock.Create, True);
end;

{ TAtlasIdeDebugStepFilterWindow }

class function TAtlasIdeDebugStepFilterWindow.Show: TAtlasDebugStepFilterFrame;
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

class function TAtlasIdeDebugStepFilterWindow.ExistingFrame: TAtlasDebugStepFilterFrame;
begin
  Result := nil;
  if (Host <> nil) and (Host.Frame is TAtlasDebugStepFilterFrame) then
    Result := TAtlasDebugStepFilterFrame(Host.Frame);
end;

class function TAtlasIdeDebugStepFilterWindow.Visible: Boolean;
begin
  // Angedockt in verstecktem Gastgeber zählt nicht als sichtbar.
  Result := (Host <> nil) and Host.Shown;
end;

class procedure TAtlasIdeDebugStepFilterWindow.Hide;
begin
  if Host <> nil then
    Host.Hide;
end;

class procedure TAtlasIdeDebugStepFilterWindow.UpdateIcon;
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

class procedure TAtlasIdeDebugStepFilterWindow.ApplyTheme;
var
  Frame: TAtlasDebugStepFilterFrame;
begin
  Frame := ExistingFrame;
  if Frame <> nil then
    Theme(Frame);
  UpdateIcon;
end;

class procedure TAtlasIdeDebugStepFilterWindow.Prepare;
begin
  EnsureHost;
end;

class procedure TAtlasIdeDebugStepFilterWindow.Release;
begin
  OnFrame := nil;
  // Meldet ab und gibt die Form nur frei, wenn die IDE sie nicht schon zerstört hat.
  FreeAndNil(Host);
end;

end.
