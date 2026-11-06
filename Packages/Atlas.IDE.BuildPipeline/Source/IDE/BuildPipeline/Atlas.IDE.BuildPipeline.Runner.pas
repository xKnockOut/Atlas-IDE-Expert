unit Atlas.IDE.BuildPipeline.Runner;

// Baut ein offenes Projekt auf Auftrag über IOTAProjectBuilder (#261) und
// meldet Ergebnis und Compilermeldungen. Genutzt vom Eingang für Claude Code
// (Atlas.IDE.BuildPipeline.Inbox, MCP-Werkzeug build_project); gedacht auch für
// „Öffnen und bauen“ der Willkommensseite (#764).
// - Abgelehnt wird mit Grund, wenn der Debugger läuft, schon ein Build oder
//   die Compilerprüfung (#548) läuft, ein eigener Auftrag noch offen ist oder
//   das Projekt nicht offen ist.
// - Konfiguration und Plattform ('' = wie in der IDE) gelten nur für diesen
//   Build; danach stellt der Läufer die vorige Auswahl wieder her.
// - Während des Builds tragen die Compile-Ereignisse (#527) requestedBy
//   "mcp" bzw. den Auftraggeber; der Build zählt als Build des Benutzers
//   (kein Hintergrund), damit get_last_build ihn zeigt.
// - Der Compiler läuft modal im Hauptthread. Schlägt der Build fehl, wartet
//   der Fortschrittsdialog auf OK; nur während des eigenen Builds drückt der
//   Läufer dort OK (wie TAtlasIdeCheckOnSave, nie Abbrechen).
// - Die Meldungen liest der Leser des Meldungsfensters (#528) kurz nach dem
//   Ende; Base reicht sie über IAtlasCompilerMessagesListener (MessagesRead) weiter. Kommen
//   sie nicht binnen MessagesWaitMs, meldet der Läufer das Ergebnis ohne sie.
// - Bricht ein Teilnehmer der Compile-Ereignisse den eigenen Build ab (etwa
//   der Release-Build-Wächter mit build.gate = block, #533), endet der
//   Auftrag als „nicht gebaut“ mit dessen Grund (AError), nicht als
//   fehlgeschlagener Build.

interface

uses
  System.SysUtils,
  Vcl.ExtCtrls,
  ToolsAPI,
  PlatformAPI,
  Atlas.Core.Build.Events,
  Atlas.Core.Build.Messages,
  Atlas.Core.BuildPipeline.Inbox;

