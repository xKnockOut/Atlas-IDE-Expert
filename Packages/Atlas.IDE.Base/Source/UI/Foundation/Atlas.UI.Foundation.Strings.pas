unit Atlas.UI.Foundation.Strings;

// Oberflächentexte des Features IDE-Grundlagen auf Deutsch und Englisch. Die Sprache bestimmt
// `TAtlasStrings.Language`; jeder Aufruf liest sie neu. Eigene Unit, damit ein neuer Text des Features nicht
// `Atlas.UI.Strings` ändert, die fast der ganze Kern verwendet; dort bleiben gemeinsame Texte.

interface

{$SCOPEDENUMS ON}

type
  TAtlasFoundationTextId = (
    KeyConflict, ForeignCompletion, ResultsCaption, SymbolTitle, SymbolDescription, TeamFileNoProject,
    TeamFileCreated, TeamFileCreateFailed, TeamFileIssueSyntax, TeamFileIssueSyntaxAt, TeamFileIssueVersion,
    TeamFileIssueUnknownKey, TeamFileIssueWrongType, TeamFileIssueInvalidValue, TeamFileIssueCredential,
    TeamFileIssueAbsolutePath, TeamFileIssueOutsidePath, StartProfilesTemporaryRestored, ResultsSureGroup,
    ResultsInferredGroup);

  TAtlasFoundationStrings = class
  public
    class function Text(AId: TAtlasFoundationTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TAtlasFoundationTextId; const AArgs: array of const): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Strings;

const
  cTexts: array[TAtlasLanguage, TAtlasFoundationTextId] of string = (
    ('Atlas: %0:s ist schon belegt (%1:s); Atlas überlässt die Taste und belegt sie nicht für %2:s. ' +
       'Entscheidung unter Tools > Optionen > Drittanbieter > Atlas > Tastenkonflikte.',
     'Atlas: %s bringt eine eigene Vervollständigung mit. Laufen beide, stören sie sich; ' +
       'eine davon abschalten (Atlas: Menü Atlas > Code Insight von Atlas). Atlas ändert fremde Erweiterungen nicht.',
     'Atlas-Ergebnisse',
     'Atlas IDE Expert %s',
     'Sprachserver, Prüfregeln, Vervollständigung und Refactoring für Delphi.',
     'Projektdatei .atlas: Es ist kein Projekt geöffnet.',
     'Projektdatei .atlas angelegt; sie gilt für alle im Team, sobald sie eingecheckt ist.',
     'Projektdatei .atlas konnte nicht angelegt werden: %s',
     'Projektdatei .atlas ist fehlerhaft (kein gültiges JSON-Objekt); Atlas nutzt die persönlichen Einstellungen.',
     'Projektdatei %s ist fehlerhaft: kein gültiges JSON in Zeile %d, Spalte %d; Atlas nutzt die persönlichen Einstellungen.',
     '.atlas: "version" fehlt oder ist neuer als diese Atlas-Version; bekannte Einträge gelten.',
     '.atlas: Unbekannter Eintrag "%s" wird ignoriert.',
     '.atlas: "%s" hat den falschen Typ und wird ignoriert.',
     '.atlas: Ungültiger Wert für "%s" wird ignoriert.',
     '.atlas: "%s" sieht nach Zugangsdaten aus und wird ignoriert; Benutzer und Token gehören in den Anmeldespeicher von Windows.',
     '.atlas: "%s" enthält einen absoluten Pfad und wird ignoriert; Pfade relativ zur Datei angeben.',
     '.atlas: "%s" führt aus dem Projekt heraus und wird ignoriert.',
     'Atlas: Vorübergehende Startparameter von %s zurückgestellt.',
     'Sicher (%d)',
     'Erschlossen (%d) · vor dem Umbenennen prüfen'),
    ('Atlas: %0:s is already assigned (%1:s); Atlas leaves the key and does not use it for %2:s. ' +
       'Decide under Tools > Options > Third Party > Atlas > Key conflicts.',
     'Atlas: %s brings its own code completion. Running both interferes; ' +
       'switch one off (Atlas: menu Atlas > Atlas Code Insight). Atlas does not change other extensions.',
     'Atlas Results',
     'Atlas IDE Expert %s',
     'Language server, code checks, completion and refactoring for Delphi.',
     'Project file .atlas: no project is open.',
     'Project file .atlas created; it applies to the whole team once it is checked in.',
     'Could not create project file .atlas: %s',
     'Project file .atlas is invalid (not a valid JSON object); Atlas uses the personal settings.',
     'Project file %s is invalid: no valid JSON at line %d, column %d; Atlas uses the personal settings.',
     '.atlas: "version" is missing or newer than this Atlas version; known entries apply.',
     '.atlas: unknown entry "%s" is ignored.',
     '.atlas: "%s" has the wrong type and is ignored.',
     '.atlas: invalid value for "%s" is ignored.',
     '.atlas: "%s" looks like credentials and is ignored; user names and tokens belong in the Windows Credential Manager.',
     '.atlas: "%s" contains an absolute path and is ignored; use paths relative to the file.',
     '.atlas: "%s" leads outside the project and is ignored.',
     'Atlas: Temporary run parameters of %s restored.',
     'Sure (%d)',
     'Inferred (%d) · check before renaming'));

{ TAtlasFoundationStrings }

class function TAtlasFoundationStrings.Text(AId: TAtlasFoundationTextId): string;
begin
  Result := cTexts[TAtlasStrings.Language, AId];
end;

class function TAtlasFoundationStrings.Fmt(AId: TAtlasFoundationTextId; const AArgs: array of const): string;
begin
  Result := Format(Text(AId), AArgs);
end;

end.
