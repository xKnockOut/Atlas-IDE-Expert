unit Atlas.IDE.CodeInsight.Manager.Crashes;

// Abstürze des Servers im Code Insight-Manager, vierte Stufe der Klassenkette. Ende des Servers: Endet
// er von selbst, steht in atlas.log, womit (Exit-Code, etwa Stapelüberlauf), nach welcher Laufzeit, bei welcher
// Anfrage und wie viel er auf stderr schrieb; das Statusfeld nennt die Ursache. Den ersten Absturz startet die
// nächste Anfrage wie bisher neu. Endet er zweimal mit demselben Code innerhalb von zehn Minuten, startet Atlas ihn
// nicht mehr still neu, sondern meldet es mit „Server neu starten“ und „Fehlerbericht erstellen…“
// (TAtlasServerCrashes). Ein Start von Hand hebt das auf.
// Absturzfälle (#1355): Der Server sichert jeden Absturz einer Anfrage als Fall und meldet ihn mit atlas/crashCase;
// stirbt er dabei, sucht der Neustart den jüngsten Fall seit dem letzten Start. Die Meldung nennt Methode, Datei,
// Zeile und Ausnahme, mit „Fall öffnen“, „Issue anlegen“ (OnCrashIssue) und „Ausblenden“. Übersprungene Anfragen
// (atlas/crashSkip, Sicherheitsnetz) zählt ServerInfo.Skipped für die Statusleiste; das Prüffenster zeigt sie als
// Warnung an der Datei, die Meldung bietet „Erneut versuchen“.

interface

uses
  System.SysUtils,
  Atlas.Core.Lsp.Client,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Lsp.CrashCases,
  Atlas.IDE.CodeInsight.Manager.Commands;

type
  /// <summary>Ende und Abstürze des Servers, Absturzfälle und übersprungene Anfragen.</summary>
  TAtlasCodeInsightCrashes = class(TAtlasCodeInsightCommands)
  protected
    /// <summary>Der Server endete von selbst (Lese-Thread): Ursache, Laufzeit und letzte Anfrage
    /// ins Protokoll, Ursache ins Statusfeld; nach zwei gleichen Abstürzen anhalten (ServerHeld).</summary>
    procedure ServerEnded(const AInfo: TLspCloseInfo); override;
    /// <summary>Hauptthread: Statusfeld und Benachrichtigung mit Neustart und Fehlerbericht.</summary>
    procedure ServerHeld(ACode: Cardinal);
    /// <summary>Hauptthread nach ServerEnded: anhalten oder die Ursache ins Statusfeld.</summary>
    procedure ServerEndedMain(ACode: Cardinal; AContinues: Boolean);
    procedure AcceptNotifications(ASession: TLspSession); override;
    /// <summary>atlas/crashCase und atlas/crashSkip (#1355) in den Hauptthread; atlas/ideMembersWanted an
    /// QueueIdeMembers.</summary>
    procedure AcceptAtlasNotifications(ASession: TLspSession);
    /// <summary>Fall oder übersprungene Anfrage im Hauptthread melden, solange ASession die Sitzung ist.</summary>
    procedure QueueCrashCase(ASession: TLspSession; const ACase: TAtlasCrashCase);
    procedure QueueCrashSkip(ASession: TLspSession; const ASkip: TAtlasCrashSkip);
    procedure CrashCaseSaved(const ACase: TAtlasCrashCase);
    procedure CrashSkipChanged(const ASkip: TAtlasCrashSkip);
    /// <summary>„Erneut versuchen“ einer übersprungenen Anfrage an AUri.</summary>
    function RetryAction(const AUri: string): TProc;
  end;

implementation

uses
  System.JSON,
  Atlas.UI.Strings,
  Atlas.UI.CodeInsight.Strings,
  Atlas.Core.Status.Lines,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Lsp.Crashes,
  Atlas.Core.Lsp.IdeMembers,
  Atlas.Core.Notifications.Contract,
  Atlas.Core.Notifications.Center,
  Atlas.Core.Notifications.Sources,
  Atlas.IDE.CodeInsight.Manager.State,
  Atlas.IDE.CodeInsight.Manager.Handlers;

procedure TAtlasCodeInsightCrashes.ServerEnded(const AInfo: TLspCloseInfo);
var
  mManager: TAtlasCodeInsightCrashes;
  mCode: Cardinal;
  mLine: string;
  mContinues: Boolean;
