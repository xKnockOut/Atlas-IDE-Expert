unit Atlas.Core.Tracker.PreviewLoad.Tests;

// Ablauf des Ladens im Fenster „Atlas-Issue“ (#1264) gegen einen gefälschten
// Lader: eine Abfrage zur Zeit, ein zweiter Wunsch bricht ab und folgt, eine
// veraltete Antwort lässt den Abbruch der laufenden wirksam, Abbrechen ohne
// Lauf, Fehler ohne Abfrage und Zurücksetzen beim Abmelden.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Tracker.PreviewLoad,
  Atlas.Tests.IssueLoaderFake;

type
  [TestFixture]
  [Category('Atlas.IDE.Tracker')]
  TAtlasIssueLoadFlowTests = class
  private
    FFake: TAtlasIssueLoaderFake;
    FFlow: TAtlasIssueLoadFlow;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure FirstRequestStarts;
    /// <summary>Ein zweiter Wunsch während des Ladens startet keine zweite Abfrage: Er bricht die laufende ab und
    /// folgt ihr, deren Antwort wird nicht gezeigt.</summary>
    [Test]
    procedure SecondRequestCancelsAndFollows;
    [Test]
    procedure LatestPendingWins;
    /// <summary>Eine verspätete Antwort einer früheren Abfrage beendet die laufende nicht; „Abbrechen“ erreicht sie
    /// danach noch.</summary>
    [Test]
    procedure OutdatedAnswerKeepsCancelOfRunning;
    [Test]
    procedure CancelWithoutRunDoesNothing;
    [Test]
    procedure CancelForgetsPending;
    [Test]
    procedure AnswerShowsOrFails;
    /// <summary>Ohne Transport startet keine Abfrage: Fehler sofort, der nächste Wunsch startet gleich.</summary>
    [Test]
    procedure RefusedStartFailsAtOnce;
    /// <summary>Generation zählt beim Abmelden hoch: Die Antwort der laufenden beendet sie, zeigt aber nichts.
    /// </summary>
    [Test]
    procedure AnswerAfterStopIsOutdated;
    [Test]
    procedure ResetForgetsRunAndPending;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Plugin.CiBuild.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Preview;

function Entry(const AKey: string): TAtlasIssueHistoryEntry;
begin
  Result := TAtlasIssueHistoryEntry.Create(Default(TAtlasTrackerTarget), AKey);
end;

function Answer(AGeneration: Integer; const AKey: string; ASucceeded: Boolean;
  AError: TAtlasCiFetchError): TAtlasIssueLoadAnswer;
begin
  Result := TAtlasIssueLoadAnswer.Create(AGeneration, Entry(AKey), ASucceeded, TAtlasTrackerDetails.Empty, AError);
end;

{ TAtlasIssueLoadFlowTests }

procedure TAtlasIssueLoadFlowTests.Setup;
begin
  FFake := TAtlasIssueLoaderFake.Create;
  FFlow := TAtlasIssueLoadFlow.Create(FFake.Loader);
end;

procedure TAtlasIssueLoadFlowTests.TearDown;
begin
  FreeAndNil(FFlow);
  FreeAndNil(FFake);
end;

procedure TAtlasIssueLoadFlowTests.FirstRequestStarts;
begin
  FFlow.Request(Entry('ATL-1'));
  Assert.AreEqual('start:ATL-1:1', FFake.CallText);
  Assert.IsTrue(FFlow.Running);
  Assert.IsFalse(FFlow.HasPending);
end;

procedure TAtlasIssueLoadFlowTests.SecondRequestCancelsAndFollows;
begin
  FFlow.Request(Entry('ATL-1'));
  FFlow.Request(Entry('ATL-2'));
  Assert.AreEqual('start:ATL-1:1,cancel', FFake.CallText, 'keine zweite Abfrage, die laufende abgebrochen');
  Assert.IsTrue(FFlow.HasPending);
  FFake.Calls.Clear;
  FFlow.Finished(Answer(1, 'ATL-1', False, TAtlasCiFetchError.Cancelled));
  Assert.AreEqual('ended,arrived:ATL-1:Pending,start:ATL-2:2', FFake.CallText, 'der vorgemerkte Wunsch folgt');
  Assert.IsTrue(FFlow.Running);
  Assert.IsFalse(FFlow.HasPending);
  FFake.Calls.Clear;
  FFlow.Finished(Answer(2, 'ATL-2', True, TAtlasCiFetchError.Network));
  Assert.AreEqual('ended,arrived:ATL-2:Show', FFake.CallText);
  Assert.IsFalse(FFlow.Running);
end;

procedure TAtlasIssueLoadFlowTests.LatestPendingWins;
begin
  FFlow.Request(Entry('ATL-1'));
  FFlow.Request(Entry('ATL-2'));
  FFlow.Request(Entry('ATL-3'));
  FFake.Calls.Clear;
  FFlow.Finished(Answer(1, 'ATL-1', True, TAtlasCiFetchError.Network));
  Assert.AreEqual('ended,arrived:ATL-1:Pending,start:ATL-3:2', FFake.CallText, 'ATL-2 entfällt');
