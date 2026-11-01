unit Atlas.IDE.Tracker.Settings;

// Abschnitt „Issue-Tracker“ im Optionsdialog, IDE-Teil des Moduls Tracker
// (#1455; vorher Atlas.IDE.Settings.Options). TAtlasIdeTrackerSettings ist
// der IAtlasSettingsSectionProvider, den die Composition des Moduls über
// seinen Scope anmeldet: Für jede Optionsseite entsteht ein
// TAtlasTrackerSettingsSection mit den Haken dazu.
// - Anbieter, Token und Transport kommen über IAtlasTrackerAccess aus der
//   Registry (setzt die Kompositionswurzel um); ohne ihn keine Token und keine
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

type
  /// <summary>„Verbindung prüfen“ der Seite Issue-Tracker (#1260): eine Abfrage je Klick im Hintergrund, Ergebnis
  /// je Server (CredentialTarget) für diese Sitzung.</summary>
  TAtlasTrackerChecks = class
  private class var
    FStates: TDictionary<string, TAtlasTrackerTokenStatus>;
    FThreads: TList<TThread>;
    class procedure Finished(AThread: TThread; const AKey: string; const AStatus: TAtlasTrackerTokenStatus;
      const ADone: TProc); static;
    class procedure ValuesLoaded(AThread: TThread; const AValues: TAtlasTrackerValueSet;
      const ADone: TProc<TAtlasTrackerValueSet, string>); static;
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

const
  TrackerStateKeys: array[TAtlasTrackerTokenState] of string = ('missing', 'saved', 'verified', 'rejected',
    'unreachable', 'unexpected');

class function TAtlasTrackerChecks.State(const AAccess: IAtlasTrackerAccess;
  const AConnection: TAtlasTrackerConnection): TAtlasTrackerTokenStatus;
var
  mTarget: TAtlasTrackerTarget;
begin
  mTarget := AConnection.Target;
  if (AAccess = nil) or not AAccess.HasToken(mTarget) then
    Exit(TAtlasTrackerTokenStatus.Stored(False));
  if (FStates <> nil) and FStates.TryGetValue(LowerCase(mTarget.CredentialTarget), Result) then
    Exit;
  Result := TAtlasTrackerTokenStatus.Stored(True);
end;

class procedure TAtlasTrackerChecks.Forget(const AConnection: TAtlasTrackerConnection);
begin
  if FStates <> nil then
    FStates.Remove(LowerCase(AConnection.Target.CredentialTarget));
end;

class procedure TAtlasTrackerChecks.Start(const AAccess: IAtlasTrackerAccess;
  const AConnection: TAtlasTrackerConnection; const ADone: TProc);
var
  mAccess: IAtlasTrackerAccess;
  mTarget: TAtlasTrackerTarget;
  mProvider: IAtlasTrackerProvider;
  mKey: string;
  mDone: TProc;
  mThread: TThread;
begin
  mAccess := AAccess;
  mTarget := AConnection.Target;
  mProvider := AAccess.Provider(AConnection.Provider);
  mKey := LowerCase(mTarget.CredentialTarget);
  mDone := ADone;
  if FThreads = nil then
    FThreads := TList<TThread>.Create;
  mThread := TThread.CreateAnonymousThread(
    procedure
    var
      mStatus: TAtlasTrackerTokenStatus;
    begin
      try
        // Token aus dem Anmeldespeicher ohne Dialog; ohne Token kein Netz („fehlt“).
        mStatus := TAtlasTrackerConnections.Check(mProvider, mTarget, mAccess.Transport(mProvider, mTarget), Now);
      except
        on E: Exception do
        begin
          mStatus := TAtlasTrackerTokenStatus.Create(TAtlasTrackerTokenState.Unreachable, Now, 0);
          TAtlasGuard.Log('Issue-Tracker: Prüfung mit ' + E.ClassName + ' abgebrochen');
        end;
      end;
      if TAtlasShutdown.Signalled then
        Exit;
      Finished(mThread, mKey, mStatus, mDone);
    end);
  mThread.FreeOnTerminate := False;
  FThreads.Add(mThread);
  mThread.Start;
end;

class procedure TAtlasTrackerChecks.Values(const AAccess: IAtlasTrackerAccess; const AProviderName: string;
  const ATarget: TAtlasTrackerTarget; const AStateField: string; const ADone: TProc<TAtlasTrackerValueSet, string>);
