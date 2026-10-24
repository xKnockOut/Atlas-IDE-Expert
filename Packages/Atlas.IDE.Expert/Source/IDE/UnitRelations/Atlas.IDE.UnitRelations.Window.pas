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
  Result := TAtlasStrings.Text(TAtlasTextId.UnitRelationsCaption);
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
  Frame: TAtlasUnitRelationsFrame;
begin
  if not (AFrame is TAtlasUnitRelationsFrame) then
    Exit;
  if Host <> nil then
    Host.FrameCreated(AFrame);
  Frame := TAtlasUnitRelationsFrame(AFrame);
  TAtlasIdeUnitRelationsWindow.UpdateIcon;
  Theme(Frame);
  if Assigned(TAtlasIdeUnitRelationsWindow.OnFrame) then
    TAtlasIdeUnitRelationsWindow.OnFrame(Frame);
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
  Index: Integer;
begin
  Result := nil;
  for Index := 0 to Screen.CustomFormCount - 1 do
    if SameText(Screen.CustomForms[Index].Name, ProjectManagerName) then
      Exit(Screen.CustomForms[Index]);
end;

/// <summary>Beim ersten Anlegen rechts neben die Projektverwaltung andocken (#593).</summary>
procedure DockToDefault;
var
  Form, Target: TCustomForm;
  Next: TAtlasPluginSettings;
begin
  Form := Host.Form;
  Target := ProjectManager;
  if (Form = nil) or not TAtlasDockPlan.DockToDefault(True, Form.HostDockSite = nil,
    TAtlasIdeSettings.Stored.UnitRelationsWindowPlaced, (Target <> nil) and (Target.HostDockSite <> nil)) then
    Exit;
  Form.ManualDock(Target.HostDockSite, nil, alClient);
  Next := TAtlasIdeSettings.Stored;
  Next.UnitRelationsWindowPlaced := True;
  TAtlasIdeSettings.Update(Next);
end;

procedure EnsureHost;
begin
  if Host = nil then
    Host := TAtlasIdeDockWindow.Create(TUnitRelationsDock.Create, True);
end;

{ TAtlasIdeUnitRelationsWindow }

class function TAtlasIdeUnitRelationsWindow.Show: TAtlasUnitRelationsFrame;
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

class function TAtlasIdeUnitRelationsWindow.ExistingFrame: TAtlasUnitRelationsFrame;
begin
  Result := nil;
  if (Host <> nil) and (Host.Frame is TAtlasUnitRelationsFrame) then
    Result := TAtlasUnitRelationsFrame(Host.Frame);
end;

class function TAtlasIdeUnitRelationsWindow.Visible: Boolean;
begin
  // Angedockt in verstecktem Gastgeber zählt nicht als sichtbar.
  Result := (Host <> nil) and Host.Shown;
end;

class procedure TAtlasIdeUnitRelationsWindow.Hide;
begin
  if Host <> nil then
    Host.Hide;
end;

class procedure TAtlasIdeUnitRelationsWindow.UpdateIcon;
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

class procedure TAtlasIdeUnitRelationsWindow.ApplyTheme;
var
  Frame: TAtlasUnitRelationsFrame;
begin
  Frame := ExistingFrame;
  if Frame <> nil then
    Theme(Frame);
  UpdateIcon;
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
