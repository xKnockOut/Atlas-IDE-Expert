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
  Atlas.Core.Build.OpenBuild,
  Atlas.Core.Build.OpenBuildSettings;

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
  Atlas.UI.Build.Strings;

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
  begin
    Exit;
  end;
  Name := FileName;
  // Keine Exception an die IDE (#493).
  if NotifyCode = ofnFileOpened then
  begin
    TAtlasGuard.Run(TAtlasFeature.Build,
      procedure
      begin
        Owner.Opened(Name);
      end);
  end
  else
  begin
    TAtlasGuard.Run(TAtlasFeature.Build,
      procedure
      begin
        Owner.Closing(Name);
      end);
  end;
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
  begin
    Exit;
  end;
  FOwner.FUserGroup := True;
  FOwner.FCore.BuildStarted;
end;

procedure TAtlasIdeOpenBuild.TWatcher.GroupFinished(ASucceeded: Boolean; ADurationMs: Int64);
begin
  if FOwner = nil then
  begin
    Exit;
  end;
  if FOwner.FCore.Running then
  begin
    // Im Hintergrund weitergelaufen: hier endet der eigene Lauf; modal schließt Compile nach der Rückkehr ab.
    if FOwner.FWaiting and not FOwner.FCompiling then
    begin
      FOwner.Finish;
    end;
    Exit;
  end;
  FOwner.FUserGroup := False;
  FOwner.FCore.BuildFinished;
end;

procedure TAtlasIdeOpenBuild.TWatcher.ProjectStarted(const AProject: TAtlasCompileProject);
begin
  if (FOwner = nil) or AProject.Background or SameText(AProject.RequestedBy, TAtlasOpenBuild.RequestedBy) then
  begin
    Exit;
  end;
  FOwner.FCore.BuildStarted;
end;

procedure TAtlasIdeOpenBuild.TWatcher.ProjectFinished(const AProject: TAtlasCompileProject; ASucceeded: Boolean;
  ADurationMs: Int64);
begin
  if FOwner = nil then
  begin
    Exit;
  end;
  if SameText(AProject.RequestedBy, TAtlasOpenBuild.RequestedBy) then
  begin
    FOwner.FCore.ProjectFinished(AProject.FileName, ASucceeded);
    Exit;
  end;
  // In einem Gruppenlauf des Benutzers endet der Build erst mit der Gruppe.
  if not AProject.Background and not FOwner.FUserGroup then
  begin
    FOwner.FCore.BuildFinished;
  end;
end;

procedure TAtlasIdeOpenBuild.TWatcher.CompileCancelled(const AProject: TAtlasCompileProject; const AReason: string);
begin
  if (FOwner <> nil) and SameText(AProject.RequestedBy, TAtlasOpenBuild.RequestedBy) then
  begin
    FOwner.FCore.ProjectCancelled(AProject.FileName, AReason);
  end;
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
  // Der Dienst übernimmt den Wächter; Destroy meldet ihn ab (danach erreicht ihn kein Ereignis mehr, #1455).
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
      begin
        FCore.Opened(Group.FileName, NowMs);
      end;
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
  begin
    FNotifier.FOwner := nil;
  end;
  if (FNotifierIndex >= 0) and Supports(BorlandIDEServices, IOTAServices, Services) then
  begin
    Services.RemoveNotifier(FNotifierIndex);
  end;
  FNotifierRef := nil;
  FWatcher.FOwner := nil;
  FEvents.Remove(FWatcher);
  FWatcher := nil;
  RestoreTargets;
  if FCore.Running and SameText(FEvents.RequestedBy, TAtlasOpenBuild.RequestedBy) then
  begin
    FEvents.RequestedBy := '';
  end;
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
  begin
    Exit(High(Integer));
  end;
  Ticks := GetTickCount;
  if Ticks >= Info.dwTime then
  begin
    Result := Ticks - Info.dwTime;
  end
  else
  begin
    Result := 0;
  end;
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
  begin
    FCore.Opened(AFileName, NowMs);
  end;
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
    begin
      for Index := 0 to Group.ProjectCount - 1 do
      begin
        FCore.Closed(Group.Projects[Index].FileName);
      end;
    end;
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
  begin
    Exit;
  end;
  Group := Modules.MainProjectGroup;
  if (Group = nil) or not SameText(Group.FileName, AFileName) or (Group.ProjectCount = 0) then
  begin
    Exit;
  end;
  for Index := 0 to Group.ProjectCount - 1 do
  begin
    AMembers := AMembers + [Group.Projects[Index].FileName];
  end;
  if AScope = TAtlasOpenBuildScope.Active then
  begin
    if Group.ActiveProject <> nil then
    begin
      AProjects := [Group.ActiveProject.FileName];
    end;
  end
  else
  begin
    AProjects := AMembers;
  end;
  Result := True;
