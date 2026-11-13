unit Atlas.Core.Tracker.EndSteps;

// „Beenden“ in der Reihenfolge des Ablaufs (#2123), ohne VCL und Open Tools
// API. Regeln eines Trackers (YouTrack-Workflows) lassen ein Issue oft erst
// weiter, wenn Aufwand gebucht und Felder gesetzt sind; sie lehnen den
// Zustandswechsel sonst mit eigenem Text ab.
// - TAtlasTrackerEndPlan: was der Dialog schreiben will: Zeit (Work Item),
//   Felder (issues.endFields, nur mit Wert), Kommentar samt Zuständigkeit und
//   zuletzt Zustand bzw. Übergang (#2122).
// - Run schreibt der Reihe nach Zeit → Felder → Pull Request (#2136) →
//   Kommentar → Übergang und hält beim ersten Fehler an. TAtlasTrackerEndProgress merkt sich, was schon
//   geschrieben ist; ein zweiter Lauf mit demselben Fortschritt überspringt
//   es (keine doppelte Zeitbuchung, kein zweiter Kommentar). Ein Feld zählt
//   mit Namen und Wert: Wer den Wert ändert, schreibt es neu.
// - Schließgrund „Duplikat“ (#2135): Vor dem ersten Schritt prüft Run, dass
//   das Original nicht das Issue selbst ist und es gibt (Lookup des
//   Anbieters); sonst wird nichts geschrieben (DuplicateMissing).
// - Pull Request (#2136, GitHub): Plan.Pull; den Schritt (Push und Anlegen)
//   führt TAtlasTrackerEndCall.Pull aus, das Ergebnis steht in Progress.Pull.
//   Ein angelegter bzw. vorhandener Pull Request gilt als geschrieben.
// - MentionedField sucht im Text einer Ablehnung den Namen eines Feldes
//   (ganzes Wort, ohne Groß-/Kleinschreibung; der längste gewinnt), damit der
//   Dialog die Zeile markieren bzw. „Feld hinzufügen“ anbieten kann. Ob eine
//   Regel das Feld nennt, hängt vom Ablauf ab: eine Hilfe, keine Garantie.
// Alles im Hintergrund; je Schritt höchstens ATimeoutMs, nichts wird
// wiederholt.

interface

uses
  Atlas.Core.Ci.Contract,
  Atlas.Core.Tracker.Contract;

