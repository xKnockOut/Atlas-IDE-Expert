unit Atlas.Core.Tracker.SyncPlan;

// Entscheidungen von „Tracker nachführen“ (#1266) ohne IDE prüfbar (#1967); die IDE (Atlas.IDE.Tracker.Workflow)
// ruft nur noch Dialog, Meldungsansicht und Hintergrundarbeiter:
// - Zugriffe auf ein Issue im Hintergrund über die Verträge des Anbieters: „Beginnen“ unter einer
//   Zustandsmaschine (#2122, erst Regeln lesen, dann FitStart, nach einem Übergang den Zustand einmal lesen),
//   Werte für den Beenden-Dialog (Benutzer, Zustände, Regeln, Felder und Zeiterfassung, #2123) und für „Prüfen“
//   (#2126).
// - Was „Beginnen“ schreibt und meldet (StartNote), was der Beenden-Dialog zeigt (Felder nur mit
//   IAtlasTrackerFields, Zeit nur mit issues.endTime, Zeitbuchung und mindestens einer Minute).
// - Einstellungen issues.* mit den Werten der Verbindung (Options) und die anonyme Protokollzeile.

interface

uses
  Atlas.Core.Ci.Contract,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Workflow;

type
  /// <summary>Zugriff auf ein Issue im Hintergrund: Schreiben, Regeln, Felder, Zeitbuchung (nil, wenn der Anbieter
  /// sie nicht kennt), Ziel, Transport, Kennung und Zustandsfeld.</summary>
  TAtlasTrackerIssueCall = record
    Writer: IAtlasTrackerWriter;
    Rules: IAtlasTrackerStateRules;
    Fields: IAtlasTrackerFields;
    Time: IAtlasTrackerTimeWriter;
    Target: TAtlasTrackerTarget;
    Transport: IAtlasCiTransport;
    Key: string;
    Field: string;
  end;

  /// <summary>Werte für den Beenden-Dialog: Benutzer, Zustände und Regeln (#2122); Werte je Feld in der Reihenfolge
  /// von FieldNames, Felder des Projekts und Zeiterfassung (#2123). FieldNames und WithTime gibt der Dialog vor.
  /// </summary>
  TAtlasTrackerEndValues = record
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

  /// <summary>„Beginnen“ unter einer Zustandsmaschine (#2122): geschriebene Änderung, gelesene Regeln, ob kein
  /// Übergang nach issues.startState führte, Zustand danach und Ergebnis.</summary>
  TAtlasTrackerStarted = record
    Change: TAtlasTrackerWrite;
    Rules: TAtlasTrackerStateRules;
    Blocked: Boolean;
    /// <summary>Nach einem Übergang gelesener Zustand; '' ohne.</summary>
    NewState: string;
    Outcome: TAtlasTrackerWriteResult;
    /// <summary>Noch nichts geschrieben; Ergebnis Network, bis der Lauf es setzt.</summary>
    class function Create(const AChange: TAtlasTrackerWrite): TAtlasTrackerStarted; static;
  end;

