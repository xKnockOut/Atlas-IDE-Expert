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
  end;

implementation

uses
  System.SysUtils,
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

initialization
  TDUnitX.RegisterTestFixture(TProcessRunnerTests);

end.
