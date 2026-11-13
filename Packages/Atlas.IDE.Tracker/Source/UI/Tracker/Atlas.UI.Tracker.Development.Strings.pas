unit Atlas.UI.Tracker.Development.Strings;

// Oberflächentexte des Trackers für Reiter „Entwicklung“ im Issue-Fenster: Branches, Commits, Pull Requests,
// Units, auf Deutsch und Englisch (#1455). Die Sprache bestimmt Base (`TAtlasStrings.Language`); jeder Aufruf
// liest sie neu.

interface

{$SCOPEDENUMS ON}

type
  TAtlasIssueDevTextId = (
    IssueDevLoading, IssueDevNoProject, IssueDevNoVcs, IssueDevVcsOff, IssueDevToolMissing, IssueDevVcsFailed,
    IssueDevBranches, IssueDevNoBranch, IssueDevColumnBranch, IssueDevColumnWhere, IssueDevColumnState,
    IssueDevLocal, IssueDevRemote, IssueDevLocalRemote, IssueDevAheadBehind, IssueDevCurrent, IssueDevSwitch,
    IssueDevSwitchAsk, IssueDevSwitchFailed, IssueDevSwitched, IssueDevCommits, IssueDevCommitsMore,
    IssueDevNoCommits, IssueDevColumnCommit, IssueDevColumnSubject, IssueDevColumnAuthor, IssueDevColumnTime,
    IssueDevCommitHint, IssueDevPulls, IssueDevNoPulls, IssueDevColumnNumber, IssueDevColumnChecks,
    IssueDevPullOpen, IssueDevPullDraft, IssueDevPullMerged, IssueDevPullClosed, IssueDevChecksPending,
    IssueDevChecksSuccess, IssueDevChecksFailure, IssueDevChecksUnknown, IssueDevTrackerChanges,
    IssueDevTrackerFailed, IssueDevUnits, IssueDevNoUnits, IssueDevOtherFiles, IssueDevDeleted, IssueDevDiffTitle,
    IssueDevDiffEmpty, IssueDevDiffFailed, IssueDevUnitMissing);

  TAtlasIssueDevStrings = class
  public
    class function Text(AId: TAtlasIssueDevTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TAtlasIssueDevTextId; const AArgs: array of const): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Strings;

const
  cTexts: array[TAtlasLanguage, TAtlasIssueDevTextId] of string = (
    ('Entwicklung wird gesucht …',
     'Kein Projekt geöffnet: Branches und Commits kommen aus der Arbeitskopie des Projekts.',
     'Das Projekt liegt in keiner Arbeitskopie (Git oder SVN).',
     'Die Versionsverwaltung ist abgeschaltet (vcs.provider = off).',
     '%s ist nicht installiert.',
     'Die Versionsverwaltung meldete einen Fehler (%s).',
     'Branches (%d)',
     'Kein Branch mit %s im Namen.',
     'Branch',
     'Ort',
     'Stand',
     'lokal',
     'entfernt',
     'lokal und entfernt',
     '%d voraus, %d zurück gegenüber %s',
     'aktuell',
     'Wechseln',
     'Die Arbeitskopie hat %d lokale Änderungen. Trotzdem zu %s wechseln?',
     'Wechsel zu %s ist gescheitert (%s).',
     'Gewechselt zu %s.',
     'Commits (%d)',
     'Commits (%d, ältere nicht durchsucht)',
     'Kein Commit mit %s in der Nachricht.',
     'Commit',
     'Betreff',
     'Autor',
     'Zeit',
     'Klick: Diff, Doppelklick: erste geänderte Unit an der Stelle öffnen',
     'Pull Requests (%d)',
     'Kein Pull Request zu %s.',
     'Nummer',
     'CI',
     'offen',
     'Entwurf',
     'gemergt',
     'geschlossen',
     '● läuft',
     '● grün',
     '● rot',
     '–',
     'Im Tracker verknüpfte Änderungen (%d)',
     'Tracker: %s',
     'Geänderte Units (%d)',
     'Keine geänderten Dateien in der Arbeitskopie.',
     'Ohne Projekt',
     '%s (gelöscht)',
     'Commit %s: %s',
     'Der Commit ändert keinen Text in der Arbeitskopie.',
     'Der Diff zu %s konnte nicht gelesen werden (%s).',
     '%s gibt es in der Arbeitskopie nicht.'),
    ('Looking for development…',
     'No project open: branches and commits come from the project’s working copy.',
     'The project is not in a working copy (Git or SVN).',
     'Version control is switched off (vcs.provider = off).',
     '%s is not installed.',
     'Version control reported an error (%s).',
     'Branches (%d)',
     'No branch with %s in its name.',
     'Branch',
     'Where',
     'Status',
     'local',
     'remote',
     'local and remote',
     '%d ahead, %d behind %s',
     'current',
     'Switch',
     'The working copy has %d local changes. Switch to %s anyway?',
     'Switching to %s failed (%s).',
     'Switched to %s.',
     'Commits (%d)',
     'Commits (%d, older ones not searched)',
     'No commit with %s in its message.',
     'Commit',
     'Subject',
     'Author',
     'Time',
     'Click: diff, double-click: open the first changed unit at the change',
     'Pull requests (%d)',
     'No pull request for %s.',
     'Number',
     'CI',
     'open',
     'draft',
     'merged',
     'closed',
     '● running',
     '● passed',
     '● failed',
     '–',
     'Changes linked in the tracker (%d)',
     'Tracker: %s',
     'Changed units (%d)',
     'No changed files in the working copy.',
     'No project',
     '%s (deleted)',
     'Commit %s: %s',
     'The commit changes no text in the working copy.',
     'The diff for %s could not be read (%s).',
     '%s does not exist in the working copy.'));

{ TAtlasIssueDevStrings }

class function TAtlasIssueDevStrings.Text(AId: TAtlasIssueDevTextId): string;
begin
  Result := cTexts[TAtlasStrings.Language, AId];
end;

class function TAtlasIssueDevStrings.Fmt(AId: TAtlasIssueDevTextId; const AArgs: array of const): string;
begin
  Result := Format(cTexts[TAtlasStrings.Language, AId], AArgs);
end;

end.