{$SCOPEDENUMS ON}
  /// <summary>Was die Zeile nach „Beginnen“ über den Zustand sagt: nichts (Übergang gefunden bzw. ohne
  /// Zustandsmaschine), kein Übergang ab hier oder die ab hier erlaubten Übergänge.</summary>
  TAtlasTrackerStartBlock = (None, NoTransitions, Transitions);
{$SCOPEDENUMS OFF}

  /// <summary>Meldungen nach „Beginnen“ unter einer Zustandsmaschine: gescheitert (dann nichts weiter),
  /// geschrieben (Zeile mit der Änderung) und ob kein Übergang nach issues.startState führte.</summary>
  TAtlasTrackerStartNote = record
    Failed: Boolean;
    Synced: Boolean;
    Block: TAtlasTrackerStartBlock;
    /// <summary>Zustand, in dem das Issue blieb.</summary>
    Current: string;
    /// <summary>Anzeigenamen der ab Current erlaubten Übergänge (Block = Transitions).</summary>
    Transitions: TArray<string>;
  end;

  TAtlasTrackerSyncPlan = class
  public const
    /// <summary>Weniger erfasste Zeit zeigt der Beenden-Dialog nicht zum Buchen an (wie der Zeitdialog).</summary>
    cMinTimeSeconds = 60;
  private
    class procedure ReadEndSteps(const ACall: TAtlasTrackerIssueCall; var AValues: TAtlasTrackerEndValues); static;
  public
    /// <summary>Schreibzugriff des Anbieters; nil, wenn er nicht schreiben kann.</summary>
    class function WriterOf(const AProvider: IAtlasTrackerProvider): IAtlasTrackerWriter; static;
    /// <summary>Regeln des Zustandsfeldes (#2122); nil, wenn der Anbieter keine kennt (GitHub).</summary>
    class function RulesOf(const AProvider: IAtlasTrackerProvider): IAtlasTrackerStateRules; static;
    /// <summary>Felder des Anbieters (#2123); nil, wenn er keine benannten Felder hat (GitHub).</summary>
    class function FieldsOf(const AProvider: IAtlasTrackerProvider): IAtlasTrackerFields; static;
    /// <summary>Zeit-Schreibzugriff des Anbieters (#1267); nil ohne Zeiterfassung (GitHub).</summary>
    class function TimeWriterOf(const AProvider: IAtlasTrackerProvider): IAtlasTrackerTimeWriter; static;
    /// <summary>Zugriff auf AKey mit allen Verträgen von AProvider, noch ohne Transport.</summary>
    class function IssueCall(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget;
      const AKey, AField: string): TAtlasTrackerIssueCall; static;
    /// <summary>Im Hintergrund: Regeln lesen, Änderung anpassen (FitStart), schreiben und nach einem Übergang den
    /// Zustand einmal lesen. Ohne lesbare Regeln wie bisher: Befehl mit dem Wert, YouTrack begründet eine
    /// Ablehnung.</summary>
    class procedure RunStart(const ACall: TAtlasTrackerIssueCall; var AStarted: TAtlasTrackerStarted); static;
    /// <summary>Benutzer, Zustände und Regeln für den Beenden-Dialog im Hintergrund, dazu Werte je Feld aus
    /// AValues.FieldNames, die Felder des Projekts und (mit AValues.WithTime) die Zeiterfassung. Ohne Leserecht
    /// bleiben die Klapplisten frei beschreibbar; ohne Regeln (GitHub) bleibt die Liste der Zustände.</summary>
    class procedure ReadEndValues(const ACall: TAtlasTrackerIssueCall; var AValues: TAtlasTrackerEndValues); static;
    /// <summary>Zustände und Regeln für „Prüfen“ im Hintergrund, ohne die Benutzer.</summary>
    class function ReadReviewValues(const ACall: TAtlasTrackerIssueCall): TAtlasTrackerEndValues; static;
    /// <summary>„Beginnen“ schreibt etwas: Zustand, Zuweisung oder Kommentar aus AOptions bzw. ein Sprint.</summary>
    class function WritesOnStart(const AOptions: TAtlasTrackerSyncOptions;
      const ASprint: TAtlasTrackerSprintRef): Boolean; static;
    /// <summary>„Beginnen“ liest erst die Regeln (#2122): ein Zustand ist zu setzen und der Anbieter kennt Regeln.
    /// </summary>
    class function StartsWithRules(const AChange: TAtlasTrackerWrite;
      const AProvider: IAtlasTrackerProvider): Boolean; static;
    /// <summary>Meldungen nach „Beginnen“ unter einer Zustandsmaschine.</summary>
    class function StartNote(const AStarted: TAtlasTrackerStarted): TAtlasTrackerStartNote; static;
    /// <summary>AOptions für den Beenden-Dialog: ohne Felder des Anbieters keine Feldzeilen.</summary>
    class function EndOptions(const AOptions: TAtlasTrackerSyncOptions;
      const AProvider: IAtlasTrackerProvider): TAtlasTrackerSyncOptions; static;
    /// <summary>Der Beenden-Dialog fragt die erfasste Zeit ab: issues.endTime an und der Anbieter bucht Zeit.
    /// </summary>
    class function AsksEndTime(const AOptions: TAtlasTrackerSyncOptions;
      const AProvider: IAtlasTrackerProvider): Boolean; static;
    /// <summary>ASeconds erfasster Zeit reichen für den Abschnitt „Zeit“ (mindestens cMinTimeSeconds).</summary>
    class function ShowsEndTime(ASeconds: Int64): Boolean; static;
    /// <summary>Einstellungen issues.* aus ASettings mit den Werten der Verbindung zum Server von ATarget;
    /// AEnglish wählt die Vorgabe des Kommentars beim Beenden.</summary>
    class function Options(const ASettings: TAtlasPluginSettings; AEnglish: Boolean;
      const ATarget: TAtlasTrackerTarget): TAtlasTrackerSyncOptions; static;
    /// <summary>Anonyme Protokollzeile: Anbieter, Art und Ergebnis; nie Adresse, Kennung, Kommentar oder Token.
    /// </summary>
    class function LogLine(const AProvider: IAtlasTrackerProvider; const AWhat: string;
      const AResult: TAtlasTrackerWriteResult): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Tracker.Connections,
  Atlas.Core.Tracker.Transitions;

