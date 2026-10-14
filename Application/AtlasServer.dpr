program AtlasServer;

{$APPTYPE CONSOLE}

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
  Shell.Mcp in 'Source\Shell\Shell.Mcp.pas',
  Shell.Diagnostics in 'Source\Shell\Shell.Diagnostics.pas';

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
