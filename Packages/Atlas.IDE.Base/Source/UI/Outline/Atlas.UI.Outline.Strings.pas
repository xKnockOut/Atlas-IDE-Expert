unit Atlas.UI.Outline.Strings;

// Oberflächentexte des Features Gliederung auf Deutsch und Englisch. Die Sprache bestimmt
// `TAtlasStrings.Language`; jeder Aufruf liest sie neu. Eigene Unit, damit ein neuer Text des Features nicht
// `Atlas.UI.Strings` ändert, die fast der ganze Kern verwendet; dort bleiben gemeinsame Texte.

interface

{$SCOPEDENUMS ON}

type
  TAtlasOutlineTextId = (
    OutlineCaption, OutlineSearchHint, OutlineVisibilityButton, OutlineKindButton, OutlineSortSource,
    OutlineSortAlphabetical, OutlineShowAll, OutlineUnimplemented, OutlineEmpty, OutlineNoServer, OutlineNoMatch,
    OutlineGoToDeclaration, OutlineGoToImplementation, OutlineFollowCursor, BreadcrumbsCurrent, BreadcrumbsEmpty,
    BreadcrumbsCrumbHint, BreadcrumbsChildrenHint, BreadcrumbsDisabled, BreadcrumbsMarkHint, BreadcrumbsPlaceLine,
    BreadcrumbsPlaceLineOnly, BreadcrumbsRegionUnnamed, BreadcrumbsSectionCount, BreadcrumbsSectionCountOne,
    BreadcrumbsSectionAppend, BreadcrumbsSectionCreate, BreadcrumbsOverloadsHint, BreadcrumbsOverloadsPrompt,
    BreadcrumbsInterfacesHint, BreadcrumbsInterfacesKey, BreadcrumbsInterfacesPrompt, BreadcrumbsInterfacesPath);

  TAtlasOutlineStrings = class
  public
    class function Text(AId: TAtlasOutlineTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TAtlasOutlineTextId; const AArgs: array of const): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Strings;

const
  cTexts: array[TAtlasLanguage, TAtlasOutlineTextId] of string = (
    ('Gliederung',
     'Gliederung durchsuchen',
     'Sichtbarkeit',
     'Art',
     'Quelltextreihenfolge',
     'Alphabetisch',
     'Alle zeigen',
     'nicht implementiert',
     'Keine Gliederung: Unit im Editor öffnen.',
     'Keine Gliederung: Der Atlas-Server läuft nicht.',
     'Kein Eintrag passt zum Filter.',
     'Zur Deklaration',
     'Zur Implementierung',
     'Cursor folgen',
     'aktuell',
     'Keine Gliederung an dieser Stelle',
     'Klick: Liste der Nachbarn · Strg+Klick: springen · Strg+Umschalt+Klick: zur Deklaration',
     'Klick: Inhalt (Typen, Mitglieder, lokale Routinen)',
     'Brotkrumenleiste nach Fehlern abgeschaltet – wieder einschalten über Atlas › Abgeschaltete Funktionen einschalten',
     '%s · deklariert in Zeile %d',
     '%s · Zeile %d',
     'Zeile %d',
     'Region (Z. %d)',
     '%d Mitglieder · Zeile %d',
     '1 Mitglied · Zeile %d',
     'Neue Zeile am Ende von %s',
     'Abschnitt anlegen: %s',
     'Überladungen von %s (Umschalt+↓)',
     'Überladungen von %s',
     'Erfüllt %s (%s, Z. %d)',
     'Klick oder Alt+↓ öffnet die Liste',
     'Erfüllt',
     '%s, Z. %d'),
    ('Outline',
     'Search outline',
     'Visibility',
     'Kind',
     'Source order',
     'Alphabetical',
     'Show all',
     'not implemented',
     'No outline: open a unit in the editor.',
     'No outline: the Atlas server is not running.',
     'No entry matches the filter.',
     'Go to declaration',
     'Go to implementation',
     'Follow cursor',
     'current',
     'No outline at this position',
     'Click: list of neighbours · Ctrl+click: jump · Ctrl+Shift+click: to the declaration',
     'Click: contents (types, members, local routines)',
     'Breadcrumbs switched off after errors – switch on again via Atlas › Re-enable switched-off features',
     '%s · declared in line %d',
     '%s · line %d',
     'line %d',
     'Region (l. %d)',
     '%d members · line %d',
     '1 member · line %d',
     'New line at the end of %s',
     'Create section: %s',
     'Overloads of %s (Shift+↓)',
     'Overloads of %s',
     'Implements %s (%s, line %d)',
     'Click or Alt+↓ opens the list',
     'Implements',
     '%s, line %d'));

{ TAtlasOutlineStrings }

class function TAtlasOutlineStrings.Text(AId: TAtlasOutlineTextId): string;
begin
  Result := cTexts[TAtlasStrings.Language, AId];
end;

class function TAtlasOutlineStrings.Fmt(AId: TAtlasOutlineTextId; const AArgs: array of const): string;
begin
  Result := Format(Text(AId), AArgs);
end;

end.
