unit Atlas.Core.Tracker.Transitions.Tests;

// Tests der Übergänge einer Zustandsmaschine (#2122) ohne Server: Zuordnung
// Übergang → Zustand (gemeinsam mit dem Board), Vorwahl nach den
// Wunschzuständen, Beginnen und Beenden mit Übergang statt Wert, Lesen der
// Regeln aus Antworten von YouTrack (Tests\Data\YouTrack: benannte
// Ereignisse, nach Zuständen benannte Ereignisse, ohne Zustandsmaschine) und
// das Auslösen über TAtlasYouTrackApi.ApplyChange gegen einen Transport mit
// festen Antworten (Kommentar bzw. Befehl vorher, Ablehnung mit Text); Felder
// beim Beenden (#2123): Felder und Werte des Projekts, Setzen per Befehl und
// ein ganzer Lauf der Schritte mit Ablehnung durch eine Workflow-Regel.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tracker')]
  TAtlasTrackerTransitionsTests = class
  public
    [Test]
    procedure LeadsToByIdOrName;
    [Test]
    procedure IntoAndPreferred;
    [Test]
    procedure TargetOfAndChoiceText;
    [Test]
    procedure NamesAndIsAt;
    [Test]
    procedure FitStartFiresTransition;
    [Test]
    procedure FitStartBlockedOrAlreadyThere;
    [Test]
    procedure FitStartWithoutStateMachineUnchanged;
    [Test]
    procedure EndTransitionCarriesTransition;
  end;

  [TestFixture]
  [Category('Atlas.IDE.Tracker')]
  TAtlasYouTrackTransitionTests = class
  public
    [Test]
    procedure ParseIssueFixtures;
    [Test]
    procedure ReadAgainstFakeTransport;
    [Test]
    procedure ApplyFiresAfterComment;
    [Test]
    procedure ApplyWithAssignSendsCommandFirst;
    [Test]
    procedure ApplyRejectedKeepsMessage;
    [Test]
    procedure ApplyWithoutFieldIdNotConfigured;
  end;

  [TestFixture]
  [Category('Atlas.IDE.Tracker')]
  TAtlasYouTrackEndFieldsTests = class
  public
    [Test]
    procedure ParseProjectFieldsFixture;
    [Test]
    procedure FieldValuesAndSetField;
    /// <summary>Workflow-Regel lehnt den Übergang ab: Zeit und Kommentar bleiben geschrieben, das Feld wird
    /// erkannt, der zweite Lauf schreibt nur noch Feld und Übergang.</summary>
    [Test]
    procedure RunRejectedByRuleThenResumes;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.JSON,
  Atlas.Core.Ci.Contract,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.EndSteps,
  Atlas.Core.Tracker.Transitions,
  Atlas.Core.Tracker.YouTrackParse,
  Atlas.Core.Tracker.Workflow,
  Atlas.Core.Tracker.Providers.YouTrack,
  Atlas.Core.Tracker.YouTrackApi,
  Atlas.Core.Tracker.YouTrackWorkflow;

type
  /// <summary>Transport mit festen Antworten je Methode und Adressanfang; merkt sich Aufrufe und Inhalte.</summary>
  TFakeRulesTransport = class(TInterfacedObject, IAtlasCiTransport, IAtlasCiSend)
  private
    FMethods: TArray<string>;
    FPrefixes: TArray<string>;
    FStatus: TArray<Integer>;
    FTexts: TArray<string>;
  public
    Calls: TArray<string>;
    Bodies: TArray<string>;
    procedure Answer(const AMethod, APrefix: string; AStatus: Integer; const AText: string);
    function Reply(const AMethod, AUrl: string; out AStatus: Integer; out AText: string): Boolean;
    function Get(const AUrl: string; ATimeoutMs: Integer; out AStatus: Integer; out AText: string;
      out AError: TAtlasCiFetchError): Boolean;
    function Send(const AMethod, AUrl, ABody: string; ATimeoutMs: Integer; out AResponse: TAtlasCiResponse):
      Boolean;
  end;

procedure TFakeRulesTransport.Answer(const AMethod, APrefix: string; AStatus: Integer; const AText: string);
begin
  FMethods := FMethods + [AMethod];
  FPrefixes := FPrefixes + [APrefix];
  FStatus := FStatus + [AStatus];
  FTexts := FTexts + [AText];