end;

procedure TAtlasIssueLoadFlowTests.OutdatedAnswerKeepsCancelOfRunning;
begin
  FFlow.Request(Entry('ATL-1'));
  FFlow.Finished(Answer(1, 'ATL-1', True, TAtlasCiFetchError.Network));
  FFlow.Request(Entry('ATL-2'));
  FFake.Calls.Clear;
  // Verspätet noch einmal die Antwort der ersten Abfrage (Generation 1, ATL-2 läuft unter 2).
  FFlow.Finished(Answer(1, 'ATL-1', True, TAtlasCiFetchError.Network));
  Assert.AreEqual('arrived:ATL-1:Outdated', FFake.CallText, 'nicht beendet, nichts gezeigt');
  Assert.IsTrue(FFlow.Running);
  FFake.Calls.Clear;
  FFlow.Cancel;
  Assert.AreEqual('cancel', FFake.CallText, 'Abbrechen erreicht die laufende');
end;

procedure TAtlasIssueLoadFlowTests.CancelWithoutRunDoesNothing;
begin
  FFlow.Cancel;
  Assert.AreEqual('', FFake.CallText);
  FFlow.Request(Entry('ATL-1'));
  FFlow.Finished(Answer(1, 'ATL-1', True, TAtlasCiFetchError.Network));
  FFake.Calls.Clear;
  FFlow.Cancel;
  Assert.AreEqual('', FFake.CallText, 'nach dem Ende nichts mehr abzubrechen');
end;

procedure TAtlasIssueLoadFlowTests.CancelForgetsPending;
begin
  FFlow.Request(Entry('ATL-1'));
  FFlow.Request(Entry('ATL-2'));
  FFlow.Cancel;
  Assert.IsFalse(FFlow.HasPending);
  FFake.Calls.Clear;
  FFlow.Finished(Answer(1, 'ATL-1', False, TAtlasCiFetchError.Cancelled));
  Assert.AreEqual('ended,arrived:ATL-1:Fail', FFake.CallText, 'ATL-2 startet nicht mehr');
  Assert.IsFalse(FFlow.Running);
end;

procedure TAtlasIssueLoadFlowTests.AnswerShowsOrFails;
begin
  FFlow.Request(Entry('ATL-1'));
  FFlow.Finished(Answer(1, 'ATL-1', False, TAtlasCiFetchError.Timeout));
  FFlow.Request(Entry('ATL-2'));
  FFlow.Finished(Answer(2, 'ATL-2', True, TAtlasCiFetchError.Network));
  Assert.AreEqual('start:ATL-1:1,ended,arrived:ATL-1:Fail,start:ATL-2:2,ended,arrived:ATL-2:Show', FFake.CallText);
end;

procedure TAtlasIssueLoadFlowTests.RefusedStartFailsAtOnce;
begin
  FFake.Refuse := True;
  FFlow.Request(Entry('ATL-1'));
  Assert.AreEqual('start:ATL-1:1,arrived:ATL-1:Fail', FFake.CallText);
  Assert.IsFalse(FFlow.Running);
  FFake.Refuse := False;
  FFake.Calls.Clear;
  FFlow.Request(Entry('ATL-2'));
  Assert.AreEqual('start:ATL-2:2', FFake.CallText, 'ohne Vormerken');
end;

procedure TAtlasIssueLoadFlowTests.AnswerAfterStopIsOutdated;
begin
  FFlow.Request(Entry('ATL-1'));
  FFake.Generation := FFake.Generation + 1;
  FFake.Calls.Clear;
  FFlow.Finished(Answer(1, 'ATL-1', True, TAtlasCiFetchError.Network));
  Assert.AreEqual('ended,arrived:ATL-1:Outdated', FFake.CallText);
  Assert.IsFalse(FFlow.Running);
end;

procedure TAtlasIssueLoadFlowTests.ResetForgetsRunAndPending;
begin
  FFlow.Request(Entry('ATL-1'));
  FFlow.Request(Entry('ATL-2'));
  FFlow.Reset;
  Assert.IsFalse(FFlow.Running);
  Assert.IsFalse(FFlow.HasPending);
  FFake.Calls.Clear;
  FFlow.Finished(Answer(1, 'ATL-1', True, TAtlasCiFetchError.Network));
  Assert.AreEqual('arrived:ATL-1:Outdated', FFake.CallText, 'spätere Antwort zählt nicht');
  FFake.Calls.Clear;
  FFlow.Request(Entry('ATL-3'));
  Assert.AreEqual('start:ATL-3:2', FFake.CallText, 'danach startet ein Wunsch sofort');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasIssueLoadFlowTests);

end.
