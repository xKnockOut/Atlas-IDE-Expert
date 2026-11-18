unit Atlas.UI.Debug.NextStatement.Strings;

// Texte zu „Nächste Anweisung hier“ und zum gezogenen Ausführungspfeil (#871), auf Deutsch und Englisch. Die
// Sprache bestimmt Base (`TAtlasStrings.Language`); jeder Aufruf liest sie neu.

interface

{$SCOPEDENUMS ON}

type
  TAtlasNextStatementTextId = (Command, TipTitle, RerunOne, RerunMany, SkipOne, SkipMany, SameLine, OutsideRoutine,
    NoCode, OtherBlock, ForHead, NotStopped, NoEditor, Platform, NoAddress, Failed, Moved, NoticeConfirm);

  TAtlasNextStatementStrings = class
  public
    class function Text(AId: TAtlasNextStatementTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TAtlasNextStatementTextId; const AArgs: array of const): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Strings;

const
  cTexts: array[TAtlasLanguage, TAtlasNextStatementTextId] of string = (
    ('Nächste Anweisung hier',
     'Nächste Anweisung',
     'Zeile %d läuft erneut',
     'Zeilen %d–%d laufen erneut',
     'Zeile %d wird übersprungen',
     'Zeilen %d–%d werden übersprungen',
     'Hier steht der Ausführungspunkt schon',
     'Nur Zeilen derselben Routine',
     'Zeile ohne ausführbaren Code',
     'Nicht in einen anderen try-, finally- oder except-Teil oder eine anonyme Methode hinein oder heraus',
     'Nicht in den Kopf einer for-Schleife mit Zähler',
     'Nächste Anweisung: Das Programm ist nicht angehalten.',
     'Nächste Anweisung: kein Editor mit Quelltext.',
     'Nächste Anweisung setzen geht nur unter Win32 und Win64 (Plattform %s).',
     'Nächste Anweisung: Keine Adresse für Zeile %d gefunden.',
     'Nächste Anweisung: Der Debugger hat den Befehlszähler nicht übernommen.',
     'Nächste Anweisung: Zeile %d (%s). Mit F7 oder F8 geht es dort weiter.',
     'Experimentell: Atlas setzt nur den Befehlszähler. Stack, Register und Variablen bleiben, wie sie sind; das ' +
       'Programm kann danach falsch rechnen oder abstürzen. Trotzdem setzen? (Dieser Hinweis kommt nur einmal.)'),
    ('Set next statement here',
     'Next statement',
     'Line %d runs again',
     'Lines %d–%d run again',
     'Line %d is skipped',
     'Lines %d–%d are skipped',
     'The execution point is already here',
     'Only lines of the same routine',
     'Line without executable code',
     'Not into or out of another try, finally or except part or an anonymous method',
     'Not into the head of a counted for loop',
     'Next statement: the program is not paused.',
     'Next statement: no editor with source code.',
     'Setting the next statement only works on Win32 and Win64 (platform %s).',
     'Next statement: no address found for line %d.',
     'Next statement: the debugger did not accept the instruction pointer.',
     'Next statement: line %d (%s). F7 or F8 continues there.',
     'Experimental: Atlas only moves the instruction pointer. Stack, registers and variables stay as they are; the ' +
       'program may compute wrong results or crash afterwards. Set it anyway? (This notice appears only once.)'));

{ TAtlasNextStatementStrings }

class function TAtlasNextStatementStrings.Text(AId: TAtlasNextStatementTextId): string;
begin
  Result := cTexts[TAtlasStrings.Language, AId];
end;

class function TAtlasNextStatementStrings.Fmt(AId: TAtlasNextStatementTextId; const AArgs: array of const): string;
begin
  Result := Format(Text(AId), AArgs);
end;

end.
