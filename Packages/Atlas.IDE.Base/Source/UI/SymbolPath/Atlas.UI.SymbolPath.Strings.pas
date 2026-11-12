unit Atlas.UI.SymbolPath.Strings;

// Oberflächentexte des Features Symbolpfad auf Deutsch und Englisch. Die Sprache bestimmt
// `TAtlasStrings.Language`; jeder Aufruf liest sie neu. Eigene Unit, damit ein neuer Text des Features nicht
// `Atlas.UI.Strings` ändert, die fast der ganze Kern verwendet; dort bleiben gemeinsame Texte.

interface

{$SCOPEDENUMS ON}

type
  TAtlasSymbolPathTextId = (
    SymbolPathFound, SymbolPathFoundMany, SymbolPathMoreRoutes, SymbolPathCallsIncomplete, SymbolPathRouteHeader,
    SymbolPathNoPath, SymbolPathAborted, SymbolPathAmbiguous, SymbolPathNotFound, SymbolPathInferred,
    SymbolPathLibrary);

  TAtlasSymbolPathStrings = class
  public
    class function Text(AId: TAtlasSymbolPathTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TAtlasSymbolPathTextId; const AArgs: array of const): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Strings;

const
  cTexts: array[TAtlasLanguage, TAtlasSymbolPathTextId] of string = (
    ('Kürzester Weg: %d Schritte · %d Knoten durchsucht · %d ms',
     'Kürzester Weg: %d Schritte, %d Wege gleich lang · %d Knoten durchsucht · %d ms',
     ' · weitere gleich lange Wege nicht gezeigt',
     ' · Aufrufe nicht ganz durchsucht (Zeitlimit)',
     'Weg %d',
     'Kein Weg in höchstens %d Schritten (%d Knoten durchsucht).',
     'Kein Weg gefunden in %d Schritten (Suche nach %d Knoten abgebrochen: %s).',
     '„%s“ ist mehrdeutig; bitte qualifiziert angeben. Treffer (Doppelklick springt hin):',
     '„%s“ ist weder Symbol noch Unit im Index.',
     'erschlossen',
     'Bibliothek'),
    ('Shortest path: %d steps · %d nodes searched · %d ms',
     'Shortest path: %d steps, %d equally short paths · %d nodes searched · %d ms',
     ' · more equally short paths not shown',
     ' · calls not fully searched (time limit)',
     'Path %d',
     'No path in at most %d steps (%d nodes searched).',
     'No path found in %d steps (search aborted after %d nodes: %s).',
     '“%s” is ambiguous; please qualify it. Matches (double-click jumps there):',
     '“%s” is neither a symbol nor a unit in the index.',
     'inferred',
     'library'));

{ TAtlasSymbolPathStrings }

class function TAtlasSymbolPathStrings.Text(AId: TAtlasSymbolPathTextId): string;
begin
  Result := cTexts[TAtlasStrings.Language, AId];
end;

class function TAtlasSymbolPathStrings.Fmt(AId: TAtlasSymbolPathTextId; const AArgs: array of const): string;
begin
  Result := Format(Text(AId), AArgs);
end;

end.
