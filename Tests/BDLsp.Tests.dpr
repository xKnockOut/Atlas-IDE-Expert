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
  BDLsp.Common.Projects.DelphiVersions.Tests in 'Common\Projects\BDLsp.Common.Projects.DelphiVersions.Tests.pas',
  BDLsp.Windows.Projects.DelphiInstallation.Tests in 'Windows\Projects\BDLsp.Windows.Projects.DelphiInstallation.Tests.pas',
  BDLsp.Common.Compiler.Tests in 'Common\Compiler\BDLsp.Common.Compiler.Tests.pas',
  BDLsp.Windows.Compiler.Adapters.ProcessRunner.Tests in 'Windows\Compiler\BDLsp.Windows.Compiler.Adapters.ProcessRunner.Tests.pas',
  BDLsp.Common.Documents.Providers.DocumentStore.Tests in 'Common\Documents\BDLsp.Common.Documents.Providers.DocumentStore.Tests.pas',
  BDLsp.Common.Documents.Uris.Tests in 'Common\Documents\BDLsp.Common.Documents.Uris.Tests.pas',
  BDLsp.Common.Index.Tests in 'Common\Index\BDLsp.Common.Index.Tests.pas',
  BDLsp.Common.Index.CacheHousekeeping.Tests in 'Common\Index\BDLsp.Common.Index.CacheHousekeeping.Tests.pas',
  BDLsp.Common.Index.Memory.Tests in 'Common\Index\BDLsp.Common.Index.Memory.Tests.pas',
  BDLsp.Common.Semantics.ControlFlow.Tests in 'Common\Semantics\BDLsp.Common.Semantics.ControlFlow.Tests.pas',
  BDLsp.Common.Semantics.NameResolver.Tests in 'Common\Semantics\BDLsp.Common.Semantics.NameResolver.Tests.pas',
  BDLsp.Common.Lsp.Definition.Tests in 'Common\Lsp\BDLsp.Common.Lsp.Definition.Tests.pas',
  BDLsp.Common.Lsp.PublishedMembers.Tests in 'Common\Lsp\BDLsp.Common.Lsp.PublishedMembers.Tests.pas',
  BDLsp.Common.Lsp.References.Tests in 'Common\Lsp\BDLsp.Common.Lsp.References.Tests.pas',
  BDLsp.Common.Lsp.Rename.Tests in 'Common\Lsp\BDLsp.Common.Lsp.Rename.Tests.pas',
  BDLsp.Common.Lsp.Completion.Tests in 'Common\Lsp\BDLsp.Common.Lsp.Completion.Tests.pas',
  BDLsp.Common.Lsp.SignatureHelp.Tests in 'Common\Lsp\BDLsp.Common.Lsp.SignatureHelp.Tests.pas',
  BDLsp.Common.Lsp.Hierarchies.Tests in 'Common\Lsp\BDLsp.Common.Lsp.Hierarchies.Tests.pas',
  BDLsp.Common.Lsp.Implementations.Tests in 'Common\Lsp\BDLsp.Common.Lsp.Implementations.Tests.pas',
  BDLsp.Common.Lsp.InlayHints.Tests in 'Common\Lsp\BDLsp.Common.Lsp.InlayHints.Tests.pas',
  BDLsp.Common.Lsp.CodeLens.Tests in 'Common\Lsp\BDLsp.Common.Lsp.CodeLens.Tests.pas',
  BDLsp.Common.Lsp.SemanticTokens.Tests in 'Common\Lsp\BDLsp.Common.Lsp.SemanticTokens.Tests.pas',
  BDLsp.Common.Lsp.Status.Tests in 'Common\Lsp\BDLsp.Common.Lsp.Status.Tests.pas',
  BDLsp.Common.Lsp.DocWiki.Tests in 'Common\Lsp\BDLsp.Common.Lsp.DocWiki.Tests.pas',
  BDLsp.Common.Lsp.Hover.Tests in 'Common\Lsp\BDLsp.Common.Lsp.Hover.Tests.pas',
  BDLsp.Common.Lsp.HoverValues.Tests in 'Common\Lsp\BDLsp.Common.Lsp.HoverValues.Tests.pas',
  BDLsp.Common.Lsp.LinkedEditing.Tests in 'Common\Lsp\BDLsp.Common.Lsp.LinkedEditing.Tests.pas',
  BDLsp.Common.Lsp.Formatting.Tests in 'Common\Lsp\BDLsp.Common.Lsp.Formatting.Tests.pas',
  BDLsp.Common.Lsp.FuzzyMatch.Tests in 'Common\Lsp\BDLsp.Common.Lsp.FuzzyMatch.Tests.pas',
  BDLsp.Common.Lsp.WorkspaceSymbols.Tests in 'Common\Lsp\BDLsp.Common.Lsp.WorkspaceSymbols.Tests.pas',
  BDLsp.Common.Lsp.DocumentHighlights.Tests in 'Common\Lsp\BDLsp.Common.Lsp.DocumentHighlights.Tests.pas',
  BDLsp.Common.Lsp.WatchedFiles.Tests in 'Common\Lsp\BDLsp.Common.Lsp.WatchedFiles.Tests.pas',
  BDLsp.Common.Lsp.WorkspaceFolders.Tests in 'Common\Lsp\BDLsp.Common.Lsp.WorkspaceFolders.Tests.pas',
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
  BDLsp.Common.Pascal.TreeCache.Tests in 'Common\Pascal\BDLsp.Common.Pascal.TreeCache.Tests.pas',
  BDLsp.Common.Pascal.IncludeFiles.Tests in 'Common\Pascal\BDLsp.Common.Pascal.IncludeFiles.Tests.pas',
  BDLsp.Common.Pascal.Parser.Robustness.Tests in 'Common\Pascal\BDLsp.Common.Pascal.Parser.Robustness.Tests.pas',
  BDLsp.Common.Pascal.LanguageFeatures.Tests in 'Common\Pascal\BDLsp.Common.Pascal.LanguageFeatures.Tests.pas',
  BDLsp.Common.Pascal.Preprocessor.Tests in 'Common\Pascal\BDLsp.Common.Pascal.Preprocessor.Tests.pas',
  BDLsp.Common.Lsp.ProtocolReplay in 'Common\Lsp\BDLsp.Common.Lsp.ProtocolReplay.pas',
  BDLsp.Common.Lsp.Protocol.Tests in 'Common\Lsp\BDLsp.Common.Lsp.Protocol.Tests.pas',
  Shell.CommandLine in '..\Application\Source\Shell\Shell.CommandLine.pas',
  Shell.CommandLine.Tests in 'Application\Shell\Shell.CommandLine.Tests.pas',
  BDLsp.Tests.LeakMonitor in 'Support\BDLsp.Tests.LeakMonitor.pas',
  BDLsp.Tests.LeakMonitor.Tests in 'Support\BDLsp.Tests.LeakMonitor.Tests.pas',
  BDLsp.Tests.RuleAssert in 'Support\BDLsp.Tests.RuleAssert.pas',
  BDLsp.Common.Rules.Engine.Tests in 'Common\Rules\BDLsp.Common.Rules.Engine.Tests.pas',
  BDLsp.Common.Rules.Profiles.Tests in 'Common\Rules\BDLsp.Common.Rules.Profiles.Tests.pas',
  BDLsp.Common.Rules.Confidence.Tests in 'Common\Rules\BDLsp.Common.Rules.Confidence.Tests.pas',
  BDLsp.Common.Rules.Output.Tests in 'Common\Rules\BDLsp.Common.Rules.Output.Tests.pas',
  BDLsp.Common.Rules.Baseline.Tests in 'Common\Rules\BDLsp.Common.Rules.Baseline.Tests.pas',
  BDLsp.Common.Rules.SuppressionStats.Tests in 'Common\Rules\BDLsp.Common.Rules.SuppressionStats.Tests.pas',
  BDLsp.Common.Rules.Catalog.Tests in 'Common\Rules\BDLsp.Common.Rules.Catalog.Tests.pas',
  BDLsp.Common.Rules.Builtin.Unicode.Tests in 'Common\Rules\Builtin\BDLsp.Common.Rules.Builtin.Unicode.Tests.pas',
  BDLsp.Common.Editing.Colors.Tests in 'Common\Editing\BDLsp.Common.Editing.Colors.Tests.pas',
  BDLsp.Common.Editing.DocumentLinks.Tests in 'Common\Editing\BDLsp.Common.Editing.DocumentLinks.Tests.pas',
  BDLsp.Common.Editing.ClassCompletion.Tests in 'Common\Editing\BDLsp.Common.Editing.ClassCompletion.Tests.pas',
  BDLsp.Common.Dfm.Tests in 'Common\Dfm\BDLsp.Common.Dfm.Tests.pas',
  BDLsp.Common.Dfm.ComponentRename.Tests in 'Common\Dfm\BDLsp.Common.Dfm.ComponentRename.Tests.pas',
  BDLsp.Common.JsonRpc.LineTransport.Tests in 'Common\JsonRpc\BDLsp.Common.JsonRpc.LineTransport.Tests.pas',
  BDLsp.Common.Mcp.Server.Tests in 'Common\Mcp\BDLsp.Common.Mcp.Server.Tests.pas',
  BDLsp.Common.Mcp.IndexTools.Tests in 'Common\Mcp\BDLsp.Common.Mcp.IndexTools.Tests.pas',
  BDLsp.Common.Mcp.CodeTools.Tests in 'Common\Mcp\BDLsp.Common.Mcp.CodeTools.Tests.pas',
  BDLsp.Common.Lsp.PullDiagnostics.Tests in 'Common\Lsp\BDLsp.Common.Lsp.PullDiagnostics.Tests.pas',
  BDLsp.Common.Editing.Formatter.Tests in 'Common\Editing\BDLsp.Common.Editing.Formatter.Tests.pas',
  BDLsp.Common.Editing.CodeActions.Tests in 'Common\Editing\BDLsp.Common.Editing.CodeActions.Tests.pas',
  BDLsp.Common.Editing.UsesClause.Tests in 'Common\Editing\BDLsp.Common.Editing.UsesClause.Tests.pas',
  BDLsp.Common.Editing.BlockCompletion.Tests in 'Common\Editing\BDLsp.Common.Editing.BlockCompletion.Tests.pas',
  BDLsp.Common.Editing.UsesCommand.Tests in 'Common\Editing\BDLsp.Common.Editing.UsesCommand.Tests.pas',
  BDLsp.Common.Editing.UnitFiles.Tests in 'Common\Editing\BDLsp.Common.Editing.UnitFiles.Tests.pas',
  BDLsp.Common.Rules.Builtin.UnitFiles.Tests in 'Common\Rules\Builtin\BDLsp.Common.Rules.Builtin.UnitFiles.Tests.pas',
  BDLsp.Common.Lsp.FileOperations.Tests in 'Common\Lsp\BDLsp.Common.Lsp.FileOperations.Tests.pas',
  BDLsp.Common.Semantics.UnresolvedNames.Tests in 'Common\Semantics\BDLsp.Common.Semantics.UnresolvedNames.Tests.pas',
  BDLsp.Common.Rules.Builtin.Architecture.Tests in 'Common\Rules\Builtin\BDLsp.Common.Rules.Builtin.Architecture.Tests.pas',
  BDLsp.Common.Rules.Builtin.Concurrency.Tests in 'Common\Rules\Builtin\BDLsp.Common.Rules.Builtin.Concurrency.Tests.pas';

{$IFNDEF TESTINSIGHT}
var
  Runner: ITestRunner;
  Results: IRunResults;
  Logger: ITestLogger;
  NUnitLogger: ITestLogger;
{$ENDIF}
begin
  {$IFDEF DEBUG}
  ReportMemoryLeaksOnShutdown := True;
  {$ENDIF}
  RegisterLeakMonitor;
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
    // Ein Speicherleck zählt als Fehlschlag.
    if (not Results.AllPassed) or (Results.MemoryLeakCount > 0) then
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