end;

function TFakeRulesTransport.Reply(const AMethod, AUrl: string; out AStatus: Integer; out AText: string): Boolean;
var
  mIndex: Integer;
begin
  Calls := Calls + [AMethod + ' ' + AUrl];
  AStatus := 404;
  AText := '';
  Result := True;
  for mIndex := 0 to High(FPrefixes) do
  begin
    if (FMethods[mIndex] = AMethod) and (Copy(AUrl, 1, Length(FPrefixes[mIndex])) = FPrefixes[mIndex]) then
    begin
      AStatus := FStatus[mIndex];
      AText := FTexts[mIndex];
      Exit;
    end;
  end;
end;

function TFakeRulesTransport.Get(const AUrl: string; ATimeoutMs: Integer; out AStatus: Integer; out AText: string;
  out AError: TAtlasCiFetchError): Boolean;
begin
  AError := TAtlasCiFetchError.None;
  Result := Reply('GET', AUrl, AStatus, AText);
end;

function TFakeRulesTransport.Send(const AMethod, AUrl, ABody: string; ATimeoutMs: Integer;
  out AResponse: TAtlasCiResponse): Boolean;
begin
  AResponse := TAtlasCiResponse.Failed(TAtlasCiFetchError.None);
  Bodies := Bodies + [ABody];
  Result := Reply(AMethod, AUrl, AResponse.Status, AResponse.Text);
end;

function Fixture(const AName: string): string;
var
  mDirectory, mFileName: string;