type
  // TAtlasBuildDoneProc steht in Atlas.Core.BuildPipeline.Inbox (ein Typ, sonst E2010 unter Delphi 12).
  TAtlasIdeBuildRunner = class
  public const
    MessagesWaitMs = 5000;
  private type
    TWatcher = class(TAtlasCompileParticipant)
    private
      FOwner: TAtlasIdeBuildRunner;
    public
      procedure GroupStarted(AKind: TAtlasCompileKind); override;
      procedure GroupFinished(ASucceeded: Boolean; ADurationMs: Int64); override;
      procedure ProjectFinished(const AProject: TAtlasCompileProject; ASucceeded: Boolean; ADurationMs: Int64);
        override;
      procedure CompileCancelled(const AProject: TAtlasCompileProject; const AReason: string); override;
    end;
  private
    FEvents: TAtlasCompileEvents;
    FWatcher: TWatcher;
    FTimer: TTimer;
    /// <summary>Ein Auftrag läuft (Build oder Warten auf die Meldungen).</summary>
    FBusy: Boolean;
    /// <summary>BuildProject läuft gerade.</summary>
    FBuilding: Boolean;
    /// <summary>Ein Build, den nicht dieser Läufer gestartet hat, läuft.</summary>
    FForeignBuild: Boolean;
    FRequest: TAtlasBuildRequest;
    FReport: TAtlasBuildReport;
    FProjectSeen: Boolean;
    FMessagesSeen: Boolean;
    /// <summary>Grund, aus dem ein Teilnehmer den eigenen Build abgebrochen hat; '' = keiner.</summary>
    FCancelReason: string;
    FWaitStarted: Int64;
    FOnDone: TAtlasBuildDoneProc;
    procedure Tick(Sender: TObject);
    procedure Finish;
    class function Debugging: Boolean; static;
    function StateRefusal(const ARequest: TAtlasBuildRequest): string;
    procedure BeginRequest(const ARequest: TAtlasBuildRequest; const AProject: IOTAProject;
      const AOnDone: TAtlasBuildDoneProc);
    function RunBuild(const ARequest: TAtlasBuildRequest; const AProject: IOTAProject;
      const AConfigurations: IOTAProjectOptionsConfigurations; const APlatforms: IOTAProjectPlatforms;
      const ARequestedBy: string): Boolean;
    procedure EndRequest(const AReason: string);
    procedure CompleteRequest(ASucceeded: Boolean; AStarted: Int64);
  public
    /// <summary>AEvents gehört dem Aufrufer und muss länger leben; der Wächter wird dort an- und in Destroy
    /// abgemeldet.</summary>
    constructor Create(AEvents: TAtlasCompileEvents);
    destructor Destroy; override;
    /// <summary>Hauptthread: baut ARequest.Project. False mit Grund in AReason, wenn nicht gebaut wird; sonst kommt
    /// das Ergebnis über AOnDone (auch bei einem Fehler unterwegs).</summary>
    function Start(const ARequest: TAtlasBuildRequest; const ARequestedBy: string; const AOnDone: TAtlasBuildDoneProc;
      out AReason: string): Boolean;
    /// <summary>Meldungen des Lesers (#528); gehören sie zum eigenen Build, gehen sie ins Ergebnis.</summary>
    procedure MessagesRead(const AMessages: TArray<TAtlasCompilerMessage>; const AProject: TAtlasCompileProject);
    property Busy: Boolean read FBusy;
  end;

implementation

uses
  Winapi.Windows,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.Hangs,
  Atlas.IDE.Build.CheckOnSave,
  Atlas.UI.BuildPipeline.Strings;

function NowMs: Int64;
begin
  Result := GetTickCount64;
end;

{ TAtlasIdeBuildRunner.TWatcher }

procedure TAtlasIdeBuildRunner.TWatcher.GroupStarted(AKind: TAtlasCompileKind);
begin
  if (FOwner <> nil) and not FOwner.FBuilding then
  begin
    FOwner.FForeignBuild := True;
  end;
end;

procedure TAtlasIdeBuildRunner.TWatcher.GroupFinished(ASucceeded: Boolean; ADurationMs: Int64);
begin
  if (FOwner <> nil) and not FOwner.FBuilding then
  begin
    FOwner.FForeignBuild := False;
  end;
end;

procedure TAtlasIdeBuildRunner.TWatcher.ProjectFinished(const AProject: TAtlasCompileProject; ASucceeded: Boolean;
  ADurationMs: Int64);
begin
  if (FOwner = nil) or not FOwner.FBuilding or not SameText(AProject.FileName, FOwner.FRequest.Project) then
  begin
    Exit;
  end;
  FOwner.FProjectSeen := True;
  FOwner.FReport.Project := AProject;
  FOwner.FReport.Succeeded := ASucceeded;
  FOwner.FReport.DurationMs := ADurationMs;
end;

procedure TAtlasIdeBuildRunner.TWatcher.CompileCancelled(const AProject: TAtlasCompileProject;
  const AReason: string);
begin
  // Auch der Abbruch eines abhängigen Projekts verhindert den eigenen Build; der erste Grund zählt.
  if (FOwner = nil) or not FOwner.FBuilding or (FOwner.FCancelReason <> '') then
  begin
    Exit;
  end;
  FOwner.FCancelReason := AReason;
  if FOwner.FCancelReason = '' then
  begin
    FOwner.FCancelReason := TAtlasBuildPipelineStrings.Text(TAtlasBuildPipelineTextId.McpRefusedCancelled);
  end;
