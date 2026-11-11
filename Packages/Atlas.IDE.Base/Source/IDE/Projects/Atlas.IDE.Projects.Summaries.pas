unit Atlas.IDE.Projects.Summaries;

// Projekt-Zusammenfassungen in %LOCALAPPDATA%\Atlas\projects pflegen (#592, #1455). Im Kern: Base schreibt sie
// auch ohne die Willkommensseite; die Willkommensseite (Bereiche Projekte, Projektverlauf, Tests, Meine Issues),
// „Fehlgeschlagene Tests erneut ausführen“ (Modul Tests) und der Release-Wächter lesen sie.
// - Geschrieben wird nach jedem Build und jeder Hintergrundprüfung (Meldungen aus dem Reiter „Build“, #528; bei
//   einer Projektgruppe auch in deren Zusammenfassung), beim Öffnen (lastOpened, hebt „Aus Liste entfernen“ auf)
//   und beim Schließen eines Projekts (lastClosed, frischer Stand der Versionsverwaltung).
// - Versionsverwaltung (#571): im Hintergrund abgefragt, je Projekt höchstens einmal je Minute (QueryIfStale),
//   mit 2 s Zeitlimit; bis dahin gilt der gespeicherte Stand. Geänderte Dateien zählen nur im Projektordner.
//   Startet die Abfrage nicht oder kommt sie nicht binnen 5 s zurück, endet „wird abgefragt …“.
// - Regeltreffer (#97): beim Schließen und nach jedem Build aus den Problemen, die das Plugin vom Server hat
//   (#398, Baseline schon abgezogen), gezählt im Projektordner; nur wenn Probleme an sind.
// - Code-Metriken (#66), TODO-Übersicht (#68) und Baseline (#97): Antworten des Servers nach einem Build, nur
//   für das Projekt, Zeitpunkt der des Builds. Nach „Baseline des Projekts aktualisieren“ (Modul Prüfregeln)
//   ebenso mit den Zählern des Servers.
// - Projektverlauf (#758, welcomePage.trends): nach jedem Build des Benutzers ein Messpunkt im Abschnitt
//   "trends", auch für die Projektgruppe; Metriken, TODOs, Baseline, Branch und Commit mit demselben Zeitpunkt
//   kommen in diesen Punkt (Fill).
// - Tests (#69): nach jedem Testlauf (Modul Tests) der Abschnitt "tests" für das Testprojekt und seine
//   Projektgruppe.
// - Nach jeder Änderung bekommt jeder IAtlasProjectSummaryListener (Beitrag eines laufenden Moduls) die
//   Meldung im Hauptthread.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  ToolsAPI,
  Atlas.Core.Projects.Summary,
  Atlas.Core.Projects.Baseline,
  Atlas.Core.Build.Events,
  Atlas.Core.Build.Messages,
  Atlas.Core.Problems.Store;

