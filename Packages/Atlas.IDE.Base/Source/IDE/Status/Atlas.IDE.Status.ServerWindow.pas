unit Atlas.IDE.Status.ServerWindow;

// Andockbares Fenster „Atlas-Server“ (#1356) über TAtlasIdeDockWindow, Inhalt
// TAtlasServerFrame. Es fragt den Server nicht selbst ab: Die Statuszeilen
// (TAtlasIdeStatusLines) holen atlas.server.status ohnehin alle 5 s, solange
// der Server läuft; das Fenster liest diese Antwort (Hook StatusJson) alle
// 5 s, aber nur, solange es wirklich zu sehen ist (Host.Shown), und nur, wenn
// sie sich geändert hat. „Aktualisieren“ stößt eine Abfrage sofort an (Hook
// QueryNow) und zeigt danach. Neustarts der Sitzung kommen vom Code
// Insight-Manager. Doppelklick auf eine Unit öffnet sie, auf eine Regel die
// Regelseite der Prüfung (#909); „Index neu aufbauen“ und
// „Diagnosepaket erstellen …“ gehen an die Composition. Mit
// server.statusWindow aus öffnet Show nichts und ein offenes Fenster
// schließt (ApplySettings). Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Classes,
  Atlas.Core.Status.Server;

type
  TAtlasIdeServerWindow = class
  public type
    THooks = record
      /// <summary>Letzte Antwort von atlas.server.status; '' ohne.</summary>
      StatusJson: TFunc<string>;
      /// <summary>Läuft der Server?</summary>
      Running: TFunc<Boolean>;
      /// <summary>Neustarts in dieser Sitzung.</summary>
      Restarts: TFunc<Integer>;
      /// <summary>Status sofort abfragen, ADone danach im Hauptthread; False ohne Abfrage.</summary>
      QueryNow: TFunc<TProc, Boolean>;
      Rebuild: TProc;
      Package: TProc;
      OpenUnit: TProc<TAtlasServerSlowUnit>;
      OpenRule: TProc<string>;
    end;
  private class var
    FHooks: THooks;
  public
    class procedure Install(const AHooks: THooks); static;
    /// <summary>Ist das Fenster eingeschaltet (server.statusWindow)?</summary>
    class function Enabled: Boolean; static;
    /// <summary>Fenster zeigen (bei Bedarf anlegen) und sofort füllen; nichts, wenn abgeschaltet.</summary>
    class procedure Show; static;
    class function Visible: Boolean; static;
    /// <summary>Einstellungen geändert: abgeschaltet schließt das Fenster.</summary>
    class procedure ApplySettings; static;
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
  Vcl.ExtCtrls,
  Vcl.Forms,
  DesignIntf,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.UI.Strings,
  Atlas.UI.Style.Symbol,
  Atlas.UI.Status.ServerFrame,
  Atlas.IDE.Foundation.Symbol,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.DockWindow;

const
  cRefreshMs = 5000;

type
  TServerDock = class(TInterfacedObject, INTACustomDockableForm)
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

  /// <summary>Zeitgeber und zuletzt gezeigter Stand.</summary>
  TServerState = class
  private
    FTimer: TTimer;
    FShownJson: string;
    FShownRunning: Boolean;
    FShownRestarts: Integer;
    procedure TimerTick(Sender: TObject);
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Frame neu füllen; AForce auch ohne Änderung.</summary>
    procedure Refresh(AForce: Boolean);
  end;

var
  Host: TAtlasIdeDockWindow;
  State: TServerState;

function Frame: TAtlasServerFrame;
begin
  Result := nil;
  if (Host <> nil) and (Host.Frame is TAtlasServerFrame) then
    Result := TAtlasServerFrame(Host.Frame);
end;

procedure UpdateIcon;
var
  mIcon: TIcon;
