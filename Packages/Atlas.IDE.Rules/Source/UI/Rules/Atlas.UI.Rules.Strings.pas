unit Atlas.UI.Rules.Strings;

// Oberflächentexte des Moduls Prüfregeln auf Deutsch und Englisch (ADR 0017, #1455). Die Sprache
// bestimmt Base (`TAtlasStrings.Language`); jeder Aufruf liest sie neu, ein Sprachwechsel braucht
// daher keine eigene Meldung. Kerntexte bleiben in `Atlas.UI.Strings`.

interface

{$SCOPEDENUMS ON}

type
  TAtlasRulesTextId = (
    BaselineUpdateCommand, BaselineUpdateNoProject, BaselineUpdateFailed, BaselineUpdateRunning, BaselineUpdateBusy,
    BaselineUpdateDone, BaselineUpdateCompleted, BaselineUpdateSetAside, BaselineUpdateOrphans,
    BaselineUpdateOrphanLine, BaselineUpdateOrphansMore, BaselineUpdateConfirm, BaselineUpdateElsewhere,
    WelcomeSetupBaselineElsewhere, DfmRulesFormCommand, DfmRulesProjectCommand, DfmRulesGroupCommand,
    DfmRulesNoForm, DfmRulesNoProject, DfmRulesNothing, DfmRulesFailed, DfmRulesPreviewTitle, DfmRulesPreviewHint,
    DfmRulesPreviewApply, DfmRulesDone, CompilerBaselineCommand, CompilerBaselineNone, CompilerBaselineDone,
    CompilerBaselineSkipped, CompilerBaselineFailed, CompilerBaselineNoProject, ProblemsFixAllNoFiles,
    ProblemsFixAllNothing, ProblemsFixAllDone, ProblemsFixAllFailed, ProblemsFixAllAction, FixPreviewTitle,
    FixPreviewRejected, FixPreviewSelection, FixPreviewApply, FixPreviewCancel);

  TAtlasRulesStrings = class
  public
    class function Text(AId: TAtlasRulesTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TAtlasRulesTextId; const AArgs: array of const): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Strings;

