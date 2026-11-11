unit Atlas.IDE.Tracker.Settings;

// Abschnitt „Issue-Tracker“ im Optionsdialog, IDE-Teil des Moduls Tracker
// (#1455; vorher Atlas.IDE.Settings.Options). TAtlasIdeTrackerSettings ist
// der IAtlasSettingsSectionProvider, den die Composition des Moduls über
// seinen Scope anmeldet: Für jede Optionsseite entsteht ein
// TAtlasTrackerSettingsSection mit den Haken dazu (Hooks).
// - Anbieter, Token und Transport kommen über IAtlasTrackerAccess aus der
//   Registry (stellt die Komposition des Moduls ab der Anmeldung bereit); ohne ihn keine Token und keine
//   Prüfung, die Seite bleibt bedienbar.
// - „Verbindung prüfen“ (#1260), „Testen“ einer Abfrage (#1263) und „Werte vom
//   Tracker laden“ (#1266) laufen im Hintergrund (höchstens 5 s,
//   TAtlasTrackerChecks); das Ergebnis geht nur an einen Abschnitt, der noch
//   offen ist. Das Ergebnis der Prüfung gilt je Server bis zum Entladen;
//   Release wartet auf laufende Prüfungen. Das Protokoll nennt nur Anbieter
//   und Zustand, nie Adresse, Abfrage oder Token.
// - Verbindung und Projekt aus der .atlas des aktiven Projekts (#486, #1261)
//   über TAtlasIdeTeamFile von Base.

interface

uses
  System.SysUtils,
  Atlas.UI.Settings.Contract;

type
  TAtlasIdeTrackerSettings = class(TInterfacedObject, IAtlasSettingsSectionProvider)
  public
    function CreateSection: IAtlasSettingsSection;
    /// <summary>Beim Abmelden des Moduls: auf laufende Prüfungen warten, Ergebnisse freigeben.</summary>
    class procedure Release; static;
  end;

implementation

uses
  System.Classes,
  System.UITypes,
  System.Generics.Collections,
  Vcl.Dialogs,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.Shutdown,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Ci.Contract,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Settings.TeamFile,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Connections,
  Atlas.Core.Tracker.Projects,
  Atlas.Core.Tracker.QueryTest,
  Atlas.Core.Tracker.Workflow,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.Foundation.TeamFile,
  Atlas.UI.Tracker.EndDialog,
  Atlas.UI.Tracker.QueryDialog,
  Atlas.UI.Tracker.SettingsSection,
  Atlas.UI.Tracker.Strings;

const
  // Protokoll: anonym, nur Anbieter, Zustand und Anzahl.
  cLogCheckAborted = 'Issue-Tracker: Prüfung mit %s abgebrochen';
  cLogValuesAborted = 'Issue-Tracker: Werte mit %s abgebrochen';
  cLogQueryAborted = 'Issue-Tracker: Test der Abfrage mit %s abgebrochen';
  cLogValuesLoaded = 'Issue-Tracker: Werte geladen (%s, %d Zustände)';
  cLogChecked = 'Issue-Tracker: Verbindung geprüft (%s)';
  cLogQueryTested = 'Issue-Tracker: Abfrage getestet (%s, %s)';
  cTrackerStateKeys: array[TAtlasTrackerTokenState] of string = ('missing', 'saved', 'verified', 'rejected',
    'unreachable', 'unexpected');
  cOutcomeKeys: array[TAtlasTrackerQueryOutcome] of string = ('found', 'empty', 'noToken', 'notConfigured',
    'rejected', 'projectUnknown', 'queryRejected', 'unreadable', 'serverError', 'unreachable');

