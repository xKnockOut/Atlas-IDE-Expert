unit Atlas.UI.Help.Strings;

// Oberflächentexte des Moduls Hilfe (#1886) auf Deutsch und Englisch (#1455). Die Sprache bestimmt Base
// (`TAtlasStrings.Language`); jeder Aufruf liest sie neu, ein Sprachwechsel braucht daher keine eigene Meldung.
// Kerntexte bleiben in `Atlas.UI.Strings`.

interface

{$SCOPEDENUMS ON}

type
  TAtlasHelpTextId = (
    SettingsHelpSource, SettingsHelpOnline, SettingsHelpLocal, KeyFindingHelp, LocalDocsMissing);

  TAtlasHelpStrings = class
  public
    class function Text(AId: TAtlasHelpTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TAtlasHelpTextId; const AArgs: array of const): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Strings;

const
  cTexts: array[TAtlasLanguage, TAtlasHelpTextId] of string = (
    ('Quelle der Hilfe',
     'Doku auf GitHub zur installierten Version',
     'Mit Atlas installierte Doku (ohne Netz)',
     'Hilfe zum Atlas-Befund (F1)',
     'Die installierte Doku fehlt (%s); Atlas öffnet die Doku auf GitHub.'),
    ('Help source',
     'Documentation on GitHub for the installed version',
     'Documentation installed with Atlas (offline)',
     'Help for the Atlas finding (F1)',
     'The installed documentation is missing (%s); Atlas opens the documentation on GitHub.'));

{ TAtlasHelpStrings }

class function TAtlasHelpStrings.Text(AId: TAtlasHelpTextId): string;
begin
  Result := cTexts[TAtlasStrings.Language, AId];
end;

class function TAtlasHelpStrings.Fmt(AId: TAtlasHelpTextId; const AArgs: array of const): string;
begin
  Result := Format(cTexts[TAtlasStrings.Language, AId], AArgs);
end;

end.
