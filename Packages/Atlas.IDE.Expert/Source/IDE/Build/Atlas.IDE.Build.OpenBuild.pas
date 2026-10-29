unit Atlas.IDE.Build.OpenBuild;

// Beim Öffnen eines Projekts oder einer Projektgruppe einmal bauen
// (build.onOpen). Ein IDE-Notifier meldet geöffnete und geschlossene
// Projektdateien an TAtlasOpenBuild; ein Timer startet den Lauf, sobald die
// IDE ruhig ist (keine Eingabe seit build.onOpenDelayMs, kein Build, kein
// Debugger, keine Compilerprüfung #548 und kein Auftrag des Läufers #261).
// - Projektgruppe: alle Projekte in der Reihenfolge der Gruppe oder nur das
//   aktive (build.onOpenScope). Projekte der Gruppe, die beim Laden einzeln
//   gemeldet werden, entscheidet die Gruppe mit.
// - Gebaut wird in einem Lauf über IOTACompileServices.CompileProjects (wie
//   „Alle erzeugen“). Ist in der IDE die Hintergrundcompilierung an, kommt der
//   Aufruf sofort zurück (crOTABackground) und die IDE bleibt bedienbar; das
//   Ende melden dann die Compile-Ereignisse (#527). Sonst läuft der Compiler
//   modal mit dem Fortschrittsdialog der IDE; schlägt der Lauf fehl, drückt
//   Atlas dort OK (nur im eigenen Lauf, nie Abbrechen, wie #548).
// - Die Compile-Ereignisse tragen requestedBy "open": kein Build des
//   Benutzers, also keine Tests nach dem Build (#69). Der Release-Wächter
//   (#533) prüft wie bei jedem Build und kann abbrechen; das Projekt zählt
//   dann als „nicht gebaut“.
// - Ergebnis je Projekt meldet die Benachrichtigungszentrale wie jeden Build
//   (#535, #601); bei mehr als einem Projekt oder einem Abbruch kommt eine
//   Zusammenfassung dazu (Quelle openBuild).
// - Konfiguration und Zielplattform (#1293, build.onOpenConfig,
//   build.onOpenPlatform): Vor dem Lauf schaltet Atlas jedes Projekt auf die
//   Vorgabe um, egal was im Projekt eingestellt ist, und stellt am Ende des
//   Laufs (auch im Hintergrund erst dann) die Auswahl des Benutzers wieder
//   her, wie der Läufer für Claude Code. Kennt ein Projekt die
//   Konfiguration nicht oder ist die Plattform dort nicht aktiviert, gilt
//   für diesen Teil die Einstellung des Projekts; die Zusammenfassung nennt
//   das.
// - Beim ersten Start in der IDE-Sitzung gilt eine schon geladene
//   Projektgruppe als eben geöffnet (die IDE lädt das letzte Projekt oft vor
//   dem Plugin); späteres Einschalten baut erst beim nächsten Öffnen.

interface

uses
  System.SysUtils,
  Vcl.ExtCtrls,
  PlatformAPI,
  ToolsAPI,
  Atlas.Core.Build.Events,
  Atlas.Core.Build.OpenBuild;

