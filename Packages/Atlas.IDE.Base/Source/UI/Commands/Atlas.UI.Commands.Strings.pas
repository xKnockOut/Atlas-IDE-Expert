unit Atlas.UI.Commands.Strings;

// Oberflächentexte des Features Befehle auf Deutsch und Englisch. Die Sprache bestimmt
// `TAtlasStrings.Language`; jeder Aufruf liest sie neu. Eigene Unit, damit ein neuer Text des Features nicht
// `Atlas.UI.Strings` ändert, die fast der ganze Kern verwendet; dort bleiben gemeinsame Texte.

interface

{$SCOPEDENUMS ON}

type
  TAtlasCommandsTextId = (
    ProjectSettingsMenu, MenuAtlas, MenuOptions, MenuEnableAll, EditorNoActions, EditorCopied, EditorTextCopied,
    EditorKindFix, EditorKindRefactor, EditorKindSource, EditorActionDisabled, EditorActionNote, UndoActionSlash,
    EditorMethodToggleNone, TestUnitNone, KeyMapTitle, KeyMapSearchHint, KeyMapOnlyConflicts, KeyMapSummary,
    KeyMapSummaryFiltered, KeyMapColumnKey, KeyMapColumnCommand, KeyMapColumnOrigin, KeyMapColumnContext,
    KeyMapColumnHint, KeyMapOriginIde, KeyMapOriginAtlas, KeyMapOriginPlugin, KeyMapContextGlobal,
    KeyMapContextEditor, KeyMapContextDesigner, KeyMapContextWelcome, KeyMapWins, KeyMapLoses, KeyMapNoneActive,
    KeyMapReasonAtlasPriority, KeyMapReasonAtlasYields, KeyMapReasonEditorBinding, KeyMapReasonLastBinding,
    KeyMapReasonFirstAction, KeyMapReasonOwnWindow, KeyMapExport, KeyMapConflictsButton, KeyMapRefresh, KeyMapClose,
    KeyMapPrint, KeyMapCreated, KeyMapFilter, KeyMapEditorBinding, KeyMapStartConflict, KeyMapNobody,
    KeyMapExportFailed, ShortcutTipLabel, ShortcutTipCommand, ShortcutTipNever, ShortcutTipAllKeys,
    ShortcutTipSpoken, AccessShortcutTip, KeyMapColumnRarely, KeyMapRarely, NotificationsTipTitle,
    NotificationsTipText, UsesActionMissing, ProblemNoneInFile, QuickOpenPrompt, QuickOpenOriginProject,
    QuickOpenOriginSearchPath, QuickOpenOriginLibrary, QuickOpenLine, QuickOpenLineHint, QuickOpenBuilding,
    QuickOpenNoEditor, FormatCodeNothing, FormatCodeOff, UndoActionFormat, ProblemsViewMenuAtlas,
    ProblemsViewMenuWindow, ProjectMenuCheck);

  TAtlasCommandsStrings = class
  public
    class function Text(AId: TAtlasCommandsTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TAtlasCommandsTextId; const AArgs: array of const): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Strings;

