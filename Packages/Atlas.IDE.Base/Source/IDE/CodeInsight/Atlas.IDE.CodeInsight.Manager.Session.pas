unit Atlas.IDE.CodeInsight.Manager.Session;

// Sitzung des Code Insight-Managers, zweite Stufe der Klassenkette: Server starten und stoppen (A-01), Neustart
// nach Absturz (#393), Projektgruppe (#648): Die Sitzung meldet dem Server alle Projekte der Gruppe, das aktive
// zuerst; Änderungen der Gruppe prüft sie höchstens alle zwei Sekunden. Änderungen außerhalb der IDE (#395): Die
// Ordner der Projekte (Git-Arbeitsverzeichnis, sonst Projektordner) werden beobachtet; gesammelte Änderungen gehen
// bei der nächsten Anfrage als workspace/didChangeWatchedFiles an den Server. Projektkontext (#396): Konfiguration,
// Plattform und Optionen der Projekte gehen in initialize mit; Änderungen prüft die Sitzung höchstens einmal je
// Sekunde. workspace/applyEdit (#397) und window/showMessage (#121) übernimmt der Hauptthread. Typen der IDE: Beim
// Start jeder Sitzung gehen die Typen der geladenen Packages als atlas/ideTypes an den Server (auch ohne .pas).

interface

uses
  System.SyncObjs,
  Atlas.Core.Lsp.Client,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Files.WatchedChanges,
  Atlas.IDE.CodeInsight.Manager.State;

