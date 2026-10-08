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
  BDLsp.Common.Documents.FileEncoding.Tests in 'Common\Documents\BDLsp.Common.Documents.FileEncoding.Tests.pas',
  BDLsp.Common.Projects.Tests in 'Common\Projects\BDLsp.Common.Projects.Tests.pas',
  BDLsp.Windows.Projects.DelphiInstallation.Tests in 'Windows\Projects\BDLsp.Windows.Projects.DelphiInstallation.Tests.pas',
  BDLsp.Common.Documents.Providers.DocumentStore.Tests in 'Common\Documents\BDLsp.Common.Documents.Providers.DocumentStore.Tests.pas',
  BDLsp.Common.Documents.Uris.Tests in 'Common\Documents\BDLsp.Common.Documents.Uris.Tests.pas',
  BDLsp.Common.Index.Tests in 'Common\Index\BDLsp.Common.Index.Tests.pas',
  BDLsp.Common.Semantics.NameResolver.Tests in 'Common\Semantics\BDLsp.Common.Semantics.NameResolver.Tests.pas',
  BDLsp.Common.Lsp.Definition.Tests in 'Common\Lsp\BDLsp.Common.Lsp.Definition.Tests.pas',
  BDLsp.Common.Lsp.Hover.Tests in 'Common\Lsp\BDLsp.Common.Lsp.Hover.Tests.pas',
  BDLsp.Common.Lsp.WorkspaceSymbols.Tests in 'Common\Lsp\BDLsp.Common.Lsp.WorkspaceSymbols.Tests.pas',
  BDLsp.Windows.Documents.PathCanonicalizer.Tests in 'Windows\Documents\BDLsp.Windows.Documents.PathCanonicalizer.Tests.pas',
  BDLsp.Common.Pascal.Lexer.Tests in 'Common\Pascal\BDLsp.Common.Pascal.Lexer.Tests.pas',
  BDLsp.Common.Lsp.Internals.Debouncer.Tests in 'Common\Lsp\BDLsp.Common.Lsp.Internals.Debouncer.Tests.pas',
  BDLsp.Common.JsonRpc.Watchdog.Tests in 'Common\JsonRpc\BDLsp.Common.JsonRpc.Watchdog.Tests.pas',
  BDLsp.Windows.Diagnostics.StackTrace.Tests in 'Windows\Diagnostics\BDLsp.Windows.Diagnostics.StackTrace.Tests.pas',
  BDLsp.Common.Lsp.DocumentSymbols.Tests in 'Common\Lsp\BDLsp.Common.Lsp.DocumentSymbols.Tests.pas',
  BDLsp.Common.Lsp.FoldingRanges.Tests in 'Common\Lsp\BDLsp.Common.Lsp.FoldingRanges.Tests.pas',
  BDLsp.Common.Lsp.SelectionRanges.Tests in 'Common\Lsp\BDLsp.Common.Lsp.SelectionRanges.Tests.pas',
  BDLsp.Common.Lsp.SyntaxDiagnostics.Tests in 'Common\Lsp\BDLsp.Common.Lsp.SyntaxDiagnostics.Tests.pas',
  BDLsp.Common.Configuration.Tests in 'Common\Configuration\BDLsp.Common.Configuration.Tests.pas',
  BDLsp.Common.Lsp.Configuration.Tests in 'Common\Lsp\BDLsp.Common.Lsp.Configuration.Tests.pas',
  BDLsp.Common.Pascal.Parser.Tests in 'Common\Pascal\BDLsp.Common.Pascal.Parser.Tests.pas',
  BDLsp.Common.Pascal.Parser.Robustness.Tests in 'Common\Pascal\BDLsp.Common.Pascal.Parser.Robustness.Tests.pas',
  BDLsp.Common.Pascal.Preprocessor.Tests in 'Common\Pascal\BDLsp.Common.Pascal.Preprocessor.Tests.pas',
  BDLsp.Common.Lsp.ProtocolReplay in 'Common\Lsp\BDLsp.Common.Lsp.ProtocolReplay.pas',
  BDLsp.Common.Lsp.Protocol.Tests in 'Common\Lsp\BDLsp.Common.Lsp.Protocol.Tests.pas',
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