var
  mAccess: IAtlasTrackerAccess;
  mTarget: TAtlasTrackerTarget;
  mProvider: IAtlasTrackerProvider;
  mField: string;
  mDone: TProc<TAtlasTrackerValueSet, string>;
  mThread: TThread;
begin
  mAccess := AAccess;
  mTarget := ATarget;
  mProvider := AAccess.Provider(AProviderName);
  mField := AStateField;
  mDone := ADone;
  if FThreads = nil then
    FThreads := TList<TThread>.Create;
  mThread := TThread.CreateAnonymousThread(
    procedure
    var
      mValues: TAtlasTrackerValueSet;
      mWriter: IAtlasTrackerWriter;
      mTransport: IAtlasCiTransport;
    begin
      mValues := Default(TAtlasTrackerValueSet);
      try
        if (mProvider = nil) or not Supports(mProvider, IAtlasTrackerWriter, mWriter) then
          mValues.Outcome := TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.UnknownProvider, 0, '')
        else
        begin
          // Token aus dem Anmeldespeicher ohne Dialog; ohne Token kein Netz.
          mTransport := mAccess.Transport(mProvider, mTarget);
          if mTransport = nil then
            mValues.Outcome := TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.NotConfigured, 0, '')
          else
            mValues := TAtlasTrackerWorkflow.LoadValues(mWriter, mTarget, mTransport, mField);
        end;
      except
        on E: Exception do
        begin
          mValues.Outcome := TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.Network, 0, '');
          TAtlasGuard.Log('Issue-Tracker: Werte mit ' + E.ClassName + ' abgebrochen');
        end;
      end;
      if TAtlasShutdown.Signalled then
        Exit;
      ValuesLoaded(mThread, mValues, mDone);
    end);
  mThread.FreeOnTerminate := False;
  FThreads.Add(mThread);
  mThread.Start;
end;

class procedure TAtlasTrackerChecks.ValuesLoaded(AThread: TThread; const AValues: TAtlasTrackerValueSet;
  const ADone: TProc<TAtlasTrackerValueSet, string>);
begin
  TAtlasMainThread.Queue(TAtlasFeature.Settings,
    procedure
    begin
      if (FThreads = nil) or not FThreads.Contains(AThread) then
        Exit;
      FThreads.Remove(AThread);
      AThread.WaitFor;
      AThread.Free;
      // Anonym: Ergebnis und Anzahl, nie Adresse, Werte oder Token.
      TAtlasGuard.Log(Format('Issue-Tracker: Werte geladen (%s, %d Zustände)',
        [TAtlasCiBuild.ErrorKey(AValues.Outcome.Error), Length(AValues.States)]));
      ADone(AValues, TAtlasTrackerEndDialog.ErrorText('', AValues.Outcome));
    end);
end;

class procedure TAtlasTrackerChecks.Finished(AThread: TThread; const AKey: string;
  const AStatus: TAtlasTrackerTokenStatus; const ADone: TProc);
begin
  TAtlasMainThread.Queue(TAtlasFeature.Settings,
    procedure
    begin
      if (FThreads = nil) or not FThreads.Contains(AThread) then
        Exit;
      FThreads.Remove(AThread);
      AThread.WaitFor;
      AThread.Free;
      if FStates = nil then
        FStates := TDictionary<string, TAtlasTrackerTokenStatus>.Create;
      FStates.AddOrSetValue(AKey, AStatus);
      // Anonym: Zustand, nie Adresse oder Token.
      TAtlasGuard.Log('Issue-Tracker: Verbindung geprüft (' + TrackerStateKeys[AStatus.State] + ')');
      ADone();
    end);
end;

class procedure TAtlasTrackerChecks.StartQueryTest(const AAccess: IAtlasTrackerAccess;
  const AConnection: TAtlasTrackerConnection; const ATarget: TAtlasTrackerTarget; const ADone: TAtlasQueryTestDone);
const
  OutcomeKeys: array[TAtlasTrackerQueryOutcome] of string = ('found', 'empty', 'noToken', 'notConfigured',
    'rejected', 'projectUnknown', 'queryRejected', 'unreadable', 'serverError', 'unreachable');
var
  mAccess: IAtlasTrackerAccess;
  mTarget: TAtlasTrackerTarget;
  mProvider: IAtlasTrackerProvider;
  mDone: TAtlasQueryTestDone;
  mThread: TThread;