type
  /// <summary>Start, Stopp und Abgleich der Sitzung mit Projektgruppe, Projektkontext und Dateien.</summary>
  TAtlasCodeInsightSession = class(TAtlasCodeInsightState)
  protected
    // Ob AtlasServer.exe da ist, höchstens alle paar Sekunden neu geprüft.
    FServerChecked: Cardinal;
    FServerFound: Boolean;
    // Zuletzt geprüfte Projektgruppe (#648).
    FProjectsChecked: Cardinal;
    /// <summary>Zuletzt geprüfter Projektkontext (#396).</summary>
    FContextsChecked: Cardinal;
    /// <summary>Änderungen außerhalb der IDE (#395).</summary>
    FFileChanges: TAtlasWatchedChanges;
    FFolderWatcher: IAtlasFolderWatcher;
    /// <summary>Signale „keine Statusabfrage“, „kein Befehl“ und „kein Bedienbefehl“ im Hintergrund; StopSession
    /// wartet auf sie.</summary>
    FQueryIdle: TEvent;
    FCommandIdle: TEvent;
    FServerCommandsIdle: TEvent;
    /// <summary>Laufende Sitzung oder Start im Hauptthread; außerhalb des Hauptthreads nur, was schon läuft (A-01).</summary>
    function EnsureSession: Boolean;
    /// <summary>Server starten und Sitzung aufbauen; nur aus EnsureSession, nur im Hauptthread.</summary>
    function StartSession: Boolean;
    /// <summary>Server starten; sein Ende färbt das Statusfeld sofort (#591).</summary>
    procedure ConnectServer(const APath, AArguments: string);
    /// <summary>Sitzung auf dem neuen Server anlegen und initialisieren; ADocuments wieder öffnen (#393).</summary>
    procedure OpenSession(const ADocuments: TArray<TLspOpenDocument>);
    /// <summary>Eintrag „Server neu gestartet“ ab dem zweiten Start (#601).</summary>
    procedure NotifyRestart(ACrashed: Boolean; APreviousStart: TDateTime; AReopened: Integer);
    /// <summary>Projekte der geöffneten Gruppe, aktives zuerst; leer ohne Gruppe (#648).</summary>
    class function GroupProjects: TArray<string>; static;
    procedure RefreshProjects;
    /// <summary>Meldet geänderte Projektkontexte (#396); höchstens einmal je Sekunde (Hauptthread).</summary>
    procedure RefreshContexts;
    /// <summary>Typen der geladenen Packages an die Sitzung (atlas/ideTypes, Hauptthread).</summary>
    procedure SendIdeTypes;
    /// <summary>Beobachtet die Ordner dieser Projekte (#395).</summary>
    procedure WatchProjects(const AProjects: TArray<string>);
    /// <summary>Gesammelte Änderungen außerhalb der IDE an den Server (Hauptthread, #395).</summary>
    procedure FlushFileChanges;
    procedure StopSession;
    procedure StopSessionNow;
    /// <summary>Meldungen der neuen Sitzung annehmen: workspace/applyEdit und window/showMessage.</summary>
    procedure AcceptNotifications(ASession: TLspSession); virtual;
    /// <summary>Nimmt workspace/applyEdit der Sitzung an (#397).</summary>
    procedure AcceptApplyEdit(ASession: TLspSession);
    /// <summary>Warnungen und Fehler des Servers (window/showMessage) ins Meldungsfenster (#121).</summary>
    procedure AcceptShowMessage(ASession: TLspSession);
    /// <summary>Der Server endete von selbst (Lese-Thread).</summary>
    procedure ServerEnded(const AInfo: TLspCloseInfo); virtual;
    function SessionOrNil: TLspSession;
    /// <summary>Gibt es den Server? Ohne ihn übernimmt die eingebaute Code Insight.</summary>
    function ServerAvailable: Boolean;
    /// <summary>Bedient Atlas diese Datei? Wie HandlesFile, aber ohne Diagnosezeile.</summary>
    function Handles(const AFileName: string): Boolean;
  public
    constructor Create(const AAdapters: TAtlasCodeInsightAdapters);
    destructor Destroy; override;
    /// <summary>Laufende Sitzung, Server bei Bedarf gestartet; nil, wenn er nicht startet (Hauptthread).</summary>
    function ActiveSession: TLspSession;
    /// <summary>„Server neu starten“ (#591, #393): Sitzung beenden und neu starten; hebt das Anhalten nach
    /// Abstürzen auf (AllowStart).</summary>
    function RestartServer: Boolean;
    /// <summary>Start von Hand („Server starten“): Nach zwei gleichen Abstürzen startet Atlas den Server wieder
    /// (Bericht H5).</summary>
    procedure AllowStart;
    /// <summary>Neustarts des Servers in dieser Sitzung (Starts nach dem ersten; Fenster „Atlas-Server“, #1356).
    /// </summary>
    function ServerRestarts: Integer;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  ToolsAPI,
  Atlas.Core.Status.Lines,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.TimeLimit,
  Atlas.Core.Diagnostics.Shutdown,
  Atlas.Core.Lsp.WorkspaceEdits,
  Atlas.Core.Projects.Contract,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Projects.Context,
  Atlas.IDE.Outline.Cache,
  Atlas.IDE.CodeInsight.Manager.Paths,
  Atlas.IDE.CodeInsight.Manager.Handlers,
  Atlas.IDE.CodeInsight.IdeTypes,
  Atlas.Core.Lsp.IdeTypes,
  System.Diagnostics,
  Atlas.Core.Localization.Language;

{$SCOPEDENUMS ON}

type
  /// <summary>Benutzertexte dieser Unit (#1458).</summary>
  TSessionText = (ServerNotFoundTheBuilt, ServerNotFound, AtlasServerExeNotFound);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TAtlasLanguage, TSessionText] of string = (
    ('Server nicht gefunden: %s (die eingebaute Code Insight bleibt aktiv)',
     'Server nicht gefunden: %s',
     'AtlasServer.exe nicht gefunden'),
    ('Server not found: %s (the built-in Code Insight stays active)',
     'Server not found: %s',
     'AtlasServer.exe not found'));

/// <summary>Text AId in der Sprache der Oberfläche.</summary>
function UiText(AId: TSessionText): string;
begin
  Result := cTexts[TAtlasTextLanguage.Current, AId];
end;

