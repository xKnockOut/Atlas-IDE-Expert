unit Atlas.UI.StatusBar.Strings;

// Oberflächentexte des Features Statusleiste auf Deutsch und Englisch. Die Sprache bestimmt
// `TAtlasStrings.Language`; jeder Aufruf liest sie neu. Eigene Unit, damit ein neuer Text des Features nicht
// `Atlas.UI.Strings` ändert, die fast der ganze Kern verwendet; dort bleiben gemeinsame Texte.

interface

{$SCOPEDENUMS ON}

type
  TAtlasStatusBarTextId = (
    StatusBarCustomize, StatusBarItemStatus, StatusBarItemFindings, StatusBarItemLiveCheck, StatusBarItemMethod,
    StatusBarHide, StatusBarLive, StatusBarOnSave, StatusBarChecking, StatusBarCheckedAgo, StatusBarSeconds,
    StatusBarMinutes, StatusBarHours, StatusBarLines, StatusBarCyclomatic, StatusBarLimit, StatusBarFindingsHint,
    StatusBarLiveOnHint, StatusBarLiveOffHint, StatusBarLastCheck, StatusBarMethodJump, StatusBarNoMethod,
    StatusBarNoFindingOfKind, StatusBarStatusClicks, StatusBarReady, StatusBarRecheckClick, StatusBarRechecking,
    StatusBarProjectProgress, StatusBarPausedDebugger, StatusBarProjectDone, StatusBarProjectPaused,
    StatusBarStatusServer, StatusBarManual, StatusBarLiveManualHint, StatusBarCheckFileClick);

  TAtlasStatusBarStrings = class
  public
    class function Text(AId: TAtlasStatusBarTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TAtlasStatusBarTextId; const AArgs: array of const): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Strings;

const
  cTexts: array[TAtlasLanguage, TAtlasStatusBarTextId] of string = (
    ('Leiste anpassen …',
     'Server-Status',
     'Meldungen dieser Unit',
     'Live-Prüfung',
     'Aktuelle Methode',
     'Statusleiste ausblenden',
     'live',
     'beim Speichern',
     'prüft …',
     'geprüft vor %s',
     '%d s',
     '%d min',
     '%d h',
     '%d Zeilen',
     'CC %d',
     '%s (Grenze %d)',
     'In dieser Unit: %d Fehler, %d Warnungen, %d Hinweise. Klick: nächster Befund dieser Art, Doppelklick: ' +
     '„Atlas-Prüfung“ für diese Unit.',
     'Prüft beim Tippen nach der Verzögerung problems.liveDelayMs (problems.update live).',
     'Prüft erst nach dem Speichern (problems.update save).',
     'Letzte Prüfung: %s in %d ms um %s',
     'Klick: zum Methodenkopf',
     'keine Methode',
     'Keine Befunde dieser Art in der Unit.',
     'Klick: Atlas-Status · Rechtsklick: Schnellschalter',
     'bereit',
     'Klick: alle Units neu prüfen',
     'Atlas prüft alle Units neu …',
     'Projekt %d %%',
     'angehalten (Debugger)',
     'Projekt fertig',
     'pausiert (Kompilieren)',
     'Doppelklick: Fenster „Atlas-Server“',
     'manuell',
     'Prüft nur auf Anforderung (problems.update manual).',
     'Klick: Datei jetzt prüfen'),
    ('Customize bar …',
     'Server status',
     'Findings in this unit',
     'Live check',
     'Current method',
     'Hide status bar',
     'live',
     'on save',
     'checking …',
     'checked %s ago',
     '%d s',
     '%d min',
     '%d h',
     '%d lines',
     'CC %d',
     '%s (limit %d)',
     'In this unit: %d errors, %d warnings, %d hints. Click: next finding of this kind, double-click: ' +
     '“Atlas Findings” for this unit.',
     'Checks while you type after the delay problems.liveDelayMs (problems.update live).',
     'Checks only after saving (problems.update save).',
     'Last check: %s in %d ms at %s',
     'Click: go to the method header',
     'no method',
     'No findings of this kind in this unit.',
     'Click: Atlas status · Right-click: quick toggles',
     'ready',
     'Click: check all units again',
     'Atlas is checking all units again …',
     'project %d %%',
     'paused (debugger)',
     'project done',
     'paused (compiling)',
     'Double-click: “Atlas server” window',
     'manual',
     'Checks only on request (problems.update manual).',
     'Click: check this file now'));

{ TAtlasStatusBarStrings }

class function TAtlasStatusBarStrings.Text(AId: TAtlasStatusBarTextId): string;
begin
  Result := cTexts[TAtlasStrings.Language, AId];
end;

class function TAtlasStatusBarStrings.Fmt(AId: TAtlasStatusBarTextId; const AArgs: array of const): string;
begin
  Result := Format(Text(AId), AArgs);
end;

end.
