unit Atlas.IDE.Tracker.Workflow;

// Tracker nachführen in der IDE (#1266):
// - Nach „Beginnen“ (Branch angelegt, gewechselt oder Kennung gemerkt):
//   Zustand issues.startState, mit issues.assignOnStart mir zuweisen,
//   Kommentar issues.startComment; das Ergebnis als eine Zeile in der
//   Meldungsansicht, bei Fehler mit Grund (der Branch bleibt).
// - „Beenden“: {commits} im Hintergrund über IAtlasVcsLocalWork.Outgoing,
//   dann der Dialog „ATL-123 beenden“ (TAtlasTrackerEndDialog) mit Benutzern
//   und Zuständen vom Tracker; geschrieben wird nur mit „Senden“.
// - Kommentar aus der Vorschau (SendComment).
// Nur mit issues.syncState und einem Anbieter, der IAtlasTrackerWriter
// umsetzt (Enabled); sonst bleibt „Beenden“ die Rückfrage von „Meine Issues“.
// Einstellungen je Verbindung (issues.connections) vor den globalen. Netz im
// Hintergrund über TAtlasVcsWorker (Stop beim Entladen), je Schreiben
// höchstens TAtlasTrackerWorkflow.WriteTimeoutMs; nichts wird wiederholt.
// Protokoll anonym: Anbieter, Art und Ergebnis, nie Adresse, Kennung,
// Kommentar oder Token.

interface

uses
  System.SysUtils,
  Atlas.Core.Ci.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Workflow,
  Atlas.Core.Vcs.Worker,
  Atlas.UI.Tracker.EndDialog;

type
  /// <summary>Transport mit dem Token aus dem Anmeldespeicher; nil ohne Token. Läuft im Hintergrund.</summary>
  TAtlasIdeTrackerTransport = reference to function(const AProvider: IAtlasTrackerProvider;
    const ATarget: TAtlasTrackerTarget): IAtlasCiTransport;
  /// <summary>{time} für AKey (#1267); '' ohne Zeiterfassung.</summary>
  TAtlasIdeTrackerTimeText = reference to function(const AKey: string): string;

  /// <summary>Was „Beenden“ über das Issue weiß.</summary>
  TAtlasIdeTrackerEnd = record
    Key: string;
    Branch: string;
    /// <summary>Ordner des Projekts (Versionsverwaltung für {commits}).</summary>
    Folder: string;
    /// <summary>issues.branchBase; '' = main, sonst master.</summary>
    Base: string;
    /// <summary>Adresse des Pull Requests für {pr}; '' ohne.</summary>
    PullRequest: string;
    class function Create(const AKey, ABranch, AFolder, ABase, APullRequest: string): TAtlasIdeTrackerEnd; static;
  end;

  TAtlasIdeTrackerSync = class
  public const
    /// <summary>Zeitlimit je Aufruf der Versionsverwaltung für {commits}.</summary>
    VcsTimeoutMs = 10000;
  private
    FWorker: TAtlasVcsWorker;
    FTransport: TAtlasIdeTrackerTransport;
    FReport: TProc<string>;
    FTimeText: TAtlasIdeTrackerTimeText;
    FStopped: Boolean;
    procedure Report(const AText: string);
    procedure ShowEnd(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget;
      const AInput: TAtlasIdeTrackerEnd; const AOptions: TAtlasTrackerSyncOptions; const ACommits: string;
      const AEnded: TProc<TAtlasTrackerChange>);
    function SendHandler(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget;
      const AKey: string): TAtlasTrackerSendEvent;
    function PrepareHandler(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget;
      const AStateField: string; const ASession: IInterface): TProc<TAtlasTrackerEndDialog>;
    procedure LoadEndValues(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget;
      const AStateField: string; const ASession: IInterface);
    class procedure Logged(const AProvider: IAtlasTrackerProvider; const AWhat: string;
      const AResult: TAtlasTrackerWriteResult); static;
  public
    /// <summary>AReport: Zeile in die Meldungsansicht.</summary>
    constructor Create(const ATransport: TAtlasIdeTrackerTransport; const AReport: TProc<string>);
    destructor Destroy; override;
    /// <summary>Keine Ergebnisse mehr; kurz auf laufende Zugriffe warten (beim Entladen).</summary>
    procedure Stop;
    /// <summary>Einstellungen issues.* mit den Werten der Verbindung zum Server von ATarget.</summary>
    class function Options(const ATarget: TAtlasTrackerTarget): TAtlasTrackerSyncOptions; static;
    /// <summary>Schreibzugriff des Anbieters; nil, wenn er nicht schreiben kann.</summary>
    class function WriterOf(const AProvider: IAtlasTrackerProvider): IAtlasTrackerWriter; static;
    /// <summary>issues.syncState an, der Anbieter kann schreiben und ein Server ist eingetragen.</summary>
    function Enabled(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget): Boolean;
    /// <summary>Nach „Beginnen“: Zustand, Zuweisung und Kommentar im Hintergrund schreiben, Ergebnis als Zeile.
    /// </summary>
    procedure Started(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget;
      const AKey, ABranch: string);
    /// <summary>„Beenden“ mit Dialog; AEnded nach erfolgreichem „Senden“ (bzw. ohne etwas zu schreiben) mit der
    /// geschriebenen Änderung. Abbrechen ändert nichts.</summary>
    procedure EndIssue(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget;
      const AInput: TAtlasIdeTrackerEnd; const AEnded: TProc<TAtlasTrackerChange>);
    /// <summary>AChange auf AKey schreiben (Hintergrund); ADone im Hauptthread, genau einmal (nach Stop nie).
    /// </summary>
    procedure Apply(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget; const AKey: string;
      const AChange: TAtlasTrackerChange; const ADone: TAtlasTrackerSendDone);
    /// <summary>Kommentar aus der Vorschau; ADone wie bei Apply.</summary>
    procedure SendComment(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget;
      const AKey, AText: string; const ADone: TAtlasTrackerSendDone);
    /// <summary>{time} für den Kommentar beim Beenden (#1267).</summary>
    property TimeText: TAtlasIdeTrackerTimeText read FTimeText write FTimeText;
  end;

