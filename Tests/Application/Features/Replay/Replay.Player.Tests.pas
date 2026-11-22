unit Replay.Player.Tests;

// Tests für TReplayPlayer (#1355): Nachstellen eines Falls gegen einen
// Testserver; reproduziert nur bei derselben Ausnahmeklasse bzw. beim
// Watchdog-Fall bei RequestCancelled.

interface

uses
  System.SysUtils,
  System.JSON,
  DUnitX.TestFramework,
  Atlas.Common.Diagnostics.CrashCase,
  Replay.Player;

type
  [TestFixture]
  TReplayPlayerTests = class
  private
    function SampleCase: TCrashCase;
    /// <summary>Testserver: beantwortet die Anfrage mit AError (Code, Text) bzw. ohne Fehler bei ACode = 0.
    /// </summary>
    function FakeServer(ACode: Integer; const AText: string; out AMethods: TFunc<string>): TReplayServer;
  public
    [Test]
    procedure ReproducesSameExceptionClass;
    [Test]
    procedure OtherClassIsNotReproduced;
    [Test]
    procedure TimeoutCaseNeedsCancelled;
    [Test]
    procedure ExitCodes;
    [Test]
    procedure IsolatedRunSendsSnapshotAndRequest;
    [Test]
    procedure UnreadableFileGivesExitCode2;
    /// <summary>Ohne eingespielte Anfrage hat der Transport keine Antwort.</summary>
    [Test]
    procedure TransportWithoutRequestHasNoAnswer;
  end;

implementation

uses
  System.IOUtils,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.Messages,
  Atlas.Common.Logging.Contract,
  Atlas.Common.Logging.Providers.Logger,
  Replay.Providers.Transport,
  Replay.Contract;

/// <summary>Logger ohne Senke: Meldungen des Servers gehen verloren.</summary>
function SilentLogger: ILogger;
begin
  Result := TLogger.Create;
end;

{ TReplayPlayerTests }

function TReplayPlayerTests.SampleCase: TCrashCase;
begin
  Result := TCrashCase.Empty;
  Result.Method := 'textDocument/hover';
  Result.Id := '7';
  Result.Uri := 'file:///C:/Gibts/Nicht/Demo.pas';
  Result.FileName := 'C:\Gibts\Nicht\Demo.pas';
  Result.Params := '{"textDocument":{"uri":"' + Result.Uri + '"},"position":{"line":0,"character":1}}';
  Result.Line := 0;
  Result.Text := 'unit Demo;';
  Result.HasText := True;
  Result.ExceptionClass := 'ECrashTest';
end;

function ErrorResponse(ACode: Integer; const AText: string): TJSONObject;
var
  mError: TJSONObject;
begin
  Result := TJSONObject.Create;
  mError := TJSONObject.Create;
  mError.AddPair('code', TJSONNumber.Create(ACode));
  mError.AddPair('message', AText);
  Result.AddPair('error', mError);
end;

/// <summary>Antwort des Testservers auf die Anfrage AMessage: zu textDocument/hover der Fehler ACode mit AText
/// (außer ACode = 0), sonst ein leeres Ergebnis.</summary>
function FakeAnswer(AMessage: TJSONObject; const AMethod: string; ACode: Integer; const AText: string): TJSONObject;
begin
  if (AMethod = 'textDocument/hover') and (ACode <> 0) then
  begin
    Result := ErrorResponse(ACode, AText);
  end
  else
  begin
    Result := TJSONObject.Create;
    Result.AddPair('result', TJSONNull.Create);
  end;
  Result.AddPair('jsonrpc', TJsonRpcMessages.cVersion);
  Result.AddPair('id', TJSONValue(AMessage.GetValue('id').Clone));
end;

function TReplayPlayerTests.FakeServer(ACode: Integer; const AText: string; out AMethods: TFunc<string>): TReplayServer;
var
  mSeen: string;
begin
  mSeen := '';
  AMethods :=
    function: string
    begin
      Result := mSeen;
    end;
  Result :=
    procedure(const ATransport: IJsonRpcTransport; const ALogger: ILogger; const ASettingsFile: string)
    var
      mMessage, mAnswer: TJSONObject;
      mMethod: string;
    begin
      while True do
      begin
        try
          mMessage := ATransport.ReadMessage;
        except
          on EJsonRpcTransportClosed do
            Exit;
        end;
        try
          mMethod := mMessage.GetValue<string>('method', '');
          mSeen := mSeen + mMethod + ';';
          if mMessage.GetValue('id') <> nil then
          begin
            mAnswer := FakeAnswer(mMessage, mMethod, ACode, AText);
            try
              ATransport.WriteMessage(mAnswer);
            finally
              mAnswer.Free;
            end;
          end;
          if mMethod = 'exit' then
          begin
            Exit;
          end;
        finally
          mMessage.Free;
        end;
      end;
    end;
