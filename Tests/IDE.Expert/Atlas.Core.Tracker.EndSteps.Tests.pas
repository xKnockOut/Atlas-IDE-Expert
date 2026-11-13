unit Atlas.Core.Tracker.EndSteps.Tests;

// Tests von „Beenden“ in der Reihenfolge des Ablaufs (#2123) ohne Server:
// Zeit → Felder → Kommentar → Übergang gegen einen Anbieter, der jeden Aufruf
// mitschreibt; Anhalten beim ersten Fehler und Wiederaufnahme ohne doppelte
// Zeitbuchung oder zweiten Kommentar; Stand je Schritt; Feldsuche im Text
// einer Ablehnung; Felder beim Beenden je Verbindung (endFields); Prüfung
// des Originals eines Duplikats vor dem ersten Schreiben (#2135); Pull Request
// nach den Feldern und vor dem Kommentar, ohne zweiten beim Fortsetzen (#2136).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tracker')]
  TAtlasTrackerEndStepsTests = class
  public
    [Test]
    procedure PlanSplitsCommentAndTransition;
    [Test]
    procedure RunsInWorkflowOrder;
    [Test]
    procedure StopsAtFirstFailureAndResumes;
    [Test]
    procedure ChangedFieldValueIsWrittenAgain;
    [Test]
    procedure WithoutTimeWriterFailsTimeStep;
    [Test]
    procedure StatesAndFinished;
    [Test]
    procedure MentionedFieldFindsWholeNames;
    [Test]
    procedure EndFieldsPerConnection;
    [Test]
    procedure DuplicateCheckedBeforeWriting;
    [Test]
    procedure CloseGoesWithTransitionPart;
    [Test]
    procedure PullRunsAfterFieldsAndOnlyOnce;
    [Test]
    procedure FailedPullStopsBeforeComment;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Ci.Contract,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Connections,
  Atlas.Core.Tracker.EndSteps,
  Atlas.Core.Tracker.Providers.GitHub,
  Atlas.Core.Tracker.Workflow;

type
  /// <summary>Anbieter, der jeden Schreibzugriff als Zeile mitschreibt; scheitert beim Aufruf FailOn (Text des
  /// Trackers in FailMessage).</summary>
  TFakeEndWriter = class(TInterfacedObject, IAtlasTrackerWriter, IAtlasTrackerTimeWriter, IAtlasTrackerFields)
  private
    function Logged(const ACall: string): TAtlasTrackerWriteResult;
  public
    Calls: TArray<string>;
    FailOn: string;
    FailMessage: string;
    /// <summary>Schließen gelingt nur über den Ersatzweg (Ergebnis mit Fallback).</summary>
    CloseFallback: Boolean;
    function Apply(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport; const AKey: string;
      const AChange: TAtlasTrackerWrite; ATimeoutMs: Integer): TAtlasTrackerWriteResult;
    function Values(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
      AKind: TAtlasTrackerValueKind; const AField: string; ATimeoutMs: Integer;
      out AValues: TArray<string>): TAtlasTrackerWriteResult;
    function TimeSettings(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport; const AKey: string;
      ATimeoutMs: Integer; out ASettings: TAtlasTrackerTimeSettings): TAtlasTrackerWriteResult;
    function BookTime(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport; const AKey: string;
      const AItem: TAtlasTrackerWorkItem; ATimeoutMs: Integer): TAtlasTrackerWriteResult;
    function IsTrackingOff(const AResult: TAtlasTrackerWriteResult): Boolean;
    function FieldValues(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport; const AKey,
      AField: string; ATimeoutMs: Integer; out AValues: TArray<string>): TAtlasTrackerWriteResult;
    function SetField(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport; const AKey, AField,
      AValue: string; ATimeoutMs: Integer): TAtlasTrackerWriteResult;
  end;

function TFakeEndWriter.Logged(const ACall: string): TAtlasTrackerWriteResult;
begin
  Calls := Calls + [ACall];
  if (FailOn <> '') and (ACall = FailOn) then
  begin
    Exit(TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.Invalid, 400, FailMessage));
  end;
  Exit(TAtlasTrackerWriteResult.Ok);
end;

