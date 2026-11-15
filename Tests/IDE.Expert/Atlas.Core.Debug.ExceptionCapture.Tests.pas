unit Atlas.Core.Debug.ExceptionCapture.Tests;

// Tests für die Aufnahme eines Exception-Halts (#517, #1967): Ablauf von Stapel und Dialog, Nachfragen,
// Ersatzklasse, Ort aus dem Stapel, Art des stillen Fortsetzens; ohne IDE.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasExceptionCaptureTests = class
  public
    [Test]
    procedure TakeNeedsStackAndDialog;
    [Test]
    procedure ForceFinishesOpenCapture;
    [Test]
    procedure RetriesUpToLimit;
    [Test]
    procedure ResetKeepsNothingOpen;
    [Test]
    procedure FallbackClass;
    [Test]
    procedure LocationFromFrames;
    [Test]
    procedure ResumeWay;
    [Test]
    procedure LocationNeedsProjectFileLine;
  end;

implementation

uses
  Atlas.Core.Debug.CallStack,
  Atlas.Core.Debug.Exceptions,
  Atlas.Core.Debug.ExceptionBanner,
  Atlas.Core.Debug.ExceptionCapture;

function Frame(const ARoutine, AFileName: string; ALine: Integer): TAtlasDebugFrame;
begin
  Result := TAtlasDebugFrame.Create(ARoutine, AFileName, ALine);
end;

{ TAtlasExceptionCaptureTests }

procedure TAtlasExceptionCaptureTests.TakeNeedsStackAndDialog;
var
  mState: TAtlasDebugCaptureState;
begin
  mState := Default(TAtlasDebugCaptureState);
  Assert.IsFalse(mState.Take);
  mState.Open;
  Assert.IsFalse(mState.Take);
  mState.StackDone := True;
  Assert.IsFalse(mState.Take);
  mState.DialogDone := True;
  Assert.IsTrue(mState.Take);
  Assert.IsFalse(mState.HasPending);
  Assert.IsFalse(mState.Take);
end;

procedure TAtlasExceptionCaptureTests.ForceFinishesOpenCapture;
var
  mState: TAtlasDebugCaptureState;
begin
  mState := Default(TAtlasDebugCaptureState);
  mState.Open;
  mState.Force;
  Assert.IsTrue(mState.Take);
end;

procedure TAtlasExceptionCaptureTests.RetriesUpToLimit;
var
  mState: TAtlasDebugCaptureState;
begin
  mState := Default(TAtlasDebugCaptureState);
  mState.Open;
  Assert.IsTrue(mState.RetryStack(2));
  Assert.IsTrue(mState.RetryStack(2));
  Assert.IsFalse(mState.RetryStack(2));
  // Neue Aufnahme fängt wieder bei null an.
  mState.Open;
  Assert.AreEqual(0, mState.Retries);
  Assert.IsFalse(mState.StackDone);
end;

procedure TAtlasExceptionCaptureTests.ResetKeepsNothingOpen;
var
  mState: TAtlasDebugCaptureState;
begin
  mState := Default(TAtlasDebugCaptureState);
  mState.Open;
  mState.EarlyStop := 4;
  mState.Reset;
  Assert.IsFalse(mState.HasPending);
  Assert.AreEqual(0, mState.EarlyStop);
end;

procedure TAtlasExceptionCaptureTests.FallbackClass;
begin
  Assert.AreEqual('EAccessViolation', TAtlasDebugCapture.ClassOrFallback('EAccessViolation', True, 'OS', 'X'));
  Assert.AreEqual('OS', TAtlasDebugCapture.ClassOrFallback('', True, 'OS', 'X'));
  Assert.AreEqual('X', TAtlasDebugCapture.ClassOrFallback('', False, 'OS', 'X'));
end;

procedure TAtlasExceptionCaptureTests.LocationFromFrames;
var
  mException: TAtlasDebugException;
begin
  mException := Default(TAtlasDebugException);
  TAtlasDebugCapture.ApplyFrames(mException, [Frame('System.RaiseExcept', '', 0),
    Frame('Unit1.TForm1.Click', 'Unit1.pas', 42)], False);
  Assert.AreEqual('Unit1.pas', mException.FileName);
  Assert.AreEqual(42, mException.Line);
  Assert.AreEqual('Unit1.TForm1.Click', mException.Routine);
  Assert.AreEqual(2, Integer(Length(mException.Frames)));
  // Ohne Quelltext: nur die Routine des obersten Rahmens.
  mException := Default(TAtlasDebugException);
  TAtlasDebugCapture.ApplyFrames(mException, [Frame('kernel32.RaiseException', '', 0)], False);
  Assert.AreEqual('', mException.FileName);
  Assert.AreEqual('kernel32.RaiseException', mException.Routine);
  mException := Default(TAtlasDebugException);
  TAtlasDebugCapture.ApplyFrames(mException, nil, False);
  Assert.AreEqual('', mException.Routine);
end;

procedure TAtlasExceptionCaptureTests.ResumeWay;
begin
  Assert.AreEqual<TAtlasDebugCaptureResume>(TAtlasDebugCaptureResume.None,
    TAtlasDebugCapture.Resume(TAtlasDebugAutoContinue.None, True));
  Assert.AreEqual<TAtlasDebugCaptureResume>(TAtlasDebugCaptureResume.ByDialog,
    TAtlasDebugCapture.Resume(TAtlasDebugAutoContinue.ByClass, True));
  Assert.AreEqual<TAtlasDebugCaptureResume>(TAtlasDebugCaptureResume.ByProcess,
    TAtlasDebugCapture.Resume(TAtlasDebugAutoContinue.ByLocation, False));
end;

procedure TAtlasExceptionCaptureTests.LocationNeedsProjectFileLine;
begin
  Assert.IsTrue(TAtlasDebugCapture.CanIgnoreLocation('P.dproj', 'Unit1.pas', 1));
  Assert.IsFalse(TAtlasDebugCapture.CanIgnoreLocation('', 'Unit1.pas', 1));
  Assert.IsFalse(TAtlasDebugCapture.CanIgnoreLocation('P.dproj', '', 1));
  Assert.IsFalse(TAtlasDebugCapture.CanIgnoreLocation('P.dproj', 'Unit1.pas', 0));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasExceptionCaptureTests);

end.
