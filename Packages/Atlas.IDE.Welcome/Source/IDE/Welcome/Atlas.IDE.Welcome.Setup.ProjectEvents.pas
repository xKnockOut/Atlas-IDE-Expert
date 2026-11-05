unit Atlas.IDE.Welcome.Setup.ProjectEvents;

// Beobachter der IDE für die Karte „<Projekt> für Atlas einrichten“ (#759):
// meldet, wenn sich das Ziel der Karte ändern kann, also bei einem anderen
// aktiven Projekt (ofnActiveProjectChanged) und beim Öffnen oder Schließen
// eines Projekts bzw. einer Projektgruppe (dann ändert sich auch die Liste
// „Wieder öffnen“). Ersetzt das Vergleichen jede Sekunde: Es lief auch bei
// geschlossener Willkommensseite und prüfte jedes Mal Dateien im Hauptthread
// (im Diagnose-Fenster die Willkommensseite alle 1 bis 2 s mit 20 bis 60 ms).
// Die IDE meldet beim Wechsel mehrere Ereignisse hintereinander (eine Gruppe
// schließt ihre Projekte einzeln, ofnActiveProjectChanged kommt vor dem
// Einlesen): OnChanged kommt einmal danach über die Nachrichtenschleife.

interface

uses
  System.SysUtils;

type
  TAtlasIdeSetupProjectEvents = class
  private
    // Beobachter der IDE; die IDE hält ihn.
    FNotifier: TObject;
    FIndex: Integer;
    // Meldung ist eingereiht.
    FQueued: Boolean;
    FOnChanged: TProc;
    procedure Notified;
    procedure Deliver;
  public
    /// <summary>AOnChanged: Ziel der Karte neu bestimmen (im Hauptthread). Meldet den Beobachter an.</summary>
    constructor Create(const AOnChanged: TProc);
    /// <summary>Meldet den Beobachter ab; eine eingereihte Meldung erreicht danach nichts mehr.</summary>
    destructor Destroy; override;
  end;

implementation

uses
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Welcome.Search;

type
  TProjectNotifier = class(TNotifierObject, IOTAIDENotifier)
  private
    FOwner: TAtlasIdeSetupProjectEvents;
  public
    procedure FileNotification(NotifyCode: TOTAFileNotification; const FileName: string; var Cancel: Boolean);
    procedure BeforeCompile(const Project: IOTAProject; var Cancel: Boolean); overload;
    procedure AfterCompile(Succeeded: Boolean); overload;
  end;

var
  // Lebt der Beobachter noch? Für Arbeit, die über die Nachrichtenschleife kommt.
  Instance: TAtlasIdeSetupProjectEvents;

/// <summary>Kann das Ereignis das Ziel der Karte ändern?</summary>
function Concerns(ANotifyCode: TOTAFileNotification; const AFileName: string): Boolean;
begin
  Result := ANotifyCode = ofnActiveProjectChanged;
  if not Result and ((ANotifyCode = ofnFileOpened) or (ANotifyCode = ofnFileClosing)) then
  begin
    Result := TAtlasWelcomeSearch.IsProjectFile(AFileName);
  end;
end;

{ TProjectNotifier }

procedure TProjectNotifier.FileNotification(NotifyCode: TOTAFileNotification; const FileName: string;
  var Cancel: Boolean);
var
  mOwner: TAtlasIdeSetupProjectEvents;
begin
  mOwner := FOwner;
  if (mOwner = nil) or not Concerns(NotifyCode, FileName) then
  begin
    Exit;
  end;
  // Keine Exception an die IDE (#493).
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    begin
      mOwner.Notified;
    end);
end;

procedure TProjectNotifier.BeforeCompile(const Project: IOTAProject; var Cancel: Boolean);
begin
end;

procedure TProjectNotifier.AfterCompile(Succeeded: Boolean);
begin
end;

{ TAtlasIdeSetupProjectEvents }

constructor TAtlasIdeSetupProjectEvents.Create(const AOnChanged: TProc);
var
  mServices: IOTAServices;
  mNotifier: TProjectNotifier;
begin
  inherited Create;
  Instance := Self;
  FOnChanged := AOnChanged;
  FIndex := -1;
  if Supports(BorlandIDEServices, IOTAServices, mServices) then
  begin
    mNotifier := TProjectNotifier.Create;
    mNotifier.FOwner := Self;
    FNotifier := mNotifier;
    FIndex := mServices.AddNotifier(mNotifier);
  end;
end;

destructor TAtlasIdeSetupProjectEvents.Destroy;
var
  mServices: IOTAServices;
begin
  if Instance = Self then
  begin
    Instance := nil;
  end;
  if FNotifier <> nil then
  begin
    TProjectNotifier(FNotifier).FOwner := nil;
    // RemoveNotifier gibt die Referenz der IDE frei und damit den Beobachter (#493).
    if (FIndex >= 0) and Supports(BorlandIDEServices, IOTAServices, mServices) then
    begin
      mServices.RemoveNotifier(FIndex);
    end;
    FNotifier := nil;
    FIndex := -1;
  end;
  FOnChanged := nil;
  inherited;
end;

procedure TAtlasIdeSetupProjectEvents.Notified;
var
  mDeliver: TThreadProcedure;
begin
  if FQueued then
  begin
    Exit;
  end;
  FQueued := True;
  mDeliver :=
    procedure
    begin
      if Instance <> nil then
      begin
        Instance.Deliver;
      end;
    end;
  TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage, mDeliver);
end;

procedure TAtlasIdeSetupProjectEvents.Deliver;
begin
  FQueued := False;
  if Assigned(FOnChanged) then
  begin
    FOnChanged();
  end;
end;

end.