type
  /// <summary>Arbeit eines Hintergrundthreads; AThread ist der Thread selbst.</summary>
  TAtlasTrackerWork = reference to procedure(AThread: TThread);

  /// <summary>„Verbindung prüfen“ der Seite Issue-Tracker (#1260): eine Abfrage je Klick im Hintergrund, Ergebnis
  /// je Server (CredentialTarget) für diese Sitzung.</summary>
  TAtlasTrackerChecks = class
  private class var
    FStates: TDictionary<string, TAtlasTrackerTokenStatus>;
    FThreads: TList<TThread>;
    class procedure Launch(const AWork: TAtlasTrackerWork); static;
    /// <summary>Im Hauptthread: AThread aufräumen und ADone rufen, wenn er noch zu den laufenden gehört.</summary>
    class procedure Deliver(AThread: TThread; const ADone: TProc); static;
    class function CheckStatus(const AAccess: IAtlasTrackerAccess; const AProvider: IAtlasTrackerProvider;
      const ATarget: TAtlasTrackerTarget): TAtlasTrackerTokenStatus; static;
    class function ValuesOf(const AAccess: IAtlasTrackerAccess; const AProvider: IAtlasTrackerProvider;
      const ATarget: TAtlasTrackerTarget; const AStateField: string): TAtlasTrackerValueSet; static;
    class function QueryResult(const AAccess: IAtlasTrackerAccess; const AProvider: IAtlasTrackerProvider;
      const ATarget: TAtlasTrackerTarget): TAtlasTrackerQueryTestResult; static;
    class procedure Checked(const AKey: string; const AStatus: TAtlasTrackerTokenStatus); static;
    class function CheckedDone(const AKey: string; const AStatus: TAtlasTrackerTokenStatus;
      const ADone: TProc): TProc; static;
    class function ValuesDelivered(const AValues: TAtlasTrackerValueSet;
      const ADone: TProc<TAtlasTrackerValueSet, string>): TProc; static;
    class function QueryDelivered(const AProviderName: string; const AResult: TAtlasTrackerQueryTestResult;
      const ADone: TAtlasQueryTestDone): TProc; static;
  public
    /// <summary>Zustand ohne Netz: ohne Token „fehlt“, sonst das Ergebnis der letzten Prüfung oder „gespeichert“.
    /// </summary>
    class function State(const AAccess: IAtlasTrackerAccess;
      const AConnection: TAtlasTrackerConnection): TAtlasTrackerTokenStatus; static;
    /// <summary>Nach „Token hinterlegen …“ oder Entfernen: Ergebnis der letzten Prüfung verwerfen.</summary>
    class procedure Forget(const AConnection: TAtlasTrackerConnection); static;
    /// <summary>Prüfung im Hintergrund; ADone danach im Hauptthread.</summary>
    class procedure Start(const AAccess: IAtlasTrackerAccess; const AConnection: TAtlasTrackerConnection;
      const ADone: TProc); static;
    /// <summary>„Testen“ einer Abfrage (#1263) im Hintergrund; ADone danach im Hauptthread.</summary>
    class procedure StartQueryTest(const AAccess: IAtlasTrackerAccess; const AConnection: TAtlasTrackerConnection;
      const ATarget: TAtlasTrackerTarget; const ADone: TAtlasQueryTestDone); static;
    /// <summary>„Werte vom Tracker laden“ (#1266) für ATarget im Hintergrund; ADone danach im Hauptthread mit den
    /// Werten und dem Grund eines Fehlers ('' = geladen).</summary>
    class procedure Values(const AAccess: IAtlasTrackerAccess; const AProviderName: string;
      const ATarget: TAtlasTrackerTarget; const AStateField: string;
      const ADone: TProc<TAtlasTrackerValueSet, string>); static;
    /// <summary>Beim Entladen: auf laufende Prüfungen warten, Ergebnisse freigeben.</summary>
    class procedure Release; static;
  end;

  /// <summary>Haken eines Abschnitts zur IDE.</summary>
  TAtlasTrackerSettingsWiring = class
  public
    /// <summary>Verbindung und Projekt aus der .atlas; ohne Zugang.</summary>
    class procedure WireTeam(ASection: TAtlasTrackerSettingsSection); static;
    class procedure WireProviders(ASection: TAtlasTrackerSettingsSection; const AAccess: IAtlasTrackerAccess);
      static;
    /// <summary>Zustand, Token hinterlegen und entfernen.</summary>
    class procedure WireTokens(ASection: TAtlasTrackerSettingsSection; const AAccess: IAtlasTrackerAccess); static;
    /// <summary>Prüfung, Test einer Abfrage und Werte vom Tracker im Hintergrund.</summary>
    class procedure WireChecks(ASection: TAtlasTrackerSettingsSection; const AAccess: IAtlasTrackerAccess); static;
  end;

