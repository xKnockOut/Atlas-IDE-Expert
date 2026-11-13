unit Atlas.IDE.Debug.ExceptionsWindow;

// Andockbares Seitenfenster „Exception-Verlauf“ (#517): verankerbar wie die
// Lesezeichen (#622) über INTAServices.CreateDockableForm, Inhalt
// TAtlasDebugExceptionsFrame, IDE-Thema, Atlas-Symbol (#751) im Fenstertitel.
// OnFrame meldet einen neuen Frame, damit TAtlasIdeDebugExceptions ihn
// verdrahtet und füllt.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Forms,
  Atlas.UI.Debug.ExceptionsFrame;

type
  TAtlasIdeDebugExceptionsWindow = class
  public class var
    /// <summary>Ein neuer Frame ist entstanden; setzt TAtlasIdeDebugExceptions.</summary>
    OnFrame: TProc<TAtlasDebugExceptionsFrame>;
  public
    /// <summary>Fenster zeigen (bei Bedarf anlegen); nil, wenn die IDE keine andockbaren Fenster anbietet.</summary>
    class function Show: TAtlasDebugExceptionsFrame; static;
    /// <summary>Frame, falls das Fenster existiert; legt nichts an.</summary>
    class function ExistingFrame: TAtlasDebugExceptionsFrame; static;
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
  Atlas.UI.Debug.Strings,
  Atlas.UI.Style.Symbol,
  Atlas.IDE.Foundation.DockWindow;

type
  TExceptionsDock = class(TInterfacedObject, INTACustomDockableForm)
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

{ TExceptionsDock }

function TExceptionsDock.GetCaption: string;
begin
  Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugExceptionsCaption);
end;

function TExceptionsDock.GetIdentifier: string;
begin
  Result := 'AtlasDebugExceptions';
end;

function TExceptionsDock.GetFrameClass: TCustomFrameClass;
begin
  Result := TAtlasDebugExceptionsFrame;
end;

procedure TExceptionsDock.FrameCreated(AFrame: TCustomFrame);
var
  mFrame: TAtlasDebugExceptionsFrame;
begin
  if not (AFrame is TAtlasDebugExceptionsFrame) then
  begin
    Exit;
  end;
  if Host <> nil then
  begin
    Host.FrameCreated(AFrame);
  end;
  mFrame := TAtlasDebugExceptionsFrame(AFrame);
  TAtlasIdeDockWindow.UpdateIcon(Host);
  Theme(mFrame);
  if Assigned(TAtlasIdeDebugExceptionsWindow.OnFrame) then
  begin
    TAtlasIdeDebugExceptionsWindow.OnFrame(mFrame);
  end;
end;

function TExceptionsDock.GetMenuActionList: TCustomActionList;
begin
  Result := nil;
end;

function TExceptionsDock.GetMenuImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TExceptionsDock.CustomizePopupMenu(PopupMenu: TPopupMenu);
begin
end;

function TExceptionsDock.GetToolbarActionList: TCustomActionList;
begin
  Result := nil;
end;

function TExceptionsDock.GetToolbarImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TExceptionsDock.CustomizeToolBar(ToolBar: TToolBar);
begin
end;

procedure TExceptionsDock.SaveWindowState(Desktop: TCustomIniFile; const Section: string; IsProject: Boolean);
begin
end;

procedure TExceptionsDock.LoadWindowState(Desktop: TCustomIniFile; const Section: string);
begin
end;

function TExceptionsDock.GetEditState: TEditState;
begin
  Result := [];
end;

function TExceptionsDock.EditAction(Action: TEditAction): Boolean;
begin
  Result := False;
end;

procedure EnsureHost;
begin
  if Host = nil then
  begin
    Host := TAtlasIdeDockWindow.Create(TExceptionsDock.Create, True);
  end;
end;

{ TAtlasIdeDebugExceptionsWindow }

class function TAtlasIdeDebugExceptionsWindow.Show: TAtlasDebugExceptionsFrame;
begin
  // Lebt die Form noch (X versteckt nur), wird sie samt Gastgebern gezeigt; sonst neu angelegt.
  EnsureHost;
  Host.Present;
  Result := ExistingFrame;
end;

class function TAtlasIdeDebugExceptionsWindow.ExistingFrame: TAtlasDebugExceptionsFrame;
begin
  Result := nil;
  if (Host <> nil) and (Host.Frame is TAtlasDebugExceptionsFrame) then
  begin
    Result := TAtlasDebugExceptionsFrame(Host.Frame);
  end;
end;

class function TAtlasIdeDebugExceptionsWindow.Visible: Boolean;
begin
  Result := TAtlasIdeDockWindow.IsShown(Host);
end;

class procedure TAtlasIdeDebugExceptionsWindow.Hide;
begin
  TAtlasIdeDockWindow.HideIfAny(Host);
end;

class procedure TAtlasIdeDebugExceptionsWindow.ApplyTheme;
var
  mFrame: TAtlasDebugExceptionsFrame;
begin
  mFrame := ExistingFrame;
  if mFrame <> nil then
  begin
    Theme(mFrame);
  end;
  TAtlasIdeDockWindow.UpdateIcon(Host);
end;

class procedure TAtlasIdeDebugExceptionsWindow.Prepare;
begin
  EnsureHost;
end;

class procedure TAtlasIdeDebugExceptionsWindow.Release;
begin
  OnFrame := nil;
  // Meldet ab und gibt die Form nur frei, wenn die IDE sie nicht schon zerstört hat.
  FreeAndNil(Host);
end;

end.