type
  TAtlasIdeOpenBuild = class
  private type
    TIdeNotifier = class(TNotifierObject, IOTAIDENotifier)
    private
      FOwner: TAtlasIdeOpenBuild;
    public
      procedure FileNotification(NotifyCode: TOTAFileNotification; const FileName: string; var Cancel: Boolean);
      procedure BeforeCompile(const Project: IOTAProject; var Cancel: Boolean); overload;
      procedure AfterCompile(Succeeded: Boolean); overload;
    end;

    /// <summary>Auswahl eines Projekts vor dem Umschalten auf die Vorgaben (#1293).</summary>
    TSwitch = record
      Project: IOTAProject;
      Configuration: string;
      Platform: string;
    end;

    TWatcher = class(TAtlasCompileParticipant)
    private
      FOwner: TAtlasIdeOpenBuild;
    public
      procedure GroupStarted(AKind: TAtlasCompileKind); override;
      procedure GroupFinished(ASucceeded: Boolean; ADurationMs: Int64); override;
      procedure ProjectStarted(const AProject: TAtlasCompileProject); override;
      procedure ProjectFinished(const AProject: TAtlasCompileProject; ASucceeded: Boolean; ADurationMs: Int64);
        override;
      procedure CompileCancelled(const AProject: TAtlasCompileProject; const AReason: string); override;
    end;
  private class var
    FStartedOnce: Boolean;
  private
    FCore: TAtlasOpenBuild;
    FEvents: TAtlasCompileEvents;
    FWatcher: TWatcher;
    FNotifier: TIdeNotifier;
    FNotifierRef: IOTAIDENotifier;
    FNotifierIndex: Integer;
    FTimer: TTimer;
    FReport: TProc<string>;
    /// <summary>CompileProjects läuft gerade (modal oder bis zur Rückkehr im Hintergrund).</summary>
    FCompiling: Boolean;
    /// <summary>Der eigene Lauf geht im Hintergrund der IDE weiter (crOTABackground).</summary>
    FWaiting: Boolean;
    /// <summary>Ein Gruppenlauf des Benutzers läuft.</summary>
    FUserGroup: Boolean;
    FKind: TAtlasCompileKind;
    FStartedAt: Int64;
    /// <summary>Umgeschaltete Projekte des Laufs; Finish stellt sie zurück (#1293).</summary>
    FSwitched: TArray<TSwitch>;
    /// <summary>Projekte, die eine Vorgabe nicht kennen, für die Zusammenfassung.</summary>
    FTargetNotes: TArray<string>;
    procedure Tick(Sender: TObject);
    procedure ApplyTargets(const AProjects: TArray<IOTAProject>);
    procedure RestoreTargets;
    procedure Run;
    procedure Compile(const AProjects: TArray<IOTAProject>; const AFiles: TArray<string>);
    procedure Finish;
    procedure Opened(const AFileName: string);
    procedure Closing(const AFileName: string);
    /// <summary>Projekte einer Gruppe; False, solange die Gruppe nicht geladen ist. AMembers bekommt alle
    /// Projekte der Gruppe (auch bei Umfang „aktiv“).</summary>
    class function ResolveGroup(const AFileName: string; AScope: TAtlasOpenBuildScope;
      out AProjects, AMembers: TArray<string>): Boolean; static;
    /// <summary>Projekt zu einer .dproj/.dpr/.dpk; nil, solange es nicht geladen ist.</summary>
    class function FindProject(const AFileName: string): IOTAProject; static;
    class function Debugging: Boolean; static;
    class function IdleMs: Int64; static;
    class function NowMs: Int64; static;
  public
    /// <summary>AEvents gehört dem Aufrufer und muss länger leben; der Wächter wird dort angemeldet.</summary>
    constructor Create(AEvents: TAtlasCompileEvents; const AReport: TProc<string>);
    destructor Destroy; override;
  end;

implementation

uses
  Winapi.Windows,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.Hangs,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Notifications.Contract,
  Atlas.Core.Notifications.Center,
  Atlas.Core.Notifications.Sources,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Build.CheckOnSave,
  Atlas.UI.Strings;

{ TAtlasIdeOpenBuild.TIdeNotifier }

procedure TAtlasIdeOpenBuild.TIdeNotifier.FileNotification(NotifyCode: TOTAFileNotification;
  const FileName: string; var Cancel: Boolean);
var
  Owner: TAtlasIdeOpenBuild;
  Name: string;
begin
  Owner := FOwner;
  if (Owner = nil) or not ((NotifyCode = ofnFileOpened) or (NotifyCode = ofnFileClosing)) or
    not TAtlasOpenBuild.IsProjectFile(FileName) then
    Exit;
  Name := FileName;
  // Keine Exception an die IDE (#493).
  if NotifyCode = ofnFileOpened then
    TAtlasGuard.Run(TAtlasFeature.Build,
      procedure
      begin
        Owner.Opened(Name);
      end)
  else
    TAtlasGuard.Run(TAtlasFeature.Build,
      procedure
      begin
        Owner.Closing(Name);
      end);