constructor TAtlasCodeInsightSession.Create(const AAdapters: TAtlasCodeInsightAdapters);
begin
  inherited Create(AAdapters);
  FQueryIdle := TEvent.Create(nil, True, True, '');
  FCommandIdle := TEvent.Create(nil, True, True, '');
  FServerCommandsIdle := TEvent.Create(nil, True, True, '');
  Diagnose('Plugin geladen: ' + GetModuleName(HInstance));
  FFileChanges := TAtlasWatchedChanges.Create;
  FFolderWatcher := FAdapters.NewFolderWatcher(FFileChanges);
end;

destructor TAtlasCodeInsightSession.Destroy;
begin
  // Hält die Beobachter-Threads an; erst danach darf der Sammler weg (Shutdown hat beides meist schon getan).
  FFolderWatcher := nil;
  FreeAndNil(FFileChanges);
  // Erst die Threads: Sie nutzen die Ereignisse bis zuletzt.
  FreeAndNil(FThreads);
  FreeAndNil(FQueryIdle);
  FreeAndNil(FCommandIdle);
  FreeAndNil(FServerCommandsIdle);
  inherited;
end;

procedure TAtlasCodeInsightSession.StopSession;
begin
  // Nur im Hauptthread (A-01); verschachtelt (CheckSynchronize beim Warten) nichts tun.
  if not TAtlasMainThread.IsMain or FStopping then
  begin
    Exit;
  end;
  FStopping := True;
  try
    StopSessionNow;
  finally
    FStopping := False;
  end;
end;

procedure TAtlasCodeInsightSession.StopSessionNow;
begin
  Assert(TAtlasMainThread.IsMain, 'StopSessionNow außerhalb des Hauptthreads');
  if FEditors <> nil then
  begin
    FEditors.BeginStop;
  end;
  if FSession <> nil then
  begin
    FSession.SetOnProgress(nil);
  end;
  if FServer <> nil then
  begin
    FServer.Client.Close;
  end;
  if FEditors <> nil then
  begin
    FEditors.EndStop;
  end;
  // Eine Statusabfrage im Hintergrund kehrt nach Close sofort zurück (#591), ebenso ein Befehl (#66).
  FQueryIdle.WaitFor(5000);
  // Aufgegebene Zeitlimit-Arbeiter können noch in Prepare bzw. Sync der Sitzung stecken (A-01, A-13).
  if not TAtlasTimeLimit.WaitIdle(TAtlasShutdown.StopMs) then
  begin
    Diagnose('Sitzung beendet, während ein Zeitlimit-Arbeiter noch lief');
  end;
  FCommandIdle.WaitFor(5000);
  FServerCommandsIdle.WaitFor(5000);
  FreeAndNil(FSession);
  FServer := nil;
end;

function TAtlasCodeInsightSession.ServerRestarts: Integer;
begin
  Result := AtomicCmpExchange(FStarts, 0, 0) - 1;
  if Result < 0 then
  begin
    Result := 0;
  end;
end;

function TAtlasCodeInsightSession.RestartServer: Boolean;
begin
  Report('Server wird neu gestartet');
  AllowStart;
  StopSession;
  SetPhase(TAtlasServerPhase.Stopped, '', True);
  Result := EnsureSession;
end;

procedure TAtlasCodeInsightSession.AllowStart;
begin
  if FCrashes.Held then
  begin
    TAtlasGuard.Log('Server: Start von Hand nach wiederholtem Absturz');
  end;
  FCrashes.Reset;
end;

procedure TAtlasCodeInsightSession.ServerEnded(const AInfo: TLspCloseInfo);
begin
end;

function TAtlasCodeInsightSession.EnsureSession: Boolean;
var
  mMain: Boolean;
