unit Atlas.IDE.Build.Target;

// Build-Konfiguration, Zielplattform und Defines des aktiven Projekts an den
// Server (#615). Der Problem-Controller ruft Tick etwa einmal je Sekunde im
// Hauptthread auf; gelesen wird über die Open Tools API (CurrentConfiguration,
// CurrentPlatform, DCC_Define der aktiven Konfiguration samt geerbter Werte,
// also auch ungespeicherte Projektoptionen). Was zu tun ist, entscheidet
// TAtlasBuildTargetTracker; die Anfrage atlas.server.selectBuild läuft in
// einem eigenen Thread, die Antwort kommt über TThread.Queue zurück. Der Server
// lädt danach das Projekt neu und bittet um neues Holen der Diagnosen; so
// stimmen die abgeblendeten {$IFDEF}-Zweige wieder.

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.Generics.Collections,
  ToolsAPI,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Build.Target;

type
  TAtlasIdeBuildTargetLog = reference to procedure(const AMessage: string);

  TAtlasIdeBuildTarget = class
  public const
    SelectBuildCommand = 'atlas.server.selectBuild';
    IntervalMs = 1000;
    /// <summary>Kennt der Server das Projekt (noch) nicht, erst so viel später wieder fragen.</summary>
    RetryMs = 10000;
    RequestTimeoutMs = 10000;
  private type
    TDone = reference to procedure(AResult: TJSONValue);

    TRequest = class(TThread)
    private
      FSession: TLspSession;
      FArguments: TJSONArray;
      FDone: TDone;
    protected
      procedure Execute; override;
    public
      constructor Create(ASession: TLspSession; AArguments: TJSONArray; const ADone: TDone);
      destructor Destroy; override;
    end;
  private
    FTracker: TAtlasBuildTargetTracker;
    FLog: TAtlasIdeBuildTargetLog;
    FSession: TLspSession;
    FCheckedAt: Cardinal;
    // Zeitpunkt der Antwort ohne Projekt; FRetryPending bis RetryMs danach.
    FRetryFrom: Cardinal;
    FRetryPending: Boolean;
    // Laufende bzw. angehaltene Anfragen; frei, sobald fertig.
    FRequests: TObjectList<TThread>;
    // Zählt Sitzungen: Antworten einer alten Sitzung verwerfen.
    FGeneration: Integer;
    procedure Send(ASession: TLspSession; const ATarget: TAtlasBuildTarget; AAction: TAtlasBuildTargetAction);
    procedure FreeFinished;
  public
    constructor Create(const ALog: TAtlasIdeBuildTargetLog);
    destructor Destroy; override;
    /// <summary>Stand des aktiven Projekts der IDE; False ohne Projekt.</summary>
    class function Read(out ATarget: TAtlasBuildTarget): Boolean; static;
    /// <summary>Hauptthread: höchstens alle IntervalMs prüfen und bei Bedarf an ASession senden.</summary>
    procedure Tick(ASession: TLspSession; ANow: Cardinal);
    /// <summary>Anfragen anhalten; mit AWait auf sie warten (vor dem Ende der Sitzung).</summary>
    procedure Stop(AWait: Boolean);
  end;

implementation

uses
  Winapi.Windows;

{ TAtlasIdeBuildTarget.TRequest }

constructor TAtlasIdeBuildTarget.TRequest.Create(ASession: TLspSession; AArguments: TJSONArray;
  const ADone: TDone);
begin
  FSession := ASession;
  FArguments := AArguments;
  FDone := ADone;
  inherited Create(False);
end;

destructor TAtlasIdeBuildTarget.TRequest.Destroy;
begin
  inherited Destroy;
  // Nicht gesendet (Thread nie gelaufen): Argumente selbst freigeben.
  FArguments.Free;
end;

procedure TAtlasIdeBuildTarget.TRequest.Execute;
var
  Arguments: TJSONArray;
  Answer: TJSONValue;
begin
  Arguments := FArguments;
  // ExecuteCommand übernimmt die Argumente.
  FArguments := nil;
  Answer := FSession.ExecuteCommand(SelectBuildCommand, Arguments, RequestTimeoutMs);
  if Terminated then
  begin
    Answer.Free;
    Exit;
  end;
  Queue(
    procedure
    begin
      try
        FDone(Answer);
      finally
        Answer.Free;
      end;
    end);
end;

{ TAtlasIdeBuildTarget }

constructor TAtlasIdeBuildTarget.Create(const ALog: TAtlasIdeBuildTargetLog);
begin
  inherited Create;
  FLog := ALog;
  FTracker := TAtlasBuildTargetTracker.Create;
  FRequests := TObjectList<TThread>.Create(True);
