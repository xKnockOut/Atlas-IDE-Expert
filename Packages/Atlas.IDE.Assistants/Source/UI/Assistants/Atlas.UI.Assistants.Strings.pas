unit Atlas.UI.Assistants.Strings;

// Oberflächentexte des Moduls KI-Assistenten auf Deutsch und Englisch (#1888, Muster der Module). Die Sprache
// bestimmt Base (`TAtlasStrings.Language`); jeder Aufruf liest sie neu. Kerntexte bleiben in `Atlas.UI.Strings`.

interface

{$SCOPEDENUMS ON}

type
  TAtlasAssistantsTextId = (
    BuildStarted, BuildFinished, BuildRefused, RequestUnreadable, RequestNoProject, RequestUnknownMode,
    NoBuildPipeline, SettingsEdit, SettingsMcpBuild,
    McpEditApplied, UndoActionMcp, SettingsContext, SettingsContextSelection, SettingsContextSelectionMax, ContextKind,
    InstructionsCommand, InstructionsWritten, InstructionsCurrent, InstructionsFailed, InstructionsNoAnswer,
    InstructionsNoFiles, InstructionsStale, SettingsInstructionsHint);

  TAtlasAssistantsStrings = class
  public
    class function Text(AId: TAtlasAssistantsTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TAtlasAssistantsTextId; const AArgs: array of const): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Strings;

const
  cTexts: array[TAtlasLanguage, TAtlasAssistantsTextId] of string = (
    ('Ein KI-Assistent baut %s in der IDE …',
     'Build für den KI-Assistenten beendet: %s, %d Fehler',
     'Build für den KI-Assistenten abgelehnt: %s (%s)',
     'Auftrag nicht lesbar',
     'Auftrag ohne Projekt',
     'Unbekannte Art "%s"; erlaubt sind make, build und check',
     'Das Modul Build-Pipeline ist nicht geladen oder abgeschaltet',
     'KI-Assistenten dürfen in offene Dateien schreiben (über den Editorpuffer)',
     'Builds für KI-Assistenten (MCP) über diese IDE erlauben (build_project)',
     'Atlas: MCP-Änderung in %s übernommen (Strg+Z macht sie rückgängig).',
     'Änderung über MCP',
     'IDE-Zustand für KI-Assistenten bereitstellen (Datei, Cursor, Methode, Projekt, Build; get_ide_context)',
     'Markierten Text mitgeben',
     'Höchstens Zeichen der Auswahl',
     'IDE-Zustand für KI-Assistenten',
     'Anweisungen für KI-Assistenten aktualisieren',
     'Atlas: Anweisungen für KI-Assistenten in %s geschrieben:',
     'Atlas: Anweisungen für KI-Assistenten in %s sind aktuell.',
     'Atlas: Anweisungen für KI-Assistenten in %s nicht geschrieben (%s).',
     'Atlas: Anweisungen für KI-Assistenten: Der Server hat nicht geantwortet.',
     'Atlas: Keine Anweisungsdatei in assistants.instructions.file.',
     'Atlas: Anweisungen für KI-Assistenten in %s veraltet; aktualisieren über Atlas › Anweisungen für ' +
       'KI-Assistenten aktualisieren.',
     'Hinweis, wenn die Anweisungen für KI-Assistenten nach einer Änderung an atlas.json veraltet sind'),
    ('An AI assistant is building %s in the IDE …',
     'Build for the AI assistant finished: %s, %d errors',
     'Build for the AI assistant refused: %s (%s)',
     'Request not readable',
     'Request without project',
     'Unknown mode "%s"; allowed are make, build and check',
     'The build pipeline module is not loaded or switched off',
     'AI assistants may write to open files (through the editor buffer)',
     'Allow builds for AI assistants (MCP) in this IDE (build_project)',
     'Atlas: MCP change applied to %s (Ctrl+Z undoes it).',
     'Change through MCP',
     'Provide the IDE state to AI assistants (file, cursor, method, project, build; get_ide_context)',
     'Include the selected text',
     'At most characters of the selection',
     'IDE state for AI assistants',
     'Update instructions for AI assistants',
     'Atlas: instructions for AI assistants written to %s:',
     'Atlas: instructions for AI assistants in %s are up to date.',
     'Atlas: instructions for AI assistants in %s not written (%s).',
     'Atlas: instructions for AI assistants: the server did not answer.',
     'Atlas: no instruction file in assistants.instructions.file.',
     'Atlas: instructions for AI assistants in %s are out of date; update with Atlas › Update instructions ' +
       'for AI assistants.',
     'Hint when the instructions for AI assistants are out of date after a change to atlas.json'));

{ TAtlasAssistantsStrings }

class function TAtlasAssistantsStrings.Text(AId: TAtlasAssistantsTextId): string;
begin
  Result := cTexts[TAtlasStrings.Language, AId];
end;

class function TAtlasAssistantsStrings.Fmt(AId: TAtlasAssistantsTextId; const AArgs: array of const): string;
begin
  Result := Format(Text(AId), AArgs);
end;

end.