{ TAtlasTrackerChecks }

class function TAtlasTrackerChecks.State(const AAccess: IAtlasTrackerAccess;
  const AConnection: TAtlasTrackerConnection): TAtlasTrackerTokenStatus;
var
  mTarget: TAtlasTrackerTarget;
begin
  mTarget := AConnection.Target;
  if (AAccess = nil) or not AAccess.HasToken(mTarget) then
  begin
    Exit(TAtlasTrackerTokenStatus.Stored(False));
  end;
  if (FStates <> nil) and FStates.TryGetValue(LowerCase(mTarget.CredentialTarget), Result) then
  begin
    Exit;
  end;
  Result := TAtlasTrackerTokenStatus.Stored(True);
end;

class procedure TAtlasTrackerChecks.Forget(const AConnection: TAtlasTrackerConnection);
begin
  if FStates <> nil then
  begin
    FStates.Remove(LowerCase(AConnection.Target.CredentialTarget));
  end;
end;

class procedure TAtlasTrackerChecks.Launch(const AWork: TAtlasTrackerWork);
var
  mWork: TAtlasTrackerWork;
  mThread: TThread;
begin
  mWork := AWork;
  if FThreads = nil then
  begin
    FThreads := TList<TThread>.Create;
  end;
  mThread := TThread.CreateAnonymousThread(
    procedure
    begin
      mWork(mThread);
    end);
  mThread.FreeOnTerminate := False;
  FThreads.Add(mThread);
  mThread.Start;
end;

class procedure TAtlasTrackerChecks.Deliver(AThread: TThread; const ADone: TProc);
var
  mDone: TProc;
begin
  // Beim Beenden der IDE kommt nichts mehr an (Release wartet auf den Thread).
  if TAtlasShutdown.Signalled then
  begin
    Exit;
  end;
  mDone := ADone;
  TAtlasMainThread.Queue(TAtlasFeature.Settings,
    procedure
    begin
      if (FThreads = nil) or not FThreads.Contains(AThread) then
      begin
        Exit;
      end;
      FThreads.Remove(AThread);
      AThread.WaitFor;
      AThread.Free;
      mDone();
    end);
end;

class function TAtlasTrackerChecks.CheckStatus(const AAccess: IAtlasTrackerAccess;
  const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget): TAtlasTrackerTokenStatus;
begin
  try
    // Token aus dem Anmeldespeicher ohne Dialog; ohne Token kein Netz („fehlt“).
    Result := TAtlasTrackerConnections.Check(AProvider, ATarget, AAccess.Transport(AProvider, ATarget), Now);
  except
    on E: Exception do
    begin
      Result := TAtlasTrackerTokenStatus.Create(TAtlasTrackerTokenState.Unreachable, Now, 0);
      TAtlasGuard.Log(Format(cLogCheckAborted, [E.ClassName], TFormatSettings.Invariant));
    end;
  end;
end;

class procedure TAtlasTrackerChecks.Checked(const AKey: string; const AStatus: TAtlasTrackerTokenStatus);
begin
  if FStates = nil then
  begin
    FStates := TDictionary<string, TAtlasTrackerTokenStatus>.Create;
  end;
  FStates.AddOrSetValue(AKey, AStatus);
  TAtlasGuard.Log(Format(cLogChecked, [cTrackerStateKeys[AStatus.State]], TFormatSettings.Invariant));
end;

class function TAtlasTrackerChecks.CheckedDone(const AKey: string; const AStatus: TAtlasTrackerTokenStatus;
  const ADone: TProc): TProc;
var
  mKey: string;
  mStatus: TAtlasTrackerTokenStatus;
  mDone: TProc;
