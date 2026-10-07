program BetterDelphiLSP;

{$APPTYPE CONSOLE}

uses
  Shell.Application in 'Source\Shell\Shell.Application.pas',
  Shell.Composition in 'Source\Shell\Shell.Composition.pas',
  Shell.CommandLine in 'Source\Shell\Shell.CommandLine.pas';

begin
  ExitCode := TApplicationShell.Run;
end.
