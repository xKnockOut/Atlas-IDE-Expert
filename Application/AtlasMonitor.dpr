program AtlasMonitor;

// Eigenständiges Fenster für alle laufenden Atlas-Server mit Symbol im Infobereich (#1901), später auch für
// Prüfläufe ohne IDE (#1900). Einstieg in Shell.Monitor, Fenster in Shell.Monitor.MainForm, Logik in
// Atlas.Common.Monitor.*, Windows-Zugriffe in Atlas.Windows.Monitor.Adapters.*.

uses
  Shell.Bootstrap in 'Source\Shell\Shell.Bootstrap.pas',
  Shell.Monitor in 'Source\Shell\Shell.Monitor.pas',
  Shell.Monitor.MainForm in 'Source\Shell\Shell.Monitor.MainForm.pas';

// Atlas-Symbol (#751) als Programmsymbol (MAINICON).
{$R '..\Packages\Atlas.IDE.Base\Resources\Symbol\Atlas.Icon.res'}

begin
  ExitCode := TMonitorShell.Run;
end.