type
{$SCOPEDENUMS ON}
  /// <summary>Schritte beim Beenden in der Reihenfolge, in der sie geschrieben werden.</summary>
  TAtlasTrackerEndStep = (Time, Fields, PullRequest, Comment, Transition);
  /// <summary>Stand eines Schritts: nicht geplant, offen, geschrieben, gescheitert.</summary>
  TAtlasTrackerStepState = (Skipped, Pending, Done, Failed);
{$SCOPEDENUMS OFF}

  /// <summary>Ein Feld mit dem Wert, den es bekommen soll.</summary>
  TAtlasTrackerFieldValue = record
    Name: string;
    Value: string;
    class function Create(const AName, AValue: string): TAtlasTrackerFieldValue; static;
  end;

  /// <summary>Was „Senden“ im Beenden-Dialog schreibt.</summary>
  TAtlasTrackerEndPlan = record
    /// <summary>Zeitbuchung; Minutes 0 = keine.</summary>
    Time: TAtlasTrackerWorkItem;
    /// <summary>Felder mit Wert; leere werden nicht geschrieben.</summary>
    Fields: TArray<TAtlasTrackerFieldValue>;
    /// <summary>Kommentar, Zuständigkeit und Zustand bzw. Übergang.</summary>
    Change: TAtlasTrackerWrite;
    /// <summary>Pull Request (#2136); Wanted False = keiner.</summary>
    Pull: TAtlasTrackerPullSpec;
    /// <summary>Nur AChange, ohne Zeit und Felder.</summary>
    class function Create(const AChange: TAtlasTrackerWrite): TAtlasTrackerEndPlan; static;
    /// <summary>Feld AName mit AValue anhängen; leere Werte entfallen.</summary>
    procedure AddField(const AName, AValue: string);
    /// <summary>Kommentar und Zuständigkeit ohne Zustand und Übergang.</summary>
    function CommentPart: TAtlasTrackerWrite;
    /// <summary>Nur Zustand bzw. Übergang (zuletzt).</summary>
    function TransitionPart: TAtlasTrackerWrite;
    /// <summary>Der Schritt hat etwas zu schreiben.</summary>
    function Has(AStep: TAtlasTrackerEndStep): Boolean;
    /// <summary>Irgendein Schritt hat etwas zu schreiben.</summary>
    function HasWork: Boolean;
  end;

  /// <summary>Was schon geschrieben ist und woran es scheiterte; bleibt zwischen zwei „Senden“ erhalten.</summary>
  TAtlasTrackerEndProgress = record
    TimeBooked: Boolean;
    /// <summary>Geschriebene Felder als Vergleichsform „name=wert“.</summary>
    FieldsDone: TArray<string>;
    CommentDone: Boolean;
    TransitionDone: Boolean;
    /// <summary>Der letzte Lauf hielt bei FailedStep an.</summary>
    Failed: Boolean;
    FailedStep: TAtlasTrackerEndStep;
    /// <summary>Name des Feldes, an dem der Lauf anhielt; '' sonst.</summary>
    FailedField: string;
    /// <summary>Ergebnis des letzten Laufs (Ok oder der Fehler mit dem Text des Trackers).</summary>
    Outcome: TAtlasTrackerWriteResult;
    /// <summary>Der letzte Lauf hielt vor dem Schreiben an: Das Original eines Duplikats ist ungültig, das Issue
    /// selbst oder unbekannt (#2135).</summary>
    DuplicateMissing: Boolean;
    /// <summary>Zustand bzw. Schließen ging über einen Ersatzweg (#2135, „Duplikat“ als „nicht geplant“).</summary>
    Fallback: Boolean;
    /// <summary>Zustand im Projekt (#2134, GitHub) aus dem Schreiben des Zustands; Project '' ohne.</summary>
    Project: TAtlasTrackerProjectStatus;
    /// <summary>Pull Request (#2136) aus dem letzten Versuch; Outcome None ohne.</summary>
    Pull: TAtlasTrackerPullResult;
    class function Empty: TAtlasTrackerEndProgress; static;
    function FieldDone(const AField: TAtlasTrackerFieldValue): Boolean;
    /// <summary>Stand von AStep für APlan.</summary>
    function StateOf(const APlan: TAtlasTrackerEndPlan; AStep: TAtlasTrackerEndStep): TAtlasTrackerStepState;
    /// <summary>Alle Schritte von APlan sind geschrieben.</summary>
    function Finished(const APlan: TAtlasTrackerEndPlan): Boolean;
    /// <summary>Mindestens ein Schritt ist geschrieben.</summary>
    function Wrote: Boolean;
    /// <summary>Lauf scheiterte mit AResult vor dem ersten offenen Schritt von APlan (kein Transport, Ausnahme).
    /// </summary>
    procedure Fail(const APlan: TAtlasTrackerEndPlan; const AResult: TAtlasTrackerWriteResult);
  end;

  /// <summary>Pull Request ASpec pushen und anlegen (#2136); im Hintergrund.</summary>
  TAtlasTrackerPullRun = reference to function(const ASpec: TAtlasTrackerPullSpec): TAtlasTrackerPullResult;

  /// <summary>Wohin geschrieben wird: Schreibzugriffe des Anbieters (Zeit und Felder dürfen nil sein, dann
  /// scheitert der Schritt mit UnknownProvider), Ziel, Transport, Kennung, Zeitgrenze je Schritt.</summary>
  TAtlasTrackerEndCall = record
    /// <summary>Für die Prüfung des Originals eines Duplikats (#2135, Lookup); nil = ohne Prüfung.</summary>
    Provider: IAtlasTrackerProvider;
    Writer: IAtlasTrackerWriter;
    Time: IAtlasTrackerTimeWriter;
    Fields: IAtlasTrackerFields;
    /// <summary>Pull Request anlegen (#2136); nil = der Schritt scheitert mit UnknownProvider.</summary>
    Pull: TAtlasTrackerPullRun;
    Target: TAtlasTrackerTarget;
    Transport: IAtlasCiTransport;
    Key: string;
    TimeoutMs: Integer;
  end;

  TAtlasTrackerEndSteps = class
  public
    /// <summary>Offene Schritte von APlan der Reihe nach schreiben, beim ersten Fehler anhalten. Im Hintergrund.
    /// </summary>
    class procedure Run(const ACall: TAtlasTrackerEndCall; const APlan: TAtlasTrackerEndPlan;
      var AProgress: TAtlasTrackerEndProgress); static;
    /// <summary>Längster Name aus ANames, der in AText als ganzes Wort steht; '' ohne.</summary>
    class function MentionedField(const AText: string; const ANames: TArray<string>): string; static;
    /// <summary>Vergleichsform eines Feldes mit Wert.</summary>
    class function FieldKey(const AField: TAtlasTrackerFieldValue): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.Character,
  Atlas.Core.CiBuild.Contract;

