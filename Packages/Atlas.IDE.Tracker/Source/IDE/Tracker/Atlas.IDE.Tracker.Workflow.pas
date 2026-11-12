unit Atlas.IDE.Tracker.Workflow;

// Tracker nachführen in der IDE (#1266):
// - Nach „Beginnen“ (Branch angelegt, gewechselt oder Kennung gemerkt):
//   Zustand issues.startState, mit issues.assignOnStart mir zuweisen,
//   Kommentar issues.startComment; das Ergebnis als eine Zeile in der
//   Meldungsansicht, bei Fehler mit Grund (der Branch bleibt).
// - „Beenden“: {commits} im Hintergrund über IAtlasVcsLocalWork.Outgoing,
//   dann der Dialog „ATL-123 beenden“ (TAtlasTrackerEndDialog) mit Benutzern
//   und Zuständen vom Tracker; geschrieben wird nur mit „Senden“.
// - Zustandsmaschine (#2122): Bietet der Anbieter IAtlasTrackerStateRules,
//   liest „Beginnen“ zuerst die erlaubten Übergänge des Issues und löst den
//   Übergang nach issues.startState aus (TAtlasTrackerWorkflow.FitStart);
//   führt keiner dorthin, bleibt der Zustand, und die Zeile nennt die ab hier
//   erlaubten Übergänge. Nach einem Übergang liest Atlas den neuen Zustand
//   einmal (benannte Ereignisse verraten ihr Ziel nicht). Der
//   Beenden-Dialog bekommt die Regeln mit den übrigen Werten (SetRules).
// - Sprint beim Beginnen (#2128): Ein mitgegebener Sprint geht im selben
//   Befehl wie Zustand und Zuweisung hinaus (TAtlasTrackerWrite.Sprint) und
//   steht in derselben Zeile; nach dem Schreiben lädt AWritten Board und
//   Sprint-Kachel neu.
// - Ablauf-Reihenfolge (#2123): Mit issues.endTime und Zeiterfassung steht
//   die erfasste Zeit (Hook TimeSeconds) im Dialog, mit issues.endFields je
//   Feld eine Zeile mit Werten vom Tracker (IAtlasTrackerFields). „Senden“
//   schreibt über TAtlasTrackerEndSteps Zeit → Felder → Kommentar → Zustand
//   bzw. Übergang und hält beim ersten Fehler an; gebuchte Zeit meldet der
//   Hook TimeBooked an die Zeiterfassung (auch nach Abbrechen), damit sie
//   nicht noch einmal angeboten wird. Ohne Zeitbuchung des Anbieters bzw.
//   ohne Felder (GitHub) bleiben die Abschnitte weg.
// - Kommentar aus der Vorschau (SendComment).
// - Zeit buchen (#1267, BookTime, TimeSettings) für die Zeiterfassung
//   (Atlas.IDE.Tracker.TimeTracking); unabhängig von issues.syncState.
// - Kommentarfeld des Dialogs als Kommentar-Editor (#1278, Hook
//   CommentAssist, Feld "end"); ohne Hook bzw. mit issues.commentEditor aus
//   ein einfaches Textfeld.
// Nur mit issues.syncState und einem Anbieter, der IAtlasTrackerWriter
// umsetzt (Enabled); sonst bleibt „Beenden“ die Rückfrage von „Meine Issues“.
// Einstellungen je Verbindung (issues.connections) vor den globalen. Netz im
// Hintergrund über TAtlasVcsWorker (Stop beim Entladen), je Schreiben
// höchstens TAtlasTrackerWorkflow.cWriteTimeoutMs; nichts wird wiederholt.
// Protokoll anonym: Anbieter, Art und Ergebnis, nie Adresse, Kennung,
// Kommentar oder Token.

interface

uses
  System.SysUtils,
  Atlas.Core.Ci.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.EndSteps,
  Atlas.Core.Tracker.CommentEditor,
  Atlas.Core.Tracker.Workflow,
  Atlas.Core.VersionControl.Worker,
  Atlas.UI.Tracker.EndDialog;