begin
  // Start und Stopp gehören dem Hauptthread (A-01): Zeitlimit-Arbeiter, Lese-Thread und Hintergrund-Threads
  // bekommen nur, was schon läuft. Abgebaut, aber von der IDE noch gehalten (#886): im Hauptthread keinen Server
  // mehr. Verschachtelt aus StopSession oder StartSession (Warten auf Threads arbeitet eingereihte Aufrufe ab):
  // weder neu starten noch die gleich freigegebene Sitzung herausgeben.
  mMain := TAtlasMainThread.IsMain;
  if not mMain or FShutDown or FStopping or FStarting then
  begin
    Exit((RunningSession <> nil) and not (mMain and FShutDown));
  end;
  if ReadySession <> nil then
  begin
    RefreshContexts;
    RefreshProjects;
    FlushFileChanges;
    Exit(True);
  end;
  // Zweimal gleich abgestürzt (Bericht H5): kein stiller Neustart; „Server neu starten“ hebt das auf.
  Result := False;
  if not FCrashes.Held then
  begin
    FStarting := True;
    try
      Result := StartSession;
    finally
      FStarting := False;
    end;
  end;
end;

function TAtlasCodeInsightSession.StartSession: Boolean;
var
  mPath, mArguments: string;
  mDocuments: TArray<TLspOpenDocument>;
  mCrashed: Boolean;
  mPreviousStart: TDateTime;
begin
  // Vom Server selbst beendet (nicht von Atlas): für den Eintrag „Server neu gestartet“ (#601).
  mCrashed := (FPhase.Phase = TAtlasServerPhase.Stopped) and not FPhase.Ended;
  mPreviousStart := FStartedAt;
  // Der neue Server meldet nach initialized, was er weiter überspringt (#1355).
  if FCrashSkips.Count > 0 then
  begin
    FCrashSkips.Clear;
    TAtlasServerHandlers.UpdateCrashProblems(FCrashSkips);
  end;
  // Abgestürzter oder hängender Server: Was die alte Sitzung abgeglichen hatte, bekommt der neue Server sofort
  // wieder, nicht erst bei der nächsten Anfrage je Datei (#393).
  mDocuments := nil;
  if FSession <> nil then
  begin
    mDocuments := FSession.OpenDocuments;
  end;
  StopSession;
  mPath := TAtlasCodeInsightPaths.ServerPath(mArguments);
  Diagnose('Starte Server: ' + mPath);
  if not FileExists(mPath) then
  begin
    ReportError(Format(UiText(TSessionText.ServerNotFound), [mPath]));
    SetPhase(TAtlasServerPhase.Failed, UiText(TSessionText.AtlasServerExeNotFound));
    Exit(False);
  end;
  SetPhase(TAtlasServerPhase.Starting, '');
  try
    ConnectServer(mPath, mArguments);
    OpenSession(mDocuments);
    FLastError := '';
    FStartedAt := Now;
    SetPhase(TAtlasServerPhase.Running, '');
    Result := True;
    // Jeder weitere Start ist ein Neustart (#393).
    Inc(FStarts);
    if FStarts > 1 then
    begin
      NotifyRestart(mCrashed, mPreviousStart, Length(mDocuments));
    end;
  except
    on E: Exception do
    begin
      ReportError('Start fehlgeschlagen: ' + E.Message);
      StopSession;
      SetPhase(TAtlasServerPhase.Failed, TAtlasCodeInsightPaths.WithoutPaths(E.Message));
      Result := False;
    end;
  end;
end;

procedure TAtlasCodeInsightSession.ConnectServer(const APath, AArguments: string);
var
  mClient: TLspClient;
begin
  FServer := FAdapters.NewServer(APath, AArguments);
  mClient := FServer.Client;
  // Ende des Prozesses (z. B. im Task-Manager beendet) färbt das Statusfeld sofort rot (#591).
  mClient.OnClosed :=
    procedure
    var
      mEnded: Boolean;
    begin
      // Während StopSession beendet Atlas den Server selbst; sonst ist er abgestürzt (#754).
      mEnded := FStopping;
      SetPhase(TAtlasServerPhase.Stopped, '', mEnded);
      // Erst danach: Die Ursache aus ServerEnded setzt der Hauptthread nur auf einen abgestürzten Server.
      if not mEnded then
      begin
        ServerEnded(mClient.CloseInfo);
      end;
    end;