end;

procedure TReplayPlayerTests.ReproducesSameExceptionClass;
var
  mResponse: TJSONObject;
  mDetail: string;
begin
  mResponse := ErrorResponse(TJsonRpcErrorCode.cInternalError, 'ECrashTest: künstlich');
  try
    Assert.IsTrue(TReplayPlayer.Reproduces(SampleCase, mResponse, mDetail));
    Assert.IsTrue(mDetail.Contains('künstlich'));
  finally
    mResponse.Free;
  end;
end;

procedure TReplayPlayerTests.OtherClassIsNotReproduced;
var
  mResponse: TJSONObject;
  mDetail: string;
begin
  mResponse := ErrorResponse(TJsonRpcErrorCode.cInternalError, 'EAccessViolation: weg');
  try
    Assert.IsFalse(TReplayPlayer.Reproduces(SampleCase, mResponse, mDetail));
  finally
    mResponse.Free;
  end;
  mResponse := TJSONObject.Create;
  try
    mResponse.AddPair('result', TJSONNull.Create);
    Assert.IsFalse(TReplayPlayer.Reproduces(SampleCase, mResponse, mDetail));
  finally
    mResponse.Free;
  end;
  Assert.IsFalse(TReplayPlayer.Reproduces(SampleCase, nil, mDetail));
end;

procedure TReplayPlayerTests.TimeoutCaseNeedsCancelled;
var
  mCase: TCrashCase;
  mResponse: TJSONObject;
  mDetail: string;
begin
  mCase := SampleCase;
  mCase.Kind := TCrashCaseKind.Timeout;
  mResponse := ErrorResponse(TJsonRpcErrorCode.cRequestCancelled, 'Zeitlimit');
  try
    Assert.IsTrue(TReplayPlayer.Reproduces(mCase, mResponse, mDetail));
  finally
    mResponse.Free;
  end;
end;

procedure TReplayPlayerTests.ExitCodes;
var
  mResult: TReplayResult;
begin
  mResult := Default(TReplayResult);
  mResult.Outcome := TReplayOutcome.Reproduced;
  Assert.AreEqual(TReplayPlayer.cExitReproduced, TReplayPlayer.ExitCodeOf(mResult));
  mResult.Outcome := TReplayOutcome.NotReproduced;
  Assert.AreEqual(TReplayPlayer.cExitNotReproduced, TReplayPlayer.ExitCodeOf(mResult));
  Assert.IsTrue(mResult.Text.StartsWith('nicht reproduziert'));
  mResult.Outcome := TReplayOutcome.Unreadable;
  Assert.AreEqual(TReplayPlayer.cExitUnreadable, TReplayPlayer.ExitCodeOf(mResult));
end;

procedure TReplayPlayerTests.IsolatedRunSendsSnapshotAndRequest;
var
  mMethods: TFunc<string>;
  mResult: TReplayResult;
begin
  mResult := TReplayPlayer.Run(SampleCase, TReplayPlace.Isolated, SilentLogger,
    FakeServer(TJsonRpcErrorCode.cInternalError, 'ECrashTest: künstlich', mMethods), TReplayTransport.Factory);
  Assert.AreEqual<TReplayOutcome>(TReplayOutcome.Reproduced, mResult.Outcome, mResult.Text);
  Assert.IsFalse(mResult.Original);
  Assert.AreEqual('initialize;initialized;textDocument/didOpen;textDocument/hover;shutdown;exit;', mMethods());
  mResult := TReplayPlayer.Run(SampleCase, TReplayPlace.Isolated, SilentLogger, FakeServer(0, '', mMethods),
    TReplayTransport.Factory);
  Assert.AreEqual<TReplayOutcome>(TReplayOutcome.NotReproduced, mResult.Outcome, mResult.Text);
end;

procedure TReplayPlayerTests.UnreadableFileGivesExitCode2;
var
  mMethods: TFunc<string>;
  mResult: TReplayResult;
begin
  mResult := TReplayPlayer.Run(TPath.Combine(TPath.GetTempPath, 'gibts-nicht-' + TGUID.NewGuid.ToString + '.json'),
    SilentLogger, FakeServer(0, '', mMethods), TReplayTransport.Factory);
  Assert.AreEqual(TReplayPlayer.cExitUnreadable, TReplayPlayer.ExitCodeOf(mResult));
end;

procedure TReplayPlayerTests.TransportWithoutRequestHasNoAnswer;
var
  mTransport: IReplayTransport;
begin
  mTransport := TReplayTransport.Factory()(nil, 0, 10);
  Assert.IsNull(mTransport.TakeAnswer);
end;

initialization
  TDUnitX.RegisterTestFixture(TReplayPlayerTests);

end.
