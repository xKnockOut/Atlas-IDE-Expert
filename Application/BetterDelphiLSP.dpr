program BetterDelphiLSP;

{$APPTYPE CONSOLE}

uses
  Shell.Application in 'Source\Shell\Shell.Application.pas';

begin
  ExitCode := TApplicationShell.Run;
end.