begin
  mKey := AKey;
  mStatus := AStatus;
  mDone := ADone;
  Result :=
    procedure
    begin
      Checked(mKey, mStatus);
      mDone();
    end;
end;

class procedure TAtlasTrackerChecks.Start(const AAccess: IAtlasTrackerAccess;
  const AConnection: TAtlasTrackerConnection; const ADone: TProc);
var
  mAccess: IAtlasTrackerAccess;
  mTarget: TAtlasTrackerTarget;
  mProvider: IAtlasTrackerProvider;
  mKey: string;
  mDone: TProc;
begin
  mAccess := AAccess;
  mTarget := AConnection.Target;
  mProvider := AAccess.Provider(AConnection.Provider);
  mKey := LowerCase(mTarget.CredentialTarget);
  mDone := ADone;
  Launch(
    procedure(AThread: TThread)
    begin
      Deliver(AThread, CheckedDone(mKey, CheckStatus(mAccess, mProvider, mTarget), mDone));
    end);
end;

class function TAtlasTrackerChecks.ValuesOf(const AAccess: IAtlasTrackerAccess;
  const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget;
  const AStateField: string): TAtlasTrackerValueSet;
var
  mWriter: IAtlasTrackerWriter;
  mTransport: IAtlasCiTransport;
begin
  Result := Default(TAtlasTrackerValueSet);
  if (AProvider = nil) or not Supports(AProvider, IAtlasTrackerWriter, mWriter) then
  begin
    Result.Outcome := TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.UnknownProvider, 0, '');
    Exit;
  end;
  // Token aus dem Anmeldespeicher ohne Dialog; ohne Token kein Netz.
  mTransport := AAccess.Transport(AProvider, ATarget);
  if mTransport = nil then
  begin
    Result.Outcome := TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.NotConfigured, 0, '');
    Exit;
  end;
  try
    Result := TAtlasTrackerWorkflow.LoadValues(mWriter, ATarget, mTransport, AStateField);
  except
    on E: Exception do
    begin
      Result := Default(TAtlasTrackerValueSet);
      Result.Outcome := TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.Network, 0, '');
      TAtlasGuard.Log(Format(cLogValuesAborted, [E.ClassName], TFormatSettings.Invariant));
    end;
  end;
end;

class function TAtlasTrackerChecks.ValuesDelivered(const AValues: TAtlasTrackerValueSet;
  const ADone: TProc<TAtlasTrackerValueSet, string>): TProc;
var
  mValues: TAtlasTrackerValueSet;
  mDone: TProc<TAtlasTrackerValueSet, string>;
begin
  mValues := AValues;
  mDone := ADone;
  Result :=
    procedure
    begin
      TAtlasGuard.Log(Format(cLogValuesLoaded, [TAtlasCiBuild.ErrorKey(mValues.Outcome.Error),
        Length(mValues.States)], TFormatSettings.Invariant));
      mDone(mValues, TAtlasTrackerEndDialog.ErrorText('', mValues.Outcome));
    end;
end;

class procedure TAtlasTrackerChecks.Values(const AAccess: IAtlasTrackerAccess; const AProviderName: string;
  const ATarget: TAtlasTrackerTarget; const AStateField: string; const ADone: TProc<TAtlasTrackerValueSet, string>);
var
  mAccess: IAtlasTrackerAccess;
  mTarget: TAtlasTrackerTarget;
  mProvider: IAtlasTrackerProvider;
  mField: string;
  mDone: TProc<TAtlasTrackerValueSet, string>;
begin
  mAccess := AAccess;
  mTarget := ATarget;
  mProvider := AAccess.Provider(AProviderName);
  mField := AStateField;
  mDone := ADone;
  Launch(
    procedure(AThread: TThread)
    begin
      Deliver(AThread, ValuesDelivered(ValuesOf(mAccess, mProvider, mTarget, mField), mDone));
    end);
end;

class function TAtlasTrackerChecks.QueryResult(const AAccess: IAtlasTrackerAccess;
  const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget): TAtlasTrackerQueryTestResult;
