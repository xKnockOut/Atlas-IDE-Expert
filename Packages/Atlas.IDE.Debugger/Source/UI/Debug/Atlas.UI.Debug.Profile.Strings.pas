unit Atlas.UI.Debug.Profile.Strings;

// Oberflächentexte des Profilers (#2057) im Modul Debugger, auf Deutsch und Englisch: Fenster „Atlas: Profil“,
// Befehle, Meldungen und Einstellungen. Die Sprache bestimmt Base (`TAtlasStrings.Language`); jeder Aufruf liest
// sie neu.

interface

{$SCOPEDENUMS ON}

type
  TAtlasProfileTextId = (
    ProfileWindowCommand, ProfileRunCommand, ProfileToggleCommand, ProfileCaption, ProfileRunsLabel, ProfileOwnOnly,
    ProfileCompare, ProfileStart, ProfileStop, ProfileReload, ProfileColumnMethod, ProfileColumnUnit,
    ProfileColumnSelf, ProfileColumnTotal, ProfileColumnLine, ProfileColumnBefore, ProfileColumnAfter,
    ProfileColumnChange, ProfileEmpty, ProfileSummary, ProfileCompareSummary, ProfileNoPrevious, ProfileRunning,
    ProfileOff, ProfileNoProject, ProfileBuildFailed, ProfileNoExe, ProfileStartFailed, ProfileNoProcess,
    ProfileServerFailed, ProfileStarted, ProfileNoMap, ProfileStopped, ProfileUnreadable, ProfileNoSource,
    SettingsDebugProfiler, SettingsDebugProfilerInterval);

  TAtlasProfileStrings = class
  public
    class function Text(AId: TAtlasProfileTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TAtlasProfileTextId; const AArgs: array of const): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Strings;

const
  cTexts: array[TAtlasLanguage, TAtlasProfileTextId] of string = (
    ('Profil',
     'Mit Profil ausführen',
     'Profil starten/beenden',
     'Atlas: Profil',
     'Lauf:',
     'Nur eigener Code',
     'Mit vorigem Lauf vergleichen',
     'Profil starten',
     'Profil beenden',
     'Neu laden',
     'Methode',
     'Unit',
     'Eigen',
     'Gesamt',
     'Heißeste Zeile',
     'Vorher',
     'Nachher',
     'Änderung',
     'Noch kein Lauf. „Mit Profil ausführen“ startet das aktive Projekt und misst es.',
     '%s · %d Proben · %s s · alle %d ms',
     'Vergleich: %s (vorher) mit %s (nachher)',
     'Es gibt keinen früheren Lauf zum Vergleichen.',
     'Atlas: Profil läuft für Prozess %d (%s s, %d Proben).',
     'Der Profiler ist ausgeschaltet (Tools › Optionen › Atlas › Debuggen, experimentell).',
     'Atlas: Kein aktives Projekt mit Programm.',
     'Atlas: Das Projekt %s ließ sich nicht übersetzen.',
     'Atlas: Das Programm %s fehlt.',
     'Atlas: %s ließ sich nicht starten.',
     'Atlas: Kein laufendes Programm im Debugger. „Mit Profil ausführen“ startet das aktive Projekt ohne Debugger.',
     'Atlas: Der Server konnte das Profil nicht starten oder beenden (läuft schon ein Profil, oder fehlt der Zugriff auf den Prozess?). Details im Protokoll des Servers.',
     'Atlas: Profil gestartet für Prozess %d, alle %d ms.',
     'Atlas: Keine Map-Datei gefunden. Ohne sie zeigt das Profil nur Module; Projektoptionen › Linker › Map-Datei = Detailliert.',
     'Atlas: Profil beendet: %s (%d Proben).',
     'Atlas: Die Profildatei %s ist nicht lesbar.',
     'Atlas: Zu %s gibt es keinen Quelltext.',
     'Profiler (Fenster „Atlas: Profil“, experimentell)',
     'Abstand der Proben in ms:'),
    ('Profile',
     'Run with profile',
     'Start/stop profile',
     'Atlas: Profile',
     'Run:',
     'Own code only',
     'Compare with previous run',
     'Start profile',
     'Stop profile',
     'Reload',
     'Method',
     'Unit',
     'Self',
     'Total',
     'Hottest line',
     'Before',
     'After',
     'Change',
     'No run yet. “Run with profile” starts the active project and samples it.',
     '%s · %d samples · %s s · every %d ms',
     'Comparison: %s (before) with %s (after)',
     'There is no earlier run to compare with.',
     'Atlas: Profile running for process %d (%s s, %d samples).',
     'The profiler is turned off (Tools › Options › Atlas › Debugging, experimental).',
     'Atlas: No active project with a program.',
     'Atlas: The project %s could not be built.',
     'Atlas: The program %s is missing.',
     'Atlas: %s could not be started.',
     'Atlas: No program running in the debugger. “Run with profile” starts the active project without the debugger.',
     'Atlas: The server could not start or stop the profile (is a profile already running, or is access to the process missing?). Details in the server log.',
     'Atlas: Profile started for process %d, every %d ms.',
     'Atlas: No map file found. Without it the profile shows modules only; Project options › Linker › Map file = Detailed.',
     'Atlas: Profile finished: %s (%d samples).',
     'Atlas: The profile file %s cannot be read.',
     'Atlas: There is no source for %s.',
     'Profiler (window “Atlas: Profile”, experimental)',
     'Interval between samples in ms:'));

{ TAtlasProfileStrings }

class function TAtlasProfileStrings.Text(AId: TAtlasProfileTextId): string;
begin
  Result := cTexts[TAtlasStrings.Language, AId];
end;

class function TAtlasProfileStrings.Fmt(AId: TAtlasProfileTextId; const AArgs: array of const): string;
begin
  Result := Format(cTexts[TAtlasStrings.Language, AId], AArgs);
end;

end.