end;

class function TAtlasIdeOpenBuild.FindProject(const AFileName: string): IOTAProject;
var
  Modules: IOTAModuleServices;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, IOTAModuleServices, Modules) then
  begin
    Exit;
  end;
  // Die IDE kennt das Projekt meist unter der .dproj, die .dpr/.dpk nur als Quelltext.
  if not Supports(Modules.FindModule(AFileName), IOTAProject, Result) then
  begin
    if not Supports(Modules.FindModule(ChangeFileExt(AFileName, '.dproj')), IOTAProject, Result) then
    begin
      Result := nil;
    end;
  end;
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
      begin
        TAtlasIdeCheckOnSave.PressProgressOk;
      end;
      Exit;
    end;
    if FWaiting then
    begin
      // Im Hintergrund: Ende über die Compile-Ereignisse; ohne Gruppenende spätestens nach MaxRunMs.
      if FCore.RunComplete or FCore.RunOverdue(NowMs) then
      begin
        Finish;
      end;
      Exit;
    end;
    Settings := TAtlasIdeSettings.Current;
    if not Settings.BuildOnOpen then
    begin
      Exit;
    end;
    // Compilerprüfung (#548) oder ein Auftrag des Läufers (#261, #69) läuft gerade.
    if FEvents.Background or (FEvents.RequestedBy <> '') then
    begin
      Exit;
    end;
    if FCore.Due(NowMs, Settings.BuildOnOpenDelayMs, IdleMs, Debugging) then
    begin
      Run;
    end;
  except
    // Keine Exception an die IDE (#493).
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Build, E);
  end;
end;

/// <summary>Projekte der gemeldeten Gruppen; ACovered bekommt alle Mitglieder. Noch nicht geladene Gruppen kommen
/// später wieder.</summary>
function GroupCandidates(ACore: TAtlasOpenBuild; const AFiles: TArray<string>; AScope: TAtlasOpenBuildScope;
  out ACovered: TArray<string>): TArray<string>;
var
  mFileName: string;
  mResolved, mMembers: TArray<string>;
begin
  Result := nil;
  ACovered := nil;
  for mFileName in AFiles do
  begin
    if not TAtlasOpenBuild.IsGroupFile(mFileName) then
    begin
      Continue;
    end;
    if TAtlasIdeOpenBuild.ResolveGroup(mFileName, AScope, mResolved, mMembers) then
    begin
      Result := Result + mResolved;
      ACovered := ACovered + mMembers;
    end
    else
    begin
      ACore.Retry(mFileName, TAtlasIdeOpenBuild.NowMs);
    end;
  end;
end;

function IsCovered(const ACovered: TArray<string>; const AFileName: string): Boolean;
var
  mMember: string;