type
  /// <summary>Hört auf geänderte Projekt-Zusammenfassungen (Hauptthread). AProject: Projekt oder Projektgruppe,
  /// '' = mehrere oder unbekannt.</summary>
  IAtlasProjectSummaryListener = interface
    ['{6E0C5B7A-2F1D-4C8E-9A35-7D41B0E2C9F6}']
    procedure SummaryChanged(const AProject: string);
  end;

  TAtlasIdeProjectSummaries = class
  private type
    TIdeNotifier = class(TNotifierObject, IOTAIDENotifier)
    private
      FOwner: TAtlasIdeProjectSummaries;
    public
      procedure FileNotification(NotifyCode: TOTAFileNotification; const FileName: string; var Cancel: Boolean);
      procedure BeforeCompile(const Project: IOTAProject; var Cancel: Boolean); overload;
      procedure AfterCompile(Succeeded: Boolean); overload;
    end;
  private class var
    FCurrent: TAtlasIdeProjectSummaries;
  private
    FNotifier: TIdeNotifier;
    FNotifierIndex: Integer;
    FStopped: Boolean;
    // Probleme, die das Plugin vom Server hat (#398); nil ohne.
    FProblems: TFunc<TAtlasProblemStore>;
    // Normierter Pfad → Zeitpunkt (GetTickCount64) bzw. Ergebnis der letzten Abfrage in dieser Sitzung.
    FFresh: TDictionary<string, UInt64>;
    FLive: TDictionary<string, TAtlasProjectVcs>;
    // Normierter Pfad → Start der laufenden Abfrage (GetTickCount64).
    FQuerying: TDictionary<string, UInt64>;
    procedure Changed(const AProject: string);
    procedure Opened(const AProject: string);
    procedure Closing(const AProject: string);
    /// <summary>Mit ABuildUtc &gt; 0 trägt das Ergebnis Branch und Commit in den Messpunkt dieses Builds ein
    /// (#758).</summary>
    procedure Query(const AProject: string; ABuildUtc: TDateTime);
    /// <summary>Stand der Versionsverwaltung in die Zusammenfassung; mit ABuildUtc &gt; 0 auch in den Messpunkt
    /// dieses Builds (#758).</summary>
    class procedure StoreVcs(const ARoot, AProject: string; const AState: TAtlasProjectVcs;
      ABuildUtc: TDateTime); static;
    function QueryingKey(const AKey: string): Boolean;
    procedure RecordRules(const AProject: string; ANowUtc: TDateTime);
    procedure RecordInto(const AProject: string; const AMessages: TArray<TAtlasCompilerMessage>;
      const AInfo: TAtlasCompileProject; ASucceeded: Boolean; ADurationMs: Int64; ANowUtc: TDateTime);
    procedure RecordTrend(const AProject: string; ANowUtc: TDateTime);
    class function TrendsOn: Boolean; static;
    class function IsProjectFile(const AFileName: string): Boolean; static;
  public
    /// <summary>AProblems liefert die Probleme des Plugins (Regeltreffer, #97); die Kompositionswurzel reicht
    /// sie herein, damit Projekte nicht von Problemen abhängen.</summary>
    constructor Create(const AProblems: TFunc<TAtlasProblemStore>);
    destructor Destroy; override;
    /// <summary>Die laufende Pflege; nil vor dem Start und nach dem Ende von Base.</summary>
    class function Current: TAtlasIdeProjectSummaries; static;
    /// <summary>Beobachter der IDE anmelden.</summary>
    procedure Start;
    /// <summary>Alles abmelden (beim Entladen); danach wirkungslos.</summary>
    procedure Stop;
    /// <summary>Ergebnis eines Compiles aus dem Reiter „Build“ (#528) mit dem Zeitpunkt des Builds AAtUtc;
    /// denselben bekommen RecordMetrics, RecordTodos und RecordBaseline (#758). AReadable = False: Meldungen nicht
    /// lesbar, dann bleibt die Zusammenfassung unverändert.</summary>
    procedure Recorded(const AMessages: TArray<TAtlasCompilerMessage>; const AProject: TAtlasCompileProject;
      ASucceeded, AReadable: Boolean; AAtUtc: TDateTime);
    /// <summary>Antwort von atlas.server.metrics (Modus summary) für AProject zum Zeitpunkt AAtUtc (#66);
    /// ungültige oder leere Antwort: Zusammenfassung bleibt unverändert. Hauptthread.</summary>
    procedure RecordMetrics(const AProject, AJson: string; AAtUtc: TDateTime);
    /// <summary>Antwort von atlas.server.todos (Modus summary) für AProject zum Zeitpunkt AAtUtc (#68).</summary>
    procedure RecordTodos(const AProject, AJson: string; AAtUtc: TDateTime);
    /// <summary>Baseline des Projekts (#97) nach einem Build: Stand der Datei, das letzte Aktualisieren bleibt.
    /// </summary>
    procedure RecordBaseline(const AProject: string; const AState: TAtlasBaselineState; AAtUtc: TDateTime);
      overload;
    /// <summary>Baseline des Projekts (#97) nach dem Aktualisieren: Stand der Datei und Zähler des Servers.</summary>
    procedure RecordBaseline(const AProject: string; const AState: TAtlasBaselineState;
      const AUpdate: TAtlasBaselineUpdate; AAtUtc: TDateTime); overload;
    /// <summary>Letzter Testlauf (#69) des Testprojekts AProject; bei einer Projektgruppe auch in deren
    /// Zusammenfassung. Hauptthread.</summary>
    procedure RecordTests(const AProject: string; const ATests: TAtlasProjectTests);
    /// <summary>AProject aus dem Bereich „Projekte“ nehmen bzw. wieder zeigen ("hidden").</summary>
    procedure SetHidden(const AProject: string; AHidden: Boolean);
    /// <summary>Stand der Versionsverwaltung: frisch abgefragt (diese Sitzung), sonst aus der Zusammenfassung;
    /// Empty ohne (#764).</summary>
    function VcsOf(const AProject: string): TAtlasProjectVcs;
    /// <summary>In dieser Sitzung frisch abgefragter Stand; False ohne.</summary>
    function LiveVcs(const AProject: string; out AVcs: TAtlasProjectVcs): Boolean;
    /// <summary>Läuft gerade eine Abfrage für AProject?</summary>
    function Querying(const AProject: string): Boolean;
    /// <summary>Branch und Änderungen abfragen, wenn die letzte Abfrage länger als VcsRefreshMs her ist (#571).
    /// </summary>
    procedure QueryIfStale(const AProject: string);
    /// <summary>Branch und Änderungen jetzt neu abfragen (nach Pull, #764), auch innerhalb der Minute.</summary>
    procedure Refresh(const AProject: string);
    /// <summary>%LOCALAPPDATA%\Atlas\projects.</summary>
    class function Folder: string; static;
    /// <summary>.dpr bzw. .dpk mit .dproj daneben → .dproj (so führt die IDE ihre Liste).</summary>
    class function ProjectFileOf(const AFileName: string): string; static;
    /// <summary>Offene Projektgruppe, in der AProject liegt; '' ohne.</summary>
    class function GroupOf(const AProject: string): string; static;
    /// <summary>Jetzt in UTC, Zeitpunkt der Einträge.</summary>
    class function StampUtc: TDateTime; static;
  end;

