unit Atlas.Windows.Compiler.Adapters.ProcessRunner.Tests;

interface

uses
  DUnitX.TestFramework,
  Atlas.Windows.Compiler.Adapters.ProcessRunner;

type
  [TestFixture]
  TProcessRunnerTests = class
  public
    [Test]
    procedure QuotesArguments;
    [Test]
    procedure ReadsOutputLinesAndExitCode;
    /// <summary>Cancel beendet einen laufenden Prozess sofort.</summary>
    [Test]
    procedure CancelEndsRunningProcess;
    [Test]
    procedure RunAfterCancelRaises;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Diagnostics,
  System.Generics.Collections,
  Atlas.Common.Compiler.Contract;

{ TProcessRunnerTests }

procedure TProcessRunnerTests.QuotesArguments;
begin
  Assert.AreEqual('-Q', TProcessRunner.QuoteArgument('-Q'));
  Assert.AreEqual('"C:\Program Files\x.dpr"', TProcessRunner.QuoteArgument('C:\Program Files\x.dpr'));
  Assert.AreEqual('"-UC:\a b\\"', TProcessRunner.QuoteArgument('-UC:\a b\'));
  Assert.AreEqual('"a\"b"', TProcessRunner.QuoteArgument('a"b'));
  Assert.AreEqual('""', TProcessRunner.QuoteArgument(''));
end;

procedure TProcessRunnerTests.ReadsOutputLinesAndExitCode;
var
  mRunner: ICompilerProcess;
  mRequest: TCompilerRequest;
  mLines: TList<string>;
  mCode: Integer;
begin
  mRunner := TProcessRunner.Create;
  mRequest := Default(TCompilerRequest);
  mRequest.Executable := GetEnvironmentVariable('ComSpec');
  mRequest.Arguments := ['/c', 'echo eins&echo zwei&exit 3'];
  mLines := TList<string>.Create;
  try
    mCode := mRunner.Run(mRequest,
      procedure(const ALine: string)
      begin
        mLines.Add(ALine);
      end);
    Assert.AreEqual(3, mCode);
    Assert.AreEqual(2, Integer(mLines.Count));
    Assert.AreEqual('eins', mLines[0]);
    Assert.AreEqual('zwei', mLines[1]);
  finally
    mLines.Free;
  end;
end;

procedure TProcessRunnerTests.CancelEndsRunningProcess;
var
  mRunner: ICompilerProcess;
  mRequest: TCompilerRequest;
  mCanceller: TThread;
  mWatch: TStopwatch;
begin
  mRunner := TProcessRunner.Create;
  mRequest := Default(TCompilerRequest);
  // Direkt starten, nicht über cmd /c: Sonst erbte ping das Schreibende der Pipe, und ReadFile
  // bliebe bis zum Ende von ping blockiert.
  mRequest.Executable := TPath.Combine(GetEnvironmentVariable('SystemRoot'), 'System32\PING.EXE');
  mRequest.Arguments := ['-n', '30', '127.0.0.1'];
  mCanceller := TThread.CreateAnonymousThread(
    procedure
    begin
      Sleep(300);
      mRunner.Cancel;
    end);
  mCanceller.FreeOnTerminate := False;
  try
    mWatch := TStopwatch.StartNew;
    mCanceller.Start;
    Assert.WillRaise(
      procedure
      begin
        mRunner.Run(mRequest, nil);
      end, ECompilerCancelled);
    Assert.IsTrue(mWatch.ElapsedMilliseconds < 5000, IntToStr(mWatch.ElapsedMilliseconds));
  finally
    mCanceller.WaitFor;
    mCanceller.Free;
  end;
end;

procedure TProcessRunnerTests.RunAfterCancelRaises;
var
  mRunner: ICompilerProcess;
  mRequest: TCompilerRequest;
begin
  mRunner := TProcessRunner.Create;
  mRequest := Default(TCompilerRequest);
  mRequest.Executable := GetEnvironmentVariable('ComSpec');
  mRequest.Arguments := ['/c', 'exit 0'];
  mRunner.Cancel;
  Assert.WillRaise(
    procedure
    begin
      mRunner.Run(mRequest, nil);
    end, ECompilerCancelled);
end;

initialization
  TDUnitX.RegisterTestFixture(TProcessRunnerTests);

end.
