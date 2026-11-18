unit Atlas.UI.Debug.Elapsed.Strings;

// Texte zur Laufzeit zwischen Haltepunkten (#579), auf Deutsch und Englisch. Die Sprache bestimmt Base
// (`TAtlasStrings.Language`); jeder Aufruf liest sie neu.

interface

{$SCOPEDENUMS ON}

type
  TAtlasElapsedTextId = (ElapsedHint, ElapsedHistory);

  TAtlasElapsedStrings = class
  public
    class function Text(AId: TAtlasElapsedTextId): string; static;
  end;

implementation

uses
  Atlas.UI.Strings;

const
  cTexts: array[TAtlasLanguage, TAtlasElapsedTextId] of string = (
    ('Laufzeit seit dem letzten Halt; enthält den Aufwand des Debuggers (Debug-Build, Ereignisse), nur ein Richtwert',
     'Letzte Messungen (Start → Ziel):'),
    ('Run time since the last stop; includes debugger overhead (debug build, events), a rough guide only',
     'Recent measurements (start → target):'));

{ TAtlasElapsedStrings }

class function TAtlasElapsedStrings.Text(AId: TAtlasElapsedTextId): string;
begin
  Result := cTexts[TAtlasStrings.Language, AId];
end;

end.
