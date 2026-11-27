program AtlasMonitor;

{$R *.res}
// Eigenständiges Fenster für alle laufenden Atlas-Server mit Symbol im Infobereich (#1901), später auch für
// Prüfläufe ohne IDE (#1900). Einstieg in Shell.Monitor, Fenster in Monitor.Hosting.MainForm, Logik in
// Atlas.Common.Monitor.*, Windows-Zugriffe in Atlas.Windows.Monitor.Adapters.*.

uses
  Core.Bootstrap in 'Source\Core\Core.Bootstrap.pas',
  Shell.Monitor in 'Source\Shell\Shell.Monitor.pas',
  Monitor.Hosting.MainForm in 'Source\Features\Monitor\Monitor.Hosting.MainForm.pas',
  Monitor.Hosting.CheckOptions in 'Source\Features\Monitor\Monitor.Hosting.CheckOptions.pas',
  Monitor.Hosting.CheckPage in 'Source\Features\Monitor\Monitor.Hosting.CheckPage.pas',
  Monitor.Hosting.AssistantsPage in 'Source\Features\Monitor\Monitor.Hosting.AssistantsPage.pas',
  Monitor.Hosting.ReportPage in 'Source\Features\Monitor\Monitor.Hosting.ReportPage.pas';

// Atlas-Symbol (#751) als Programmsymbol (MAINICON).
{$R '..\Packages\Atlas.IDE.Base\Resources\Symbol\Atlas.Icon.res'}

begin
  ExitCode := TMonitorShell.Run;
end.
