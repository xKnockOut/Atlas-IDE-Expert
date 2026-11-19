unit Atlas.IDE.Debug.DockPanel;

// Gemeinsamer Gastgeber für andockbare Fenster des Debuggers: verankerbar wie die Lesezeichen (#622) über
// TAtlasIdeDockWindow, Inhalt ein Frame der übergebenen Klasse, IDE-Thema, Atlas-Symbol (#751) im Fenstertitel.
// OnFrame meldet einen neuen Frame, damit die IDE-Schicht ihn verdrahtet und füllt. Ein Objekt je Fenster;
// Freigeben meldet das Fenster bei der IDE ab. Für neue Fenster statt einer weiteren Kopie der Fenster-Units.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Forms,
  Atlas.IDE.Foundation.DockWindow;

type
  TAtlasIdeDebugDockPanel = class
  private
    FHost: TAtlasIdeDockWindow;
    FIdentifier: string;
    FFrameClass: TCustomFrameClass;
    FCaption: TFunc<string>;
    FOnFrame: TProc<TCustomFrame>;
    procedure EnsureHost;
    procedure FrameCreated(AFrame: TCustomFrame);
  public
    /// <summary>AIdentifier: Name des Fensters im Desktop der IDE; ACaption liefert den Titel in der Sprache der
    /// Oberfläche.</summary>
    constructor Create(const AIdentifier: string; AFrameClass: TCustomFrameClass; const ACaption: TFunc<string>);
    destructor Destroy; override;
    /// <summary>Fenster zeigen (bei Bedarf anlegen); nil, wenn die IDE keine andockbaren Fenster anbietet.</summary>
    function Show: TCustomFrame;
    /// <summary>Frame, falls das Fenster existiert; legt nichts an.</summary>
    function ExistingFrame: TCustomFrame;
    /// <summary>Angedockt in verstecktem Gastgeber zählt nicht als sichtbar.</summary>
    function Visible: Boolean;
    procedure Hide;
    procedure ApplyTheme;
    /// <summary>Früh: bei der IDE anmelden, damit der Desktop das Fenster speichert und wiederherstellt (#879).
    /// </summary>
    procedure Prepare;
    property OnFrame: TProc<TCustomFrame> read FOnFrame write FOnFrame;
  end;

implementation

uses
  System.IniFiles,
  Vcl.ActnList,
  Vcl.ImgList,
  Vcl.Menus,
  Vcl.ComCtrls,
  DesignIntf,
  ToolsAPI;

type
  TPanelDock = class(TInterfacedObject, INTACustomDockableForm)
  private
    FPanel: TAtlasIdeDebugDockPanel;
  public
    constructor Create(APanel: TAtlasIdeDebugDockPanel);
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

{ TPanelDock }

constructor TPanelDock.Create(APanel: TAtlasIdeDebugDockPanel);
begin
  inherited Create;
  FPanel := APanel;
end;

function TPanelDock.GetCaption: string;
begin
  Result := FPanel.FCaption();
end;

function TPanelDock.GetIdentifier: string;
begin
  Result := FPanel.FIdentifier;
end;

function TPanelDock.GetFrameClass: TCustomFrameClass;
begin
  Result := FPanel.FFrameClass;
end;

procedure TPanelDock.FrameCreated(AFrame: TCustomFrame);
begin
  FPanel.FrameCreated(AFrame);
end;

function TPanelDock.GetMenuActionList: TCustomActionList;
begin
  Result := nil;
end;

function TPanelDock.GetMenuImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TPanelDock.CustomizePopupMenu(PopupMenu: TPopupMenu);
begin
end;

function TPanelDock.GetToolbarActionList: TCustomActionList;
begin
  Result := nil;
end;

function TPanelDock.GetToolbarImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TPanelDock.CustomizeToolBar(ToolBar: TToolBar);
begin
end;

procedure TPanelDock.SaveWindowState(Desktop: TCustomIniFile; const Section: string; IsProject: Boolean);
begin
end;

procedure TPanelDock.LoadWindowState(Desktop: TCustomIniFile; const Section: string);
begin
end;

function TPanelDock.GetEditState: TEditState;
begin
  Result := [];
end;

function TPanelDock.EditAction(Action: TEditAction): Boolean;
begin
  Result := False;
end;

{ TAtlasIdeDebugDockPanel }

constructor TAtlasIdeDebugDockPanel.Create(const AIdentifier: string; AFrameClass: TCustomFrameClass;
  const ACaption: TFunc<string>);
begin
  inherited Create;
  FIdentifier := AIdentifier;
  FFrameClass := AFrameClass;
  FCaption := ACaption;
end;

destructor TAtlasIdeDebugDockPanel.Destroy;
begin
  FOnFrame := nil;
  // Meldet ab und gibt die Form nur frei, wenn die IDE sie nicht schon zerstört hat.
  FreeAndNil(FHost);
  FCaption := nil;
  inherited Destroy;
end;

procedure TAtlasIdeDebugDockPanel.EnsureHost;
begin
  if FHost = nil then
  begin
    FHost := TAtlasIdeDockWindow.Create(TPanelDock.Create(Self), True);
  end;
end;

procedure TAtlasIdeDebugDockPanel.FrameCreated(AFrame: TCustomFrame);
begin
  if not (AFrame is FFrameClass) then
  begin
    Exit;
  end;
  if FHost <> nil then
  begin
    FHost.FrameCreated(AFrame);
  end;
  TAtlasIdeDockWindow.UpdateIcon(FHost);
  TAtlasIdeDockWindow.ApplyIdeTheme(AFrame);
  if Assigned(FOnFrame) then
  begin
    FOnFrame(AFrame);
  end;
end;

function TAtlasIdeDebugDockPanel.Show: TCustomFrame;
begin
  // Lebt die Form noch (X versteckt nur), wird sie samt Gastgebern gezeigt; sonst neu angelegt.
  EnsureHost;
  FHost.Present;
  Result := ExistingFrame;
end;

function TAtlasIdeDebugDockPanel.ExistingFrame: TCustomFrame;
begin
  Result := nil;
  if (FHost <> nil) and (FHost.Frame is FFrameClass) then
  begin
    Result := FHost.Frame;
  end;
end;

function TAtlasIdeDebugDockPanel.Visible: Boolean;
begin
  Result := TAtlasIdeDockWindow.IsShown(FHost);
end;

procedure TAtlasIdeDebugDockPanel.Hide;
begin
  TAtlasIdeDockWindow.HideIfAny(FHost);
end;

procedure TAtlasIdeDebugDockPanel.ApplyTheme;
var
  mFrame: TCustomFrame;
begin
  mFrame := ExistingFrame;
  if mFrame <> nil then
  begin
    TAtlasIdeDockWindow.ApplyIdeTheme(mFrame);
  end;
  TAtlasIdeDockWindow.UpdateIcon(FHost);
end;

procedure TAtlasIdeDebugDockPanel.Prepare;
begin
  EnsureHost;
end;

end.
