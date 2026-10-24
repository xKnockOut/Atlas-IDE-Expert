unit Atlas.IDE.Search.ReplaceWindow;

// Andockbares Fenster „Atlas-Suche: Ersetzen“ (#893): die Treffer einer Suche
// über Dateien mit Häkchen und „Ausgewählte ersetzen“ (Inhalt
// TAtlasSearchReplaceFrame). Das Register „Atlas-Suche“ der Meldungen kann
// keine Häkchen zeigen; deshalb dieses Fenster, verankerbar wie das
// Diagnosefenster (#479) über INTAServices.CreateDockableForm, mit IDE-Thema
// und Atlas-Symbol (#751). Nicht im Desktop: Die Suchleiste öffnet es mit
// „Auswählen …“. OnFrame meldet einen neuen Frame, damit die Suche ihn füllt.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Forms,
  Atlas.UI.Search.ReplaceFrame;

type
  TAtlasIdeSearchReplaceWindow = class
  public class var
    /// <summary>Ein neuer Frame ist entstanden; setzt die Suche.</summary>
    OnFrame: TProc<TAtlasSearchReplaceFrame>;
  public
    /// <summary>Fenster zeigen (bei Bedarf anlegen); nil, wenn die IDE keine andockbaren Fenster anbietet.</summary>
    class function Show: TAtlasSearchReplaceFrame; static;
    /// <summary>Frame, falls das Fenster existiert; legt nichts an.</summary>
    class function ExistingFrame: TAtlasSearchReplaceFrame; static;
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
  TReplaceDock = class(TInterfacedObject, INTACustomDockableForm)
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

{ TReplaceDock }

function TReplaceDock.GetCaption: string;
begin
  Result := TAtlasStrings.Text(TAtlasTextId.SearchReplaceCaption);
end;

function TReplaceDock.GetIdentifier: string;
begin
  Result := 'AtlasSearchReplace';
end;

function TReplaceDock.GetFrameClass: TCustomFrameClass;
begin
  Result := TAtlasSearchReplaceFrame;
end;

procedure TReplaceDock.FrameCreated(AFrame: TCustomFrame);
var
  Frame: TAtlasSearchReplaceFrame;
begin
  if not (AFrame is TAtlasSearchReplaceFrame) then
    Exit;
  if Host <> nil then
    Host.FrameCreated(AFrame);
  Frame := TAtlasSearchReplaceFrame(AFrame);
  TAtlasIdeSearchReplaceWindow.UpdateIcon;
  Theme(Frame);
  if Assigned(TAtlasIdeSearchReplaceWindow.OnFrame) then
    TAtlasIdeSearchReplaceWindow.OnFrame(Frame);
end;

function TReplaceDock.GetMenuActionList: TCustomActionList;
begin
  Result := nil;
end;

function TReplaceDock.GetMenuImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TReplaceDock.CustomizePopupMenu(PopupMenu: TPopupMenu);
begin
end;

function TReplaceDock.GetToolbarActionList: TCustomActionList;
begin
  Result := nil;
end;

function TReplaceDock.GetToolbarImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TReplaceDock.CustomizeToolBar(ToolBar: TToolBar);
begin
end;

procedure TReplaceDock.SaveWindowState(Desktop: TCustomIniFile; const Section: string; IsProject: Boolean);
begin
end;

procedure TReplaceDock.LoadWindowState(Desktop: TCustomIniFile; const Section: string);
begin
end;

function TReplaceDock.GetEditState: TEditState;
begin
  Result := [];
end;

function TReplaceDock.EditAction(Action: TEditAction): Boolean;
begin
  Result := False;
end;

procedure EnsureHost;
begin
  // Nicht im Desktop: Die Suchleiste öffnet das Fenster selbst.
  if Host = nil then
    Host := TAtlasIdeDockWindow.Create(TReplaceDock.Create, False);
end;

{ TAtlasIdeSearchReplaceWindow }

class function TAtlasIdeSearchReplaceWindow.Show: TAtlasSearchReplaceFrame;
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

class function TAtlasIdeSearchReplaceWindow.ExistingFrame: TAtlasSearchReplaceFrame;
begin
  Result := nil;
  if (Host <> nil) and (Host.Frame is TAtlasSearchReplaceFrame) then
    Result := TAtlasSearchReplaceFrame(Host.Frame);
end;

class function TAtlasIdeSearchReplaceWindow.Visible: Boolean;
begin
  // Angedockt in verstecktem Gastgeber zählt nicht als sichtbar.
  Result := (Host <> nil) and Host.Shown;
end;

class procedure TAtlasIdeSearchReplaceWindow.Hide;
begin
  if Host <> nil then
    Host.Hide;
end;

class procedure TAtlasIdeSearchReplaceWindow.UpdateIcon;
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

class procedure TAtlasIdeSearchReplaceWindow.ApplyTheme;
var
  Frame: TAtlasSearchReplaceFrame;
begin
  Frame := ExistingFrame;
  if Frame <> nil then
    Theme(Frame);
  UpdateIcon;
end;

class procedure TAtlasIdeSearchReplaceWindow.Release;
begin
  OnFrame := nil;
  // Meldet ab und gibt die Form nur frei, wenn die IDE sie nicht schon zerstört hat.
  FreeAndNil(Host);
end;

end.