end;

destructor TAtlasIdeBuildTarget.Destroy;
begin
  Stop(True);
  FRequests.Free;
  FTracker.Free;
  inherited Destroy;
end;

class function TAtlasIdeBuildTarget.Read(out ATarget: TAtlasBuildTarget): Boolean;
var
  Modules: IOTAModuleServices;
  Project: IOTAProject;
  Configurations: IOTAProjectOptionsConfigurations;
  Config, Platform: IOTABuildConfiguration;
begin
  ATarget := Default(TAtlasBuildTarget);
  Result := False;
  if not Supports(BorlandIDEServices, IOTAModuleServices, Modules) then
    Exit;
  Project := Modules.GetActiveProject;
  if (Project = nil) or not SameText(ExtractFileExt(Project.FileName), '.dproj') then
    Exit;
  ATarget.Project := Project.FileName;
  ATarget.Config := Project.CurrentConfiguration;
  ATarget.Platform := Project.CurrentPlatform;
  if Supports(Project.ProjectOptions, IOTAProjectOptionsConfigurations, Configurations) then
  begin
    Config := Configurations.ActiveConfiguration;
    if Config <> nil then
    begin
      // Werte der Plattform enthalten die der Konfiguration (geerbt).
      Platform := Config.PlatformConfiguration[ATarget.Platform];
      if Platform <> nil then
        Config := Platform;
      ATarget.Defines := TAtlasBuildTarget.ParseDefines(Config.GetValue('DCC_Define', True));
    end;
  end;
  Result := True;
end;

procedure TAtlasIdeBuildTarget.FreeFinished;
var
  Index: Integer;
begin
  for Index := FRequests.Count - 1 downto 0 do
    if FRequests[Index].Finished then
    begin
      TThread.RemoveQueuedEvents(FRequests[Index]);
      FRequests.Delete(Index);
    end;
end;

procedure TAtlasIdeBuildTarget.Tick(ASession: TLspSession; ANow: Cardinal);
var
  Target: TAtlasBuildTarget;
  Action: TAtlasBuildTargetAction;
begin
  FreeFinished;
  if ASession <> FSession then
  begin
    // Neuer Server: beginnt mit der Auswahl der Datei, also neu abgleichen.
    Stop(False);
    FSession := ASession;
  end;
  if (ASession = nil) or (ANow - FCheckedAt < IntervalMs) then
    Exit;
  FCheckedAt := ANow;
  if FRetryPending and (ANow - FRetryFrom < RetryMs) then
    Exit;
  FRetryPending := False;
  if not Read(Target) then
    Exit;
  Action := FTracker.Decide(Target);
  if Action <> TAtlasBuildTargetAction.None then
    Send(ASession, Target, Action);
end;

procedure TAtlasIdeBuildTarget.Send(ASession: TLspSession; const ATarget: TAtlasBuildTarget;
  AAction: TAtlasBuildTargetAction);
var
  Generation: Integer;
begin
  Generation := FGeneration;
  if AAction = TAtlasBuildTargetAction.Select then
    FLog(Format('Build-Auswahl an den Server: %s, %s, %d Symbole',
      [ATarget.Config, ATarget.Platform, Length(ATarget.Defines)]));
  FRequests.Add(TRequest.Create(ASession, ATarget.SelectArguments(TLspSession.PathToUri(ATarget.Project), AAction),
    procedure(AResult: TJSONValue)
    var
      Config, Platform: string;
    begin
      if Generation <> FGeneration then
        Exit;
      FTracker.Finished;
      if AResult = nil then
        FLog('Build-Auswahl: keine Antwort des Servers');
      if AAction <> TAtlasBuildTargetAction.Query then
        Exit;
      if TAtlasBuildTarget.FromSelection(AResult, ATarget.Project, Config, Platform) then
        FTracker.Baseline(ATarget.Project, Config, Platform, ATarget.Defines, True)
      else
      begin
        // Projekt noch nicht geladen oder nicht im Arbeitsbereich: später noch einmal fragen.
        FRetryPending := True;
        FRetryFrom := GetTickCount;
      end;
    end));
end;

procedure TAtlasIdeBuildTarget.Stop(AWait: Boolean);
var
  Request: TThread;
begin
  Inc(FGeneration);
  FTracker.Reset;
  for Request in FRequests do
    Request.Terminate;
  if not AWait then
    Exit;
  for Request in FRequests do
  begin
    Request.WaitFor;
    TThread.RemoveQueuedEvents(Request);
  end;
  FRequests.Clear;
end;

end.
