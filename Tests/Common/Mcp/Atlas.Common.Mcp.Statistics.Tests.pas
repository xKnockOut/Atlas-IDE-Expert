unit Atlas.Common.Mcp.Statistics.Tests;

// Tests für die Aufrufstatistik des MCP-Servers (#2611): Zählung, Median, Fehlerquote, Kennzeichnung der
// Argumente, JSON und die Zählung über den Verteiler (tools/call, resources/read, prompts/get).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMcpStatisticsTests = class
  public
    [Test]
    procedure CountsCallsErrorsDurationAndSize;
    [Test]
    procedure MedianOfOddAndEvenCounts;
    [Test]
    procedure ErrorRateIsConspicuousFromFiveCalls;
    [Test]
    procedure KnownToolsAppearWithoutCalls;
    [Test]
    procedure FailedCallKeepsMarkedArguments;
    [Test]
    procedure LongArgumentsAreCut;
    [Test]
    procedure SnapshotSurvivesJson;
    [Test]
    procedure ServerCountsToolCalls;
    [Test]
    procedure ServerCountsResourcesUnderTemplate;
    [Test]
    procedure ServerWithoutStatisticsCountsNothing;
  end;

implementation

uses
  System.SysUtils,
  System.DateUtils,
  System.JSON,
  Atlas.Text.LogMarks,
  Atlas.Text.McpStatistics,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Mcp.Server,
  Atlas.Common.Mcp.Statistics;

const
  cNow: TDateTime = 46324.5;

function CallOf(const AName: string; AFailed: Boolean; AMs, ABytes: Int64): TMcpCall;
begin
  Result := Default(TMcpCall);
  Result.Kind := TMcpCallKind.Tool;
  Result.Name := AName;
  Result.Failed := AFailed;
  Result.ElapsedMs := AMs;
  Result.Bytes := ABytes;
end;

function Find(const AStats: TMcpSessionStatistics; const AName: string): TMcpCallSummary;
var
  mCall: TMcpCallSummary;
begin
  for mCall in AStats.Calls do
  begin
    if mCall.Name = AName then
    begin
      Exit(mCall);
    end;
  end;
  Result := Default(TMcpCallSummary);
end;

function NewServer(AStatistics: TMcpStatistics): TMcpServer;
begin
  Result := TMcpServer.Create('Atlas', '1.0');
  Result.Statistics := AStatistics;
  Result.AddTool('echo', 'Gibt den Text zurück', TMcpArgs.StringSchema(['text'], ['Text']),
    function(const AArguments: TJSONObject): string
    begin
      Result := 'Echo: ' + TMcpArgs.RequiredString(AArguments, 'text');
    end);
  Result.AddTool('nie', 'Wird nie aufgerufen', TMcpArgs.StringSchema([], []),
    function(const AArguments: TJSONObject): string
    begin
      Result := '';
    end);
  Result.AddResource('delphi://stats', 'stats', 'Statistik', 'text/markdown',
    function: string
    begin
      Result := 'Zahlen';
    end);
  Result.AddResourceTemplate('delphi://unit/{name}', 'unit', 'Unit', 'text/markdown',
    function(const AValue: string): string
    begin
      Result := 'Unit ' + AValue;
    end);
end;

/// <summary>Schickt AJson als Anfrage an ADispatcher und gibt die Antwort frei.</summary>
procedure Send(ADispatcher: TJsonRpcDispatcher; const AJson: string);
var
  mMessage: TJSONObject;
begin
  mMessage := TJSONObject(TJSONObject.ParseJSONValue(AJson));
  try
    ADispatcher.DispatchMessage(mMessage).Free;
  finally
    mMessage.Free;
  end;
end;

{ TMcpStatisticsTests }

procedure TMcpStatisticsTests.CountsCallsErrorsDurationAndSize;
var
  mStatistics: TMcpStatistics;
  mCall: TMcpCallSummary;
begin
  mStatistics := TMcpStatistics.Create('C:\App', cNow);
  try
    mStatistics.Add(CallOf('find_symbol', False, 40, 2000), cNow);
    mStatistics.Add(CallOf('find_symbol', True, 10, 100), cNow);
    mStatistics.Add(CallOf('find_symbol', False, 900, 500), cNow);
    mCall := Find(mStatistics.Snapshot, 'find_symbol');
  finally
    mStatistics.Free;
  end;
  Assert.AreEqual(3, mCall.Calls);
  Assert.AreEqual(1, mCall.Errors);
  Assert.AreEqual(Int64(40), mCall.MedianMs);
  Assert.AreEqual(Int64(900), mCall.MaxMs);
  Assert.AreEqual(Int64(500), mCall.MedianBytes);
  Assert.AreEqual(Int64(2000), mCall.MaxBytes);
  Assert.AreEqual(33, mCall.ErrorPercent);