function TFakeEndWriter.Apply(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  const AKey: string; const AChange: TAtlasTrackerWrite; ATimeoutMs: Integer): TAtlasTrackerWriteResult;
begin
  if AChange.Transition.Id <> '' then
  begin
    Exit(Logged('transition ' + AChange.Transition.Id));
  end;
  if AChange.State <> '' then
  begin
    Exit(Logged('state ' + AChange.State));
  end;
  if AChange.Close <> TAtlasTrackerClose.ByState then
  begin
    Result := Logged('close ' + IntToStr(Ord(AChange.Close)) + ' ' + AChange.DuplicateOf);
    Result.Fallback := Result.Succeeded and CloseFallback;
    Exit;
  end;
  Exit(Logged('comment ' + AChange.Comment));
end;

type
  /// <summary>Nur GET: Issue #418 gibt es, alle anderen nicht.</summary>
  TFakeLookupTransport = class(TInterfacedObject, IAtlasCiTransport)
  public
    Calls: Integer;
    function Get(const AUrl: string; ATimeoutMs: Integer; out AStatus: Integer; out AText: string;
      out AError: TAtlasCiFetchError): Boolean;
  end;

function TFakeLookupTransport.Get(const AUrl: string; ATimeoutMs: Integer; out AStatus: Integer; out AText: string;
  out AError: TAtlasCiFetchError): Boolean;
begin
  Inc(Calls);
  AError := TAtlasCiFetchError.None;
  AStatus := 404;
  AText := '{"message":"Not Found"}';
  if AUrl = 'https://api.github.com/repos/beispiel/atlas/issues/418' then
  begin
    AStatus := 200;
    AText := '{"id":9418,"number":418,"title":"Original","state":"open","labels":[],"assignees":[]}';
  end;
  Result := True;
end;

function TFakeEndWriter.Values(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  AKind: TAtlasTrackerValueKind; const AField: string; ATimeoutMs: Integer;
  out AValues: TArray<string>): TAtlasTrackerWriteResult;
begin
  AValues := nil;
  Exit(TAtlasTrackerWriteResult.Ok);
end;

function TFakeEndWriter.TimeSettings(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  const AKey: string; ATimeoutMs: Integer; out ASettings: TAtlasTrackerTimeSettings): TAtlasTrackerWriteResult;
begin
  ASettings := Default(TAtlasTrackerTimeSettings);
  Exit(TAtlasTrackerWriteResult.Ok);
end;

function TFakeEndWriter.BookTime(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  const AKey: string; const AItem: TAtlasTrackerWorkItem; ATimeoutMs: Integer): TAtlasTrackerWriteResult;
begin
  Exit(Logged('time ' + IntToStr(AItem.Minutes)));
end;

function TFakeEndWriter.IsTrackingOff(const AResult: TAtlasTrackerWriteResult): Boolean;
begin
  Exit(False);
end;

function TFakeEndWriter.FieldValues(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  const AKey, AField: string; ATimeoutMs: Integer; out AValues: TArray<string>): TAtlasTrackerWriteResult;
begin
  AValues := nil;
  Exit(TAtlasTrackerWriteResult.Ok);
end;

function TFakeEndWriter.SetField(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  const AKey, AField, AValue: string; ATimeoutMs: Integer): TAtlasTrackerWriteResult;
begin
  Exit(Logged('field ' + AField + '=' + AValue));
end;

/// <summary>Zeit 85 min, zwei Felder, Kommentar mit Übergabe und Übergang „Zur Prüfung geben“.</summary>
function FullPlan: TAtlasTrackerEndPlan;
var
  mChange: TAtlasTrackerWrite;
begin
  mChange := TAtlasTrackerWrite.Empty;
  mChange.StateField := 'Status';
  mChange.Comment := 'Fertig';
  mChange.AssigneeField := 'Assignee';
  mChange.Assign := TAtlasTrackerAssign.User;
  mChange.Assignee := 'anna';
  mChange.Transition := TAtlasTrackerTransition.Create('review', 'Zur Prüfung geben');
  mChange.FieldId := '82-11';
  Result := TAtlasTrackerEndPlan.Create(mChange);
  Result.Time := TAtlasTrackerWorkItem.Create(85, EncodeDate(2026, 11, 12), 'Entwicklung', 'abc');
  Result.AddField('Behoben in Version', '2.1.0');
  Result.AddField('Ursache', 'Fehlende Prüfung');
  Result.AddField('Notiz', '  ');
