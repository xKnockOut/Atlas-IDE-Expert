unit Atlas.UI.Tracker.Sprint.Strings;

// Oberflächentexte des Trackers für Sprint-Kachel und Sprint beim Beginnen, auf Deutsch und Englisch (#1455).
// Die Sprache bestimmt Base (`TAtlasStrings.Language`); jeder Aufruf liest sie neu.

interface

{$SCOPEDENUMS ON}

type
  TAtlasSprintTextId = (
    WelcomeSprintTitle, WelcomeSprintDaysLeft, WelcomeSprintDayLeft, WelcomeSprintEnded, WelcomeSprintNotStarted,
    WelcomeSprintMineOpen, WelcomeSprintMineDone, WelcomeSprintTeamLeft, WelcomeSprintPoints, WelcomeSprintIssues,
    WelcomeSprintCompare, WelcomeSprintVelocity, WelcomeSprintNoProject, WelcomeSprintNoBoard,
    WelcomeSprintNoBoardFound, WelcomeSprintNoSprint, WelcomeSprintLoading, WelcomeSprintStale,
    WelcomeSprintDayHint, WelcomeSprintDayHintPrevious, WelcomeSprintHintOpen, WelcomeSprintHintDone,
    WelcomeSprintHintBoard, WelcomeSprintHintBrowse, WelcomeSprintHintAssign, SprintStartTitle, SprintStartQuestion,
    SprintStartAdd, SprintStartAddOpen, SprintStartDate, SprintStartDontAsk, SprintStartWithout, SprintStartAccept,
    SprintStartCancel);

  TAtlasSprintStrings = class
  public
    class function Text(AId: TAtlasSprintTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TAtlasSprintTextId; const AArgs: array of const): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Strings;

const
  cTexts: array[TAtlasLanguage, TAtlasSprintTextId] of string = (
    ('Sprint',
     'noch %d Tage',
     'noch 1 Tag',
     'beendet',
     'beginnt am %s',
     'meine offen',
     'meine erledigt',
     'Team übrig',
     'Punkte',
     'Issues',
     'erledigt %s · Vorsprint %s am selben Tag %s',
     'Velocity',
     'Kein Projekt geöffnet.',
     'Kein Board für dieses Projekt – zuordnen …',
     'Kein Board gefunden (YouTrack: Agile Board, GitHub: Projekt mit Iterationen).',
     'Das Board hat keinen Sprint mit Zeitraum.',
     'Wird geladen …',
     'Stand vom %s · %s',
     'Tag %d (%s): Rest %s · ideal %s',
     'Vorsprint %s',
     'Meine offenen Issues dieses Sprints in „Meine Issues“ zeigen',
     'Meine erledigten Issues dieses Sprints in „Meine Issues“ zeigen',
     'Board öffnen (Atlas-Board)',
     'Board im Browser öffnen',
     'Seite Issue-Tracker öffnen und das Projekt zuordnen',
     '%s beginnen',
     '%s „%s“ ist in keinem Sprint von „%s“.',
     'In den laufenden Sprint „%s“ (bis %s) aufnehmen?',
     'In den laufenden Sprint „%s“ aufnehmen?',
     'dd.mm.',
     'Nicht mehr fragen',
     'Ohne Sprint beginnen',
     'Aufnehmen und beginnen',
     'Abbrechen'),
    ('Sprint',
     '%d days left',
     '1 day left',
     'ended',
     'starts on %s',
     'my open',
     'my done',
     'team left',
     'points',
     'issues',
     'done %s · previous sprint %s on the same day %s',
     'Velocity',
     'No project open.',
     'No board for this project – assign …',
     'No board found (YouTrack: agile board, GitHub: project with iterations).',
     'The board has no sprint with a time frame.',
     'Loading …',
     'As of %s · %s',
     'Day %d (%s): left %s · ideal %s',
     'previous sprint %s',
     'Show my open issues of this sprint in “My issues”',
     'Show my finished issues of this sprint in “My issues”',
     'Open the board (Atlas board)',
     'Open the board in the browser',
     'Open the Issue tracker page and assign the project',
     'Start %s',
     '%s "%s" is in no sprint of "%s".',
     'Add it to the running sprint "%s" (until %s)?',
     'Add it to the running sprint "%s"?',
     'mmm d',
     'Don''t ask again',
     'Start without sprint',
     'Add and start',
     'Cancel'));

{ TAtlasSprintStrings }

class function TAtlasSprintStrings.Text(AId: TAtlasSprintTextId): string;
begin
  Result := cTexts[TAtlasStrings.Language, AId];
end;

class function TAtlasSprintStrings.Fmt(AId: TAtlasSprintTextId; const AArgs: array of const): string;
begin
  Result := Format(cTexts[TAtlasStrings.Language, AId], AArgs);
end;

end.
