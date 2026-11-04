unit Atlas.IDE.Welcome.ProjectWatch;

// welcomePage.openWhenNoProject (#761, Vorgabe an): Beobachter der IDE für
// geschlossene Projekte und Projektgruppen. Ist danach kein Projekt mehr offen
// (und die IDE wird nicht beendet), öffnet er das Fenster „Atlas-Start“ über
// die Steuerung. Abgeteilt aus Atlas.IDE.Welcome.Commands (Atlas-Befunde).

interface

uses
  System.SysUtils;

type
  TAtlasIdeWelcomeProjectWatch = class
  private
    // Beobachter der IDE; die IDE hält ihn.
    FNotifier: TObject;
    FIndex: Integer;
    // Prüfung „noch ein Projekt offen?“ ist eingereiht.
    FQueued: Boolean;
    FOnOpenStart: TProc;
    procedure Closing;
    procedure Check;
  public
    /// <summary>AOnOpenStart: Fenster „Atlas-Start“ öffnen. Meldet den Beobachter an.</summary>
    constructor Create(const AOnOpenStart: TProc);
    /// <summary>Meldet den Beobachter ab.</summary>
    destructor Destroy; override;
  end;

implementation

uses
  Vcl.Forms,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Welcome.Projects,
  Atlas.Core.Welcome.Search,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Welcome.Window;

type
  // Meldet das Schließen von Projekten und Projektgruppen (#1114).
  TClosedNotifier = class(TNotifierObject, IOTAIDENotifier)
  private
    FOwner: TAtlasIdeWelcomeProjectWatch;
  public
    procedure FileNotification(NotifyCode: TOTAFileNotification; const FileName: string; var Cancel: Boolean);
    procedure BeforeCompile(const Project: IOTAProject; var Cancel: Boolean); overload;
    procedure AfterCompile(Succeeded: Boolean); overload;
  end;

var
  // Lebt der Beobachter noch? Für Arbeit, die über die Nachrichtenschleife kommt.
  Instance: TAtlasIdeWelcomeProjectWatch;

function OpenProjectCount: Integer;
var
  mServices: IOTAModuleServices;
  mGroup: IOTAProjectGroup;
begin
  Result := -1;
  if Supports(BorlandIDEServices, IOTAModuleServices, mServices) then
  begin
    mGroup := mServices.MainProjectGroup;
    Result := 0;
    if mGroup <> nil then
    begin
      Result := mGroup.ProjectCount;
    end;
  end;
end;

function IdeRunning: Boolean;
begin
  // Beim Beenden schließt die IDE alle Projekte; dann kein Fenster mehr anlegen.
  Result := not Application.Terminated and (Application.MainForm <> nil) and Application.MainForm.Visible and
    not (csDestroying in Application.MainForm.ComponentState);
end;

{ TClosedNotifier }

procedure TClosedNotifier.FileNotification(NotifyCode: TOTAFileNotification; const FileName: string;
  var Cancel: Boolean);
var
  mOwner: TAtlasIdeWelcomeProjectWatch;
begin
  mOwner := FOwner;
  if (mOwner = nil) or (NotifyCode <> ofnFileClosing) or not TAtlasWelcomeSearch.IsProjectFile(FileName) then
  begin
    Exit;
  end;
  // Keine Exception an die IDE (#493).
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    begin
      mOwner.Closing;
    end);
end;

procedure TClosedNotifier.BeforeCompile(const Project: IOTAProject; var Cancel: Boolean);
begin
end;

procedure TClosedNotifier.AfterCompile(Succeeded: Boolean);
begin
end;

{ TAtlasIdeWelcomeProjectWatch }

constructor TAtlasIdeWelcomeProjectWatch.Create(const AOnOpenStart: TProc);
var
  mServices: IOTAServices;
  mNotifier: TClosedNotifier;
begin
  inherited Create;
  Instance := Self;
  FOnOpenStart := AOnOpenStart;
  FIndex := -1;
  if Supports(BorlandIDEServices, IOTAServices, mServices) then
  begin
    mNotifier := TClosedNotifier.Create;
    mNotifier.FOwner := Self;
    FNotifier := mNotifier;
    FIndex := mServices.AddNotifier(mNotifier);
  end;
end;

destructor TAtlasIdeWelcomeProjectWatch.Destroy;
var
  mServices: IOTAServices;
begin
  Instance := nil;
  if FNotifier <> nil then
  begin
    TClosedNotifier(FNotifier).FOwner := nil;
    // RemoveNotifier gibt die Referenz der IDE frei und damit den Beobachter (#493).
    if (FIndex >= 0) and Supports(BorlandIDEServices, IOTAServices, mServices) then
    begin
      mServices.RemoveNotifier(FIndex);
    end;
    FNotifier := nil;
    FIndex := -1;
  end;
  FOnOpenStart := nil;
  inherited;
end;

procedure TAtlasIdeWelcomeProjectWatch.Closing;
begin
  // ofnFileClosing kommt, bevor das Projekt weg ist; eine Gruppe schließt mehrere Projekte nacheinander.
  // Darum einmal danach über die Nachrichtenschleife prüfen.
  if FQueued then
  begin
    Exit;
  end;
  FQueued := True;
  TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage,
    procedure
    begin
      if Instance <> nil then
      begin
        Instance.Check;
      end;
    end);
end;

procedure TAtlasIdeWelcomeProjectWatch.Check;
var
  mCurrent: TAtlasPluginSettings;
begin
  FQueued := False;
  mCurrent := TAtlasIdeSettings.Current;
  if TAtlasWelcomeAutoOpen.AfterProjectClosed(mCurrent.WelcomePage, mCurrent.WelcomePageOpenWhenNoProject,
    OpenProjectCount, IdeRunning, TAtlasIdeWelcomeWindow.Visible) and Assigned(FOnOpenStart) then
  begin
    FOnOpenStart();
  end;
end;

end.