const
  // Protokoll anonym: Anbieter, Art und Ergebnis.
  cLogWritten = 'Tracker nachführen: %s %s geschrieben';
  cLogFailed = 'Tracker nachführen: %s %s nicht geschrieben (%s, %d)';

{ TAtlasTrackerStarted }

class function TAtlasTrackerStarted.Create(const AChange: TAtlasTrackerWrite): TAtlasTrackerStarted;
begin
  Result.Change := AChange;
  Result.Rules := Default(TAtlasTrackerStateRules);
  Result.Blocked := False;
  Result.NewState := '';
  Result.Outcome := TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.Network, 0, '');
end;

{ TAtlasTrackerSyncPlan }

class function TAtlasTrackerSyncPlan.WriterOf(const AProvider: IAtlasTrackerProvider): IAtlasTrackerWriter;
begin
  if (AProvider = nil) or not Supports(AProvider, IAtlasTrackerWriter, Result) then
  begin
    Result := nil;
  end;
end;

class function TAtlasTrackerSyncPlan.RulesOf(const AProvider: IAtlasTrackerProvider): IAtlasTrackerStateRules;
begin
  if (AProvider = nil) or not Supports(AProvider, IAtlasTrackerStateRules, Result) then
  begin
    Result := nil;
  end;
end;

class function TAtlasTrackerSyncPlan.FieldsOf(const AProvider: IAtlasTrackerProvider): IAtlasTrackerFields;
begin
  if (AProvider = nil) or not Supports(AProvider, IAtlasTrackerFields, Result) then
  begin
    Result := nil;
  end;
end;

class function TAtlasTrackerSyncPlan.TimeWriterOf(const AProvider: IAtlasTrackerProvider): IAtlasTrackerTimeWriter;
begin
  if (AProvider = nil) or not Supports(AProvider, IAtlasTrackerTimeWriter, Result) then
  begin
    Result := nil;
  end;
end;

class function TAtlasTrackerSyncPlan.IssueCall(const AProvider: IAtlasTrackerProvider;
  const ATarget: TAtlasTrackerTarget; const AKey, AField: string): TAtlasTrackerIssueCall;
begin
  Result.Writer := WriterOf(AProvider);
  Result.Rules := RulesOf(AProvider);
  Result.Fields := FieldsOf(AProvider);
  Result.Time := TimeWriterOf(AProvider);
  Result.Target := ATarget;
  Result.Transport := nil;
  Result.Key := AKey;
  Result.Field := AField;
end;

class procedure TAtlasTrackerSyncPlan.RunStart(const ACall: TAtlasTrackerIssueCall; var AStarted: TAtlasTrackerStarted);
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

class procedure TAtlasTrackerSyncPlan.ReadEndSteps(const ACall: TAtlasTrackerIssueCall;
  var AValues: TAtlasTrackerEndValues);
var
  mIndex: Integer;
  mValues: TArray<string>;
begin
  AValues.FieldValues := nil;
  if (ACall.Fields <> nil) and (Length(AValues.FieldNames) > 0) then
  begin
    SetLength(AValues.FieldValues, Length(AValues.FieldNames));
    for mIndex := 0 to High(AValues.FieldNames) do
    begin
      ACall.Fields.FieldValues(ACall.Target, ACall.Transport, ACall.Key, AValues.FieldNames[mIndex],
        TAtlasTrackerWorkflow.cWriteTimeoutMs, mValues);
      AValues.FieldValues[mIndex] := mValues;
    end;
    ACall.Fields.FieldValues(ACall.Target, ACall.Transport, ACall.Key, '', TAtlasTrackerWorkflow.cWriteTimeoutMs,
      AValues.KnownFields);
  end;
  AValues.TimeRead := AValues.WithTime and (ACall.Time <> nil) and ACall.Time.TimeSettings(ACall.Target,
    ACall.Transport, ACall.Key, TAtlasTrackerWorkflow.cWriteTimeoutMs, AValues.Time).Succeeded;
end;

class procedure TAtlasTrackerSyncPlan.ReadEndValues(const ACall: TAtlasTrackerIssueCall;
  var AValues: TAtlasTrackerEndValues);
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

class function TAtlasTrackerSyncPlan.ReadReviewValues(const ACall: TAtlasTrackerIssueCall): TAtlasTrackerEndValues;
begin
  Result := Default(TAtlasTrackerEndValues);
  ACall.Writer.Values(ACall.Target, ACall.Transport, TAtlasTrackerValueKind.States, ACall.Field,
    TAtlasTrackerWorkflow.cWriteTimeoutMs, Result.States);
  if ACall.Rules <> nil then
  begin
    ACall.Rules.StateRules(ACall.Target, ACall.Transport, ACall.Key, ACall.Field,
      TAtlasTrackerWorkflow.cWriteTimeoutMs, Result.Rules);
  end;