begin
  try
    // Token aus dem Anmeldespeicher ohne Dialog; ohne Token „kein Token“ und kein Netz.
    Result := TAtlasTrackerQueryTest.Run(AProvider, ATarget, AAccess.Transport(AProvider, ATarget));
  except
    on E: Exception do
    begin
      Result := TAtlasTrackerQueryTestResult.Create(TAtlasTrackerQueryOutcome.Unreachable, '');
      TAtlasGuard.Log(Format(cLogQueryAborted, [E.ClassName], TFormatSettings.Invariant));
    end;
  end;
end;

class function TAtlasTrackerChecks.QueryDelivered(const AProviderName: string;
  const AResult: TAtlasTrackerQueryTestResult; const ADone: TAtlasQueryTestDone): TProc;
var
  mProviderName: string;
  mResult: TAtlasTrackerQueryTestResult;
  mDone: TAtlasQueryTestDone;
begin
  mProviderName := AProviderName;
  mResult := AResult;
  mDone := ADone;
  Result :=
    procedure
    begin
      TAtlasGuard.Log(Format(cLogQueryTested, [mProviderName, cOutcomeKeys[mResult.Outcome]],
        TFormatSettings.Invariant));
      mDone(mResult);
    end;
end;

class procedure TAtlasTrackerChecks.StartQueryTest(const AAccess: IAtlasTrackerAccess;
  const AConnection: TAtlasTrackerConnection; const ATarget: TAtlasTrackerTarget; const ADone: TAtlasQueryTestDone);
var
  mAccess: IAtlasTrackerAccess;
  mTarget: TAtlasTrackerTarget;
  mProvider: IAtlasTrackerProvider;
  mDone: TAtlasQueryTestDone;
begin
  mAccess := AAccess;
  mTarget := ATarget;
  mProvider := AAccess.Provider(AConnection.Provider);
  mDone := ADone;
  Launch(
    procedure(AThread: TThread)
    begin
      Deliver(AThread, QueryDelivered(mTarget.Provider, QueryResult(mAccess, mProvider, mTarget), mDone));
    end);
end;

class procedure TAtlasTrackerChecks.Release;
var
  mThread: TThread;
begin
  if FThreads <> nil then
  begin
    // Höchstens die Zeitgrenze einer Prüfung (5 s); danach kommt kein Ergebnis mehr an.
    for mThread in FThreads do
    begin
      mThread.WaitFor;
      mThread.Free;
    end;
    FreeAndNil(FThreads);
  end;
  FreeAndNil(FStates);
end;

/// <summary>Tracker aus der .atlas des aktiven Projekts; False ohne Projekt oder ohne Abschnitt tracker.</summary>
function TeamTracker(out AProject: string; out ATarget: TAtlasTrackerTarget): Boolean;
var
  mTeam: TAtlasTeamSettings;
begin
  ATarget := TAtlasTrackerTarget.Create('', '', '', '');
  AProject := TAtlasIdeFiles.ActiveProjectFile;
  Result := False;
  if AProject <> '' then
  begin
    mTeam := TAtlasIdeTeamFile.Read(AProject);
    Result := mTeam.Tracker.Configured;
    ATarget := TAtlasTrackerTarget.Create(mTeam.Tracker.Provider, mTeam.Tracker.Url, mTeam.Tracker.Project, '');
  end;
end;

/// <summary>Ziel für „Werte vom Tracker laden“: mit dem Projekt aus der .atlas des aktiven Projekts, wenn deren
/// Tracker derselbe Server ist (GitHub braucht owner/repo, YouTrack liest dann die Felder dieses Projekts).</summary>
function TrackerValuesTarget(const AConnection: TAtlasTrackerConnection): TAtlasTrackerTarget;
var
  mProject: string;
  mTeamTarget: TAtlasTrackerTarget;
begin
  Result := AConnection.Target;
  if TeamTracker(mProject, mTeamTarget) and SameText(mTeamTarget.Provider, Result.Provider) and
    SameText(mTeamTarget.Server, Result.Server) then
  begin
    Result := mTeamTarget;
  end;
end;

