program BetterDelphiLSP;

{$APPTYPE CONSOLE}

uses
  Shell.Application in 'Source\Shell\Shell.Application.pas',
  Shell.Composition in 'Source\Shell\Shell.Composition.pas',
  Shell.CommandLine in 'Source\Shell\Shell.CommandLine.pas',
  Shell.Workspace in 'Source\Shell\Shell.Workspace.pas',
  Shell.Linter in 'Source\Shell\Shell.Linter.pas',
  Shell.GitChanges in 'Source\Shell\Shell.GitChanges.pas',
  Shell.Mcp in 'Source\Shell\Shell.Mcp.pas';

begin
  // Lecks beim Beenden melden; der Bericht geht nicht auf stdout.
  {$IFDEF DEBUG}
  ReportMemoryLeaksOnShutdown := True;
  {$ENDIF}
  ExitCode := TApplicationShell.Run;
end.