begin
  if (Host = nil) or (Host.Form = nil) then
    Exit;
  mIcon := TAtlasSymbolImages.Icon(TAtlasIdeSymbol.Current);
  try
    // Icon ist erst in TForm öffentlich.
    TForm(Host.Form).Icon.Assign(mIcon);
  finally
    mIcon.Free;
  end;
end;

procedure Theme(AFrame: TAtlasServerFrame);
begin
  TAtlasIdeDockWindow.ApplyIdeTheme(AFrame);
  AFrame.SetColors(TAtlasIdeStyle.Colors);
end;

procedure Wire(AFrame: TAtlasServerFrame);
begin
  AFrame.OnRefresh :=
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.Status,
        procedure
        begin
          if Assigned(TAtlasIdeServerWindow.FHooks.QueryNow) and TAtlasIdeServerWindow.FHooks.QueryNow(
            procedure
            begin
              if State <> nil then
                State.Refresh(True);
            end) then
            Exit;
          // Läuft gerade eine Abfrage (oder kein Server): zeigen, was da ist.
          if State <> nil then
            State.Refresh(True);
        end);
    end;
  AFrame.OnRebuild :=
    procedure
    begin
      if Assigned(TAtlasIdeServerWindow.FHooks.Rebuild) then
        TAtlasGuard.Run(TAtlasFeature.Status, TAtlasIdeServerWindow.FHooks.Rebuild);
    end;
  AFrame.OnPackage :=
    procedure
    begin
      if Assigned(TAtlasIdeServerWindow.FHooks.Package) then
        TAtlasGuard.Run(TAtlasFeature.Status, TAtlasIdeServerWindow.FHooks.Package);
    end;
  AFrame.OnOpenUnit :=
    procedure(AUnit: TAtlasServerSlowUnit)
    var
      mUnit: TAtlasServerSlowUnit;
    begin
      mUnit := AUnit;
      if Assigned(TAtlasIdeServerWindow.FHooks.OpenUnit) then
        TAtlasGuard.Run(TAtlasFeature.Status,
          procedure
          begin
            TAtlasIdeServerWindow.FHooks.OpenUnit(mUnit);
          end);
    end;
  AFrame.OnOpenRule :=
    procedure(ARule: string)
    var
      mRule: string;
    begin
      mRule := ARule;
      if Assigned(TAtlasIdeServerWindow.FHooks.OpenRule) then
        TAtlasGuard.Run(TAtlasFeature.Status,
          procedure
          begin
            TAtlasIdeServerWindow.FHooks.OpenRule(mRule);
          end);
    end;
end;

{ TServerDock }

function TServerDock.GetCaption: string;
begin
  Result := TAtlasStrings.Text(TAtlasTextId.ServerWindowCaption);
end;

function TServerDock.GetIdentifier: string;
begin
  Result := 'AtlasServerStatus';
end;

function TServerDock.GetFrameClass: TCustomFrameClass;
begin
  Result := TAtlasServerFrame;
end;

procedure TServerDock.FrameCreated(AFrame: TCustomFrame);
begin
  if not (AFrame is TAtlasServerFrame) then
    Exit;
  if Host <> nil then
    Host.FrameCreated(AFrame);
  UpdateIcon;
  Theme(TAtlasServerFrame(AFrame));
  Wire(TAtlasServerFrame(AFrame));
  if State <> nil then
    State.Refresh(True);
end;

function TServerDock.GetMenuActionList: TCustomActionList;
begin
  Result := nil;
end;

function TServerDock.GetMenuImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TServerDock.CustomizePopupMenu(PopupMenu: TPopupMenu);
begin
end;

function TServerDock.GetToolbarActionList: TCustomActionList;
begin
  Result := nil;
end;

function TServerDock.GetToolbarImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TServerDock.CustomizeToolBar(ToolBar: TToolBar);
begin
end;

procedure TServerDock.SaveWindowState(Desktop: TCustomIniFile; const Section: string; IsProject: Boolean);
begin
end;

procedure TServerDock.LoadWindowState(Desktop: TCustomIniFile; const Section: string);
begin
end;