{ TAtlasTrackerFieldValue }

class function TAtlasTrackerFieldValue.Create(const AName, AValue: string): TAtlasTrackerFieldValue;
begin
  Result.Name := Trim(AName);
  Result.Value := Trim(AValue);
end;

{ TAtlasTrackerEndPlan }

class function TAtlasTrackerEndPlan.Create(const AChange: TAtlasTrackerWrite): TAtlasTrackerEndPlan;
begin
  Result.Time := TAtlasTrackerWorkItem.Create(0, 0, '', '');
  Result.Fields := nil;
  Result.Change := AChange;
  Result.Pull := TAtlasTrackerPullSpec.None;
end;

procedure TAtlasTrackerEndPlan.AddField(const AName, AValue: string);
begin
  if (Trim(AName) <> '') and (Trim(AValue) <> '') then
  begin
    Fields := Fields + [TAtlasTrackerFieldValue.Create(AName, AValue)];
  end;
end;

function TAtlasTrackerEndPlan.CommentPart: TAtlasTrackerWrite;
begin
  Result := Change;
  Result.State := '';
  Result.PreviousState := '';
  Result.Transition := TAtlasTrackerTransition.Create('', '');
  Result.FieldId := '';
  Result.Close := TAtlasTrackerClose.ByState;
  Result.DuplicateOf := '';
  Result.DuplicateNote := '';
end;

function TAtlasTrackerEndPlan.TransitionPart: TAtlasTrackerWrite;
begin
  Result := TAtlasTrackerWrite.Empty;
  Result.StateField := Change.StateField;
  Result.State := Change.State;
  Result.PreviousState := Change.PreviousState;
  Result.AssigneeField := Change.AssigneeField;
  Result.Transition := Change.Transition;
  Result.FieldId := Change.FieldId;
  Result.Close := Change.Close;
  Result.DuplicateOf := Change.DuplicateOf;
  Result.DuplicateNote := Change.DuplicateNote;
  Result.GitHub := Change.GitHub;
end;

function TAtlasTrackerEndPlan.Has(AStep: TAtlasTrackerEndStep): Boolean;
begin
  case AStep of
    TAtlasTrackerEndStep.Time:
      Result := Time.Minutes > 0;
    TAtlasTrackerEndStep.Fields:
      Result := Length(Fields) > 0;
    TAtlasTrackerEndStep.PullRequest:
      Result := Pull.Wanted;
    TAtlasTrackerEndStep.Comment:
      Result := CommentPart.HasWork;
  else
    Result := TransitionPart.HasWork;
  end;
end;

function TAtlasTrackerEndPlan.HasWork: Boolean;
var
  mStep: TAtlasTrackerEndStep;
begin
  for mStep := Low(TAtlasTrackerEndStep) to High(TAtlasTrackerEndStep) do
  begin
    if Has(mStep) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

{ TAtlasTrackerEndProgress }

class function TAtlasTrackerEndProgress.Empty: TAtlasTrackerEndProgress;
begin
  Result := Default(TAtlasTrackerEndProgress);
  Result.FailedStep := TAtlasTrackerEndStep.Time;
  Result.Outcome := TAtlasTrackerWriteResult.Ok;
  Result.Pull := TAtlasTrackerPullResult.Make(TAtlasTrackerPullOutcome.None);
end;

function TAtlasTrackerEndProgress.FieldDone(const AField: TAtlasTrackerFieldValue): Boolean;
var
  mKey, mDone: string;
begin
  mKey := TAtlasTrackerEndSteps.FieldKey(AField);
  for mDone in FieldsDone do
  begin
    if mDone = mKey then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TAtlasTrackerEndProgress.StateOf(const APlan: TAtlasTrackerEndPlan;
  AStep: TAtlasTrackerEndStep): TAtlasTrackerStepState;