end;

function CallOf(const AWriter: TFakeEndWriter): TAtlasTrackerEndCall;
begin
  Result := Default(TAtlasTrackerEndCall);
  Result.Writer := AWriter;
  Result.Time := AWriter;
  Result.Fields := AWriter;
  Result.Target := TAtlasTrackerTarget.Create('youtrack', 'https://yt.beispiel.de', 'ATL', '');
  Result.Key := 'ATL-2052';
  Result.TimeoutMs := 5000;
end;

/// <summary>Pull Request mit festem Ergebnis AAnswer; schreibt „pull &lt;Kopf&gt;“ bei AWriter mit.</summary>
function PullRunner(const AWriter: TFakeEndWriter; const AAnswer: TAtlasTrackerPullResult): TAtlasTrackerPullRun;
var
  mWriter: TFakeEndWriter;
  mAnswer: TAtlasTrackerPullResult;
begin
  mWriter := AWriter;
  mAnswer := AAnswer;
  Result :=
    function(const ASpec: TAtlasTrackerPullSpec): TAtlasTrackerPullResult
    begin
      mWriter.Calls := mWriter.Calls + ['pull ' + ASpec.Head];
      Result := mAnswer;
    end;
end;

/// <summary>FullPlan mit Pull Request für Branch 7-statusfeld.</summary>
function PullPlan: TAtlasTrackerEndPlan;
begin
  Result := FullPlan;
  Result.Fields := Copy(Result.Fields, 0, 1);
  Result.Pull := TAtlasTrackerPullSpec.None;
  Result.Pull.Wanted := True;
  Result.Pull.Head := '7-statusfeld';
  Result.Pull.Title := 'Statusfeld';
end;

{ TAtlasTrackerEndStepsTests }

procedure TAtlasTrackerEndStepsTests.PlanSplitsCommentAndTransition;
var
  mPlan: TAtlasTrackerEndPlan;
begin
  mPlan := FullPlan;
  Assert.AreEqual(2, Integer(Length(mPlan.Fields)), 'leere Felder werden nicht geschrieben');
  Assert.AreEqual('', mPlan.CommentPart.Transition.Id, 'Kommentar ohne Übergang');
  Assert.AreEqual('anna', mPlan.CommentPart.Assignee, 'Übergabe mit dem Kommentar');
  Assert.AreEqual('review', mPlan.TransitionPart.Transition.Id);
  Assert.AreEqual('82-11', mPlan.TransitionPart.FieldId);
  Assert.AreEqual('', mPlan.TransitionPart.Comment, 'Übergang ohne Kommentar');
  Assert.IsTrue(mPlan.TransitionPart.Assign = TAtlasTrackerAssign.Keep);
  Assert.IsTrue(mPlan.HasWork);
  Assert.IsFalse(TAtlasTrackerEndPlan.Create(TAtlasTrackerWrite.Empty).HasWork);
end;

procedure TAtlasTrackerEndStepsTests.RunsInWorkflowOrder;
var
  mWriter: TFakeEndWriter;
  mKeep: IAtlasTrackerWriter;
  mProgress: TAtlasTrackerEndProgress;
  mPlan: TAtlasTrackerEndPlan;
begin
  mWriter := TFakeEndWriter.Create;
  mKeep := mWriter;
  mPlan := FullPlan;
  mProgress := TAtlasTrackerEndProgress.Empty;
  TAtlasTrackerEndSteps.Run(CallOf(mWriter), mPlan, mProgress);
  Assert.AreEqual('time 85|field Behoben in Version=2.1.0|field Ursache=Fehlende Prüfung|comment Fertig|' +
    'transition review', string.Join('|', mWriter.Calls));
  Assert.IsFalse(mProgress.Failed);
  Assert.IsTrue(mProgress.Finished(mPlan));
  Assert.IsTrue(mProgress.Outcome.Succeeded);
end;

procedure TAtlasTrackerEndStepsTests.StopsAtFirstFailureAndResumes;
var
  mWriter: TFakeEndWriter;
  mKeep: IAtlasTrackerWriter;
  mProgress: TAtlasTrackerEndProgress;
  mPlan: TAtlasTrackerEndPlan;