end;

procedure TMcpStatisticsTests.MedianOfOddAndEvenCounts;
begin
  Assert.AreEqual(Int64(0), TMcpStatistics.Median(nil));
  Assert.AreEqual(Int64(5), TMcpStatistics.Median(TArray<Int64>.Create(9, 1, 5)));
  Assert.AreEqual(Int64(4), TMcpStatistics.Median(TArray<Int64>.Create(9, 1, 3, 5)), 'Mittel der beiden mittleren');
end;

procedure TMcpStatisticsTests.ErrorRateIsConspicuousFromFiveCalls;
var
  mCall: TMcpCallSummary;
begin
  mCall := Default(TMcpCallSummary);
  mCall.Calls := 4;
  mCall.Errors := 4;
  Assert.IsFalse(mCall.Conspicuous, 'unter fünf Aufrufen nie auffällig');
  mCall.Calls := 5;
  mCall.Errors := 1;
  Assert.IsFalse(mCall.Conspicuous, 'genau 20 % ist nicht über der Schwelle');
  mCall.Calls := 41;
  mCall.Errors := 9;
  Assert.IsTrue(mCall.Conspicuous, '22 %');
  Assert.AreEqual(22, mCall.ErrorPercent);
end;

procedure TMcpStatisticsTests.KnownToolsAppearWithoutCalls;
var
  mStatistics: TMcpStatistics;
  mStats: TMcpSessionStatistics;
begin
  mStatistics := TMcpStatistics.Create('C:\App', cNow);
  try
    mStatistics.Know(TMcpCallKind.Tool, 'get_impact');
    mStatistics.Add(CallOf('find_symbol', False, 1, 1), cNow);
    mStats := mStatistics.Snapshot;
  finally
    mStatistics.Free;
  end;
  Assert.AreEqual(2, Integer(Length(mStats.Calls)));
  Assert.AreEqual('find_symbol', mStats.Calls[0].Name, 'nach Aufrufen absteigend');
  Assert.AreEqual('get_impact', mStats.Calls[1].Name);
  Assert.AreEqual(0, mStats.Calls[1].Calls);
end;

procedure TMcpStatisticsTests.FailedCallKeepsMarkedArguments;
var
  mStatistics: TMcpStatistics;
  mCall: TMcpCall;
  mArguments: TJSONObject;
  mSummary: TMcpCallSummary;
begin
  mArguments := TJSONObject.Create;
  mStatistics := TMcpStatistics.Create('C:\App', cNow);
  try
    mArguments.AddPair('file', 'C:\App\Run.pas');
    mArguments.AddPair('text', 'begin end.');
    mArguments.AddPair('line', TJSONNumber.Create(12));
    mCall := CallOf('check_code', True, 1200, 4000);
    mCall.Arguments := mArguments;
    mCall.Message := 'Datei C:\App\Run.pas fehlt';
    mStatistics.Add(mCall, cNow);
    mSummary := Find(mStatistics.Snapshot, 'check_code');
  finally
    mStatistics.Free;
    mArguments.Free;
  end;
  Assert.AreEqual(DateToISO8601(cNow), DateToISO8601(mSummary.LastFailed.At));
  Assert.AreEqual('file="' + TLogMarks.Path('C:\App\Run.pas') + '" text="' + TLogMarks.Text('begin end.') +
    '" line=12', mSummary.LastFailed.Arguments, 'Pfad und Quelltext gekennzeichnet, Zahlen bleiben');
  Assert.AreEqual(TLogMarks.Text('Datei C:\App\Run.pas fehlt'), mSummary.LastFailed.Message);
end;

procedure TMcpStatisticsTests.LongArgumentsAreCut;
var
  mArguments: TJSONObject;
  mText: string;
begin
  mArguments := TJSONObject.Create;
  try
    mArguments.AddPair('text', StringOfChar('x', 2000));
    mText := TLogMarks.Plain(TMcpStatistics.MarkedArguments(mArguments));
  finally
    mArguments.Free;
  end;
  Assert.AreEqual('text="' + StringOfChar('x', TMcpStatistics.cMaxArgumentChars) + '"', mText);
end;

procedure TMcpStatisticsTests.SnapshotSurvivesJson;
var
  mStatistics: TMcpStatistics;
  mJson: TJSONObject;
  mStats, mRead: TMcpSessionStatistics;
