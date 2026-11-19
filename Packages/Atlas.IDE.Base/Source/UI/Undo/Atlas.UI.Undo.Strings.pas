unit Atlas.UI.Undo.Strings;

// Oberflächentexte des Features Rückgängig auf Deutsch und Englisch. Die Sprache bestimmt
// `TAtlasStrings.Language`; jeder Aufruf liest sie neu. Eigene Unit, damit ein neuer Text des Features nicht
// `Atlas.UI.Strings` ändert, die fast der ganze Kern verwendet; dort bleiben gemeinsame Texte.

interface

{$SCOPEDENUMS ON}

type
  TAtlasUndoTextId = (
    UndoListTitle, UndoDisabled, UndoConflictChanged, UndoConflictExists, UndoConflictMissing, UndoFailed,
    UndoStateApplied, UndoStatePartly, UndoStateUndone, UndoKindCreated, UndoKindDeleted, UndoDiffTitle, UndoNoDiff,
    UndoSetCaption, UndoClose, UndoNothing, RedoNothing, UndoDone, RedoDone, UndoPartial, RedoPartial, UndoAborted,
    RedoAborted, UndoRecycleBinNotReachable);

  TAtlasUndoStrings = class
  public
    class function Text(AId: TAtlasUndoTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TAtlasUndoTextId; const AArgs: array of const): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Strings;

const
  cTexts: array[TAtlasLanguage, TAtlasUndoTextId] of string = (
    ('Atlas-Änderungen (%d) – Doppelklick zeigt den Unterschied, Rechtsklick nimmt zurück',
     'Atlas: Zurücknehmen über mehrere Dateien ist ausgeschaltet (undo.multiFile).',
     '  %s: nach der Aktion an diesen Stellen geändert',
     '  %s: gibt es inzwischen wieder',
     '  %s: fehlt',
     '  %s: %s',
     'angewendet',
     'teilweise zurückgenommen',
     'zurückgenommen',
     'neu',
     'gelöscht',
     'Atlas-Änderung: %s',
     '(kein Unterschied im Text)',
     '%s · %d Dateien · %s · %s',
     'Schließen',
     'Atlas: keine Atlas-Änderung zum Zurücknehmen.',
     'Atlas: keine Atlas-Änderung zum Wiederherstellen.',
     'Atlas: „%s“ in %d Dateien zurückgenommen.',
     'Atlas: „%s“ in %d Dateien wiederhergestellt.',
     'Atlas: „%s“ in %d Dateien zurückgenommen, %d Dateien blieben unverändert:',
     'Atlas: „%s“ in %d Dateien wiederhergestellt, %d Dateien blieben unverändert:',
     'Atlas: „%s“ nicht zurückgenommen, %d Dateien haben Konflikte (undo.multiFile.onConflict = abort):',
     'Atlas: „%s“ nicht wiederhergestellt, %d Dateien haben Konflikte (undo.multiFile.onConflict = abort):',
     'Papierkorb nicht erreichbar'),
    ('Atlas changes (%d) – double-click shows the difference, right-click undoes',
     'Atlas: undo across files is switched off (undo.multiFile).',
     '  %s: changed at these places after the action',
     '  %s: exists again in the meantime',
     '  %s: missing',
     '  %s: %s',
     'applied',
     'partly undone',
     'undone',
     'new',
     'deleted',
     'Atlas change: %s',
     '(no difference in the text)',
     '%s · %d files · %s · %s',
     'Close',
     'Atlas: no Atlas change to undo.',
     'Atlas: no Atlas change to redo.',
     'Atlas: "%s" undone in %d files.',
     'Atlas: "%s" redone in %d files.',
     'Atlas: "%s" undone in %d files, %d files were left unchanged:',
     'Atlas: "%s" redone in %d files, %d files were left unchanged:',
     'Atlas: "%s" not undone, %d files have conflicts (undo.multiFile.onConflict = abort):',
     'Atlas: "%s" not redone, %d files have conflicts (undo.multiFile.onConflict = abort):',
     'recycle bin not reachable'));

{ TAtlasUndoStrings }

class function TAtlasUndoStrings.Text(AId: TAtlasUndoTextId): string;
begin
  Result := cTexts[TAtlasStrings.Language, AId];
end;

class function TAtlasUndoStrings.Fmt(AId: TAtlasUndoTextId; const AArgs: array of const): string;
begin
  Result := Format(Text(AId), AArgs);
end;

end.