var
  mDone: Boolean;
  mField: TAtlasTrackerFieldValue;
begin
  if not APlan.Has(AStep) then
  begin
    Exit(TAtlasTrackerStepState.Skipped);
  end;
  case AStep of
    TAtlasTrackerEndStep.Time:
      mDone := TimeBooked;
    TAtlasTrackerEndStep.Fields:
      begin
        mDone := True;
        for mField in APlan.Fields do
        begin
          mDone := mDone and FieldDone(mField);
        end;
      end;
    TAtlasTrackerEndStep.PullRequest:
      mDone := Pull.Stands;
    TAtlasTrackerEndStep.Comment:
      mDone := CommentDone;
  else
    mDone := TransitionDone;
  end;
  if mDone then
  begin
    Result := TAtlasTrackerStepState.Done;
  end
  else if Failed and (FailedStep = AStep) then
  begin
    Result := TAtlasTrackerStepState.Failed;
  end
  else
  begin
    Result := TAtlasTrackerStepState.Pending;
  end;
end;

function TAtlasTrackerEndProgress.Finished(const APlan: TAtlasTrackerEndPlan): Boolean;
var
  mStep: TAtlasTrackerEndStep;
begin
  for mStep := Low(TAtlasTrackerEndStep) to High(TAtlasTrackerEndStep) do
  begin
    if StateOf(APlan, mStep) in [TAtlasTrackerStepState.Pending, TAtlasTrackerStepState.Failed] then
    begin
      Exit(False);
    end;
  end;
  Result := True;
end;

function TAtlasTrackerEndProgress.Wrote: Boolean;
begin
  Result := TimeBooked or (Length(FieldsDone) > 0) or Pull.Stands or CommentDone or TransitionDone;
end;

procedure TAtlasTrackerEndProgress.Fail(const APlan: TAtlasTrackerEndPlan; const AResult: TAtlasTrackerWriteResult);
var
  mStep: TAtlasTrackerEndStep;
begin
  Failed := False;
  for mStep := Low(TAtlasTrackerEndStep) to High(TAtlasTrackerEndStep) do
  begin
    if StateOf(APlan, mStep) = TAtlasTrackerStepState.Pending then
    begin
      FailedStep := mStep;
      Break;
    end;
  end;
  Failed := True;
  FailedField := '';
  Outcome := AResult;
  DuplicateMissing := False;
end;

{ TAtlasTrackerEndSteps }

class function TAtlasTrackerEndSteps.FieldKey(const AField: TAtlasTrackerFieldValue): string;
begin
  Result := LowerCase(Trim(AField.Name)) + '=' + Trim(AField.Value);
end;

/// <summary>Lauf hält bei AStep an: Ergebnis merken.</summary>
procedure Stopped(var AProgress: TAtlasTrackerEndProgress; AStep: TAtlasTrackerEndStep;
  const AResult: TAtlasTrackerWriteResult);
begin
  AProgress.Failed := True;
  AProgress.FailedStep := AStep;
  AProgress.Outcome := AResult;
end;

/// <summary>Offene Felder der Reihe nach; False, sobald eines scheitert.</summary>
function RunFields(const ACall: TAtlasTrackerEndCall; const APlan: TAtlasTrackerEndPlan;
  var AProgress: TAtlasTrackerEndProgress): Boolean;
var
  mField: TAtlasTrackerFieldValue;
  mResult: TAtlasTrackerWriteResult;
begin
  for mField in APlan.Fields do
  begin
    if AProgress.FieldDone(mField) then
    begin
      Continue;
    end;
    if ACall.Fields = nil then
    begin
      mResult := TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.UnknownProvider, 0, '');
    end
    else
    begin
      mResult := ACall.Fields.SetField(ACall.Target, ACall.Transport, ACall.Key, mField.Name, mField.Value,
        ACall.TimeoutMs);
    end;
    if not mResult.Succeeded then
    begin
      AProgress.FailedField := mField.Name;
      Stopped(AProgress, TAtlasTrackerEndStep.Fields, mResult);
      Exit(False);
    end;
    AProgress.FieldsDone := AProgress.FieldsDone + [TAtlasTrackerEndSteps.FieldKey(mField)];
  end;
  Result := True;
