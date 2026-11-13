unit Atlas.UI.Completion.Strings;

// Oberflächentexte des Features Vervollständigung auf Deutsch und Englisch. Die Sprache bestimmt
// `TAtlasStrings.Language`; jeder Aufruf liest sie neu. Eigene Unit, damit ein neuer Text des Features nicht
// `Atlas.UI.Strings` ändert, die fast der ganze Kern verwendet; dort bleiben gemeinsame Texte.

interface

{$SCOPEDENUMS ON}

type
  TAtlasCompletionTextId = (
    FooterKeys, CountOf, NoMatchesFor, BackspaceWidens, NoSuggestions, EscCloses, NoDetails, Overload,
    DeprecatedWith, DeprecatedPlain, InheritedFrom, InheritedPlain, TagRecent, TagFrequent, FitsType, OtherGroup,
    CountFits, AccessCompletion, AccessPosition, DidYouMean, SetFooterKeys, SetChosen, SetHeader, SetHeaderPlain,
    UnknownHeader, BatchHeader, AssignHeader, FormHeader, SenderHeader, DataSourceFooter, GuardFooterKeys,
    PlaceholderFooter, CompletionLimited, HidesDeclaration, WithMemberOrigin, ExceptionGroupTry,
    ExceptionGroupGeneral, SyntaxLimited, SyntaxUnknown, SyntaxLine, TargetFooter, UnavailableHint, FavoritePinned,
    FavoriteUnpinned, FavoritesFull, FavoriteNotAllowed, AccessFavorite, CompletionRestHeader, CountHitsRest,
    CompletionLossyHint, HelperAddsUnit, UsesGroupProject, UsesGroupRtl, UsesGroupLibrary, UsesInInterface,
    UsesInImplementation, UsesCycleTag, UsesTypesHeading, InheritedSameTag, InheritedOverloadTag, SameNameActiveTag,
    SameNameDeclaredIn, SameNameRoleActive, SameNameRoleThis, SameNameRoleHidden, SameNameNotActive,
    SameNameInsertPrefix, SameNameInsertPrefixAdd, SameNameInsertMove, SameNameInsertAdd, SameNameHiddenFooter,
    TagVariantBranch, NarrowedHeader, DescendantsHeader, InaccessibleOne, InaccessibleMany, InaccessibleHeader);

  TAtlasCompletionStrings = class
  public
    class function Text(AId: TAtlasCompletionTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TAtlasCompletionTextId; const AArgs: array of const): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Strings;

