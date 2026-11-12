unit Atlas.IDE.CodeInsight.Manager.State;

// Zustand des Code Insight-Managers, unterste Stufe der Klassenkette State → Session → Commands →
// Crashes → Manager: Server, Sitzung, Phase für das Statusfeld (#591, #754), Abstürze (#1355), Haken der
// Kompositionswurzel und das Diagnoseprotokoll.

interface

uses
  System.SysUtils,
  System.Classes,
  Atlas.Core.Status.Lines,
  Atlas.Core.Diagnostics.ThreadList,
  Atlas.Core.Lsp.Client,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Lsp.Crashes,
  Atlas.Core.Lsp.CrashCases,
  Atlas.Core.Files.WatchedChanges,
  Atlas.Core.Signature.Contract,
  Atlas.Core.Notifications.Contract,
  Atlas.IDE.Completion.Editor,
  Atlas.IDE.CodeInsight.Manager.Editors;

type
  /// <summary>Adapter des Kerns, eingesetzt von der Kompositionswurzel.</summary>
  TAtlasCodeInsightAdapters = record
    /// <summary>Startet AtlasServer.exe; löst bei Fehlern EOSError aus.</summary>
    NewServer: TFunc<string, string, IAtlasLspServer>;
    NewFolderWatcher: TFunc<TAtlasWatchedChanges, IAtlasFolderWatcher>;
    NewCompletionSources: TAtlasCompletionSourcesFactory;
    NewSignatureSource: TFunc<TAtlasSessionFunc, IAtlasSignatureSource>;
    /// <summary>Code-Aktionen an der Schreibmarke öffnen wie Strg+. (Klick auf die Marke „braucht kein Self“,
    /// #686); nil = nur der Sprung.</summary>
    OpenCodeActions: TProc;
  end;

  /// <summary>Phase des Servers für das Statusfeld (#591) mit Beginn (Ortszeit) und „von Atlas beendet“ (#754).
  /// </summary>
  TAtlasServerPhaseState = record
    Phase: TAtlasServerPhase;
    Error: string;
    Since: TDateTime;
    Ended: Boolean;
  end;

  /// <summary>Zustand und Protokoll des Managers; die Stufen darüber starten die Sitzung, schicken Befehle,
  /// melden Abstürze und bedienen die IDE.</summary>
  TAtlasCodeInsightState = class(TInterfacedObject)
  protected
    FEnabled: Boolean;
    FAdapters: TAtlasCodeInsightAdapters;
    FServer: IAtlasLspServer;
    FSession: TLspSession;
    FLastError: string;
    FDiagnose: Boolean;
    FPhase: TAtlasServerPhaseState;
    /// <summary>StopSession läuft: Ein Ende des Prozesses jetzt ist kein Absturz.</summary>
    FStopping: Boolean;
    /// <summary>EnsureSession startet gerade (gegen Wiedereintritt über CheckSynchronize).</summary>
    FStarting: Boolean;
    /// <summary>Shutdown ist gelaufen: Sitzung, Threads und Editor-Anbindungen sind weg (#886).</summary>
    FShutDown: Boolean;
    FOnServerChanged: TProc;
    FOnOpenLog: TProc;
    FOnBugReport: TProc;
    FOnCrashIssue: TProc<TAtlasCrashCase>;
    /// <summary>Erfolgreiche Starts des Servers; ab dem zweiten meldet jeder „Server neu gestartet“ (#601).
    /// </summary>
    FStarts: Integer;
    /// <summary>Abstürze des Servers; nach zwei gleichen startet Atlas ihn nicht mehr still neu.</summary>
    FCrashes: TAtlasServerCrashes;
    /// <summary>Anfragen, die der Server gerade nach Absturz überspringt (#1355); nur im Hauptthread.</summary>
    FCrashSkips: TAtlasCrashSkips;
    /// <summary>Start der laufenden Sitzung; nach einem Absturz gilt ein Fall ab hier als dessen Ursache.</summary>
    FStartedAt: TDateTime;
    /// <summary>Vervollständigung, Parameter-Hint, Hover, Probleme, Inlay-Hints und Code Lens.</summary>
    FEditors: TAtlasCodeInsightEditors;
    /// <summary>Threads von Statusabfrage, Befehlen und Bedienbefehlen; Destroy wartet auf ihr Ende (#886).</summary>
    FThreads: TAtlasThreadList;
    procedure SetPhase(APhase: TAtlasServerPhase; const AError: string); overload;
    procedure SetPhase(APhase: TAtlasServerPhase; const AError: string; AEnded: Boolean); overload;
    /// <summary>OnServerChanged aufrufen, falls gesetzt; aus jedem Thread.</summary>
    procedure ServerChanged;
    /// <summary>Aktion „Protokoll öffnen“ für Einträge der Benachrichtigungszentrale (#601); leer ohne OnOpenLog.
    /// </summary>
    function LogActions: TArray<TAtlasNotificationAction>;
    procedure ReportError(const AMessage: string);
    procedure Diagnose(const AMessage: string);
    /// <summary>Server läuft und die Sitzung ist initialisiert, auch während StopSession.</summary>
    function ReadySession: TLspSession;
  public
    constructor Create(const AAdapters: TAtlasCodeInsightAdapters);
    destructor Destroy; override;
    /// <summary>Laufende, initialisierte Sitzung oder nil; startet keinen Server (#402).</summary>
    function RunningSession: TLspSession;
    /// <summary>Fortschritt des Servers ("Index 45 %"); '' ohne Sitzung oder Vorgang. Startet keinen Server
    /// (#492).</summary>
    function ServerProgress: string;
    /// <summary>Stand des Servers für das Statusfeld (#591); startet keinen Server.</summary>
    function ServerInfo: TAtlasServerInfo;
    /// <summary>Indizierung läuft? APercent = Fortschritt, -1 = unbekannt; False ohne Sitzung.</summary>
    function ServerIndexing(out APercent: Integer): Boolean;
    /// <summary>Wie ServerIndexing für den Vorgang AToken (ein Projekt der Gruppe, #2142).</summary>
    function ServerIndexingOf(const AToken: string; out APercent: Integer): Boolean;
    /// <summary>Zeile im Diagnoseprotokoll (nur mit Diagnose = 1).</summary>
    procedure Log(const AMessage: string);
    /// <summary>Zeile im Protokoll unabhängig von Diagnose, z. B. Hänger (#501).</summary>
    procedure Report(const AMessage: string);
    /// <summary>Phase, Version oder Fortschritt haben sich geändert; aus jedem Thread.</summary>
    property OnServerChanged: TProc read FOnServerChanged write FOnServerChanged;
    /// <summary>„Protokoll öffnen“ für die Einträge der Quelle Server in der Benachrichtigungszentrale (#601).
    /// </summary>
    property OnOpenLog: TProc read FOnOpenLog write FOnOpenLog;
    /// <summary>„Fehlerbericht erstellen…“ in der Meldung nach zwei gleichen Abstürzen des Servers.
    /// </summary>
    property OnBugReport: TProc read FOnBugReport write FOnBugReport;
    /// <summary>„Issue anlegen“ in der Meldung zu einem Absturzfall (#1355, Dialog aus #1268).</summary>
    property OnCrashIssue: TProc<TAtlasCrashCase> read FOnCrashIssue write FOnCrashIssue;
  end;