function TServerDock.GetEditState: TEditState;
begin
  Result := [];
end;

function TServerDock.EditAction(Action: TEditAction): Boolean;
begin
  Result := False;
end;

{ TServerState }

constructor TServerState.Create;
begin
  inherited Create;
  FShownRestarts := -1;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := cRefreshMs;
  FTimer.OnTimer := TimerTick;
  FTimer.Enabled := True;
end;

destructor TServerState.Destroy;
begin
  FreeAndNil(FTimer);
  inherited;
end;

procedure TServerState.TimerTick(Sender: TObject);
begin
  TAtlasGuard.Run(TAtlasFeature.Status,
    procedure
    begin
      // Geschlossen, verdeckt oder als Reiter im Hintergrund: nichts lesen, nichts zeichnen.
      if (Host = nil) or not Host.Shown then
        Exit;
      Refresh(False);
    end);
end;

procedure TServerState.Refresh(AForce: Boolean);
var
  mFrame: TAtlasServerFrame;
  mJson: string;
  mRunning: Boolean;
  mRestarts: Integer;
begin
  mFrame := Frame;
  if mFrame = nil then
    Exit;
  mJson := '';
  if Assigned(TAtlasIdeServerWindow.FHooks.StatusJson) then
    mJson := TAtlasIdeServerWindow.FHooks.StatusJson();
  mRunning := Assigned(TAtlasIdeServerWindow.FHooks.Running) and TAtlasIdeServerWindow.FHooks.Running();
  mRestarts := 0;
  if Assigned(TAtlasIdeServerWindow.FHooks.Restarts) then
    mRestarts := TAtlasIdeServerWindow.FHooks.Restarts();
  if not AForce and (mJson = FShownJson) and (mRunning = FShownRunning) and (mRestarts = FShownRestarts) then
    Exit;
  FShownJson := mJson;
  FShownRunning := mRunning;
  FShownRestarts := mRestarts;
  mFrame.SetSnapshot(TAtlasServerSnapshot.Parse(mJson), mRunning, mRestarts);
  mFrame.ShowNote(TAtlasStrings.Fmt(TAtlasTextId.ServerWindowUpdated, [FormatDateTime('hh":"nn":"ss', Now)]) +
    ' · ' + TAtlasStrings.Text(TAtlasTextId.ServerWindowHint));
end;

{ TAtlasIdeServerWindow }

class procedure TAtlasIdeServerWindow.Install(const AHooks: THooks);
begin
  FHooks := AHooks;
end;

class function TAtlasIdeServerWindow.Enabled: Boolean;
begin
  Result := TAtlasIdeSettings.Current.ServerStatusWindow;
end;

class procedure TAtlasIdeServerWindow.Show;
var
  mCreated: Boolean;
begin
  if not Enabled then
    Exit;
  // Nicht im Desktop: geöffnet nur auf Befehl, damit ohne Fenster nichts mitliest.
  if Host = nil then
    Host := TAtlasIdeDockWindow.Create(TServerDock.Create, False);
  if State = nil then
    State := TServerState.Create;
  Host.Show(mCreated);
  if mCreated then
    UpdateIcon;
  State.Refresh(True);
end;

class function TAtlasIdeServerWindow.Visible: Boolean;
begin
  Result := (Host <> nil) and Host.Shown;
end;

class procedure TAtlasIdeServerWindow.ApplySettings;
begin
  if not Enabled and (Host <> nil) then
    Host.Hide;
end;

class procedure TAtlasIdeServerWindow.ApplyTheme;
var
  mFrame: TAtlasServerFrame;
begin
  mFrame := Frame;
  if mFrame <> nil then
    Theme(mFrame);
  UpdateIcon;
end;

class procedure TAtlasIdeServerWindow.Release;
begin
  FHooks := Default(THooks);
  FreeAndNil(State);
  // Meldet ab und gibt die Form nur frei, wenn die IDE sie nicht schon zerstört hat.
  FreeAndNil(Host);
end;

end.