implementation

uses
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Tracker.Connections,
  Atlas.Core.Vcs.Contract,
  Atlas.UI.Strings,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Vcs.Service;

type
  /// <summary>Der offene Beenden-Dialog für nachgeladene Werte; nil, sobald er geschlossen ist.</summary>
  IAtlasTrackerEndSession = interface
    ['{8E2C5A17-3B94-4F0D-A6C1-D72E9B058F43}']
    function Dialog: TAtlasTrackerEndDialog;
    procedure SetDialog(ADialog: TAtlasTrackerEndDialog);
  end;

  TAtlasTrackerEndSession = class(TInterfacedObject, IAtlasTrackerEndSession)
  private
    FDialog: TAtlasTrackerEndDialog;
  public
    function Dialog: TAtlasTrackerEndDialog;
    procedure SetDialog(ADialog: TAtlasTrackerEndDialog);
  end;

function TAtlasTrackerEndSession.Dialog: TAtlasTrackerEndDialog;
begin
  Result := FDialog;
end;

procedure TAtlasTrackerEndSession.SetDialog(ADialog: TAtlasTrackerEndDialog);
begin
  FDialog := ADialog;
end;

{ TAtlasIdeTrackerEnd }

class function TAtlasIdeTrackerEnd.Create(const AKey, ABranch, AFolder, ABase,
  APullRequest: string): TAtlasIdeTrackerEnd;
begin
  Result.Key := AKey;
  Result.Branch := ABranch;
  Result.Folder := AFolder;
  Result.Base := ABase;
  Result.PullRequest := APullRequest;
end;

{ TAtlasIdeTrackerSync }

constructor TAtlasIdeTrackerSync.Create(const ATransport: TAtlasIdeTrackerTransport; const AReport: TProc<string>);
begin
  inherited Create;
  FTransport := ATransport;
  FReport := AReport;
  FWorker := TAtlasVcsWorker.Create;
end;

destructor TAtlasIdeTrackerSync.Destroy;
begin
  Stop;
  FWorker.Free;
  inherited;
end;

procedure TAtlasIdeTrackerSync.Stop;
begin
  if FStopped then
    Exit;
  FStopped := True;
  // Höchstens die Zeitgrenze eines Schreibens; danach kommt kein Ergebnis mehr an.
  FWorker.Stop(1000);
  FTransport := nil;
  FReport := nil;
  FTimeText := nil;
end;

procedure TAtlasIdeTrackerSync.Report(const AText: string);
begin
  if Assigned(FReport) and (AText <> '') then
    FReport(AText);
end;