begin
  mAccess := AAccess;
  mTarget := ATarget;
  mProvider := AAccess.Provider(AConnection.Provider);
  mDone := ADone;
  if FThreads = nil then
    FThreads := TList<TThread>.Create;
  mThread := TThread.CreateAnonymousThread(
    procedure
    var
      mResult: TAtlasTrackerQueryTestResult;
    begin
      try
        // Token aus dem Anmeldespeicher ohne Dialog; ohne Token „kein Token“ und kein Netz.
        mResult := TAtlasTrackerQueryTest.Run(mProvider, mTarget, mAccess.Transport(mProvider, mTarget));
      except
        on E: Exception do
        begin
          mResult := TAtlasTrackerQueryTestResult.Create(TAtlasTrackerQueryOutcome.Unreachable, '');
          TAtlasGuard.Log('Issue-Tracker: Test der Abfrage mit ' + E.ClassName + ' abgebrochen');
        end;
      end;
      if TAtlasShutdown.Signalled then
        Exit;
      TAtlasMainThread.Queue(TAtlasFeature.Settings,
        procedure
        begin
          if (FThreads = nil) or not FThreads.Contains(mThread) then
            Exit;
          FThreads.Remove(mThread);
          mThread.WaitFor;
          mThread.Free;
          // Anonym: Anbieter und Ergebnis, nie Adresse, Abfrage oder Token.
          TAtlasGuard.Log('Issue-Tracker: Abfrage getestet (' + mTarget.Provider + ', ' +
            OutcomeKeys[mResult.Outcome] + ')');
          mDone(mResult);
        end);
    end);
  mThread.FreeOnTerminate := False;
  FThreads.Add(mThread);
  mThread.Start;
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

/// <summary>Ziel für „Werte vom Tracker laden“: mit dem Projekt aus der .atlas des aktiven Projekts, wenn deren
/// Tracker derselbe Server ist (GitHub braucht owner/repo, YouTrack liest dann die Felder dieses Projekts).</summary>
function TrackerValuesTarget(const AConnection: TAtlasTrackerConnection): TAtlasTrackerTarget;
var
  mProject: string;
  mTeam: TAtlasTeamSettings;
  mTeamTarget: TAtlasTrackerTarget;
begin
  Result := AConnection.Target;
  mProject := TAtlasIdeTeamFile.ActiveProject;
  if mProject = '' then
    Exit;
  mTeam := TAtlasIdeTeamFile.Read(mProject);
  if not mTeam.Tracker.Configured then
    Exit;
  mTeamTarget := TAtlasTrackerTarget.Create(mTeam.Tracker.Provider, mTeam.Tracker.Url, mTeam.Tracker.Project, '');
  if SameText(mTeamTarget.Provider, Result.Provider) and SameText(mTeamTarget.Server, Result.Server) then
    Result := mTeamTarget;
end;

/// <summary>Verbindung aus dem Abschnitt tracker der .atlas des aktiven Projekts (#486); leer ohne.</summary>
function TeamTrackerConnections: TArray<TAtlasTrackerConnection>;
var
  mProject: string;
  mTeam: TAtlasTeamSettings;
begin
  Result := nil;
  mProject := TAtlasIdeTeamFile.ActiveProject;
  if mProject = '' then
    Exit;
  mTeam := TAtlasIdeTeamFile.Read(mProject);
  if not mTeam.Tracker.Configured then
    Exit;
  Result := [TAtlasTrackerConnection.FromTeamFile(ChangeFileExt(ExtractFileName(mProject), ''),
    TAtlasTrackerTarget.Create(mTeam.Tracker.Provider, mTeam.Tracker.Url, mTeam.Tracker.Project, ''))];
end;

/// <summary>Aktives Projekt, geöffnete .groupproj (wenn es darin ist) und die Zeile aus dessen .atlas (#1261).
/// </summary>
function TrackerProjectContext: TAtlasTrackerProjectContext;
var
  mTeam: TAtlasTeamSettings;
begin
  Result := TAtlasTrackerProjectContext.Empty;
  Result.ProjectFile := TAtlasIdeTeamFile.ActiveProject;
  if Result.ProjectFile = '' then
    Exit;
  Result.GroupFile := TAtlasIdeFiles.GroupOfProject(Result.ProjectFile);
  mTeam := TAtlasIdeTeamFile.Read(Result.ProjectFile);
  if mTeam.Tracker.Configured then
    Result.Team := [TAtlasTrackerProjectMapping.FromTeamFile(Result.ProjectFile,
      ChangeFileExt(ExtractFileName(Result.ProjectFile), ''), mTeam.Tracker.Project)];
end;


