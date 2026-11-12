unit Atlas.UI.Problems.Strings;

// Oberflächentexte des Features Problemliste auf Deutsch und Englisch. Die Sprache bestimmt
// `TAtlasStrings.Language`; jeder Aufruf liest sie neu. Eigene Unit, damit ein neuer Text des Features nicht
// `Atlas.UI.Strings` ändert, die fast der ganze Kern verwendet; dort bleiben gemeinsame Texte.

interface

{$SCOPEDENUMS ON}

type
  TAtlasProblemsTextId = (
    ProblemsGroup, ProblemsMore, SeverityError, SeverityWarning, SeverityInformation, SeverityHint,
    InactiveCondition, InactiveTarget, InactiveRegion, ProblemsMenuCreateIssue, ProblemsMenuCreateIssueMany,
    ProblemsKindCount, ProblemsCategoryAll, ProblemsCategoryBug, ProblemsCategoryVulnerability,
    ProblemsCategoryCodeSmell, ProblemsCategoryHotspot, ProblemsCategoryCompiler, ProblemsCategoryOther,
    ProblemsFilterHint, ProblemsLive, ProblemsOnSave, ProblemsColumnKind, ProblemsColumnMessage, ProblemsColumnLine,
    ProblemsColumnLocation, ProblemsColumnRule, ProblemsStatusCount, ProblemsStatusLast, ProblemsStatusWaiting,
    ProblemsEmpty, ProblemsMenuOpen, ProblemsMenuFix, ProblemsMenuFixNone, ProblemsMenuDisable, ProblemsMenuExplain,
    ProblemsMenuCopy, ProblemsMenuColumns, ProblemsMenuResetSort, ProblemsExplainUnknown, ProblemsExplainTitle,
    ProblemsExplainClose, ProblemsColumnCompiler, ProblemsSectionActive, ProblemsSectionOpen, ProblemsSectionClosed,
    ProblemsTagActive, ProblemsTagClosed, ProblemsCleanActive, ProblemsCheckingActive, ProblemsOpenFirst,
    ProblemsOpenFirstHint, ProblemsStatusTiers, ProblemsStatusHidden, ProblemsMenuFixAll, ProblemsManual,
    // Fehler der IDE (#1819): Spalte und Filter „Quelle“.
    ProblemsColumnSource, ProblemsOriginAll, ProblemsOriginAtlas, ProblemsOriginIde);

  TAtlasProblemsStrings = class
  public
    class function Text(AId: TAtlasProblemsTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TAtlasProblemsTextId; const AArgs: array of const): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Strings;

const
  cTexts: array[TAtlasLanguage, TAtlasProblemsTextId] of string = (
    ('Atlas-Probleme',
     '… %d weitere Probleme',
     'Fehler',
     'Warnung',
     'Info',
     'Hinweis',
     'Inaktiv: Bedingung %s nicht erfüllt',
     ' (Zielplattform %s · %s)',
     'Inaktiver Bereich (bedingte Kompilierung)',
     'Für diesen Befund ein Issue anlegen …',
     'Für diese %d Befunde ein Issue anlegen …',
     '%s %d',
     'Alle Kategorien',
     'Bug',
     'Schwachstelle',
     'Code Smell',
     'Sicherheits-Hotspot',
     'Compiler',
     'Sonstige',
     'Filtern (Meldung, Regel, Datei)',
     '● Live',
     'Beim Speichern',
     'Art',
     'Meldung',
     'Zeile',
     'Stelle',
     'Regel',
     '%d Befunde in %d Dateien',
     'zuletzt geprüft %s (%s, %d ms)',
     'Projektweite Regeln warten auf den Index (%d %%)',
     'Keine Befunde.',
     'Gehe zu',
     'Schnellkorrektur: %s',
     'Schnellkorrektur',
     'Regel abschalten',
     'Regel erklären',
     'Kopieren',
     'Spalten',
     'Sortierung zurücksetzen',
     'Zur Regel %s gibt es keinen Katalogtext.',
     'Regel %s',
     'Schließen',
     'Compiler',
     '%s · aktiver Editor',
     'Geöffnet · %d Units · %d Befunde',
     'Nicht geöffnet · %d Units · %d Befunde',
     'aktiver Editor',
     'nicht geöffnet',
     '%s · Keine Befunde',
     '%s · wird geprüft …',
     'Offene zuerst',
     'Aktive Unit oben anpinnen, geöffnete Units zuerst, nicht geöffnete danach',
     '%d Befunde · %d offene Units (%d) · %d nicht geöffnete Units (%d)',
     '%d nicht geöffnete Units ausgeblendet',
     'Alle sicheren Treffer von %s korrigieren …',
     'Manuell',
     'Quelle',
     'Atlas und IDE',
     'nur Atlas',
     'nur IDE'),
    ('Atlas problems',
     '… %d more problems',
     'Error',
     'Warning',
     'Info',
     'Hint',
     'Inactive: condition %s not met',
     ' (target platform %s · %s)',
     'Inactive region (conditional compilation)',
     'Create an issue for this finding …',
     'Create one issue for these %d findings …',
     '%s %d',
     'All categories',
     'Bug',
     'Vulnerability',
     'Code smell',
     'Security hotspot',
     'Compiler',
     'Other',
     'Filter (message, rule, file)',
     '● Live',
     'On save',
     'Kind',
     'Message',
     'Line',
     'Location',
     'Rule',
     '%d findings in %d files',
     'last checked %s (%s, %d ms)',
     'Project-wide rules wait for the index (%d %%)',
     'No findings.',
     'Go to',
     'Quick fix: %s',
     'Quick fix',
     'Disable rule',
     'Explain rule',
     'Copy',
     'Columns',
     'Reset sorting',
     'There is no catalog text for rule %s.',
     'Rule %s',
     'Close',
     'Compiler',
     '%s · active editor',
     'Open · %d units · %d findings',
     'Not open · %d units · %d findings',
     'active editor',
     'not open',
     '%s · No findings',
     '%s · checking …',
     'Open first',
     'Pin the active unit on top, open units first, units that are not open after them',
     '%d findings · %d open units (%d) · %d units not open (%d)',
     '%d units that are not open hidden',
     'Fix all safe findings of %s …',
     'Manual',
     'Source',
     'Atlas and IDE',
     'Atlas only',
     'IDE only'));

{ TAtlasProblemsStrings }

class function TAtlasProblemsStrings.Text(AId: TAtlasProblemsTextId): string;
begin
  Result := cTexts[TAtlasStrings.Language, AId];
end;

class function TAtlasProblemsStrings.Fmt(AId: TAtlasProblemsTextId; const AArgs: array of const): string;
begin
  Result := Format(Text(AId), AArgs);
end;

end.
