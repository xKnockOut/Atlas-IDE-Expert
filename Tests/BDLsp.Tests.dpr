program BDLsp.Tests;

{$IFNDEF TESTINSIGHT}
{$APPTYPE CONSOLE}
{$ENDIF}
{$STRONGLINKTYPES ON}

uses
  System.SysUtils,
  {$IFDEF TESTINSIGHT}
  TestInsight.DUnitX,
  {$ELSE}
  DUnitX.Loggers.Console,
  DUnitX.Loggers.Xml.NUnit,
  {$ENDIF}
  DUnitX.TestFramework,
  BDLsp.Common.Product.Version.Tests in 'Common\BDLsp.Common.Product.Version.Tests.pas',
  BDLsp.Common.Logging.Providers.Logger.Tests in 'Common\Logging\BDLsp.Common.Logging.Providers.Logger.Tests.pas',
  BDLsp.Common.Logging.Providers.StreamSink.Tests in 'Common\Logging\BDLsp.Common.Logging.Providers.StreamSink.Tests.pas',
  BDLsp.Common.JsonRpc.TestSupport in 'Common\JsonRpc\BDLsp.Common.JsonRpc.TestSupport.pas',
  BDLsp.Common.JsonRpc.StreamTransport.Tests in 'Common\JsonRpc\BDLsp.Common.JsonRpc.StreamTransport.Tests.pas',
  BDLsp.Common.JsonRpc.TracingTransport.Tests in 'Common\JsonRpc\BDLsp.Common.JsonRpc.TracingTransport.Tests.pas',
  BDLsp.Common.JsonRpc.PendingRequests.Tests in 'Common\JsonRpc\BDLsp.Common.JsonRpc.PendingRequests.Tests.pas',
  BDLsp.Common.JsonRpc.Dispatcher.Tests in 'Common\JsonRpc\BDLsp.Common.JsonRpc.Dispatcher.Tests.pas',
  BDLsp.Common.JsonRpc.Connection.Tests in 'Common\JsonRpc\BDLsp.Common.JsonRpc.Connection.Tests.pas',
  BDLsp.Common.Lsp.Lifecycle.Tests in 'Common\Lsp\BDLsp.Common.Lsp.Lifecycle.Tests.pas',
  BDLsp.Common.Lsp.Adapters.LogMessageSink.Tests in 'Common\Lsp\BDLsp.Common.Lsp.Adapters.LogMessageSink.Tests.pas',
  BDLsp.Common.Lsp.TextDocumentSync.Tests in 'Common\Lsp\BDLsp.Common.Lsp.TextDocumentSync.Tests.pas',
  BDLsp.Common.Documents.TextDocument.Tests in 'Common\Documents\BDLsp.Common.Documents.TextDocument.Tests.pas',
  BDLsp.Common.Documents.Providers.DocumentStore.Tests in 'Common\Documents\BDLsp.Common.Documents.Providers.DocumentStore.Tests.pas',
  BDLsp.Common.Pascal.Lexer.Tests in 'Common\Pascal\BDLsp.Common.Pascal.Lexer.Tests.pas',
  Shell.CommandLine in '..\Application\Source\Shell\Shell.CommandLine.pas',
  Shell.CommandLine.Tests in 'Application\Shell\Shell.CommandLine.Tests.pas';

{$IFNDEF TESTINSIGHT}
var
  Runner: ITestRunner;
  Results: IRunResults;
  Logger: ITestLogger;
  NUnitLogger: ITestLogger;
{$ENDIF}
begin
{$IFDEF TESTINSIGHT}
  TestInsight.DUnitX.RunRegisteredTests;
{$ELSE}
  try
    TDUnitX.CheckCommandLine;
    Runner := TDUnitX.CreateRunner;
    Runner.UseRTTI := True;
    Runner.FailsOnNoAsserts := False;

    if TDUnitX.Options.ConsoleMode <> TDunitXConsoleMode.Off then
    begin
      Logger := TDUnitXConsoleLogger.Create(TDUnitX.Options.ConsoleMode = TDunitXConsoleMode.Quiet);
      Runner.AddLogger(Logger);
    end;
    NUnitLogger := TDUnitXXMLNUnitFileLogger.Create(TDUnitX.Options.XMLOutputFile);
    Runner.AddLogger(NUnitLogger);

    Results := Runner.Execute;
    if not Results.AllPassed then
      System.ExitCode := EXIT_ERRORS;

    {$IFNDEF CI}
    if TDUnitX.Options.ExitBehavior = TDUnitXExitBehavior.Pause then
    begin
      System.Write('Fertig. <Enter> zum Beenden drücken.');
      System.Readln;
    end;
    {$ENDIF}
  except
    on E: Exception do
    begin
      System.Writeln(E.ClassName, ': ', E.Message);
      System.ExitCode := EXIT_ERRORS;
    end;
  end;
{$ENDIF}
end.