end;

{ TAtlasIdeBuildRunner }

constructor TAtlasIdeBuildRunner.Create(AEvents: TAtlasCompileEvents);
begin
  inherited Create;
  FEvents := AEvents;
  FWatcher := TWatcher.Create;
  FWatcher.FOwner := Self;
  // Die Ereignisse halten den Wächter; Destroy meldet ihn ab und gibt ihn so frei (Regel 3, ADR 0017).
  FEvents.Add(FWatcher);
  FTimer := TTimer.Create(nil);
  FTimer.Interval := 250;
  FTimer.OnTimer := Tick;
  FTimer.Enabled := False;
end;

destructor TAtlasIdeBuildRunner.Destroy;
begin
  FTimer.Free;
  // Erst trennen, dann abmelden: Nach dem Entladen des Moduls darf kein Wächter mehr in den Ereignissen stehen.
  FWatcher.FOwner := nil;
  FEvents.Remove(FWatcher);
  FWatcher := nil;
  // Offener Auftrag: ohne Ergebnis abschließen, damit der Auftraggeber nicht wartet.
  if FBusy and Assigned(FOnDone) then
    try
      FOnDone(FReport, TAtlasBuildPipelineStrings.Text(TAtlasBuildPipelineTextId.McpRefusedShutdown));
    except
      on Exception do
        ;
    end;
  inherited;
end;

class function TAtlasIdeBuildRunner.Debugging: Boolean;
var
  Debugger: IOTADebuggerServices;
begin
  Result := Supports(BorlandIDEServices, IOTADebuggerServices, Debugger) and (Debugger.ProcessCount > 0);
end;

function ConfigurationKnown(const AConfigurations: IOTAProjectOptionsConfigurations; const AName: string): Boolean;
var
  Index: Integer;
begin
  Result := False;
  for Index := 0 to AConfigurations.ConfigurationCount - 1 do
  begin
    if SameText(AConfigurations.Configurations[Index].Name, AName) then
    begin
      Exit(True);
    end;
  end;
end;

/// <summary>Grund, aus dem der Läufer gerade nicht baut; '' = bereit.</summary>
function TAtlasIdeBuildRunner.StateRefusal(const ARequest: TAtlasBuildRequest): string;
begin
  Result := '';
  if FBusy then
  begin
    Result := TAtlasBuildPipelineStrings.Text(TAtlasBuildPipelineTextId.McpRefusedBusy);
  end
  else if FForeignBuild or FEvents.Background then
  begin
    Result := TAtlasBuildPipelineStrings.Text(TAtlasBuildPipelineTextId.McpRefusedForeignBuild);
  end
  else if Debugging then
  begin
    Result := TAtlasBuildPipelineStrings.Text(TAtlasBuildPipelineTextId.McpRefusedDebugging);
  end
  else if not (ARequest.Kind in [TAtlasCompileKind.Make, TAtlasCompileKind.Build, TAtlasCompileKind.Check]) then
  begin
    Result := TAtlasBuildPipelineStrings.Text(TAtlasBuildPipelineTextId.McpRefusedKind);
  end;
end;

/// <summary>Grund, aus dem ARequest nicht zum offenen Projekt passt; '' = passt. AConfigurations und APlatforms
/// sind nur gesetzt, wenn der Auftrag Konfiguration bzw. Plattform nennt.</summary>
function TargetRefusal(const ARequest: TAtlasBuildRequest; out AProject: IOTAProject;
  out AConfigurations: IOTAProjectOptionsConfigurations; out APlatforms: IOTAProjectPlatforms): string;
var
  Services: IOTAModuleServices;
