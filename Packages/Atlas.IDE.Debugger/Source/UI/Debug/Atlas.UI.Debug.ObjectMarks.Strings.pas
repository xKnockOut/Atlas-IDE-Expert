unit Atlas.UI.Debug.ObjectMarks.Strings;

// Oberflächentexte für markierte Objekte beim Debuggen (#839) im Modul Debugger, auf Deutsch und Englisch: Befehle,
// Fenster „Markierte Objekte“, Etikett hinter Werten, Meldungen und Einstellung. Die Sprache bestimmt Base
// (`TAtlasStrings.Language`); jeder Aufruf liest sie neu.

interface

{$SCOPEDENUMS ON}

type
  TAtlasObjectMarksTextId = (
    SettingsDebugObjectMarks, ObjectMarksCaption, ObjectMarksCommand, MarkObjectCommand, MarkObjectTitle,
    MarkObjectPrompt, MarkObjectNoObject, MarkObjectNoExpression, MarkObjectDone, ObjectMarksValueFormat,
    ObjectMarksInlineFormat,
    ObjectMarksEmpty, ObjectMarksFreed, ObjectMarksRemove, ObjectMarksColor, ObjectMarksRename, ObjectMarksFooter,
    ObjectMarksColumnLabel, ObjectMarksColumnClass, ObjectMarksColumnAddress, ObjectMarksColumnSeen,
    ObjectMarksColumnState, ObjectMarksSeen);

  TAtlasObjectMarksStrings = class
  public
    class function Text(AId: TAtlasObjectMarksTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TAtlasObjectMarksTextId; const AArgs: array of const): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Plugin.Localization.Strings;

const
  cTexts: array[TAtlasLanguage, TAtlasObjectMarksTextId] of string = (
    ('Objekte beim Debuggen markieren und Etiketten an ihren Werten zeigen',
     'Markierte Objekte',
     'Markierte Objekte',
     'Objekt markieren …',
     'Objekt markieren',
     'Etikett für %s:',
     'Atlas: „%s“ ist im angehaltenen Programm kein Objekt.',
     'Atlas: An der Schreibmarke steht kein Ausdruck.',
     'Atlas: Objekt markiert als „%s“ (%s).',
     '%0:s  ‹%1:s›',
     '‹%1:s› %0:s',
     'Keine markierten Objekte. Im Halt: Rechtsklick auf einen Bezeichner › Atlas › Objekt markieren …',
     'vermutlich freigegeben',
     'Entfernen',
     'Farbe wechseln',
     'Etikett ändern …',
     'Entf entfernt · F2 ändert das Etikett · Leertaste wechselt die Farbe',
     'Etikett',
     'Klasse',
     'Adresse',
     'Zuletzt gesehen',
     'Zustand',
     '%s (%s)'),
    ('Mark objects while debugging and show labels next to their values',
     'Marked objects',
     'Marked objects',
     'Mark object …',
     'Mark object',
     'Label for %s:',
     'Atlas: "%s" is not an object in the stopped program.',
     'Atlas: There is no expression at the cursor.',
     'Atlas: Object marked as "%s" (%s).',
     '%0:s  ‹%1:s›',
     '‹%1:s› %0:s',
     'No marked objects. At a stop: right-click an identifier › Atlas › Mark object …',
     'probably freed',
     'Remove',
     'Change color',
     'Rename label …',
     'Del removes · F2 renames the label · Space changes the color',
     'Label',
     'Class',
     'Address',
     'Last seen',
     'State',
     '%s (%s)'));

{ TAtlasObjectMarksStrings }

class function TAtlasObjectMarksStrings.Text(AId: TAtlasObjectMarksTextId): string;
begin
  Result := cTexts[TAtlasStrings.Language, AId];
end;

class function TAtlasObjectMarksStrings.Fmt(AId: TAtlasObjectMarksTextId; const AArgs: array of const): string;
begin
  Result := Format(Text(AId), AArgs);
end;

end.