begin
  mCode := TAtlasServerExits.cUnknown;
  if AInfo.ExitKnown then
  begin
    mCode := AInfo.ExitCode;
  end;
  mLine := TAtlasServerExits.Line(mCode, AInfo.RuntimeMs, AInfo.LastMethod, AInfo.OpenMethods, AInfo.ErrorLines);
  // atlas.log für den Fehlerbericht, das Diagnoseprotokoll für den zeitlichen Zusammenhang mit den Aufrufen.
  TAtlasGuard.Log(mLine);
  Report(mLine);
  mContinues := FCrashes.Crashed(mCode);
  if not mContinues then
  begin
    TAtlasGuard.Log(Format('Server: zweimal %s innerhalb von %d min, kein weiterer Start ohne Zutun',
      [TAtlasServerExits.Describe(mCode), TAtlasServerCrashes.cWindowMinutes]));
  end;
  mManager := Self;
  // Statusfeld und Benachrichtigung im Hauptthread: Der Fehlertext der Phase ist ein String, den der Hauptthread
  // liest.
  TAtlasMainThread.Queue(TAtlasFeature.Server,
    procedure
    begin
      if ManagerLive(mManager) then
      begin
        mManager.ServerEndedMain(mCode, mContinues);
      end;
    end);
end;

procedure TAtlasCodeInsightCrashes.ServerEndedMain(ACode: Cardinal; AContinues: Boolean);
begin
  if not AContinues then
  begin
    ServerHeld(ACode);
  end
  // Inzwischen neu gestartet oder von Atlas beendet: Die Ursache gehört nicht mehr ins Statusfeld.
  else if (FPhase.Phase = TAtlasServerPhase.Stopped) and not FPhase.Ended then
  begin
    SetPhase(TAtlasServerPhase.Stopped, TAtlasServerExits.Describe(ACode));
  end;
end;

procedure TAtlasCodeInsightCrashes.ServerHeld(ACode: Cardinal);
var
  mManager: TAtlasCodeInsightCrashes;
  mActions: TArray<TAtlasNotificationAction>;
  mCause: string;
begin
  // Von Hand neu gestartet, bevor dieser Eintrag dran war: nichts mehr zu melden.
  if not FCrashes.Held then
  begin
    Exit;
  end;
  mCause := TAtlasServerExits.Describe(ACode);
  SetPhase(TAtlasServerPhase.Stopped, TAtlasCodeInsightStrings.Fmt(TAtlasCodeInsightTextId.ServerHeldPhase, [mCause]));
  mManager := Self;
  mActions := [TAtlasNotificationCenter.Action(TAtlasStrings.Text(TAtlasTextId.StatusRestartServer),
    procedure
    begin
      if ManagerLive(mManager) then
      begin
        mManager.RestartServer;
      end;
    end)];
  if Assigned(FOnBugReport) then
  begin
    mActions := mActions + [TAtlasNotificationCenter.Action(TAtlasStrings.Text(TAtlasTextId.BugReportMenu),
      FOnBugReport)];
  end;
  mActions := mActions + LogActions;
  TAtlasNotificationCenter.Default.Notify(TAtlasNotificationSources.cServer, TAtlasNotificationSeverity.Error,
    TAtlasCodeInsightStrings.Text(TAtlasCodeInsightTextId.ServerHeldTitle),
    TAtlasCodeInsightStrings.Fmt(TAtlasCodeInsightTextId.ServerHeldText, [mCause, TAtlasServerCrashes.cWindowMinutes]),
    mActions);
end;

procedure TAtlasCodeInsightCrashes.AcceptNotifications(ASession: TLspSession);
begin
  inherited AcceptNotifications(ASession);
  AcceptAtlasNotifications(ASession);
end;

procedure TAtlasCodeInsightCrashes.AcceptAtlasNotifications(ASession: TLspSession);
var
  mManager: TAtlasCodeInsightCrashes;
begin
  mManager := Self;
  ASession.OnAtlasNotification :=
    procedure(const AMethod: string; const AParams: TJSONValue)
    var
      mCase: TAtlasCrashCase;
      mSkip: TAtlasCrashSkip;
    begin
      // Im Lese-Thread lesen: AParams gehört dem Aufrufer und lebt nicht bis in den Hauptthread.
      if AMethod = TAtlasCrashCases.cCaseNotification then
      begin
        if TAtlasCrashCases.ParseCase(AParams, mCase) then
        begin
          mManager.QueueCrashCase(ASession, mCase);
        end;
      end
      else if AMethod = TAtlasIdeMembers.cWantedMethod then
      begin
        mManager.QueueIdeMembers(ASession, TAtlasIdeMembers.WantedUnits(AParams));
      end
      else if (AMethod = TAtlasCrashCases.cSkipNotification) and TAtlasCrashCases.ParseSkip(AParams, mSkip) then
      begin
        mManager.QueueCrashSkip(ASession, mSkip);
      end;
    end;