begin
  mWriter := TFakeEndWriter.Create;
  mKeep := mWriter;
  mWriter.FailOn := 'transition review';
  mWriter.FailMessage := 'Bitte ‚Behoben in Version‘ setzen.';
  mPlan := FullPlan;
  mPlan.Fields := Copy(mPlan.Fields, 0, 1);
  mProgress := TAtlasTrackerEndProgress.Empty;
  TAtlasTrackerEndSteps.Run(CallOf(mWriter), mPlan, mProgress);
  Assert.IsTrue(mProgress.Failed);
  Assert.IsTrue(mProgress.FailedStep = TAtlasTrackerEndStep.Transition);
  Assert.AreEqual(400, mProgress.Outcome.Status);
  Assert.IsTrue(mProgress.TimeBooked and mProgress.CommentDone);
  Assert.IsTrue(mProgress.Wrote);
  Assert.IsFalse(mProgress.Finished(mPlan));
  // Feld ergänzt, erneut senden: Zeit, erstes Feld und Kommentar nicht noch einmal.
  mWriter.FailOn := '';
  mWriter.Calls := nil;
  mPlan.AddField('Ursache', 'Fehlende Prüfung');
  TAtlasTrackerEndSteps.Run(CallOf(mWriter), mPlan, mProgress);
  Assert.AreEqual('field Ursache=Fehlende Prüfung|transition review', string.Join('|', mWriter.Calls));
  Assert.IsTrue(mProgress.Finished(mPlan));
  // Ein Feld scheitert: Name des Feldes, nichts danach.
  mWriter.Calls := nil;
  mWriter.FailOn := 'field Ursache=Fehlende Prüfung';
  mPlan := FullPlan;
  mProgress := TAtlasTrackerEndProgress.Empty;
  TAtlasTrackerEndSteps.Run(CallOf(mWriter), mPlan, mProgress);
  Assert.AreEqual('Ursache', mProgress.FailedField);
  Assert.IsTrue(mProgress.FailedStep = TAtlasTrackerEndStep.Fields);
  Assert.AreEqual(3, Integer(Length(mWriter.Calls)), 'kein Kommentar, kein Übergang');
end;

procedure TAtlasTrackerEndStepsTests.ChangedFieldValueIsWrittenAgain;
var
  mWriter: TFakeEndWriter;
  mKeep: IAtlasTrackerWriter;
  mProgress: TAtlasTrackerEndProgress;
  mPlan: TAtlasTrackerEndPlan;
begin
  mWriter := TFakeEndWriter.Create;
  mKeep := mWriter;
  mWriter.FailOn := 'comment Fertig';
  mPlan := FullPlan;
  mProgress := TAtlasTrackerEndProgress.Empty;
  TAtlasTrackerEndSteps.Run(CallOf(mWriter), mPlan, mProgress);
  Assert.IsTrue(mProgress.FailedStep = TAtlasTrackerEndStep.Comment);
  mWriter.FailOn := '';
  mWriter.Calls := nil;
  mPlan.Fields[0].Value := '2.2.0';
  TAtlasTrackerEndSteps.Run(CallOf(mWriter), mPlan, mProgress);
  Assert.AreEqual('field Behoben in Version=2.2.0|comment Fertig|transition review',
    string.Join('|', mWriter.Calls));
end;

procedure TAtlasTrackerEndStepsTests.WithoutTimeWriterFailsTimeStep;
var
  mWriter: TFakeEndWriter;
  mKeep: IAtlasTrackerWriter;
  mCall: TAtlasTrackerEndCall;
  mProgress: TAtlasTrackerEndProgress;
begin
  mWriter := TFakeEndWriter.Create;
  mKeep := mWriter;
  mCall := CallOf(mWriter);
  mCall.Time := nil;
  mProgress := TAtlasTrackerEndProgress.Empty;
  TAtlasTrackerEndSteps.Run(mCall, FullPlan, mProgress);
  Assert.IsTrue(mProgress.FailedStep = TAtlasTrackerEndStep.Time);
  Assert.IsTrue(mProgress.Outcome.Error = TAtlasCiFetchError.UnknownProvider);
  Assert.AreEqual(0, Integer(Length(mWriter.Calls)), 'nichts geschrieben');
  mCall.Writer := nil;
  TAtlasTrackerEndSteps.Run(mCall, FullPlan, mProgress);
  Assert.IsTrue(mProgress.Failed);
