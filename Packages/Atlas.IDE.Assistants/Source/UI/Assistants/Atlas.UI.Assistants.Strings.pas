unit Atlas.UI.Assistants.Strings;

// Oberflächentexte des Moduls KI-Assistenten auf Deutsch und Englisch (#1888, Muster der Module). Die Sprache
// bestimmt Base (`TAtlasStrings.Language`); jeder Aufruf liest sie neu. Kerntexte bleiben in `Atlas.UI.Strings`.

interface

{$SCOPEDENUMS ON}

type
  TAtlasAssistantsTextId = (
    BuildStarted, BuildFinished, BuildRefused, RequestUnreadable, RequestNoProject, RequestUnknownMode,
    NoBuildPipeline, SettingsEdit, SettingsMcpBuild,
    McpEditApplied, UndoActionMcp,
    // Anzeige „KI-Assistent aktiv“ mit Pause (#1906).
    SettingsBanner, BannerBuilding, BannerEdited, BannerPaused, BannerHintActive, BannerHintPaused,
    PauseOn, PauseOff, RefusedPaused, PauseCommandOn, PauseCommandOff, PauseCommandHint);

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
     'Anzeige „KI-Assistent aktiv“ im Statusfeld mit Pause für KI-Assistenten',
     'KI-Assistent aktiv%s · baut %s',
     'KI-Assistent aktiv%s · %s geändert',
     'KI-Assistenten pausiert',
     'Klick: Pause für KI-Assistenten. Neue Builds und Änderungen an offenen Dateien lehnt die IDE dann ab; ' +
       'ein laufender Build läuft zu Ende.',
     'Klick: Pause aufheben. KI-Assistenten dürfen wieder über die IDE bauen und offene Dateien ändern.',
     'Atlas: Pause für KI-Assistenten. Neue Aufträge lehnt die IDE ab, bis die Pause aufgehoben ist.',
     'Atlas: Pause für KI-Assistenten aufgehoben.',
     'Pause für KI: Der Benutzer hat KI-Assistenten in der IDE angehalten. Nicht erneut senden, sondern warten ' +
       'oder nachfragen.',
     'Pause für KI-Assistenten',
     'Pause für KI-Assistenten aufheben',
     'Hält KI-Assistenten (MCP-Clients) an: Neue Builds und Änderungen an offenen Dateien lehnt die IDE mit Grund ' +
       'ab, bis die Pause aufgehoben ist.'),
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
     '“AI assistant active” display in the status field with pause for AI assistants',
     'AI assistant active%s · building %s',
     'AI assistant active%s · changed %s',
     'AI assistants paused',
     'Click: pause AI assistants. The IDE then refuses new builds and changes to open files; a running build ' +
       'finishes.',
     'Click: end the pause. AI assistants may build through the IDE and change open files again.',
     'Atlas: AI assistants paused. The IDE refuses new requests until the pause ends.',
     'Atlas: pause for AI assistants ended.',
     'Paused for AI: the user has paused AI assistants in the IDE. Do not send again; wait or ask.',
     'Pause AI assistants',
     'End pause for AI assistants',
     'Pauses AI assistants (MCP clients): the IDE refuses new builds and changes to open files with a reason ' +
       'until the pause ends.'));

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