type
  /// <summary>Transport mit dem Token aus dem Anmeldespeicher; nil ohne Token. Läuft im Hintergrund.</summary>
  TAtlasIdeTrackerTransport = reference to function(const AProvider: IAtlasTrackerProvider;
    const ATarget: TAtlasTrackerTarget): IAtlasCiTransport;
  /// <summary>{time} für AKey (#1267); '' ohne Zeiterfassung.</summary>
  TAtlasIdeTrackerTimeText = reference to function(const AKey: string): string;
  /// <summary>Erfasste Zeit des aktuellen Issues AKey in Sekunden (#2123); 0 ohne.</summary>
  TAtlasIdeTrackerTimeSeconds = reference to function(const AKey: string): Int64;
  /// <summary>Im Beenden-Dialog wurden ASeconds der erfassten Zeit von AKey gebucht (#2123).</summary>
  TAtlasIdeTrackerTimeBooked = reference to procedure(const AKey: string; ASeconds: Int64);
  /// <summary>Kommentar-Editor für Feld AField zu AKey (#1278); nil mit issues.commentEditor aus.</summary>
  TAtlasIdeTrackerAssist = reference to function(const ATarget: TAtlasTrackerTarget;
    const AKey, AField: string): IAtlasCommentAssist;

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

  /// <summary>„Beginnen“ unter einer Zustandsmaschine (#2122): geschriebene Änderung, gelesene Regeln, ob kein
  /// Übergang nach issues.startState führte, Zustand danach und Ergebnis.</summary>
  TAtlasIdeTrackerStarted = record
    Change: TAtlasTrackerWrite;
    Rules: TAtlasTrackerStateRules;
    Blocked: Boolean;
    /// <summary>Nach einem Übergang gelesener Zustand; '' ohne.</summary>
    NewState: string;
    Outcome: TAtlasTrackerWriteResult;
    class function Create(const AChange: TAtlasTrackerWrite): TAtlasIdeTrackerStarted; static;
  end;

  TAtlasIdeTrackerSync = class
  public const
    /// <summary>Zeitlimit je Aufruf der Versionsverwaltung für {commits}.</summary>
    cVcsTimeoutMs = 10000;
    /// <summary>Weniger erfasste Zeit zeigt der Beenden-Dialog nicht zum Buchen an (wie der Zeitdialog).</summary>
    cMinTimeSeconds = 60;
  private
    FWorker: TAtlasVcsWorker;
    FTransport: TAtlasIdeTrackerTransport;
    FReport: TProc<string>;
    FTimeText: TAtlasIdeTrackerTimeText;
    FTimeSeconds: TAtlasIdeTrackerTimeSeconds;
    FTimeBooked: TAtlasIdeTrackerTimeBooked;
    FCommentAssist: TAtlasIdeTrackerAssist;
    FStopped: Boolean;
    procedure Report(const AText: string);
    procedure ShowEnd(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget;
      const AInput: TAtlasIdeTrackerEnd; const AOptions: TAtlasTrackerSyncOptions; const ACommits: string;
      const AEnded: TProc<TAtlasTrackerWrite>);
    function EndRequest(const AProvider: IAtlasTrackerProvider; const AInput: TAtlasIdeTrackerEnd;
      const AOptions: TAtlasTrackerSyncOptions; const ACommits: string): TAtlasTrackerEndRequest;
    procedure Finished(const AKey: string; const AOutcome: TAtlasTrackerEndOutcome;
      const AEnded: TProc<TAtlasTrackerWrite>);
    function SendHandler(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget;
      const AKey: string): TAtlasTrackerEndSendEvent;
    procedure RunEnd(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget; const AKey: string;
      const APlan: TAtlasTrackerEndPlan; const AProgress: TAtlasTrackerEndProgress; const ADone: TAtlasTrackerEndDone);
    function PrepareHandler(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget;
      const AKey, AStateField: string; const ASession: IInterface): TProc<TAtlasTrackerEndDialog>;
    procedure BindComment(ADialog: TAtlasTrackerEndDialog; const ATarget: TAtlasTrackerTarget; const AKey: string);
    procedure LoadEndValues(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget;
      const AKey, AStateField: string; const ASession: IInterface);
    procedure StartWithRules(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget;
      const AKey: string; const AChange: TAtlasTrackerWrite; const AField: string; const AWritten: TProc);
    procedure ReportStart(const AKey: string; const AStarted: TAtlasIdeTrackerStarted);
    class procedure Logged(const AProvider: IAtlasTrackerProvider; const AWhat: string;
      const AResult: TAtlasTrackerWriteResult); static;
    /// <summary>Protokoll: AWhat mit der Ausnahme AError abgebrochen (nur die Klasse, nie die Meldung).</summary>
    class procedure Aborted(const AWhat: string; AError: Exception); static;
  public
    /// <summary>AReport: Zeile in die Meldungsansicht.</summary>
    constructor Create(const ATransport: TAtlasIdeTrackerTransport; const AReport: TProc<string>);
    destructor Destroy; override;
    /// <summary>Keine Ergebnisse mehr; kurz auf laufende Zugriffe warten (beim Entladen).</summary>
    procedure Stop;
    /// <summary>Einstellungen issues.* mit den Werten der Verbindung zum Server von ATarget.</summary>
    class function Options(const ATarget: TAtlasTrackerTarget): TAtlasTrackerSyncOptions; static;
    /// <summary>Felder des Anbieters (#2123); nil, wenn er keine benannten Felder hat (GitHub).</summary>
    class function FieldsOf(const AProvider: IAtlasTrackerProvider): IAtlasTrackerFields; static;
    /// <summary>Schreibzugriff des Anbieters; nil, wenn er nicht schreiben kann.</summary>
    class function WriterOf(const AProvider: IAtlasTrackerProvider): IAtlasTrackerWriter; static;
    /// <summary>Regeln des Zustandsfeldes (#2122); nil, wenn der Anbieter keine kennt (GitHub).</summary>
    class function RulesOf(const AProvider: IAtlasTrackerProvider): IAtlasTrackerStateRules; static;
    /// <summary>issues.syncState an, der Anbieter kann schreiben und ein Server ist eingetragen.</summary>
    function Enabled(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget): Boolean;
    /// <summary>Nach „Beginnen“: Zustand, Zuweisung, Kommentar und ASprint (#2128, nicht gesetzt = keiner) im
    /// Hintergrund schreiben, Ergebnis als Zeile; AWritten (darf nil sein) im Hauptthread nach dem Schreiben.
    /// </summary>
    procedure Started(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget;
      const AKey, ABranch: string; const ASprint: TAtlasTrackerSprintRef; const AWritten: TProc);
    /// <summary>„Beenden“ mit Dialog; AEnded nach erfolgreichem „Senden“ (bzw. ohne etwas zu schreiben) mit der
    /// geschriebenen Änderung. Abbrechen ändert nichts.</summary>
    procedure EndIssue(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget;
      const AInput: TAtlasIdeTrackerEnd; const AEnded: TProc<TAtlasTrackerWrite>);
    /// <summary>AChange auf AKey schreiben (Hintergrund); ADone im Hauptthread, genau einmal (nach Stop nie).
    /// </summary>
    procedure Apply(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget; const AKey: string;
      const AChange: TAtlasTrackerWrite; const ADone: TAtlasTrackerSendDone);
    /// <summary>Kommentar aus der Vorschau; ADone wie bei Apply.</summary>
    procedure SendComment(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget;
      const AKey, AText: string; const ADone: TAtlasTrackerSendDone);
    /// <summary>Zeit-Schreibzugriff des Anbieters (#1267); nil ohne Zeiterfassung (GitHub).</summary>
    class function TimeWriterOf(const AProvider: IAtlasTrackerProvider): IAtlasTrackerTimeWriter; static;
    /// <summary>AItem auf AKey buchen (#1267, Work Item); ADone wie bei Apply.</summary>
    procedure BookTime(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget; const AKey: string;
      const AItem: TAtlasTrackerWorkItem; const ADone: TAtlasTrackerSendDone);
    /// <summary>Zeiterfassung und Arbeitstypen des Projekts von AKey (#1267) im Hintergrund; ADone im Hauptthread
    /// (nach Stop nie).</summary>
    procedure TimeSettings(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget;
      const AKey: string; const ADone: TProc<TAtlasTrackerTimeSettings, TAtlasTrackerWriteResult>);
    /// <summary>{time} für den Kommentar beim Beenden (#1267).</summary>
    property TimeText: TAtlasIdeTrackerTimeText read FTimeText write FTimeText;
    /// <summary>Erfasste Zeit für den Abschnitt „Zeit“ im Beenden-Dialog (#2123).</summary>
    property TimeSeconds: TAtlasIdeTrackerTimeSeconds read FTimeSeconds write FTimeSeconds;
    /// <summary>Im Beenden-Dialog gebuchte Zeit an die Zeiterfassung (#2123).</summary>
    property TimeBooked: TAtlasIdeTrackerTimeBooked read FTimeBooked write FTimeBooked;
    /// <summary>Kommentar-Editor im Beenden-Dialog (#1278).</summary>
    property CommentAssist: TAtlasIdeTrackerAssist read FCommentAssist write FCommentAssist;
  end;

