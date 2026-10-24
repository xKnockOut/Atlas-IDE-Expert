unit Atlas.IDE.Build.SwitchesWindow;

// Andockbares Seitenfenster „Compiler-Schalter“ (#558): verankerbar wie die
// Lesezeichen (#622) über INTAServices.CreateDockableForm, Inhalt
// TAtlasBuildSwitchesFrame, IDE-Thema, Atlas-Symbol (#751) im Fenstertitel.
// OnFrame meldet einen neuen Frame, damit TAtlasIdeCompilerSwitches ihn
// verdrahtet und füllt.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Forms,
  Atlas.UI.Build.SwitchesFrame;

type
  TAtlasIdeBuildSwitchesWindow = class
  public class var
    /// <summary>Ein neuer Frame ist entstanden; setzt TAtlasIdeCompilerSwitches.</summary>
    OnFrame: TProc<TAtlasBuildSwitchesFrame>;
  public
    /// <summary>Fenster zeigen (bei Bedarf anlegen); nil, wenn die IDE keine andockbaren Fenster anbietet.</summary>
    class function Show: TAtlasBuildSwitchesFrame; static;
    /// <summary>Frame, falls das Fenster existiert; legt nichts an.</summary>
    class function ExistingFrame: TAtlasBuildSwitchesFrame; static;
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
  TSwitchesDock = class(TInterfacedObject, INTACustomDockableForm)
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

{ TSwitchesDock }

function TSwitchesDock.GetCaption: string;
begin
  Result := TAtlasStrings.Text(TAtlasTextId.CompilerSwitchesCaption);
end;

function TSwitchesDock.GetIdentifier: string;
begin
  Result := 'AtlasCompilerSwitches';
end;

function TSwitchesDock.GetFrameClass: TCustomFrameClass;
begin
  Result := TAtlasBuildSwitchesFrame;
end;

procedure TSwitchesDock.FrameCreated(AFrame: TCustomFrame);
var
  Frame: TAtlasBuildSwitchesFrame;
begin
  if not (AFrame is TAtlasBuildSwitchesFrame) then
    Exit;
  if Host <> nil then
    Host.FrameCreated(AFrame);
  Frame := TAtlasBuildSwitchesFrame(AFrame);
  TAtlasIdeBuildSwitchesWindow.UpdateIcon;
  Theme(Frame);
  if Assigned(TAtlasIdeBuildSwitchesWindow.OnFrame) then
    TAtlasIdeBuildSwitchesWindow.OnFrame(Frame);
end;

function TSwitchesDock.GetMenuActionList: TCustomActionList;
begin
  Result := nil;
end;

function TSwitchesDock.GetMenuImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TSwitchesDock.CustomizePopupMenu(PopupMenu: TPopupMenu);
begin
end;

function TSwitchesDock.GetToolbarActionList: TCustomActionList;
begin
  Result := nil;
end;

function TSwitchesDock.GetToolbarImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TSwitchesDock.CustomizeToolBar(ToolBar: TToolBar);
begin
end;

procedure TSwitchesDock.SaveWindowState(Desktop: TCustomIniFile; const Section: string; IsProject: Boolean);
begin
end;

procedure TSwitchesDock.LoadWindowState(Desktop: TCustomIniFile; const Section: string);
begin
end;

function TSwitchesDock.GetEditState: TEditState;
begin
  Result := [];
end;

function TSwitchesDock.EditAction(Action: TEditAction): Boolean;
begin
  Result := False;
end;

procedure EnsureHost;
begin
  if Host = nil then
    Host := TAtlasIdeDockWindow.Create(TSwitchesDock.Create, True);
end;

{ TAtlasIdeBuildSwitchesWindow }

class function TAtlasIdeBuildSwitchesWindow.Show: TAtlasBuildSwitchesFrame;
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

class function TAtlasIdeBuildSwitchesWindow.ExistingFrame: TAtlasBuildSwitchesFrame;
begin
  Result := nil;
  if (Host <> nil) and (Host.Frame is TAtlasBuildSwitchesFrame) then
    Result := TAtlasBuildSwitchesFrame(Host.Frame);
end;

class function TAtlasIdeBuildSwitchesWindow.Visible: Boolean;
begin
  // Angedockt in verstecktem Gastgeber zählt nicht als sichtbar.
  Result := (Host <> nil) and Host.Shown;
end;

class procedure TAtlasIdeBuildSwitchesWindow.Hide;
begin
  if Host <> nil then
    Host.Hide;
end;

class procedure TAtlasIdeBuildSwitchesWindow.UpdateIcon;
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

class procedure TAtlasIdeBuildSwitchesWindow.ApplyTheme;
var
  Frame: TAtlasBuildSwitchesFrame;
begin
  Frame := ExistingFrame;
  if Frame <> nil then
    Theme(Frame);
  UpdateIcon;
end;

class procedure TAtlasIdeBuildSwitchesWindow.Prepare;
begin
  EnsureHost;
end;

class procedure TAtlasIdeBuildSwitchesWindow.Release;
begin
  OnFrame := nil;
  // Meldet ab und gibt die Form nur frei, wenn die IDE sie nicht schon zerstört hat.
  FreeAndNil(Host);
end;

end.
