unit Atlas.IDE.Debug.BreakpointsWindow;

// Andockbares Fenster „Schrittfilter“ (#850): verankerbar wie die Lesezeichen
// (#622) über INTACustomDockableForm, Inhalt TAtlasDebugBreakpointsFrame,
// IDE-Thema (hell und dunkel), Atlas-Symbol (#751) im Fenstertitel. OnFrame
// meldet einen neuen Frame, damit TAtlasIdeDebugStepFilter ihn verdrahtet und
// füllt.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Forms,
  Atlas.UI.Debug.BreakpointsFrame;

type
  TAtlasIdeDebugBreakpointsWindow = class
  public class var
    /// <summary>Ein neuer Frame ist entstanden; setzt TAtlasIdeDebugBreakpointList.</summary>
    OnFrame: TProc<TAtlasDebugBreakpointsFrame>;
  public
    /// <summary>Fenster zeigen (bei Bedarf anlegen); nil, wenn die IDE keine andockbaren Fenster anbietet.</summary>
    class function Show: TAtlasDebugBreakpointsFrame; static;
    /// <summary>Frame, falls das Fenster existiert; legt nichts an.</summary>
    class function ExistingFrame: TAtlasDebugBreakpointsFrame; static;
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
  Vcl.ActnList,
  Vcl.ImgList,
  Vcl.Menus,
  Vcl.ComCtrls,
  Vcl.Graphics,
  DesignIntf,
  ToolsAPI,
  Atlas.Core.Debug.BreakpointList,
  Atlas.UI.Debug.Strings,
  Atlas.UI.Style.Symbol,
  Atlas.IDE.Foundation.DockWindow;

type
  TBreakpointsDock = class(TInterfacedObject, INTACustomDockableForm)
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

const
  cColumnsKey = 'AtlasColumns';
  cGroupingKey = 'AtlasGrouping';

var
  // Verwaltet Form, Frame und Anmeldung bei der IDE (#879).
  Host: TAtlasIdeDockWindow;
  // Aus dem Desktop gelesen, bevor es einen Frame gab.
  Layout: record
    Known: Boolean;
    Columns: string;
    Grouping: Integer;
  end;

procedure ApplyLayout(AFrame: TAtlasDebugBreakpointsFrame);
begin
  if Layout.Known then
  begin
    AFrame.Columns := TAtlasBreakpointColumns.Parse(Layout.Columns);
    if (Layout.Grouping >= Ord(Low(TAtlasBreakpointGrouping))) and
      (Layout.Grouping <= Ord(High(TAtlasBreakpointGrouping))) then
    begin
      AFrame.SetGrouping(TAtlasBreakpointGrouping(Layout.Grouping));
    end;
  end;
end;

procedure Theme(AFrame: TCustomFrame);
begin
  TAtlasIdeDockWindow.ApplyIdeTheme(AFrame);
end;

{ TBreakpointsDock }

function TBreakpointsDock.GetCaption: string;
begin
  Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.BreakpointsCaption);
end;

function TBreakpointsDock.GetIdentifier: string;
begin
  Result := 'AtlasBreakpoints';
end;

function TBreakpointsDock.GetFrameClass: TCustomFrameClass;
begin
  Result := TAtlasDebugBreakpointsFrame;
end;

procedure TBreakpointsDock.FrameCreated(AFrame: TCustomFrame);
var
  mFrame: TAtlasDebugBreakpointsFrame;
begin
  if not (AFrame is TAtlasDebugBreakpointsFrame) then
  begin
    Exit;
  end;
  if Host <> nil then
  begin
    Host.FrameCreated(AFrame);
  end;
  mFrame := TAtlasDebugBreakpointsFrame(AFrame);
  TAtlasIdeDockWindow.UpdateIcon(Host);
  Theme(mFrame);
  ApplyLayout(mFrame);
  if Assigned(TAtlasIdeDebugBreakpointsWindow.OnFrame) then
  begin
    TAtlasIdeDebugBreakpointsWindow.OnFrame(mFrame);
  end;