end;

procedure TAtlasIdeOpenBuild.TIdeNotifier.BeforeCompile(const Project: IOTAProject; var Cancel: Boolean);
begin
end;

procedure TAtlasIdeOpenBuild.TIdeNotifier.AfterCompile(Succeeded: Boolean);
begin
end;

{ TAtlasIdeOpenBuild.TWatcher }

procedure TAtlasIdeOpenBuild.TWatcher.GroupStarted(AKind: TAtlasCompileKind);
begin
  if (FOwner = nil) or FOwner.FCore.Running then
    Exit;
  FOwner.FUserGroup := True;
  FOwner.FCore.BuildStarted;
end;

procedure TAtlasIdeOpenBuild.TWatcher.GroupFinished(ASucceeded: Boolean; ADurationMs: Int64);
begin
  if FOwner = nil then
    Exit;
  if FOwner.FCore.Running then
  begin
    // Im Hintergrund weitergelaufen: hier endet der eigene Lauf; modal schließt Compile nach der Rückkehr ab.
    if FOwner.FWaiting and not FOwner.FCompiling then
      FOwner.Finish;
    Exit;
  end;
  FOwner.FUserGroup := False;
  FOwner.FCore.BuildFinished;
end;

procedure TAtlasIdeOpenBuild.TWatcher.ProjectStarted(const AProject: TAtlasCompileProject);
begin
  if (FOwner = nil) or AProject.Background or SameText(AProject.RequestedBy, TAtlasOpenBuild.RequestedBy) then
    Exit;
  FOwner.FCore.BuildStarted;
end;

procedure TAtlasIdeOpenBuild.TWatcher.ProjectFinished(const AProject: TAtlasCompileProject; ASucceeded: Boolean;
  ADurationMs: Int64);
begin
  if FOwner = nil then
    Exit;
  if SameText(AProject.RequestedBy, TAtlasOpenBuild.RequestedBy) then
  begin
    FOwner.FCore.ProjectFinished(AProject.FileName, ASucceeded);
    Exit;
  end;
  // In einem Gruppenlauf des Benutzers endet der Build erst mit der Gruppe.
  if not AProject.Background and not FOwner.FUserGroup then
    FOwner.FCore.BuildFinished;
end;

procedure TAtlasIdeOpenBuild.TWatcher.CompileCancelled(const AProject: TAtlasCompileProject; const AReason: string);
begin
  if (FOwner <> nil) and SameText(AProject.RequestedBy, TAtlasOpenBuild.RequestedBy) then
    FOwner.FCore.ProjectCancelled(AProject.FileName, AReason);
end;

{ TAtlasIdeOpenBuild }

constructor TAtlasIdeOpenBuild.Create(AEvents: TAtlasCompileEvents; const AReport: TProc<string>);
var
  Services: IOTAServices;
  Modules: IOTAModuleServices;
  Group: IOTAProjectGroup;
begin
  inherited Create;
  FEvents := AEvents;
  FReport := AReport;
  FCore := TAtlasOpenBuild.Create;
  FWatcher := TWatcher.Create;
  FWatcher.FOwner := Self;
  // Der Dienst übernimmt den Wächter; Destroy trennt ihn nur von uns.
  FEvents.Add(FWatcher);
  FNotifierIndex := -1;
  if Supports(BorlandIDEServices, IOTAServices, Services) then
  begin
    FNotifier := TIdeNotifier.Create;
    FNotifier.FOwner := Self;
    FNotifierRef := FNotifier;
    FNotifierIndex := Services.AddNotifier(FNotifierRef);
  end;
  // Erster Start in dieser IDE-Sitzung: Eine schon geladene Gruppe gilt als eben geöffnet.
  if not FStartedOnce then
  begin
    FStartedOnce := True;
    if Supports(BorlandIDEServices, IOTAModuleServices, Modules) then
    begin
      Group := Modules.MainProjectGroup;
      if (Group <> nil) and (Group.ProjectCount > 0) then
        FCore.Opened(Group.FileName, NowMs);
    end;
  end;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := 250;
  FTimer.OnTimer := Tick;
  FTimer.Enabled := True;