const
  cTexts: array[TAtlasLanguage, TAtlasCompletionTextId] of string = (
    ('Enter übernehmen · Esc schließen',
     '%d von %d',
     'Keine Treffer für „%s“',
     'Rücktaste erweitert die Suche',
     'Keine Vorschläge an dieser Stelle',
     'Esc schließt',
     'Keine Details zu diesem Eintrag',
     'Überladung',
     'Veraltet: %s',
     'Veraltet.',
     'Geerbt von %s',
     'Geerbt',
     'zuletzt',
     'häufig',
     'Passt zu %s',
     'Weitere',
     '%d passend · %d gesamt',
     'Atlas Vervollständigung',
     '%d von %d',
     'Meintest du',
     'Leertaste wählen · Enter einfügen · Esc verwerfen',
     '%d gewählt',
     '%s · Menge von %s',
     'Menge von %s',
     '„%s“ ist unbekannt',
     'Fehlende Methoden von %s',
     'Alle Felder zuweisen · %s',
     'Formular %s',
     'Sender ist %s · %s',
     'Quelle: %s',
     'Enter anwenden · weitertippen verwirft',
     'Platzhalter %d / %d · Tab weiter · Esc fertig',
     'eingeschränkt (Index wird aufgebaut)',
     'Verdeckt: %s',
     'Mitglied von %s (with)',
     'Aus dem try-Block',
     'Allgemein',
     'Ergebnisse möglicherweise unvollständig · Syntaxfehler in ',
     'Kontext unklar · Syntaxfehler in ',
     'Zeile %d',
     'Ziel: %s',
     'Nicht verfügbar: Die Bedingung „%s“ ist für %s nicht erfüllt. Es gelten die Symbole der Plattform ' +
     'und des Compilers sowie die Bedingungen aus den Projektoptionen der aktiven Konfiguration (z. B. DEBUG).',
     '%s angeheftet · Strg+D löst',
     '%s gelöst',
     'Schon %d Favoriten bei %s – erst einen lösen',
     'Dieser Eintrag lässt sich nicht anheften',
     'angeheftet',
     'Weitere Einträge',
     '%d Treffer · %d weitere',
     '%s passt nicht verlustfrei zu %s: Round(…) rundet, Trunc(…) schneidet ab.',
     'Enter trägt %s in die uses-Klausel ein; danach gilt dieser Helper.',
     'Projekt',
     'RTL/VCL',
     'Drittanbieter',
     'bereits im interface-Teil',
     'bereits im implementation-Teil',
     'Zirkelbezug',
     'Exportierte Typen',
     'gleiche Parameter',
     'Überladung',
     'aktiv',
     'Deklariert in',
     'aktiv · letzte Unit in den uses',
     'diese Variante',
     'ausgeblendet',
     'nicht aktiv',
     'Enter fügt den Unit-Präfix ein',
     'Enter fügt den Unit-Präfix ein und ergänzt %s in den uses; andere Stellen können ihre Bedeutung ändern',
     'Enter verschiebt %s in den uses nach hinten; andere Stellen können ihre Bedeutung ändern',
     'Enter ergänzt %s in den uses; andere Stellen können ihre Bedeutung ändern',
     '%s ausgeblendet',
     'Zweig %s',
     '%s ist hier %s (is-Prüfung, Zeile %d)',
     'Nachfahren von %s',
     '1 Treffer nicht sichtbar: %s (%s in %s) · Strg+Leertaste zeigt ihn',
     '%d Treffer nicht sichtbar: %s · Strg+Leertaste zeigt sie',
     'Nicht sichtbar · Enter bietet Aktionen an'),
    ('Enter to accept · Esc to close',
     '%d of %d',
     'No matches for “%s”',
     'Backspace widens the search',
     'No suggestions here',
     'Esc closes',
     'No details for this entry',
     'Overload',
     'Deprecated: %s',
     'Deprecated.',
     'Inherited from %s',
     'Inherited',
     'recent',
     'frequent',
     'Matches %s',
     'Other',
     '%d matching · %d total',
     'Atlas completion',
     '%d of %d',
     'Did you mean',
     'Space selects · Enter inserts · Esc discards',
     '%d selected',
     '%s · set of %s',
     'Set of %s',
     '"%s" is unknown',
     'Missing methods of %s',
     'Assign all fields · %s',
     'Form %s',
     'Sender is %s · %s',
     'Source: %s',
     'Enter applies · keep typing to discard',
     'Placeholder %d / %d · Tab next · Esc done',
     'limited (index is being built)',
     'Hides: %s',
     'Member of %s (with)',
     'From the try block',
     'General',
     'Results may be incomplete · syntax error in ',
     'Context unclear · syntax error in ',
     'line %d',
     'Target: %s',
     'Not available: the condition “%s” is not met for %s. The symbols of the platform ' +
     'and compiler and the conditionals from the project options of the active configuration (e.g. DEBUG) apply.',
     '%s pinned · Ctrl+D unpins',
     '%s unpinned',
     'Already %d favorites for %s – unpin one first',
     'This entry cannot be pinned',
     'pinned',
     'More entries',
     '%d matches · %d more',
     '%s does not fit %s without loss: Round(…) rounds, Trunc(…) truncates.',
     'Enter adds %s to the uses clause; this helper applies from then on.',
     'Project',
     'RTL/VCL',
     'Third party',
     'already in the interface section',
     'already in the implementation section',
     'Circular reference',
     'Exported types',
     'same parameters',
     'overload',
     'active',
     'Declared in',
     'active · last unit in uses',
     'this variant',
     'hidden',
     'not active',
     'Enter inserts the unit prefix',
     'Enter inserts the unit prefix and adds %s to uses; other places may change their meaning',
     'Enter moves %s to the end of uses; other places may change their meaning',
     'Enter adds %s to uses; other places may change their meaning',
     '%s hidden',
     'branch %s',
     '%s is %s here (is check, line %d)',
     'Descendants of %s',
     '1 match not visible: %s (%s in %s) · Ctrl+Space shows it',
     '%d matches not visible: %s · Ctrl+Space shows them',
     'Not visible · Enter offers actions'));

{ TAtlasCompletionStrings }

class function TAtlasCompletionStrings.Text(AId: TAtlasCompletionTextId): string;
begin
  Result := cTexts[TAtlasStrings.Language, AId];
end;

class function TAtlasCompletionStrings.Fmt(AId: TAtlasCompletionTextId; const AArgs: array of const): string;
begin
  Result := Format(Text(AId), AArgs);
end;

end.