end;

function TBreakpointsDock.GetMenuActionList: TCustomActionList;
begin
  Result := nil;
end;

function TBreakpointsDock.GetMenuImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TBreakpointsDock.CustomizePopupMenu(PopupMenu: TPopupMenu);
begin
end;

function TBreakpointsDock.GetToolbarActionList: TCustomActionList;
begin
  Result := nil;
end;

function TBreakpointsDock.GetToolbarImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TBreakpointsDock.CustomizeToolBar(ToolBar: TToolBar);
begin
end;

procedure TBreakpointsDock.SaveWindowState(Desktop: TCustomIniFile; const Section: string; IsProject: Boolean);
var
  mFrame: TAtlasDebugBreakpointsFrame;
begin
  mFrame := TAtlasIdeDebugBreakpointsWindow.ExistingFrame;
  if mFrame <> nil then
  begin
    Desktop.WriteString(Section, cColumnsKey, mFrame.Columns.ToText);
    Desktop.WriteInteger(Section, cGroupingKey, Ord(mFrame.CurrentGrouping));
  end;
end;

procedure TBreakpointsDock.LoadWindowState(Desktop: TCustomIniFile; const Section: string);
var
  mFrame: TAtlasDebugBreakpointsFrame;
begin
  Layout.Columns := Desktop.ReadString(Section, cColumnsKey, '');
  Layout.Grouping := Desktop.ReadInteger(Section, cGroupingKey, 0);
  Layout.Known := True;
  mFrame := TAtlasIdeDebugBreakpointsWindow.ExistingFrame;
  if mFrame <> nil then
  begin
    ApplyLayout(mFrame);
  end;
end;

function TBreakpointsDock.GetEditState: TEditState;
begin
  Result := [];
end;

function TBreakpointsDock.EditAction(Action: TEditAction): Boolean;
begin
  Result := False;
end;

procedure EnsureHost;
begin
  if Host = nil then
  begin
    Host := TAtlasIdeDockWindow.Create(TBreakpointsDock.Create, True);
  end;
end;

{ TAtlasIdeDebugBreakpointsWindow }

class function TAtlasIdeDebugBreakpointsWindow.Show: TAtlasDebugBreakpointsFrame;
begin
  // Lebt die Form noch (X versteckt nur), wird sie samt Gastgebern gezeigt; sonst neu angelegt.
  EnsureHost;
  Host.Present;
  Result := ExistingFrame;
end;

class function TAtlasIdeDebugBreakpointsWindow.ExistingFrame: TAtlasDebugBreakpointsFrame;
begin
  Result := nil;
  if (Host <> nil) and (Host.Frame is TAtlasDebugBreakpointsFrame) then
  begin
    Result := TAtlasDebugBreakpointsFrame(Host.Frame);
  end;
end;

class function TAtlasIdeDebugBreakpointsWindow.Visible: Boolean;
begin
  Result := TAtlasIdeDockWindow.IsShown(Host);
end;

class procedure TAtlasIdeDebugBreakpointsWindow.Hide;
begin
  TAtlasIdeDockWindow.HideIfAny(Host);
end;

class procedure TAtlasIdeDebugBreakpointsWindow.ApplyTheme;
var
  mFrame: TAtlasDebugBreakpointsFrame;
begin
  mFrame := ExistingFrame;
  if mFrame <> nil then
  begin
    Theme(mFrame);
  end;
  TAtlasIdeDockWindow.UpdateIcon(Host);
end;

class procedure TAtlasIdeDebugBreakpointsWindow.Prepare;
begin
  EnsureHost;
end;

class procedure TAtlasIdeDebugBreakpointsWindow.Release;
begin
  OnFrame := nil;
  // Meldet ab und gibt die Form nur frei, wenn die IDE sie nicht schon zerstört hat.
  FreeAndNil(Host);
end;

end.
