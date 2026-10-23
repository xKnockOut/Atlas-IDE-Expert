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
  Result := TAtlasStrings.Text(TAtlasTextId.DebugExceptionsCaption);
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
  Frame: TAtlasDebugExceptionsFrame;
begin
  if not (AFrame is TAtlasDebugExceptionsFrame) then
    Exit;
  if Host <> nil then
    Host.FrameCreated(AFrame);
  Frame := TAtlasDebugExceptionsFrame(AFrame);
  TAtlasIdeDebugExceptionsWindow.UpdateIcon;
  Theme(Frame);
  if Assigned(TAtlasIdeDebugExceptionsWindow.OnFrame) then
    TAtlasIdeDebugExceptionsWindow.OnFrame(Frame);
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
    Host := TAtlasIdeDockWindow.Create(TExceptionsDock.Create, True);
end;

{ TAtlasIdeDebugExceptionsWindow }

class function TAtlasIdeDebugExceptionsWindow.Show: TAtlasDebugExceptionsFrame;
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

class function TAtlasIdeDebugExceptionsWindow.ExistingFrame: TAtlasDebugExceptionsFrame;
begin
  Result := nil;
  if (Host <> nil) and (Host.Frame is TAtlasDebugExceptionsFrame) then
    Result := TAtlasDebugExceptionsFrame(Host.Frame);
end;

class function TAtlasIdeDebugExceptionsWindow.Visible: Boolean;
begin
  // Angedockt in verstecktem Gastgeber zählt nicht als sichtbar.
  Result := (Host <> nil) and Host.Shown;
end;

class procedure TAtlasIdeDebugExceptionsWindow.Hide;
begin
  if Host <> nil then
    Host.Hide;
end;

class procedure TAtlasIdeDebugExceptionsWindow.UpdateIcon;
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

class procedure TAtlasIdeDebugExceptionsWindow.ApplyTheme;
var
  Frame: TAtlasDebugExceptionsFrame;
begin
  Frame := ExistingFrame;
  if Frame <> nil then
    Theme(Frame);
  UpdateIcon;
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
