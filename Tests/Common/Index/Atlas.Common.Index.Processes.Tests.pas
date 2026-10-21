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
  Lsp, Mcp: TIndexProcessInfo;
  Event: TIndexProcessEvent;
  Events: TArray<TIndexProcessEvent>;
  Base: TDateTime;
begin
  Base := EncodeDateTime(2026, 10, 21, 10, 41, 0, 0);
  Lsp := Info(1, TIndexProcessInfo.KindLsp);
  Event.Time := Base;
  Event.Text := 'Cache-Sperre erhalten';
  Lsp.Events := [Event];
  Event.Time := IncSecond(Base, 19);
  Event.Text := 'Index gespeichert';
  Lsp.Events := Lsp.Events + [Event];
  Mcp := Info(2, TIndexProcessInfo.KindMcp);
  Event.Time := IncSecond(Base, 5);
  Event.Text := 'Sperre belegt';
  Mcp.Events := [Event];
  Event.Time := IncSecond(Base, 19);
  Event.Text := 'neuen Stand übernommen';
  Mcp.Events := Mcp.Events + [Event];
  Events := TIndexProcessLog.Events([Lsp, Mcp]);
  Assert.AreEqual(4, Integer(Length(Events)));
  Assert.AreEqual('LSP: Cache-Sperre erhalten', Events[0].Text);
  Assert.AreEqual('MCP: Sperre belegt', Events[1].Text);
  Assert.AreEqual('LSP: Index gespeichert', Events[2].Text);
  Assert.AreEqual('MCP: neuen Stand übernommen', Events[3].Text);
  // Zwei LSP-Prozesse: mit Prozessnummer.
  Events := TIndexProcessLog.Events([Lsp, Info(3, TIndexProcessInfo.KindLsp), Mcp]);
  Assert.AreEqual('LSP 1: Cache-Sperre erhalten', Events[0].Text);
end;

procedure TIndexProcessInfoTests.JsonRoundTrip;
var
  Source, Copy: TIndexProcessInfo;
  Json: string;
  Event: TIndexProcessEvent;
  Value: TJSONObject;
begin
  Source := Info(42, TIndexProcessInfo.KindMcp);
  Source.State := TIndexProcessInfo.StateReady;
  Source.Writer := True;
  Source.Started := EncodeDateTime(2026, 10, 21, 9, 0, 0, 0);
  Event.Time := Source.Started;
  Event.Text := 'bereit';
  Source.Events := [Event];
  Value := Source.ToJson;
  try
    Json := Value.ToJSON;
  finally
    Value.Free;
  end;
  Assert.IsTrue(TIndexProcessInfo.FromJson(Json, Copy));
  Assert.AreEqual(Cardinal(42), Copy.Pid);
  Assert.IsTrue(Copy.Writer);
  Assert.AreEqual('Claude Code', Copy.Client);
  Assert.AreEqual(Source.Started, Copy.Started, 1 / SecsPerDay);
  Assert.AreEqual('bereit', Copy.Events[0].Text);
  Assert.IsFalse(TIndexProcessInfo.FromJson('{"pid":', Copy));
  Assert.IsFalse(TIndexProcessInfo.FromJson('{"kind":"LSP"}', Copy));
end;

initialization
  TDUnitX.RegisterTestFixture(TIndexProcessInfoTests);

end.