const
  Texts: array[TAtlasLanguage, TAtlasRulesTextId] of string = (
    ('Baseline des Projekts aktualisieren',
     'Baseline aktualisieren: kein aktives Projekt.',
     'Baseline aktualisieren: Der Atlas-Server hat keine Baseline geschrieben (Projekt noch nicht geladen, ' +
     'Server nicht bereit oder Zeitlimit überschritten).',
     'Baseline wird aktualisiert: Atlas prüft alle Dateien des Projekts …',
     'Baseline aktualisieren: Der Atlas-Server ist gerade beschäftigt; bitte gleich noch einmal versuchen.',
     'Baseline geschrieben: %s (%d Treffer, %d Dateien geprüft; %d neu, %d entfernt, %d unverändert)',
     'Baseline: %d Einträge der älteren Baseline um die Routine ergänzt.',
     'Baseline: Die bisherige Datei war unbrauchbar und liegt jetzt als %s daneben.',
     'Baseline: %d Einträge ohne Datei entfernt (umbenannt, verschoben oder gelöscht):',
     '  %s (%d Treffer)',
     '  … und %d weitere',
     'Die Baseline enthält %d Einträge ohne Datei (umbenannt, verschoben oder gelöscht):%sBeim Aktualisieren ' +
     'fallen sie heraus; die Treffer unter dem neuen Pfad nimmt die Baseline neu auf. Jetzt aktualisieren?',
     'Atlas: Der Server hat die Baseline in %0:s geschrieben, nicht im Projektordner %1:s (das Projekt ist dort ' +
     'wohl noch nicht als Arbeitsbereich bekannt). Projektverlauf und Einrichtung lesen die Baseline im ' +
     'Projektordner; bitte nach dem nächsten Build erneut aktualisieren.',
     'Die Baseline liegt nicht im Projektordner (Details in der Meldungsansicht).',
     'Eigenschaftsregeln anwenden: Formular',
     'Eigenschaftsregeln anwenden: Projekt',
     'Eigenschaftsregeln anwenden: Projektgruppe',
     'Im Editor ist keine Unit mit Formular offen.',
     'Kein aktives Projekt.',
     'Eigenschaftsregeln: nichts zu ändern.',
     'Eigenschaftsregeln anwenden fehlgeschlagen: %s',
     'Eigenschaftsregeln anwenden',
     '%d Änderungen in %d Formulardateien',
     'Anwenden',
     'Eigenschaftsregeln: %d Änderungen in %d Dateien übernommen.',
     'Aktuelle Compilermeldungen in die Basislinie',
     'Keine Warnungen oder Hinweise aus dem letzten Build von %s für die Basislinie.',
     'Compilermeldungen in die Basislinie übernommen: %s (%d Compilermeldungen; %d neu, %d entfernt, %d unverändert)',
     '%d Meldungen nicht übernommen: Datei nicht lesbar oder außerhalb des Projektordners.',
     'Compilermeldungen nicht in die Basislinie übernommen (Server nicht erreichbar oder Basislinie nicht lesbar).',
     'Kein aktives Projekt für die Basislinie.',
     'Keine Treffer von %s in der Liste.',
     'Keine sicheren Korrekturen für %s. %s',
     'Sammelkorrektur %s: %d Korrekturen in %d Dateien (%s)',
     'Sammelkorrektur %s nicht angewendet: %s',
     'Sichere Korrekturen: %s',
     'Sichere Korrekturen: %s',
     '%s: verworfen, die Korrektur ergäbe neue Syntaxfehler',
     '%d Korrekturen in %d Dateien gewählt',
     'Korrigieren',
     'Abbrechen'),
    ('Update project baseline',
     'Update baseline: no active project.',
     'Update baseline: the Atlas server wrote no baseline (project not loaded yet, server not ready or ' +
     'time limit exceeded).',
     'Updating baseline: Atlas is checking all files of the project …',
     'Update baseline: the Atlas server is busy right now; please try again shortly.',
     'Baseline written: %s (%d findings in %d files; %d added, %d removed, %d unchanged)',
     'Baseline: %d entries of the older baseline completed with their routine.',
     'Baseline: the previous file was unusable and has been set aside as %s.',
     'Baseline: removed %d entries without a file (renamed, moved or deleted):',
     '  %s (%d findings)',
     '  … and %d more',
     'The baseline contains %d entries without a file (renamed, moved or deleted):%sUpdating removes them; ' +
     'findings under the new path are added again. Update now?',
     'Atlas: The server wrote the baseline to %0:s, not to the project folder %1:s (it probably does not know ' +
     'the project as a workspace yet). Project history and setup read the baseline in the project folder; please ' +
     'update again after the next build.',
     'The baseline is not in the project folder (details in the Messages view).',
     'Apply property rules: form',
     'Apply property rules: project',
     'Apply property rules: project group',
     'No unit with a form is open in the editor.',
     'No active project.',
     'Property rules: nothing to change.',
     'Applying property rules failed: %s',
     'Apply property rules',
     '%d changes in %d form files',
     'Apply',
     'Property rules: %d changes in %d files applied.',
     'Add current compiler messages to the baseline',
     'No warnings or hints from the last build of %s for the baseline.',
     'Compiler messages added to the baseline: %s (%d compiler messages; %d new, %d removed, %d unchanged)',
     '%d messages not added: file not readable or outside the project folder.',
     'Compiler messages not added to the baseline (server not reachable or baseline not readable).',
     'No active project for the baseline.',
     'No findings of %s in the list.',
     'No safe fixes for %s. %s',
     'Bulk fix %s: %d fixes in %d files (%s)',
     'Bulk fix %s not applied: %s',
     'Safe fixes: %s',
     'Safe fixes: %s',
     '%s: rejected, the fix would cause new syntax errors',
     '%d fixes in %d files selected',
     'Fix',
     'Cancel'));

{ TAtlasRulesStrings }

class function TAtlasRulesStrings.Text(AId: TAtlasRulesTextId): string;
begin
  Result := Texts[TAtlasStrings.Language, AId];
end;

class function TAtlasRulesStrings.Fmt(AId: TAtlasRulesTextId; const AArgs: array of const): string;
begin
  Result := Format(Texts[TAtlasStrings.Language, AId], AArgs);
end;

end.