begin
  mStatistics := TMcpStatistics.Create('C:\App', cNow);
  try
    mStatistics.SetClient('Assistent A');
    mStatistics.Add(CallOf('find_symbol', True, 40, 2048), cNow);
    mStats := mStatistics.Snapshot;
  finally
    mStatistics.Free;
  end;
  mJson := mStats.ToJson;
  try
    mRead := TMcpSessionStatistics.FromJson(mJson);
  finally
    mJson.Free;
  end;
  Assert.AreEqual('Assistent A', mRead.Client);
  Assert.AreEqual('C:\App', mRead.Project);
  Assert.IsTrue(Abs(mRead.Started - cNow) < 1 / 86400);
  Assert.AreEqual(1, Integer(Length(mRead.Calls)));
  Assert.AreEqual(1, mRead.Calls[0].Errors);
  Assert.AreEqual(Int64(2048), mRead.Calls[0].MaxBytes);
  Assert.IsTrue(Abs(mRead.Calls[0].LastFailed.At - cNow) < 1 / 86400);
end;

procedure TMcpStatisticsTests.ServerCountsToolCalls;
var
  mServer: TMcpServer;
  mDispatcher: TJsonRpcDispatcher;
  mStatistics: TMcpStatistics;
  mStats: TMcpSessionStatistics;
begin
  mStatistics := TMcpStatistics.Create('C:\App', cNow);
  mServer := NewServer(mStatistics);
  mDispatcher := TJsonRpcDispatcher.Create;
  try
    mServer.Attach(mDispatcher);
    Send(mDispatcher, '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"echo","arguments":' +
      '{"text":"a"}}}');
    Send(mDispatcher, '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"echo","arguments":{}}}');
    Send(mDispatcher, '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"gibtsnicht"}}');
    mStats := mStatistics.Snapshot;
  finally
    mDispatcher.Free;
    mServer.Free;
    mStatistics.Free;
  end;
  Assert.AreEqual(2, Find(mStats, 'echo').Calls);
  Assert.AreEqual(1, Find(mStats, 'echo').Errors, 'isError zählt als Fehler');
  Assert.IsTrue(Find(mStats, 'echo').MaxBytes > 0, 'Antwortgröße');
  Assert.IsTrue(Find(mStats, 'echo').LastFailed.Message.Contains('text'), 'Meldung des Werkzeugs');
  Assert.AreEqual('nie', Find(mStats, 'nie').Name, 'angebotenes Werkzeug ohne Aufruf');
  Assert.AreEqual('', Find(mStats, 'gibtsnicht').Name, 'unbekannte Werkzeuge nicht zählen');
end;

procedure TMcpStatisticsTests.ServerCountsResourcesUnderTemplate;
var
  mServer: TMcpServer;
  mDispatcher: TJsonRpcDispatcher;
  mStatistics: TMcpStatistics;
  mStats: TMcpSessionStatistics;
begin
  mStatistics := TMcpStatistics.Create('C:\App', cNow);
  mServer := NewServer(mStatistics);
  mDispatcher := TJsonRpcDispatcher.Create;
  try
    mServer.Attach(mDispatcher);
    Send(mDispatcher, '{"jsonrpc":"2.0","id":1,"method":"resources/read","params":{"uri":"delphi://unit/A"}}');
    Send(mDispatcher, '{"jsonrpc":"2.0","id":2,"method":"resources/read","params":{"uri":"delphi://unit/B"}}');
    Send(mDispatcher, '{"jsonrpc":"2.0","id":3,"method":"resources/read","params":{"uri":"delphi://stats"}}');
    Send(mDispatcher, '{"jsonrpc":"2.0","id":4,"method":"prompts/get","params":{"name":"fehlt"}}');
    mStats := mStatistics.Snapshot;
  finally
    mDispatcher.Free;
    mServer.Free;
    mStatistics.Free;
  end;
  Assert.AreEqual(2, Find(mStats, 'delphi://unit/{name}').Calls, 'Vorlage statt einzelner Units');
  Assert.AreEqual<TMcpCallKind>(TMcpCallKind.Resource, Find(mStats, 'delphi://unit/{name}').Kind);
  Assert.AreEqual(1, Find(mStats, 'delphi://stats').Calls);
  Assert.AreEqual(1, Find(mStats, 'fehlt').Errors, 'Ausnahme zählt als Fehler');
  Assert.AreEqual<TMcpCallKind>(TMcpCallKind.Prompt, Find(mStats, 'fehlt').Kind);
end;

procedure TMcpStatisticsTests.ServerWithoutStatisticsCountsNothing;
var
  mServer: TMcpServer;
  mDispatcher: TJsonRpcDispatcher;
begin
  mServer := NewServer(nil);
  mDispatcher := TJsonRpcDispatcher.Create;
  try
    mServer.Attach(mDispatcher);
    Send(mDispatcher, '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"echo","arguments":' +
      '{"text":"a"}}}');
    Assert.IsNull(mServer.Statistics);
  finally
    mDispatcher.Free;
    mServer.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TMcpStatisticsTests);

end.