implementation

uses
  System.Math,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Tracker.Transitions,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Tracker.Connections,
  Atlas.Core.VersionControl.Contract,
  Atlas.UI.Tracker.Strings,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Contracts.VersionControl;

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

{ TAtlasIdeTrackerStarted }

class function TAtlasIdeTrackerStarted.Create(const AChange: TAtlasTrackerWrite): TAtlasIdeTrackerStarted;
begin
  Result.Change := AChange;
  Result.Rules := Default(TAtlasTrackerStateRules);
  Result.Blocked := False;
  Result.NewState := '';
  Result.Outcome := TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.Network, 0, '');
end;

type
  /// <summary>Zugriff auf ein Issue im Hintergrund: Schreiben, Regeln, Ziel, Transport, Kennung, Zustandsfeld.
  /// </summary>
  TAtlasIssueCall = record
    Writer: IAtlasTrackerWriter;
    Rules: IAtlasTrackerStateRules;
    /// <summary>Felder und Zeitbuchung (#2123); nil, wenn der Anbieter sie nicht kennt.</summary>
    Fields: IAtlasTrackerFields;
    Time: IAtlasTrackerTimeWriter;
    Target: TAtlasTrackerTarget;
    Transport: IAtlasCiTransport;
    Key: string;
    Field: string;
  end;

  /// <summary>Werte für den Beenden-Dialog: Benutzer, Zustände und Regeln (#2122); Werte je Feld in der Reihenfolge
  /// von FieldNames, Felder des Projekts und Zeiterfassung (#2123).</summary>
  TAtlasEndValues = record
    Users: TArray<string>;
    States: TArray<string>;
    Rules: TAtlasTrackerStateRules;
    FieldNames: TArray<string>;
    FieldValues: TArray<TArray<string>>;
    KnownFields: TArray<string>;
    WithTime: Boolean;
    Time: TAtlasTrackerTimeSettings;
    TimeRead: Boolean;
  end;

function IssueCall(const AWriter: IAtlasTrackerWriter; const ARules: IAtlasTrackerStateRules;
  const ATarget: TAtlasTrackerTarget; const AKey, AField: string): TAtlasIssueCall;
begin
  Result.Writer := AWriter;
  Result.Rules := ARules;
  Result.Fields := nil;
  Result.Time := nil;
  Result.Target := ATarget;
  Result.Transport := nil;
  Result.Key := AKey;
  Result.Field := AField;
end;

/// <summary>Im Hintergrund: Regeln lesen, Änderung anpassen (FitStart), schreiben und nach einem Übergang den
/// Zustand einmal lesen. Ohne lesbare Regeln wie bisher: Befehl mit dem Wert, YouTrack begründet eine Ablehnung.
/// </summary>
procedure RunStart(const ACall: TAtlasIssueCall; var AStarted: TAtlasIdeTrackerStarted);
var
  mAfter: TAtlasTrackerStateRules;
begin
  if ACall.Rules.StateRules(ACall.Target, ACall.Transport, ACall.Key, ACall.Field,
    TAtlasTrackerWorkflow.cWriteTimeoutMs, AStarted.Rules).Succeeded then
  begin
    AStarted.Change := TAtlasTrackerWorkflow.FitStart(AStarted.Change, AStarted.Rules, AStarted.Blocked);
  end;
  AStarted.Outcome := ACall.Writer.Apply(ACall.Target, ACall.Transport, ACall.Key, AStarted.Change,
    TAtlasTrackerWorkflow.cWriteTimeoutMs);
  if AStarted.Outcome.Succeeded and (AStarted.Change.Transition.Id <> '') and ACall.Rules.StateRules(ACall.Target,
    ACall.Transport, ACall.Key, ACall.Field, TAtlasTrackerWorkflow.cWriteTimeoutMs, mAfter).Succeeded then
  begin
    AStarted.NewState := mAfter.Current;
  end;
end;

/// <summary>Werte je Feld aus AValues.FieldNames, die Felder des Projekts und die Zeiterfassung (#2123).</summary>
procedure ReadEndSteps(const ACall: TAtlasIssueCall; var AValues: TAtlasEndValues);
var
  mName: string;
  mValues: TArray<string>;