end;

/// <summary>Zeit buchen, wenn geplant und noch nicht gebucht; False bei Fehler.</summary>
function RunTime(const ACall: TAtlasTrackerEndCall; const APlan: TAtlasTrackerEndPlan;
  var AProgress: TAtlasTrackerEndProgress): Boolean;
var
  mResult: TAtlasTrackerWriteResult;
begin
  Result := True;
  if not APlan.Has(TAtlasTrackerEndStep.Time) or AProgress.TimeBooked then
  begin
    Exit;
  end;
  if ACall.Time = nil then
  begin
    mResult := TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.UnknownProvider, 0, '');
  end
  else
  begin
    mResult := ACall.Time.BookTime(ACall.Target, ACall.Transport, ACall.Key, APlan.Time, ACall.TimeoutMs);
  end;
  AProgress.TimeBooked := mResult.Succeeded;
  if not mResult.Succeeded then
  begin
    Stopped(AProgress, TAtlasTrackerEndStep.Time, mResult);
  end;
  Result := mResult.Succeeded;
end;

/// <summary>Ergebnis eines Pull Requests als Schreibergebnis: Ok, wenn er steht; sonst der Fehler (Dirty, Foreign
/// und PushFailed als Invalid, Text in AProgress.Pull).</summary>
function PullResult(const APull: TAtlasTrackerPullResult): TAtlasTrackerWriteResult;
begin
  if APull.Stands then
  begin
    Result := TAtlasTrackerWriteResult.Ok;
  end
  else if APull.Outcome = TAtlasTrackerPullOutcome.Failed then
  begin
    Result := TAtlasTrackerWriteResult.Failed(APull.Error, APull.Status, APull.Message);
  end
  else
  begin
    Result := TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.Invalid, 0, APull.Message);
  end;
end;

/// <summary>Pull Request pushen und anlegen, wenn geplant und noch keiner steht; False bei Fehler.</summary>
function RunPull(const ACall: TAtlasTrackerEndCall; const APlan: TAtlasTrackerEndPlan;
  var AProgress: TAtlasTrackerEndProgress): Boolean;
var
  mResult: TAtlasTrackerWriteResult;
begin
  Result := True;
  if not APlan.Pull.Wanted or AProgress.Pull.Stands then
  begin
    Exit;
  end;
  if Assigned(ACall.Pull) then
  begin
    AProgress.Pull := ACall.Pull(APlan.Pull);
  end
  else
  begin
    AProgress.Pull := TAtlasTrackerPullResult.Failure(TAtlasCiFetchError.UnknownProvider, 0, '');
  end;
  mResult := PullResult(AProgress.Pull);
  if not mResult.Succeeded then
  begin
    Stopped(AProgress, TAtlasTrackerEndStep.PullRequest, mResult);
  end;
  Result := mResult.Succeeded;
end;

/// <summary>AChange schreiben, wenn es etwas gibt und noch nicht geschrieben ist (ADone); False bei Fehler.
/// </summary>
function RunChange(const ACall: TAtlasTrackerEndCall; const AChange: TAtlasTrackerWrite; AStep: TAtlasTrackerEndStep;
  var ADone: Boolean; var AProgress: TAtlasTrackerEndProgress): Boolean;
var
  mResult: TAtlasTrackerWriteResult;
begin
  Result := True;
  if ADone or not AChange.HasWork then
  begin
    Exit;
  end;
  mResult := ACall.Writer.Apply(ACall.Target, ACall.Transport, ACall.Key, AChange, ACall.TimeoutMs);
  ADone := mResult.Succeeded;
  if not mResult.Succeeded then
  begin
    Stopped(AProgress, AStep, mResult);
  end;
  AProgress.Fallback := AProgress.Fallback or mResult.Fallback;
  if (mResult.Project.Project <> '') or mResult.Project.Denied then
  begin
    AProgress.Project := mResult.Project;
  end;
  Result := mResult.Succeeded;
end;

/// <summary>Original eines Duplikats prüfen, bevor etwas geschrieben wird (#2135): nicht leer, nicht das Issue
/// selbst und beim Tracker vorhanden. False hält den Lauf an.</summary>
function CheckDuplicate(const ACall: TAtlasTrackerEndCall; const APlan: TAtlasTrackerEndPlan;
  var AProgress: TAtlasTrackerEndProgress): Boolean;
