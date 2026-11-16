unit Atlas.UI.Debug.CallStack.Strings;

// Texte des Fensters „Aufrufstapel“ von Atlas, auf Deutsch und Englisch (#1455). Die Sprache bestimmt Base
// (`TAtlasStrings.Language`); jeder Aufruf liest sie neu.

interface

{$SCOPEDENUMS ON}

type
  TAtlasCallStackTextId = (
    CallStackCaption, CallStackSearchHint, CallStackCompare, CallStackCopy, CallStackCopyText, CallStackCopyMarkdown,
    CallStackCopyOwnOnly, CallStackColumnFrame, CallStackColumnLocation, CallStackGroup, CallStackGroupMixed,
    CallStackGroupHits, CallStackStatus, CallStackHits, CallStackRunning, CallStackReading, CallStackNoPrevious,
    CallStackPrevious, CallStackCopied, CallStackFooter);

  TAtlasCallStackStrings = class
  public
    class function Text(AId: TAtlasCallStackTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TAtlasCallStackTextId; const AArgs: array of const): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Strings;

const
  cTexts: array[TAtlasLanguage, TAtlasCallStackTextId] of string = (
    ('Atlas-Aufrufstapel',
     'Suchen: Routine, Unit oder Wert',
     'Mit letztem Halt vergleichen',
     'Kopieren',
     'Als Text',
     'Als Markdown',
     'Nur eigener Code',
     'Routine und Parameter',
     'Unit:Zeile',
     '▸ %d Aufrufe in %s',
     '▸ %d Bibliotheksaufrufe',
     ' · %d Treffer',
     '%d Rahmen, davon %d eigene',
     '%d Treffer',
     'Das Programm läuft; der Aufrufstapel erscheint beim nächsten Halt.',
     'Lese Aufrufstapel …',
     'Kein früherer Halt an dieser Stelle.',
     'Letzter Halt an dieser Stelle',
     'Atlas: %d Rahmen in die Zwischenablage kopiert.',
     'Enter oder Doppelklick: springen bzw. aufklappen · Strg+C: kopieren · Strg+F: suchen'),
    ('Atlas Call Stack',
     'Search: routine, unit or value',
     'Compare with last stop',
     'Copy',
     'As text',
     'As Markdown',
     'Just my code',
     'Routine and parameters',
     'Unit:line',
     '▸ %d calls in %s',
     '▸ %d library calls',
     ' · %d matches',
     '%d frames, %d of them own',
     '%d matches',
     'The program is running; the call stack appears at the next stop.',
     'Reading call stack …',
     'No earlier stop at this place.',
     'Last stop at this place',
     'Atlas: copied %d frames to the clipboard.',
     'Enter or double click: jump or expand · Ctrl+C: copy · Ctrl+F: search'));

{ TAtlasCallStackStrings }

class function TAtlasCallStackStrings.Text(AId: TAtlasCallStackTextId): string;
begin
  Result := cTexts[TAtlasStrings.Language, AId];
end;

class function TAtlasCallStackStrings.Fmt(AId: TAtlasCallStackTextId; const AArgs: array of const): string;
begin
  Result := Format(cTexts[TAtlasStrings.Language, AId], AArgs);
end;

end.
