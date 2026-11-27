program AtlasMonitor;

{$R *.res}
// Eigenständiges Fenster für alle laufenden Atlas-Server mit Symbol im Infobereich (#1901), später auch für
// Prüfläufe ohne IDE (#1900). Einstieg in Shell.Monitor, Fenster in Monitor.MainForm, Logik in
// Atlas.Common.Monitor.*, Windows-Zugriffe in Atlas.Windows.Monitor.Adapters.*.

uses
  Core.Bootstrap in 'Source\Core\Core.Bootstrap.pas',
  Shell.Monitor in 'Source\Shell\Shell.Monitor.pas',
  Monitor.MainForm in 'Source\Features\Monitor\Monitor.MainForm.pas',
  Monitor.CheckOptions in 'Source\Features\Monitor\Monitor.CheckOptions.pas',
  Monitor.CheckPage in 'Source\Features\Monitor\Monitor.CheckPage.pas',
  Monitor.AssistantsPage in 'Source\Features\Monitor\Monitor.AssistantsPage.pas',
  Monitor.ReportPage in 'Source\Features\Monitor\Monitor.ReportPage.pas';

// Atlas-Symbol (#751) als Programmsymbol (MAINICON).
{$R '..\Packages\Atlas.IDE.Base\Resources\Symbol\Atlas.Icon.res'}

begin
  ExitCode := TMonitorShell.Run;
end.