begin
  AValues.FieldValues := nil;
  if (ACall.Fields <> nil) and (Length(AValues.FieldNames) > 0) then
  begin
    for mName in AValues.FieldNames do
    begin
      ACall.Fields.FieldValues(ACall.Target, ACall.Transport, ACall.Key, mName, TAtlasTrackerWorkflow.cWriteTimeoutMs,
        mValues);
      AValues.FieldValues := AValues.FieldValues + [mValues];
    end;
    ACall.Fields.FieldValues(ACall.Target, ACall.Transport, ACall.Key, '', TAtlasTrackerWorkflow.cWriteTimeoutMs,
      AValues.KnownFields);
  end;
  AValues.TimeRead := AValues.WithTime and (ACall.Time <> nil) and ACall.Time.TimeSettings(ACall.Target,
    ACall.Transport, ACall.Key, TAtlasTrackerWorkflow.cWriteTimeoutMs, AValues.Time).Succeeded;
end;

/// <summary>Benutzer, Zustände und Regeln für den Beenden-Dialog im Hintergrund; AValues bringt die Feldnamen und ob
/// Zeit gefragt ist. Ohne Leserecht bleiben die Klapplisten frei beschreibbar; ohne Regeln (GitHub) bleibt die Liste
/// der Zustände.</summary>
procedure ReadEndValues(const ACall: TAtlasIssueCall; var AValues: TAtlasEndValues);
begin
  AValues.Users := nil;
  AValues.States := nil;
  AValues.Rules := Default(TAtlasTrackerStateRules);
  ACall.Writer.Values(ACall.Target, ACall.Transport, TAtlasTrackerValueKind.Users, '',
    TAtlasTrackerWorkflow.cWriteTimeoutMs, AValues.Users);
  ACall.Writer.Values(ACall.Target, ACall.Transport, TAtlasTrackerValueKind.States, ACall.Field,
    TAtlasTrackerWorkflow.cWriteTimeoutMs, AValues.States);
  if ACall.Rules <> nil then
  begin
    ACall.Rules.StateRules(ACall.Target, ACall.Transport, ACall.Key, ACall.Field,
      TAtlasTrackerWorkflow.cWriteTimeoutMs, AValues.Rules);
  end;
  ReadEndSteps(ACall, AValues);
end;

/// <summary>Was der Dialog zusätzlich braucht (#2123): Namen seiner Feldzeilen und ob er „Zeit“ zeigt.</summary>
function EndValuesFor(ADialog: TAtlasTrackerEndDialog): TAtlasEndValues;
var
  mRow: TAtlasEndFieldRow;
begin
  Result := Default(TAtlasEndValues);
  if ADialog = nil then
  begin
    Exit;
  end;
  for mRow in ADialog.Parts.Fields do
  begin
    Result.FieldNames := Result.FieldNames + [mRow.Name];
  end;
  Result.WithTime := ADialog.Parts.BookTime <> nil;
end;

/// <summary>Nachgeladene Werte der Felder und der Zeiterfassung in den Dialog (#2123).</summary>
procedure ShowEndSteps(ADialog: TAtlasTrackerEndDialog; const AValues: TAtlasEndValues);
var
  mIndex: Integer;
begin
  for mIndex := 0 to Min(High(AValues.FieldNames), High(AValues.FieldValues)) do
  begin
    ADialog.Rows.SetFieldValues(AValues.FieldNames[mIndex], AValues.FieldValues[mIndex]);
  end;
  ADialog.Rows.SetKnownFields(AValues.KnownFields);
  if AValues.TimeRead then
  begin
    ADialog.Rows.SetWorkTypes(AValues.Time.WorkTypes);
    if not AValues.Time.Enabled then
    begin
      ADialog.Rows.SetTimeOff;
    end;
  end;
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
  begin
    Exit;
  end;
  FStopped := True;
  // Höchstens die Zeitgrenze eines Schreibens; danach kommt kein Ergebnis mehr an.
  FWorker.Stop(1000);
  FTransport := nil;
  FReport := nil;
  FTimeText := nil;
  FTimeSeconds := nil;
  FTimeBooked := nil;
  FCommentAssist := nil;
end;

procedure TAtlasIdeTrackerSync.Report(const AText: string);
begin
  if Assigned(FReport) and (AText <> '') then
  begin
    FReport(AText);
  end;
end;

class function TAtlasIdeTrackerSync.Options(const ATarget: TAtlasTrackerTarget): TAtlasTrackerSyncOptions;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  Result := TAtlasTrackerSyncOptions.Create(mSettings.IssuesSyncState, mSettings.IssuesStateField,
    mSettings.IssuesAssigneeField).WithStart(mSettings.IssuesStartState, mSettings.IssuesAssignOnStart,
    mSettings.IssuesStartComment).WithEnd(mSettings.IssuesEndStates,
    TAtlasTrackerWorkflow.EndCommentFor(mSettings.IssuesEndComment, TAtlasTrackerStrings.English)).WithReview(
    mSettings.IssuesReviewStates).WithEndSteps(mSettings.IssuesEndFields, mSettings.IssuesEndTime);
  Result := TAtlasTrackerWorkflow.ForConnection(Result, TAtlasTrackerConnections.Read(mSettings.IssuesConnections),
    ATarget);
end;

class function TAtlasIdeTrackerSync.WriterOf(const AProvider: IAtlasTrackerProvider): IAtlasTrackerWriter;
begin
  if (AProvider = nil) or not Supports(AProvider, IAtlasTrackerWriter, Result) then
  begin
    Result := nil;
  end;
end;

class function TAtlasIdeTrackerSync.FieldsOf(const AProvider: IAtlasTrackerProvider): IAtlasTrackerFields;
begin
  if (AProvider = nil) or not Supports(AProvider, IAtlasTrackerFields, Result) then
  begin
    Result := nil;
  end;
end;

