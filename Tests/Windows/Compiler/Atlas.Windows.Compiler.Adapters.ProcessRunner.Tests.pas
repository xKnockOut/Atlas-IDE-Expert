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
    /// <summary>Code-Review A-05: Cancel beendet einen laufenden Prozess sofort.</summary>
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
  Runner: ICompilerProcess;
  Request: TCompilerRequest;
  Lines: TList<string>;
  Code: Integer;
begin
  Runner := TProcessRunner.Create;
  Request := Default(TCompilerRequest);
  Request.Executable := GetEnvironmentVariable('ComSpec');
  Request.Arguments := ['/c', 'echo eins&echo zwei&exit 3'];
  Lines := TList<string>.Create;
  try
    Code := Runner.Run(Request,
      procedure(const ALine: string)
      begin
        Lines.Add(ALine);
      end);
    Assert.AreEqual(3, Code);
    Assert.AreEqual(2, Integer(Lines.Count));
    Assert.AreEqual('eins', Lines[0]);
    Assert.AreEqual('zwei', Lines[1]);
  finally
    Lines.Free;
  end;
end;

procedure TProcessRunnerTests.CancelEndsRunningProcess;
var
  Runner: ICompilerProcess;
  Request: TCompilerRequest;
  Canceller: TThread;
  Watch: TStopwatch;
begin
  Runner := TProcessRunner.Create;
  Request := Default(TCompilerRequest);
  // Direkt starten, nicht über cmd /c: Sonst erbte ping das Schreibende der Pipe, und ReadFile
  // bliebe bis zum Ende von ping blockiert.
  Request.Executable := TPath.Combine(GetEnvironmentVariable('SystemRoot'), 'System32\PING.EXE');
  Request.Arguments := ['-n', '30', '127.0.0.1'];
  Canceller := TThread.CreateAnonymousThread(
    procedure
    begin
      Sleep(300);
      Runner.Cancel;
    end);
  Canceller.FreeOnTerminate := False;
  try
    Watch := TStopwatch.StartNew;
    Canceller.Start;
    Assert.WillRaise(
      procedure
      begin
        Runner.Run(Request, nil);
      end, ECompilerCancelled);
    Assert.IsTrue(Watch.ElapsedMilliseconds < 5000, IntToStr(Watch.ElapsedMilliseconds));
  finally
    Canceller.WaitFor;
    Canceller.Free;
  end;
end;

procedure TProcessRunnerTests.RunAfterCancelRaises;
var
  Runner: ICompilerProcess;
  Request: TCompilerRequest;
begin
  Runner := TProcessRunner.Create;
  Request := Default(TCompilerRequest);
  Request.Executable := GetEnvironmentVariable('ComSpec');
  Request.Arguments := ['/c', 'exit 0'];
  Runner.Cancel;
  Assert.WillRaise(
    procedure
    begin
      Runner.Run(Request, nil);
    end, ECompilerCancelled);
end;

initialization
  TDUnitX.RegisterTestFixture(TProcessRunnerTests);

end.