end;

procedure TAtlasTrackerEndStepsTests.StatesAndFinished;
var
  mPlan: TAtlasTrackerEndPlan;
  mProgress: TAtlasTrackerEndProgress;
begin
  mPlan := TAtlasTrackerEndPlan.Create(TAtlasTrackerWrite.CommentOnly('x'));
  mProgress := TAtlasTrackerEndProgress.Empty;
  Assert.IsTrue(mProgress.StateOf(mPlan, TAtlasTrackerEndStep.Time) = TAtlasTrackerStepState.Skipped);
  Assert.IsTrue(mProgress.StateOf(mPlan, TAtlasTrackerEndStep.Comment) = TAtlasTrackerStepState.Pending);
  Assert.IsTrue(mProgress.StateOf(mPlan, TAtlasTrackerEndStep.Transition) = TAtlasTrackerStepState.Skipped);
  mProgress.Fail(mPlan, TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.NotConfigured, 0, ''));
  Assert.IsTrue(mProgress.StateOf(mPlan, TAtlasTrackerEndStep.Comment) = TAtlasTrackerStepState.Failed,
    'erster offener Schritt');
  mProgress.CommentDone := True;
  Assert.IsTrue(mProgress.StateOf(mPlan, TAtlasTrackerEndStep.Comment) = TAtlasTrackerStepState.Done);
  Assert.IsTrue(mProgress.Finished(mPlan));
  Assert.IsTrue(TAtlasTrackerEndProgress.Empty.Finished(TAtlasTrackerEndPlan.Create(TAtlasTrackerWrite.Empty)),
    'nichts zu schreiben');
end;

procedure TAtlasTrackerEndStepsTests.MentionedFieldFindsWholeNames;
var
  mNames: TArray<string>;
begin
  mNames := TArray<string>.Create('Version', 'Behoben in Version', 'Ursache');
  Assert.AreEqual('Behoben in Version', TAtlasTrackerEndSteps.MentionedField(
    'Bitte ‚Behoben in Version‘ setzen, bevor das Issue zur Prüfung geht.', mNames), 'der längste Name');
  Assert.AreEqual('Ursache', TAtlasTrackerEndSteps.MentionedField('Field "ursache" is required', mNames),
    'ohne Groß- und Kleinschreibung');
  Assert.AreEqual('', TAtlasTrackerEndSteps.MentionedField('Ursachenanalyse fehlt', mNames), 'nur ganze Wörter');
  Assert.AreEqual('', TAtlasTrackerEndSteps.MentionedField('', mNames));
end;

procedure TAtlasTrackerEndStepsTests.EndFieldsPerConnection;
var
  mItems: TArray<TAtlasTrackerConnection>;
  mOptions: TAtlasTrackerSyncOptions;
begin
  mItems := TAtlasTrackerConnections.Read('[{"name": "Firma", "provider": "youtrack", "url": "https://yt.beispiel.de",' +
    ' "endFields": ["Behoben in Version", "Ursache"]}]');
  Assert.AreEqual(1, Integer(Length(mItems)));
  Assert.AreEqual('Behoben in Version|Ursache', string.Join('|', mItems[0].EndFields));
  Assert.Contains(TAtlasTrackerConnections.ToJson(mItems), '"endFields": ["Behoben in Version", "Ursache"]');
  mOptions := TAtlasTrackerSyncOptions.Create(True, '', '').WithEndSteps('Notiz; Ursache', False);
  Assert.AreEqual('Notiz|Ursache', string.Join('|', mOptions.EndFields));
  Assert.IsFalse(mOptions.EndTime);
  mOptions := TAtlasTrackerWorkflow.ForConnection(mOptions, mItems,
    TAtlasTrackerTarget.Create('youtrack', 'https://yt.beispiel.de', 'ATL', ''));
  Assert.AreEqual('Behoben in Version|Ursache', string.Join('|', mOptions.EndFields), 'Verbindung vor global');
end;

/// <summary>Beenden von #2109 als Duplikat von ADuplicateOf mit Kommentar.</summary>
function DuplicatePlan(const ADuplicateOf: string): TAtlasTrackerEndPlan;
var
  mChange: TAtlasTrackerWrite;
