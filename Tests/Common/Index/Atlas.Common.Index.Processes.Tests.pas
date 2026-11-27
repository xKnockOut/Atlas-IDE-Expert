unit Atlas.Common.Index.Processes.Tests;

// Anmeldung eines Prozesses am Index-Cache als Datensatz (#62): JSON hin und
// zurück, Ereignisse aller Prozesse nach Zeit.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TIndexProcessInfoTests = class
  public
    [Test]
    procedure EventsAreMergedByTime;
    [Test]
    procedure JsonRoundTrip;
    [Test]
    procedure UnreadableTimesAreZero;
    [Test]
    procedure SessionTravelsAndOlderFilesHaveNone;
    [Test]
    procedure SessionIsShortAndDistinguishesProcesses;
  end;

implementation

uses
  System.SysUtils,
  System.DateUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Index.Processes,
  Atlas.Common.Index.Processes.TestSupport;

{ TIndexProcessInfoTests }

procedure TIndexProcessInfoTests.EventsAreMergedByTime;
var
  mLsp, mMcp: TIndexProcessInfo;
  mEvent: TIndexProcessEvent;
  mEvents: TArray<TIndexProcessEvent>;
  mBase: TDateTime;
begin
  mBase := EncodeDateTime(2026, 10, 21, 10, 41, 0, 0);
  mLsp := Info(1, TIndexProcessInfo.cKindLsp);
  mEvent.Time := mBase;
  mEvent.Text := 'Cache-Sperre erhalten';
  mLsp.Events := [mEvent];
  mEvent.Time := IncSecond(mBase, 19);
  mEvent.Text := 'Index gespeichert';
  mLsp.Events := mLsp.Events + [mEvent];
  mMcp := Info(2, TIndexProcessInfo.cKindMcp);
  mEvent.Time := IncSecond(mBase, 5);
  mEvent.Text := 'Sperre belegt';
  mMcp.Events := [mEvent];
  mEvent.Time := IncSecond(mBase, 19);
  mEvent.Text := 'neuen Stand übernommen';
  mMcp.Events := mMcp.Events + [mEvent];
  mEvents := TIndexProcessLog.Events([mLsp, mMcp]);
  Assert.AreEqual(4, Integer(Length(mEvents)));
  Assert.AreEqual('LSP: Cache-Sperre erhalten', mEvents[0].Text);
  Assert.AreEqual('MCP: Sperre belegt', mEvents[1].Text);
  Assert.AreEqual('LSP: Index gespeichert', mEvents[2].Text);
  Assert.AreEqual('MCP: neuen Stand übernommen', mEvents[3].Text);
  // Zwei LSP-Prozesse: mit Prozessnummer.
  mEvents := TIndexProcessLog.Events([mLsp, Info(3, TIndexProcessInfo.cKindLsp), mMcp]);
  Assert.AreEqual('LSP 1: Cache-Sperre erhalten', mEvents[0].Text);
end;

procedure TIndexProcessInfoTests.JsonRoundTrip;
var
  mSource, mCopy: TIndexProcessInfo;
  mJson: string;
  mEvent: TIndexProcessEvent;
  mValue: TJSONObject;
begin
  mSource := Info(42, TIndexProcessInfo.cKindMcp);
  mSource.State := TIndexProcessInfo.cStateReady;
  mSource.Writer := True;
  mSource.Started := EncodeDateTime(2026, 10, 21, 9, 0, 0, 0);
  mEvent.Time := mSource.Started;
  mEvent.Text := 'bereit';
  mSource.Events := [mEvent];
  mValue := mSource.ToJson;
  try
    mJson := mValue.ToJSON;
  finally
    mValue.Free;
  end;
  Assert.IsTrue(TIndexProcessInfo.FromJson(mJson, mCopy));
  Assert.AreEqual(Cardinal(42), mCopy.Pid);
  Assert.IsTrue(mCopy.Writer);
  Assert.AreEqual('Claude Code', mCopy.Client);
  Assert.AreEqual(mSource.Started, mCopy.Started, 1 / SecsPerDay);
  Assert.AreEqual('bereit', mCopy.Events[0].Text);
  Assert.IsFalse(TIndexProcessInfo.FromJson('{"pid":', mCopy));
  Assert.IsFalse(TIndexProcessInfo.FromJson('{"kind":"LSP"}', mCopy));
end;

procedure TIndexProcessInfoTests.UnreadableTimesAreZero;
var
  mCopy: TIndexProcessInfo;
begin
  // Unlesbarer Zeitpunkt: 0, die Anmeldung und ihre Ereignisse bleiben.
  Assert.IsTrue(TIndexProcessInfo.FromJson('{"pid":7,"kind":"MCP","started":"gestern",' +
    '"events":[{"time":"2026-13-01T00:00:00","text":"bereit"}]}', mCopy));
  Assert.AreEqual(Cardinal(7), mCopy.Pid);
  Assert.AreEqual(Double(0), Double(mCopy.Started));
  Assert.AreEqual(1, Integer(Length(mCopy.Events)));
  Assert.AreEqual(Double(0), Double(mCopy.Events[0].Time));
  Assert.AreEqual('bereit', mCopy.Events[0].Text);
end;

procedure TIndexProcessInfoTests.SessionTravelsAndOlderFilesHaveNone;
var
  mSource, mCopy: TIndexProcessInfo;
  mValue: TJSONObject;
  mJson: string;
begin
  mSource := Info(42, TIndexProcessInfo.cKindMcp);
  mSource.Session := '3f2a';
  mValue := mSource.ToJson;
  try
    mJson := mValue.ToJSON;
  finally
    mValue.Free;
  end;
  Assert.IsTrue(TIndexProcessInfo.FromJson(mJson, mCopy));
  Assert.AreEqual('3f2a', mCopy.Session);
  // Datei eines älteren Servers ohne "session".
  Assert.IsTrue(TIndexProcessInfo.FromJson('{"pid":7,"kind":"MCP","client":"A"}', mCopy));
  Assert.AreEqual('', mCopy.Session);
end;

procedure TIndexProcessInfoTests.SessionIsShortAndDistinguishesProcesses;
var
  mStarted: TDateTime;
  mSession: string;
begin
  mStarted := EncodeDateTime(2026, 11, 27, 9, 41, 12, 345);
  mSession := TIndexProcessInfo.SessionOf(4711, mStarted);
  Assert.AreEqual(4, Length(mSession));
  Assert.AreEqual(LowerCase(mSession), mSession);
  // Gleiche Werte, gleiche Kennung; anderer Prozess oder andere Startzeit, andere Kennung.
  Assert.AreEqual(mSession, TIndexProcessInfo.SessionOf(4711, mStarted));
  Assert.AreNotEqual(mSession, TIndexProcessInfo.SessionOf(4712, mStarted));
  Assert.AreNotEqual(mSession, TIndexProcessInfo.SessionOf(4711, IncMilliSecond(mStarted, 1)));
end;

initialization
  TDUnitX.RegisterTestFixture(TIndexProcessInfoTests);

end.
