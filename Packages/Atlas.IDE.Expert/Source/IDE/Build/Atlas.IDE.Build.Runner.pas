unit Atlas.IDE.Build.Runner;

// Baut ein offenes Projekt auf Auftrag über IOTAProjectBuilder (#261) und
// meldet Ergebnis und Compilermeldungen. Genutzt vom Eingang für Claude Code
// (Atlas.IDE.Build.Inbox, MCP-Werkzeug build_project); gedacht auch für
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
//   Ende; die Kompositionswurzel reicht sie über MessagesRead weiter. Kommen
//   sie nicht binnen MessagesWaitMs, meldet der Läufer das Ergebnis ohne sie.

interface

uses
  System.SysUtils,
  Vcl.ExtCtrls,
  Atlas.Core.Build.Events,
  Atlas.Core.Build.Messages,
  Atlas.Core.Build.Inbox;

type
  /// <summary>Ende eines Auftrags; AError <> '' = nicht gebaut (Grund), sonst Ergebnis in AReport.</summary>
  TAtlasBuildDoneProc = reference to procedure(const AReport: TAtlasBuildReport; const AError: string);

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
    FWaitStarted: Int64;
    FOnDone: TAtlasBuildDoneProc;
    procedure Tick(Sender: TObject);
    procedure Finish;
    class function Debugging: Boolean; static;
  public
    /// <summary>AEvents gehört dem Aufrufer und muss länger leben; der Wächter wird dort angemeldet.</summary>
    constructor Create(AEvents: TAtlasCompileEvents);
    destructor Destroy; override;
    /// <summary>Hauptthread: baut ARequest.Project. False mit Grund in AReason, wenn nicht gebaut wird; sonst kommt
    /// das Ergebnis über AOnDone (auch bei einem Fehler unterwegs).</summary>
    function Start(const ARequest: TAtlasBuildRequest; const ARequestedBy: string; const AOnDone: TAtlasBuildDoneProc;
      out AReason: string): Boolean;
    /// <summary>Meldungen des Lesers (#528); gehören sie zum eigenen Build, gehen sie ins Ergebnis.</summary>
    procedure MessagesRead(const AMessages: TArray<TAtlasCompilerMessage>; const AProject: TAtlasCompileProject;
      ASucceeded, AReadable: Boolean);
    property Busy: Boolean read FBusy;
  end;

implementation

uses
  Winapi.Windows,
  ToolsAPI,
  PlatformAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.Hangs,
  Atlas.IDE.Build.CheckOnSave;

function NowMs: Int64;
begin
  Result := GetTickCount64;
end;

{ TAtlasIdeBuildRunner.TWatcher }

procedure TAtlasIdeBuildRunner.TWatcher.GroupStarted(AKind: TAtlasCompileKind);
begin
  if (FOwner <> nil) and not FOwner.FBuilding then
    FOwner.FForeignBuild := True;
end;

procedure TAtlasIdeBuildRunner.TWatcher.GroupFinished(ASucceeded: Boolean; ADurationMs: Int64);
begin
  if (FOwner <> nil) and not FOwner.FBuilding then
    FOwner.FForeignBuild := False;
end;

procedure TAtlasIdeBuildRunner.TWatcher.ProjectFinished(const AProject: TAtlasCompileProject; ASucceeded: Boolean;
  ADurationMs: Int64);
begin
  if (FOwner = nil) or not FOwner.FBuilding or not SameText(AProject.FileName, FOwner.FRequest.Project) then
    Exit;
  FOwner.FProjectSeen := True;
  FOwner.FReport.Project := AProject;
  FOwner.FReport.Succeeded := ASucceeded;
  FOwner.FReport.DurationMs := ADurationMs;
end;

{ TAtlasIdeBuildRunner }

constructor TAtlasIdeBuildRunner.Create(AEvents: TAtlasCompileEvents);
begin
  inherited Create;
  FEvents := AEvents;
  FWatcher := TWatcher.Create;
  FWatcher.FOwner := Self;
  // Der Dienst übernimmt den Wächter; Destroy trennt ihn nur von uns.
  FEvents.Add(FWatcher);
  FTimer := TTimer.Create(nil);
  FTimer.Interval := 250;
  FTimer.OnTimer := Tick;
  FTimer.Enabled := False;
end;

destructor TAtlasIdeBuildRunner.Destroy;
begin
  FTimer.Free;
  FWatcher.FOwner := nil;
  // Offener Auftrag: ohne Ergebnis abschließen, damit der Auftraggeber nicht wartet.
  if FBusy and Assigned(FOnDone) then
    try
      FOnDone(FReport, 'Atlas wurde in der IDE beendet');
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
    if SameText(AConfigurations.Configurations[Index].Name, AName) then
      Exit(True);
end;

function TAtlasIdeBuildRunner.Start(const ARequest: TAtlasBuildRequest; const ARequestedBy: string;
  const AOnDone: TAtlasBuildDoneProc; out AReason: string): Boolean;
const
  Modes: array[TAtlasCompileKind] of TOTACompileMode = (cmOTAMake, cmOTABuild, cmOTACheck, cmOTAMakeUnit,
    cmOTAClean, cmOTALink);