end;

destructor TAtlasIdeOpenBuild.Destroy;
var
  Services: IOTAServices;
begin
  if FTimer <> nil then
  begin
    FTimer.Enabled := False;
    FTimer.Free;
  end;
  // Erst abmelden, dann freigeben (#493).
  if FNotifier <> nil then
    FNotifier.FOwner := nil;
  if (FNotifierIndex >= 0) and Supports(BorlandIDEServices, IOTAServices, Services) then
    Services.RemoveNotifier(FNotifierIndex);
  FNotifierRef := nil;
  FWatcher.FOwner := nil;
  RestoreTargets;
  if FCore.Running and SameText(FEvents.RequestedBy, TAtlasOpenBuild.RequestedBy) then
    FEvents.RequestedBy := '';
  FCore.Free;
  inherited;
end;

class function TAtlasIdeOpenBuild.NowMs: Int64;
begin
  Result := GetTickCount64;
end;

class function TAtlasIdeOpenBuild.IdleMs: Int64;
var
  Info: TLastInputInfo;
  Ticks: Cardinal;
begin
  // Zeit seit der letzten Eingabe in Windows; ohne Angabe gilt die IDE als ruhig.
  Info.cbSize := SizeOf(Info);
  if not GetLastInputInfo(Info) then
    Exit(High(Integer));
  Ticks := GetTickCount;
  if Ticks >= Info.dwTime then
    Result := Ticks - Info.dwTime
  else
    Result := 0;
end;

class function TAtlasIdeOpenBuild.Debugging: Boolean;
var
  Debugger: IOTADebuggerServices;
begin
  Result := Supports(BorlandIDEServices, IOTADebuggerServices, Debugger) and (Debugger.ProcessCount > 0);
end;

procedure TAtlasIdeOpenBuild.Opened(const AFileName: string);
begin
  if TAtlasIdeSettings.Current.BuildOnOpen then
    FCore.Opened(AFileName, NowMs);
end;

procedure TAtlasIdeOpenBuild.Closing(const AFileName: string);
var
  Modules: IOTAModuleServices;
  Group: IOTAProjectGroup;
  Index: Integer;
begin
  // Eine Gruppe gibt beim Schließen auch ihre Projekte frei (falls die IDE sie nicht einzeln meldet).
  if TAtlasOpenBuild.IsGroupFile(AFileName) and Supports(BorlandIDEServices, IOTAModuleServices, Modules) then
  begin
    Group := Modules.MainProjectGroup;
    if (Group <> nil) and SameText(Group.FileName, AFileName) then
      for Index := 0 to Group.ProjectCount - 1 do
        FCore.Closed(Group.Projects[Index].FileName);
  end;
  FCore.Closed(AFileName);
end;

class function TAtlasIdeOpenBuild.ResolveGroup(const AFileName: string; AScope: TAtlasOpenBuildScope;
  out AProjects, AMembers: TArray<string>): Boolean;
var
  Modules: IOTAModuleServices;
  Group: IOTAProjectGroup;
  Index: Integer;
begin
  AProjects := nil;
  AMembers := nil;
  Result := False;
  if not Supports(BorlandIDEServices, IOTAModuleServices, Modules) then
    Exit;
  Group := Modules.MainProjectGroup;
  if (Group = nil) or not SameText(Group.FileName, AFileName) or (Group.ProjectCount = 0) then
    Exit;
  for Index := 0 to Group.ProjectCount - 1 do
    AMembers := AMembers + [Group.Projects[Index].FileName];
  if AScope = TAtlasOpenBuildScope.Active then
  begin
    if Group.ActiveProject <> nil then
      AProjects := [Group.ActiveProject.FileName];
  end
  else
    AProjects := AMembers;
  Result := True;