class function TAtlasIdeTrackerSync.RulesOf(const AProvider: IAtlasTrackerProvider): IAtlasTrackerStateRules;
begin
  if (AProvider = nil) or not Supports(AProvider, IAtlasTrackerStateRules, Result) then
  begin
    Result := nil;
  end;
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
  begin
    mName := AProvider.Name;
  end;
  // Anonym: Anbieter, Art, Ergebnis; nie Adresse, Kennung, Kommentar oder Token.
  if AResult.Succeeded then
  begin
    TAtlasGuard.Log(Format('Tracker nachführen: %s %s geschrieben', [mName, AWhat]));
  end
  else
  begin
    TAtlasGuard.Log(Format('Tracker nachführen: %s %s nicht geschrieben (%s, %d)', [mName, AWhat,
      TAtlasCiBuild.ErrorKey(AResult.Error), AResult.Status]));
  end;
end;

class procedure TAtlasIdeTrackerSync.Aborted(const AWhat: string; AError: Exception);
begin
  TAtlasGuard.Log(Format('Tracker nachführen: %s mit %s abgebrochen', [AWhat, AError.ClassName]));
end;

procedure TAtlasIdeTrackerSync.Apply(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget;
  const AKey: string; const AChange: TAtlasTrackerWrite; const ADone: TAtlasTrackerSendDone);
var
  mWriter: IAtlasTrackerWriter;
  mProvider: IAtlasTrackerProvider;
  mTransports: TAtlasIdeTrackerTransport;
  mTarget: TAtlasTrackerTarget;
  mKey: string;
  mChange: TAtlasTrackerWrite;
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
        begin
          mResult := TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.NotConfigured, 0, '');
        end
        else
        begin
          mResult := mWriter.Apply(mTarget, mTransport, mKey, mChange, TAtlasTrackerWorkflow.cWriteTimeoutMs);
        end;
      except
        on E: Exception do
        begin
          mResult := TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.Network, 0, '');
          Aborted('Schreiben', E);
        end;
      end;
    end,
    procedure
    begin
      mDone(mResult);
    end) then
  begin
    ADone(TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.Cancelled, 0, ''));
  end;
end;

procedure TAtlasIdeTrackerSync.Started(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget;
  const AKey, ABranch: string; const ASprint: TAtlasTrackerSprintRef; const AWritten: TProc);
var
  mOptions: TAtlasTrackerSyncOptions;
  mChange: TAtlasTrackerWrite;
  mOwner: TAtlasIdeTrackerSync;
  mProvider: IAtlasTrackerProvider;
  mKey: string;
  mWritten: TProc;
begin
  if not Enabled(AProvider, ATarget) then
  begin
    Exit;
  end;
  mOptions := Options(ATarget);
  if not mOptions.HasStartWork and not ASprint.IsSet then
  begin
    Exit;
  end;
  mChange := TAtlasTrackerWorkflow.StartChange(mOptions, TAtlasTrackerPlaceholders.Create(AKey, ABranch));
  // Sprint (#2128) im selben Befehl wie Zustand und Zuweisung.
  mChange.Sprint := ASprint;
  // Zustandsmaschine (#2122): erst die erlaubten Übergänge lesen, dann den passenden auslösen.
  if (mChange.State <> '') and (RulesOf(AProvider) <> nil) then
  begin
    StartWithRules(AProvider, ATarget, AKey, mChange, mOptions.StateField, AWritten);
    Exit;
  end;
  mOwner := Self;
  mProvider := AProvider;
  mKey := AKey;
  mWritten := AWritten;
  Apply(AProvider, ATarget, AKey, mChange,
    procedure(const AResult: TAtlasTrackerWriteResult)
    begin
      Logged(mProvider, 'Beginnen', AResult);
      if AResult.Succeeded then
      begin
        mOwner.Report(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.TrackerStartSynced,
          [mKey, TAtlasTrackerEndDialog.SummaryText(mChange)]));
        if Assigned(mWritten) then
        begin
          mWritten();
        end;
      end
      else
      begin
        mOwner.Report(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.TrackerStartFailed,
          [mKey, TAtlasTrackerEndDialog.ErrorText(mKey, AResult)]));
      end;
    end);
end;

procedure TAtlasIdeTrackerSync.StartWithRules(const AProvider: IAtlasTrackerProvider;
  const ATarget: TAtlasTrackerTarget; const AKey: string; const AChange: TAtlasTrackerWrite; const AField: string;
  const AWritten: TProc);
var
  mWritten: TProc;
  mOwner: TAtlasIdeTrackerSync;
  mProvider: IAtlasTrackerProvider;
  mTransports: TAtlasIdeTrackerTransport;
  mCall: TAtlasIssueCall;
  mStarted: TAtlasIdeTrackerStarted;
begin
  mOwner := Self;
  mProvider := AProvider;
  mTransports := FTransport;
  mCall := IssueCall(WriterOf(AProvider), RulesOf(AProvider), ATarget, AKey, AField);
  mStarted := TAtlasIdeTrackerStarted.Create(AChange);
  mWritten := AWritten;
  if (mCall.Writer = nil) or not Assigned(mTransports) then
  begin
    Exit;
  end;
  FWorker.Run(
    procedure
    begin
      try
        mCall.Transport := mTransports(mProvider, mCall.Target);
        if mCall.Transport = nil then
        begin
          mStarted.Outcome := TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.NotConfigured, 0, '');
          Exit;
        end;
        RunStart(mCall, mStarted);
      except
        on E: Exception do
        begin
          mStarted.Outcome := TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.Network, 0, '');
          Aborted('Beginnen', E);
        end;
      end;
    end,
    procedure
    begin
      Logged(mProvider, 'Beginnen', mStarted.Outcome);
      mOwner.ReportStart(mCall.Key, mStarted);
      if mStarted.Outcome.Succeeded and Assigned(mWritten) then
      begin
        mWritten();
      end;
    end);
end;

