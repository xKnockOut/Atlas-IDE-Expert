unit Atlas.UI.Tracker.Flow.Strings;

// Oberflächentexte des Trackers für Ablauf-Karte (Atlas-Ablauf), auf Deutsch und Englisch (#1455). Die
// Sprache bestimmt Base (`TAtlasStrings.Language`); jeder Aufruf liest sie neu.

interface

{$SCOPEDENUMS ON}

type
  TAtlasFlowTextId = (FlowCaption, FlowRefresh, FlowLoading, FlowSummary, FlowTruncated, FlowOffline, FlowNoTracker,
    FlowEmpty, FlowAverage, FlowNoAverage, FlowOpen, FlowMine, FlowStuckMark, FlowEnd, FlowStuckTitle,
    FlowStuckFilter, FlowNoStuck, FlowColumnKey, FlowColumnTitle, FlowColumnState, FlowColumnSince,
    FlowColumnAssignee, FlowDays, FlowDaysBefore);

  TAtlasFlowStrings = class
  public
    class function Text(AId: TAtlasFlowTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TAtlasFlowTextId; const AArgs: array of const): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Strings;

const
  cTexts: array[TAtlasLanguage, TAtlasFlowTextId] of string = (
    ('Atlas-Ablauf',
     'Aktualisieren',
     'Wird geladen …',
     '%s · %d Tage · %d Issues · %d Wechsel',
     ' · unvollständig (Grenze erreicht)',
     'Stand vom %s · %s',
     'Die Ablauf-Karte gibt es für YouTrack mit eingetragenem Projektkürzel.',
     'Keine Zustände im Zeitraum.',
     '⌀ %s Tage',
     '⌀ –',
     '%d offen',
     ' · %d ich',
     ' · %d lange',
     'Ende',
     'Liegt lange (ab %d Tagen)',
     'Liegt lange in „%s“ (ab %d Tagen) · Klick auf den Zustand zeigt wieder alle',
     'nichts',
     'Kennung',
     'Titel',
     'Zustand',
     'seit',
     'Zuständig',
     '%d Tagen',
     'über %d Tagen'),
    ('Atlas Flow',
     'Refresh',
     'Loading…',
     '%s · %d days · %d issues · %d changes',
     ' · incomplete (limit reached)',
     'As of %s · %s',
     'The flow map needs YouTrack with a project key.',
     'No states in this period.',
     '⌀ %s days',
     '⌀ –',
     '%d open',
     ' · %d mine',
     ' · %d stuck',
     'End',
     'Stuck (%d days or more)',
     'Stuck in “%s” (%d days or more) · click the state again to show all',
     'none',
     'Key',
     'Title',
     'State',
     'Since',
     'Assignee',
     '%d days',
     'over %d days'));

{ TAtlasFlowStrings }

class function TAtlasFlowStrings.Text(AId: TAtlasFlowTextId): string;
begin
  Result := cTexts[TAtlasStrings.Language, AId];
end;

class function TAtlasFlowStrings.Fmt(AId: TAtlasFlowTextId; const AArgs: array of const): string;
begin
  Result := Format(cTexts[TAtlasStrings.Language, AId], AArgs);
end;

end.
