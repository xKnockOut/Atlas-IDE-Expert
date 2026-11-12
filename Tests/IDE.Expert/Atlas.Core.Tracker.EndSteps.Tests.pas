unit Atlas.Core.Tracker.EndSteps.Tests;

// Tests von „Beenden“ in der Reihenfolge des Ablaufs (#2123) ohne Server:
// Zeit → Felder → Kommentar → Übergang gegen einen Anbieter, der jeden Aufruf
// mitschreibt; Anhalten beim ersten Fehler und Wiederaufnahme ohne doppelte
// Zeitbuchung oder zweiten Kommentar; Stand je Schritt; Feldsuche im Text
// einer Ablehnung; Felder beim Beenden je Verbindung (endFields).

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
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Ci.Contract,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Connections,
  Atlas.Core.Tracker.EndSteps,
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
  Exit(Logged('comment ' + AChange.Comment));
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

initialization
  TDUnitX.RegisterTestFixture(TAtlasTrackerEndStepsTests);

end.