procedure TAtlasIdeTrackerSync.ReportStart(const AKey: string; const AStarted: TAtlasIdeTrackerStarted);
var
  mNames: TArray<string>;
  mIndex: Integer;
begin
  if not AStarted.Outcome.Succeeded then
  begin
    Report(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.TrackerStartFailed,
      [AKey, TAtlasTrackerEndDialog.ErrorText(AKey, AStarted.Outcome)]));
    Exit;
  end;
  if AStarted.Change.HasWork then
  begin
    Report(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.TrackerStartSynced,
      [AKey, TAtlasTrackerEndDialog.SummaryText(AStarted.Change, AStarted.NewState)]));
  end;
  if not AStarted.Blocked then
  begin
    Exit;
  end;
  // Kein Übergang führt nach issues.startState: der Zustand bleibt, die Zeile nennt die erlaubten.
  mNames := TAtlasTrackerTransitions.Captions(AStarted.Rules);
  if Length(mNames) = 0 then
  begin
    Report(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.TrackerStartNoTransitionNone, [AKey,
      AStarted.Rules.Current]));
    Exit;
  end;
  for mIndex := 0 to High(mNames) do
  begin
    mNames[mIndex] := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.TrackerQuoted, [mNames[mIndex]]);
  end;
  Report(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.TrackerStartNoTransition,
    [AKey, AStarted.Rules.Current, string.Join(', ', mNames)]));
end;

procedure TAtlasIdeTrackerSync.EndIssue(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget;
  const AInput: TAtlasIdeTrackerEnd; const AEnded: TProc<TAtlasTrackerWrite>);
var
  mOwner: TAtlasIdeTrackerSync;
  mProvider: IAtlasTrackerProvider;
  mTarget: TAtlasTrackerTarget;
  mInput: TAtlasIdeTrackerEnd;
  mOptions: TAtlasTrackerSyncOptions;
  mEnded: TProc<TAtlasTrackerWrite>;
  mCommits: string;
begin
  if not Enabled(AProvider, ATarget) then
  begin
    Exit;
  end;
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
      mVcs := TAtlasIdeVcs.ForFolder(mInput.Folder, cVcsTimeoutMs);
      if Supports(mVcs, IAtlasVcsLocalWork, mWork) then
      begin
        mCommits := TAtlasTrackerWorkflow.CommitsFor(mWork, mInput.Branch, mInput.Base, mInput.Key);
      end;
    end,
    procedure
    begin
      if not mOwner.FStopped then
      begin
        TAtlasGuard.Run(TAtlasFeature.Tracker,
          procedure
          begin
            mOwner.ShowEnd(mProvider, mTarget, mInput, mOptions, mCommits, mEnded);
          end);
      end;
    end) then
  begin
    ShowEnd(AProvider, ATarget, AInput, mOptions, '', AEnded);
  end;
end;

/// <summary>Was der Dialog zeigt: ohne Felder des Anbieters keine Feldzeilen, Zeit nur mit issues.endTime,
/// Zeitbuchung des Anbieters und mindestens einer Minute erfasster Zeit.</summary>
function TAtlasIdeTrackerSync.EndRequest(const AProvider: IAtlasTrackerProvider; const AInput: TAtlasIdeTrackerEnd;
  const AOptions: TAtlasTrackerSyncOptions; const ACommits: string): TAtlasTrackerEndRequest;
var
  mValues: TAtlasTrackerPlaceholders;
  mOptions: TAtlasTrackerSyncOptions;
  mSeconds: Int64;
begin
  mValues := TAtlasTrackerPlaceholders.Create(AInput.Key, AInput.Branch);
  mValues.Commits := ACommits;
  mValues.PullRequest := AInput.PullRequest;
  if Assigned(FTimeText) then
  begin
    mValues.Time := FTimeText(AInput.Key);
  end;
  mOptions := AOptions;
  if FieldsOf(AProvider) = nil then
  begin
    mOptions.EndFields := nil;
  end;
  Result := TAtlasTrackerEndRequest.Create(AInput.Key, mOptions,
    TAtlasTrackerWorkflow.Fill(AOptions.EndComment, mValues));
  mSeconds := 0;
  if AOptions.EndTime and (TimeWriterOf(AProvider) <> nil) and Assigned(FTimeSeconds) then
  begin
    mSeconds := FTimeSeconds(AInput.Key);
  end;
  if mSeconds >= cMinTimeSeconds then
  begin
    Result.Time := TAtlasTrackerEndTime.Create(mSeconds, TAtlasIdeSettings.Current.IssuesTimeRounding, Date,
      TAtlasTrackerWorkflow.CommitSubjects(ACommits));
  end;
end;

procedure TAtlasIdeTrackerSync.ShowEnd(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget;
  const AInput: TAtlasIdeTrackerEnd; const AOptions: TAtlasTrackerSyncOptions; const ACommits: string;
  const AEnded: TProc<TAtlasTrackerWrite>);
var
  mSession: IAtlasTrackerEndSession;
  mOutcome: TAtlasTrackerEndOutcome;
begin
  mSession := TAtlasTrackerEndSession.Create;
  try
    TAtlasTrackerEndDialog.Execute(EndRequest(AProvider, AInput, AOptions, ACommits),
      SendHandler(AProvider, ATarget, AInput.Key),
      PrepareHandler(AProvider, ATarget, AInput.Key, AOptions.StateField, mSession), mOutcome);
  finally
    // Nachgeladene Werte kommen danach nicht mehr an den freigegebenen Dialog.
    mSession.SetDialog(nil);
  end;
  if not FStopped then
  begin
    Finished(AInput.Key, mOutcome, AEnded);
  end;
end;

/// <summary>Nach dem Dialog: gebuchte Zeit melden (auch nach Abbrechen), Zeile in die Meldungsansicht und bei
/// vollständigem Beenden AEnded.</summary>
procedure TAtlasIdeTrackerSync.Finished(const AKey: string; const AOutcome: TAtlasTrackerEndOutcome;
  const AEnded: TProc<TAtlasTrackerWrite>);