begin
  for mMember in ACovered do
  begin
    if TAtlasOpenBuild.KeyOf(mMember) = TAtlasOpenBuild.KeyOf(AFileName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Einzeln gemeldete Projekte, die keine Gruppe schon abdeckt; nicht geladene kommen später wieder.</summary>
function ProjectCandidates(ACore: TAtlasOpenBuild; const AFiles, ACovered: TArray<string>): TArray<string>;
var
  mFileName: string;
  mProject: IOTAProject;
begin
  Result := nil;
  for mFileName in AFiles do
  begin
    if TAtlasOpenBuild.IsGroupFile(mFileName) or IsCovered(ACovered, mFileName) then
    begin
      Continue;
    end;
    mProject := TAtlasIdeOpenBuild.FindProject(mFileName);
    if mProject <> nil then
    begin
      Result := Result + [mProject.FileName];
    end
    else
    begin
      ACore.Retry(mFileName, TAtlasIdeOpenBuild.NowMs);
    end;
  end;
end;

/// <summary>Geladene Projekte mit Builder; ABuilt sind ihre Dateien.</summary>
function BuildableProjects(const ASelected: TArray<string>; out ABuilt: TArray<string>): TArray<IOTAProject>;
var
  mFileName: string;
  mProject: IOTAProject;
begin
  Result := nil;
  ABuilt := nil;
  for mFileName in ASelected do
  begin
    mProject := TAtlasIdeOpenBuild.FindProject(mFileName);
    if (mProject <> nil) and (mProject.ProjectBuilder <> nil) then
    begin
      Result := Result + [mProject];
      ABuilt := ABuilt + [mProject.FileName];
    end;
  end;
end;

procedure TAtlasIdeOpenBuild.Run;
var
  mSettings: TAtlasPluginSettings;
  mFiles, mCandidates, mCovered, mBuilt: TArray<string>;
  mProjects: TArray<IOTAProject>;
begin
  mSettings := TAtlasIdeSettings.Current;
  mFiles := FCore.Take;
  // Zuerst die Gruppen: Sie entscheiden auch über ihre einzeln gemeldeten Projekte.
  mCandidates := GroupCandidates(FCore, mFiles, TAtlasOpenBuildSettings.ScopeOf(mSettings.BuildOnOpenScope),
    mCovered);
  mCandidates := mCandidates + ProjectCandidates(FCore, mFiles, mCovered);
  mProjects := BuildableProjects(FCore.Select(mCandidates,
    TAtlasOpenBuildSettings.ParseExclude(mSettings.BuildOnOpenExclude)), mBuilt);
  if Length(mProjects) = 0 then
  begin
    Exit;
  end;
  FKind := TAtlasOpenBuildSettings.KindOf(mSettings.BuildOnOpenKind);
  Compile(mProjects, mBuilt);
end;

function TargetNote(const AProject: IOTAProject; const AWanted: string): string;
begin
  Result := TAtlasBuildStrings.Fmt(TAtlasBuildTextId.OpenBuildTargetMissing,
    [TAtlasOpenBuildSettings.NameOf(AProject.FileName), AWanted]);
end;

/// <summary>Konfiguration AWanted in der Schreibweise des Projekts; '' ohne Vorgabe oder wenn sie fehlt (dann
/// mit Hinweis in ANotes).</summary>
function PickConfiguration(const AProject: IOTAProject; const AWanted: string; var ANotes: TArray<string>): string;
var
  mConfigurations: IOTAProjectOptionsConfigurations;
  mNames: TArray<string>;
  mIndex: Integer;
begin
  Result := '';
  if AWanted = '' then
  begin
    Exit;
  end;
  mNames := nil;
  if Supports(AProject.ProjectOptions, IOTAProjectOptionsConfigurations, mConfigurations) then
  begin
    for mIndex := 0 to mConfigurations.ConfigurationCount - 1 do
    begin
      mNames := mNames + [mConfigurations.Configurations[mIndex].Name];
    end;
  end;
  Result := TAtlasOpenBuildSettings.PickTarget(AWanted, mNames);
  if Result = '' then
  begin
    ANotes := ANotes + [TargetNote(AProject, AWanted)];
  end;
end;

/// <summary>Wie PickConfiguration für die Plattform: nur aktivierte, in der Schreibweise des Projekts (auch
/// „Win 64“ trifft Win64).</summary>
function PickPlatform(const AProject: IOTAProject; const AWanted: string; var ANotes: TArray<string>): string;
var
  mPlatforms: IOTAProjectPlatforms;
begin
  Result := '';
  if AWanted = '' then
  begin
    Exit;
  end;
  if Supports(AProject, IOTAProjectPlatforms, mPlatforms) then
  begin
    Result := TAtlasOpenBuildSettings.PickTarget(AWanted, mPlatforms.EnabledPlatforms);
  end;
  if Result = '' then
  begin
    ANotes := ANotes + [TargetNote(AProject, AWanted)];
  end;
end;

function Differs(const AWanted, ACurrent: string): Boolean;
begin
  Result := (AWanted <> '') and not SameText(AWanted, ACurrent);
end;

procedure TAtlasIdeOpenBuild.ApplyTargets(const AProjects: TArray<IOTAProject>);
var
  mSettings: TAtlasPluginSettings;
  mProject: IOTAProject;
  mConfiguration, mPlatform: string;
  mSwitch: TSwitch;
begin
  FSwitched := nil;
  FTargetNotes := nil;
  mSettings := TAtlasIdeSettings.Current;
  if (mSettings.BuildOnOpenConfig = '') and (mSettings.BuildOnOpenPlatform = '') then
  begin
    Exit;
  end;
  for mProject in AProjects do
  begin
    mSwitch.Project := mProject;
    mSwitch.Configuration := mProject.CurrentConfiguration;
    mSwitch.Platform := mProject.CurrentPlatform;
    mConfiguration := PickConfiguration(mProject, mSettings.BuildOnOpenConfig, FTargetNotes);
    mPlatform := PickPlatform(mProject, mSettings.BuildOnOpenPlatform, FTargetNotes);
    // Nur für diesen Lauf; über IOTAProject, denn die Hilfsschnittstellen lesen nur (wie der Läufer).
    if Differs(mConfiguration, mSwitch.Configuration) or Differs(mPlatform, mSwitch.Platform) then
    begin
      FSwitched := FSwitched + [mSwitch];
      if Differs(mConfiguration, mSwitch.Configuration) then
      begin
        mProject.CurrentConfiguration := mConfiguration;
      end;
      if Differs(mPlatform, mSwitch.Platform) then
      begin
        mProject.CurrentPlatform := mPlatform;
      end;
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
      begin
        Switch.Project.CurrentConfiguration := Switch.Configuration;
      end;
      if not SameText(Switch.Project.CurrentPlatform, Switch.Platform) then
      begin
        Switch.Project.CurrentPlatform := Switch.Platform;
      end;
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
  begin
    Exit;
  end;
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
  begin
    FWaiting := True;
  end
  else
  begin
    Finish;
  end;
end;

function FinishSeverity(const AOutcome: TAtlasOpenBuildResult; AHasNotes: Boolean): TAtlasNotificationSeverity;
begin
  Result := TAtlasNotificationSeverity.Info;
  if (AOutcome.NotBuilt > 0) or AHasNotes then
  begin
    Result := TAtlasNotificationSeverity.Warning;
  end;
  if AOutcome.Failed > 0 then
  begin
    Result := TAtlasNotificationSeverity.Error;
  end;
end;

function FinishLines(const AOutcome: TAtlasOpenBuildResult; const AKind: string;
  const ANotes: TArray<string>): TArray<string>;
begin
  Result := nil;
  if AOutcome.Failed > 0 then
  begin
    Result := Result + [TAtlasBuildStrings.Fmt(TAtlasBuildTextId.OpenBuildFailed,
      [string.Join(', ', AOutcome.FailedNames)])];
  end;
  if AOutcome.NotBuilt > 0 then
  begin
    Result := Result + [TAtlasBuildStrings.Fmt(TAtlasBuildTextId.OpenBuildNotBuilt,
      [string.Join(', ', AOutcome.NotBuiltNames)])];
  end;
  if AOutcome.CancelReason <> '' then
  begin
    Result := Result + [TAtlasBuildStrings.Fmt(TAtlasBuildTextId.OpenBuildReason, [AOutcome.CancelReason])];
  end;
  if Length(Result) = 0 then
  begin
    Result := Result + [TAtlasBuildStrings.Fmt(TAtlasBuildTextId.OpenBuildSucceeded, [AKind])];
  end;
  // Vorgaben, die ein Projekt nicht kennt (#1293): gebaut wie im Projekt eingestellt.
  Result := Result + ANotes;
end;

procedure TAtlasIdeOpenBuild.Finish;
var
  mOutcome: TAtlasOpenBuildResult;
  mKind: string;
begin
  if not FCore.Running then
  begin
    Exit;
  end;
  FWaiting := False;
  // Erst nach dem ganzen Lauf, auch im Hintergrund: Die Auswahl des Benutzers kommt zurück (#1293).
  RestoreTargets;
  if SameText(FEvents.RequestedBy, TAtlasOpenBuild.RequestedBy) then
  begin
    FEvents.RequestedBy := '';
  end;
  mOutcome := FCore.RunFinished;
  mKind := TAtlasOpenBuildSettings.KindName(FKind);
  if Assigned(FReport) then
  begin
    FReport(TAtlasBuildStrings.Fmt(TAtlasBuildTextId.OpenBuildReport, [mKind, mOutcome.Total, mOutcome.Succeeded,
      mOutcome.Failed, mOutcome.NotBuilt, NowMs - FStartedAt]));
  end;
  // Ein einzelnes gebautes Projekt meldet schon „Build fertig“ (#535); die Zusammenfassung lohnt nur sonst.
  if (mOutcome.Total <= 1) and (mOutcome.NotBuilt = 0) and (Length(FTargetNotes) = 0) then
  begin
    Exit;
  end;
  TAtlasNotificationCenter.Default.Notify(TAtlasNotificationSources.cOpenBuild,
    FinishSeverity(mOutcome, Length(FTargetNotes) > 0),
    TAtlasBuildStrings.Fmt(TAtlasBuildTextId.OpenBuildTitle, [mOutcome.Succeeded, mOutcome.Total]),
    string.Join(sLineBreak, FinishLines(mOutcome, mKind, FTargetNotes)));
end;

end.
