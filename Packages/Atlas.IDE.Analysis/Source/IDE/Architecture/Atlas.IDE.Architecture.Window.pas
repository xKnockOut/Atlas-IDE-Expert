unit Atlas.IDE.Architecture.Window;

// Andockbares Fenster „Atlas-Architektur“ (#1118): verankerbar wie die
// Lesezeichen (#622) über INTAServices.CreateDockableForm, Inhalt
// TAtlasArchitectureFrame, IDE-Thema, Atlas-Symbol (#751) im Fenstertitel.
// OnFrame meldet einen neuen Frame, damit TAtlasIdeArchitecture ihn
// verdrahtet und füllt. Vorgabeplatz ist rechts: Beim allerersten Anlegen
// dockt das Fenster als Reiter neben der Projektverwaltung an (Entscheidung in
// TAtlasDockPlan.DockToDefault, gemerkt in ArchitectureWindowPlaced); danach
// stellt die IDE die Lage aus ihrem Desktop wieder her.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Forms,
  Atlas.UI.Architecture.Frame;

type
  TAtlasIdeArchitectureWindow = class
  public class var
    /// <summary>Ein neuer Frame ist entstanden; setzt TAtlasIdeArchitecture.</summary>
    OnFrame: TProc<TAtlasArchitectureFrame>;
  public
    /// <summary>Fenster zeigen (bei Bedarf anlegen); nil, wenn die IDE keine andockbaren Fenster anbietet.</summary>
    class function Show: TAtlasArchitectureFrame; static;
    /// <summary>Frame, falls das Fenster existiert; legt nichts an.</summary>
    class function ExistingFrame: TAtlasArchitectureFrame; static;
    class function Visible: Boolean; static;
    class procedure Hide; static;
    class procedure ApplyTheme; static;
    /// <summary>Früh (Register): bei der IDE anmelden, damit der Desktop das Fenster speichert und wiederherstellt
    /// (#879).</summary>
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
  Atlas.UI.Analysis.Strings,
  Atlas.UI.Style.Symbol,
  Atlas.Core.Dock.Plan,
  Atlas.Core.Settings.Plugin,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.DockWindow;

const
  /// <summary>Name der Projektverwaltung der IDE; sie steht in der Vorgabe-Anordnung rechts.</summary>
  cProjectManagerName = 'ProjectManagerForm';

type
  TArchitectureDock = class(TInterfacedObject, INTACustomDockableForm)
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

{ TArchitectureDock }

function TArchitectureDock.GetCaption: string;
begin
  Result := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureCaption);
end;

function TArchitectureDock.GetIdentifier: string;
begin
  Result := 'AtlasArchitecture';
end;

function TArchitectureDock.GetFrameClass: TCustomFrameClass;
begin
  Result := TAtlasArchitectureFrame;
end;

procedure TArchitectureDock.FrameCreated(AFrame: TCustomFrame);
var
  mFrame: TAtlasArchitectureFrame;
begin
  if not (AFrame is TAtlasArchitectureFrame) then
  begin
    Exit;
  end;
  if Host <> nil then
  begin
    Host.FrameCreated(AFrame);
  end;
  mFrame := TAtlasArchitectureFrame(AFrame);
  TAtlasIdeDockWindow.UpdateIcon(Host);
  Theme(mFrame);
  if Assigned(TAtlasIdeArchitectureWindow.OnFrame) then
  begin
    TAtlasIdeArchitectureWindow.OnFrame(mFrame);
  end;
end;

function TArchitectureDock.GetMenuActionList: TCustomActionList;
begin
  Result := nil;
end;

function TArchitectureDock.GetMenuImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TArchitectureDock.CustomizePopupMenu(PopupMenu: TPopupMenu);
begin
end;

function TArchitectureDock.GetToolbarActionList: TCustomActionList;
begin
  Result := nil;
end;

function TArchitectureDock.GetToolbarImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TArchitectureDock.CustomizeToolBar(ToolBar: TToolBar);
begin
end;

procedure TArchitectureDock.SaveWindowState(Desktop: TCustomIniFile; const Section: string; IsProject: Boolean);
begin
end;

procedure TArchitectureDock.LoadWindowState(Desktop: TCustomIniFile; const Section: string);
begin
end;

function TArchitectureDock.GetEditState: TEditState;
begin
  Result := [];
end;

function TArchitectureDock.EditAction(Action: TEditAction): Boolean;
begin
  Result := False;
end;

function ProjectManager: TCustomForm;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to Screen.CustomFormCount - 1 do
  begin
    if SameText(Screen.CustomForms[mIndex].Name, cProjectManagerName) then
    begin
      Exit(Screen.CustomForms[mIndex]);
    end;
  end;
end;

/// <summary>Beim ersten Anlegen rechts neben die Projektverwaltung andocken (#1118).</summary>
procedure DockToDefault;
var
  mForm, mTarget: TCustomForm;
  mNext: TAtlasPluginSettings;
begin
  mForm := Host.Form;
  mTarget := ProjectManager;
  if (mForm = nil) or not TAtlasDockPlan.DockToDefault(True, mForm.HostDockSite = nil,
    TAtlasIdeSettings.Stored.ArchitectureWindowPlaced, (mTarget <> nil) and (mTarget.HostDockSite <> nil)) then
  begin
    Exit;
  end;
  mForm.ManualDock(mTarget.HostDockSite, nil, alClient);
  mNext := TAtlasIdeSettings.Stored;
  mNext.ArchitectureWindowPlaced := True;
  TAtlasIdeSettings.Update(mNext);
end;

procedure EnsureHost;
begin
  if Host = nil then
  begin
    Host := TAtlasIdeDockWindow.Create(TArchitectureDock.Create, True);
  end;
end;

{ TAtlasIdeArchitectureWindow }

class function TAtlasIdeArchitectureWindow.Show: TAtlasArchitectureFrame;
var
  mCreated: Boolean;
begin
  // Lebt die Form noch (X versteckt nur), wird sie samt Gastgebern gezeigt; sonst neu angelegt.
  EnsureHost;
  Host.Show(mCreated);
  if mCreated then
  begin
    DockToDefault;
    // Nach dem Andocken die Reiterseite wählen und Gastgeber zeigen.
    Host.Show(mCreated);
  end;
  Result := ExistingFrame;
end;

class function TAtlasIdeArchitectureWindow.ExistingFrame: TAtlasArchitectureFrame;
begin
  Result := nil;
  if (Host <> nil) and (Host.Frame is TAtlasArchitectureFrame) then
  begin
    Result := TAtlasArchitectureFrame(Host.Frame);
  end;
end;

class function TAtlasIdeArchitectureWindow.Visible: Boolean;
begin
  Result := TAtlasIdeDockWindow.IsShown(Host);
end;

class procedure TAtlasIdeArchitectureWindow.Hide;
begin
  TAtlasIdeDockWindow.HideIfAny(Host);
end;

class procedure TAtlasIdeArchitectureWindow.ApplyTheme;
var
  mFrame: TAtlasArchitectureFrame;
begin
  mFrame := ExistingFrame;
  if mFrame <> nil then
  begin
    Theme(mFrame);
  end;
  TAtlasIdeDockWindow.UpdateIcon(Host);
end;

class procedure TAtlasIdeArchitectureWindow.Prepare;
begin
  EnsureHost;
end;

class procedure TAtlasIdeArchitectureWindow.Release;
begin
  OnFrame := nil;
  // Meldet ab und gibt die Form nur frei, wenn die IDE sie nicht schon zerstört hat.
  FreeAndNil(Host);
end;

end.