implementation

uses
  Winapi.Windows,
  System.Classes,
  System.DateUtils,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Projects.Recording,
  Atlas.Core.Projects.Trends,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Modules.Contributions,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Contracts.VersionControl;

{ TAtlasIdeProjectSummaries.TIdeNotifier }

procedure TAtlasIdeProjectSummaries.TIdeNotifier.FileNotification(NotifyCode: TOTAFileNotification;
  const FileName: string; var Cancel: Boolean);
var
  mOwner: TAtlasIdeProjectSummaries;
  mName: string;
begin
  mOwner := FOwner;
  if (mOwner = nil) or not ((NotifyCode = ofnFileOpened) or (NotifyCode = ofnFileClosing)) or
    not IsProjectFile(FileName) then
  begin
    Exit;
  end;
  mName := FileName;
  // Keine Exception an die IDE (#493).
  if NotifyCode = ofnFileOpened then
  begin
    TAtlasGuard.Run(TAtlasFeature.WelcomePage,
      procedure
      begin
        mOwner.Opened(mName);
      end);
  end
  else
  begin
    TAtlasGuard.Run(TAtlasFeature.WelcomePage,
      procedure
      begin
        mOwner.Closing(mName);
      end);
  end;
end;

procedure TAtlasIdeProjectSummaries.TIdeNotifier.BeforeCompile(const Project: IOTAProject; var Cancel: Boolean);
begin
end;

procedure TAtlasIdeProjectSummaries.TIdeNotifier.AfterCompile(Succeeded: Boolean);
begin
end;

{ TAtlasIdeProjectSummaries }

constructor TAtlasIdeProjectSummaries.Create(const AProblems: TFunc<TAtlasProblemStore>);
begin
  inherited Create;
  FProblems := AProblems;
  FNotifierIndex := -1;
  FFresh := TDictionary<string, UInt64>.Create;
  FLive := TDictionary<string, TAtlasProjectVcs>.Create;
  FQuerying := TDictionary<string, UInt64>.Create;
  FCurrent := Self;
end;

destructor TAtlasIdeProjectSummaries.Destroy;
begin
  Stop;
  if FCurrent = Self then
  begin
    FCurrent := nil;
  end;
  FQuerying.Free;
  FLive.Free;
  FFresh.Free;
  inherited;
end;

class function TAtlasIdeProjectSummaries.Current: TAtlasIdeProjectSummaries;
begin
  Result := FCurrent;
