unit Atlas.UI.Debug.DataSetTable.Strings;

// Texte des Fensters „Datenmenge als Tabelle“ (#3024) und des Knopfs „Tabelle“ im Fenster „Auswerten“, auf Deutsch
// und Englisch. Die Sprache bestimmt Base (`TAtlasStrings.Language`); jeder Aufruf liest sie neu.

interface

{$SCOPEDENUMS ON}

type
  TAtlasDataSetTableTextId = (
    EvaluateTableButton, Title, Header, HeaderUnknownPosition, ColumnRecord, LoadMore, GoToRecord, EditValue,
    CopyCsv, CopyJson, Refresh, Cancel, Reading, StatusRows, StatusHelper, StatusCursor, StatusCurrentOnly,
    StatusAtEnd, ConsentNote, ConsentRead, ConsentCurrentOnly, NoMoveNote, UnknownPosition, HelperHint, NotADataSet,
    Running, GoToConfirm, EditConfirm, EditTitle, EditPrompt, EditFailed, GoToFailed, ReadFailed, NullValue,
    CursorRestored, SettingsDataSetTable, SettingsPageSize, SettingsMoveCursor, MoveCursorNever, MoveCursorAsk,
    MoveCursorAlways);

  TAtlasDataSetTableStrings = class
  public
    class function Text(AId: TAtlasDataSetTableTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TAtlasDataSetTableTextId; const AArgs: array of const): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Plugin.Localization.Strings;

const
  cTexts: array[TAtlasLanguage, TAtlasDataSetTableTextId] of string = (
    ('Tabelle …',
     'Datenmenge: %s',
     '%s · %s · Datensatz %d von %s',
     '%s · %s',
     '#',
     'Weitere %d laden',
     'Zum Datensatz springen',
     'Wert ändern …',
     'Als CSV kopieren',
     'Als JSON kopieren',
     'Aktualisieren',
     'Abbrechen',
     'wird gelesen …',
     'Zeilen %d–%d von %s',
     'gelesen über Atlas.Debug.DataSets, Cursor nicht bewegt',
     'gelesen durch Bewegen des Cursors, zurück auf Datensatz %d',
     'nur der aktuelle Datensatz',
     'Ende der Datenmenge',
     'Um mehr als den aktuellen Datensatz zu lesen, muss Atlas den Cursor von %s bewegen. Dabei laufen ' +
       'BeforeScroll, AfterScroll und OnCalcFields in Ihrem Programm. Danach kehrt Atlas zu Datensatz %d zurück.',
     '%d Zeilen lesen',
     'Nur aktueller Datensatz',
     'Mehr als den aktuellen Datensatz kann Atlas jetzt nicht lesen: %s',
     'Position unbekannt (RecNo %d)',
     'Schneller und ohne Cursorbewegung: Unit Atlas.Debug.DataSets aus dem Ordner „Vorlagen“ in Debug-Builds ' +
       'einbinden.',
     '„%s“ ist keine geöffnete Datenmenge (%s).',
     'Das Programm läuft; die Tabelle zeigt den letzten Stand.',
     'Cursor von %s auf Datensatz %d setzen? Dabei laufen BeforeScroll und AfterScroll in Ihrem Programm.',
     '%s.%s in Datensatz %d auf „%s“ setzen? Dabei laufen Edit, Post und deren Ereignisse in Ihrem Programm.',
     'Wert ändern',
     'Neuer Wert für %s (Datensatz %d):',
     'Ändern fehlgeschlagen: %s',
     'Springen fehlgeschlagen: %s',
     'Lesen abgebrochen: %s',
     '(NULL)',
     'Cursor zurückgestellt.',
     'Datenmenge als Tabelle (Knopf „Tabelle“)',
     'Zeilen je Seite',
     'Cursor zum Lesen bewegen',
     'nie',
     'nachfragen',
     'immer'),
    ('Table …',
     'Data set: %s',
     '%s · %s · record %d of %s',
     '%s · %s',
     '#',
     'Load %d more',
     'Go to record',
     'Edit value …',
     'Copy as CSV',
     'Copy as JSON',
     'Refresh',
     'Cancel',
     'reading …',
     'Rows %d–%d of %s',
     'read via Atlas.Debug.DataSets, cursor not moved',
     'read by moving the cursor, back on record %d',
     'current record only',
     'end of data set',
     'To read more than the current record, Atlas has to move the cursor of %s. BeforeScroll, AfterScroll and ' +
       'OnCalcFields run in your program. Atlas returns to record %d afterwards.',
     'Read %d rows',
     'Current record only',
     'Atlas cannot read more than the current record now: %s',
     'position unknown (RecNo %d)',
     'Faster and without moving the cursor: add the unit Atlas.Debug.DataSets from the “Vorlagen” folder to ' +
       'debug builds.',
     '“%s” is not an open data set (%s).',
     'The program is running; the table shows the last state.',
     'Move the cursor of %s to record %d? BeforeScroll and AfterScroll run in your program.',
     'Set %s.%s in record %d to “%s”? Edit, Post and their events run in your program.',
     'Edit value',
     'New value for %s (record %d):',
     'Editing failed: %s',
     'Going to the record failed: %s',
     'Reading stopped: %s',
     '(NULL)',
     'Cursor restored.',
     'Data set as table (button “Table”)',
     'Rows per page',
     'Move the cursor to read',
     'never',
     'ask',
     'always'));

{ TAtlasDataSetTableStrings }

class function TAtlasDataSetTableStrings.Text(AId: TAtlasDataSetTableTextId): string;
begin
  Result := cTexts[TAtlasStrings.Language, AId];
end;

class function TAtlasDataSetTableStrings.Fmt(AId: TAtlasDataSetTableTextId; const AArgs: array of const): string;
begin
  Result := Format(cTexts[TAtlasStrings.Language, AId], AArgs);
end;

end.
