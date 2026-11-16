unit Atlas.UI.Debug.MethodBreakpoints.Strings;

// Texte der Methodenhaltepunkte und ihrer Gruppen, auf Deutsch und Englisch (#1455). Die Sprache bestimmt Base
// (`TAtlasStrings.Language`); jeder Aufruf liest sie neu.

interface

{$SCOPEDENUMS ON}

type
  TAtlasMethodBreakpointsTextId = (
    MethodBreakpointsTitle, MethodBreakpointsPattern, MethodBreakpointsPatternHint, MethodBreakpointsSearch,
    MethodBreakpointsOverrides, MethodBreakpointsOverloads, MethodBreakpointsGrow, MethodBreakpointsCondition,
    MethodBreakpointsLogOnly, MethodBreakpointsSet, MethodBreakpointsCancel, MethodBreakpointsFooter,
    MethodBreakpointsTruncated, MethodBreakpointsNone, MethodBreakpointsNoSource, MethodBreakpointsOverride,
    MethodBreakpointsImplements, MethodBreakpointsHitLine, MethodBreakpointsNoServer, MethodBreakpointsCreated,
    MethodBreakpointsGrown, MethodBreakpointsOff, MethodBreakpointsLog, MethodGroupsTitle, MethodGroupsEmpty,
    MethodGroupsItem, MethodGroupsGrowing, MethodGroupsToggle, MethodGroupsRemove, MethodGroupsClose,
    MethodGroupsRemoved);

  TAtlasMethodBreakpointsStrings = class
  public
    class function Text(AId: TAtlasMethodBreakpointsTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TAtlasMethodBreakpointsTextId; const AArgs: array of const): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Strings;

const
  cTexts: array[TAtlasLanguage, TAtlasMethodBreakpointsTextId] of string = (
    ('Haltepunkt auf Methoden',
     'Muster:',
     'z. B. TKunde.Speichere, TKunde.*, *.Validiere*, Unit.*, IAuftrag.Pruefe',
     'Suchen',
     'Überschreibungen',
     'Überladungen',
     'Mitwachsen: neue Methoden beim Debug-Start ergänzen',
     'Bedingung:',
     'Nicht anhalten, nur protokollieren',
     'Setzen (%d)',
     'Abbrechen',
     '%d Treffer, %d gewählt',
     'Mehr als %d Treffer, Muster enger fassen; %d gewählt',
     'Keine passende Methode gefunden.',
     'ohne Quelltext',
     'überschreibt %s',
     'setzt %s um',
     '%s:%d  %s',
     'Haltepunkt auf Methoden: Der Atlas-Server antwortet nicht. %s',
     'Haltepunkt auf Methoden: %d Haltepunkte in der Gruppe „%s“ gesetzt.',
     'Mitwachsen: %d neue Haltepunkte für „%s“: %s',
     'Haltepunkt auf Methoden ist abgeschaltet (debug.methodBreakpoints).',
     'Methode %s erreicht',
     'Haltepunktgruppen der Methoden',
     'Für dieses Projekt gibt es keine Gruppen.',
     '%s  ·  %d Haltepunkte, %d aktiv',
     '  ·  wächst mit',
     'Ein-/Ausschalten',
     'Entfernen',
     'Schließen',
     'Haltepunkt auf Methoden: Gruppe „%s“ entfernt (%d Haltepunkte).'),
    ('Breakpoint on methods',
     'Pattern:',
     'e.g. TCustomer.Save, TCustomer.*, *.Validate*, Unit.*, IOrder.Check',
     'Search',
     'Overrides',
     'Overloads',
     'Grow: add new methods when debugging starts',
     'Condition:',
     'Do not break, log only',
     'Set (%d)',
     'Cancel',
     '%d matches, %d selected',
     'More than %d matches, narrow the pattern; %d selected',
     'No matching method found.',
     'no source',
     'overrides %s',
     'implements %s',
     '%s:%d  %s',
     'Breakpoint on methods: the Atlas server does not answer. %s',
     'Breakpoint on methods: %d breakpoints set in group “%s”.',
     'Grow: %d new breakpoints for “%s”: %s',
     'Breakpoint on methods is turned off (debug.methodBreakpoints).',
     'Method %s reached',
     'Method breakpoint groups',
     'There are no groups for this project.',
     '%s  ·  %d breakpoints, %d enabled',
     '  ·  grows',
     'Enable/disable',
     'Remove',
     'Close',
     'Breakpoint on methods: group “%s” removed (%d breakpoints).'));

{ TAtlasMethodBreakpointsStrings }

class function TAtlasMethodBreakpointsStrings.Text(AId: TAtlasMethodBreakpointsTextId): string;
begin
  Result := cTexts[TAtlasStrings.Language, AId];
end;

class function TAtlasMethodBreakpointsStrings.Fmt(AId: TAtlasMethodBreakpointsTextId;
  const AArgs: array of const): string;
begin
  Result := Format(cTexts[TAtlasStrings.Language, AId], AArgs);
end;

end.