end;

class function TAtlasIdeProjectSummaries.Folder: string;
begin
  Result := TAtlasProjectSummaries.DefaultFolder;
end;

class function TAtlasIdeProjectSummaries.StampUtc: TDateTime;
begin
  Result := TTimeZone.Local.ToUniversalTime(Now);
end;

class function TAtlasIdeProjectSummaries.IsProjectFile(const AFileName: string): Boolean;
var
  mExtension: string;
begin
  mExtension := LowerCase(ExtractFileExt(Trim(AFileName)));
  Result := (mExtension = '.dproj') or (mExtension = '.dpr') or (mExtension = '.dpk') or
    (mExtension = '.groupproj');
end;

class function TAtlasIdeProjectSummaries.ProjectFileOf(const AFileName: string): string;
begin
  Result := AFileName;
  if (SameText(ExtractFileExt(Result), '.dpr') or SameText(ExtractFileExt(Result), '.dpk')) and
    FileExists(ChangeFileExt(Result, '.dproj')) then
  begin
    Result := ChangeFileExt(Result, '.dproj');
  end;
end;

class function TAtlasIdeProjectSummaries.GroupOf(const AProject: string): string;
var
  mModules: IOTAModuleServices;
  mGroup: IOTAProjectGroup;
  mIndex: Integer;
begin
  // Liegt das Projekt in der offenen Projektgruppe, zählt sein Build auch für die Gruppe (die Liste der IDE
  // führt oft nur die Gruppe).
  Result := '';
  if not Supports(BorlandIDEServices, IOTAModuleServices, mModules) then
  begin
    Exit;
  end;
  mGroup := mModules.MainProjectGroup;
  if (mGroup = nil) or (mGroup.FileName = '') or SameText(mGroup.FileName, AProject) then
  begin
    Exit;
  end;
  for mIndex := 0 to mGroup.ProjectCount - 1 do
  begin
    if (mGroup.Projects[mIndex] <> nil) and SameText(mGroup.Projects[mIndex].FileName, AProject) then
    begin
      Exit(mGroup.FileName);
    end;
  end;
end;

class function TAtlasIdeProjectSummaries.TrendsOn: Boolean;
begin
  Result := TAtlasIdeSettings.Current.WelcomePageTrends;
end;

procedure TAtlasIdeProjectSummaries.Start;
var
  mServices: IOTAServices;
begin
  FStopped := False;
  if (FNotifier = nil) and Supports(BorlandIDEServices, IOTAServices, mServices) then
  begin
    FNotifier := TIdeNotifier.Create;
    FNotifier.FOwner := Self;
    FNotifierIndex := mServices.AddNotifier(FNotifier);
  end;
end;

procedure TAtlasIdeProjectSummaries.Stop;
var
  mServices: IOTAServices;
begin
  if FStopped then
  begin
    Exit;
  end;
  FStopped := True;
  if FNotifier <> nil then
  begin
    FNotifier.FOwner := nil;
    // RemoveNotifier gibt die Referenz der IDE frei und damit den Beobachter (#493).
    if (FNotifierIndex >= 0) and Supports(BorlandIDEServices, IOTAServices, mServices) then
    begin
      mServices.RemoveNotifier(FNotifierIndex);
    end;
    FNotifier := nil;
    FNotifierIndex := -1;
  end;
end;

procedure TAtlasIdeProjectSummaries.Changed(const AProject: string);
var
  mItem: IInterface;
  mListener: IAtlasProjectSummaryListener;
  mProject: string;
begin
  if FStopped then
  begin
    Exit;
  end;
  mProject := AProject;
  for mItem in TAtlasModuleContributions.Active(AtlasModuleRegistry, IAtlasProjectSummaryListener) do
  begin
    if Supports(mItem, IAtlasProjectSummaryListener, mListener) then
    begin
      TAtlasGuard.Run(TAtlasFeature.WelcomePage,
        procedure
        begin
          mListener.SummaryChanged(mProject);
        end);
    end;
  end;
end;

function TAtlasIdeProjectSummaries.QueryingKey(const AKey: string): Boolean;
var
  mStarted: UInt64;
