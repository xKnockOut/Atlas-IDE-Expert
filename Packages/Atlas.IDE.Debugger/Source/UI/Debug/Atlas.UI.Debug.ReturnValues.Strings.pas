unit Atlas.UI.Debug.ReturnValues.Strings;

// Texte zu den Rückgabewerten nach dem Verlassen eigener Funktionen (#844), auf Deutsch und Englisch. Die Sprache
// bestimmt Base (`TAtlasStrings.Language`); jeder Aufruf liest sie neu.

interface

{$SCOPEDENUMS ON}

type
  TAtlasReturnValuesTextId = (ReturnUnavailable, ReturnHint, ReturnHistory);

  TAtlasReturnValuesStrings = class
  public
    class function Text(AId: TAtlasReturnValuesTextId): string; static;
  end;

implementation

uses
  Atlas.Plugin.Localization.Strings;

const
  cTexts: array[TAtlasLanguage, TAtlasReturnValuesTextId] of string = (
    ('‹kein Zugriff›',
     'Abgeholt an der end-Zeile der Funktion; mit Optimierung ($O+) ist Result dort oft nicht auswertbar',
     'Zuletzt zurückgegeben (Funktion, Ergebnis, end-Zeile, Zeit):'),
    ('‹no access›',
     'Read at the end line of the function; with optimization ($O+) Result often cannot be evaluated there',
     'Recently returned (function, result, end line, time):'));

{ TAtlasReturnValuesStrings }

class function TAtlasReturnValuesStrings.Text(AId: TAtlasReturnValuesTextId): string;
begin
  Result := cTexts[TAtlasStrings.Language, AId];
end;

end.