var
  mSummary: string;
begin
  if AOutcome.Progress.TimeBooked and Assigned(FTimeBooked) then
  begin
    FTimeBooked(AKey, AOutcome.TimeSeconds);
  end;
  mSummary := TAtlasTrackerEndTexts.EndSummary(AOutcome.Plan, AOutcome.Progress);
  if not AOutcome.Finished then
  begin
    // Abgebrochen nach einem Teilerfolg: sagen, was schon im Tracker steht.
    if AOutcome.Progress.Wrote then
    begin
      Report(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.TrackerEndPartial, [AKey, mSummary]));
    end;
    Exit;
  end;
  if mSummary <> '' then
  begin
    Report(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.TrackerEndSent, [AKey, mSummary]));
  end;
  AEnded(AOutcome.Plan.Change);
end;

function TAtlasIdeTrackerSync.SendHandler(const AProvider: IAtlasTrackerProvider;
  const ATarget: TAtlasTrackerTarget; const AKey: string): TAtlasTrackerEndSendEvent;
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
    procedure(const APlan: TAtlasTrackerEndPlan; const AProgress: TAtlasTrackerEndProgress;
      const ADone: TAtlasTrackerEndDone)
    begin
      mOwner.RunEnd(mProvider, mTarget, mKey, APlan, AProgress, ADone);
    end;
end;

procedure TAtlasIdeTrackerSync.RunEnd(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget;
  const AKey: string; const APlan: TAtlasTrackerEndPlan; const AProgress: TAtlasTrackerEndProgress;
  const ADone: TAtlasTrackerEndDone);
var
  mProvider: IAtlasTrackerProvider;
  mTransports: TAtlasIdeTrackerTransport;
  mCall: TAtlasTrackerEndCall;
  mPlan: TAtlasTrackerEndPlan;
  mProgress: TAtlasTrackerEndProgress;
  mDone: TAtlasTrackerEndDone;
begin
  mProvider := AProvider;
  mTransports := FTransport;
  mCall := Default(TAtlasTrackerEndCall);
  mCall.Writer := WriterOf(AProvider);
  mCall.Time := TimeWriterOf(AProvider);
  mCall.Fields := FieldsOf(AProvider);
  mCall.Target := ATarget;
  mCall.Key := AKey;
  mCall.TimeoutMs := TAtlasTrackerWorkflow.cWriteTimeoutMs;
  mPlan := APlan;
  mProgress := AProgress;
  mDone := ADone;
  if FStopped or (mCall.Writer = nil) or not Assigned(mTransports) then
  begin
    mProgress.Fail(mPlan, TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.UnknownProvider, 0, ''));
    ADone(mProgress);
    Exit;
  end;
  if not FWorker.Run(
    procedure
    begin
      try
        // Token aus dem Anmeldespeicher ohne Dialog; ohne Token nichts schreiben.
        mCall.Transport := mTransports(mProvider, mCall.Target);
        if mCall.Transport = nil then
        begin
          mProgress.Fail(mPlan, TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.NotConfigured, 0, ''));
          Exit;
        end;
        TAtlasTrackerEndSteps.Run(mCall, mPlan, mProgress);
      except
        on E: Exception do
        begin
          mProgress.Fail(mPlan, TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.Network, 0, ''));
          Aborted('Beenden', E);
        end;
      end;
    end,
    procedure
    begin
      Logged(mProvider, 'Beenden', mProgress.Outcome);
      mDone(mProgress);
    end) then
  begin
    mProgress.Fail(mPlan, TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.Cancelled, 0, ''));
    ADone(mProgress);
  end;
end;

function TAtlasIdeTrackerSync.PrepareHandler(const AProvider: IAtlasTrackerProvider;
  const ATarget: TAtlasTrackerTarget; const AKey, AStateField: string;
  const ASession: IInterface): TProc<TAtlasTrackerEndDialog>;
var
  mOwner: TAtlasIdeTrackerSync;
  mProvider: IAtlasTrackerProvider;
  mTarget: TAtlasTrackerTarget;
  mKey: string;
  mField: string;
  mSession: IInterface;
begin
  mOwner := Self;
  mProvider := AProvider;
  mTarget := ATarget;
  mKey := AKey;
  mField := AStateField;
  mSession := ASession;
  Result :=
    procedure(ADialog: TAtlasTrackerEndDialog)
    begin
      (mSession as IAtlasTrackerEndSession).SetDialog(ADialog);
      mOwner.BindComment(ADialog, mTarget, mKey);
      mOwner.LoadEndValues(mProvider, mTarget, mKey, mField, mSession);
    end;
end;

procedure TAtlasIdeTrackerSync.BindComment(ADialog: TAtlasTrackerEndDialog; const ATarget: TAtlasTrackerTarget;
  const AKey: string);
var
  mAssist: IAtlasCommentAssist;
begin
  // Vorlage steht schon im Feld (kein Entwurf); ein Entwurf des Felds "end" wird mit „Übernehmen“ angeboten.
  mAssist := nil;
  if Assigned(FCommentAssist) then
  begin
    mAssist := FCommentAssist(ATarget, AKey, TAtlasCommentDrafts.cFieldEnd);
  end;
  ADialog.Parts.Editor.Enhanced := mAssist <> nil;
  ADialog.Parts.Editor.Bind(mAssist);
end;

procedure TAtlasIdeTrackerSync.LoadEndValues(const AProvider: IAtlasTrackerProvider;
  const ATarget: TAtlasTrackerTarget; const AKey, AStateField: string; const ASession: IInterface);
var
  mProvider: IAtlasTrackerProvider;
  mTransports: TAtlasIdeTrackerTransport;
  mCall: TAtlasIssueCall;
  mSession: IAtlasTrackerEndSession;
  mValues: TAtlasEndValues;