begin
  // Eine Abfrage, die nicht binnen VcsQueryLimitMs zurückkam, gilt als beendet.
  Result := FQuerying.TryGetValue(AKey, mStarted) and TAtlasProjectRecording.QueryRunning(mStarted, GetTickCount64);
  if not Result then
  begin
    FQuerying.Remove(AKey);
  end;
end;

function TAtlasIdeProjectSummaries.Querying(const AProject: string): Boolean;
begin
  Result := not FStopped and QueryingKey(TAtlasProjectSummaries.NormalizedPath(AProject));
end;

function TAtlasIdeProjectSummaries.LiveVcs(const AProject: string; out AVcs: TAtlasProjectVcs): Boolean;
begin
  AVcs := TAtlasProjectVcs.Empty;
  Result := not FStopped and FLive.TryGetValue(TAtlasProjectSummaries.NormalizedPath(AProject), AVcs);
end;

function TAtlasIdeProjectSummaries.VcsOf(const AProject: string): TAtlasProjectVcs;
var
  mSummary: TAtlasProjectSummary;
begin
  Result := TAtlasProjectVcs.Empty;
  if FStopped or (AProject = '') then
  begin
    Exit;
  end;
  if LiveVcs(AProject, Result) then
  begin
    Exit;
  end;
  if TAtlasProjectSummaries.Load(Folder, AProject, mSummary) then
  begin
    Result := mSummary.Vcs;
  end;
end;

procedure TAtlasIdeProjectSummaries.QueryIfStale(const AProject: string);
var
  mLast: UInt64;
begin
  if FStopped or (AProject = '') then
  begin
    Exit;
  end;
  if not FFresh.TryGetValue(TAtlasProjectSummaries.NormalizedPath(AProject), mLast) or
    (GetTickCount64 - mLast >= TAtlasProjectRecording.cVcsRefreshMs) then
  begin
    Query(AProject, 0);
  end;
end;

procedure TAtlasIdeProjectSummaries.Refresh(const AProject: string);
begin
  if FStopped or (AProject = '') then
  begin
    Exit;
  end;
  // Auch ohne welcomePage.refreshVcs: Der Benutzer hat gerade geholt, der alte Stand wäre falsch.
  FFresh.Remove(TAtlasProjectSummaries.NormalizedPath(AProject));
  Query(AProject, 0);
end;

class procedure TAtlasIdeProjectSummaries.StoreVcs(const ARoot, AProject: string; const AState: TAtlasProjectVcs;
  ABuildUtc: TDateTime);
var
  mState: TAtlasProjectVcs;
  mBuildStamp: TDateTime;
begin
  mState := AState;
  mBuildStamp := ABuildUtc;
  TAtlasProjectSummaries.Update(ARoot, AProject,
    procedure(var ASummary: TAtlasProjectSummary)
    begin
      ASummary.Vcs := mState;
      // Branch und Commit zum Zeitpunkt des Builds in dessen Messpunkt (#758).
      if mBuildStamp > 0 then
      begin
        TAtlasProjectTrendLog.Fill(ASummary, mBuildStamp);
      end;
    end);
end;

procedure TAtlasIdeProjectSummaries.Query(const AProject: string; ABuildUtc: TDateTime);
var
  mKey, mProject, mDir, mRoot: string;
  mStamp, mBuildStamp: TDateTime;
  mOk: Boolean;
  mState: TAtlasProjectVcs;
  mStarted: UInt64;
