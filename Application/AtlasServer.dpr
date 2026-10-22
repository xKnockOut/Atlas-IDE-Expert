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
  Shell.CommandLine in 'Source\Shell\Shell.CommandLine.pas',
  Shell.Workspace in 'Source\Shell\Shell.Workspace.pas',
  Shell.Linter in 'Source\Shell\Shell.Linter.pas',
  Shell.SlashHost in 'Source\Shell\Shell.SlashHost.pas',
  Shell.VcsChanges in 'Source\Shell\Shell.VcsChanges.pas',
  Atlas.Core.Vcs.Contract in '..\Packages\Atlas.IDE.Expert\Source\Core\Vcs\Atlas.Core.Vcs.Contract.pas',
  Atlas.Core.Vcs.Internals.Text in '..\Packages\Atlas.IDE.Expert\Source\Core\Vcs\Atlas.Core.Vcs.Internals.Text.pas',
  Atlas.Core.Vcs.Internals.GitParser in '..\Packages\Atlas.IDE.Expert\Source\Core\Vcs\Atlas.Core.Vcs.Internals.GitParser.pas',
  Atlas.Core.Vcs.Internals.SvnParser in '..\Packages\Atlas.IDE.Expert\Source\Core\Vcs\Atlas.Core.Vcs.Internals.SvnParser.pas',
  Atlas.Core.Vcs.Tools in '..\Packages\Atlas.IDE.Expert\Source\Core\Vcs\Atlas.Core.Vcs.Tools.pas',
  Atlas.Core.Vcs.Providers.Git in '..\Packages\Atlas.IDE.Expert\Source\Core\Vcs\Atlas.Core.Vcs.Providers.Git.pas',
  Atlas.Core.Vcs.Providers.Svn in '..\Packages\Atlas.IDE.Expert\Source\Core\Vcs\Atlas.Core.Vcs.Providers.Svn.pas',
  Atlas.Core.Vcs.Providers.Null in '..\Packages\Atlas.IDE.Expert\Source\Core\Vcs\Atlas.Core.Vcs.Providers.Null.pas',
  Atlas.Core.Vcs.Detection in '..\Packages\Atlas.IDE.Expert\Source\Core\Vcs\Atlas.Core.Vcs.Detection.pas',
  Atlas.Core.Vcs.Composition in '..\Packages\Atlas.IDE.Expert\Source\Core\Vcs\Atlas.Core.Vcs.Composition.pas',
  Atlas.Core.Vcs.Adapters.ProcessRunner in '..\Packages\Atlas.IDE.Expert\Source\Core\Vcs\Atlas.Core.Vcs.Adapters.ProcessRunner.pas',
  Shell.Mcp in 'Source\Shell\Shell.Mcp.pas',
  Shell.Diagnostics in 'Source\Shell\Shell.Diagnostics.pas',
  Shell.Bootstrap in 'Source\Shell\Shell.Bootstrap.pas',
  Shell.Commands.Build in 'Source\Shell\Shell.Commands.Build.pas',
  Shell.Commands.Index in 'Source\Shell\Shell.Commands.Index.pas',
  Shell.Compiler in 'Source\Shell\Shell.Compiler.pas';

// Atlas-Symbol (#751) als Programmsymbol (MAINICON).
{$R '..\Packages\Atlas.IDE.Expert\Resources\Symbol\Atlas.Icon.res'}

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
