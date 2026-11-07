unit Atlas.IDE.Diagnostics.TimingWindow;

// Andockbares Fenster „Atlas-Diagnose“ (#479): klein, verankerbar wie das
// Ergebnisfenster (#400) über INTAServices.CreateDockableForm, Inhalt
// TAtlasDiagnosticsFrame (Reiter Hauptthread, Server, Hintergrund, Hänger und
// Vervollständigung), IDE-Thema, Atlas-Symbol (#751) im Fenstertitel. OnFrame
// meldet einen neuen Frame, damit TAtlasIdeDiagnosticMode ihn füllt.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Forms,
  Atlas.UI.Diagnostics.PluginFrame;

type
  TAtlasIdeTimingWindow = class
  public class var
    /// <summary>Ein neuer Frame ist entstanden; setzt der Diagnosemodus.</summary>
    OnFrame: TProc<TAtlasDiagnosticsFrame>;
  public
    /// <summary>Fenster zeigen (bei Bedarf anlegen); nil, wenn die IDE keine andockbaren Fenster anbietet.</summary>
    class function Show: TAtlasDiagnosticsFrame; static;
    /// <summary>Frame, falls das Fenster existiert; legt nichts an.</summary>
    class function ExistingFrame: TAtlasDiagnosticsFrame; static;
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
  TTimingDock = class(TInterfacedObject, INTACustomDockableForm)
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

{ TTimingDock }

function TTimingDock.GetCaption: string;
begin
  Result := TAtlasStrings.Text(TAtlasTextId.DiagnosticCaption);
end;

function TTimingDock.GetIdentifier: string;
begin
  Result := 'AtlasDiagnostics';
end;

function TTimingDock.GetFrameClass: TCustomFrameClass;
begin
  Result := TAtlasDiagnosticsFrame;
end;

procedure TTimingDock.FrameCreated(AFrame: TCustomFrame);
var
  mFrame: TAtlasDiagnosticsFrame;
begin
  if not (AFrame is TAtlasDiagnosticsFrame) then
  begin
    Exit;
  end;
  if Host <> nil then
  begin
    Host.FrameCreated(AFrame);
  end;
  mFrame := TAtlasDiagnosticsFrame(AFrame);
  TAtlasIdeTimingWindow.UpdateIcon;
  Theme(mFrame);
  if Assigned(TAtlasIdeTimingWindow.OnFrame) then
  begin
    TAtlasIdeTimingWindow.OnFrame(mFrame);
  end;
end;

function TTimingDock.GetMenuActionList: TCustomActionList;
begin
  Result := nil;
end;

function TTimingDock.GetMenuImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TTimingDock.CustomizePopupMenu(PopupMenu: TPopupMenu);
begin
end;

function TTimingDock.GetToolbarActionList: TCustomActionList;
begin
  Result := nil;
end;

function TTimingDock.GetToolbarImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TTimingDock.CustomizeToolBar(ToolBar: TToolBar);
begin
end;

procedure TTimingDock.SaveWindowState(Desktop: TCustomIniFile; const Section: string; IsProject: Boolean);
begin
end;

procedure TTimingDock.LoadWindowState(Desktop: TCustomIniFile; const Section: string);
begin
end;

function TTimingDock.GetEditState: TEditState;
begin
  Result := [];
end;

function TTimingDock.EditAction(Action: TEditAction): Boolean;
begin
  Result := False;
end;

procedure EnsureHost;
begin
  // Nicht im Desktop: Der Diagnosemodus öffnet das Fenster selbst, und zwar erst nach dem Build
  // (TAtlasIdeBuildIdleGate).
  if Host = nil then
  begin
    Host := TAtlasIdeDockWindow.Create(TTimingDock.Create, False);
  end;
end;

{ TAtlasIdeTimingWindow }

class function TAtlasIdeTimingWindow.Show: TAtlasDiagnosticsFrame;
var
  mCreated: Boolean;
begin
  // Lebt die Form noch (X versteckt nur), wird sie samt Gastgebern gezeigt; sonst neu angelegt.
  EnsureHost;
  Host.Show(mCreated);
  if mCreated then
  begin
    UpdateIcon;
  end;
  Result := ExistingFrame;
end;

class function TAtlasIdeTimingWindow.ExistingFrame: TAtlasDiagnosticsFrame;
begin
  Result := nil;
  if (Host <> nil) and (Host.Frame is TAtlasDiagnosticsFrame) then
  begin
    Result := TAtlasDiagnosticsFrame(Host.Frame);
  end;
end;

class function TAtlasIdeTimingWindow.Visible: Boolean;
begin
  // Angedockt in verstecktem Gastgeber zählt nicht als sichtbar.
  Result := (Host <> nil) and Host.Shown;
end;

class procedure TAtlasIdeTimingWindow.Hide;
begin
  if Host <> nil then
  begin
    Host.Hide;
  end;
end;

class procedure TAtlasIdeTimingWindow.UpdateIcon;
var
  mIcon: TIcon;
begin
  if (Host = nil) or (Host.Form = nil) then
  begin
    Exit;
  end;
  mIcon := TAtlasSymbolImages.Icon(TAtlasIdeSymbol.Current);
  try
    // Icon ist erst in TForm öffentlich.
    TForm(Host.Form).Icon.Assign(mIcon);
  finally
    mIcon.Free;
  end;
end;

class procedure TAtlasIdeTimingWindow.ApplyTheme;
var
  mFrame: TAtlasDiagnosticsFrame;
begin
  mFrame := ExistingFrame;
  if mFrame <> nil then
  begin
    Theme(mFrame);
  end;
  UpdateIcon;
end;

class procedure TAtlasIdeTimingWindow.Release;
begin
  OnFrame := nil;
  // Meldet ab und gibt die Form nur frei, wenn die IDE sie nicht schon zerstört hat.
  FreeAndNil(Host);
end;

end.
