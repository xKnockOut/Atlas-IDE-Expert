unit Atlas.IDE.UnitRelations.Window;

// Andockbares Fenster „Unit-Beziehungen“ (#593): verankerbar wie das Fenster
// „Atlas-Architektur“ (#1118) über INTAServices.CreateDockableForm, Inhalt
// TAtlasUnitRelationsFrame, IDE-Thema, Atlas-Symbol (#751) im Fenstertitel.
// OnFrame meldet einen neuen Frame, damit TAtlasIdeUnitRelations ihn
// verdrahtet und füllt. Vorgabeplatz ist rechts: Beim allerersten Anlegen
// dockt das Fenster als Reiter neben der Projektverwaltung an (Entscheidung in
// TAtlasDockPlan.DockToDefault, gemerkt in UnitRelationsWindowPlaced); danach
// stellt die IDE die Lage aus ihrem Desktop wieder her.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Forms,
  Atlas.UI.UnitRelations.Frame;

type
  TAtlasIdeUnitRelationsWindow = class
  public class var
    /// <summary>Ein neuer Frame ist entstanden; setzt TAtlasIdeUnitRelations.</summary>
    OnFrame: TProc<TAtlasUnitRelationsFrame>;
  public
    /// <summary>Fenster zeigen (bei Bedarf anlegen); nil, wenn die IDE keine andockbaren Fenster anbietet.</summary>
    class function Show: TAtlasUnitRelationsFrame; static;
    /// <summary>Frame, falls das Fenster existiert; legt nichts an.</summary>
    class function ExistingFrame: TAtlasUnitRelationsFrame; static;
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
  TUnitRelationsDock = class(TInterfacedObject, INTACustomDockableForm)
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

{ TUnitRelationsDock }

function TUnitRelationsDock.GetCaption: string;
begin
  Result := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.UnitRelationsCaption);
end;

function TUnitRelationsDock.GetIdentifier: string;
begin
  Result := 'AtlasUnitRelations';
end;

function TUnitRelationsDock.GetFrameClass: TCustomFrameClass;
begin
  Result := TAtlasUnitRelationsFrame;
end;

procedure TUnitRelationsDock.FrameCreated(AFrame: TCustomFrame);
var
  mFrame: TAtlasUnitRelationsFrame;
begin
  if not (AFrame is TAtlasUnitRelationsFrame) then
  begin
    Exit;
  end;
  if Host <> nil then
  begin
    Host.FrameCreated(AFrame);
  end;
  mFrame := TAtlasUnitRelationsFrame(AFrame);
  TAtlasIdeDockWindow.UpdateIcon(Host);
  Theme(mFrame);
  if Assigned(TAtlasIdeUnitRelationsWindow.OnFrame) then
  begin
    TAtlasIdeUnitRelationsWindow.OnFrame(mFrame);
  end;
end;

function TUnitRelationsDock.GetMenuActionList: TCustomActionList;
begin
  Result := nil;
end;

function TUnitRelationsDock.GetMenuImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TUnitRelationsDock.CustomizePopupMenu(PopupMenu: TPopupMenu);
begin
end;

function TUnitRelationsDock.GetToolbarActionList: TCustomActionList;
begin
  Result := nil;
end;

function TUnitRelationsDock.GetToolbarImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TUnitRelationsDock.CustomizeToolBar(ToolBar: TToolBar);
begin
end;

procedure TUnitRelationsDock.SaveWindowState(Desktop: TCustomIniFile; const Section: string; IsProject: Boolean);
begin
end;

procedure TUnitRelationsDock.LoadWindowState(Desktop: TCustomIniFile; const Section: string);
begin
end;

function TUnitRelationsDock.GetEditState: TEditState;
begin
  Result := [];
end;

function TUnitRelationsDock.EditAction(Action: TEditAction): Boolean;
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

/// <summary>Beim ersten Anlegen rechts neben die Projektverwaltung andocken (#593).</summary>
procedure DockToDefault;
var
  mForm, mTarget: TCustomForm;
  mNext: TAtlasPluginSettings;
begin
  mForm := Host.Form;
  mTarget := ProjectManager;
  if (mForm = nil) or not TAtlasDockPlan.DockToDefault(True, mForm.HostDockSite = nil,
    TAtlasIdeSettings.Stored.UnitRelationsWindowPlaced, (mTarget <> nil) and (mTarget.HostDockSite <> nil)) then
  begin
    Exit;
  end;
  mForm.ManualDock(mTarget.HostDockSite, nil, alClient);
  mNext := TAtlasIdeSettings.Stored;
  mNext.UnitRelationsWindowPlaced := True;
  TAtlasIdeSettings.Update(mNext);
end;

procedure EnsureHost;
begin
  if Host = nil then
  begin
    Host := TAtlasIdeDockWindow.Create(TUnitRelationsDock.Create, True);
  end;
end;

{ TAtlasIdeUnitRelationsWindow }

class function TAtlasIdeUnitRelationsWindow.Show: TAtlasUnitRelationsFrame;
var
  mCreated: Boolean;
begin
  // Lebt die Form noch (X versteckt nur), wird sie samt Gastgebern gezeigt; sonst neu angelegt.
  EnsureHost;
  Host.Show(mCreated);
  if mCreated then
  begin
    TAtlasIdeDockWindow.UpdateIcon(Host);
    DockToDefault;
    // Nach dem Andocken die Reiterseite wählen und Gastgeber zeigen.
    Host.Show(mCreated);
  end;
  Result := ExistingFrame;
end;

class function TAtlasIdeUnitRelationsWindow.ExistingFrame: TAtlasUnitRelationsFrame;
begin
  Result := nil;
  if (Host <> nil) and (Host.Frame is TAtlasUnitRelationsFrame) then
  begin
    Result := TAtlasUnitRelationsFrame(Host.Frame);
  end;
end;

class function TAtlasIdeUnitRelationsWindow.Visible: Boolean;
begin
  // Angedockt in verstecktem Gastgeber zählt nicht als sichtbar.
  Result := (Host <> nil) and Host.Shown;
end;

class procedure TAtlasIdeUnitRelationsWindow.Hide;
begin
  if Host <> nil then
  begin
    Host.Hide;
  end;
end;

class procedure TAtlasIdeUnitRelationsWindow.ApplyTheme;
var
  mFrame: TAtlasUnitRelationsFrame;
begin
  mFrame := ExistingFrame;
  if mFrame <> nil then
  begin
    Theme(mFrame);
  end;
  TAtlasIdeDockWindow.UpdateIcon(Host);
end;

class procedure TAtlasIdeUnitRelationsWindow.Prepare;
begin
  EnsureHost;
end;

class procedure TAtlasIdeUnitRelationsWindow.Release;
begin
  OnFrame := nil;
  // Meldet ab und gibt die Form nur frei, wenn die IDE sie nicht schon zerstört hat.
  FreeAndNil(Host);
end;

end.