/// <summary>Anbieter, Token und Transport aus der Registry; nil ohne Kompositionswurzel.</summary>
function Access: IAtlasTrackerAccess;
var
  mItem: IInterface;
begin
  Result := nil;
  for mItem in AtlasModuleRegistry.FindAll(IAtlasTrackerAccess) do
    if Supports(mItem, IAtlasTrackerAccess, Result) then
      Exit;
end;

/// <summary>Ergebnis der Prüfung für ASection; hält den Abschnitt (AKeep), bis die Antwort da ist. Eigene Routine:
/// Der Rahmen der Haken in CreateSection hielte sonst den Abschnitt über seine eigenen Haken fest.</summary>
function CheckDone(const AKeep: IAtlasSettingsSection; ASection: TAtlasTrackerSettingsSection;
  const AConnection: TAtlasTrackerConnection): TProc;
begin
  Result :=
    procedure
    begin
      // Nur an den Abschnitt, für den geprüft wurde, solange seine Seite offen ist.
      if (AKeep <> nil) and not ASection.Closed then
        ASection.TrackerCheckDone(AConnection);
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
        ASection.TrackerValuesDone(AValues, AError);
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
  mKeep: IAtlasSettingsSection;
  mAccess: IAtlasTrackerAccess;
  mNames, mCaptions: TArray<string>;
  mProvider: IAtlasTrackerProvider;
begin
  mSection := TAtlasTrackerSettingsSection.Create;
  mKeep := mSection;
  Result := mKeep;
  // Verbindung und Projekt aus der .atlas immer, Token und Prüfung nur mit dem Zugang der Kompositionswurzel.
  mSection.OnTrackerTeam :=
    function: TArray<TAtlasTrackerConnection>
    begin
      Result := TeamTrackerConnections;
    end;
  mSection.OnTrackerContext :=
    function: TAtlasTrackerProjectContext
    begin
      Result := TrackerProjectContext;
    end;
  mAccess := Access;
  if mAccess = nil then
    Exit;
  mNames := nil;
  mCaptions := nil;
  for mProvider in mAccess.Providers do
  begin
    mNames := mNames + [mProvider.Name];
    mCaptions := mCaptions + [mProvider.Caption];
  end;
  mSection.SetTrackerProviders(mNames, mCaptions);
  mSection.OnTrackerState :=
    function(const AConnection: TAtlasTrackerConnection): TAtlasTrackerTokenStatus
    begin
      Result := TAtlasTrackerChecks.State(mAccess, AConnection);
    end;
  mSection.OnTrackerToken :=
    procedure(const AConnection: TAtlasTrackerConnection)
    var
      mTokenProvider: IAtlasTrackerProvider;
    begin
      mTokenProvider := mAccess.Provider(AConnection.Provider);
      if mTokenProvider = nil then
        Exit;
      // Derselbe verdeckte Dialog wie Atlas.TrackerLogin; leer entfernt das Token.
      if mAccess.EnterToken(mTokenProvider, AConnection.Target) then
        TAtlasTrackerChecks.Forget(AConnection);
    end;
  mSection.OnTrackerCheck :=
    procedure(const AConnection: TAtlasTrackerConnection)
    begin
      TAtlasTrackerChecks.Start(mAccess, AConnection, CheckDone(mSection, mSection, AConnection));
    end;
  mSection.OnTrackerQueryTest :=
    procedure(const AConnection: TAtlasTrackerConnection; const ATarget: TAtlasTrackerTarget;
      const ADone: TAtlasQueryTestDone)
    begin
      // Der Dialog prüft selbst, ob er noch offen ist.
      TAtlasTrackerChecks.StartQueryTest(mAccess, AConnection, ATarget, ADone);
    end;
  mSection.OnTrackerValues :=
    procedure(const AConnection: TAtlasTrackerConnection; const AStateField: string)
    begin
      TAtlasTrackerChecks.Values(mAccess, AConnection.Provider, TrackerValuesTarget(AConnection), AStateField,
        ValuesDone(mSection, mSection));
    end;
  mSection.OnTrackerRemove :=
    procedure(const AConnection: TAtlasTrackerConnection)
    begin
      if not mAccess.HasToken(AConnection.Target) then
        Exit;
      if MessageDlg(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.SettingsIssuesConnectionRemoveToken, [AConnection.Target.Server]),
        mtConfirmation, [mbYes, mbNo], 0) = mrYes then
      begin
        mAccess.RemoveToken(AConnection.Target);
        TAtlasTrackerChecks.Forget(AConnection);
      end;
    end;
end;

end.
