unit Atlas.Common.Monitor.Texts;

// Texte der Oberfläche von AtlasMonitor (#1901) in Deutsch und Englisch: Fenster, Reiter „Server“, Kontextmenü des
// Symbols im Infobereich, Rückfragen und Meldungen. Die Sprache wählt TMonitorSettings.LanguageOf beim Start.

interface

type
  {$SCOPEDENUMS ON}
  TMonitorText = (Caption, TabServers, StopServer, OpenLog, OpenLogFolder, ClearCache, OpenWindow, StopAllServers,
    StartWithWindows, TrayIcon, ExitProgram, MenuFile, MenuSettings, NoServers, SelectServer, ConfirmStop,
    ConfirmStopAll, StopFailed, CacheCleared, AutostartFailed, SaveFailed, CloseToTray);
  {$SCOPEDENUMS OFF}

  TMonitorTexts = record
  public
    class function Text(AText: TMonitorText): string; static;
    class function Fmt(AText: TMonitorText; const AArgs: array of const): string; static;
  end;

implementation

uses
  Atlas.Common.Localization.Texts;

const
  cTexts: array[TMonitorText] of TAtlasText = (
    (De: 'Atlas Monitor'; En: 'Atlas Monitor'),
    (De: 'Server'; En: 'Servers'),
    (De: 'Server beenden'; En: 'Stop server'),
    (De: 'Protokoll öffnen'; En: 'Open log'),
    (De: 'Protokollordner öffnen'; En: 'Open log folder'),
    (De: 'Index-Cache leeren'; En: 'Clear index cache'),
    (De: 'Fenster öffnen'; En: 'Open window'),
    (De: 'Alle Server beenden'; En: 'Stop all servers'),
    (De: 'Mit Windows starten'; En: 'Start with Windows'),
    (De: 'Symbol im Infobereich'; En: 'Icon in the notification area'),
    (De: 'Beenden'; En: 'Exit'),
    (De: '&Datei'; En: '&File'),
    (De: '&Einstellungen'; En: '&Settings'),
    (De: 'Keine laufenden Server'; En: 'No running servers'),
    (De: 'Einen Server in der Liste wählen.'; En: 'Select a server in the list.'),
    (De: 'Server %d beenden? Die IDE startet ihren Server bei Bedarf neu.';
     En: 'Stop server %d? The IDE restarts its server when needed.'),
    (De: 'Alle %d Atlas-Server beenden?'; En: 'Stop all %d Atlas servers?'),
    (De: 'Server %d ließ sich nicht beenden.'; En: 'Could not stop server %d.'),
    (De: '%d Index-Caches gelöscht; Caches laufender Server bleiben.';
     En: '%d index caches deleted; caches of running servers remain.'),
    (De: 'Der Start mit Windows ließ sich nicht ändern.'; En: 'Could not change the start with Windows.'),
    (De: 'Die Einstellungen ließen sich nicht speichern (%s).'; En: 'Could not save the settings (%s).'),
    (De: 'Atlas Monitor läuft im Infobereich weiter.'; En: 'Atlas Monitor keeps running in the notification area.'));

class function TMonitorTexts.Text(AText: TMonitorText): string;
begin
  Result := cTexts[AText].Text;
end;

class function TMonitorTexts.Fmt(AText: TMonitorText; const AArgs: array of const): string;
begin
  Result := cTexts[AText].Fmt(AArgs);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Monitor.Texts', cTexts);

end.