end;

class function TAtlasTrackerSyncPlan.WritesOnStart(const AOptions: TAtlasTrackerSyncOptions;
  const ASprint: TAtlasTrackerSprintRef): Boolean;
begin
  Result := AOptions.HasStartWork or ASprint.IsSet;
end;

class function TAtlasTrackerSyncPlan.StartsWithRules(const AChange: TAtlasTrackerWrite;
  const AProvider: IAtlasTrackerProvider): Boolean;
begin
  Result := (AChange.State <> '') and (RulesOf(AProvider) <> nil);
end;

class function TAtlasTrackerSyncPlan.StartNote(const AStarted: TAtlasTrackerStarted): TAtlasTrackerStartNote;
begin
  Result := Default(TAtlasTrackerStartNote);
  Result.Failed := not AStarted.Outcome.Succeeded;
  if Result.Failed then
  begin
    Exit;
  end;
  Result.Synced := AStarted.Change.HasWork;
  if not AStarted.Blocked then
  begin
    Exit;
  end;
  // Kein Übergang führt nach issues.startState: der Zustand bleibt, die Zeile nennt die erlaubten.
  Result.Current := AStarted.Rules.Current;
  Result.Transitions := TAtlasTrackerTransitions.Captions(AStarted.Rules);
  Result.Block := TAtlasTrackerStartBlock.NoTransitions;
  if Length(Result.Transitions) > 0 then
  begin
    Result.Block := TAtlasTrackerStartBlock.Transitions;
  end;
end;

class function TAtlasTrackerSyncPlan.EndOptions(const AOptions: TAtlasTrackerSyncOptions;
  const AProvider: IAtlasTrackerProvider): TAtlasTrackerSyncOptions;
begin
  Result := AOptions;
  if FieldsOf(AProvider) = nil then
  begin
    Result.EndFields := nil;
  end;
end;

class function TAtlasTrackerSyncPlan.AsksEndTime(const AOptions: TAtlasTrackerSyncOptions;
  const AProvider: IAtlasTrackerProvider): Boolean;
begin
  Result := AOptions.EndTime and (TimeWriterOf(AProvider) <> nil);
end;

class function TAtlasTrackerSyncPlan.ShowsEndTime(ASeconds: Int64): Boolean;
begin
  Result := ASeconds >= cMinTimeSeconds;
end;

class function TAtlasTrackerSyncPlan.Options(const ASettings: TAtlasPluginSettings; AEnglish: Boolean;
  const ATarget: TAtlasTrackerTarget): TAtlasTrackerSyncOptions;
begin
  Result := TAtlasTrackerSyncOptions.Create(ASettings.IssuesSyncState, ASettings.IssuesStateField,
    ASettings.IssuesAssigneeField).WithStart(ASettings.IssuesStartState, ASettings.IssuesAssignOnStart,
    ASettings.IssuesStartComment).WithEnd(ASettings.IssuesEndStates,
    TAtlasTrackerWorkflow.EndCommentFor(ASettings.IssuesEndComment, AEnglish)).WithReview(
    ASettings.IssuesReviewStates).WithEndSteps(ASettings.IssuesEndFields, ASettings.IssuesEndTime).WithGitHub(
    ASettings.IssuesGitHubStateTarget, ASettings.IssuesGitHubProject,
    ASettings.IssuesGitHubAddToProject).WithLinkBranch(ASettings.IssuesGitHubLinkBranch).WithPullRequest(
    ASettings.IssuesGitHubCreatePr, ASettings.IssuesGitHubPrBase, ASettings.IssuesGitHubPrBody,
    ASettings.IssuesGitHubPrDraft);
  Result := TAtlasTrackerWorkflow.ForConnection(Result, TAtlasTrackerConnections.Read(ASettings.IssuesConnections),
    ATarget);
end;

class function TAtlasTrackerSyncPlan.LogLine(const AProvider: IAtlasTrackerProvider; const AWhat: string;
  const AResult: TAtlasTrackerWriteResult): string;
var
  mName: string;
begin
  mName := '';
  if AProvider <> nil then
  begin
    mName := AProvider.Name;
  end;
  if AResult.Succeeded then
  begin
    Exit(Format(cLogWritten, [mName, AWhat]));
  end;
  Result := Format(cLogFailed, [mName, AWhat,
    TAtlasCiBuild.ErrorKey(AResult.Error), AResult.Status]);
end;

end.