begin
  Result := '';
  AConfigurations := nil;
  APlatforms := nil;
  if not Supports(BorlandIDEServices, IOTAModuleServices, Services) or
    not Supports(Services.FindModule(ARequest.Project), IOTAProject, AProject) or (AProject.ProjectBuilder = nil) then
  begin
    Result := TAtlasBuildPipelineStrings.Fmt(TAtlasBuildPipelineTextId.McpRefusedProjectClosed,
      [ExtractFileName(ARequest.Project)]);
  end
  else if (ARequest.Configuration <> '') and
    (not Supports(AProject.ProjectOptions, IOTAProjectOptionsConfigurations, AConfigurations) or
    not ConfigurationKnown(AConfigurations, ARequest.Configuration)) then
  begin
    Result := TAtlasBuildPipelineStrings.Fmt(TAtlasBuildPipelineTextId.McpRefusedConfiguration,
      [ARequest.Configuration]);
  end
  else if (ARequest.Platform <> '') and
    (not Supports(AProject, IOTAProjectPlatforms, APlatforms) or not APlatforms.Enabled[ARequest.Platform]) then
  begin
    Result := TAtlasBuildPipelineStrings.Fmt(TAtlasBuildPipelineTextId.McpRefusedPlatform, [ARequest.Platform]);
  end;
end;

procedure TAtlasIdeBuildRunner.BeginRequest(const ARequest: TAtlasBuildRequest; const AProject: IOTAProject;
  const AOnDone: TAtlasBuildDoneProc);
begin
  FRequest := ARequest;
  FRequest.Project := AProject.FileName;
  FOnDone := AOnDone;
  FReport := Default(TAtlasBuildReport);
  FReport.Project.FileName := AProject.FileName;
  FReport.Project.Kind := ARequest.Kind;
  FProjectSeen := False;
  FMessagesSeen := False;
  FCancelReason := '';
  FBusy := True;
  FBuilding := True;
  FTimer.Enabled := True;
end;

/// <summary>BuildProject mit der Konfiguration und Plattform des Auftrags; danach gilt wieder die Auswahl des
/// Benutzers.</summary>
function TAtlasIdeBuildRunner.RunBuild(const ARequest: TAtlasBuildRequest; const AProject: IOTAProject;
  const AConfigurations: IOTAProjectOptionsConfigurations; const APlatforms: IOTAProjectPlatforms;
  const ARequestedBy: string): Boolean;
const
  Modes: array[TAtlasCompileKind] of TOTACompileMode = (cmOTAMake, cmOTABuild, cmOTACheck, cmOTAMakeUnit,
    cmOTAClean, cmOTALink);
var
  OldConfiguration, OldPlatform: string;
begin
  OldConfiguration := AProject.CurrentConfiguration;
  OldPlatform := AProject.CurrentPlatform;
  try
    // Nur für diesen Build umschalten; der Benutzer findet danach seine Auswahl wieder. Über IOTAProject:
    // ActiveConfigurationName und CurrentPlatform der Hilfsschnittstellen sind nur lesbar.
    if (AConfigurations <> nil) and not SameText(OldConfiguration, ARequest.Configuration) then
    begin
      AProject.CurrentConfiguration := ARequest.Configuration;
    end;
    if (APlatforms <> nil) and not SameText(OldPlatform, ARequest.Platform) then
    begin
      AProject.CurrentPlatform := ARequest.Platform;
    end;
    FReport.Project.Configuration := AProject.CurrentConfiguration;
    FReport.Project.Platform := AProject.CurrentPlatform;
    FEvents.RequestedBy := ARequestedBy;
    try
      Result := AProject.ProjectBuilder.BuildProject(Modes[ARequest.Kind], False, True);
    finally
      FEvents.RequestedBy := '';
    end;
  finally
    FBuilding := False;
    if (AConfigurations <> nil) and not SameText(AProject.CurrentConfiguration, OldConfiguration) then
    begin
      AProject.CurrentConfiguration := OldConfiguration;
    end;
    if (APlatforms <> nil) and not SameText(AProject.CurrentPlatform, OldPlatform) then
    begin
      AProject.CurrentPlatform := OldPlatform;
    end;
  end;
end;