begin
  mDirectory := ExtractFileDir(ParamStr(0));
  while mDirectory <> '' do
  begin
    mFileName := TPath.Combine(mDirectory, TPath.Combine('Tests', TPath.Combine('Data',
      TPath.Combine('YouTrack', AName))));
    if TFile.Exists(mFileName) then
    begin
      Exit(TFile.ReadAllText(mFileName, TEncoding.UTF8));
    end;
    if ExtractFileDir(mDirectory) = mDirectory then
    begin
      Break;
    end;
    mDirectory := ExtractFileDir(mDirectory);
  end;
  raise Exception.Create('Tests\Data\YouTrack\' + AName + ' nicht gefunden');
end;

function YouTrackTarget: TAtlasTrackerTarget;
begin
  Result := TAtlasTrackerTarget.Create('youtrack', 'https://yt.beispiel.de', 'ATL', '');
end;

/// <summary>Zustandsmaschine ab „In Bearbeitung“ mit benannten Ereignissen.</summary>
function NamedRules: TAtlasTrackerStateRules;
begin
  Result := Default(TAtlasTrackerStateRules);
  Result.StateMachine := True;
  Result.FieldId := '82-11';
  Result.Current := 'In Bearbeitung';
  Result.Transitions := [TAtlasTrackerTransition.Create('review', 'Zur Prüfung geben'),
    TAtlasTrackerTransition.Create('zurueckgestellt', 'Zurückstellen'),
    TAtlasTrackerTransition.Create('abbrechen', 'Abbrechen')];
end;

/// <summary>Zustandsmaschine ab „Neu“, Ereignisse nach den Zielzuständen benannt.</summary>
function StateRules: TAtlasTrackerStateRules;
begin
  Result := Default(TAtlasTrackerStateRules);
  Result.StateMachine := True;
  Result.FieldId := '82-11';
  Result.Current := 'Neu';
  Result.Transitions := [TAtlasTrackerTransition.Create('in-bearbeitung', 'In Bearbeitung'),
    TAtlasTrackerTransition.Create('abgelehnt', '')];
end;

/// <summary>Wert AName des JSON-Objekts AJson als Text ('' ohne).</summary>
function JsonText(const AJson, AName: string): string;
var
  mValue, mItem: TJSONValue;
begin
  Result := '';
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    if mValue is TJSONObject then
    begin
      mItem := TJSONObject(mValue).Values[AName];
      if mItem is TJSONObject then
      begin
        Result := mItem.ToJSON;
      end
      else if mItem <> nil then
      begin
        Result := mItem.Value;
      end;
    end;
  finally
    mValue.Free;
  end;
end;

{ TAtlasTrackerTransitionsTests }

procedure TAtlasTrackerTransitionsTests.LeadsToByIdOrName;
begin
  Assert.IsTrue(TAtlasTrackerTransitions.LeadsTo(TAtlasTrackerTransition.Create('in-bearbeitung', 'Beginnen'),
    TArray<string>.Create('Offen', 'In Bearbeitung')), 'Kennung, "-" wie Leerzeichen');
  Assert.IsTrue(TAtlasTrackerTransitions.LeadsTo(TAtlasTrackerTransition.Create('x', 'in_bearbeitung'),
    TArray<string>.Create('IN BEARBEITUNG')), 'Name, ohne Groß- und Kleinschreibung');
  Assert.IsFalse(TAtlasTrackerTransitions.LeadsTo(TAtlasTrackerTransition.Create('review', 'Zur Prüfung geben'),
    TArray<string>.Create('Zur Prüfung')), 'benanntes Ereignis verrät sein Ziel nicht');
  Assert.IsFalse(TAtlasTrackerTransitions.LeadsTo(TAtlasTrackerTransition.Create('', ''),
    TArray<string>.Create('', ' ')), 'leere Werte führen nirgends hin');
end;

procedure TAtlasTrackerTransitionsTests.IntoAndPreferred;
begin
  Assert.AreEqual(0, TAtlasTrackerTransitions.Into(StateRules, TArray<string>.Create('In Bearbeitung')));
  Assert.AreEqual(1, TAtlasTrackerTransitions.Into(StateRules, TArray<string>.Create('Abgelehnt', 'Erledigt')));
  Assert.AreEqual(-1, TAtlasTrackerTransitions.Into(StateRules, TArray<string>.Create('Erledigt')));
  // Reihenfolge der Wünsche zählt, nicht die der Übergänge.
  Assert.AreEqual(1, TAtlasTrackerTransitions.Preferred(StateRules,
    TArray<string>.Create('Behoben', 'Abgelehnt', 'In Bearbeitung')));
  Assert.AreEqual(-1, TAtlasTrackerTransitions.Preferred(NamedRules, TArray<string>.Create('Behoben')));
  Assert.AreEqual(-1, TAtlasTrackerTransitions.Preferred(StateRules, nil));
end;

procedure TAtlasTrackerTransitionsTests.TargetOfAndChoiceText;
var
  mStates: TArray<string>;
begin
  mStates := TArray<string>.Create('Neu', 'In Bearbeitung', 'Zurückgestellt', 'Abgelehnt');
  Assert.AreEqual('Abgelehnt', TAtlasTrackerTransitions.TargetOf(TAtlasTrackerTransition.Create('abgelehnt',
    'Ablehnen'), mStates), 'über die Kennung');
  Assert.AreEqual('', TAtlasTrackerTransitions.TargetOf(NamedRules.Transitions[0], mStates));
  Assert.AreEqual('', TAtlasTrackerTransitions.TargetOf(NamedRules.Transitions[1], mStates),
    '"zurueckgestellt" ist nicht "Zurückgestellt"');
  Assert.AreEqual('Ablehnen → Abgelehnt', TAtlasTrackerTransitions.ChoiceText(TAtlasTrackerTransition.Create(
    'abgelehnt', 'Ablehnen'), mStates));
  Assert.AreEqual('Zur Prüfung geben', TAtlasTrackerTransitions.ChoiceText(NamedRules.Transitions[0], mStates),
    'ohne bekanntes Ziel nur der Name');
  Assert.AreEqual('In Bearbeitung', TAtlasTrackerTransitions.ChoiceText(StateRules.Transitions[0], mStates),
    'Ziel gleich Name: kein Pfeil');
  Assert.AreEqual('abgelehnt', TAtlasTrackerTransitions.ChoiceText(StateRules.Transitions[1], mStates),
    'ohne Namen die Kennung, Ziel gleich Kennung');
end;

procedure TAtlasTrackerTransitionsTests.NamesAndIsAt;
begin
  Assert.AreEqual('Zur Prüfung geben, Zurückstellen, Abbrechen', TAtlasTrackerTransitions.Names(NamedRules));
  Assert.AreEqual(2, Integer(Length(TAtlasTrackerTransitions.Captions(StateRules))));
  Assert.AreEqual('abgelehnt', TAtlasTrackerTransitions.Captions(StateRules)[1]);
  Assert.IsTrue(TAtlasTrackerTransitions.IsAt(NamedRules, ' in bearbeitung '));
  Assert.IsFalse(TAtlasTrackerTransitions.IsAt(NamedRules, ''));
  Assert.IsFalse(TAtlasTrackerTransitions.IsAt(StateRules, 'In Bearbeitung'));
end;

function StartWith(const AState: string): TAtlasTrackerWrite;
begin
  Result := TAtlasTrackerWrite.Empty;
  Result.StateField := 'Status';
  Result.State := AState;
  Result.Assign := TAtlasTrackerAssign.Me;
  Result.Comment := 'Beginne';
end;

procedure TAtlasTrackerTransitionsTests.FitStartFiresTransition;
var
  mChange: TAtlasTrackerWrite;
  mBlocked: Boolean;
begin
  mChange := TAtlasTrackerWorkflow.FitStart(StartWith('In Bearbeitung'), StateRules, mBlocked);
  Assert.IsFalse(mBlocked);
  Assert.AreEqual('', mChange.State, 'kein Befehl mit dem Wert');
  Assert.AreEqual('in-bearbeitung', mChange.Transition.Id);
  Assert.AreEqual('82-11', mChange.FieldId);
  Assert.AreEqual(Ord(TAtlasTrackerAssign.Me), Ord(mChange.Assign), 'Zuweisung bleibt');
  Assert.AreEqual('Beginne', mChange.Comment);
  Assert.IsTrue(mChange.HasWork);
end;

procedure TAtlasTrackerTransitionsTests.FitStartBlockedOrAlreadyThere;
var
  mChange: TAtlasTrackerWrite;
  mBlocked: Boolean;
begin
  mChange := TAtlasTrackerWorkflow.FitStart(StartWith('Offen'), NamedRules, mBlocked);
  Assert.IsTrue(mBlocked, 'kein Übergang nach „Offen“');
  Assert.AreEqual('', mChange.State);
  Assert.AreEqual('', mChange.Transition.Id);
  Assert.AreEqual('Beginne', mChange.Comment, 'Kommentar und Zuweisung gehen trotzdem');
  mChange := TAtlasTrackerWorkflow.FitStart(StartWith('in bearbeitung'), NamedRules, mBlocked);
  Assert.IsFalse(mBlocked, 'schon dort');
  Assert.AreEqual('', mChange.State);
  Assert.AreEqual('', mChange.Transition.Id);
end;

procedure TAtlasTrackerTransitionsTests.FitStartWithoutStateMachineUnchanged;
var
  mRules: TAtlasTrackerStateRules;
  mChange: TAtlasTrackerWrite;
  mBlocked: Boolean;
begin
  mRules := Default(TAtlasTrackerStateRules);
  mRules.Current := 'Offen';
  mChange := TAtlasTrackerWorkflow.FitStart(StartWith('In Bearbeitung'), mRules, mBlocked);
  Assert.IsFalse(mBlocked);
  Assert.AreEqual('In Bearbeitung', mChange.State, 'Befehl mit dem Wert wie bisher');
  Assert.AreEqual('', mChange.Transition.Id);
  // Zustandsmaschine ohne Feld-ID: nichts auslösbar, also wie bisher.
  mRules := StateRules;
  mRules.FieldId := '';
  mChange := TAtlasTrackerWorkflow.FitStart(StartWith('In Bearbeitung'), mRules, mBlocked);
  Assert.AreEqual('In Bearbeitung', mChange.State);
end;

procedure TAtlasTrackerTransitionsTests.EndTransitionCarriesTransition;
var
  mOptions: TAtlasTrackerSyncOptions;
  mChange: TAtlasTrackerWrite;
begin
  mOptions := TAtlasTrackerSyncOptions.Create(True, 'Status', '').WithStart('In Bearbeitung', False, '')
    .WithEnd('Behoben', '');
  mChange := TAtlasTrackerWorkflow.EndTransition(mOptions, NamedRules, 0, ' Fertig ', True, 'anna');
  Assert.AreEqual('review', mChange.Transition.Id);
  Assert.AreEqual('82-11', mChange.FieldId);
  Assert.AreEqual('', mChange.State);
  Assert.AreEqual('Fertig', mChange.Comment);
  Assert.AreEqual('anna', mChange.Assignee);
  mChange := TAtlasTrackerWorkflow.EndTransition(mOptions, NamedRules, -1, 'Fertig', False, '');
  Assert.AreEqual('', mChange.Transition.Id, 'Zustand nicht ändern');
  Assert.AreEqual('Fertig', mChange.Comment);
  mChange := TAtlasTrackerWorkflow.EndTransition(mOptions, NamedRules, 9, '', False, '');
  Assert.IsFalse(mChange.HasWork, 'ungültiger Index');
end;

{ TAtlasYouTrackTransitionTests }

procedure TAtlasYouTrackTransitionTests.ParseIssueFixtures;
var
  mRules: TAtlasTrackerStateRules;
begin
  Assert.IsTrue(TAtlasYouTrackWorkflow.ParseIssue(Fixture('state-rules-named.json'), 'status', mRules));
  Assert.IsTrue(mRules.StateMachine);
  Assert.AreEqual('82-11', mRules.FieldId);
  Assert.AreEqual('In Bearbeitung', mRules.Current);
  Assert.AreEqual(3, Integer(Length(mRules.Transitions)));
  Assert.AreEqual('Zur Prüfung geben', mRules.Transitions[0].Name);
  Assert.AreEqual(-1, TAtlasTrackerTransitions.Preferred(mRules, TArray<string>.Create('Behoben')));
  Assert.IsTrue(TAtlasYouTrackWorkflow.ParseIssue(Fixture('state-rules-states.json'), 'Status', mRules));
  Assert.AreEqual('Neu', mRules.Current);
  Assert.AreEqual(0, TAtlasTrackerTransitions.Preferred(mRules, TArray<string>.Create('In Bearbeitung')));
  Assert.IsTrue(TAtlasYouTrackWorkflow.ParseIssue(Fixture('state-rules-plain.json'), 'Status', mRules));
  Assert.IsFalse(mRules.StateMachine, 'ohne Zustandsmaschine');
  Assert.AreEqual('Offen', mRules.Current, 'Wert trotzdem bekannt');
  Assert.IsTrue(TAtlasYouTrackWorkflow.ParseIssue(Fixture('state-rules-named.json'), 'State', mRules));
  Assert.IsFalse(mRules.StateMachine, 'anderes Feld');
  Assert.IsFalse(TAtlasYouTrackWorkflow.ParseIssue('kein JSON', 'Status', mRules));
end;

procedure TAtlasYouTrackTransitionTests.ReadAgainstFakeTransport;
var
  mTransport: TFakeRulesTransport;
  mKeep: IAtlasCiTransport;
  mReader: IAtlasTrackerStateRules;
  mRules: TAtlasTrackerStateRules;
begin
  mTransport := TFakeRulesTransport.Create;
  mKeep := mTransport;
  mTransport.Answer('GET', 'https://yt.beispiel.de/api/issues/ATL-2052?fields=', 200,
    Fixture('state-rules-named.json'));
  mReader := TAtlasYouTrackTracker.Create;
  Assert.IsTrue(mReader.StateRules(YouTrackTarget, mKeep, 'ATL-2052', 'Status', 5000, mRules).Succeeded);
  Assert.AreEqual(3, Integer(Length(mRules.Transitions)));
  Assert.Contains(mTransport.Calls[0], 'possibleEvents');
  Assert.AreEqual<TAtlasCiFetchError>(TAtlasCiFetchError.NotFound,
    mReader.StateRules(YouTrackTarget, mKeep, 'ATL-9', 'Status', 5000, mRules).Error);
  Assert.IsFalse(mReader.StateRules(YouTrackTarget, mKeep, 'ATL 1/..', 'Status', 5000, mRules).Succeeded,
    'ungültige Kennung');
  Assert.AreEqual(2, Integer(Length(mTransport.Calls)), 'ungültige Kennung fragt nicht');
end;

function ReviewChange(const AComment: string): TAtlasTrackerWrite;
begin
  Result := TAtlasTrackerWrite.Empty;
  Result.StateField := 'Status';
  Result.Comment := AComment;
  Result.Transition := TAtlasTrackerTransition.Create('review', 'Zur Prüfung geben');
  Result.FieldId := '82-11';
end;

procedure TAtlasYouTrackTransitionTests.ApplyFiresAfterComment;
var
  mTransport: TFakeRulesTransport;
  mKeep: IAtlasCiTransport;
  mWriter: IAtlasTrackerWriter;
begin
  mTransport := TFakeRulesTransport.Create;
  mKeep := mTransport;
  mTransport.Answer('POST', 'https://yt.beispiel.de/api/issues/ATL-2052/comments', 200, '{"id":"1"}');
  mTransport.Answer('POST', 'https://yt.beispiel.de/api/issues/ATL-2052/fields/82-11', 200, '{"id":"82-11"}');
  mWriter := TAtlasYouTrackTracker.Create;
  Assert.IsTrue(mWriter.Apply(YouTrackTarget, mKeep, 'ATL-2052', ReviewChange('Fertig'), 5000).Succeeded);
  Assert.AreEqual(2, Integer(Length(mTransport.Calls)));
  Assert.AreEqual('POST https://yt.beispiel.de/api/issues/ATL-2052/comments?fields=id', mTransport.Calls[0],
    'Kommentar zuerst');
  Assert.AreEqual('POST https://yt.beispiel.de/api/issues/ATL-2052/fields/82-11?fields=id', mTransport.Calls[1]);
  Assert.AreEqual('StateMachineIssueCustomField', JsonText(mTransport.Bodies[1], '$type'));
  Assert.AreEqual('review', JsonText(JsonText(mTransport.Bodies[1], 'event'), 'id'));
  // Ohne Kommentar nur das Ereignis; kein Befehl mit dem Wert.
  Assert.IsTrue(mWriter.Apply(YouTrackTarget, mKeep, 'ATL-2052', ReviewChange(''), 5000).Succeeded);
  Assert.AreEqual(3, Integer(Length(mTransport.Calls)));
  Assert.AreEqual('POST https://yt.beispiel.de/api/issues/ATL-2052/fields/82-11?fields=id', mTransport.Calls[2]);
end;

procedure TAtlasYouTrackTransitionTests.ApplyWithAssignSendsCommandFirst;
var
  mTransport: TFakeRulesTransport;
  mKeep: IAtlasCiTransport;
  mWriter: IAtlasTrackerWriter;
  mChange: TAtlasTrackerWrite;
begin
  mTransport := TFakeRulesTransport.Create;
  mKeep := mTransport;
  mTransport.Answer('POST', 'https://yt.beispiel.de/api/commands', 200, '{}');
  mTransport.Answer('POST', 'https://yt.beispiel.de/api/issues/ATL-2052/fields/82-11', 200, '{}');
  mWriter := TAtlasYouTrackTracker.Create;
  mChange := ReviewChange('Fertig');
  mChange.State := 'Zur Prüfung';
  mChange.AssigneeField := 'Assignee';
  mChange.Assign := TAtlasTrackerAssign.User;
  mChange.Assignee := 'anna';
  Assert.IsTrue(mWriter.Apply(YouTrackTarget, mKeep, 'ATL-2052', mChange, 5000).Succeeded);
  Assert.AreEqual('POST https://yt.beispiel.de/api/commands', mTransport.Calls[0]);
  Assert.AreEqual('Assignee anna', JsonText(mTransport.Bodies[0], 'query'), 'Zustand nicht im Befehl');
  Assert.AreEqual('Fertig', JsonText(mTransport.Bodies[0], 'comment'));
  Assert.AreEqual('POST https://yt.beispiel.de/api/issues/ATL-2052/fields/82-11?fields=id', mTransport.Calls[1]);
end;

procedure TAtlasYouTrackTransitionTests.ApplyRejectedKeepsMessage;
var
  mTransport: TFakeRulesTransport;
  mKeep: IAtlasCiTransport;
  mWriter: IAtlasTrackerWriter;
  mResult: TAtlasTrackerWriteResult;
begin
  mTransport := TFakeRulesTransport.Create;
  mKeep := mTransport;
  mTransport.Answer('POST', 'https://yt.beispiel.de/api/issues/ATL-2052/fields/82-11', 400,
    Fixture('event-no-event.json'));
  mWriter := TAtlasYouTrackTracker.Create;
  mResult := mWriter.Apply(YouTrackTarget, mKeep, 'ATL-2052', ReviewChange(''), 5000);
  Assert.AreEqual<TAtlasCiFetchError>(TAtlasCiFetchError.Invalid, mResult.Error);
  Assert.AreEqual(400, mResult.Status);
  Assert.Contains(mResult.Message, 'No event found');
  // Kommentar abgelehnt: das Ereignis geht nicht mehr hinaus.
  mTransport.Answer('POST', 'https://yt.beispiel.de/api/issues/ATL-2052/comments', 403, '{}');
  mResult := mWriter.Apply(YouTrackTarget, mKeep, 'ATL-2052', ReviewChange('Fertig'), 5000);
  Assert.AreEqual(403, mResult.Status);
  Assert.AreEqual(2, Integer(Length(mTransport.Calls)));
end;

procedure TAtlasYouTrackTransitionTests.ApplyWithoutFieldIdNotConfigured;
var
  mTransport: TFakeRulesTransport;
  mKeep: IAtlasCiTransport;
  mChange: TAtlasTrackerWrite;
begin
  mTransport := TFakeRulesTransport.Create;
  mKeep := mTransport;
  mChange := ReviewChange('Fertig');
  mChange.FieldId := '82/11';
  Assert.AreEqual<TAtlasCiFetchError>(TAtlasCiFetchError.NotConfigured,
    TAtlasYouTrackApi.ApplyChange(YouTrackTarget, mKeep, 'ATL-2052', mChange, 5000).Error);
  Assert.AreEqual(0, Integer(Length(mTransport.Calls)), 'nichts halb geschrieben');
end;

{ TAtlasYouTrackEndFieldsTests }

procedure TAtlasYouTrackEndFieldsTests.ParseProjectFieldsFixture;
var
  mValues: TArray<string>;
begin
  Assert.IsTrue(TAtlasYouTrackParse.ParseProjectFields(Fixture('end-fields-projects.json'), 'ATL', '', mValues));
  Assert.AreEqual('Status|Behoben in Version|Ursache|Notiz', string.Join('|', mValues), 'Namen der Felder');
  Assert.IsTrue(TAtlasYouTrackParse.ParseProjectFields(Fixture('end-fields-projects.json'), 'atl',
    'behoben in version', mValues));
  Assert.AreEqual('2.1.0|2.2.0', string.Join('|', mValues), 'archivierte Werte fehlen');
  Assert.IsTrue(TAtlasYouTrackParse.ParseProjectFields(Fixture('end-fields-projects.json'), 'WEB', 'Ursache',
    mValues));
  Assert.AreEqual('Tippfehler', string.Join('|', mValues), 'nur das genannte Projekt');
  Assert.IsTrue(TAtlasYouTrackParse.ParseProjectFields(Fixture('end-fields-projects.json'), 'ATL', 'Notiz',
    mValues));
  Assert.AreEqual(0, Integer(Length(mValues)), 'Textfeld ohne Werte');
  Assert.IsFalse(TAtlasYouTrackParse.ParseProjectFields('{}', 'ATL', '', mValues));
end;

procedure TAtlasYouTrackEndFieldsTests.FieldValuesAndSetField;
var
  mTransport: TFakeRulesTransport;
  mKeep: IAtlasCiTransport;
  mFields: IAtlasTrackerFields;
  mValues: TArray<string>;
begin
  mTransport := TFakeRulesTransport.Create;
  mKeep := mTransport;
  mTransport.Answer('GET', 'https://yt.beispiel.de/api/admin/projects', 200, Fixture('end-fields-projects.json'));
  mTransport.Answer('POST', 'https://yt.beispiel.de/api/commands', 200, '{}');
  mFields := TAtlasYouTrackTracker.Create;
  Assert.IsTrue(mFields.FieldValues(YouTrackTarget, mKeep, 'ATL-2052', 'Ursache', 5000, mValues).Succeeded);
  Assert.AreEqual('Fehlende Prüfung|Falsche Annahme', string.Join('|', mValues));
  Assert.IsTrue(mFields.SetField(YouTrackTarget, mKeep, 'ATL-2052', 'Behoben in Version', '2.1.0', 5000).Succeeded);
  Assert.AreEqual('{Behoben in Version} 2.1.0', JsonText(mTransport.Bodies[0], 'query'));
  Assert.AreEqual<TAtlasCiFetchError>(TAtlasCiFetchError.NotConfigured,
    mFields.SetField(YouTrackTarget, mKeep, 'ATL-2052', 'Ursache', '', 5000).Error, 'leerer Wert geht nicht hinaus');
  Assert.AreEqual(1, Integer(Length(mTransport.Bodies)));
end;

procedure TAtlasYouTrackEndFieldsTests.RunRejectedByRuleThenResumes;
var
  mTransport: TFakeRulesTransport;
  mKeep: IAtlasCiTransport;
  mTracker: TAtlasYouTrackTracker;
  mCall: TAtlasTrackerEndCall;
  mPlan: TAtlasTrackerEndPlan;
  mProgress: TAtlasTrackerEndProgress;
begin
  mTransport := TFakeRulesTransport.Create;
  mKeep := mTransport;
  mTransport.Answer('POST', 'https://yt.beispiel.de/api/issues/ATL-2052/timeTracking/workItems', 200, '{"id":"w"}');
  mTransport.Answer('POST', 'https://yt.beispiel.de/api/issues/ATL-2052/comments', 200, '{"id":"c"}');
  mTransport.Answer('POST', 'https://yt.beispiel.de/api/issues/ATL-2052/fields/82-11', 400,
    Fixture('end-rule-rejected.json'));
  mTracker := TAtlasYouTrackTracker.Create;
  mCall := Default(TAtlasTrackerEndCall);
  mCall.Writer := mTracker;
  mCall.Time := mTracker;
  mCall.Fields := mTracker;
  mCall.Target := YouTrackTarget;
  mCall.Transport := mKeep;
  mCall.Key := 'ATL-2052';
  mCall.TimeoutMs := 5000;
  mPlan := TAtlasTrackerEndPlan.Create(ReviewChange('Fertig'));
  mPlan.Time := TAtlasTrackerWorkItem.Create(85, EncodeDate(2026, 11, 12), '', 'abc1234 Fix');
  mProgress := TAtlasTrackerEndProgress.Empty;
  TAtlasTrackerEndSteps.Run(mCall, mPlan, mProgress);
  Assert.IsTrue(mProgress.TimeBooked);
  Assert.IsTrue(mProgress.CommentDone);
  Assert.IsFalse(mProgress.TransitionDone);
  Assert.AreEqual<TAtlasTrackerEndStep>(TAtlasTrackerEndStep.Transition, mProgress.FailedStep);
  Assert.AreEqual('Behoben in Version', TAtlasTrackerEndSteps.MentionedField(mProgress.Outcome.Message,
    TArray<string>.Create('Status', 'Behoben in Version', 'Ursache', 'Version')), 'längster ganzer Name');
  // Feld ergänzt, Regel erfüllt: nur Feld und Übergang gehen hinaus.
  mPlan.AddField('Behoben in Version', '2.1.0');
  mTransport := TFakeRulesTransport.Create;
  mKeep := mTransport;
  mTransport.Answer('POST', 'https://yt.beispiel.de/api/commands', 200, '{}');
  mTransport.Answer('POST', 'https://yt.beispiel.de/api/issues/ATL-2052/fields/82-11', 200, '{}');
  mCall.Transport := mKeep;
  TAtlasTrackerEndSteps.Run(mCall, mPlan, mProgress);
  Assert.IsTrue(mProgress.Finished(mPlan));
  Assert.AreEqual(2, Integer(Length(mTransport.Calls)));
  Assert.AreEqual('POST https://yt.beispiel.de/api/commands', mTransport.Calls[0]);
  Assert.AreEqual('POST https://yt.beispiel.de/api/issues/ATL-2052/fields/82-11?fields=id', mTransport.Calls[1]);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTrackerTransitionsTests);
  TDUnitX.RegisterTestFixture(TAtlasYouTrackTransitionTests);
  TDUnitX.RegisterTestFixture(TAtlasYouTrackEndFieldsTests);

end.
