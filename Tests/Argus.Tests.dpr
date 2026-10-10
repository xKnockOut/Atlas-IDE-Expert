program Argus.Tests;

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
  Argus.Common.Product.Version.Tests in 'Common\Argus.Common.Product.Version.Tests.pas',
  Argus.Common.Logging.Providers.Logger.Tests in 'Common\Logging\Argus.Common.Logging.Providers.Logger.Tests.pas',
  Argus.Common.Logging.Providers.StreamSink.Tests in 'Common\Logging\Argus.Common.Logging.Providers.StreamSink.Tests.pas',
  Argus.Common.Logging.Providers.RotatingFileStream.Tests in 'Common\Logging\Argus.Common.Logging.Providers.RotatingFileStream.Tests.pas',
  Argus.Common.JsonRpc.TestSupport in 'Common\JsonRpc\Argus.Common.JsonRpc.TestSupport.pas',
  Argus.Common.JsonRpc.StreamTransport.Tests in 'Common\JsonRpc\Argus.Common.JsonRpc.StreamTransport.Tests.pas',
  Argus.Common.JsonRpc.TracingTransport.Tests in 'Common\JsonRpc\Argus.Common.JsonRpc.TracingTransport.Tests.pas',
  Argus.Common.JsonRpc.PendingRequests.Tests in 'Common\JsonRpc\Argus.Common.JsonRpc.PendingRequests.Tests.pas',
  Argus.Common.JsonRpc.Dispatcher.Tests in 'Common\JsonRpc\Argus.Common.JsonRpc.Dispatcher.Tests.pas',
  Argus.Common.JsonRpc.Connection.Tests in 'Common\JsonRpc\Argus.Common.JsonRpc.Connection.Tests.pas',
  Argus.Common.Lsp.Lifecycle.Tests in 'Common\Lsp\Argus.Common.Lsp.Lifecycle.Tests.pas',
  Argus.Common.Lsp.Adapters.LogMessageSink.Tests in 'Common\Lsp\Argus.Common.Lsp.Adapters.LogMessageSink.Tests.pas',
  Argus.Common.Lsp.TextDocumentSync.Tests in 'Common\Lsp\Argus.Common.Lsp.TextDocumentSync.Tests.pas',
  Argus.Common.Documents.TextDocument.Tests in 'Common\Documents\Argus.Common.Documents.TextDocument.Tests.pas',
  Argus.Common.Documents.FileEncoding.Tests in 'Common\Documents\Argus.Common.Documents.FileEncoding.Tests.pas',
  Argus.Common.Projects.Tests in 'Common\Projects\Argus.Common.Projects.Tests.pas',
  Argus.Common.Projects.DelphiVersions.Tests in 'Common\Projects\Argus.Common.Projects.DelphiVersions.Tests.pas',
  Argus.Common.Projects.DprojEditor.Tests in 'Common\Projects\Argus.Common.Projects.DprojEditor.Tests.pas',
  Argus.Windows.Projects.DelphiInstallation.Tests in 'Windows\Projects\Argus.Windows.Projects.DelphiInstallation.Tests.pas',
  Argus.Common.Compiler.Tests in 'Common\Compiler\Argus.Common.Compiler.Tests.pas',
  Argus.Common.Diagnostics.MapFile.Tests in 'Common\Diagnostics\Argus.Common.Diagnostics.MapFile.Tests.pas',
  Argus.Windows.Compiler.Adapters.ProcessRunner.Tests in 'Windows\Compiler\Argus.Windows.Compiler.Adapters.ProcessRunner.Tests.pas',
  Argus.Common.Documents.Providers.DocumentStore.Tests in 'Common\Documents\Argus.Common.Documents.Providers.DocumentStore.Tests.pas',
  Argus.Common.Documents.Uris.Tests in 'Common\Documents\Argus.Common.Documents.Uris.Tests.pas',
  Argus.Common.Index.Tests in 'Common\Index\Argus.Common.Index.Tests.pas',
  Argus.Common.Index.CacheHousekeeping.Tests in 'Common\Index\Argus.Common.Index.CacheHousekeeping.Tests.pas',
  Argus.Common.Index.Memory.Tests in 'Common\Index\Argus.Common.Index.Memory.Tests.pas',
  Argus.Common.Semantics.ControlFlow.Tests in 'Common\Semantics\Argus.Common.Semantics.ControlFlow.Tests.pas',
  Argus.Common.Semantics.NameResolver.Tests in 'Common\Semantics\Argus.Common.Semantics.NameResolver.Tests.pas',
  Argus.Common.Semantics.NameResolverStage2.Tests in 'Common\Semantics\Argus.Common.Semantics.NameResolverStage2.Tests.pas',
  Argus.Common.Lsp.Definition.Tests in 'Common\Lsp\Argus.Common.Lsp.Definition.Tests.pas',
  Argus.Common.Lsp.PublishedMembers.Tests in 'Common\Lsp\Argus.Common.Lsp.PublishedMembers.Tests.pas',
  Argus.Common.Lsp.References.Tests in 'Common\Lsp\Argus.Common.Lsp.References.Tests.pas',
  Argus.Common.Lsp.Rename.Tests in 'Common\Lsp\Argus.Common.Lsp.Rename.Tests.pas',
  Argus.Common.Lsp.Completion.Tests in 'Common\Lsp\Argus.Common.Lsp.Completion.Tests.pas',
  Argus.Common.Lsp.SignatureHelp.Tests in 'Common\Lsp\Argus.Common.Lsp.SignatureHelp.Tests.pas',
  Argus.Common.Lsp.Hierarchies.Tests in 'Common\Lsp\Argus.Common.Lsp.Hierarchies.Tests.pas',
  Argus.Common.Lsp.Implementations.Tests in 'Common\Lsp\Argus.Common.Lsp.Implementations.Tests.pas',
  Argus.Common.Lsp.InlayHints.Tests in 'Common\Lsp\Argus.Common.Lsp.InlayHints.Tests.pas',
  Argus.Common.Lsp.CodeLens.Tests in 'Common\Lsp\Argus.Common.Lsp.CodeLens.Tests.pas',
  Argus.Common.Lsp.SemanticTokens.Tests in 'Common\Lsp\Argus.Common.Lsp.SemanticTokens.Tests.pas',
  Argus.Common.Lsp.Status.Tests in 'Common\Lsp\Argus.Common.Lsp.Status.Tests.pas',
  Argus.Common.Lsp.QualifiedNames.Tests in 'Common\Lsp\Argus.Common.Lsp.QualifiedNames.Tests.pas',
  Argus.Common.Lsp.WinApiDocs.Tests in 'Common\Lsp\Argus.Common.Lsp.WinApiDocs.Tests.pas',
  Argus.Common.Lsp.KeywordReference.Tests in 'Common\Lsp\Argus.Common.Lsp.KeywordReference.Tests.pas',
  Argus.Common.Editing.AssignmentSwap.Tests in 'Common\Editing\Argus.Common.Editing.AssignmentSwap.Tests.pas',
  Argus.Common.Editing.StringLiterals.Tests in 'Common\Editing\Argus.Common.Editing.StringLiterals.Tests.pas',
  Argus.Common.Lsp.DocWiki.Tests in 'Common\Lsp\Argus.Common.Lsp.DocWiki.Tests.pas',
  Argus.Common.Lsp.CompilerDirectives.Tests in 'Common\Lsp\Argus.Common.Lsp.CompilerDirectives.Tests.pas',
  Argus.Common.Lsp.Hover.Tests in 'Common\Lsp\Argus.Common.Lsp.Hover.Tests.pas',
  Argus.Common.Lsp.HoverValues.Tests in 'Common\Lsp\Argus.Common.Lsp.HoverValues.Tests.pas',
  Argus.Common.Lsp.LinkedEditing.Tests in 'Common\Lsp\Argus.Common.Lsp.LinkedEditing.Tests.pas',
  Argus.Common.Lsp.Formatting.Tests in 'Common\Lsp\Argus.Common.Lsp.Formatting.Tests.pas',
  Argus.Common.Lsp.FuzzyMatch.Tests in 'Common\Lsp\Argus.Common.Lsp.FuzzyMatch.Tests.pas',
  Argus.Common.Lsp.WorkspaceSymbols.Tests in 'Common\Lsp\Argus.Common.Lsp.WorkspaceSymbols.Tests.pas',
  Argus.Common.Lsp.DocumentHighlights.Tests in 'Common\Lsp\Argus.Common.Lsp.DocumentHighlights.Tests.pas',
  Argus.Common.Lsp.KeywordHighlights.Tests in 'Common\Lsp\Argus.Common.Lsp.KeywordHighlights.Tests.pas',
  Argus.Common.Lsp.WatchedFiles.Tests in 'Common\Lsp\Argus.Common.Lsp.WatchedFiles.Tests.pas',
  Argus.Common.Lsp.WorkspaceFolders.Tests in 'Common\Lsp\Argus.Common.Lsp.WorkspaceFolders.Tests.pas',
  Argus.Windows.Documents.PathCanonicalizer.Tests in 'Windows\Documents\Argus.Windows.Documents.PathCanonicalizer.Tests.pas',
  Argus.Common.Pascal.Lexer.Tests in 'Common\Pascal\Argus.Common.Pascal.Lexer.Tests.pas',
  Argus.Common.Lsp.Internals.Debouncer.Tests in 'Common\Lsp\Argus.Common.Lsp.Internals.Debouncer.Tests.pas',
  Argus.Common.JsonRpc.Watchdog.Tests in 'Common\JsonRpc\Argus.Common.JsonRpc.Watchdog.Tests.pas',
  Argus.Windows.Diagnostics.StackTrace.Tests in 'Windows\Diagnostics\Argus.Windows.Diagnostics.StackTrace.Tests.pas',
  Argus.Common.Lsp.DocumentSymbols.Tests in 'Common\Lsp\Argus.Common.Lsp.DocumentSymbols.Tests.pas',
  Argus.Common.Lsp.FoldingRanges.Tests in 'Common\Lsp\Argus.Common.Lsp.FoldingRanges.Tests.pas',
  Argus.Common.Lsp.SelectionRanges.Tests in 'Common\Lsp\Argus.Common.Lsp.SelectionRanges.Tests.pas',
  Argus.Common.Lsp.SyntaxDiagnostics.Tests in 'Common\Lsp\Argus.Common.Lsp.SyntaxDiagnostics.Tests.pas',
  Argus.Common.Configuration.Tests in 'Common\Configuration\Argus.Common.Configuration.Tests.pas',
  Argus.Common.Lsp.Configuration.Tests in 'Common\Lsp\Argus.Common.Lsp.Configuration.Tests.pas',
  Argus.Common.Pascal.Parser.Tests in 'Common\Pascal\Argus.Common.Pascal.Parser.Tests.pas',
  Argus.Common.Pascal.TreeCache.Tests in 'Common\Pascal\Argus.Common.Pascal.TreeCache.Tests.pas',
  Argus.Common.Pascal.IncludeFiles.Tests in 'Common\Pascal\Argus.Common.Pascal.IncludeFiles.Tests.pas',
  Argus.Common.Pascal.Parser.Robustness.Tests in 'Common\Pascal\Argus.Common.Pascal.Parser.Robustness.Tests.pas',
  Argus.Common.Pascal.LanguageFeatures.Tests in 'Common\Pascal\Argus.Common.Pascal.LanguageFeatures.Tests.pas',
  Argus.Common.Pascal.Preprocessor.Tests in 'Common\Pascal\Argus.Common.Pascal.Preprocessor.Tests.pas',
  Argus.Common.Lsp.ProtocolReplay in 'Common\Lsp\Argus.Common.Lsp.ProtocolReplay.pas',
  Argus.Common.Lsp.Protocol.Tests in 'Common\Lsp\Argus.Common.Lsp.Protocol.Tests.pas',
  Shell.CommandLine in '..\Application\Source\Shell\Shell.CommandLine.pas',
  Shell.CommandLine.Tests in 'Application\Shell\Shell.CommandLine.Tests.pas',
  Argus.Tests.LeakMonitor in 'Support\Argus.Tests.LeakMonitor.pas',
  Argus.Tests.LeakMonitor.Tests in 'Support\Argus.Tests.LeakMonitor.Tests.pas',
  Argus.Tests.RuleAssert in 'Support\Argus.Tests.RuleAssert.pas',
  Argus.Common.Rules.Engine.Tests in 'Common\Rules\Argus.Common.Rules.Engine.Tests.pas',
  Argus.Common.Rules.GoldenCorpus.Tests in 'Common\Rules\Argus.Common.Rules.GoldenCorpus.Tests.pas',
  Argus.Common.Rules.Profiles.Tests in 'Common\Rules\Argus.Common.Rules.Profiles.Tests.pas',
  Argus.Common.Rules.Confidence.Tests in 'Common\Rules\Argus.Common.Rules.Confidence.Tests.pas',
  Argus.Common.Rules.Output.Tests in 'Common\Rules\Argus.Common.Rules.Output.Tests.pas',
  Argus.Common.Rules.Baseline.Tests in 'Common\Rules\Argus.Common.Rules.Baseline.Tests.pas',
  Argus.Common.Rules.SuppressionStats.Tests in 'Common\Rules\Argus.Common.Rules.SuppressionStats.Tests.pas',
  Argus.Common.Rules.Catalog.Tests in 'Common\Rules\Argus.Common.Rules.Catalog.Tests.pas',
  Argus.Common.Rules.Builtin.Unicode.Tests in 'Common\Rules\Builtin\Argus.Common.Rules.Builtin.Unicode.Tests.pas',
  Argus.Common.Editing.Colors.Tests in 'Common\Editing\Argus.Common.Editing.Colors.Tests.pas',
  Argus.Common.Editing.DocumentLinks.Tests in 'Common\Editing\Argus.Common.Editing.DocumentLinks.Tests.pas',
  Argus.Common.Editing.ClassCompletion.Tests in 'Common\Editing\Argus.Common.Editing.ClassCompletion.Tests.pas',
  Argus.Common.Dfm.Tests in 'Common\Dfm\Argus.Common.Dfm.Tests.pas',
  Argus.Common.Dfm.ComponentRename.Tests in 'Common\Dfm\Argus.Common.Dfm.ComponentRename.Tests.pas',
  Argus.Common.Dfm.FormModel.Tests in 'Common\Dfm\Argus.Common.Dfm.FormModel.Tests.pas',
  Argus.Common.Dfm.FormInfo.Tests in 'Common\Dfm\Argus.Common.Dfm.FormInfo.Tests.pas',
  Argus.Common.Dfm.BinaryForm.Tests in 'Common\Dfm\Argus.Common.Dfm.BinaryForm.Tests.pas',
  Argus.Common.JsonRpc.LineTransport.Tests in 'Common\JsonRpc\Argus.Common.JsonRpc.LineTransport.Tests.pas',
  Argus.Common.Mcp.Server.Tests in 'Common\Mcp\Argus.Common.Mcp.Server.Tests.pas',
  Argus.Common.Mcp.IndexTools.Tests in 'Common\Mcp\Argus.Common.Mcp.IndexTools.Tests.pas',
  Argus.Common.Mcp.CodeTools.Tests in 'Common\Mcp\Argus.Common.Mcp.CodeTools.Tests.pas',
  Argus.Common.Lsp.PullDiagnostics.Tests in 'Common\Lsp\Argus.Common.Lsp.PullDiagnostics.Tests.pas',
  Argus.Common.Editing.Formatter.Tests in 'Common\Editing\Argus.Common.Editing.Formatter.Tests.pas',
  Argus.Common.Editing.CodeActions.Tests in 'Common\Editing\Argus.Common.Editing.CodeActions.Tests.pas',
  Argus.Core.Lsp.Client in '..\Packages\Argus.IDE.Expert\Source\Core\Lsp\Argus.Core.Lsp.Client.pas',
  Argus.Core.Lsp.Session in '..\Packages\Argus.IDE.Expert\Source\Core\Lsp\Argus.Core.Lsp.Session.pas',
  Argus.Core.Lsp.Adapters.ServerProcess in '..\Packages\Argus.IDE.Expert\Source\Core\Lsp\Argus.Core.Lsp.Adapters.ServerProcess.pas',
  Argus.Core.Lsp.Tests in 'IDE.Expert\Argus.Core.Lsp.Tests.pas',
  Argus.Core.Completion.Contract in '..\Packages\Argus.IDE.Expert\Source\Core\Completion\Argus.Core.Completion.Contract.pas',
  Argus.Core.Completion.Internals.Async in '..\Packages\Argus.IDE.Expert\Source\Core\Completion\Internals\Argus.Core.Completion.Internals.Async.pas',
  Argus.Core.Completion.Composite in '..\Packages\Argus.IDE.Expert\Source\Core\Completion\Argus.Core.Completion.Composite.pas',
  Argus.Core.Completion.Providers.Fixed in '..\Packages\Argus.IDE.Expert\Source\Core\Completion\Providers\Argus.Core.Completion.Providers.Fixed.pas',
  Argus.Core.Completion.Providers.Server in '..\Packages\Argus.IDE.Expert\Source\Core\Completion\Providers\Argus.Core.Completion.Providers.Server.pas',
  Argus.Core.Completion.Tests in 'IDE.Expert\Argus.Core.Completion.Tests.pas',
  Argus.Core.Completion.Matching in '..\Packages\Argus.IDE.Expert\Source\Core\Completion\Argus.Core.Completion.Matching.pas',
  Argus.Core.Completion.Controller in '..\Packages\Argus.IDE.Expert\Source\Core\Completion\Argus.Core.Completion.Controller.pas',
  Argus.Core.Completion.Controller.Tests in 'IDE.Expert\Argus.Core.Completion.Controller.Tests.pas',
  Argus.Core.Signature.Contract in '..\Packages\Argus.IDE.Expert\Source\Core\Signature\Argus.Core.Signature.Contract.pas',
  Argus.Core.Signature.CallScanner in '..\Packages\Argus.IDE.Expert\Source\Core\Signature\Argus.Core.Signature.CallScanner.pas',
  Argus.Core.Signature.Controller in '..\Packages\Argus.IDE.Expert\Source\Core\Signature\Argus.Core.Signature.Controller.pas',
  Argus.Core.Signature.Providers.Server in '..\Packages\Argus.IDE.Expert\Source\Core\Signature\Argus.Core.Signature.Providers.Server.pas',
  Argus.Core.Signature.Tests in 'IDE.Expert\Argus.Core.Signature.Tests.pas',
  Argus.Core.Style.Color in '..\Packages\Argus.IDE.Expert\Source\Core\Style\Argus.Core.Style.Color.pas',
  Argus.Core.Style.Palette in '..\Packages\Argus.IDE.Expert\Source\Core\Style\Argus.Core.Style.Palette.pas',
  Argus.Core.Style.Syntax in '..\Packages\Argus.IDE.Expert\Source\Core\Style\Argus.Core.Style.Syntax.pas',
  Argus.Core.Style.Scaling in '..\Packages\Argus.IDE.Expert\Source\Core\Style\Argus.Core.Style.Scaling.pas',
  Argus.Core.Completion.Presentation in '..\Packages\Argus.IDE.Expert\Source\Core\Completion\Argus.Core.Completion.Presentation.pas',
  Argus.Core.Completion.Word in '..\Packages\Argus.IDE.Expert\Source\Core\Completion\Argus.Core.Completion.Word.pas',
  Argus.Core.Style.Tests in 'IDE.Expert\Argus.Core.Style.Tests.pas',
  Argus.Common.Pascal.XmlDoc.Tests in 'Common\Pascal\Argus.Common.Pascal.XmlDoc.Tests.pas',
  Argus.Common.Editing.UsesClause.Tests in 'Common\Editing\Argus.Common.Editing.UsesClause.Tests.pas',
  Argus.Common.Editing.UsesActions.Tests in 'Common\Editing\Argus.Common.Editing.UsesActions.Tests.pas',
  Argus.Common.Editing.UsesCommand.Tests in 'Common\Editing\Argus.Common.Editing.UsesCommand.Tests.pas',
  Argus.Common.Editing.SlashCommands.Tests in 'Common\Editing\Argus.Common.Editing.SlashCommands.Tests.pas',
  Argus.Common.Editing.DeclarationCommands.Tests in 'Common\Editing\Argus.Common.Editing.DeclarationCommands.Tests.pas',
  Argus.Common.Editing.ClassCommands.Tests in 'Common\Editing\Argus.Common.Editing.ClassCommands.Tests.pas',
  Argus.Common.Editing.WrapCommands.Tests in 'Common\Editing\Argus.Common.Editing.WrapCommands.Tests.pas',
  Argus.Common.Editing.MaintenanceCommands.Tests in 'Common\Editing\Argus.Common.Editing.MaintenanceCommands.Tests.pas',
  Argus.Common.Editing.TypeCommands.Tests in 'Common\Editing\Argus.Common.Editing.TypeCommands.Tests.pas',
  Argus.Common.Editing.CollectionCommands.Tests in 'Common\Editing\Argus.Common.Editing.CollectionCommands.Tests.pas',
  Argus.Common.Editing.UnitTemplates.Tests in 'Common\Editing\Argus.Common.Editing.UnitTemplates.Tests.pas',
  Argus.Common.Editing.ErrorCommands.Tests in 'Common\Editing\Argus.Common.Editing.ErrorCommands.Tests.pas',
  Argus.Common.Semantics.UnresolvedNames.Tests in 'Common\Semantics\Argus.Common.Semantics.UnresolvedNames.Tests.pas',
  Argus.Common.Rules.Builtin.Architecture.Tests in 'Common\Rules\Builtin\Argus.Common.Rules.Builtin.Architecture.Tests.pas',
  Argus.Common.Rules.Builtin.Concurrency.Tests in 'Common\Rules\Builtin\Argus.Common.Rules.Builtin.Concurrency.Tests.pas',
  Argus.Common.Rules.Builtin.Flow.Tests in 'Common\Rules\Builtin\Argus.Common.Rules.Builtin.Flow.Tests.pas',
  Argus.Common.Rules.Builtin.Unused.Tests in 'Common\Rules\Builtin\Argus.Common.Rules.Builtin.Unused.Tests.pas',
  Argus.Common.Rules.Builtin.Declarations.Tests in 'Common\Rules\Builtin\Argus.Common.Rules.Builtin.Declarations.Tests.pas',
  Argus.Common.Rules.Builtin.Inheritance.Tests in 'Common\Rules\Builtin\Argus.Common.Rules.Builtin.Inheritance.Tests.pas',
  Argus.Common.Rules.Builtin.Capture.Tests in 'Common\Rules\Builtin\Argus.Common.Rules.Builtin.Capture.Tests.pas',
  Argus.Common.Rules.Builtin.Components.Tests in 'Common\Rules\Builtin\Argus.Common.Rules.Builtin.Components.Tests.pas',
  Argus.Core.Settings.Plugin in '..\Packages\Argus.IDE.Expert\Source\Core\Settings\Argus.Core.Settings.Plugin.pas',
  Argus.Core.Settings.Tests in 'IDE.Expert\Argus.Core.Settings.Tests.pas',
  Argus.Core.Completion.Ranking in '..\Packages\Argus.IDE.Expert\Source\Core\Completion\Argus.Core.Completion.Ranking.pas',
  Argus.Core.Completion.Usage in '..\Packages\Argus.IDE.Expert\Source\Core\Completion\Argus.Core.Completion.Usage.pas',
  Argus.Core.Completion.Ranking.Tests in 'IDE.Expert\Argus.Core.Completion.Ranking.Tests.pas',
  Argus.UI.Strings in '..\Packages\Argus.IDE.Expert\Source\UI\Argus.UI.Strings.pas',
  Argus.UI.Strings.Tests in 'IDE.Expert\Argus.UI.Strings.Tests.pas',
  Argus.Core.Completion.Providers.XmlDoc in '..\Packages\Argus.IDE.Expert\Source\Core\Completion\Providers\Argus.Core.Completion.Providers.XmlDoc.pas',
  Argus.Core.Completion.Parentheses in '..\Packages\Argus.IDE.Expert\Source\Core\Completion\Argus.Core.Completion.Parentheses.pas',
  Argus.Core.Completion.Parentheses.Tests in 'IDE.Expert\Argus.Core.Completion.Parentheses.Tests.pas',
  Argus.Core.Completion.Preview in '..\Packages\Argus.IDE.Expert\Source\Core\Completion\Argus.Core.Completion.Preview.pas',
  Argus.UI.Settings.Page in '..\Packages\Argus.IDE.Expert\Source\UI\Settings\Argus.UI.Settings.Page.pas',
  Argus.UI.Settings.Page.Tests in 'IDE.Expert\Argus.UI.Settings.Page.Tests.pas',
  Argus.Core.Build.Events in '..\Packages\Argus.IDE.Expert\Source\Core\Build\Argus.Core.Build.Events.pas',
  Argus.Core.Build.Events.Tests in 'IDE.Expert\Argus.Core.Build.Events.Tests.pas',
  Argus.Core.Diagnostics.Hangs in '..\Packages\Argus.IDE.Expert\Source\Core\Diagnostics\Argus.Core.Diagnostics.Hangs.pas',
  Argus.Core.Diagnostics.Hangs.Tests in 'IDE.Expert\Argus.Core.Diagnostics.Hangs.Tests.pas',
  Argus.Core.Files.ExternalChanges in '..\Packages\Argus.IDE.Expert\Source\Core\Files\Argus.Core.Files.ExternalChanges.pas',
  Argus.Core.Files.ExternalChanges.Tests in 'IDE.Expert\Argus.Core.Files.ExternalChanges.Tests.pas',
  Argus.Core.Commands.Palette in '..\Packages\Argus.IDE.Expert\Source\Core\Commands\Argus.Core.Commands.Palette.pas',
  Argus.Core.Commands.Palette.Tests in 'IDE.Expert\Argus.Core.Commands.Palette.Tests.pas',
  Argus.Core.Editor.Pairs in '..\Packages\Argus.IDE.Expert\Source\Core\Editor\Argus.Core.Editor.Pairs.pas',
  Argus.Core.Editor.Pairs.Tests in 'IDE.Expert\Argus.Core.Editor.Pairs.Tests.pas',
  Argus.Core.Build.Messages in '..\Packages\Argus.IDE.Expert\Source\Core\Build\Argus.Core.Build.Messages.pas',
  Argus.Core.Build.Messages.Tests in 'IDE.Expert\Argus.Core.Build.Messages.Tests.pas',
  Argus.Common.Lsp.IdeBuild.Tests in 'Common\Lsp\Argus.Common.Lsp.IdeBuild.Tests.pas',
  Argus.Core.Build.CheckOnSave in '..\Packages\Argus.IDE.Expert\Source\Core\Build\Argus.Core.Build.CheckOnSave.pas',
  Argus.Core.Build.CheckOnSave.Tests in 'IDE.Expert\Argus.Core.Build.CheckOnSave.Tests.pas',
  Argus.Common.Mcp.BuildTools.Tests in 'Common\Mcp\Argus.Common.Mcp.BuildTools.Tests.pas',
  Argus.Common.Mcp.Paths.Tests in 'Common\Mcp\Argus.Common.Mcp.Paths.Tests.pas',
  Shell.Workspace in '..\Application\Source\Shell\Shell.Workspace.pas',
  Shell.Mcp in '..\Application\Source\Shell\Shell.Mcp.pas',
  Argus.Common.Mcp.Freshness.Tests in 'Common\Mcp\Argus.Common.Mcp.Freshness.Tests.pas',
  Shell.Mcp.Tests in 'Application\Shell\Shell.Mcp.Tests.pas',
  Argus.Common.Rules.Builtin.FormFields.Tests in 'Common\Rules\Builtin\Argus.Common.Rules.Builtin.FormFields.Tests.pas',
  Argus.Common.Rules.Builtin.Security.Tests in 'Common\Rules\Builtin\Argus.Common.Rules.Builtin.Security.Tests.pas',
  Argus.Common.Rules.Builtin.General.Tests in 'Common\Rules\Builtin\Argus.Common.Rules.Builtin.General.Tests.pas',
  Argus.Common.Rules.Builtin.RtlPatterns.Tests in 'Common\Rules\Builtin\Argus.Common.Rules.Builtin.RtlPatterns.Tests.pas',
  Argus.Common.Rules.Builtin.RtlTypePatterns.Tests in 'Common\Rules\Builtin\Argus.Common.Rules.Builtin.RtlTypePatterns.Tests.pas',
  Argus.Common.Rules.Builtin.Exceptions.Tests in 'Common\Rules\Builtin\Argus.Common.Rules.Builtin.Exceptions.Tests.pas',
  Argus.Common.Rules.Builtin.Performance.Tests in 'Common\Rules\Builtin\Argus.Common.Rules.Builtin.Performance.Tests.pas',
  Argus.Common.Rules.ChangedFiles.Tests in 'Common\Rules\Argus.Common.Rules.ChangedFiles.Tests.pas',
  Argus.Common.Editing.RefactoringCommands.Tests in 'Common\Editing\Argus.Common.Editing.RefactoringCommands.Tests.pas',
  Argus.Common.Editing.ExpressionCommands.Tests in 'Common\Editing\Argus.Common.Editing.ExpressionCommands.Tests.pas',
  Argus.Common.Editing.Modernizer.Tests in 'Common\Editing\Argus.Common.Editing.Modernizer.Tests.pas',
  Argus.Common.Editing.ProjectCommands.Tests in 'Common\Editing\Argus.Common.Editing.ProjectCommands.Tests.pas',
  Argus.Common.Editing.SqlText.Tests in 'Common\Editing\Argus.Common.Editing.SqlText.Tests.pas',
  Argus.Common.Editing.DatabaseCommands.Tests in 'Common\Editing\Argus.Common.Editing.DatabaseCommands.Tests.pas',
  Argus.Common.Editing.Bookmarks.Tests in 'Common\Editing\Argus.Common.Editing.Bookmarks.Tests.pas',
  Argus.Common.Editing.DocumentationCommands.Tests in 'Common\Editing\Argus.Common.Editing.DocumentationCommands.Tests.pas',
  Argus.Common.Editing.ComponentCommands.Tests in 'Common\Editing\Argus.Common.Editing.ComponentCommands.Tests.pas',
  Argus.Common.Editing.WinApiCommands.Tests in 'Common\Editing\Argus.Common.Editing.WinApiCommands.Tests.pas',
  Argus.Common.Editing.TaskCommands.Tests in 'Common\Editing\Argus.Common.Editing.TaskCommands.Tests.pas',
  Argus.Common.Editing.RecordCommands.Tests in 'Common\Editing\Argus.Common.Editing.RecordCommands.Tests.pas',
  Argus.Common.Rules.Builtin.DataBinding.Tests in 'Common\Rules\Builtin\Argus.Common.Rules.Builtin.DataBinding.Tests.pas';

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