class function TAtlasIdeTrackerSync.Options(const ATarget: TAtlasTrackerTarget): TAtlasTrackerSyncOptions;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  Result := TAtlasTrackerSyncOptions.Create(mSettings.IssuesSyncState, mSettings.IssuesStateField,
    mSettings.IssuesAssigneeField, mSettings.IssuesStartState, mSettings.IssuesAssignOnStart,
    mSettings.IssuesStartComment, mSettings.IssuesEndStates, mSettings.IssuesEndComment);
  Result := TAtlasTrackerWorkflow.ForConnection(Result, TAtlasTrackerConnections.Read(mSettings.IssuesConnections),
    ATarget);
end;

class function TAtlasIdeTrackerSync.WriterOf(const AProvider: IAtlasTrackerProvider): IAtlasTrackerWriter;
begin
  if (AProvider = nil) or not Supports(AProvider, IAtlasTrackerWriter, Result) then
    Result := nil;
end;

function TAtlasIdeTrackerSync.Enabled(const AProvider: IAtlasTrackerProvider;
  const ATarget: TAtlasTrackerTarget): Boolean;
begin
  Result := not FStopped and TAtlasIdeSettings.Current.IssuesSyncState and (WriterOf(AProvider) <> nil) and
    (ATarget.Server <> '') and Assigned(FTransport);
end;

class procedure TAtlasIdeTrackerSync.Logged(const AProvider: IAtlasTrackerProvider; const AWhat: string;
  const AResult: TAtlasTrackerWriteResult);
var
  mName: string;
begin
  mName := '';
  if AProvider <> nil then
    mName := AProvider.Name;
  // Anonym: Anbieter, Art, Ergebnis; nie Adresse, Kennung, Kommentar oder Token.
  if AResult.Succeeded then
    TAtlasGuard.Log(Format('Tracker nachführen: %s %s geschrieben', [mName, AWhat]))
  else
    TAtlasGuard.Log(Format('Tracker nachführen: %s %s nicht geschrieben (%s, %d)', [mName, AWhat,
      TAtlasCiBuild.ErrorKey(AResult.Error), AResult.Status]));
end;

procedure TAtlasIdeTrackerSync.Apply(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget;
  const AKey: string; const AChange: TAtlasTrackerChange; const ADone: TAtlasTrackerSendDone);
var
  mWriter: IAtlasTrackerWriter;
  mProvider: IAtlasTrackerProvider;
  mTransports: TAtlasIdeTrackerTransport;
  mTarget: TAtlasTrackerTarget;
  mKey: string;
  mChange: TAtlasTrackerChange;
  mDone: TAtlasTrackerSendDone;
  mResult: TAtlasTrackerWriteResult;
begin
  mWriter := WriterOf(AProvider);
  mTransports := FTransport;
  if FStopped or (mWriter = nil) or not Assigned(mTransports) then
  begin
    ADone(TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.UnknownProvider, 0, ''));
    Exit;
  end;
  mProvider := AProvider;
  mTarget := ATarget;
  mKey := AKey;
  mChange := AChange;
  mDone := ADone;
  mResult := TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.Network, 0, '');
  if not FWorker.Run(
    procedure
    var
      mTransport: IAtlasCiTransport;
    begin
      try
        // Token aus dem Anmeldespeicher ohne Dialog; ohne Token nichts schreiben.
        mTransport := mTransports(mProvider, mTarget);
        if mTransport = nil then
          mResult := TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.NotConfigured, 0, '')
        else
          mResult := mWriter.Apply(mTarget, mTransport, mKey, mChange, TAtlasTrackerWorkflow.WriteTimeoutMs);
      except
        on E: Exception do
        begin
          mResult := TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.Network, 0, '');
          TAtlasGuard.Log('Tracker nachführen: Schreiben mit ' + E.ClassName + ' abgebrochen');
        end;
      end;
    end,
    procedure
    begin
      mDone(mResult);
    end) then
    ADone(TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.Cancelled, 0, ''));
end;

procedure TAtlasIdeTrackerSync.Started(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget;
  const AKey, ABranch: string);
var
  mOptions: TAtlasTrackerSyncOptions;
  mChange: TAtlasTrackerChange;
  mOwner: TAtlasIdeTrackerSync;
  mProvider: IAtlasTrackerProvider;
  mKey: string;