var
  Services: IOTAModuleServices;
  Project: IOTAProject;
  Configurations: IOTAProjectOptionsConfigurations;
  Platforms: IOTAProjectPlatforms;
  OldConfiguration, OldPlatform: string;
  Started: Int64;
  Succeeded: Boolean;
  Activity: IInterface;
begin
  AReason := '';
  if FBusy then
    AReason := 'Atlas baut in der IDE schon ein Projekt'
  else if FForeignBuild or FEvents.Background then
    AReason := 'In der IDE läuft schon ein Build oder eine Compilerprüfung'
  else if Debugging then
    AReason := 'In der IDE läuft der Debugger'
  else if not (ARequest.Kind in [TAtlasCompileKind.Make, TAtlasCompileKind.Build, TAtlasCompileKind.Check]) then
    AReason := 'Nur make, build und check sind möglich'
  else if not Supports(BorlandIDEServices, IOTAModuleServices, Services) or
    not Supports(Services.FindModule(ARequest.Project), IOTAProject, Project) or (Project.ProjectBuilder = nil) then
    AReason := Format('Das Projekt %s ist in der IDE nicht offen', [ExtractFileName(ARequest.Project)]);
  Configurations := nil;
  Platforms := nil;
  if (AReason = '') and (ARequest.Configuration <> '') then
    if not Supports(Project.ProjectOptions, IOTAProjectOptionsConfigurations, Configurations) or
      not ConfigurationKnown(Configurations, ARequest.Configuration) then
      AReason := Format('Das Projekt kennt die Konfiguration %s nicht', [ARequest.Configuration]);
  if (AReason = '') and (ARequest.Platform <> '') then
    if not Supports(Project, IOTAProjectPlatforms, Platforms) or not Platforms.Enabled[ARequest.Platform] then
      AReason := Format('Die Plattform %s ist im Projekt nicht aktiviert', [ARequest.Platform]);
  if AReason <> '' then
    Exit(False);
  FRequest := ARequest;
  FRequest.Project := Project.FileName;
  FOnDone := AOnDone;
  FReport := Default(TAtlasBuildReport);
  FReport.Project.FileName := Project.FileName;
  FReport.Project.Kind := ARequest.Kind;
  FProjectSeen := False;
  FMessagesSeen := False;
  FBusy := True;
  FBuilding := True;
  FTimer.Enabled := True;
  Activity := TAtlasActivity.Scope('Build für Claude Code');
  OldConfiguration := Project.CurrentConfiguration;
  OldPlatform := Project.CurrentPlatform;
  Started := NowMs;
  try
    try
      // Nur für diesen Build umschalten; der Benutzer findet danach seine Auswahl wieder. Über IOTAProject:
      // ActiveConfigurationName und CurrentPlatform der Hilfsschnittstellen sind nur lesbar.
      if (Configurations <> nil) and not SameText(OldConfiguration, ARequest.Configuration) then
        Project.CurrentConfiguration := ARequest.Configuration;
      if (Platforms <> nil) and not SameText(OldPlatform, ARequest.Platform) then
        Project.CurrentPlatform := ARequest.Platform;
      FReport.Project.Configuration := Project.CurrentConfiguration;
      FReport.Project.Platform := Project.CurrentPlatform;
      FEvents.RequestedBy := ARequestedBy;
      try
        Succeeded := Project.ProjectBuilder.BuildProject(Modes[ARequest.Kind], False, True);
      finally
        FEvents.RequestedBy := '';
      end;
    finally
      FBuilding := False;
      if (Configurations <> nil) and not SameText(Project.CurrentConfiguration, OldConfiguration) then
        Project.CurrentConfiguration := OldConfiguration;
      if (Platforms <> nil) and not SameText(Project.CurrentPlatform, OldPlatform) then
        Project.CurrentPlatform := OldPlatform;
    end;
  except
    on E: Exception do
    begin
      TAtlasGuard.Report(TAtlasFeature.Build, E);
      FBusy := False;
      FTimer.Enabled := False;
      FOnDone(FReport, Format('Build in der IDE fehlgeschlagen: %s', [E.Message]));
      FOnDone := nil;
      Exit(True);
    end;
  end;
  if not FProjectSeen then
  begin
    // Ohne Ereignis des Compilers: Ergebnis von BuildProject und eigene Messung.
    FReport.Succeeded := Succeeded;
    FReport.DurationMs := NowMs - Started;
  end;
  FReport.FinishedAt := Now;
  FWaitStarted := NowMs;
  if FMessagesSeen then
    Finish;
  Result := True;
end;

procedure TAtlasIdeBuildRunner.MessagesRead(const AMessages: TArray<TAtlasCompilerMessage>;
  const AProject: TAtlasCompileProject; ASucceeded, AReadable: Boolean);
begin
  if not FBusy or FMessagesSeen or not SameText(AProject.FileName, FRequest.Project) then
    Exit;
  FMessagesSeen := True;
  FReport.Messages := AMessages;
  // Der Leser kann mitten im modalen Build kommen (Warteschlange); dann schließt Start ab.
  if not FBuilding then
    Finish;
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
      Finish;
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
    Exit;
  FBusy := False;
  FTimer.Enabled := False;
  Done := FOnDone;
  FOnDone := nil;
  if Assigned(Done) then
    Done(FReport, '');
end;

end.