end;

procedure TAtlasCodeInsightSession.OpenSession(const ADocuments: TArray<TLspOpenDocument>);
var
  mProjects: TArray<string>;
begin
  FSession := TLspSession.Create(FServer.Client);
  // Sprache der Oberfläche (#1458): Befunde, Code-Aktionen und Hover wie die Oberfläche; ohne "language" in
  // settings.json entscheidet allein diese Angabe.
  FSession.InitializeOptions := TLspInitializeOptions.ForLocale(TAtlasTextLanguage.Code);
  Diagnose('initialize mit locale ' + TAtlasTextLanguage.Code);
  FContextsChecked := 0;
  RefreshContexts;
  AcceptNotifications(FSession);
  mProjects := GroupProjects;
  FSession.SetProjects(mProjects);
  WatchProjects(mProjects);
  // Server-Einstellungen liest der Server selbst aus settings.json und atlas.json; das Plugin schickt keine.
  FSession.SetOnProgress(
    procedure
    begin
      ServerChanged;
    end);
  FProjectsChecked := GetTickCount;
  FSession.Initialize;
  SendIdeTypes;
  if ADocuments <> nil then
  begin
    FSession.Reopen(ADocuments);
    Diagnose(Format('Nach Neustart erneut geöffnet: %d Dateien', [Length(ADocuments)]));
  end;
end;

procedure TAtlasCodeInsightSession.NotifyRestart(ACrashed: Boolean; APreviousStart: TDateTime; AReopened: Integer);
var
  mRestart: TAtlasServerRestart;
begin
  mRestart := Default(TAtlasServerRestart);
  mRestart.Crashed := ACrashed;
  mRestart.CodeKnown := ACrashed and FCrashes.LastCode(mRestart.Code);
  mRestart.PreviousStart := APreviousStart;
  mRestart.Reopened := AReopened;
  mRestart.LogActions := LogActions;
  mRestart.CrashIssue := FOnCrashIssue;
  TAtlasServerHandlers.NotifyRestarted(mRestart);
end;

/// <summary>Ist AFileName ein gespeichertes Delphi-Projekt? Neue, noch namenlose Projekte haben keinen Ordner.
/// </summary>
function SavedProject(const AFileName: string): Boolean;
begin
  Result := SameText(ExtractFileExt(AFileName), '.dproj') and FileExists(AFileName);
end;

class function TAtlasCodeInsightSession.GroupProjects: TArray<string>;
var
  mModules: IOTAModuleServices;
  mGroup: IOTAProjectGroup;
  mActive: string;
  mIndex: Integer;
  mFileName: string;
begin
  Result := nil;
  mGroup := nil;
  if Supports(BorlandIDEServices, IOTAModuleServices, mModules) then
  begin
    mGroup := mModules.MainProjectGroup;
  end;
  if mGroup = nil then
  begin
    Exit;
  end;
  mActive := '';
  if mGroup.ActiveProject <> nil then
  begin
    mActive := mGroup.ActiveProject.FileName;
  end;
  if (mActive <> '') and SavedProject(mActive) then
  begin
    Result := [mActive];
  end;
  for mIndex := 0 to mGroup.ProjectCount - 1 do
  begin
    mFileName := mGroup.Projects[mIndex].FileName;
    if SavedProject(mFileName) and not SameText(mFileName, mActive) then
    begin
      Result := Result + [mFileName];
    end;
  end;
end;

procedure TAtlasCodeInsightSession.AcceptNotifications(ASession: TLspSession);
begin
  AcceptApplyEdit(ASession);
  AcceptShowMessage(ASession);
end;

procedure TAtlasCodeInsightSession.AcceptApplyEdit(ASession: TLspSession);
var
  mManager: TAtlasCodeInsightSession;