var
  mOther: string;
  mIssue: TAtlasTrackerIssue;
  mError: TAtlasCiFetchError;
begin
  Result := True;
  if (APlan.Change.Close <> TAtlasTrackerClose.Duplicate) or AProgress.TransitionDone then
  begin
    Exit;
  end;
  mOther := Trim(APlan.Change.DuplicateOf);
  mError := TAtlasCiFetchError.None;
  if (mOther = '') or SameText(mOther, Trim(ACall.Key)) then
  begin
    mError := TAtlasCiFetchError.Invalid;
  end
  else if (ACall.Provider <> nil) and not ACall.Provider.Lookup(ACall.Target, ACall.Transport, mOther,
    ACall.TimeoutMs, mIssue, mError) then
  begin
    // Lookup meldet False immer mit Grund; ohne Grund gilt das Issue als unbekannt.
    if mError = TAtlasCiFetchError.None then
    begin
      mError := TAtlasCiFetchError.NotFound;
    end;
  end;
  if mError = TAtlasCiFetchError.None then
  begin
    Exit;
  end;
  AProgress.Fail(APlan, TAtlasTrackerWriteResult.Failed(mError, 0, ''));
  AProgress.DuplicateMissing := mError in [TAtlasCiFetchError.Invalid, TAtlasCiFetchError.NotFound];
  Result := False;
end;

class procedure TAtlasTrackerEndSteps.Run(const ACall: TAtlasTrackerEndCall; const APlan: TAtlasTrackerEndPlan;
  var AProgress: TAtlasTrackerEndProgress);
var
  mDone: Boolean;
begin
  AProgress.Failed := False;
  AProgress.FailedField := '';
  AProgress.Outcome := TAtlasTrackerWriteResult.Ok;
  AProgress.DuplicateMissing := False;
  if ACall.Writer = nil then
  begin
    AProgress.Fail(APlan, TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.UnknownProvider, 0, ''));
    Exit;
  end;
  if not CheckDuplicate(ACall, APlan, AProgress) or not RunTime(ACall, APlan, AProgress) or
    not RunFields(ACall, APlan, AProgress) or not RunPull(ACall, APlan, AProgress) then
  begin
    Exit;
  end;
  mDone := AProgress.CommentDone;
  if not RunChange(ACall, APlan.CommentPart, TAtlasTrackerEndStep.Comment, mDone, AProgress) then
  begin
    Exit;
  end;
  AProgress.CommentDone := mDone;
  mDone := AProgress.TransitionDone;
  RunChange(ACall, APlan.TransitionPart, TAtlasTrackerEndStep.Transition, mDone, AProgress);
  AProgress.TransitionDone := mDone;
end;

/// <summary>AText[AIndex] gehört zu einem Wort: Buchstabe, Ziffer oder Unterstrich (Anführungszeichen wie ‚…‘
/// nicht, anders als TTextChars.IsIdentChar).</summary>
function LetterAt(const AText: string; AIndex: Integer): Boolean;
begin
  Result := (AIndex >= 1) and (AIndex <= Length(AText)) and
    (AText[AIndex].IsLetterOrDigit or (AText[AIndex] = '_'));
end;

/// <summary>ANeedle steht in AHaystack (beide klein) als ganzes Wort.</summary>
function HasWord(const AHaystack, ANeedle: string): Boolean;
var
  mAt: Integer;
begin
  mAt := Pos(ANeedle, AHaystack);
  while mAt > 0 do
  begin
    if not LetterAt(AHaystack, mAt - 1) and not LetterAt(AHaystack, mAt + Length(ANeedle)) then
    begin
      Exit(True);
    end;
    mAt := Pos(ANeedle, AHaystack, mAt + 1);
  end;
  Result := False;
end;

class function TAtlasTrackerEndSteps.MentionedField(const AText: string; const ANames: TArray<string>): string;
var
  mText, mName: string;
begin
  Result := '';
  mText := AnsiLowerCase(AText);
  for mName in ANames do
  begin
    if (Trim(mName) <> '') and (Length(Trim(mName)) > Length(Result)) and
      HasWord(mText, AnsiLowerCase(Trim(mName))) then
    begin
      Result := Trim(mName);
    end;
  end;
end;

end.
