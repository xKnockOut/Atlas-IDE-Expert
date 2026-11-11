unit Atlas.UI.Generate.Strings;

// Oberflächentexte des Features Codeerzeugung auf Deutsch und Englisch. Die Sprache bestimmt
// `TAtlasStrings.Language`; jeder Aufruf liest sie neu. Eigene Unit, damit ein neuer Text des Features nicht
// `Atlas.UI.Strings` ändert, die fast der ganze Kern verwendet; dort bleiben gemeinsame Texte.

interface

{$SCOPEDENUMS ON}

type
  TAtlasGenerateTextId = (
    GenerateTitle, GenerateGroupRecent, GenerateGroupGenerate, GenerateGroupSurround, GenerateGroupTemplates,
    GenerateHint, GenerateFilter, GenerateEmpty, GenerateNoMatch, GenerateStepHint, GenerateStepMultiHint,
    GenerateFreeText, GenerateExample, GenerateArgumentPrompt, GenerateNoChoices, GenerateMenuOff, GenerateFailed,
    GenerateHiddenSaved, WelcomeSetupNewFailed, GalleryFileExists, GalleryChoiceSearch, GalleryChoiceOk,
    GalleryChoiceCancel);

  TAtlasGenerateStrings = class
  public
    class function Text(AId: TAtlasGenerateTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TAtlasGenerateTextId; const AArgs: array of const): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Strings;

const
  cTexts: array[TAtlasLanguage, TAtlasGenerateTextId] of string = (
    ('Erzeugen',
     'Zuletzt gewählt',
     'Erzeugen',
     'Umschließen',
     'Vorlagen',
     '1–9 wählen · Tippen filtert · Entf blendet aus',
     'Filter: %s',
     'Hier gibt es nichts zu erzeugen',
     'Kein Eintrag passt',
     'Enter übernimmt · Esc zurück',
     'Leertaste wählt · Enter übernimmt · Esc zurück',
     '„%s“ verwenden',
     'Beispiel: %s',
     'Argument eingeben',
     'Keine Auswahl; Argument eingeben',
     'Das Erzeugen-Menü ist abgeschaltet (keys.generateMenu).',
     'Erzeugen: %s',
     '„%s“ ausgeblendet; wieder einblenden unter Einstellungen › Befehle.',
     'Neu mit Atlas: Die Datei ließ sich nicht anlegen (%s).',
     'Die Datei %s gibt es schon.',
     'Suchen',
     'OK',
     'Abbrechen'),
    ('Generate',
     'Recently used',
     'Generate',
     'Surround',
     'Templates',
     '1–9 choose · type to filter · Del hides',
     'Filter: %s',
     'Nothing to generate here',
     'No entry matches',
     'Enter applies · Esc goes back',
     'Space toggles · Enter applies · Esc goes back',
     'Use “%s”',
     'Example: %s',
     'Type an argument',
     'No choices; type an argument',
     'The generate menu is switched off (keys.generateMenu).',
     'Generate: %s',
     '“%s” hidden; show it again under Settings › Commands.',
     'New with Atlas: the file could not be created (%s).',
     'The file %s already exists.',
     'Search',
     'OK',
     'Cancel'));

{ TAtlasGenerateStrings }

class function TAtlasGenerateStrings.Text(AId: TAtlasGenerateTextId): string;
begin
  Result := cTexts[TAtlasStrings.Language, AId];
end;

class function TAtlasGenerateStrings.Fmt(AId: TAtlasGenerateTextId; const AArgs: array of const): string;
begin
  Result := Format(Text(AId), AArgs);
end;

end.