begin
  mChange := TAtlasTrackerWrite.CommentOnly('Steckt schon in #418.');
  mChange := TAtlasTrackerWorkflow.WithClose(mChange, TAtlasTrackerClose.Duplicate, ADuplicateOf, 'Duplikat von #418.');
  Result := TAtlasTrackerEndPlan.Create(mChange);
end;

procedure TAtlasTrackerEndStepsTests.DuplicateCheckedBeforeWriting;
var
  mWriter: TFakeEndWriter;
  mKeep: IAtlasTrackerWriter;
  mTransport: TFakeLookupTransport;
  mTransportKeep: IAtlasCiTransport;
  mProvider: IAtlasTrackerProvider;
  mCall: TAtlasTrackerEndCall;
  mProgress: TAtlasTrackerEndProgress;
begin
  mWriter := TFakeEndWriter.Create;
  mKeep := mWriter;
  mTransport := TFakeLookupTransport.Create;
  mTransportKeep := mTransport;
  mProvider := TAtlasGitHubTracker.Create;
  mCall := CallOf(mWriter);
  mCall.Provider := mProvider;
  mCall.Target := TAtlasTrackerTarget.Create('github', '', 'beispiel/atlas', '');
  mCall.Transport := mTransportKeep;
  mCall.Key := '#2109';
  // Duplikat von sich selbst: nichts gefragt, nichts geschrieben.
  mProgress := TAtlasTrackerEndProgress.Empty;
  TAtlasTrackerEndSteps.Run(mCall, DuplicatePlan('#2109'), mProgress);
  Assert.IsTrue(mProgress.Failed and mProgress.DuplicateMissing);
  Assert.AreEqual(0, mTransport.Calls);
  Assert.AreEqual(0, Integer(Length(mWriter.Calls)));
  // Unbekanntes Issue: eine Abfrage, nichts geschrieben.
  mProgress := TAtlasTrackerEndProgress.Empty;
  TAtlasTrackerEndSteps.Run(mCall, DuplicatePlan('#999'), mProgress);
  Assert.IsTrue(mProgress.DuplicateMissing);
  Assert.IsTrue(mProgress.Outcome.Error = TAtlasCiFetchError.NotFound);
  Assert.IsTrue(mProgress.FailedStep = TAtlasTrackerEndStep.Comment, 'erster offener Schritt');
  Assert.AreEqual(1, mTransport.Calls);
  Assert.AreEqual(0, Integer(Length(mWriter.Calls)));
  // Vorhanden: Kommentar, dann Schließen als Duplikat (der Kommentar nennt #418, kein Ersatzkommentar).
  mProgress := TAtlasTrackerEndProgress.Empty;
  TAtlasTrackerEndSteps.Run(mCall, DuplicatePlan('#418'), mProgress);
  Assert.IsFalse(mProgress.Failed);
  Assert.IsFalse(mProgress.DuplicateMissing);
  Assert.AreEqual('comment Steckt schon in #418.|close 3 #418', string.Join('|', mWriter.Calls));
  Assert.IsFalse(mProgress.Fallback);
  // Nach dem Schließen nicht noch einmal prüfen.
  mTransport.Calls := 0;
  TAtlasTrackerEndSteps.Run(mCall, DuplicatePlan('#418'), mProgress);
  Assert.AreEqual(0, mTransport.Calls);
end;

procedure TAtlasTrackerEndStepsTests.CloseGoesWithTransitionPart;
var
  mPlan: TAtlasTrackerEndPlan;
  mWriter: TFakeEndWriter;
  mKeep: IAtlasTrackerWriter;
  mProgress: TAtlasTrackerEndProgress;
  mChange: TAtlasTrackerWrite;
