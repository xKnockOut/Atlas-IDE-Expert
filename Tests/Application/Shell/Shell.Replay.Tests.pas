unit Shell.Replay.Tests;

// Tests für TShellReplay (#1355): Nachstellen eines Falls gegen einen
// Testserver; reproduziert nur bei derselben Ausnahmeklasse bzw. beim
// Watchdog-Fall bei RequestCancelled.

interface

uses
  System.SysUtils,
  System.JSON,
  DUnitX.TestFramework,
  Atlas.Common.Diagnostics.CrashCase,
  Shell.Replay;

type
  [TestFixture]
  TShellReplayTests = class
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
  end;

implementation

uses
  System.IOUtils,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.Messages,
  Atlas.Common.Logging.Contract;

function TShellReplayTests.SampleCase: TCrashCase;
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

function TShellReplayTests.FakeServer(ACode: Integer; const AText: string; out AMethods: TFunc<string>): TReplayServer;
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
            if (mMethod = 'textDocument/hover') and (ACode <> 0) then
              mAnswer := ErrorResponse(ACode, AText)
            else
            begin
              mAnswer := TJSONObject.Create;
              mAnswer.AddPair('result', TJSONNull.Create);
            end;
            try
              mAnswer.AddPair('jsonrpc', TJsonRpcMessages.Version);
              mAnswer.AddPair('id', TJSONValue(mMessage.GetValue('id').Clone));
              ATransport.WriteMessage(mAnswer);
            finally
              mAnswer.Free;
            end;
          end;
          if mMethod = 'exit' then
            Exit;
        finally
          mMessage.Free;
        end;
      end;
    end;
end;

procedure TShellReplayTests.ReproducesSameExceptionClass;
var
  mResponse: TJSONObject;
  mDetail: string;
begin
  mResponse := ErrorResponse(TJsonRpcErrorCode.InternalError, 'ECrashTest: künstlich');
  try
    Assert.IsTrue(TShellReplay.Reproduces(SampleCase, mResponse, mDetail));
    Assert.IsTrue(mDetail.Contains('künstlich'));
  finally
    mResponse.Free;
  end;
end;

procedure TShellReplayTests.OtherClassIsNotReproduced;
var
  mResponse: TJSONObject;
  mDetail: string;
begin
  mResponse := ErrorResponse(TJsonRpcErrorCode.InternalError, 'EAccessViolation: weg');
  try
    Assert.IsFalse(TShellReplay.Reproduces(SampleCase, mResponse, mDetail));
  finally
    mResponse.Free;
  end;
  mResponse := TJSONObject.Create;
  try
    mResponse.AddPair('result', TJSONNull.Create);
    Assert.IsFalse(TShellReplay.Reproduces(SampleCase, mResponse, mDetail));
  finally
    mResponse.Free;
  end;
  Assert.IsFalse(TShellReplay.Reproduces(SampleCase, nil, mDetail));
end;

procedure TShellReplayTests.TimeoutCaseNeedsCancelled;
var
  mCase: TCrashCase;
  mResponse: TJSONObject;
  mDetail: string;
begin
  mCase := SampleCase;
  mCase.Kind := TCrashCaseKind.Timeout;
  mResponse := ErrorResponse(TJsonRpcErrorCode.RequestCancelled, 'Zeitlimit');
  try
    Assert.IsTrue(TShellReplay.Reproduces(mCase, mResponse, mDetail));
  finally
    mResponse.Free;
  end;
end;

procedure TShellReplayTests.ExitCodes;
var
  mResult: TReplayResult;
begin
  mResult := Default(TReplayResult);
  mResult.Outcome := TReplayOutcome.Reproduced;
  Assert.AreEqual(TShellReplay.ExitReproduced, TShellReplay.ExitCodeOf(mResult));
  mResult.Outcome := TReplayOutcome.NotReproduced;
  Assert.AreEqual(TShellReplay.ExitNotReproduced, TShellReplay.ExitCodeOf(mResult));
  Assert.IsTrue(mResult.Text.StartsWith('nicht reproduziert'));
  mResult.Outcome := TReplayOutcome.Unreadable;
  Assert.AreEqual(TShellReplay.ExitUnreadable, TShellReplay.ExitCodeOf(mResult));
end;

procedure TShellReplayTests.IsolatedRunSendsSnapshotAndRequest;
var
  mMethods: TFunc<string>;
  mResult: TReplayResult;
begin
  mResult := TShellReplay.Run(SampleCase, TReplayPlace.Isolated, nil,
    FakeServer(TJsonRpcErrorCode.InternalError, 'ECrashTest: künstlich', mMethods));
  Assert.IsTrue(mResult.Outcome = TReplayOutcome.Reproduced, mResult.Text);
  Assert.IsFalse(mResult.Original);
  Assert.AreEqual('initialize;initialized;textDocument/didOpen;textDocument/hover;shutdown;exit;', mMethods());
  mResult := TShellReplay.Run(SampleCase, TReplayPlace.Isolated, nil, FakeServer(0, '', mMethods));
  Assert.IsTrue(mResult.Outcome = TReplayOutcome.NotReproduced, mResult.Text);
end;

procedure TShellReplayTests.UnreadableFileGivesExitCode2;
var
  mMethods: TFunc<string>;
  mResult: TReplayResult;
begin
  mResult := TShellReplay.Run(TPath.Combine(TPath.GetTempPath, 'gibts-nicht-' + TGUID.NewGuid.ToString + '.json'),
    nil, FakeServer(0, '', mMethods));
  Assert.AreEqual(TShellReplay.ExitUnreadable, TShellReplay.ExitCodeOf(mResult));
end;

initialization
  TDUnitX.RegisterTestFixture(TShellReplayTests);

end.
