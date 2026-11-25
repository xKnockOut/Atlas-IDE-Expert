program AtlasUpdate;

{$R *.res}
{$APPTYPE CONSOLE}

// Installer und Updater von Atlas (#1519): Erstinstallation aus dem
// entpackten Release-Paket (install) und Updates aus dem Plugin (prepare,
// apply). Ablauf und Prüfungen in Atlas.Common.Updates.*, Windows-Zugriffe in
// Atlas.Windows.Updates.Adapters.*.

uses
  Core.Bootstrap in 'Source\Core\Core.Bootstrap.pas',
  Shell.Update in 'Source\Shell\Shell.Update.pas',
  Shell.Update.System in 'Source\Shell\Shell.Update.System.pas',
  Update.Install in 'Source\Features\Update\Update.Install.pas';

begin
  ExitCode := TShellUpdate.Run;
end.