begin
  mCall := IssueCall(WriterOf(AProvider), RulesOf(AProvider), ATarget, AKey, AStateField);
  mCall.Fields := FieldsOf(AProvider);
  mCall.Time := TimeWriterOf(AProvider);
  mTransports := FTransport;
  if (mCall.Writer = nil) or not Assigned(mTransports) then
  begin
    Exit;
  end;
  mProvider := AProvider;
  mSession := ASession as IAtlasTrackerEndSession;
  mValues := EndValuesFor(mSession.Dialog);
  FWorker.Run(
    procedure
    begin
      try
        mCall.Transport := mTransports(mProvider, mCall.Target);
        if mCall.Transport <> nil then
        begin
          ReadEndValues(mCall, mValues);
        end;
      except
        on E: Exception do
          Aborted('Werte', E);
      end;
    end,
    procedure
    begin
      if mSession.Dialog = nil then
      begin
        Exit;
      end;
      mSession.Dialog.SetUsers(mValues.Users);
      mSession.Dialog.SetStates(mValues.States);
      mSession.Dialog.SetRules(mValues.Rules);
      ShowEndSteps(mSession.Dialog, mValues);
    end);
end;

class function TAtlasIdeTrackerSync.TimeWriterOf(const AProvider: IAtlasTrackerProvider): IAtlasTrackerTimeWriter;
begin
  if (AProvider = nil) or not Supports(AProvider, IAtlasTrackerTimeWriter, Result) then
  begin
    Result := nil;
  end;
end;

procedure TAtlasIdeTrackerSync.BookTime(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget;
  const AKey: string; const AItem: TAtlasTrackerWorkItem; const ADone: TAtlasTrackerSendDone);
var
  mWriter: IAtlasTrackerTimeWriter;
  mProvider: IAtlasTrackerProvider;
  mTransports: TAtlasIdeTrackerTransport;
  mTarget: TAtlasTrackerTarget;
  mKey: string;
  mItem: TAtlasTrackerWorkItem;
  mDone: TAtlasTrackerSendDone;
  mResult: TAtlasTrackerWriteResult;
begin
  mWriter := TimeWriterOf(AProvider);
  mTransports := FTransport;
  if FStopped or (mWriter = nil) or not Assigned(mTransports) then
  begin
    ADone(TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.UnknownProvider, 0, ''));
    Exit;
  end;
  mProvider := AProvider;
  mTarget := ATarget;
  mKey := AKey;
  mItem := AItem;
  mDone := ADone;
  mResult := TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.Network, 0, '');
  if not FWorker.Run(
    procedure
    var
      mTransport: IAtlasCiTransport;
    begin
      try
        mTransport := mTransports(mProvider, mTarget);
        if mTransport = nil then
        begin
          mResult := TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.NotConfigured, 0, '');
        end
        else
        begin
          mResult := mWriter.BookTime(mTarget, mTransport, mKey, mItem, TAtlasTrackerWorkflow.cWriteTimeoutMs);
        end;
      except
        on E: Exception do
        begin
          mResult := TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.Network, 0, '');
          TAtlasGuard.Log('Zeiterfassung: Buchen mit ' + E.ClassName + ' abgebrochen');
        end;
      end;
    end,
    procedure
    begin
      Logged(mProvider, 'Zeitbuchung', mResult);
      mDone(mResult);
    end) then
  begin
    ADone(TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.Cancelled, 0, ''));
  end;
end;

procedure TAtlasIdeTrackerSync.TimeSettings(const AProvider: IAtlasTrackerProvider;
  const ATarget: TAtlasTrackerTarget; const AKey: string;
  const ADone: TProc<TAtlasTrackerTimeSettings, TAtlasTrackerWriteResult>);
var
  mWriter: IAtlasTrackerTimeWriter;
  mProvider: IAtlasTrackerProvider;
  mTransports: TAtlasIdeTrackerTransport;
  mTarget: TAtlasTrackerTarget;
  mKey: string;
  mDone: TProc<TAtlasTrackerTimeSettings, TAtlasTrackerWriteResult>;
  mSettings: TAtlasTrackerTimeSettings;
  mResult: TAtlasTrackerWriteResult;
begin
  mWriter := TimeWriterOf(AProvider);
  mTransports := FTransport;
  if FStopped or (mWriter = nil) or not Assigned(mTransports) then
  begin
    Exit;
  end;
  mProvider := AProvider;
  mTarget := ATarget;
  mKey := AKey;
  mDone := ADone;
  mSettings.Enabled := True;
  mSettings.WorkTypes := nil;
  mResult := TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.Network, 0, '');
  FWorker.Run(
    procedure
    var
      mTransport: IAtlasCiTransport;
    begin
      try
        mTransport := mTransports(mProvider, mTarget);
        if mTransport = nil then
        begin
          mResult := TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.NotConfigured, 0, '');
        end
        else
        begin
          mResult := mWriter.TimeSettings(mTarget, mTransport, mKey, TAtlasTrackerWorkflow.cWriteTimeoutMs, mSettings);
        end;
      except
        on E: Exception do
        begin
          mResult := TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.Network, 0, '');
          TAtlasGuard.Log('Zeiterfassung: Einstellungen mit ' + E.ClassName + ' abgebrochen');
        end;
      end;
    end,
    procedure
    begin
      mDone(mSettings, mResult);
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
  Apply(AProvider, ATarget, AKey, TAtlasTrackerWrite.CommentOnly(AText),
    procedure(const AResult: TAtlasTrackerWriteResult)
    begin
      Logged(mProvider, 'Kommentar', AResult);
      if AResult.Succeeded then
      begin
        mOwner.Report(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.TrackerCommentSent, [mKey]));
      end;
      mDone(AResult);
    end);
end;

end.
