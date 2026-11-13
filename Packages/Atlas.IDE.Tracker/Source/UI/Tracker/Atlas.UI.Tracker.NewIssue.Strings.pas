unit Atlas.UI.Tracker.NewIssue.Strings;

// Oberflächentexte des Trackers für Neues Issue anlegen und Pfadvorschläge, auf Deutsch und Englisch (#1455).
// Die Sprache bestimmt Base (`TAtlasStrings.Language`); jeder Aufruf liest sie neu.

interface

{$SCOPEDENUMS ON}

type
  TAtlasNewIssueTextId = (
    NewIssueDialogTitle, NewIssueTracker, NewIssueProject, NewIssueSummary, NewIssueDescription,
    NewIssueIncludeCode, NewIssueType, NewIssuePriority, NewIssueAssignee, NewIssueAssignToMe, NewIssueStartNow,
    NewIssueLoading, NewIssueLoadFailed, NewIssueCreate, NewIssueCancel, NewIssueSending, NewIssueNoTitle,
    NewIssueNoTracker, NewIssueCreated, NewIssueOpen, NewIssueInsertComment, NewIssueTodoChanged, NewIssueNoToken,
    NewIssueNotConfigured, NewIssueRejected, NewIssueProjectUnknown, NewIssueInvalid, NewIssueUnreadable,
    NewIssueServerError, NewIssueUnreachable, NewIssueLabelLocation, NewIssueLabelLine, NewIssueLabelMethod,
    NewIssueLabelBranch, NewIssueLabelCommit, NewIssueLabelFindings, NewIssueFindingsTitle, NewIssueNoEditor,
    SuggestTitle, SuggestIntro, SuggestColumnPath, SuggestColumnKind, SuggestColumnWhy, SuggestWhyProject,
    SuggestWhyExternal, SuggestWhySubmodule, SuggestWhyGroup, SuggestWhyRemote, SuggestWhyWorktree, SuggestNothing,
    SuggestApply, SuggestSearching);

  TAtlasNewIssueStrings = class
  public
    class function Text(AId: TAtlasNewIssueTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TAtlasNewIssueTextId; const AArgs: array of const): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Strings;

const
  cTexts: array[TAtlasLanguage, TAtlasNewIssueTextId] of string = (
    ('Issue anlegen',
     'Tracker:',
     'Projekt:',
     'Titel:',
     'Beschreibung (Markdown):',
     'Codeausschnitt mitsenden',
     'Typ:',
     'Priorität:',
     'Zuständig:',
     'mir zuweisen',
     'gleich beginnen',
     'Listen des Trackers werden geladen …',
     'Listen nicht geladen; Typ, Priorität und Zuständig lassen sich eintippen.',
     'Anlegen',
     'Abbrechen',
     'Wird angelegt …',
     'Bitte einen Titel eingeben.',
     'Für dieses Projekt ist kein Issue-Tracker eingerichtet. Auf der Seite Issue-Tracker eine Verbindung anlegen und das Projekt zuordnen.',
     '%s angelegt; die Kennung steht in der Zwischenablage.',
     'Im Browser öffnen',
     'Kommentar „%s“ in die Cursorzeile einfügen?',
     'TODO ergänzt: %s',
     'Kein Token für %s hinterlegt; nichts gesendet.',
     'Tracker unvollständig eingerichtet (Adresse bzw. owner/repo fehlt); nichts gesendet.',
     'Der Tracker hat das Anlegen abgelehnt (HTTP %d); der Code bleibt unverändert.',
     'Projekt „%s“ ist im Tracker unbekannt; der Code bleibt unverändert.',
     'Der Tracker hat die Angaben abgelehnt: %s',
     'Antwort des Trackers nicht lesbar; bitte im Tracker nachsehen, ob das Issue angelegt wurde.',
     'Fehler beim Tracker (HTTP %d); der Code bleibt unverändert.',
     'Tracker nicht erreichbar; der Code bleibt unverändert.',
     'Fundstelle',
     'Zeile',
     'Methode',
     'Branch',
     'Commit',
     'Befunde',
     '%d Befunde in %s',
     'Kein Editor geöffnet.',
     'Arbeitskopien vorschlagen – %s',
     'Gefunden in der Projektdatei, deren Externals bzw. Submodulen, der Projektgruppe und den zuletzt geöffneten Projekten. Häkchen setzen, dann „Übernehmen“.',
     'Pfad',
     'Art',
     'Warum vorgeschlagen',
     'Arbeitskopie von %s',
     'svn:externals in %s',
     'Git-Submodul in %s',
     'Projekt der Gruppe: %s',
     'origin = %s',
     'Worktree desselben Repositorys',
     'Nichts gefunden – Ordner selbst wählen …',
     'Übernehmen',
     'Suche Arbeitskopien …'),
    ('Create issue',
     'Tracker:',
     'Project:',
     'Title:',
     'Description (Markdown):',
     'Include code snippet',
     'Type:',
     'Priority:',
     'Assignee:',
     'assign to me',
     'start right away',
     'Loading the tracker''s lists …',
     'Lists not loaded; type, priority and assignee can be typed.',
     'Create',
     'Cancel',
     'Creating …',
     'Please enter a title.',
     'No issue tracker is set up for this project. Add a connection on the Issue tracker page and assign the project.',
     '%s created; the key is on the clipboard.',
     'Open in browser',
     'Insert the comment "%s" at the cursor line?',
     'TODO updated: %s',
     'No token stored for %s; nothing sent.',
     'Tracker not fully set up (address or owner/repo missing); nothing sent.',
     'The tracker refused to create the issue (HTTP %d); the code stays unchanged.',
     'Project "%s" is unknown to the tracker; the code stays unchanged.',
     'The tracker rejected the input: %s',
     'The tracker''s answer is unreadable; please check in the tracker whether the issue was created.',
     'Tracker error (HTTP %d); the code stays unchanged.',
     'Tracker unreachable; the code stays unchanged.',
     'Location',
     'line',
     'Method',
     'Branch',
     'commit',
     'Findings',
     '%d findings in %s',
     'No editor open.',
     'Suggest working copies – %s',
     'Found in the project file, its externals or submodules, the project group and the recently opened projects. Tick the ones you want, then “Apply”.',
     'Path',
     'Kind',
     'Why suggested',
     'Working copy of %s',
     'svn:externals in %s',
     'Git submodule in %s',
     'Project of the group: %s',
     'origin = %s',
     'Worktree of the same repository',
     'Nothing found – choose folder…',
     'Apply',
     'Searching working copies…'));

{ TAtlasNewIssueStrings }

class function TAtlasNewIssueStrings.Text(AId: TAtlasNewIssueTextId): string;
begin
  Result := cTexts[TAtlasStrings.Language, AId];
end;

class function TAtlasNewIssueStrings.Fmt(AId: TAtlasNewIssueTextId; const AArgs: array of const): string;
begin
  Result := Format(cTexts[TAtlasStrings.Language, AId], AArgs);
end;

end.
