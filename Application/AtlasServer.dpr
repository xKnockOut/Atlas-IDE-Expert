program AtlasServer;

{$APPTYPE CONSOLE}

// 8 MB Stapel je Thread statt 1 MB (#1094). Netz, nicht Ursache: Seit Bericht M1
// laufen Prüfregeln, LSP und Editing iterativ über den Syntaxbaum, die Tiefe
// begrenzen Parser (MaxNesting) und Regel-Engine (MaxTreeDepth, mit Hinweis
// unit-too-deep). Belegt wird nur, was ein Thread wirklich braucht.
{$MAXSTACKSIZE $00800000}

uses
  // Muss als erste Unit stehen: zählt den Speicherrest beim Beenden (#177).
  Atlas.Common.Diagnostics.ShutdownLeaks,
  Atlas.Windows.Diagnostics.DebugOutput,
  Shell.Application in 'Source\Shell\Shell.Application.pas',
  Shell.Composition in 'Source\Shell\Shell.Composition.pas',
  Shell.Composition.Compile in 'Source\Shell\Shell.Composition.Compile.pas',
  Shell.Composition.Refactorings.Services in 'Source\Shell\Shell.Composition.Refactorings.Services.pas',
  Shell.Composition.Refactorings.Structure in 'Source\Shell\Shell.Composition.Refactorings.Structure.pas',
  Shell.Composition.Refactorings.Conversions in 'Source\Shell\Shell.Composition.Refactorings.Conversions.pas',
  Shell.Composition.Refactorings.Types in 'Source\Shell\Shell.Composition.Refactorings.Types.pas',
  Shell.Composition.Refactorings.Fixes in 'Source\Shell\Shell.Composition.Refactorings.Fixes.pas',
  Shell.Composition.Refactorings.Editing in 'Source\Shell\Shell.Composition.Refactorings.Editing.pas',
  Shell.Composition.Stepping in 'Source\Shell\Shell.Composition.Stepping.pas',
  Shell.Composition.Baselines in 'Source\Shell\Shell.Composition.Baselines.pas',
  Shell.Composition.Overviews in 'Source\Shell\Shell.Composition.Overviews.pas',
  Shell.Composition.Analysis in 'Source\Shell\Shell.Composition.Analysis.pas',
  Shell.Composition.Navigation in 'Source\Shell\Shell.Composition.Navigation.pas',
  Shell.Composition.Completion in 'Source\Shell\Shell.Composition.Completion.pas',
  Shell.Composition.Editing in 'Source\Shell\Shell.Composition.Editing.pas',
  Shell.Composition.EditorCommands in 'Source\Shell\Shell.Composition.EditorCommands.pas',
  Shell.Composition.ServerCommands in 'Source\Shell\Shell.Composition.ServerCommands.pas',
  Shell.Composition.CodeActions in 'Source\Shell\Shell.Composition.CodeActions.pas',
  Shell.Composition.Status in 'Source\Shell\Shell.Composition.Status.pas',
  Shell.Composition.Slash in 'Source\Shell\Shell.Composition.Slash.pas',
  Shell.Composition.Contract in 'Source\Shell\Shell.Composition.Contract.pas',
  Shell.Composition.UnitSearch in 'Source\Shell\Shell.Composition.UnitSearch.pas',
  Shell.Composition.TestUnits in 'Source\Shell\Shell.Composition.TestUnits.pas',
  Shell.Composition.Workspaces in 'Source\Shell\Shell.Composition.Workspaces.pas',
  Shell.Composition.Settings in 'Source\Shell\Shell.Composition.Settings.pas',
  Shell.Composition.RuleContext in 'Source\Shell\Shell.Composition.RuleContext.pas',
  Shell.Composition.Ide in 'Source\Shell\Shell.Composition.Ide.pas',
  Shell.Composition.Configuration in 'Source\Shell\Shell.Composition.Configuration.pas',
  Shell.Composition.FileChanges in 'Source\Shell\Shell.Composition.FileChanges.pas',
  Shell.Composition.Sources in 'Source\Shell\Shell.Composition.Sources.pas',
  Shell.Composition.Directives in 'Source\Shell\Shell.Composition.Directives.pas',
  Shell.Composition.FileOptions in 'Source\Shell\Shell.Composition.FileOptions.pas',
  Shell.Composition.Folders in 'Source\Shell\Shell.Composition.Folders.pas',
  Shell.Composition.CompileSetup in 'Source\Shell\Shell.Composition.CompileSetup.pas',
  Shell.Composition.Stdio in 'Source\Shell\Shell.Composition.Stdio.pas',
  Shell.Composition.AffectedTests in 'Source\Shell\Shell.Composition.AffectedTests.pas',
  Shell.Composition.DfmPropertyRules in 'Source\Shell\Shell.Composition.DfmPropertyRules.pas',
  Shell.Composition.Core in 'Source\Shell\Shell.Composition.Core.pas',
  Shell.Composition.AnalysisArea in 'Source\Shell\Shell.Composition.AnalysisArea.pas',
  Shell.Composition.CodeArea in 'Source\Shell\Shell.Composition.CodeArea.pas',
  Shell.Composition.CommandArea in 'Source\Shell\Shell.Composition.CommandArea.pas',
  Shell.Composition.DiagnosticsArea in 'Source\Shell\Shell.Composition.DiagnosticsArea.pas',
  Shell.Composition.Refactorings in 'Source\Shell\Shell.Composition.Refactorings.pas',
  Shell.CommandLine in 'Source\Shell\Shell.CommandLine.pas',
  Shell.Workspace in 'Source\Shell\Shell.Workspace.pas',
  Shell.Workspace.Listings in 'Source\Shell\Shell.Workspace.Listings.pas',
  Shell.Workspace.Setup in 'Source\Shell\Shell.Workspace.Setup.pas',
  Shell.Workspace.Packages in 'Source\Shell\Shell.Workspace.Packages.pas',
  Shell.Workspace.State in 'Source\Shell\Shell.Workspace.State.pas',
  Shell.Workspace.Build in 'Source\Shell\Shell.Workspace.Build.pas',
  Shell.Workspace.Cache in 'Source\Shell\Shell.Workspace.Cache.pas',
  Shell.Workspace.RuleProjects in 'Source\Shell\Shell.Workspace.RuleProjects.pas',
  Shell.Workspace.Loader in 'Source\Shell\Shell.Workspace.Loader.pas',
  Shell.Workspace.Requests in 'Source\Shell\Shell.Workspace.Requests.pas',
  Shell.Workspace.Encodings in 'Source\Shell\Shell.Workspace.Encodings.pas',
  Shell.Workspace.Jobs in 'Source\Shell\Shell.Workspace.Jobs.pas',
  Shell.Workspace.Indexing in 'Source\Shell\Shell.Workspace.Indexing.pas',
  Shell.WorkspaceGroup in 'Source\Shell\Shell.WorkspaceGroup.pas',
  Shell.Linter in 'Source\Shell\Shell.Linter.pas',
  Shell.Linter.Output in 'Source\Shell\Shell.Linter.Output.pas',
  Shell.Linter.Settings in 'Source\Shell\Shell.Linter.Settings.pas',
  Shell.Linter.Files in 'Source\Shell\Shell.Linter.Files.pas',
  Shell.Linter.Changes in 'Source\Shell\Shell.Linter.Changes.pas',
  Shell.Linter.Index in 'Source\Shell\Shell.Linter.Index.pas',
  Shell.Linter.Baseline in 'Source\Shell\Shell.Linter.Baseline.pas',
  Shell.Linter.Architecture in 'Source\Shell\Shell.Linter.Architecture.pas',
  Shell.Linter.Query in 'Source\Shell\Shell.Linter.Query.pas',
  Shell.Linter.Hotspots in 'Source\Shell\Shell.Linter.Hotspots.pas',
  Shell.Linter.Formatting in 'Source\Shell\Shell.Linter.Formatting.pas',
  Shell.Linter.AffectedTests in 'Source\Shell\Shell.Linter.AffectedTests.pas',
  Shell.Linter.Fix in 'Source\Shell\Shell.Linter.Fix.pas',
  Shell.Linter.Check in 'Source\Shell\Shell.Linter.Check.pas',
  Shell.Linter.Reports in 'Source\Shell\Shell.Linter.Reports.pas',
  Shell.SlashHost in 'Source\Shell\Shell.SlashHost.pas',
  Shell.VcsChanges in 'Source\Shell\Shell.VcsChanges.pas',
  Shell.AffectedTests in 'Source\Shell\Shell.AffectedTests.pas',
  Shell.Hotspots in 'Source\Shell\Shell.Hotspots.pas',
  Atlas.Core.Vcs.Contract in '..\Packages\Atlas.IDE.Base\Source\Core\Vcs\Atlas.Core.Vcs.Contract.pas',
  Atlas.Core.Vcs.Internals.Text in '..\Packages\Atlas.IDE.Base\Source\Core\Vcs\Atlas.Core.Vcs.Internals.Text.pas',
  Atlas.Core.Vcs.ServerAccess in '..\Packages\Atlas.IDE.Base\Source\Core\Vcs\Atlas.Core.Vcs.ServerAccess.pas',
  Atlas.Core.Vcs.Internals.GitParser in '..\Packages\Atlas.IDE.Base\Source\Core\Vcs\Atlas.Core.Vcs.Internals.GitParser.pas',
  Atlas.Core.Vcs.Internals.SvnParser in '..\Packages\Atlas.IDE.Base\Source\Core\Vcs\Atlas.Core.Vcs.Internals.SvnParser.pas',
  Atlas.Core.Vcs.Internals.SvnLayout in '..\Packages\Atlas.IDE.Base\Source\Core\Vcs\Atlas.Core.Vcs.Internals.SvnLayout.pas',
  Atlas.Core.Vcs.Internals.LineTrace in '..\Packages\Atlas.IDE.Base\Source\Core\Vcs\Atlas.Core.Vcs.Internals.LineTrace.pas',
  Atlas.Core.Vcs.Tools in '..\Packages\Atlas.IDE.Base\Source\Core\Vcs\Atlas.Core.Vcs.Tools.pas',
  Atlas.Core.Vcs.Providers.Git in '..\Packages\Atlas.IDE.Base\Source\Core\Vcs\Atlas.Core.Vcs.Providers.Git.pas',
  Atlas.Core.Vcs.Providers.Svn in '..\Packages\Atlas.IDE.Base\Source\Core\Vcs\Atlas.Core.Vcs.Providers.Svn.pas',
  Atlas.Core.Vcs.Providers.Null in '..\Packages\Atlas.IDE.Base\Source\Core\Vcs\Atlas.Core.Vcs.Providers.Null.pas',
  Atlas.Core.Vcs.Detection in '..\Packages\Atlas.IDE.Base\Source\Core\Vcs\Atlas.Core.Vcs.Detection.pas',
  Atlas.Core.Vcs.Composition in '..\Packages\Atlas.IDE.Base\Source\Core\Vcs\Atlas.Core.Vcs.Composition.pas',
  Atlas.Core.Vcs.Adapters.ProcessRunner in '..\Packages\Atlas.IDE.Base\Source\Core\Vcs\Atlas.Core.Vcs.Adapters.ProcessRunner.pas',
  Atlas.Core.Tracker.CommitHook in '..\Packages\Atlas.IDE.Tracker\Source\Core\Tracker\Atlas.Core.Tracker.CommitHook.pas',
  Shell.Mcp in 'Source\Shell\Shell.Mcp.pas',
  Shell.Mcp.Context in 'Source\Shell\Shell.Mcp.Context.pas',
  Shell.Mcp.Ide in 'Source\Shell\Shell.Mcp.Ide.pas',
  Shell.Mcp.Services in 'Source\Shell\Shell.Mcp.Services.pas',
  Shell.Mcp.Startup in 'Source\Shell\Shell.Mcp.Startup.pas',
  Shell.Mcp.Tools in 'Source\Shell\Shell.Mcp.Tools.pas',
  Shell.Mcp.NavigationTools in 'Source\Shell\Shell.Mcp.NavigationTools.pas',
  Shell.Mcp.BuildTestTools in 'Source\Shell\Shell.Mcp.BuildTestTools.pas',
  Shell.Mcp.CheckTools in 'Source\Shell\Shell.Mcp.CheckTools.pas',
  Shell.Mcp.ArchitectureTools in 'Source\Shell\Shell.Mcp.ArchitectureTools.pas',
  Shell.Mcp.EditingTools in 'Source\Shell\Shell.Mcp.EditingTools.pas',
  Shell.Mcp.ProjectTools in 'Source\Shell\Shell.Mcp.ProjectTools.pas',
  Shell.Mcp.ChangeTools in 'Source\Shell\Shell.Mcp.ChangeTools.pas',
  Shell.Mcp.Changes in 'Source\Shell\Shell.Mcp.Changes.pas',
  Shell.Diagnostics in 'Source\Shell\Shell.Diagnostics.pas',
  Shell.Bootstrap in 'Source\Shell\Shell.Bootstrap.pas',
  Shell.CrashCases in 'Source\Shell\Shell.CrashCases.pas',
  Shell.Replay in 'Source\Shell\Shell.Replay.pas',
  Shell.ReplayServer in 'Source\Shell\Shell.ReplayServer.pas',
  Shell.Commands.Build in 'Source\Shell\Shell.Commands.Build.pas',
  Shell.Commands.Index in 'Source\Shell\Shell.Commands.Index.pas',
  Shell.Compiler in 'Source\Shell\Shell.Compiler.pas',
  Shell.Platform in 'Source\Shell\Shell.Platform.pas';

// Atlas-Symbol (#751) als Programmsymbol (MAINICON).
{$R '..\Packages\Atlas.IDE.Base\Resources\Symbol\Atlas.Icon.res'}

// Speicherrest beim Beenden an den Debugger; die Zeile im Log (--log) schreibt
// TShutdownLeaks selbst. Kein ReportMemoryLeaksOnShutdown: dessen Dialog
// blockiert den unsichtbar gestarteten Server (#177).
procedure ReportShutdownLeak(ABytes: Int64);
begin
  TDebugOutput.Write(TShutdownLeaks.Describe(ABytes));
end;

begin
  {$IFDEF DEBUG}
  TShutdownLeaks.Enable(ReportShutdownLeak);
  {$ENDIF}
  ExitCode := TApplicationShell.Run;
end.