/// <summary>Ist AManager der lebende Manager? Späte Einträge im Hauptthread (applyEdit, Meldungen) tun sonst nichts.
/// </summary>
function ManagerLive(AManager: TObject): Boolean;
/// <summary>AManager ist abgebaut (Shutdown): ab jetzt nicht mehr lebend.</summary>
procedure RetireManager(AManager: TObject);

implementation

uses
  Atlas.UI.Strings,
  Atlas.UI.CodeInsight.Strings,
  Atlas.Core.Notifications.Center,
  Atlas.Core.Notifications.Sources,
  Atlas.IDE.CodeInsight.Manager.Paths,
  ToolsAPI;

var
  /// <summary>Lebender Manager; nach dem Abbau nil, damit späte applyEdit-Aufrufe nichts mehr tun.</summary>
  LiveManager: TObject;

function ManagerLive(AManager: TObject): Boolean;
begin
  Result := (AManager <> nil) and (LiveManager = AManager);
end;

procedure RetireManager(AManager: TObject);
begin
  if LiveManager = AManager then
  begin
    LiveManager := nil;
  end;
end;

{ TAtlasCodeInsightState }

constructor TAtlasCodeInsightState.Create(const AAdapters: TAtlasCodeInsightAdapters);
begin
  inherited Create;
  FAdapters := AAdapters;
  LiveManager := Self;
  FEnabled := True;
  FDiagnose := TAtlasCodeInsightPaths.DiagnoseEnabled;
  FPhase := Default(TAtlasServerPhaseState);
  FPhase.Phase := TAtlasServerPhase.NotStarted;
  FThreads := TAtlasThreadList.Create;
  FCrashes := TAtlasServerCrashes.Create(nil);
  FCrashSkips := TAtlasCrashSkips.Create;
end;

destructor TAtlasCodeInsightState.Destroy;
begin
  RetireManager(Self);
  FreeAndNil(FThreads);
  // Nach Shutdown: Kein Lese-Thread meldet mehr ein Ende.
  FreeAndNil(FCrashes);
  FreeAndNil(FCrashSkips);
  inherited;
end;

procedure TAtlasCodeInsightState.ServerChanged;
var
  mChanged: TProc;
begin
  mChanged := FOnServerChanged;
  if Assigned(mChanged) then
  begin
    mChanged();
  end;