end;

procedure TAtlasCodeInsightCrashes.QueueCrashCase(ASession: TLspSession; const ACase: TAtlasCrashCase);
var
  mManager: TAtlasCodeInsightCrashes;
  mCase: TAtlasCrashCase;
begin
  mManager := Self;
  mCase := ACase;
  TAtlasMainThread.Queue(TAtlasFeature.Server,
    procedure
    begin
      if ManagerLive(mManager) and (mManager.FSession = ASession) then
      begin
        mManager.CrashCaseSaved(mCase);
      end;
    end);
end;

procedure TAtlasCodeInsightCrashes.QueueCrashSkip(ASession: TLspSession; const ASkip: TAtlasCrashSkip);
var
  mManager: TAtlasCodeInsightCrashes;
  mSkip: TAtlasCrashSkip;
begin
  mManager := Self;
  mSkip := ASkip;
  TAtlasMainThread.Queue(TAtlasFeature.Server,
    procedure
    begin
      if ManagerLive(mManager) and (mManager.FSession = ASession) then
      begin
        mManager.CrashSkipChanged(mSkip);
      end;
    end);
end;

procedure TAtlasCodeInsightCrashes.CrashCaseSaved(const ACase: TAtlasCrashCase);
begin
  Diagnose('Absturzfall gesichert: ' + ACase.Summary);
  TAtlasNotificationCenter.Default.Notify(TAtlasNotificationSources.cServer, TAtlasNotificationSeverity.Warning,
    TAtlasCodeInsightStrings.Text(TAtlasCodeInsightTextId.CrashCaseTitle),
    TAtlasCodeInsightStrings.Fmt(TAtlasCodeInsightTextId.CrashCaseText, [TAtlasCrashCases.SummaryText(ACase)]),
    TAtlasServerHandlers.CrashActions(ACase, FOnCrashIssue));
end;

function TAtlasCodeInsightCrashes.RetryAction(const AUri: string): TProc;
var
  mManager: TAtlasCodeInsightCrashes;
  mUri: string;
begin
  mManager := Self;
  mUri := AUri;
  Result :=
    procedure
    var
      mArguments: TJSONArray;
    begin
      // Die Meldung kann den Manager überleben (Entladen).
      if not ManagerLive(mManager) then
      begin
        Exit;
      end;
      mArguments := TAtlasCrashCases.RetryArguments(mUri);
      try
        mManager.RunServerCommandAsync(TAtlasCrashCases.cRetryCommand, mArguments.ToJSON, 5000, nil);
      finally
        mArguments.Free;
      end;
    end;
end;

procedure TAtlasCodeInsightCrashes.CrashSkipChanged(const ASkip: TAtlasCrashSkip);
var
  mName: string;
begin
  if not FCrashSkips.Apply(ASkip) then
  begin
    Exit;
  end;
  TAtlasServerHandlers.UpdateCrashProblems(FCrashSkips);
  mName := TAtlasServerHandlers.SkipName(ASkip);
  if ASkip.Active then
  begin
    TAtlasNotificationCenter.Default.Notify(TAtlasNotificationSources.cServer, TAtlasNotificationSeverity.Warning,
      TAtlasCodeInsightStrings.Text(TAtlasCodeInsightTextId.CrashSkipTitle),
      TAtlasCodeInsightStrings.Fmt(TAtlasCodeInsightTextId.CrashSkipText,
      [ASkip.Method, mName, ASkip.Crashes, ASkip.ExceptionClass]),
      [TAtlasNotificationCenter.Action(TAtlasCodeInsightStrings.Text(TAtlasCodeInsightTextId.CrashRetry),
      RetryAction(ASkip.Uri))]);
  end
  else
  begin
    TAtlasNotificationCenter.Default.Notify(TAtlasNotificationSources.cServer, TAtlasNotificationSeverity.Info,
      TAtlasCodeInsightStrings.Text(TAtlasCodeInsightTextId.CrashSkipTitle),
      TAtlasCodeInsightStrings.Fmt(TAtlasCodeInsightTextId.CrashSkipEnded,
      [ASkip.Method, mName]), LogActions);
  end;
  ServerChanged;
end;

end.