begin
  mKey := TAtlasProjectSummaries.NormalizedPath(AProject);
  if FStopped or QueryingKey(mKey) then
  begin
    Exit;
  end;
  mStarted := GetTickCount64;
  FQuerying.AddOrSetValue(mKey, mStarted);
  mProject := AProject;
  mDir := ExtractFileDir(AProject);
  mRoot := Folder;
  mStamp := StampUtc;
  mBuildStamp := ABuildUtc;
  mOk := False;
  mState := TAtlasProjectVcs.Empty;
  // Arbeit und Ergebnis teilen sich mOk und mState; das Ergebnis kommt erst nach der Arbeit. Die Pflege lebt bis
  // zum Ende von Base; TAtlasIdeVcs ruft nach dem Ende nichts mehr auf.
  if not TAtlasIdeVcs.Run(
    procedure
    begin
      // Geänderte Dateien nur im Projektordner: Eine Arbeitskopie kann mehrere Projekte enthalten.
      mOk := TAtlasProjectRecording.Probe(TAtlasIdeVcs.ForFolder(mDir, TAtlasProjectRecording.cVcsCallTimeoutMs),
        mDir, mStamp, mState);
    end,
    procedure
    var
      mCurrent: UInt64;
    begin
      if FStopped then
      begin
        Exit;
      end;
      // Nur die eigene Abfrage beenden, nicht eine neuere nach Ablauf des Zeitlimits.
      if FQuerying.TryGetValue(mKey, mCurrent) and (mCurrent = mStarted) then
      begin
        FQuerying.Remove(mKey);
      end;
      FFresh.AddOrSetValue(mKey, GetTickCount64);
      if mOk then
      begin
        FLive.AddOrSetValue(mKey, mState);
        StoreVcs(mRoot, mProject, mState, mBuildStamp);
      end;
      Changed(mProject);
    end) then
  begin
    // Nicht gestartet (Versionsverwaltung noch nicht bereit oder beendet): kein „wird abgefragt …“, nicht
    // bei jedem Zeichnen neu versuchen.
    FQuerying.Remove(mKey);
    FFresh.AddOrSetValue(mKey, GetTickCount64);
  end;
end;

procedure TAtlasIdeProjectSummaries.RecordRules(const AProject: string; ANowUtc: TDateTime);
var
  mSettings: TAtlasPluginSettings;
  mHits: Integer;
  mStamp: TDateTime;
begin
  // Nur was das Plugin vom Server hat (Probleme an); ohne geprüfte Datei im Projektordner bleibt der alte Stand.
  mSettings := TAtlasIdeSettings.Current;
  if not (mSettings.Enabled and mSettings.Problems) or not Assigned(FProblems) then
  begin
    Exit;
  end;
  if not TAtlasProjectRecording.CountRuleHits(FProblems(), ExtractFileDir(AProject), mHits) then
  begin
    Exit;
  end;
  mStamp := ANowUtc;
  TAtlasProjectSummaries.Update(Folder, AProject,
    procedure(var ASummary: TAtlasProjectSummary)
    begin
      TAtlasProjectRecording.RecordRules(ASummary, mHits, mStamp);
    end);
end;

procedure TAtlasIdeProjectSummaries.Opened(const AProject: string);
var
  mStamp: TDateTime;
  mProject: string;
begin
  if FStopped then
  begin
    Exit;
  end;
  mStamp := StampUtc;
  mProject := ProjectFileOf(AProject);
  TAtlasProjectSummaries.Update(Folder, mProject,
    procedure(var ASummary: TAtlasProjectSummary)
    begin
      ASummary.LastOpened := mStamp;
      // Wieder geöffnet: erscheint wieder in der Liste.
      ASummary.Hidden := False;
    end);
  Changed(mProject);
end;

procedure TAtlasIdeProjectSummaries.Closing(const AProject: string);
var
  mStamp: TDateTime;
  mProject: string;
begin
  if FStopped then
  begin
    Exit;
  end;
  mStamp := StampUtc;
  mProject := ProjectFileOf(AProject);
  TAtlasProjectSummaries.Update(Folder, mProject,
    procedure(var ASummary: TAtlasProjectSummary)
    begin
      ASummary.LastClosed := mStamp;
    end);
  // Regeltreffer, solange die Probleme des Projekts noch im Speicher sind.
  RecordRules(mProject, mStamp);
  // Branch und Änderungen beim Schließen festhalten (im Hintergrund).
  if TAtlasIdeSettings.Current.WelcomePageRefreshVcs then
  begin
    Query(mProject, 0);
  end;
  Changed(mProject);
end;

procedure TAtlasIdeProjectSummaries.RecordInto(const AProject: string;
  const AMessages: TArray<TAtlasCompilerMessage>; const AInfo: TAtlasCompileProject; ASucceeded: Boolean;
  ADurationMs: Int64; ANowUtc: TDateTime);
var
  mMessages: TArray<TAtlasCompilerMessage>;
  mInfo: TAtlasCompileProject;
  mSucceeded: Boolean;
  mStamp: TDateTime;
  mDuration: Integer;
