unit Atlas.UI.Debug.VariablesStrings;

// Oberflächentexte des Fensters „Variablen“ (#853) auf Deutsch und Englisch.
// Eigene Tabelle neben Atlas.UI.Debug.Strings, die sonst über die Grenze der
// Unit-Länge wüchse. Die Sprache bestimmt Base (`TAtlasStrings.Language`); jeder
// Aufruf liest sie neu.

interface

uses
  Atlas.Core.Localization.Language;

{$SCOPEDENUMS ON}

type
  TAtlasVariablesTextId = (
    VariablesCommand, VariablesCaption, VariablesTabAutos, VariablesTabLocals, VariablesTabWatch,
    VariablesSearchHint, VariablesSearchValues, VariablesSearchDeep, VariablesWatchHint, VariablesAddWatch,
    VariablesCopyValue, VariablesCopyExpression, VariablesRemoveWatch, VariablesNoServer, VariablesCount,
    VariablesHits, VariablesSearching, VariablesTruncated, VariablesKeys, VariablesWatchesKind,
    SettingsDebugVariablesWindow, SettingsDebugVariablesSearchDepth, SettingsDebugVariablesSearchLimit);

{$SCOPEDENUMS OFF}

  TAtlasVariablesStrings = class
  public
    /// <summary>Text in der Sprache der Oberfläche.</summary>
    class function Text(AId: TAtlasVariablesTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TAtlasVariablesTextId; const AArgs: array of const): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Strings;

const
  cTexts: array[TAtlasLanguage, TAtlasVariablesTextId] of string = (
    ('Atlas: Variablen',
     'Atlas: Variablen',
     'Autos',
     'Lokal',
     'Überwachung',
     'Suchen (Strg+F) …',
     'In Werten',
     'Unterelemente',
     'Ausdruck überwachen (Enter)',
     'Als Überwachung hinzufügen',
     'Wert kopieren',
     'Ausdruck kopieren',
     'Überwachung entfernen',
     'Autos und Lokal brauchen den Atlas-Server; die Überwachung geht ohne.',
     '%d Einträge',
     '%d Treffer',
     'Suche … (%d Auswertungen)',
     '%d Treffer · Suche nach %d Auswertungen abgebrochen',
     'Strg+F: suchen · Strg+C: Wert kopieren · Strg+W: überwachen · F2: Wert ändern · Entf: Überwachung entfernen',
     'Überwachungsliste des Fensters „Variablen“',
     'Fenster „Variablen“ mit Autos und Suche',
     'Suchtiefe in Unterelementen (1 bis 10)',
     'Höchstens so viele Auswertungen je Suche'),
    ('Atlas: Variables',
     'Atlas: Variables',
     'Autos',
     'Locals',
     'Watch',
     'Search (Ctrl+F) …',
     'In values',
     'Children',
     'Watch expression (Enter)',
     'Add as watch',
     'Copy value',
     'Copy expression',
     'Remove watch',
     'Autos and Locals need the Atlas server; Watch works without it.',
     '%d entries',
     '%d matches',
     'Searching … (%d evaluations)',
     '%d matches · search stopped after %d evaluations',
     'Ctrl+F: search · Ctrl+C: copy value · Ctrl+W: watch · F2: change value · Del: remove watch',
     'Watch list of the Variables window',
     'Variables window with Autos and search',
     'Search depth in children (1 to 10)',
     'At most this many evaluations per search')
);

{ TAtlasVariablesStrings }

class function TAtlasVariablesStrings.Text(AId: TAtlasVariablesTextId): string;
begin
  Result := cTexts[TAtlasStrings.Language, AId];
end;

class function TAtlasVariablesStrings.Fmt(AId: TAtlasVariablesTextId; const AArgs: array of const): string;
begin
  Result := Format(cTexts[TAtlasStrings.Language, AId], AArgs);
end;

end.
