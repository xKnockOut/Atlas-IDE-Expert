unit Atlas.Core.Assistants.DebugInbox.Tests;

// Tests für den Eingang der Debug-Aufträge von KI-Assistenten (#1874) ohne IDE: Auftrag lesen, Antwort im Format,
// das der MCP-Server an den Client weitergibt.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Assistants')]
  TAtlasDebugInboxTests = class
  public
    [Test]
    procedure ReadsStartRequest;
    [Test]
    procedure ReadsStepAndEvaluate;
    [Test]
    procedure RejectsBrokenRequests;
    [Test]
    procedure WritesStoppedState;
    [Test]
    procedure WritesRunningStateWithoutDetails;
    [Test]
    procedure WritesBreakpointAndEvaluation;
    [Test]
    procedure WritesRefusal;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Core.DebugControl.Types,
  Atlas.Core.Assistants.DebugInbox;

function Texts: TAtlasDebugInboxTexts;
begin
  Result := Default(TAtlasDebugInboxTexts);
  Result.Unreadable := 'unlesbar';
  Result.UnknownCommand := 'unbekannt: %s';
end;

{ TAtlasDebugInboxTests }

procedure TAtlasDebugInboxTests.ReadsStartRequest;
var
  mRequest: TAtlasDebugRequest;
  mReason: string;
begin
  Assert.IsTrue(TAtlasDebugInbox.ParseRequest('{"command":"debug_start","client":"Agent","project":"C:\\P\\App.dproj",' +
    '"configuration":"Debug","platform":"Win64","test":"U.TFix.M","arguments":"-x","waitSeconds":3}', Texts,
    mRequest, mReason), mReason);
  Assert.AreEqual(Ord(TAtlasDebugCommand.Start), Ord(mRequest.Command));
  Assert.AreEqual('Agent', mRequest.Client);
  Assert.AreEqual('C:\P\App.dproj', mRequest.Launch.Project);
  Assert.AreEqual('Debug', mRequest.Launch.Configuration);
  Assert.AreEqual('Win64', mRequest.Launch.Platform);
  Assert.AreEqual('U.TFix.M', mRequest.Launch.Test);
  Assert.AreEqual('-x', mRequest.Launch.Arguments);
  Assert.AreEqual(3, mRequest.WaitSeconds);
end;

procedure TAtlasDebugInboxTests.ReadsStepAndEvaluate;
var
  mRequest: TAtlasDebugRequest;
  mReason: string;
begin
  Assert.IsTrue(TAtlasDebugInbox.ParseRequest('{"command":"debug_step","kind":"toLine","file":"C:\\P\\A.pas",' +
    '"line":12}', Texts, mRequest, mReason), mReason);
  Assert.AreEqual(Ord(TAtlasDebugControlStep.ToLine), Ord(mRequest.StepKind));
  Assert.AreEqual('C:\P\A.pas', mRequest.FileName);
  Assert.AreEqual(12, mRequest.Line);
  Assert.AreEqual(TAtlasDebugInbox.cDefaultWaitSeconds, mRequest.WaitSeconds, 'Vorgabe');
  Assert.IsTrue(TAtlasDebugInbox.ParseRequest('{"command":"debug_step","kind":"out"}', Texts, mRequest, mReason));
  Assert.AreEqual(Ord(TAtlasDebugControlStep.Return), Ord(mRequest.StepKind));
  Assert.IsTrue(TAtlasDebugInbox.ParseRequest('{"command":"debug_evaluate","expression":"A.Count",' +
    '"sideEffects":true}', Texts, mRequest, mReason), mReason);
  Assert.AreEqual('A.Count', mRequest.Expression);
  Assert.IsTrue(mRequest.SideEffects);
  Assert.IsTrue(TAtlasDebugInbox.ParseRequest('{"command":"debug_state"}', Texts, mRequest, mReason));
  Assert.AreEqual(TAtlasDebugInbox.cDefaultFrames, mRequest.Frames);
  Assert.IsTrue(mRequest.Locals);
  Assert.IsTrue(TAtlasDebugInbox.ParseRequest('{"command":"remove_breakpoint","all":true}', Texts, mRequest,
    mReason));
  Assert.IsTrue(mRequest.All);
end;

procedure TAtlasDebugInboxTests.RejectsBrokenRequests;
var
  mRequest: TAtlasDebugRequest;
  mReason: string;
begin
  Assert.IsFalse(TAtlasDebugInbox.ParseRequest('kaputt', Texts, mRequest, mReason));
  Assert.AreEqual('unlesbar', mReason);
  Assert.IsFalse(TAtlasDebugInbox.ParseRequest('{"command":"debug_dance"}', Texts, mRequest, mReason));
  Assert.AreEqual('unbekannt: debug_dance', mReason);
  Assert.IsFalse(TAtlasDebugInbox.ParseRequest('{"command":"debug_step","kind":"sideways"}', Texts, mRequest,
    mReason));
  Assert.IsNotEmpty(mReason);
end;

/// <summary>Angehalten an einer Exception mit zwei Rahmen, einer Variablen und einem Thread.</summary>
function StoppedState: TAtlasDebugControlState;
var
  mFrame: TAtlasDebugControlFrame;
  mVariable: TAtlasDebugControlVariable;
  mThread: TAtlasDebugControlThread;