begin
  if not Enabled(AProvider, ATarget) then
    Exit;
  mOptions := Options(ATarget);
  if not mOptions.HasStartWork then
    Exit;
  mChange := TAtlasTrackerWorkflow.StartChange(mOptions, TAtlasTrackerPlaceholders.Create(AKey, ABranch));
  mOwner := Self;
  mProvider := AProvider;
  mKey := AKey;
  Apply(AProvider, ATarget, AKey, mChange,
    procedure(const AResult: TAtlasTrackerWriteResult)
    begin
      Logged(mProvider, 'Beginnen', AResult);
      if AResult.Succeeded then
        mOwner.Report(TAtlasStrings.Fmt(TAtlasTextId.TrackerStartSynced,
          [mKey, TAtlasTrackerEndDialog.SummaryText(mChange)]))
      else
        mOwner.Report(TAtlasStrings.Fmt(TAtlasTextId.TrackerStartFailed,
          [mKey, TAtlasTrackerEndDialog.ErrorText(mKey, AResult)]));
    end);
end;

procedure TAtlasIdeTrackerSync.EndIssue(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget;
  const AInput: TAtlasIdeTrackerEnd; const AEnded: TProc<TAtlasTrackerChange>);
var
  mOwner: TAtlasIdeTrackerSync;
  mProvider: IAtlasTrackerProvider;
  mTarget: TAtlasTrackerTarget;
  mInput: TAtlasIdeTrackerEnd;
  mOptions: TAtlasTrackerSyncOptions;
  mEnded: TProc<TAtlasTrackerChange>;
  mCommits: string;
begin
  if not Enabled(AProvider, ATarget) then
    Exit;
  mOwner := Self;
  mProvider := AProvider;
  mTarget := ATarget;
  mInput := AInput;
  mOptions := Options(ATarget);
  mEnded := AEnded;
  mCommits := '';
  // {commits} aus der Versionsverwaltung im Hintergrund, danach der Dialog im Hauptthread.
  if not TAtlasIdeVcs.Run(
    procedure
    var
      mVcs: IAtlasVersionControl;
      mWork: IAtlasVcsLocalWork;
    begin
      mVcs := TAtlasIdeVcs.ForFolder(mInput.Folder, VcsTimeoutMs);
      if Supports(mVcs, IAtlasVcsLocalWork, mWork) then
        mCommits := TAtlasTrackerWorkflow.CommitsFor(mWork, mInput.Branch, mInput.Base, mInput.Key);
    end,
    procedure
    begin
      if not mOwner.FStopped then
        TAtlasGuard.Run(TAtlasFeature.WelcomePage,
          procedure
          begin
            mOwner.ShowEnd(mProvider, mTarget, mInput, mOptions, mCommits, mEnded);
          end);
    end) then
    ShowEnd(AProvider, ATarget, AInput, mOptions, '', AEnded);
end;

procedure TAtlasIdeTrackerSync.ShowEnd(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget;
  const AInput: TAtlasIdeTrackerEnd; const AOptions: TAtlasTrackerSyncOptions; const ACommits: string;
  const AEnded: TProc<TAtlasTrackerChange>);
var
  mValues: TAtlasTrackerPlaceholders;
  mSession: IAtlasTrackerEndSession;
  mChange: TAtlasTrackerChange;
  mDone: Boolean;
begin
  mValues := TAtlasTrackerPlaceholders.Create(AInput.Key, AInput.Branch);
  mValues.Commits := ACommits;
  mValues.PullRequest := AInput.PullRequest;
  if Assigned(FTimeText) then
    mValues.Time := FTimeText(AInput.Key);
  mSession := TAtlasTrackerEndSession.Create;
  try
    mDone := TAtlasTrackerEndDialog.Execute(AInput.Key, AOptions,
      TAtlasTrackerWorkflow.Fill(AOptions.EndComment, mValues), SendHandler(AProvider, ATarget, AInput.Key),
      PrepareHandler(AProvider, ATarget, AOptions.StateField, mSession), mChange);
  finally
    // Nachgeladene Werte kommen danach nicht mehr an den freigegebenen Dialog.
    mSession.SetDialog(nil);
  end;
  if not mDone or FStopped then
    Exit;
  if mChange.HasWork then
    Report(TAtlasStrings.Fmt(TAtlasTextId.TrackerEndSent, [AInput.Key, TAtlasTrackerEndDialog.SummaryText(mChange)]));
  AEnded(mChange);
end;

function TAtlasIdeTrackerSync.SendHandler(const AProvider: IAtlasTrackerProvider;
  const ATarget: TAtlasTrackerTarget; const AKey: string): TAtlasTrackerSendEvent;
var
  mOwner: TAtlasIdeTrackerSync;
  mProvider: IAtlasTrackerProvider;
  mTarget: TAtlasTrackerTarget;
  mKey: string;