begin
  mChange := TAtlasTrackerWorkflow.WithClose(TAtlasTrackerWrite.CommentOnly('Wird nicht umgesetzt.'),
    TAtlasTrackerClose.NotPlanned, '#5', 'x');
  Assert.AreEqual('', mChange.DuplicateOf, 'Original nur beim Duplikat');
  mPlan := TAtlasTrackerEndPlan.Create(mChange);
  Assert.IsTrue(mPlan.CommentPart.Close = TAtlasTrackerClose.ByState, 'Kommentar schließt nicht');
  Assert.IsTrue(mPlan.TransitionPart.Close = TAtlasTrackerClose.NotPlanned);
  Assert.IsTrue(mPlan.Has(TAtlasTrackerEndStep.Transition), 'Schließen ist ein Schritt');
  mPlan := DuplicatePlan('#418');
  Assert.AreEqual('#418', mPlan.TransitionPart.DuplicateOf);
  Assert.AreEqual('', mPlan.TransitionPart.DuplicateNote, 'Kommentar nennt #418 schon');
  Assert.AreEqual('', mPlan.CommentPart.DuplicateOf);
  // Ersatzweg des Anbieters kommt im Fortschritt an.
  mWriter := TFakeEndWriter.Create;
  mKeep := mWriter;
  mWriter.CloseFallback := True;
  mProgress := TAtlasTrackerEndProgress.Empty;
  TAtlasTrackerEndSteps.Run(CallOf(mWriter), TAtlasTrackerEndPlan.Create(mChange), mProgress);
  Assert.IsTrue(mProgress.Finished(TAtlasTrackerEndPlan.Create(mChange)));
  Assert.IsTrue(mProgress.Fallback);
end;

procedure TAtlasTrackerEndStepsTests.PullRunsAfterFieldsAndOnlyOnce;
var
  mWriter: TFakeEndWriter;
  mKeep: IAtlasTrackerWriter;
  mProgress: TAtlasTrackerEndProgress;
  mCall: TAtlasTrackerEndCall;
  mPlan: TAtlasTrackerEndPlan;
begin
  mWriter := TFakeEndWriter.Create;
  mKeep := mWriter;
  mWriter.FailOn := 'transition review';
  mCall := CallOf(mWriter);
  mCall.Pull := PullRunner(mWriter, TAtlasTrackerPullResult.Make(TAtlasTrackerPullOutcome.Created));
  mPlan := PullPlan;
  mProgress := TAtlasTrackerEndProgress.Empty;
  TAtlasTrackerEndSteps.Run(mCall, mPlan, mProgress);
  Assert.AreEqual('time 85|field Behoben in Version=2.1.0|pull 7-statusfeld|comment Fertig|transition review',
    string.Join('|', mWriter.Calls));
  Assert.IsTrue(mProgress.Wrote);
  // Fortsetzen nach dem abgelehnten Übergang: kein zweiter Pull Request.
  mWriter.FailOn := '';
  mWriter.Calls := nil;
  TAtlasTrackerEndSteps.Run(mCall, mPlan, mProgress);
  Assert.AreEqual('transition review', string.Join('|', mWriter.Calls));
  Assert.IsTrue(mProgress.Finished(mPlan));
  Assert.IsTrue(mProgress.Pull.Outcome = TAtlasTrackerPullOutcome.Created);
end;

procedure TAtlasTrackerEndStepsTests.FailedPullStopsBeforeComment;
var
  mWriter: TFakeEndWriter;
  mKeep: IAtlasTrackerWriter;
  mProgress: TAtlasTrackerEndProgress;
  mCall: TAtlasTrackerEndCall;
begin
  mWriter := TFakeEndWriter.Create;
  mKeep := mWriter;
  mCall := CallOf(mWriter);
  mCall.Pull := PullRunner(mWriter, TAtlasTrackerPullResult.Make(TAtlasTrackerPullOutcome.Dirty));
  mProgress := TAtlasTrackerEndProgress.Empty;
  TAtlasTrackerEndSteps.Run(mCall, PullPlan, mProgress);
  Assert.IsTrue(mProgress.Failed);
  Assert.IsTrue(mProgress.FailedStep = TAtlasTrackerEndStep.PullRequest);
  Assert.AreEqual('time 85|field Behoben in Version=2.1.0|pull 7-statusfeld', string.Join('|', mWriter.Calls),
    'kein Kommentar, kein Übergang');
  // Ohne Runner scheitert der Schritt, statt still nichts anzulegen.
  mWriter.Calls := nil;
  mCall.Pull := nil;
  mProgress := TAtlasTrackerEndProgress.Empty;
  TAtlasTrackerEndSteps.Run(mCall, PullPlan, mProgress);
  Assert.IsTrue(mProgress.FailedStep = TAtlasTrackerEndStep.PullRequest);
  Assert.IsTrue(mProgress.Pull.Error = TAtlasCiFetchError.UnknownProvider);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTrackerEndStepsTests);

end.