const
  cTexts: array[TAtlasLanguage, TAtlasCommandsTextId] of string = (
    ('Projekt-Einstellungen (atlas.json)…',
     'Atlas',
     'Optionen…',
     'Abgeschaltete Funktionen einschalten (%s)',
     'Atlas: An dieser Stelle gibt es keine Code-Aktionen.',
     'Atlas: In die Zwischenablage kopiert: %s',
     'Atlas: Text in die Zwischenablage kopiert.',
     'Korrektur',
     'Umbau',
     'Quelltext',
     'Atlas: %s geht hier nicht: %s',
     'Hinweis',
     'Schnellbefehl',
     'Atlas: Am Cursor steht keine Methode mit Deklaration und Implementierung.',
     'Keine Testunit: %s',
     'Atlas – Tastenkürzel',
     'Taste oder Befehl suchen, z. B. Strg+Umschalt+P',
     'Nur Konflikte',
     '%d Kürzel, %d Konflikte',
     '%d von %d Kürzeln, %d Konflikte',
     'Taste',
     'Befehl',
     'Herkunft',
     'Kontext',
     'Hinweis',
     'IDE',
     'Atlas',
     'Erweiterung %s',
     'global',
     'Editor',
     'Designer',
     'Willkommensseite',
     'gewinnt: %s',
     'unterliegt „%s“ (%s): %s',
     'doppelt belegt, keine Belegung aktiv',
     'Atlas hat Vorrang (Tastenkonflikte)',
     'Atlas überlässt die Taste (Tastenkonflikte)',
     'im Editor geht die Tastaturbelegung dem Menübefehl vor',
     'zuletzt angemeldete Tastaturbelegung',
     'erste Aktion in der Liste der IDE',
     'nur auf der Willkommensseite, dort gewinnt Atlas',
     'Als HTML exportieren',
     'Tastenkonflikte…',
     'Aktualisieren',
     'Schließen',
     'Drucken',
     'Stand: %s · %s',
     'Filter: %s',
     'Tastaturbelegung des Editors',
     'Atlas: %0:s ist doppelt belegt – %1:s (Atlas) und %2:s; es gewinnt %3:s. ' +
       'Übersicht: Atlas > Tastenkürzel-Übersicht; Entscheidung unter Tools > Optionen > Drittanbieter > Atlas > ' +
       'Tastenkonflikte.',
     'keine der beiden',
     'Atlas: Tastenkürzel-Übersicht konnte nicht exportiert werden (%s).',
     'Tipp:',
     'für „%s“',
     'Nicht mehr zeigen',
     'Alle Kürzel',
     'Tipp: %s für %s',
     'Tastenkürzel-Tipp',
     'Selten per Tastatur',
     '%d× Maus, %d× Tastatur',
     'Tastenkürzel: %s',
     '„%s“ geht auch mit %s.',
     'Atlas: Das geht hier nicht sicher (Direktive oder Kommentar in der uses-Liste).',
     'Atlas: Keine Befunde in dieser Datei.',
     'Datei suchen · @ Symbol der Datei · # Symbol im Projekt · : Zeile',
     'Projekt',
     'Suchpfad',
     'Bibliothek',
     'Zeile %d',
     'Zeilennummer eingeben',
     'Dateiliste wird aufgebaut …',
     'Keine Datei im Editor',
     'Atlas: Nichts zu formatieren.',
     'Atlas: „Formatieren“ ist ausgeschaltet (Tools › Optionen › Atlas › Editor).',
     'Formatieren',
     'Atlas',
     'Prüfung',
     'Mit Atlas prüfen'),
    ('Project settings (atlas.json)…',
     'Atlas',
     'Options…',
     'Re-enable switched-off features (%s)',
     'Atlas: No code actions here.',
     'Atlas: Copied to the clipboard: %s',
     'Atlas: Text copied to the clipboard.',
     'Quick fix',
     'Refactoring',
     'Source',
     'Atlas: %s is not possible here: %s',
     'Note',
     'Quick command',
     'Atlas: There is no method with declaration and implementation at the cursor.',
     'No test unit: %s',
     'Atlas – Keyboard shortcuts',
     'Search key or command, e.g. Ctrl+Shift+P',
     'Conflicts only',
     '%d shortcuts, %d conflicts',
     '%d of %d shortcuts, %d conflicts',
     'Key',
     'Command',
     'Origin',
     'Context',
     'Note',
     'IDE',
     'Atlas',
     'Extension %s',
     'global',
     'Editor',
     'Designer',
     'Welcome page',
     'wins: %s',
     'loses to "%s" (%s): %s',
     'assigned twice, none active',
     'Atlas has priority (key conflicts)',
     'Atlas leaves the key (key conflicts)',
     'in the editor the key binding comes before the menu command',
     'key binding registered last',
     'first action in the IDE list',
     'only on the welcome page, where Atlas wins',
     'Export as HTML',
     'Key conflicts…',
     'Refresh',
     'Close',
     'Print',
     'As of %s · %s',
     'Filter: %s',
     'Editor key binding',
     'Atlas: %0:s is assigned twice – %1:s (Atlas) and %2:s; %3:s wins. ' +
       'Overview: Atlas > Keyboard shortcuts; decide under Tools > Options > Third Party > Atlas > Key conflicts.',
     'neither',
     'Atlas: Could not export the keyboard shortcuts (%s).',
     'Tip:',
     'for “%s”',
     'Don''t show again',
     'All shortcuts',
     'Tip: %s for %s',
     'Keyboard shortcut tip',
     'Rarely by keyboard',
     '%d× mouse, %d× keyboard',
     'Shortcut: %s',
     '“%s” also works with %s.',
     'Atlas: This cannot be done safely here (directive or comment in the uses list).',
     'Atlas: No findings in this file.',
     'Search files · @ symbol in file · # symbol in project · : line',
     'Project',
     'Search path',
     'Library',
     'Line %d',
     'Enter a line number',
     'Building the file list …',
     'No file in the editor',
     'Atlas: Nothing to format.',
     'Atlas: “Format” is switched off (Tools › Options › Atlas › Editor).',
     'Format',
     'Atlas',
     'Findings',
     'Check with Atlas'));

{ TAtlasCommandsStrings }

class function TAtlasCommandsStrings.Text(AId: TAtlasCommandsTextId): string;
begin
  Result := cTexts[TAtlasStrings.Language, AId];
end;

class function TAtlasCommandsStrings.Fmt(AId: TAtlasCommandsTextId; const AArgs: array of const): string;
begin
  Result := Format(Text(AId), AArgs);
end;

end.