end;

class function TAtlasIdeOpenBuild.FindProject(const AFileName: string): IOTAProject;
var
  Modules: IOTAModuleServices;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, IOTAModuleServices, Modules) then
    Exit;
  // Die IDE kennt das Projekt meist unter der .dproj, die .dpr/.dpk nur als Quelltext.
  if not Supports(Modules.FindModule(AFileName), IOTAProject, Result) then
    if not Supports(Modules.FindModule(ChangeFileExt(AFileName, '.dproj')), IOTAProject, Result) then
      Result := nil;
end;

procedure TAtlasIdeOpenBuild.Tick(Sender: TObject);
var
  Settings: TAtlasPluginSettings;
begin
  try
    // Läuft auch in der modalen Schleife des Compilers weiter.
    if FCompiling then
    begin
      if not FWaiting then
        TAtlasIdeCheckOnSave.PressProgressOk;
      Exit;
    end;
    if FWaiting then
    begin
      // Im Hintergrund: Ende über die Compile-Ereignisse; ohne Gruppenende spätestens nach MaxRunMs.
      if FCore.RunComplete or FCore.RunOverdue(NowMs) then
        Finish;
      Exit;
    end;
    Settings := TAtlasIdeSettings.Current;
    if not Settings.BuildOnOpen then
      Exit;
    // Compilerprüfung (#548) oder ein Auftrag des Läufers (#261, #69) läuft gerade.
    if FEvents.Background or (FEvents.RequestedBy <> '') then
      Exit;
    if FCore.Due(NowMs, Settings.BuildOnOpenDelayMs, IdleMs, Debugging) then
      Run;
  except
    // Keine Exception an die IDE (#493).
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Build, E);
  end;
end;

procedure TAtlasIdeOpenBuild.Run;
var
  Settings: TAtlasPluginSettings;
  Scope: TAtlasOpenBuildScope;
  Files, Resolved, Members, Candidates, Selected, Built: TArray<string>;
  Covered: TArray<string>;
  FileName, Member: string;
  Project: IOTAProject;
  Projects: TArray<IOTAProject>;
  Skip: Boolean;
begin
  Settings := TAtlasIdeSettings.Current;
  Scope := TAtlasOpenBuild.ScopeOf(Settings.BuildOnOpenScope);
  Files := FCore.Take;
  Candidates := nil;
  Covered := nil;
  // Zuerst die Gruppen: Sie entscheiden auch über ihre einzeln gemeldeten Projekte.
  for FileName in Files do
    if TAtlasOpenBuild.IsGroupFile(FileName) then
    begin
      if ResolveGroup(FileName, Scope, Resolved, Members) then
      begin
        Candidates := Candidates + Resolved;
        Covered := Covered + Members;
      end
      else
        FCore.Retry(FileName, NowMs);
    end;
  for FileName in Files do
  begin
    if TAtlasOpenBuild.IsGroupFile(FileName) then
      Continue;
    Skip := False;
    for Member in Covered do
      if TAtlasOpenBuild.KeyOf(Member) = TAtlasOpenBuild.KeyOf(FileName) then
        Skip := True;
    if Skip then
      Continue;
    Project := FindProject(FileName);
    if Project <> nil then
      Candidates := Candidates + [Project.FileName]
    else
      FCore.Retry(FileName, NowMs);
  end;
  Selected := FCore.Select(Candidates, TAtlasOpenBuild.ParseExclude(Settings.BuildOnOpenExclude));
  Projects := nil;
  Built := nil;
  for FileName in Selected do
  begin
    Project := FindProject(FileName);
    if (Project <> nil) and (Project.ProjectBuilder <> nil) then
    begin
      Projects := Projects + [Project];
      Built := Built + [Project.FileName];
    end;
  end;
  if Length(Projects) = 0 then
    Exit;
  FKind := TAtlasOpenBuild.KindOf(Settings.BuildOnOpenKind);
  Compile(Projects, Built);
end;

