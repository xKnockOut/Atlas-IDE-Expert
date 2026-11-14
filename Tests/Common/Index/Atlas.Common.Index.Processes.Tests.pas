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
  end;

implementation

uses
  System.SysUtils,
  System.DateUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Index.Processes;

function Info(APid: Cardinal; const AKind: string): TIndexProcessInfo;
begin
  Result := Default(TIndexProcessInfo);
  Result.Pid := APid;
  Result.Kind := AKind;
  Result.Client := 'Claude Code';
  Result.Workspace := 'Kasse';
end;

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

initialization
  TDUnitX.RegisterTestFixture(TIndexProcessInfoTests);

end.
