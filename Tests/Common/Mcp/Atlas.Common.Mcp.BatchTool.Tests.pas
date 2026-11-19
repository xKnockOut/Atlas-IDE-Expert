unit Atlas.Common.Mcp.BatchTool.Tests;

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Mcp.Server,
  Atlas.Common.Mcp.BatchTool;

type
  [TestFixture]
  TMcpBatchToolTests = class
  private
    FServer: TMcpServer;
    FChecks: Integer;
    FCancelAfter: Integer;
    FCalls: Integer;
    FTimeoutMs: Integer;
    function CallText(const AJson: string; out AIsError: Boolean): string;
    function Limits: TMcpBatchLimits;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure RunsReadToolsWithOneFreshnessCheck;
    [Test]
    procedure AnswersAreTheSameAsSingleCalls;
    [Test]
    procedure RefusesWriteProcessBatchAndDisabledPerSection;
    [Test]
    procedure ErrorAffectsOnlyItsSection;
    [Test]
    procedure MoreThanTenCallsIsAToolError;
    [Test]
    procedure MissingCallsIsAToolError;
    [Test]
    procedure CancelKeepsFinishedSections;
    [Test]
    procedure TimeLimitKeepsFinishedSections;
    [Test]
    procedure ShortensLongSectionsAndMarksThem;
    [Test]
    procedure JsonListsToolOkResultAndError;
  end;

implementation

uses
  System.SysUtils,
  System.JSON;

function EchoTool: TMcpToolHandler;
begin
  Result :=
    function(const AArguments: TJSONObject): string
    begin
      Result := 'Echo ' + TMcpArgs.OptionalString(AArguments, 'name');
    end;
end;

function FailingTool: TMcpToolHandler;
begin
  Result :=
    function(const AArguments: TJSONObject): string
    begin
      raise EMcpToolError.Create('Symbol fehlt');
    end;
end;

function CrashingTool: TMcpToolHandler;
begin
  Result :=
    function(const AArguments: TJSONObject): string
    begin
      raise EArgumentException.Create('Absturz');
    end;
end;

function SlowTool: TMcpToolHandler;
begin
  Result :=
    function(const AArguments: TJSONObject): string
    begin
      Sleep(30);
      Result := 'langsam';
    end;
end;

function DisabledOf: TFunc<TArray<string>>;
begin
  Result :=
    function: TArray<string>
    begin
      Result := TArray<string>.Create('abgeschaltet');
    end;
end;

{ TMcpBatchToolTests }

procedure TMcpBatchToolTests.Setup;
begin
  FChecks := 0;
  FCalls := 0;
  FCancelAfter := -1;
  FTimeoutMs := 0;
  FServer := TMcpServer.Create('Atlas', '1');
  FServer.AddTool('echo', 'Echo', '{"type":"object"}',
    function(const AArguments: TJSONObject): string
    begin
      Inc(FCalls);
      Result := EchoTool()(AArguments);
    end);
  FServer.AddTool('fehler', 'Fehler', '{"type":"object"}', FailingTool());
  FServer.AddTool('absturz', 'Absturz', '{"type":"object"}', CrashingTool());
  FServer.AddTool('langsam', 'Langsam', '{"type":"object"}', SlowTool());
  FServer.AddTool('abgeschaltet', 'Aus', '{"type":"object"}', EchoTool());
  FServer.AddTool('schreiben', 'Schreibt', '{"type":"object"}', EchoTool(), TMcpToolKind.Write);
  FServer.AddTool('bauen', 'Baut', '{"type":"object"}', EchoTool(), TMcpToolKind.Process);
  FServer.OnDisabledTools := DisabledOf();
  FServer.OnBeforeToolCall :=
    procedure
    begin
      Inc(FChecks);
    end;
  TMcpBatchTool.Register(FServer,
    function: TMcpBatchLimits
    begin
      Result := Limits;
    end);
end;

procedure TMcpBatchToolTests.TearDown;
begin
  FreeAndNil(FServer);
end;

function TMcpBatchToolTests.Limits: TMcpBatchLimits;
begin
  Result := Default(TMcpBatchLimits);
  Result.TimeoutMs := FTimeoutMs;
  Result.Cancelled :=
    function: Boolean
    begin
      Result := (FCancelAfter >= 0) and (FCalls >= FCancelAfter);
    end;