procedure TAtlasIdeOpenBuild.ApplyTargets(const AProjects: TArray<IOTAProject>);
var
  Settings: TAtlasPluginSettings;
  Project: IOTAProject;
  Configurations: IOTAProjectOptionsConfigurations;
  Platforms: IOTAProjectPlatforms;
  Names: TArray<string>;
  Index: Integer;
  Configuration, Platform: string;
  Switch: TSwitch;
begin
  FSwitched := nil;
  FTargetNotes := nil;
  Settings := TAtlasIdeSettings.Current;
  if (Settings.BuildOnOpenConfig = '') and (Settings.BuildOnOpenPlatform = '') then
    Exit;
  for Project in AProjects do
  begin
    Switch.Project := Project;
    Switch.Configuration := Project.CurrentConfiguration;
    Switch.Platform := Project.CurrentPlatform;
    Configuration := '';
    if Settings.BuildOnOpenConfig <> '' then
    begin
      Names := nil;
      if Supports(Project.ProjectOptions, IOTAProjectOptionsConfigurations, Configurations) then
        for Index := 0 to Configurations.ConfigurationCount - 1 do
          Names := Names + [Configurations.Configurations[Index].Name];
      Configuration := TAtlasOpenBuild.PickTarget(Settings.BuildOnOpenConfig, Names);
      if Configuration = '' then
        FTargetNotes := FTargetNotes + [TAtlasStrings.Fmt(TAtlasTextId.OpenBuildTargetMissing,
          [TAtlasOpenBuild.NameOf(Project.FileName), Settings.BuildOnOpenConfig])];
    end;
    Platform := '';
    if Settings.BuildOnOpenPlatform <> '' then
    begin
      // Nur aktivierte Plattformen, in der Schreibweise des Projekts (auch „Win 64“ trifft Win64).
      if Supports(Project, IOTAProjectPlatforms, Platforms) then
        Platform := TAtlasOpenBuild.PickTarget(Settings.BuildOnOpenPlatform, Platforms.EnabledPlatforms);
      if Platform = '' then
        FTargetNotes := FTargetNotes + [TAtlasStrings.Fmt(TAtlasTextId.OpenBuildTargetMissing,
          [TAtlasOpenBuild.NameOf(Project.FileName), Settings.BuildOnOpenPlatform])];
    end;
    // Nur für diesen Lauf; über IOTAProject, denn die Hilfsschnittstellen lesen nur (wie der Läufer).
    if ((Configuration <> '') and not SameText(Configuration, Switch.Configuration)) or
      ((Platform <> '') and not SameText(Platform, Switch.Platform)) then
    begin
      FSwitched := FSwitched + [Switch];
      if (Configuration <> '') and not SameText(Configuration, Switch.Configuration) then
        Project.CurrentConfiguration := Configuration;
      if (Platform <> '') and not SameText(Platform, Switch.Platform) then
        Project.CurrentPlatform := Platform;
    end;
  end;
end;

procedure TAtlasIdeOpenBuild.RestoreTargets;
var
  Switch: TSwitch;
begin
  for Switch in FSwitched do
    try
      if not SameText(Switch.Project.CurrentConfiguration, Switch.Configuration) then
        Switch.Project.CurrentConfiguration := Switch.Configuration;
      if not SameText(Switch.Project.CurrentPlatform, Switch.Platform) then
        Switch.Project.CurrentPlatform := Switch.Platform;
    except
      // Ein inzwischen geschlossenes Projekt hält die anderen nicht auf (#493).
      on E: Exception do
        TAtlasGuard.Report(TAtlasFeature.Build, E);
    end;
  FSwitched := nil;
end;

procedure TAtlasIdeOpenBuild.Compile(const AProjects: TArray<IOTAProject>; const AFiles: TArray<string>);
const
  Modes: array[TAtlasCompileKind] of TOTACompileMode = (cmOTAMake, cmOTABuild, cmOTACheck, cmOTAMakeUnit,
    cmOTAClean, cmOTALink);