end;

procedure TAtlasCodeInsightState.SetPhase(APhase: TAtlasServerPhase; const AError: string);
begin
  SetPhase(APhase, AError, False);
end;

procedure TAtlasCodeInsightState.SetPhase(APhase: TAtlasServerPhase; const AError: string; AEnded: Boolean);
begin
  // Ein beendeter Server bleibt beendet, bis er wieder startet; der Zeitpunkt bleibt der erste.
  if (APhase <> FPhase.Phase) or (AEnded <> FPhase.Ended) then
  begin
    FPhase.Since := Now;
  end;
  FPhase.Phase := APhase;
  FPhase.Error := AError;
  FPhase.Ended := (APhase = TAtlasServerPhase.Stopped) and AEnded;
  ServerChanged;
end;

function TAtlasCodeInsightState.LogActions: TArray<TAtlasNotificationAction>;
begin
  Result := nil;
  if Assigned(FOnOpenLog) then
  begin
    Result := [TAtlasNotificationCenter.Action(TAtlasStrings.Text(TAtlasTextId.StatusOpenLog), FOnOpenLog)];
  end;
end;

procedure TAtlasCodeInsightState.ReportError(const AMessage: string);
var
  mMessages: IOTAMessageServices;
  mMode: TAtlasNotificationMode;
begin
  Diagnose('Fehler: ' + AMessage);
  // Jede Meldung nur einmal, sonst flutet ein fehlender Server das Meldungsfenster.
  if AMessage = FLastError then
  begin
    Exit;
  end;
  FLastError := AMessage;
  // Benachrichtigungszentrale (#601): bei „nur sammeln“ oder „aus“ keine Zeile im Meldungsfenster.
  mMode := TAtlasNotificationCenter.Default.Notify(TAtlasNotificationSources.cServer,
    TAtlasNotificationSeverity.Error, TAtlasCodeInsightStrings.Text(TAtlasCodeInsightTextId.NotificationsServerError),
    AMessage,
    LogActions);
  if (mMode = TAtlasNotificationMode.Show) and Supports(BorlandIDEServices, IOTAMessageServices, mMessages) then
  begin
    mMessages.AddTitleMessage('Atlas: ' + AMessage);
  end;
end;

procedure TAtlasCodeInsightState.Diagnose(const AMessage: string);
begin
  // Diagnose darf die IDE nie stören.
  if FDiagnose then
  begin
    TAtlasCodeInsightPaths.Append(AMessage);
  end;
end;

procedure TAtlasCodeInsightState.Log(const AMessage: string);
begin
  Diagnose(AMessage);
end;

procedure TAtlasCodeInsightState.Report(const AMessage: string);
begin
  TAtlasCodeInsightPaths.Append(AMessage);
end;

function TAtlasCodeInsightState.ReadySession: TLspSession;
begin
  Result := nil;
  if (FServer <> nil) and FServer.Running and (FSession <> nil) and FSession.Initialized then
  begin
    Result := FSession;
  end;
end;

function TAtlasCodeInsightState.RunningSession: TLspSession;
begin
  Result := nil;
  // Während StopSession nie: Die Sitzung wird gleich freigegeben. Aus jedem Thread aufrufbar.
  if not FStopping then
  begin
    Result := ReadySession;
  end;
end;

function TAtlasCodeInsightState.ServerProgress: string;
begin
  Result := '';
  if (FSession <> nil) and FSession.Initialized then
  begin
    Result := FSession.ProgressText;
  end;
end;

function TAtlasCodeInsightState.ServerInfo: TAtlasServerInfo;
begin
  Result := Default(TAtlasServerInfo);
  Result.Phase := FPhase.Phase;
  Result.Error := FPhase.Error;
  Result.Since := FPhase.Since;
  Result.Ended := FPhase.Ended;
  Result.Version := '';
  Result.AverageMs := 0;
  Result.Samples := 0;
  if (FSession <> nil) and FSession.Initialized then
  begin
    Result.Version := FSession.ServerVersion;
  end;
  if FServer <> nil then
  begin
    Result.AverageMs := FServer.Client.AverageMs(Result.Samples);
  end;
  if (FCrashSkips <> nil) and (FPhase.Phase = TAtlasServerPhase.Running) then
  begin
    Result.Skipped := FCrashSkips.Count;
  end;
end;

function TAtlasCodeInsightState.ServerIndexing(out APercent: Integer): Boolean;
begin
  APercent := -1;
  Result := (FSession <> nil) and FSession.Initialized and FSession.Indexing(APercent);
end;

function TAtlasCodeInsightState.ServerIndexingOf(const AToken: string; out APercent: Integer): Boolean;
begin
  APercent := -1;
  Result := (FSession <> nil) and FSession.Initialized and FSession.IndexingOf(AToken, APercent);
end;

end.
