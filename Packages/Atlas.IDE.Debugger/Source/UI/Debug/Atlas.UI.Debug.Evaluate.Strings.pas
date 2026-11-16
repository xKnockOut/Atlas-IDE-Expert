unit Atlas.UI.Debug.Evaluate.Strings;

// Texte des Auswertungsfensters (Auswerten/Ändern von Atlas) und des Ausdrucksverlaufs, auf Deutsch und Englisch
// (#1455). Die Sprache bestimmt Base (`TAtlasStrings.Language`); jeder Aufruf liest sie neu.

interface

{$SCOPEDENUMS ON}

type
  TAtlasEvaluateTextId = (
    DebugEvaluateCaption, DebugEvaluateSideEffects, DebugEvaluateInputHint, DebugEvaluateViewText,
    DebugEvaluateViewLines, DebugEvaluateViewJson, DebugEvaluateViewHex, DebugEvaluateModify, DebugEvaluatePin,
    DebugEvaluateUnpin, DebugEvaluateIdeDialog, DebugEvaluateKeys, DebugEvaluatePending, DebugEvaluateNotStopped,
    DebugEvaluateNoSelection, DebugEvaluateViewUnfit, DebugEvaluateLinesFailed, DebugEvaluateModifyTitle,
    DebugEvaluateModifyPrompt, DebugEvaluateModifyFailed, DebugEvaluateHistoryEmpty, DebugEvaluateNoFields,
    DebugEvaluateTimeout);

  TAtlasEvaluateStrings = class
  public
    class function Text(AId: TAtlasEvaluateTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TAtlasEvaluateTextId; const AArgs: array of const): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Strings;

const
  cTexts: array[TAtlasLanguage, TAtlasEvaluateTextId] of string = (
    ('Atlas: Auswerten',
     'Nebenwirkungen erlauben',
     'Ausdruck eingeben, Enter fügt ihn hinzu',
     'Text',
     'Zeilen',
     'JSON',
     'Hex',
     'Ändern …',
     'Festheften',
     'Lösen',
     'IDE-Dialog',
     'Enter: hinzufügen · Strg+Enter: festheften · Entf: entfernen · ↓ im leeren Feld: Verlauf · F2: ändern',
     'wird ausgewertet …',
     '‹Programm nicht angehalten›',
     'Eine Zeile wählen, um ihren Wert zu sehen.',
     'Diese Ansicht passt nicht zum Wert; gezeigt wird der Text.',
     'Keine Zeilen: „%s“ ließ sich nicht auswerten (%s).',
     'Wert ändern',
     'Neuer Wert für %s:',
     'Ändern von %s fehlgeschlagen: %s',
     '(kein Verlauf)',
     '(keine Felder)',
     '‹keine Antwort des Debuggers›'),
    ('Atlas: Evaluate',
     'Allow side effects',
     'Type an expression, Enter adds it',
     'Text',
     'Lines',
     'JSON',
     'Hex',
     'Modify …',
     'Pin',
     'Unpin',
     'IDE dialog',
     'Enter: add · Ctrl+Enter: pin · Del: remove · ↓ in the empty field: history · F2: modify',
     'evaluating …',
     '‹program not stopped›',
     'Select a row to see its value.',
     'This view does not fit the value; showing the text.',
     'No lines: “%s” could not be evaluated (%s).',
     'Modify value',
     'New value for %s:',
     'Modifying %s failed: %s',
     '(no history)',
     '(no fields)',
     '‹no answer from the debugger›'));

{ TAtlasEvaluateStrings }

class function TAtlasEvaluateStrings.Text(AId: TAtlasEvaluateTextId): string;
begin
  Result := cTexts[TAtlasStrings.Language, AId];
end;

class function TAtlasEvaluateStrings.Fmt(AId: TAtlasEvaluateTextId; const AArgs: array of const): string;
begin
  Result := Format(cTexts[TAtlasStrings.Language, AId], AArgs);
end;

end.
