program Atlas.Tests;

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
  Atlas.Common.Product.Version.Tests in 'Common\Atlas.Common.Product.Version.Tests.pas',
  Atlas.Common.Logging.Providers.Logger.Tests in 'Common\Logging\Atlas.Common.Logging.Providers.Logger.Tests.pas',
  Atlas.Common.Logging.Providers.StreamSink.Tests in 'Common\Logging\Atlas.Common.Logging.Providers.StreamSink.Tests.pas',
  Atlas.Common.Logging.Providers.RotatingFileStream.Tests in 'Common\Logging\Atlas.Common.Logging.Providers.RotatingFileStream.Tests.pas',
  Atlas.Common.JsonRpc.TestSupport in 'Common\JsonRpc\Atlas.Common.JsonRpc.TestSupport.pas',
  Atlas.Common.JsonRpc.StreamTransport.Tests in 'Common\JsonRpc\Atlas.Common.JsonRpc.StreamTransport.Tests.pas',
  Atlas.Common.JsonRpc.TracingTransport.Tests in 'Common\JsonRpc\Atlas.Common.JsonRpc.TracingTransport.Tests.pas',
  Atlas.Common.JsonRpc.PendingRequests.Tests in 'Common\JsonRpc\Atlas.Common.JsonRpc.PendingRequests.Tests.pas',
  Atlas.Common.JsonRpc.Dispatcher.Tests in 'Common\JsonRpc\Atlas.Common.JsonRpc.Dispatcher.Tests.pas',
  Atlas.Common.JsonRpc.Connection.Tests in 'Common\JsonRpc\Atlas.Common.JsonRpc.Connection.Tests.pas',
  Atlas.Common.Lsp.Lifecycle.Tests in 'Common\Lsp\Atlas.Common.Lsp.Lifecycle.Tests.pas',
  Atlas.Common.Lsp.Adapters.LogMessageSink.Tests in 'Common\Lsp\Atlas.Common.Lsp.Adapters.LogMessageSink.Tests.pas',
  Atlas.Common.Lsp.TextDocumentSync.Tests in 'Common\Lsp\Atlas.Common.Lsp.TextDocumentSync.Tests.pas',
  Atlas.Common.Documents.TextDocument.Tests in 'Common\Documents\Atlas.Common.Documents.TextDocument.Tests.pas',
  Atlas.Common.Documents.FileEncoding.Tests in 'Common\Documents\Atlas.Common.Documents.FileEncoding.Tests.pas',
  Atlas.Common.Projects.Tests in 'Common\Projects\Atlas.Common.Projects.Tests.pas',
  Atlas.Common.Projects.DelphiVersions.Tests in 'Common\Projects\Atlas.Common.Projects.DelphiVersions.Tests.pas',
  Atlas.Common.Projects.DprojEditor.Tests in 'Common\Projects\Atlas.Common.Projects.DprojEditor.Tests.pas',
  Atlas.Windows.Projects.DelphiInstallation.Tests in 'Windows\Projects\Atlas.Windows.Projects.DelphiInstallation.Tests.pas',
  Atlas.Common.Compiler.Tests in 'Common\Compiler\Atlas.Common.Compiler.Tests.pas',
  Atlas.Common.Diagnostics.MapFile.Tests in 'Common\Diagnostics\Atlas.Common.Diagnostics.MapFile.Tests.pas',
  Atlas.Windows.Compiler.Adapters.ProcessRunner.Tests in 'Windows\Compiler\Atlas.Windows.Compiler.Adapters.ProcessRunner.Tests.pas',
  Atlas.Common.Documents.Providers.DocumentStore.Tests in 'Common\Documents\Atlas.Common.Documents.Providers.DocumentStore.Tests.pas',
  Atlas.Common.Documents.Uris.Tests in 'Common\Documents\Atlas.Common.Documents.Uris.Tests.pas',
  Atlas.Common.Index.Tests in 'Common\Index\Atlas.Common.Index.Tests.pas',
  Atlas.Common.Index.CacheHousekeeping.Tests in 'Common\Index\Atlas.Common.Index.CacheHousekeeping.Tests.pas',
  Atlas.Common.Index.Memory.Tests in 'Common\Index\Atlas.Common.Index.Memory.Tests.pas',
  Atlas.Common.Semantics.ControlFlow.Tests in 'Common\Semantics\Atlas.Common.Semantics.ControlFlow.Tests.pas',
  Atlas.Common.Semantics.NameResolver.Tests in 'Common\Semantics\Atlas.Common.Semantics.NameResolver.Tests.pas',
  Atlas.Common.Semantics.Attributes.Tests in 'Common\Semantics\Atlas.Common.Semantics.Attributes.Tests.pas',
  Atlas.Common.Semantics.NameResolverStage2.Tests in 'Common\Semantics\Atlas.Common.Semantics.NameResolverStage2.Tests.pas',
  Atlas.Common.Lsp.Definition.Tests in 'Common\Lsp\Atlas.Common.Lsp.Definition.Tests.pas',
  Atlas.Common.Lsp.Attributes.Tests in 'Common\Lsp\Atlas.Common.Lsp.Attributes.Tests.pas',
  Atlas.Common.Lsp.PublishedMembers.Tests in 'Common\Lsp\Atlas.Common.Lsp.PublishedMembers.Tests.pas',
  Atlas.Common.Lsp.References.Tests in 'Common\Lsp\Atlas.Common.Lsp.References.Tests.pas',
  Atlas.Common.Lsp.Rename.Tests in 'Common\Lsp\Atlas.Common.Lsp.Rename.Tests.pas',
  Atlas.Common.Lsp.Completion.Tests in 'Common\Lsp\Atlas.Common.Lsp.Completion.Tests.pas',
  Atlas.Common.Lsp.SignatureHelp.Tests in 'Common\Lsp\Atlas.Common.Lsp.SignatureHelp.Tests.pas',
  Atlas.Common.Lsp.Hierarchies.Tests in 'Common\Lsp\Atlas.Common.Lsp.Hierarchies.Tests.pas',
  Atlas.Common.Lsp.Implementations.Tests in 'Common\Lsp\Atlas.Common.Lsp.Implementations.Tests.pas',
  Atlas.Common.Lsp.InlayHints.Tests in 'Common\Lsp\Atlas.Common.Lsp.InlayHints.Tests.pas',
  Atlas.Common.Lsp.CodeLens.Tests in 'Common\Lsp\Atlas.Common.Lsp.CodeLens.Tests.pas',
  Atlas.Common.Lsp.SemanticTokens.Tests in 'Common\Lsp\Atlas.Common.Lsp.SemanticTokens.Tests.pas',
  Atlas.Common.Lsp.Status.Tests in 'Common\Lsp\Atlas.Common.Lsp.Status.Tests.pas',
  Atlas.Common.Lsp.QualifiedNames.Tests in 'Common\Lsp\Atlas.Common.Lsp.QualifiedNames.Tests.pas',
  Atlas.Common.Lsp.WinApiDocs.Tests in 'Common\Lsp\Atlas.Common.Lsp.WinApiDocs.Tests.pas',
  Atlas.Common.Lsp.KeywordReference.Tests in 'Common\Lsp\Atlas.Common.Lsp.KeywordReference.Tests.pas',
  Atlas.Common.Editing.AssignmentSwap.Tests in 'Common\Editing\Atlas.Common.Editing.AssignmentSwap.Tests.pas',
  Atlas.Common.Editing.StringLiterals.Tests in 'Common\Editing\Atlas.Common.Editing.StringLiterals.Tests.pas',
  Atlas.Common.Lsp.DocWiki.Tests in 'Common\Lsp\Atlas.Common.Lsp.DocWiki.Tests.pas',
  Atlas.Common.Lsp.CompilerDirectives.Tests in 'Common\Lsp\Atlas.Common.Lsp.CompilerDirectives.Tests.pas',
  Atlas.Common.Lsp.Hover.Tests in 'Common\Lsp\Atlas.Common.Lsp.Hover.Tests.pas',
  Atlas.Common.Lsp.HoverTypes.Tests in 'Common\Lsp\Atlas.Common.Lsp.HoverTypes.Tests.pas',
  Atlas.Common.Lsp.HoverValues.Tests in 'Common\Lsp\Atlas.Common.Lsp.HoverValues.Tests.pas',
  Atlas.Common.Lsp.LinkedEditing.Tests in 'Common\Lsp\Atlas.Common.Lsp.LinkedEditing.Tests.pas',
  Atlas.Common.Lsp.Formatting.Tests in 'Common\Lsp\Atlas.Common.Lsp.Formatting.Tests.pas',
  Atlas.Common.Lsp.FuzzyMatch.Tests in 'Common\Lsp\Atlas.Common.Lsp.FuzzyMatch.Tests.pas',
  Atlas.Common.Lsp.WorkspaceSymbols.Tests in 'Common\Lsp\Atlas.Common.Lsp.WorkspaceSymbols.Tests.pas',
  Atlas.Common.Lsp.DocumentHighlights.Tests in 'Common\Lsp\Atlas.Common.Lsp.DocumentHighlights.Tests.pas',
  Atlas.Common.Lsp.KeywordHighlights.Tests in 'Common\Lsp\Atlas.Common.Lsp.KeywordHighlights.Tests.pas',
  Atlas.Common.Lsp.WatchedFiles.Tests in 'Common\Lsp\Atlas.Common.Lsp.WatchedFiles.Tests.pas',
  Atlas.Common.Lsp.WorkspaceFolders.Tests in 'Common\Lsp\Atlas.Common.Lsp.WorkspaceFolders.Tests.pas',
  Atlas.Windows.Documents.PathCanonicalizer.Tests in 'Windows\Documents\Atlas.Windows.Documents.PathCanonicalizer.Tests.pas',
  Atlas.Common.Pascal.Lexer.Tests in 'Common\Pascal\Atlas.Common.Pascal.Lexer.Tests.pas',
  Atlas.Common.Lsp.Internals.Debouncer.Tests in 'Common\Lsp\Atlas.Common.Lsp.Internals.Debouncer.Tests.pas',
  Atlas.Common.JsonRpc.Watchdog.Tests in 'Common\JsonRpc\Atlas.Common.JsonRpc.Watchdog.Tests.pas',
  Atlas.Windows.Diagnostics.StackTrace.Tests in 'Windows\Diagnostics\Atlas.Windows.Diagnostics.StackTrace.Tests.pas',
  Atlas.Common.Lsp.DocumentSymbols.Tests in 'Common\Lsp\Atlas.Common.Lsp.DocumentSymbols.Tests.pas',
  Atlas.Common.Lsp.FoldingRanges.Tests in 'Common\Lsp\Atlas.Common.Lsp.FoldingRanges.Tests.pas',
  Atlas.Common.Lsp.SelectionRanges.Tests in 'Common\Lsp\Atlas.Common.Lsp.SelectionRanges.Tests.pas',
  Atlas.Common.Lsp.SyntaxDiagnostics.Tests in 'Common\Lsp\Atlas.Common.Lsp.SyntaxDiagnostics.Tests.pas',
  Atlas.Common.Configuration.Tests in 'Common\Configuration\Atlas.Common.Configuration.Tests.pas',
  Atlas.Common.Lsp.Configuration.Tests in 'Common\Lsp\Atlas.Common.Lsp.Configuration.Tests.pas',
  Atlas.Common.Pascal.Parser.Tests in 'Common\Pascal\Atlas.Common.Pascal.Parser.Tests.pas',
  Atlas.Common.Pascal.TreeCache.Tests in 'Common\Pascal\Atlas.Common.Pascal.TreeCache.Tests.pas',
  Atlas.Common.Pascal.IncludeFiles.Tests in 'Common\Pascal\Atlas.Common.Pascal.IncludeFiles.Tests.pas',
  Atlas.Common.Pascal.Parser.Robustness.Tests in 'Common\Pascal\Atlas.Common.Pascal.Parser.Robustness.Tests.pas',
  Atlas.Common.Pascal.LanguageFeatures.Tests in 'Common\Pascal\Atlas.Common.Pascal.LanguageFeatures.Tests.pas',
  Atlas.Common.Pascal.Preprocessor.Tests in 'Common\Pascal\Atlas.Common.Pascal.Preprocessor.Tests.pas',
  Atlas.Common.Lsp.ProtocolReplay in 'Common\Lsp\Atlas.Common.Lsp.ProtocolReplay.pas',
  Atlas.Common.Lsp.Protocol.Tests in 'Common\Lsp\Atlas.Common.Lsp.Protocol.Tests.pas',
  Shell.CommandLine in '..\Application\Source\Shell\Shell.CommandLine.pas',
  Shell.CommandLine.Tests in 'Application\Shell\Shell.CommandLine.Tests.pas',
  Atlas.Tests.LeakMonitor in 'Support\Atlas.Tests.LeakMonitor.pas',
  Atlas.Tests.LeakMonitor.Tests in 'Support\Atlas.Tests.LeakMonitor.Tests.pas',
  Atlas.Tests.RuleAssert in 'Support\Atlas.Tests.RuleAssert.pas',
  Atlas.Common.Rules.Engine.Tests in 'Common\Rules\Atlas.Common.Rules.Engine.Tests.pas',
  Atlas.Common.Rules.GoldenCorpus.Tests in 'Common\Rules\Atlas.Common.Rules.GoldenCorpus.Tests.pas',
  Atlas.Common.Rules.Profiles.Tests in 'Common\Rules\Atlas.Common.Rules.Profiles.Tests.pas',
  Atlas.Common.Rules.Confidence.Tests in 'Common\Rules\Atlas.Common.Rules.Confidence.Tests.pas',
  Atlas.Common.Rules.Output.Tests in 'Common\Rules\Atlas.Common.Rules.Output.Tests.pas',
  Atlas.Common.Rules.Baseline.Tests in 'Common\Rules\Atlas.Common.Rules.Baseline.Tests.pas',
  Atlas.Common.Rules.SuppressionStats.Tests in 'Common\Rules\Atlas.Common.Rules.SuppressionStats.Tests.pas',
  Atlas.Common.Rules.Catalog.Tests in 'Common\Rules\Atlas.Common.Rules.Catalog.Tests.pas',
  Atlas.Common.Rules.Builtin.Unicode.Tests in 'Common\Rules\Builtin\Atlas.Common.Rules.Builtin.Unicode.Tests.pas',
  Atlas.Common.Editing.Colors.Tests in 'Common\Editing\Atlas.Common.Editing.Colors.Tests.pas',
  Atlas.Common.Editing.DocumentLinks.Tests in 'Common\Editing\Atlas.Common.Editing.DocumentLinks.Tests.pas',
  Atlas.Common.Editing.ClassCompletion.Tests in 'Common\Editing\Atlas.Common.Editing.ClassCompletion.Tests.pas',
  Atlas.Common.Dfm.Tests in 'Common\Dfm\Atlas.Common.Dfm.Tests.pas',
  Atlas.Common.Dfm.ComponentRename.Tests in 'Common\Dfm\Atlas.Common.Dfm.ComponentRename.Tests.pas',
  Atlas.Common.Dfm.FormModel.Tests in 'Common\Dfm\Atlas.Common.Dfm.FormModel.Tests.pas',
  Atlas.Common.Dfm.FormInfo.Tests in 'Common\Dfm\Atlas.Common.Dfm.FormInfo.Tests.pas',
  Atlas.Common.Dfm.BinaryForm.Tests in 'Common\Dfm\Atlas.Common.Dfm.BinaryForm.Tests.pas',
  Atlas.Common.Dfm.FormFiles.Tests in 'Common\Dfm\Atlas.Common.Dfm.FormFiles.Tests.pas',
  Atlas.Common.JsonRpc.LineTransport.Tests in 'Common\JsonRpc\Atlas.Common.JsonRpc.LineTransport.Tests.pas',
  Atlas.Common.Mcp.Server.Tests in 'Common\Mcp\Atlas.Common.Mcp.Server.Tests.pas',
  Atlas.Common.Mcp.IndexTools.Tests in 'Common\Mcp\Atlas.Common.Mcp.IndexTools.Tests.pas',
  Atlas.Common.Mcp.CodeTools.Tests in 'Common\Mcp\Atlas.Common.Mcp.CodeTools.Tests.pas',
  Atlas.Common.Lsp.PullDiagnostics.Tests in 'Common\Lsp\Atlas.Common.Lsp.PullDiagnostics.Tests.pas',
  Atlas.Common.Editing.Formatter.Tests in 'Common\Editing\Atlas.Common.Editing.Formatter.Tests.pas',
  Atlas.Common.Editing.CodeActions.Tests in 'Common\Editing\Atlas.Common.Editing.CodeActions.Tests.pas',
  Atlas.Core.Lsp.Client in '..\Packages\Atlas.IDE.Expert\Source\Core\Lsp\Atlas.Core.Lsp.Client.pas',
  Atlas.Core.Lsp.Session in '..\Packages\Atlas.IDE.Expert\Source\Core\Lsp\Atlas.Core.Lsp.Session.pas',
  Atlas.Core.Lsp.Adapters.ServerProcess in '..\Packages\Atlas.IDE.Expert\Source\Core\Lsp\Atlas.Core.Lsp.Adapters.ServerProcess.pas',
  Atlas.Core.Lsp.Tests in 'IDE.Expert\Atlas.Core.Lsp.Tests.pas',
  Atlas.Core.Completion.Contract in '..\Packages\Atlas.IDE.Expert\Source\Core\Completion\Atlas.Core.Completion.Contract.pas',
  Atlas.Core.Completion.Internals.Async in '..\Packages\Atlas.IDE.Expert\Source\Core\Completion\Internals\Atlas.Core.Completion.Internals.Async.pas',
  Atlas.Core.Completion.Composite in '..\Packages\Atlas.IDE.Expert\Source\Core\Completion\Atlas.Core.Completion.Composite.pas',
  Atlas.Core.Completion.Providers.Fixed in '..\Packages\Atlas.IDE.Expert\Source\Core\Completion\Providers\Atlas.Core.Completion.Providers.Fixed.pas',
  Atlas.Core.Completion.Providers.Server in '..\Packages\Atlas.IDE.Expert\Source\Core\Completion\Providers\Atlas.Core.Completion.Providers.Server.pas',
  Atlas.Core.Completion.Tests in 'IDE.Expert\Atlas.Core.Completion.Tests.pas',
  Atlas.Core.Completion.Matching in '..\Packages\Atlas.IDE.Expert\Source\Core\Completion\Atlas.Core.Completion.Matching.pas',
  Atlas.Core.Completion.Controller in '..\Packages\Atlas.IDE.Expert\Source\Core\Completion\Atlas.Core.Completion.Controller.pas',
  Atlas.Core.Completion.Controller.Tests in 'IDE.Expert\Atlas.Core.Completion.Controller.Tests.pas',
  Atlas.Core.Signature.Contract in '..\Packages\Atlas.IDE.Expert\Source\Core\Signature\Atlas.Core.Signature.Contract.pas',
  Atlas.Core.Hover.Contract in '..\Packages\Atlas.IDE.Expert\Source\Core\Hover\Atlas.Core.Hover.Contract.pas',
  Atlas.Core.Hover.History in '..\Packages\Atlas.IDE.Expert\Source\Core\Hover\Atlas.Core.Hover.History.pas',
  Atlas.Core.Hover.Tests in 'IDE.Expert\Atlas.Core.Hover.Tests.pas',
  Atlas.Core.Signature.CallScanner in '..\Packages\Atlas.IDE.Expert\Source\Core\Signature\Atlas.Core.Signature.CallScanner.pas',
  Atlas.Core.Signature.Controller in '..\Packages\Atlas.IDE.Expert\Source\Core\Signature\Atlas.Core.Signature.Controller.pas',
  Atlas.Core.Signature.Providers.Server in '..\Packages\Atlas.IDE.Expert\Source\Core\Signature\Atlas.Core.Signature.Providers.Server.pas',
  Atlas.Core.Signature.Tests in 'IDE.Expert\Atlas.Core.Signature.Tests.pas',
  Atlas.Core.Style.Color in '..\Packages\Atlas.IDE.Expert\Source\Core\Style\Atlas.Core.Style.Color.pas',
  Atlas.Core.Style.Palette in '..\Packages\Atlas.IDE.Expert\Source\Core\Style\Atlas.Core.Style.Palette.pas',
  Atlas.Core.Style.Syntax in '..\Packages\Atlas.IDE.Expert\Source\Core\Style\Atlas.Core.Style.Syntax.pas',
  Atlas.Core.Style.Scaling in '..\Packages\Atlas.IDE.Expert\Source\Core\Style\Atlas.Core.Style.Scaling.pas',
  Atlas.Core.Completion.Presentation in '..\Packages\Atlas.IDE.Expert\Source\Core\Completion\Atlas.Core.Completion.Presentation.pas',
  Atlas.Core.Completion.Word in '..\Packages\Atlas.IDE.Expert\Source\Core\Completion\Atlas.Core.Completion.Word.pas',
  Atlas.Core.Style.Tests in 'IDE.Expert\Atlas.Core.Style.Tests.pas',
  Atlas.Common.Pascal.XmlDoc.Tests in 'Common\Pascal\Atlas.Common.Pascal.XmlDoc.Tests.pas',
  Atlas.Common.Editing.UsesClause.Tests in 'Common\Editing\Atlas.Common.Editing.UsesClause.Tests.pas',
  Atlas.Common.Editing.UsesActions.Tests in 'Common\Editing\Atlas.Common.Editing.UsesActions.Tests.pas',
  Atlas.Common.Editing.UsesCommand.Tests in 'Common\Editing\Atlas.Common.Editing.UsesCommand.Tests.pas',
  Atlas.Common.Editing.SlashCommands.Tests in 'Common\Editing\Atlas.Common.Editing.SlashCommands.Tests.pas',
  Atlas.Common.Editing.DeclarationCommands.Tests in 'Common\Editing\Atlas.Common.Editing.DeclarationCommands.Tests.pas',
  Atlas.Common.Editing.ClassCommands.Tests in 'Common\Editing\Atlas.Common.Editing.ClassCommands.Tests.pas',
  Atlas.Common.Editing.WrapCommands.Tests in 'Common\Editing\Atlas.Common.Editing.WrapCommands.Tests.pas',
  Atlas.Common.Editing.MaintenanceCommands.Tests in 'Common\Editing\Atlas.Common.Editing.MaintenanceCommands.Tests.pas',
  Atlas.Common.Editing.TypeCommands.Tests in 'Common\Editing\Atlas.Common.Editing.TypeCommands.Tests.pas',
  Atlas.Common.Editing.CollectionCommands.Tests in 'Common\Editing\Atlas.Common.Editing.CollectionCommands.Tests.pas',
  Atlas.Common.Editing.UnitTemplates.Tests in 'Common\Editing\Atlas.Common.Editing.UnitTemplates.Tests.pas',
  Atlas.Common.Editing.ErrorCommands.Tests in 'Common\Editing\Atlas.Common.Editing.ErrorCommands.Tests.pas',
  Atlas.Common.Semantics.UnresolvedNames.Tests in 'Common\Semantics\Atlas.Common.Semantics.UnresolvedNames.Tests.pas',
  Atlas.Common.Rules.Builtin.Architecture.Tests in 'Common\Rules\Builtin\Atlas.Common.Rules.Builtin.Architecture.Tests.pas',
  Atlas.Common.Rules.Builtin.Concurrency.Tests in 'Common\Rules\Builtin\Atlas.Common.Rules.Builtin.Concurrency.Tests.pas',
  Atlas.Common.Rules.Builtin.Flow.Tests in 'Common\Rules\Builtin\Atlas.Common.Rules.Builtin.Flow.Tests.pas',
  Atlas.Common.Rules.Builtin.Unused.Tests in 'Common\Rules\Builtin\Atlas.Common.Rules.Builtin.Unused.Tests.pas',
  Atlas.Common.Rules.Builtin.Declarations.Tests in 'Common\Rules\Builtin\Atlas.Common.Rules.Builtin.Declarations.Tests.pas',
  Atlas.Common.Rules.Builtin.Inheritance.Tests in 'Common\Rules\Builtin\Atlas.Common.Rules.Builtin.Inheritance.Tests.pas',
  Atlas.Common.Rules.Builtin.Capture.Tests in 'Common\Rules\Builtin\Atlas.Common.Rules.Builtin.Capture.Tests.pas',
  Atlas.Common.Rules.Builtin.Components.Tests in 'Common\Rules\Builtin\Atlas.Common.Rules.Builtin.Components.Tests.pas',
  Atlas.Core.Settings.Plugin in '..\Packages\Atlas.IDE.Expert\Source\Core\Settings\Atlas.Core.Settings.Plugin.pas',
  Atlas.Core.Settings.Tests in 'IDE.Expert\Atlas.Core.Settings.Tests.pas',
  Atlas.Core.Completion.Ranking in '..\Packages\Atlas.IDE.Expert\Source\Core\Completion\Atlas.Core.Completion.Ranking.pas',
  Atlas.Core.Completion.Usage in '..\Packages\Atlas.IDE.Expert\Source\Core\Completion\Atlas.Core.Completion.Usage.pas',
  Atlas.Core.Completion.Ranking.Tests in 'IDE.Expert\Atlas.Core.Completion.Ranking.Tests.pas',
  Atlas.UI.Strings in '..\Packages\Atlas.IDE.Expert\Source\UI\Atlas.UI.Strings.pas',
  Atlas.UI.Strings.Tests in 'IDE.Expert\Atlas.UI.Strings.Tests.pas',
  Atlas.Core.Completion.Providers.XmlDoc in '..\Packages\Atlas.IDE.Expert\Source\Core\Completion\Providers\Atlas.Core.Completion.Providers.XmlDoc.pas',
  Atlas.Core.Completion.Parentheses in '..\Packages\Atlas.IDE.Expert\Source\Core\Completion\Atlas.Core.Completion.Parentheses.pas',
  Atlas.Core.Completion.Parentheses.Tests in 'IDE.Expert\Atlas.Core.Completion.Parentheses.Tests.pas',
  Atlas.Core.Completion.Preview in '..\Packages\Atlas.IDE.Expert\Source\Core\Completion\Atlas.Core.Completion.Preview.pas',
  Atlas.UI.Settings.Page in '..\Packages\Atlas.IDE.Expert\Source\UI\Settings\Atlas.UI.Settings.Page.pas',
  Atlas.UI.Settings.Page.Tests in 'IDE.Expert\Atlas.UI.Settings.Page.Tests.pas',
  Atlas.Core.Build.Events in '..\Packages\Atlas.IDE.Expert\Source\Core\Build\Atlas.Core.Build.Events.pas',
  Atlas.Core.Build.Events.Tests in 'IDE.Expert\Atlas.Core.Build.Events.Tests.pas',
  Atlas.Core.Diagnostics.Hangs in '..\Packages\Atlas.IDE.Expert\Source\Core\Diagnostics\Atlas.Core.Diagnostics.Hangs.pas',
  Atlas.Core.Diagnostics.Hangs.Tests in 'IDE.Expert\Atlas.Core.Diagnostics.Hangs.Tests.pas',
  Atlas.Core.Files.ExternalChanges in '..\Packages\Atlas.IDE.Expert\Source\Core\Files\Atlas.Core.Files.ExternalChanges.pas',
  Atlas.Core.Files.ExternalChanges.Tests in 'IDE.Expert\Atlas.Core.Files.ExternalChanges.Tests.pas',
  Atlas.Core.Commands.Palette in '..\Packages\Atlas.IDE.Expert\Source\Core\Commands\Atlas.Core.Commands.Palette.pas',
  Atlas.Core.Commands.Palette.Tests in 'IDE.Expert\Atlas.Core.Commands.Palette.Tests.pas',
  Atlas.Core.Editor.Pairs in '..\Packages\Atlas.IDE.Expert\Source\Core\Editor\Atlas.Core.Editor.Pairs.pas',
  Atlas.Core.Editor.Guides in '..\Packages\Atlas.IDE.Expert\Source\Core\Editor\Atlas.Core.Editor.Guides.pas',
  Atlas.Core.Problems.Contract in '..\Packages\Atlas.IDE.Expert\Source\Core\Problems\Atlas.Core.Problems.Contract.pas',
  Atlas.Core.Problems.Store in '..\Packages\Atlas.IDE.Expert\Source\Core\Problems\Atlas.Core.Problems.Store.pas',
  Atlas.Core.Problems.Tests in 'IDE.Expert\Atlas.Core.Problems.Tests.pas',
  Atlas.Core.Editor.Pairs.Tests in 'IDE.Expert\Atlas.Core.Editor.Pairs.Tests.pas',
  Atlas.Core.Build.Messages in '..\Packages\Atlas.IDE.Expert\Source\Core\Build\Atlas.Core.Build.Messages.pas',
  Atlas.Core.Build.Messages.Tests in 'IDE.Expert\Atlas.Core.Build.Messages.Tests.pas',
  Atlas.Common.Lsp.IdeBuild.Tests in 'Common\Lsp\Atlas.Common.Lsp.IdeBuild.Tests.pas',
  Atlas.Core.Build.CheckOnSave in '..\Packages\Atlas.IDE.Expert\Source\Core\Build\Atlas.Core.Build.CheckOnSave.pas',
  Atlas.Core.Build.CheckOnSave.Tests in 'IDE.Expert\Atlas.Core.Build.CheckOnSave.Tests.pas',
  Atlas.Common.Mcp.BuildTools.Tests in 'Common\Mcp\Atlas.Common.Mcp.BuildTools.Tests.pas',
  Atlas.Common.Mcp.Paths.Tests in 'Common\Mcp\Atlas.Common.Mcp.Paths.Tests.pas',
  Shell.Workspace in '..\Application\Source\Shell\Shell.Workspace.pas',
  Shell.Mcp in '..\Application\Source\Shell\Shell.Mcp.pas',
  Atlas.Common.Mcp.Freshness.Tests in 'Common\Mcp\Atlas.Common.Mcp.Freshness.Tests.pas',
  Shell.Mcp.Tests in 'Application\Shell\Shell.Mcp.Tests.pas',
  Atlas.Common.Rules.Builtin.FormFields.Tests in 'Common\Rules\Builtin\Atlas.Common.Rules.Builtin.FormFields.Tests.pas',
  Atlas.Common.Rules.Builtin.Security.Tests in 'Common\Rules\Builtin\Atlas.Common.Rules.Builtin.Security.Tests.pas',
  Atlas.Common.Rules.Builtin.General.Tests in 'Common\Rules\Builtin\Atlas.Common.Rules.Builtin.General.Tests.pas',
  Atlas.Common.Rules.Builtin.RtlPatterns.Tests in 'Common\Rules\Builtin\Atlas.Common.Rules.Builtin.RtlPatterns.Tests.pas',
  Atlas.Common.Rules.Builtin.RtlTypePatterns.Tests in 'Common\Rules\Builtin\Atlas.Common.Rules.Builtin.RtlTypePatterns.Tests.pas',
  Atlas.Common.Rules.Builtin.Exceptions.Tests in 'Common\Rules\Builtin\Atlas.Common.Rules.Builtin.Exceptions.Tests.pas',
  Atlas.Common.Rules.Builtin.Style.Tests in 'Common\Rules\Builtin\Atlas.Common.Rules.Builtin.Style.Tests.pas',
  Atlas.Common.Rules.Builtin.PaletteIcons.Tests in 'Common\Rules\Builtin\Atlas.Common.Rules.Builtin.PaletteIcons.Tests.pas',
  Atlas.Common.Rules.Builtin.Performance.Tests in 'Common\Rules\Builtin\Atlas.Common.Rules.Builtin.Performance.Tests.pas',
  Atlas.Common.Rules.ChangedFiles.Tests in 'Common\Rules\Atlas.Common.Rules.ChangedFiles.Tests.pas',
  Atlas.Common.Editing.RefactoringCommands.Tests in 'Common\Editing\Atlas.Common.Editing.RefactoringCommands.Tests.pas',
  Atlas.Common.Editing.ExpressionCommands.Tests in 'Common\Editing\Atlas.Common.Editing.ExpressionCommands.Tests.pas',
  Atlas.Common.Editing.Modernizer.Tests in 'Common\Editing\Atlas.Common.Editing.Modernizer.Tests.pas',
  Atlas.Common.Editing.DocComments.Tests in 'Common\Editing\Atlas.Common.Editing.DocComments.Tests.pas',
  Atlas.Common.Editing.MemberOrder.Tests in 'Common\Editing\Atlas.Common.Editing.MemberOrder.Tests.pas',
  Atlas.Common.Editing.ProjectCommands.Tests in 'Common\Editing\Atlas.Common.Editing.ProjectCommands.Tests.pas',
  Atlas.Common.Editing.SqlText.Tests in 'Common\Editing\Atlas.Common.Editing.SqlText.Tests.pas',
  Atlas.Common.Editing.DatabaseCommands.Tests in 'Common\Editing\Atlas.Common.Editing.DatabaseCommands.Tests.pas',
  Atlas.Common.Editing.Bookmarks.Tests in 'Common\Editing\Atlas.Common.Editing.Bookmarks.Tests.pas',
  Atlas.Common.Editing.DocumentationCommands.Tests in 'Common\Editing\Atlas.Common.Editing.DocumentationCommands.Tests.pas',
  Atlas.Common.Editing.ComponentCommands.Tests in 'Common\Editing\Atlas.Common.Editing.ComponentCommands.Tests.pas',
  Atlas.Common.Editing.WinApiCommands.Tests in 'Common\Editing\Atlas.Common.Editing.WinApiCommands.Tests.pas',
  Atlas.Common.Editing.TaskCommands.Tests in 'Common\Editing\Atlas.Common.Editing.TaskCommands.Tests.pas',
  Atlas.Common.Editing.RecordCommands.Tests in 'Common\Editing\Atlas.Common.Editing.RecordCommands.Tests.pas',
  Atlas.Common.Rules.Builtin.DataBinding.Tests in 'Common\Rules\Builtin\Atlas.Common.Rules.Builtin.DataBinding.Tests.pas',
  Atlas.Common.Rules.Builtin.DfmProperties.Tests in 'Common\Rules\Builtin\Atlas.Common.Rules.Builtin.DfmProperties.Tests.pas',
  Atlas.Common.Editing.PostfixTemplates.Tests in 'Common\Editing\Atlas.Common.Editing.PostfixTemplates.Tests.pas',
  Atlas.Common.Lsp.Completion.Postfix.Tests in 'Common\Lsp\Atlas.Common.Lsp.Completion.Postfix.Tests.pas';

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