begin
  Result := Default(TAtlasDebugControlState);
  Result.Phase := TAtlasDebugControlPhase.Stopped;
  Result.StopReason := 'exception';
  Result.ExceptionClass := 'EConvertError';
  Result.ExceptionMessage := '''x'' ist kein gültiger Integerwert';
  Result.FileName := 'C:\P\Main.pas';
  Result.Line := 42;
  mFrame := Default(TAtlasDebugControlFrame);
  mFrame.FileName := 'C:\P\Main.pas';
  mFrame.Line := 42;
  mFrame.Header := 'Main.TForm1.Parse(''x'')';
  mFrame.Own := True;
  SetLength(Result.Frames, 2);
  Result.Frames[0] := mFrame;
  mFrame.FileName := '';
  mFrame.Line := 0;
  mFrame.Header := 'System.SysUtils.StrToInt';
  mFrame.Own := False;
  Result.Frames[1] := mFrame;
  mVariable := Default(TAtlasDebugControlVariable);
  mVariable.Name := 'S';
  mVariable.TypeName := 'string';
  mVariable.Value := '''x''';
  SetLength(Result.Locals, 1);
  Result.Locals[0] := mVariable;
  mThread := Default(TAtlasDebugControlThread);
  mThread.Id := 1234;
  mThread.Name := 'Main';
  mThread.Current := True;
  SetLength(Result.Threads, 1);
  Result.Threads[0] := mThread;
end;

procedure TAtlasDebugInboxTests.WritesStoppedState;
var
  mJson: TJSONValue;
  mFrames: TJSONArray;
begin
  mJson := TJSONObject.ParseJSONValue(TAtlasDebugInbox.SuccessText(TAtlasDebugInbox.StateJson('S1', 'stopped',
    StoppedState)));
  try
    Assert.IsTrue(mJson.GetValue<Boolean>('ok'));
    Assert.AreEqual('S1', mJson.GetValue<string>('result.session'));
    Assert.AreEqual('stopped', mJson.GetValue<string>('result.state'));
    Assert.AreEqual('exception', mJson.GetValue<string>('result.stop.reason'));
    Assert.AreEqual('EConvertError', mJson.GetValue<string>('result.stop.exceptionClass'));
    Assert.AreEqual('C:\P\Main.pas', mJson.GetValue<string>('result.location.file'));
    Assert.AreEqual(42, mJson.GetValue<Integer>('result.location.line'));
    mFrames := mJson.GetValue<TJSONArray>('result.frames');
    Assert.AreEqual(2, mFrames.Count);
    Assert.IsTrue((mFrames.Items[0] as TJSONObject).GetValue<Boolean>('own'));
    Assert.IsFalse((mFrames.Items[1] as TJSONObject).GetValue<Boolean>('own'));
    mFrames := mJson.GetValue<TJSONArray>('result.locals');
    Assert.AreEqual('string', (mFrames.Items[0] as TJSONObject).GetValue<string>('type'));
    mFrames := mJson.GetValue<TJSONArray>('result.threads');
    Assert.AreEqual(1234, (mFrames.Items[0] as TJSONObject).GetValue<Integer>('id'));
  finally
    mJson.Free;
  end;
end;

procedure TAtlasDebugInboxTests.WritesRunningStateWithoutDetails;
var
  mResult: TJSONObject;
  mState: TAtlasDebugControlState;
begin
  mState := StoppedState;
  mState.Phase := TAtlasDebugControlPhase.Running;
  mResult := TAtlasDebugInbox.StateJson('S1', 'running', mState);
  try
    Assert.AreEqual('running', mResult.GetValue<string>('state'));
    Assert.IsNull(mResult.GetValue('stop'));
    Assert.IsNull(mResult.GetValue('frames'));
  finally
    mResult.Free;
  end;
end;

procedure TAtlasDebugInboxTests.WritesBreakpointAndEvaluation;
var
  mBreakpoint: TAtlasDebugControlBreakpoint;
  mResult: TJSONObject;
begin
  mBreakpoint := Default(TAtlasDebugControlBreakpoint);
  mBreakpoint.Id := 3;
  mBreakpoint.FileName := 'C:\P\Main.pas';
  mBreakpoint.Line := 7;
  mBreakpoint.Valid := False;
  mResult := TAtlasDebugInbox.BreakpointJson(mBreakpoint);
  try
    Assert.AreEqual(3, mResult.GetValue<Integer>('id'));
    Assert.IsFalse(mResult.GetValue<Boolean>('valid'));
    Assert.AreEqual(cAtlasDebugControlGroup, mResult.GetValue<string>('group'));
  finally
    mResult.Free;
  end;
  mResult := TAtlasDebugInbox.EvaluationJson('Liste.Count', '3', 'Integer');
  try
    Assert.AreEqual('3', mResult.GetValue<string>('value'));
    Assert.AreEqual('Integer', mResult.GetValue<string>('type'));
  finally
    mResult.Free;
  end;
  mResult := TAtlasDebugInbox.RemovedJson(2);
  try
    Assert.AreEqual(2, mResult.GetValue<Integer>('removed'));
  finally
    mResult.Free;
  end;
end;

procedure TAtlasDebugInboxTests.WritesRefusal;
var
  mJson: TJSONValue;
begin
  mJson := TJSONObject.ParseJSONValue(TAtlasDebugInbox.RefusalText('Pause für KI'));
  try
    Assert.IsFalse(mJson.GetValue<Boolean>('ok'));
    Assert.AreEqual('Pause für KI', mJson.GetValue<string>('reason'));
  finally
    mJson.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasDebugInboxTests);

end.