begin
  mManager := Self;
  ASession.OnApplyEdit :=
    procedure(const AEdit: TLspWorkspaceEdit; const AReply: TLspApplyEditReply)
    begin
      // Lese-Thread: Open Tools API nur im Hauptthread. Atlas gehört der Eintrag: beim Entladen verworfen
      // (Code-Review A-02); ohne Antwort gibt die Sitzung die Id frei (S-07).
      TAtlasMainThread.Queue(TAtlasFeature.EditorCommands,
        procedure
        var
          mApplied: Boolean;
          mReason: string;
        begin
          // Manager weg oder neue Sitzung: Die alte Verbindung gibt es nicht mehr, nicht antworten.
          if not ManagerLive(mManager) or (mManager.FSession <> ASession) then
          begin
            Exit;
          end;
          mApplied := TAtlasServerHandlers.ApplyEdit(AEdit,
            procedure(AMessage: string)
            begin
              mManager.Diagnose(AMessage);
            end, mReason);
          // Genau eine Antwort, auch nach einer Ausnahme (S-05).
          AReply(mApplied, mReason);
        end);
    end;
end;

procedure TAtlasCodeInsightSession.AcceptShowMessage(ASession: TLspSession);
var
  mManager: TAtlasCodeInsightSession;
begin
  mManager := Self;
  ASession.OnShowMessage :=
    procedure(AType: Integer; const AMessage: string)
    begin
      // Information und Protokoll gehören ins Diagnoseprotokoll, nicht ins Meldungsfenster.
      if AType > 2 then
      begin
        Exit;
      end;
      TAtlasMainThread.Queue(TAtlasFeature.Server,
        procedure
        begin
          if ManagerLive(mManager) and (mManager.FSession = ASession) then
          begin
            mManager.Diagnose('window/showMessage: ' + AMessage);
            TAtlasServerHandlers.ServerMessage(AType, AMessage, mManager.LogActions);
          end;
        end);
    end;
end;

procedure TAtlasCodeInsightSession.RefreshProjects;
var
  mProjects: TArray<string>;
begin
  // Open Tools API nur im Hauptthread.
  if (GetCurrentThreadId <> MainThreadID) or (GetTickCount - FProjectsChecked < 2000) then
  begin
    Exit;
  end;
  FProjectsChecked := GetTickCount;
  try
    mProjects := GroupProjects;
    FSession.SetProjects(mProjects);
    WatchProjects(mProjects);
  except
    on E: Exception do
    begin
      Diagnose('Projektgruppe nicht gemeldet: ' + E.Message);
    end;
  end;
end;

procedure TAtlasCodeInsightSession.RefreshContexts;
var
  mContext: TAtlasProjectContext;
  mChanged: TArray<TAtlasProjectContext>;
begin
  // Open Tools API nur im Hauptthread.
  if (GetCurrentThreadId <> MainThreadID) or
    ((FContextsChecked <> 0) and (GetTickCount - FContextsChecked < 1000)) then
  begin
    Exit;
  end;
  FContextsChecked := GetTickCount;
  try
    // Mit Diagnose=1 prüfbar, ob die geerbten Optionen ankommen (#396).
    mChanged := FSession.SetProjectContexts(TAtlasIdeProjectContext.Group);
    for mContext in mChanged do
    begin
      Diagnose('Projektkontext: ' + mContext.Describe);
    end;
    // Andere Plattform oder Konfiguration: andere aktive {$IFDEF}-Zweige, Gliederung neu holen (#845).
    if Length(mChanged) > 0 then
    begin
      TAtlasIdeOutlineCache.InvalidateAll;
    end;
  except
    on E: Exception do
    begin
      Diagnose('Projektkontext nicht gemeldet: ' + E.Message);
    end;
  end;
end;

procedure TAtlasCodeInsightSession.SendIdeTypes;
var
  mWatch: TStopwatch;
  mTypes: TArray<TAtlasIdeType>;
  mFailed: Integer;