end;

function TMcpBatchToolTests.CallText(const AJson: string; out AIsError: Boolean): string;
var
  mParams: TJSONValue;
  mResult: TJSONObject;
begin
  mParams := TJSONObject.ParseJSONValue(AJson);
  try
    mResult := FServer.CallTool(mParams);
    try
      AIsError := mResult.GetValue<Boolean>('isError');
      Result := mResult.GetValue<TJSONArray>('content').Items[0].GetValue<string>('text');
    finally
      mResult.Free;
    end;
  finally
    mParams.Free;
  end;
end;

procedure TMcpBatchToolTests.RunsReadToolsWithOneFreshnessCheck;
var
  mText: string;
  mIsError: Boolean;
begin
  mText := CallText('{"name":"batch","arguments":{"calls":[{"tool":"echo","args":{"name":"A"}},' +
    '{"tool":"echo","args":{"name":"B"}},{"tool":"echo","args":{"name":"C"}}]}}', mIsError);
  Assert.IsFalse(mIsError);
  Assert.AreEqual(1, FChecks);
  Assert.Contains(mText, '3 Aufrufe');
  Assert.Contains(mText, '## 1 echo'#10'Echo A');
  Assert.Contains(mText, '## 3 echo'#10'Echo C');
end;

procedure TMcpBatchToolTests.AnswersAreTheSameAsSingleCalls;
var
  mSingle, mBatch: string;
  mIsError: Boolean;
begin
  mSingle := CallText('{"name":"echo","arguments":{"name":"X"}}', mIsError);
  mBatch := CallText('{"name":"batch","arguments":{"calls":[{"tool":"echo","args":{"name":"X"}}]}}', mIsError);
  Assert.Contains(mBatch, '## 1 echo'#10 + mSingle);
end;

procedure TMcpBatchToolTests.RefusesWriteProcessBatchAndDisabledPerSection;
var
  mText: string;
  mIsError: Boolean;
begin
  mText := CallText('{"name":"batch","arguments":{"calls":[{"tool":"schreiben"},{"tool":"bauen"},' +
    '{"tool":"batch","args":{"calls":[]}},{"tool":"abgeschaltet"},{"tool":"echo","args":{"name":"Z"}}]}}',
    mIsError);
  Assert.IsFalse(mIsError);
  Assert.Contains(mText, '## 1 schreiben'#10'Fehler: Werkzeug "schreiben" ist nicht lesend');
  Assert.Contains(mText, '## 2 bauen'#10'Fehler: Werkzeug "bauen" ist nicht lesend');
  Assert.Contains(mText, '## 3 batch'#10'Fehler: batch lässt sich nicht verschachteln.');
  Assert.Contains(mText, '## 4 abgeschaltet'#10'Fehler: Werkzeug "abgeschaltet" ist in atlas.json abgeschaltet');
  Assert.Contains(mText, '## 5 echo'#10'Echo Z');
end;

procedure TMcpBatchToolTests.ErrorAffectsOnlyItsSection;
var
  mText: string;
  mIsError: Boolean;
begin
  mText := CallText('{"name":"batch","arguments":{"calls":[{"tool":"fehler"},{"tool":"absturz"},' +
    '{"tool":"gibtesnicht"},{"args":{}},{"tool":"echo","args":{"name":"Y"}}]}}', mIsError);
  Assert.IsFalse(mIsError);
  Assert.Contains(mText, '## 1 fehler'#10'Fehler: Symbol fehlt');
  Assert.Contains(mText, '## 2 absturz'#10'Fehler: Absturz');
  Assert.Contains(mText, '## 3 gibtesnicht'#10'Fehler: Werkzeug "gibtesnicht" gibt es in diesem Server nicht.');
  Assert.Contains(mText, 'Fehler: Aufruf ohne "tool"');
  Assert.Contains(mText, '## 5 echo'#10'Echo Y');
end;

procedure TMcpBatchToolTests.MoreThanTenCallsIsAToolError;
var
  mText, mCalls: string;
  mIndex: Integer;
  mIsError: Boolean;
begin
  mCalls := '';
  for mIndex := 1 to 11 do
  begin
    if mCalls <> '' then
    begin
      mCalls := mCalls + ',';
    end;
    mCalls := mCalls + '{"tool":"echo"}';
  end;
  mText := CallText('{"name":"batch","arguments":{"calls":[' + mCalls + ']}}', mIsError);
  Assert.IsTrue(mIsError);
  Assert.Contains(mText, 'Höchstens 10 Aufrufe');
  Assert.AreEqual(0, FCalls);
end;

procedure TMcpBatchToolTests.MissingCallsIsAToolError;
var
  mText: string;
  mIsError: Boolean;
begin
  mText := CallText('{"name":"batch","arguments":{"calls":[]}}', mIsError);
  Assert.IsTrue(mIsError);
  Assert.Contains(mText, '"calls" fehlt');
end;

procedure TMcpBatchToolTests.CancelKeepsFinishedSections;
var
  mText: string;
  mIsError: Boolean;
begin
  FCancelAfter := 1;
  mText := CallText('{"name":"batch","arguments":{"calls":[{"tool":"echo","args":{"name":"A"}},' +
    '{"tool":"echo","args":{"name":"B"}}]}}', mIsError);
  Assert.IsFalse(mIsError);
  Assert.Contains(mText, '## 1 echo'#10'Echo A');
  Assert.Contains(mText, '## 2 echo'#10'nicht ausgeführt: abgebrochen');
  Assert.AreEqual(1, FCalls);
end;

procedure TMcpBatchToolTests.TimeLimitKeepsFinishedSections;
var
  mText: string;
  mIsError: Boolean;
begin
  FTimeoutMs := 10;
  mText := CallText('{"name":"batch","arguments":{"calls":[{"tool":"langsam"},' +
    '{"tool":"echo","args":{"name":"B"}}]}}', mIsError);
  Assert.Contains(mText, '## 1 langsam'#10'langsam');
  Assert.Contains(mText, '## 2 echo'#10'nicht ausgeführt: Zeitlimit von 10 ms erreicht');
end;

procedure TMcpBatchToolTests.ShortensLongSectionsAndMarksThem;
var
  mParts: TArray<TMcpBatchPart>;
begin
  SetLength(mParts, 3);
  mParts[0].Text := StringOfChar('a', 10);
  mParts[1].Text := StringOfChar('b', 200);
  mParts[2].Text := StringOfChar('c', 100);
  TMcpBatchTool.Shorten(mParts, 100);
  Assert.AreEqual(StringOfChar('a', 10), mParts[0].Text);
  Assert.AreEqual(0, mParts[0].OriginalLength);
  Assert.AreEqual(200, mParts[1].OriginalLength);
  Assert.AreEqual(100, mParts[2].OriginalLength);
  Assert.IsTrue(mParts[1].Text.StartsWith(StringOfChar('b', 45) + #10 + '… gekürzt auf 45 von 200 Zeichen'));
  Assert.IsTrue(mParts[2].Text.StartsWith(StringOfChar('c', 45) + #10 + '… gekürzt auf 45 von 100 Zeichen'));
  mParts := nil;
end;

procedure TMcpBatchToolTests.JsonListsToolOkResultAndError;
var
  mText: string;
  mIsError: Boolean;
  mValue: TJSONValue;
  mCalls: TJSONArray;
begin
  mText := CallText('{"name":"batch","arguments":{"format":"json","calls":[{"tool":"echo","args":{"name":"A"}},' +
    '{"tool":"fehler"}]}}', mIsError);
  mValue := TJSONObject.ParseJSONValue(mText);
  try
    Assert.AreEqual('json', mValue.GetValue<string>('format'));
    mCalls := mValue.GetValue<TJSONArray>('calls');
    Assert.AreEqual(2, mCalls.Count);
    Assert.AreEqual('echo', mCalls.Items[0].GetValue<string>('tool'));
    Assert.IsTrue(mCalls.Items[0].GetValue<Boolean>('ok'));
    Assert.AreEqual('Echo A', mCalls.Items[0].GetValue<string>('result'));
    Assert.IsFalse(mCalls.Items[1].GetValue<Boolean>('ok'));
    Assert.AreEqual('Symbol fehlt', mCalls.Items[1].GetValue<string>('error'));
  finally
    mValue.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TMcpBatchToolTests);

end.