/// <summary>Verbindung aus dem Abschnitt tracker der .atlas des aktiven Projekts (#486); leer ohne.</summary>
function TeamTrackerConnections: TArray<TAtlasTrackerConnection>;
var
  mProject: string;
  mTarget: TAtlasTrackerTarget;
begin
  Result := nil;
  if TeamTracker(mProject, mTarget) then
  begin
    Result := TArray<TAtlasTrackerConnection>.Create(
      TAtlasTrackerConnection.FromTeamFile(ChangeFileExt(ExtractFileName(mProject), ''), mTarget));
  end;
end;

/// <summary>Aktives Projekt, geöffnete .groupproj (wenn es darin ist) und die Zeile aus dessen .atlas (#1261).
/// </summary>
function TrackerProjectContext: TAtlasTrackerProjectContext;
var
  mProject: string;
  mTarget: TAtlasTrackerTarget;
begin
  Result := TAtlasTrackerProjectContext.Empty;
  if TeamTracker(mProject, mTarget) then
  begin
    Result.Team := TArray<TAtlasTrackerProjectMapping>.Create(TAtlasTrackerProjectMapping.FromTeamFile(mProject,
      ChangeFileExt(ExtractFileName(mProject), ''), mTarget.Project));
  end;
  Result.ProjectFile := mProject;
  if mProject <> '' then
  begin
    Result.GroupFile := TAtlasIdeFiles.GroupOfProject(mProject);
  end;
end;

/// <summary>Anbieter, Token und Transport aus der Registry; nil ohne Kompositionswurzel.</summary>
function Access: IAtlasTrackerAccess;
var
  mItem: IInterface;
begin
  Result := nil;
  for mItem in AtlasModuleRegistry.FindAll(IAtlasTrackerAccess) do
  begin
    if Supports(mItem, IAtlasTrackerAccess, Result) then
    begin
      Exit;
    end;
  end;
end;

/// <summary>Ergebnis der Prüfung für ASection; hält den Abschnitt (AKeep), bis die Antwort da ist. Eigene Routine:
/// Der Rahmen der Haken hielte sonst den Abschnitt über seine eigenen Haken fest.</summary>
function CheckDone(const AKeep: IAtlasSettingsSection; ASection: TAtlasTrackerSettingsSection;
  const AConnection: TAtlasTrackerConnection): TProc;
begin
  Result :=
    procedure
    begin
      // Nur an den Abschnitt, für den geprüft wurde, solange seine Seite offen ist.
      if (AKeep <> nil) and not ASection.Closed then
      begin
        ASection.TrackerCheckDone(AConnection);
      end;
    end;
end;

/// <summary>Wie CheckDone für „Werte vom Tracker laden“.</summary>
function ValuesDone(const AKeep: IAtlasSettingsSection;
  ASection: TAtlasTrackerSettingsSection): TProc<TAtlasTrackerValueSet, string>;
begin
  Result :=
    procedure(AValues: TAtlasTrackerValueSet; AError: string)
    begin
      if (AKeep <> nil) and not ASection.Closed then
      begin
        ASection.TrackerValuesDone(AValues, AError);
      end;
    end;
end;

{ TAtlasTrackerSettingsWiring }

class procedure TAtlasTrackerSettingsWiring.WireTeam(ASection: TAtlasTrackerSettingsSection);
begin
  ASection.Hooks.OnTeam :=
    function: TArray<TAtlasTrackerConnection>
    begin
      Result := TeamTrackerConnections;
    end;
  ASection.Hooks.OnContext :=
    function: TAtlasTrackerProjectContext
    begin
      Result := TrackerProjectContext;
    end;
end;

class procedure TAtlasTrackerSettingsWiring.WireProviders(ASection: TAtlasTrackerSettingsSection;
  const AAccess: IAtlasTrackerAccess);
var
  mNames: TArray<string>;
  mCaptions: TArray<string>;
  mProvider: IAtlasTrackerProvider;
begin
  mNames := nil;
  mCaptions := nil;
  for mProvider in AAccess.Providers do
  begin
    mNames := mNames + [mProvider.Name];
    mCaptions := mCaptions + [mProvider.Caption];
  end;
  ASection.SetTrackerProviders(mNames, mCaptions);