/// <summary>Auftrag ohne Warten auf Meldungen mit AReason abschließen.</summary>
procedure TAtlasIdeBuildRunner.EndRequest(const AReason: string);
begin
  FBusy := False;
  FTimer.Enabled := False;
  FOnDone(FReport, AReason);
  FOnDone := nil;
end;

/// <summary>Build fertig: auf die Meldungen warten oder, wenn sie schon da sind, abschließen.</summary>
procedure TAtlasIdeBuildRunner.CompleteRequest(ASucceeded: Boolean; AStarted: Int64);
begin
  if not FProjectSeen then
  begin
    // Ohne Ereignis des Compilers: Ergebnis von BuildProject und eigene Messung.
    FReport.Succeeded := ASucceeded;
    FReport.DurationMs := NowMs - AStarted;
  end;
  FReport.FinishedAt := Now;
  FWaitStarted := NowMs;
  if FMessagesSeen then
  begin
    Finish;
  end;
end;

function TAtlasIdeBuildRunner.Start(const ARequest: TAtlasBuildRequest; const ARequestedBy: string;
  const AOnDone: TAtlasBuildDoneProc; out AReason: string): Boolean;
var
  Project: IOTAProject;
  Configurations: IOTAProjectOptionsConfigurations;
  Platforms: IOTAProjectPlatforms;
  Started: Int64;
  Succeeded: Boolean;
  Activity: IInterface;
begin
  AReason := StateRefusal(ARequest);
  if AReason = '' then
  begin
    AReason := TargetRefusal(ARequest, Project, Configurations, Platforms);
  end;
  if AReason <> '' then
  begin
    Exit(False);
  end;
  BeginRequest(ARequest, Project, AOnDone);
  Activity := TAtlasActivity.Scope('Build für Claude Code');
  Started := NowMs;
  try
    Succeeded := RunBuild(ARequest, Project, Configurations, Platforms, ARequestedBy);
  except
    on E: Exception do
    begin
      TAtlasGuard.Report(TAtlasFeature.Build, E);
      EndRequest(TAtlasBuildPipelineStrings.Fmt(TAtlasBuildPipelineTextId.McpBuildException, [E.Message]));
      Exit(True);
    end;
  end;
  if FCancelReason <> '' then
  begin
    // Abgebrochen vor dem Compile (#533): nicht gebaut, mit Grund; keine Meldungen abwarten.
    EndRequest(FCancelReason);
  end
  else
  begin
    CompleteRequest(Succeeded, Started);
  end;
  Result := True;
end;

procedure TAtlasIdeBuildRunner.MessagesRead(const AMessages: TArray<TAtlasCompilerMessage>;
  const AProject: TAtlasCompileProject);
begin
  if not FBusy or FMessagesSeen or not SameText(AProject.FileName, FRequest.Project) then
  begin
    Exit;
  end;
  FMessagesSeen := True;
  FReport.Messages := AMessages;
  // Der Leser kann mitten im modalen Build kommen (Warteschlange); dann schließt Start ab.
  if not FBuilding then
  begin
    Finish;
  end;
end;

procedure TAtlasIdeBuildRunner.Tick(Sender: TObject);
begin
  try
    // Läuft auch in der modalen Schleife des Compilers weiter.
    if FBuilding then
    begin
      TAtlasIdeCheckOnSave.PressProgressOk;
      Exit;
    end;
    if FBusy and (NowMs - FWaitStarted >= MessagesWaitMs) then
    begin
      Finish;
    end;
  except
    // Keine Exception an die IDE (#493).
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Build, E);
  end;
end;

procedure TAtlasIdeBuildRunner.Finish;
var
  Done: TAtlasBuildDoneProc;
begin
  if not FBusy then
  begin
    Exit;
  end;
  FBusy := False;
  FTimer.Enabled := False;
  Done := FOnDone;
  FOnDone := nil;
  if Assigned(Done) then
  begin
    Done(FReport, '');
  end;
end;

end.