var
  CompileServices: IOTACompileServices;
  Outcome: TOTACompileResult;
  Activity: IInterface;
begin
  if not Supports(BorlandIDEServices, IOTACompileServices, CompileServices) then
    Exit;
  FCore.RunStarted(AFiles, NowMs);
  FStartedAt := NowMs;
  FWaiting := False;
  // Bis zum Ende des Laufs (auch im Hintergrund) tragen die Compile-Ereignisse den Auftraggeber "open".
  FEvents.RequestedBy := TAtlasOpenBuild.RequestedBy;
  Activity := TAtlasActivity.Scope('Bauen beim Öffnen');
  FCompiling := True;
  try
    try
      ApplyTargets(AProjects);
      Outcome := CompileServices.CompileProjects(AProjects, Modes[FKind], False, True);
    finally
      FCompiling := False;
    end;
  except
    on E: Exception do
    begin
      TAtlasGuard.Report(TAtlasFeature.Build, E);
      Finish;
      Exit;
    end;
  end;
  if (Outcome = crOTABackground) and FCore.Running and not FCore.RunComplete then
    FWaiting := True
  else
    Finish;
end;

procedure TAtlasIdeOpenBuild.Finish;
var
  Outcome: TAtlasOpenBuildResult;
  Severity: TAtlasNotificationSeverity;
  Kind, Text: string;
  Lines: TArray<string>;
begin
  if not FCore.Running then
    Exit;
  FWaiting := False;
  // Erst nach dem ganzen Lauf, auch im Hintergrund: Die Auswahl des Benutzers kommt zurück (#1293).
  RestoreTargets;
  if SameText(FEvents.RequestedBy, TAtlasOpenBuild.RequestedBy) then
    FEvents.RequestedBy := '';
  Outcome := FCore.RunFinished;
  Kind := TAtlasOpenBuild.KindName(FKind);
  if Assigned(FReport) then
    FReport(TAtlasStrings.Fmt(TAtlasTextId.OpenBuildReport, [Kind, Outcome.Total, Outcome.Succeeded,
      Outcome.Failed, Outcome.NotBuilt, NowMs - FStartedAt]));
  // Ein einzelnes gebautes Projekt meldet schon „Build fertig“ (#535); die Zusammenfassung lohnt nur sonst.
  if (Outcome.Total <= 1) and (Outcome.NotBuilt = 0) and (Length(FTargetNotes) = 0) then
    Exit;
  Severity := TAtlasNotificationSeverity.Info;
  if (Outcome.NotBuilt > 0) or (Length(FTargetNotes) > 0) then
    Severity := TAtlasNotificationSeverity.Warning;
  if Outcome.Failed > 0 then
    Severity := TAtlasNotificationSeverity.Error;
  Lines := nil;
  if Outcome.Failed > 0 then
    Lines := Lines + [TAtlasStrings.Fmt(TAtlasTextId.OpenBuildFailed, [string.Join(', ', Outcome.FailedNames)])];
  if Outcome.NotBuilt > 0 then
    Lines := Lines + [TAtlasStrings.Fmt(TAtlasTextId.OpenBuildNotBuilt, [string.Join(', ', Outcome.NotBuiltNames)])];
  if Outcome.CancelReason <> '' then
    Lines := Lines + [TAtlasStrings.Fmt(TAtlasTextId.OpenBuildReason, [Outcome.CancelReason])];
  if Length(Lines) = 0 then
    Lines := Lines + [TAtlasStrings.Fmt(TAtlasTextId.OpenBuildSucceeded, [Kind])];
  // Vorgaben, die ein Projekt nicht kennt (#1293): gebaut wie im Projekt eingestellt.
  Lines := Lines + FTargetNotes;
  Text := string.Join(sLineBreak, Lines);
  TAtlasNotificationCenter.Default.Notify(TAtlasNotificationSources.OpenBuild, Severity,
    TAtlasStrings.Fmt(TAtlasTextId.OpenBuildTitle, [Outcome.Succeeded, Outcome.Total]), Text);
end;

end.
