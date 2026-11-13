unit Atlas.UI.Tracker.Board.Strings;

// Oberflächentexte des Trackers für Atlas-Board: Spalten, Swimlanes, Verschieben und Zuweisen, auf Deutsch
// und Englisch (#1455). Die Sprache bestimmt Base (`TAtlasStrings.Language`); jeder Aufruf liest sie neu.

interface

{$SCOPEDENUMS ON}

type
  TAtlasBoardTextId = (
    BoardCaption, BoardCommand, BoardViewMenu, BoardBoardHint, BoardSprintHint, BoardOnlyMine, BoardAll,
    BoardSearchHint, BoardRefresh, BoardLoading, BoardOffline, BoardEmpty, BoardEmptyMine, BoardNoTracker,
    BoardNoBoard, BoardNoColumn, BoardColumnOpen, BoardColumnClosed, BoardColumnCount, BoardLaneNone,
    BoardMoveTitle, BoardMoveQuestion, BoardMoveComment, BoardMoveOk, BoardMoveDontAsk, BoardMoving, BoardMoved,
    BoardMoveFailed, BoardMoveLocked, BoardMenuStart, BoardMenuPreview, BoardMenuBrowse, BoardMenuCopy,
    BoardMenuAssign, BoardAssigned, BoardAssignFailed, BoardErrorScopes, BoardMoveNoTransition, BoardMoveNotAllowed,
    BoardMoveTransitions);

  TAtlasBoardStrings = class
  public
    class function Text(AId: TAtlasBoardTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TAtlasBoardTextId; const AArgs: array of const): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Strings;

const
  cTexts: array[TAtlasLanguage, TAtlasBoardTextId] of string = (
    ('Atlas-Board',
     'Board',
     'Board',
     'Board bzw. Projekt',
     'Sprint bzw. Iteration',
     'Nur meine',
     'Alle',
     'Suchen (Kennung, Titel, Zuständig)',
     'Aktualisieren',
     'Wird geladen …',
     'Stand vom %s · %s · Ziehen ist gesperrt',
     'Keine Karten in diesem Sprint.',
     'Keine Karten für dich. „Alle“ zeigt das ganze Board.',
     'Für dieses Projekt ist kein Issue-Tracker eingerichtet.',
     'Kein Board gefunden (YouTrack: Agile Board mit diesem Projekt).',
     'Ohne Spalte',
     'Offen',
     'Geschlossen',
     '%s (%d)',
     'Ohne Zuordnung',
     'Karte verschieben',
     '%s → %s?',
     'Kommentar (optional, Markdown):',
     'Verschieben',
     'Nicht mehr fragen',
     '%s wird verschoben …',
     '%s → %s',
     '%s nicht verschoben: %s',
     'Ohne Verbindung zum Tracker lassen sich Karten nicht verschieben.',
     'Beginnen',
     'Vorschau',
     'Im Browser öffnen',
     'Kennung kopieren',
     'Mir zuweisen',
     '%s ist dir zugewiesen.',
     '%s nicht zugewiesen: %s',
     'Der Token darf Projekte nicht lesen bzw. ändern (GitHub: Berechtigung „project“).',
     '%s bleibt in „%s“: Der Workflow von YouTrack erlaubt von hier aus keinen Wechsel.',
     '%s nicht nach „%s“ verschoben: Der Workflow von YouTrack erlaubt von „%s“ aus nur: %s.',
     '%s Von „%s“ aus erlaubt der Workflow von YouTrack: %s.'),
    ('Atlas board',
     'Board',
     'Board',
     'Board or project',
     'Sprint or iteration',
     'Mine only',
     'All',
     'Search (key, title, assignee)',
     'Refresh',
     'Loading…',
     'As of %s · %s · moving is disabled',
     'No cards in this sprint.',
     'No cards for you. “All” shows the whole board.',
     'No issue tracker is set up for this project.',
     'No board found (YouTrack: agile board with this project).',
     'No column',
     'Open',
     'Closed',
     '%s (%d)',
     'Uncategorized',
     'Move card',
     '%s → %s?',
     'Comment (optional, Markdown):',
     'Move',
     'Don''t ask again',
     'Moving %s…',
     '%s → %s',
     '%s not moved: %s',
     'Cards cannot be moved without a connection to the tracker.',
     'Start',
     'Preview',
     'Open in browser',
     'Copy key',
     'Assign to me',
     '%s is assigned to you.',
     '%s not assigned: %s',
     'The token may not read or change projects (GitHub: scope “project”).',
     '%s stays in “%s”: the YouTrack workflow allows no transition from here.',
     '%s not moved to “%s”: from “%s” the YouTrack workflow only allows: %s.',
     '%s From “%s” the YouTrack workflow allows: %s.'));

{ TAtlasBoardStrings }

class function TAtlasBoardStrings.Text(AId: TAtlasBoardTextId): string;
begin
  Result := cTexts[TAtlasStrings.Language, AId];
end;

class function TAtlasBoardStrings.Fmt(AId: TAtlasBoardTextId; const AArgs: array of const): string;
begin
  Result := Format(cTexts[TAtlasStrings.Language, AId], AArgs);
end;

end.
