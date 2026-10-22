unit Atlas.IDE.Problems.Window;

// Andockbares Fenster „Atlas-Prüfung“ (#909): verankerbar wie das
// Lesezeichen-Fenster (#622) über INTAServices.CreateDockableForm, Inhalt
// TAtlasProblemsFrame, IDE-Thema, Atlas-Symbol (#751) im Fenstertitel.
// Die IDE speichert Lage und Andockung im Desktop; beim Speichern des
// Desktops meldet OnSave, damit die Spalten in problems.window.columns
// landen. OnFrame meldet einen neuen Frame, damit TAtlasIdeProblems ihn
// verdrahtet und füllt.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Forms,
  Atlas.UI.Problems.Frame;

type
  TAtlasIdeProblemsWindow = class
  public class var
    /// <summary>Ein neuer Frame ist entstanden; setzt TAtlasIdeProblems.</summary>
    OnFrame: TProc<TAtlasProblemsFrame>;
    /// <summary>Die IDE speichert den Desktop: Spalten des Frames sichern.</summary>
    OnSave: TProc;
  public
    /// <summary>Fenster zeigen (bei Bedarf anlegen); nil, wenn die IDE keine andockbaren Fenster anbietet.</summary>
    class function Show: TAtlasProblemsFrame; static;
    /// <summary>Frame, falls das Fenster existiert; legt nichts an.</summary>
    class function ExistingFrame: TAtlasProblemsFrame; static;
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
  TProblemsDock = class(TInterfacedObject, INTACustomDockableForm)
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
var
  Theming: IOTAIDEThemingServices;
begin
  if (AFrame <> nil) and Supports(BorlandIDEServices, IOTAIDEThemingServices, Theming) and
    Theming.IDEThemingEnabled then
    Theming.ApplyTheme(AFrame);
end;

{ TProblemsDock }

function TProblemsDock.GetCaption: string;
begin
  Result := TAtlasStrings.Text(TAtlasTextId.ProblemsWindowCaption);
end;

function TProblemsDock.GetIdentifier: string;
begin
  Result := 'AtlasProblems';
end;

function TProblemsDock.GetFrameClass: TCustomFrameClass;
begin
  Result := TAtlasProblemsFrame;
end;

procedure TProblemsDock.FrameCreated(AFrame: TCustomFrame);
var
  Frame: TAtlasProblemsFrame;
begin
  if not (AFrame is TAtlasProblemsFrame) then
    Exit;
  if Host <> nil then
    Host.FrameCreated(AFrame);
  Frame := TAtlasProblemsFrame(AFrame);
  TAtlasIdeProblemsWindow.UpdateIcon;
  Theme(Frame);
  if Assigned(TAtlasIdeProblemsWindow.OnFrame) then
    TAtlasIdeProblemsWindow.OnFrame(Frame);
end;

function TProblemsDock.GetMenuActionList: TCustomActionList;
begin
  Result := nil;
end;

function TProblemsDock.GetMenuImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TProblemsDock.CustomizePopupMenu(PopupMenu: TPopupMenu);
begin
end;

function TProblemsDock.GetToolbarActionList: TCustomActionList;
begin
  Result := nil;
end;

function TProblemsDock.GetToolbarImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TProblemsDock.CustomizeToolBar(ToolBar: TToolBar);
begin
end;

procedure TProblemsDock.SaveWindowState(Desktop: TCustomIniFile; const Section: string; IsProject: Boolean);
begin
  if Assigned(TAtlasIdeProblemsWindow.OnSave) then
    TAtlasIdeProblemsWindow.OnSave();
end;

procedure TProblemsDock.LoadWindowState(Desktop: TCustomIniFile; const Section: string);
begin
end;

function TProblemsDock.GetEditState: TEditState;
begin
  Result := [];
end;

function TProblemsDock.EditAction(Action: TEditAction): Boolean;
begin
  Result := False;
end;

procedure EnsureHost;
begin
  if Host = nil then
    Host := TAtlasIdeDockWindow.Create(TProblemsDock.Create, True);
end;

{ TAtlasIdeProblemsWindow }

class function TAtlasIdeProblemsWindow.Show: TAtlasProblemsFrame;
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

class function TAtlasIdeProblemsWindow.ExistingFrame: TAtlasProblemsFrame;
begin
  Result := nil;
  if (Host <> nil) and (Host.Frame is TAtlasProblemsFrame) then
    Result := TAtlasProblemsFrame(Host.Frame);
end;

class function TAtlasIdeProblemsWindow.Visible: Boolean;
begin
  // Angedockt in verstecktem Gastgeber zählt nicht als sichtbar.
  Result := (Host <> nil) and Host.Shown;
end;

class procedure TAtlasIdeProblemsWindow.Hide;
begin
  if Host <> nil then
    Host.Hide;
end;

class procedure TAtlasIdeProblemsWindow.UpdateIcon;
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

class procedure TAtlasIdeProblemsWindow.ApplyTheme;
var
  Frame: TAtlasProblemsFrame;
begin
  Frame := ExistingFrame;
  if Frame <> nil then
    Theme(Frame);
  UpdateIcon;
end;

class procedure TAtlasIdeProblemsWindow.Prepare;
begin
  EnsureHost;
end;

class procedure TAtlasIdeProblemsWindow.Release;
begin
  OnFrame := nil;
  OnSave := nil;
  // Meldet ab und gibt die Form nur frei, wenn die IDE sie nicht schon zerstört hat.
  FreeAndNil(Host);
end;

end.