begin
  // Eigene Routine: Die Methodenreferenz hält nur diese Werte, keinen Rahmen von ShowEnd.
  mOwner := Self;
  mProvider := AProvider;
  mTarget := ATarget;
  mKey := AKey;
  Result :=
    procedure(const AChange: TAtlasTrackerChange; const ADone: TAtlasTrackerSendDone)
    var
      mDone: TAtlasTrackerSendDone;
    begin
      mDone := ADone;
      mOwner.Apply(mProvider, mTarget, mKey, AChange,
        procedure(const AResult: TAtlasTrackerWriteResult)
        begin
          Logged(mProvider, 'Beenden', AResult);
          mDone(AResult);
        end);
    end;
end;

function TAtlasIdeTrackerSync.PrepareHandler(const AProvider: IAtlasTrackerProvider;
  const ATarget: TAtlasTrackerTarget; const AStateField: string;
  const ASession: IInterface): TProc<TAtlasTrackerEndDialog>;
var
  mOwner: TAtlasIdeTrackerSync;
  mProvider: IAtlasTrackerProvider;
  mTarget: TAtlasTrackerTarget;
  mField: string;
  mSession: IInterface;
begin
  mOwner := Self;
  mProvider := AProvider;
  mTarget := ATarget;
  mField := AStateField;
  mSession := ASession;
  Result :=
    procedure(ADialog: TAtlasTrackerEndDialog)
    begin
      (mSession as IAtlasTrackerEndSession).SetDialog(ADialog);
      mOwner.LoadEndValues(mProvider, mTarget, mField, mSession);
    end;
end;

procedure TAtlasIdeTrackerSync.LoadEndValues(const AProvider: IAtlasTrackerProvider;
  const ATarget: TAtlasTrackerTarget; const AStateField: string; const ASession: IInterface);
var
  mWriter: IAtlasTrackerWriter;
  mProvider: IAtlasTrackerProvider;
  mTransports: TAtlasIdeTrackerTransport;
  mTarget: TAtlasTrackerTarget;
  mField: string;
  mSession: IAtlasTrackerEndSession;
  mUsers, mStates: TArray<string>;
begin
  mWriter := WriterOf(AProvider);
  mTransports := FTransport;
  if (mWriter = nil) or not Assigned(mTransports) then
    Exit;
  mProvider := AProvider;
  mTarget := ATarget;
  mField := AStateField;
  mSession := ASession as IAtlasTrackerEndSession;
  mUsers := nil;
  mStates := nil;
  // Ohne Leserecht auf Benutzer oder Felder bleiben die Klapplisten frei beschreibbar.
  FWorker.Run(
    procedure
    var
      mTransport: IAtlasCiTransport;
    begin
      try
        mTransport := mTransports(mProvider, mTarget);
        if mTransport = nil then
          Exit;
        mWriter.Values(mTarget, mTransport, TAtlasTrackerValueKind.Users, '', TAtlasTrackerWorkflow.WriteTimeoutMs,
          mUsers);
        mWriter.Values(mTarget, mTransport, TAtlasTrackerValueKind.States, mField,
          TAtlasTrackerWorkflow.WriteTimeoutMs, mStates);
      except
        on E: Exception do
          TAtlasGuard.Log('Tracker nachführen: Werte mit ' + E.ClassName + ' abgebrochen');
      end;
    end,
    procedure
    begin
      if mSession.Dialog = nil then
        Exit;
      mSession.Dialog.SetUsers(mUsers);
      mSession.Dialog.SetStates(mStates);
    end);
end;

procedure TAtlasIdeTrackerSync.SendComment(const AProvider: IAtlasTrackerProvider;
  const ATarget: TAtlasTrackerTarget; const AKey, AText: string; const ADone: TAtlasTrackerSendDone);
var
  mOwner: TAtlasIdeTrackerSync;
  mProvider: IAtlasTrackerProvider;
  mKey: string;
  mDone: TAtlasTrackerSendDone;
begin
  if not Enabled(AProvider, ATarget) or (Trim(AText) = '') then
  begin
    ADone(TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.NotConfigured, 0, ''));
    Exit;
  end;
  mOwner := Self;
  mProvider := AProvider;
  mKey := AKey;
  mDone := ADone;
  Apply(AProvider, ATarget, AKey, TAtlasTrackerChange.CommentOnly(AText),
    procedure(const AResult: TAtlasTrackerWriteResult)
    begin
      Logged(mProvider, 'Kommentar', AResult);
      if AResult.Succeeded then
        mOwner.Report(TAtlasStrings.Fmt(TAtlasTextId.TrackerCommentSent, [mKey]));
      mDone(AResult);
    end);
end;

end.