begin
  mMessages := AMessages;
  mInfo := AInfo;
  mSucceeded := ASucceeded;
  mStamp := ANowUtc;
  // Mehr als 24 Tage gibt es nicht; ungültige Werte als unbekannt.
  mDuration := 0;
  if (ADurationMs > 0) and (ADurationMs < MaxInt) then
  begin
    mDuration := Integer(ADurationMs);
  end;
  TAtlasProjectSummaries.Update(Folder, AProject,
    procedure(var ASummary: TAtlasProjectSummary)
    begin
      TAtlasProjectRecording.RecordCompile(ASummary, mMessages, TAtlasProjectCompileRun.Create(mInfo.Background,
        mSucceeded, TAtlasCompileEvents.KindText(mInfo.Kind), mInfo.Configuration, mInfo.Platform), mStamp);
      // Build-Dauer (#758); eine Hintergrundprüfung ändert den Abschnitt "build" nicht.
      if not mInfo.Background then
      begin
        ASummary.Build.DurationMs := mDuration;
      end;
    end);
end;

procedure TAtlasIdeProjectSummaries.RecordTrend(const AProject: string; ANowUtc: TDateTime);
var
  mStamp: TDateTime;
  mLimit: Integer;
begin
  mStamp := ANowUtc;
  mLimit := TAtlasIdeSettings.Current.WelcomePageTrendsPoints;
  TAtlasProjectSummaries.Update(Folder, AProject,
    procedure(var ASummary: TAtlasProjectSummary)
    begin
      TAtlasProjectTrendLog.Append(ASummary, mStamp, mLimit);
    end);
end;

procedure TAtlasIdeProjectSummaries.Recorded(const AMessages: TArray<TAtlasCompilerMessage>;
  const AProject: TAtlasCompileProject; ASucceeded, AReadable: Boolean; AAtUtc: TDateTime);
var
  mGroup: string;
  mGroupDuration: Int64;
  mTrends: Boolean;
begin
  if FStopped or not AReadable or (AProject.FileName = '') then
  begin
    Exit;
  end;
  // Projektverlauf (#758): nur Builds des Benutzers, nicht die eigene Hintergrundprüfung.
  mTrends := TrendsOn and not AProject.Background;
  RecordInto(AProject.FileName, AMessages, AProject, ASucceeded, AProject.DurationMs, AAtUtc);
  RecordRules(AProject.FileName, AAtUtc);
  if mTrends then
  begin
    RecordTrend(AProject.FileName, AAtUtc);
  end;
  mGroup := GroupOf(AProject.FileName);
  if mGroup <> '' then
  begin
    // Die Gruppe misst den ganzen Lauf („Alle erzeugen“); ohne Angabe die Dauer des Projekts.
    mGroupDuration := AProject.GroupDurationMs;
    if mGroupDuration <= 0 then
    begin
      mGroupDuration := AProject.DurationMs;
    end;
    RecordInto(mGroup, AMessages, AProject, ASucceeded, mGroupDuration, AAtUtc);
    RecordRules(mGroup, AAtUtc);
    if mTrends then
    begin
      RecordTrend(mGroup, AAtUtc);
    end;
  end;
  // Branch und Commit des Builds frisch abfragen (im Hintergrund); bis dahin gilt der bekannte Stand.
  if mTrends and TAtlasIdeSettings.Current.WelcomePageRefreshVcs then
  begin
    Query(ProjectFileOf(AProject.FileName), AAtUtc);
    if mGroup <> '' then
    begin
      Query(mGroup, AAtUtc);
    end;
  end;
  Changed('');
end;

procedure TAtlasIdeProjectSummaries.RecordMetrics(const AProject, AJson: string; AAtUtc: TDateTime);
var
  mMetrics: TAtlasProjectMetrics;
begin
  if FStopped or (AProject = '') then
  begin
    Exit;
  end;
  if not TAtlasProjectMetrics.FromServer(AJson, AAtUtc, mMetrics) then
  begin
    Exit;
  end;
  TAtlasProjectSummaries.Update(Folder, AProject,
    procedure(var ASummary: TAtlasProjectSummary)
    begin
      ASummary.Metrics := mMetrics;
      // In den Messpunkt des Builds mit demselben Zeitpunkt (#758); ohne Punkt nichts.
      TAtlasProjectTrendLog.Fill(ASummary, ASummary.Metrics.At);
    end);
  Changed(AProject);
