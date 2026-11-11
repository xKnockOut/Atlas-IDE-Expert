unit Atlas.UI.Status.Strings;

// Oberflächentexte des Features Statusfenster auf Deutsch und Englisch. Die Sprache bestimmt
// `TAtlasStrings.Language`; jeder Aufruf liest sie neu. Eigene Unit, damit ein neuer Text des Features nicht
// `Atlas.UI.Strings` ändert, die fast der ganze Kern verwendet; dort bleiben gemeinsame Texte.

interface

{$SCOPEDENUMS ON}

type
  TAtlasStatusTextId = (
    ServerWindowCaption, ServerWindowNoServer, ServerWindowWaiting, ServerWindowOldServer, ServerWindowHeader,
    ServerStateUnknown, ServerStateLoading, ServerStateReady, ServerStateChecking, ServerWindowQueue,
    ServerWindowCacheHits, ServerWindowUnknownValue, ServerMemorySymbols, ServerMemoryUsages, ServerMemoryLibrary,
    ServerMemoryTrees, ServerMemoryDocuments, ServerMemoryPackages, ServerMemoryRest, ServerMemoryTotal,
    ServerWindowBudget, ServerWindowNoBudget, ServerWindowOverBudget, ServerWindowCheckRun,
    ServerWindowCheckRunning, ServerWindowNoCheckRun, ServerColumnUnit, ServerColumnMs, ServerColumnRule,
    ServerColumnCalls, ServerColumnRequest, ServerColumnCount, ServerColumnAverage, ServerColumnMax,
    ServerColumnFailed, ServerWindowRefresh, ServerWindowRebuild, ServerWindowPackage, ServerWindowUpdated,
    ServerWindowHint);

  TAtlasStatusStrings = class
  public
    class function Text(AId: TAtlasStatusTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TAtlasStatusTextId; const AArgs: array of const): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Strings;

const
  cTexts: array[TAtlasLanguage, TAtlasStatusTextId] of string = (
    ('Atlas-Server',
     'Der Atlas-Server läuft nicht.',
     'Warte auf den Status des Servers …',
     'Dieser Server liefert noch keine Diagnose; gezeigt werden Units, Speicher und Anfragen.',
     'Prozess %d · Version %s · läuft seit %s · %s · Neustarts in dieser Sitzung: %d',
     'unbekannt',
     'lädt',
     'bereit',
     'prüft',
     'Warteschlange: Index %d wartend, %d läuft · Prüfung %d wartend, %d läuft · älteste Wartezeit %s',
     'Cache-Treffer: Index %s · Syntaxbäume %s · %d Units im Index',
     '–',
     'Symbole',
     'Verwendungen',
     'Bibliotheks-Units',
     'Syntaxbäume',
     'Offene Dokumente',
     'Packages (.dcp)',
     'Rest',
     'Prozess gesamt',
     'Budget %s',
     'ohne Budget',
     'Budget überschritten: Verwendungen werden ausgelagert.',
     'Letzter Prüflauf %s: %d Units in %s',
     'Prüflauf läuft: %d Units bisher',
     'Noch kein Prüflauf in dieser Sitzung.',
     'Langsamste Units',
     'ms',
     'Langsamste Regeln',
     'Aufrufe',
     'Langsamste Anfragen',
     'Anzahl',
     'Mittel ms',
     'Maximum ms',
     'Fehler',
     'Aktualisieren',
     'Index neu aufbauen',
     'Diagnosepaket erstellen …',
     'Stand %s',
     'Doppelklick auf eine Unit öffnet sie, auf eine Regel ihre Einstellungen.'),
    ('Atlas server',
     'The Atlas server is not running.',
     'Waiting for the server status …',
     'This server does not report diagnostics yet; showing units, memory and requests.',
     'Process %d · version %s · up %s · %s · restarts this session: %d',
     'unknown',
     'loading',
     'ready',
     'checking',
     'Queue: index %d waiting, %d running · check %d waiting, %d running · oldest wait %s',
     'Cache hits: index %s · syntax trees %s · %d units in the index',
     '–',
     'Symbols',
     'Usages',
     'Library units',
     'Syntax trees',
     'Open documents',
     'Packages (.dcp)',
     'Other',
     'Process total',
     'Budget %s',
     'no budget',
     'Budget exceeded: usages are being offloaded.',
     'Last check run %s: %d units in %s',
     'Check run in progress: %d units so far',
     'No check run in this session yet.',
     'Slowest units',
     'ms',
     'Slowest rules',
     'Calls',
     'Slowest requests',
     'Count',
     'Average ms',
     'Maximum ms',
     'Failed',
     'Refresh',
     'Rebuild index',
     'Create diagnostic package …',
     'As of %s',
     'Double-click a unit to open it, a rule to open its settings.'));

{ TAtlasStatusStrings }

class function TAtlasStatusStrings.Text(AId: TAtlasStatusTextId): string;
begin
  Result := cTexts[TAtlasStrings.Language, AId];
end;

class function TAtlasStatusStrings.Fmt(AId: TAtlasStatusTextId; const AArgs: array of const): string;
begin
  Result := Format(Text(AId), AArgs);
end;

end.