begin
  try
    mWatch := TStopwatch.StartNew;
    mTypes := TAtlasIdeTypeCollector.Collect(mFailed);
    // Nach Initialize: Der Server ersetzt mit jeder Meldung den ganzen Stand und prüft offene Dateien neu.
    FSession.Notify(TAtlasIdeTypes.Method, TAtlasIdeTypes.ToJson(mTypes));
    Diagnose(Format('IDE-Typen: %d, %d ms, RTTI unlesbar: %d', [Length(mTypes), mWatch.ElapsedMilliseconds,
      mFailed]));
  except
    on E: Exception do
    begin
      Diagnose('IDE-Typen: ' + E.Message);
    end;
  end;
end;

procedure TAtlasCodeInsightSession.WatchProjects(const AProjects: TArray<string>);
begin
  try
    FFolderWatcher.SetRoots(TAtlasWatchedChanges.Roots(AProjects,
      function(const APath: string): Boolean
      begin
        // .git ist ein Ordner, in Worktrees und Submodulen eine Datei.
        Result := DirectoryExists(APath) or FileExists(APath);
      end));
  except
    on E: Exception do
    begin
      Diagnose('Ordner nicht beobachtet: ' + E.Message);
    end;
  end;
end;

procedure TAtlasCodeInsightSession.FlushFileChanges;
var
  mChanges: TArray<TAtlasFileChange>;
begin
  if GetCurrentThreadId <> MainThreadID then
  begin
    Exit;
  end;
  mChanges := FFileChanges.Take(GetTickCount);
  if mChanges = nil then
  begin
    Exit;
  end;
  try
    FSession.FilesChanged(mChanges);
    Diagnose(Format('Änderungen außerhalb der IDE gemeldet: %d Dateien', [Length(mChanges)]));
  except
    on E: Exception do
    begin
      Diagnose('Änderungen außerhalb der IDE nicht gemeldet: ' + E.Message);
    end;
  end;
end;

function TAtlasCodeInsightSession.SessionOrNil: TLspSession;
begin
  Result := nil;
  if EnsureSession then
  begin
    Result := FSession;
  end;
end;

function TAtlasCodeInsightSession.ActiveSession: TLspSession;
begin
  Result := SessionOrNil;
end;

function TAtlasCodeInsightSession.ServerAvailable: Boolean;
var
  mArguments, mPath: string;
begin
  if (FServerChecked = 0) or (GetTickCount - FServerChecked > 5000) then
  begin
    FServerChecked := GetTickCount;
    mPath := TAtlasCodeInsightPaths.ServerPath(mArguments);
    FServerFound := FileExists(mPath);
    if not FServerFound then
    begin
      ReportError(Format(UiText(TSessionText.ServerNotFoundTheBuilt), [mPath]));
    end;
  end;
  Result := FServerFound;
end;

function TAtlasCodeInsightSession.Handles(const AFileName: string): Boolean;
var
  mExtension: string;
begin
  // Nach Shutdown (abgemeldet, die IDE hält den Manager noch): nichts mehr übernehmen (#886).
  Result := False;
  if FShutDown then
  begin
    Exit;
  end;
  mExtension := LowerCase(ExtractFileExt(AFileName));
  // Hauptschalter (#407): ausgeschaltet übernimmt die eingebaute Code Insight; ebenso ohne Server.
  Result := TAtlasIdeSettings.Current.Enabled and not TAtlasGuard.Disabled(TAtlasFeature.Completion) and
    ((mExtension = '.pas') or (mExtension = '.dpr') or (mExtension = '.dpk') or (mExtension = '.inc')) and
    ServerAvailable;
end;

initialization
  TAtlasTextLanguage.AddTable('Atlas.IDE.CodeInsight.Manager.Session', cTexts[TAtlasLanguage.German], cTexts[TAtlasLanguage.English]);

end.