end;

procedure TAtlasIdeProjectSummaries.RecordTodos(const AProject, AJson: string; AAtUtc: TDateTime);
var
  mTodos: TAtlasProjectTodos;
begin
  if FStopped or (AProject = '') then
  begin
    Exit;
  end;
  if not TAtlasProjectTodos.FromServer(AJson, AAtUtc, mTodos) then
  begin
    Exit;
  end;
  TAtlasProjectSummaries.Update(Folder, AProject,
    procedure(var ASummary: TAtlasProjectSummary)
    begin
      ASummary.Todos := mTodos;
      // In den Messpunkt des Builds mit demselben Zeitpunkt (#758); ohne Punkt nichts.
      TAtlasProjectTrendLog.Fill(ASummary, ASummary.Todos.At);
    end);
  Changed(AProject);
end;

procedure TAtlasIdeProjectSummaries.RecordTests(const AProject: string; const ATests: TAtlasProjectTests);
var
  mTests: TAtlasProjectTests;
  mGroup: string;
begin
  if FStopped or (AProject = '') or not ATests.Known then
  begin
    Exit;
  end;
  mTests := ATests;
  TAtlasProjectSummaries.Update(Folder, AProject,
    procedure(var ASummary: TAtlasProjectSummary)
    begin
      ASummary.Tests := mTests;
    end);
  mGroup := GroupOf(AProject);
  if mGroup <> '' then
  begin
    TAtlasProjectSummaries.Update(Folder, mGroup,
      procedure(var ASummary: TAtlasProjectSummary)
      begin
        ASummary.Tests := mTests;
      end);
  end;
  Changed(AProject);
end;

procedure TAtlasIdeProjectSummaries.RecordBaseline(const AProject: string; const AState: TAtlasBaselineState;
  AAtUtc: TDateTime);
var
  mState: TAtlasBaselineState;
  mStamp: TDateTime;
begin
  if FStopped or (AProject = '') then
  begin
    Exit;
  end;
  mState := AState;
  mStamp := AAtUtc;
  TAtlasProjectSummaries.Update(Folder, AProject,
    procedure(var ASummary: TAtlasProjectSummary)
    begin
      TAtlasProjectBaselines.Measured(ASummary.Baseline, mState, mStamp);
      // Ohne Baseline wird „Regeltreffer seit Baseline“ im Messpunkt dieses Builds zur Lücke (#758).
      TAtlasProjectTrendLog.Fill(ASummary, mStamp);
    end);
  Changed(AProject);
end;

procedure TAtlasIdeProjectSummaries.RecordBaseline(const AProject: string; const AState: TAtlasBaselineState;
  const AUpdate: TAtlasBaselineUpdate; AAtUtc: TDateTime);
var
  mState: TAtlasBaselineState;
  mUpdate: TAtlasBaselineUpdate;
  mStamp: TDateTime;
begin
  if FStopped or (AProject = '') then
  begin
    Exit;
  end;
  mState := AState;
  mUpdate := AUpdate;
  mStamp := AAtUtc;
  TAtlasProjectSummaries.Update(Folder, AProject,
    procedure(var ASummary: TAtlasProjectSummary)
    begin
      TAtlasProjectBaselines.Updated(ASummary.Baseline, mUpdate, mState, mStamp);
    end);
  Changed(AProject);
end;

procedure TAtlasIdeProjectSummaries.SetHidden(const AProject: string; AHidden: Boolean);
var
  mHidden: Boolean;
begin
  if FStopped or (AProject = '') then
  begin
    Exit;
  end;
  mHidden := AHidden;
  // Nur der Bereich „Projekte“: Die Liste „Zuletzt geöffnet“ der IDE bleibt unverändert.
  TAtlasProjectSummaries.Update(Folder, AProject,
    procedure(var ASummary: TAtlasProjectSummary)
    begin
      ASummary.Hidden := mHidden;
    end);
  Changed(AProject);
end;

end.
