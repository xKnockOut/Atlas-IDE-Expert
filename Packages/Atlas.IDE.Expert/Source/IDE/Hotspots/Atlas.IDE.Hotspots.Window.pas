unit Atlas.IDE.Hotspots.Window;

// Andockbares Fenster „Atlas-Hotspots“ (#1354): verankerbar wie die
// Lesezeichen (#622) über INTAServices.CreateDockableForm, Inhalt
// TAtlasHotspotsFrame, IDE-Thema, Atlas-Symbol (#751) im Fenstertitel.
// OnFrame meldet einen neuen Frame, damit TAtlasIdeHotspots ihn
// verdrahtet und füllt. Vorgabeplatz ist rechts: Beim allerersten Anlegen
// dockt das Fenster als Reiter neben der Projektverwaltung an (Entscheidung in
// TAtlasDockPlan.DockToDefault, gemerkt in HotspotsWindowPlaced); danach
// stellt die IDE die Lage aus ihrem Desktop wieder her.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Forms,
  Atlas.UI.Hotspots.Frame;

type
  TAtlasIdeHotspotsWindow = class
  public class var
    /// <summary>Ein neuer Frame ist entstanden; setzt TAtlasIdeHotspots.</summary>
    OnFrame: TProc<TAtlasHotspotsFrame>;
  public
    /// <summary>Fenster zeigen (bei Bedarf anlegen); nil, wenn die IDE keine andockbaren Fenster anbietet.</summary>
    class function Show: TAtlasHotspotsFrame; static;
    /// <summary>Frame, falls das Fenster existiert; legt nichts an.</summary>
    class function ExistingFrame: TAtlasHotspotsFrame; static;
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
  Atlas.Core.Dock.Plan,
  Atlas.Core.Settings.Plugin,
  Atlas.IDE.Foundation.Symbol,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.DockWindow;

const
  /// <summary>Name der Projektverwaltung der IDE; sie steht in der Vorgabe-Anordnung rechts.</summary>
  ProjectManagerName = 'ProjectManagerForm';

type
  THotspotsDock = class(TInterfacedObject, INTACustomDockableForm)
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

{ THotspotsDock }

function THotspotsDock.GetCaption: string;
begin
  Result := TAtlasStrings.Text(TAtlasTextId.HotspotsCaption);
end;

function THotspotsDock.GetIdentifier: string;
begin
  Result := 'AtlasHotspots';
end;

function THotspotsDock.GetFrameClass: TCustomFrameClass;
begin
  Result := TAtlasHotspotsFrame;
end;

procedure THotspotsDock.FrameCreated(AFrame: TCustomFrame);
var
  Frame: TAtlasHotspotsFrame;
begin
  if not (AFrame is TAtlasHotspotsFrame) then
    Exit;
  if Host <> nil then
    Host.FrameCreated(AFrame);
  Frame := TAtlasHotspotsFrame(AFrame);
  TAtlasIdeHotspotsWindow.UpdateIcon;
  Theme(Frame);
  if Assigned(TAtlasIdeHotspotsWindow.OnFrame) then
    TAtlasIdeHotspotsWindow.OnFrame(Frame);
end;

function THotspotsDock.GetMenuActionList: TCustomActionList;
begin
  Result := nil;
end;

function THotspotsDock.GetMenuImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure THotspotsDock.CustomizePopupMenu(PopupMenu: TPopupMenu);
begin
end;

function THotspotsDock.GetToolbarActionList: TCustomActionList;
begin
  Result := nil;
end;

function THotspotsDock.GetToolbarImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure THotspotsDock.CustomizeToolBar(ToolBar: TToolBar);
begin
end;

procedure THotspotsDock.SaveWindowState(Desktop: TCustomIniFile; const Section: string; IsProject: Boolean);
begin
end;

procedure THotspotsDock.LoadWindowState(Desktop: TCustomIniFile; const Section: string);
begin
end;

function THotspotsDock.GetEditState: TEditState;
begin
  Result := [];
end;

function THotspotsDock.EditAction(Action: TEditAction): Boolean;
begin
  Result := False;
end;

function ProjectManager: TCustomForm;
var
  Index: Integer;
begin
  Result := nil;
  for Index := 0 to Screen.CustomFormCount - 1 do
    if SameText(Screen.CustomForms[Index].Name, ProjectManagerName) then
      Exit(Screen.CustomForms[Index]);
end;

/// <summary>Beim ersten Anlegen rechts neben die Projektverwaltung andocken (#1354).</summary>
procedure DockToDefault;
var
  Form, Target: TCustomForm;
  Next: TAtlasPluginSettings;
begin
  Form := Host.Form;
  Target := ProjectManager;
  if (Form = nil) or not TAtlasDockPlan.DockToDefault(True, Form.HostDockSite = nil,
    TAtlasIdeSettings.Stored.HotspotsWindowPlaced, (Target <> nil) and (Target.HostDockSite <> nil)) then
    Exit;
  Form.ManualDock(Target.HostDockSite, nil, alClient);
  Next := TAtlasIdeSettings.Stored;
  Next.HotspotsWindowPlaced := True;
  TAtlasIdeSettings.Update(Next);
end;

procedure EnsureHost;
begin
  if Host = nil then
    Host := TAtlasIdeDockWindow.Create(THotspotsDock.Create, True);
end;

{ TAtlasIdeHotspotsWindow }

class function TAtlasIdeHotspotsWindow.Show: TAtlasHotspotsFrame;
var
  Created: Boolean;
begin
  // Lebt die Form noch (X versteckt nur), wird sie samt Gastgebern gezeigt; sonst neu angelegt.
  EnsureHost;
  Host.Show(Created);
  if Created then
  begin
    UpdateIcon;
    DockToDefault;
    // Nach dem Andocken die Reiterseite wählen und Gastgeber zeigen.
    Host.Show(Created);
  end;
  Result := ExistingFrame;
end;

class function TAtlasIdeHotspotsWindow.ExistingFrame: TAtlasHotspotsFrame;
begin
  Result := nil;
  if (Host <> nil) and (Host.Frame is TAtlasHotspotsFrame) then
    Result := TAtlasHotspotsFrame(Host.Frame);
end;

class function TAtlasIdeHotspotsWindow.Visible: Boolean;
begin
  // Angedockt in verstecktem Gastgeber zählt nicht als sichtbar.
  Result := (Host <> nil) and Host.Shown;
end;

class procedure TAtlasIdeHotspotsWindow.Hide;
begin
  if Host <> nil then
    Host.Hide;
end;

class procedure TAtlasIdeHotspotsWindow.UpdateIcon;
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

class procedure TAtlasIdeHotspotsWindow.ApplyTheme;
var
  Frame: TAtlasHotspotsFrame;
begin
  Frame := ExistingFrame;
  if Frame <> nil then
    Theme(Frame);
  UpdateIcon;
end;

class procedure TAtlasIdeHotspotsWindow.Prepare;
begin
  EnsureHost;
end;

class procedure TAtlasIdeHotspotsWindow.Release;
begin
  OnFrame := nil;
  // Meldet ab und gibt die Form nur frei, wenn die IDE sie nicht schon zerstört hat.
  FreeAndNil(Host);
end;

end.