end;

class procedure TAtlasTrackerSettingsWiring.WireTokens(ASection: TAtlasTrackerSettingsSection;
  const AAccess: IAtlasTrackerAccess);
var
  mAccess: IAtlasTrackerAccess;
begin
  mAccess := AAccess;
  ASection.Hooks.OnState :=
    function(const AConnection: TAtlasTrackerConnection): TAtlasTrackerTokenStatus
    begin
      Result := TAtlasTrackerChecks.State(mAccess, AConnection);
    end;
  ASection.Hooks.OnToken :=
    procedure(const AConnection: TAtlasTrackerConnection)
    begin
      // Derselbe verdeckte Dialog wie Atlas.TrackerLogin; leer entfernt das Token.
      if (mAccess.Provider(AConnection.Provider) <> nil) and
        mAccess.EnterToken(mAccess.Provider(AConnection.Provider), AConnection.Target) then
      begin
        TAtlasTrackerChecks.Forget(AConnection);
      end;
    end;
  ASection.Hooks.OnRemove :=
    procedure(const AConnection: TAtlasTrackerConnection)
    begin
      if mAccess.HasToken(AConnection.Target) and (MessageDlg(TAtlasTrackerStrings.Fmt(
        TAtlasTrackerTextId.SettingsIssuesConnectionRemoveToken, [AConnection.Target.Server]), mtConfirmation,
        [mbYes, mbNo], 0) = mrYes) then
      begin
        mAccess.RemoveToken(AConnection.Target);
        TAtlasTrackerChecks.Forget(AConnection);
      end;
    end;
end;

class procedure TAtlasTrackerSettingsWiring.WireChecks(ASection: TAtlasTrackerSettingsSection;
  const AAccess: IAtlasTrackerAccess);
var
  mAccess: IAtlasTrackerAccess;
  mSection: TAtlasTrackerSettingsSection;
begin
  mAccess := AAccess;
  mSection := ASection;
  ASection.Hooks.OnCheck :=
    procedure(const AConnection: TAtlasTrackerConnection)
    begin
      TAtlasTrackerChecks.Start(mAccess, AConnection, CheckDone(mSection, mSection, AConnection));
    end;
  ASection.Hooks.OnQueryTest :=
    procedure(const AConnection: TAtlasTrackerConnection; const ATarget: TAtlasTrackerTarget;
      const ADone: TAtlasQueryTestDone)
    begin
      // Der Dialog prüft selbst, ob er noch offen ist.
      TAtlasTrackerChecks.StartQueryTest(mAccess, AConnection, ATarget, ADone);
    end;
  ASection.Hooks.OnValues :=
    procedure(const AConnection: TAtlasTrackerConnection; const AStateField: string)
    begin
      TAtlasTrackerChecks.Values(mAccess, AConnection.Provider, TrackerValuesTarget(AConnection), AStateField,
        ValuesDone(mSection, mSection));
    end;
end;

{ TAtlasIdeTrackerSettings }

class procedure TAtlasIdeTrackerSettings.Release;
begin
  TAtlasTrackerChecks.Release;
end;

function TAtlasIdeTrackerSettings.CreateSection: IAtlasSettingsSection;
var
  mSection: TAtlasTrackerSettingsSection;
  mAccess: IAtlasTrackerAccess;
begin
  mSection := TAtlasTrackerSettingsSection.Create;
  Result := mSection;
  // Verbindung und Projekt aus der .atlas immer, Token und Prüfung nur mit dem Zugang der Kompositionswurzel.
  TAtlasTrackerSettingsWiring.WireTeam(mSection);
  mAccess := Access;
  if mAccess <> nil then
  begin
    TAtlasTrackerSettingsWiring.WireProviders(mSection, mAccess);
    TAtlasTrackerSettingsWiring.WireTokens(mSection, mAccess);
    TAtlasTrackerSettingsWiring.WireChecks(mSection, mAccess);
  end;
end;

end.
