unit Atlas.UI.Tracker.Commands.Strings;

// Oberflächentexte des Trackers für seine Befehle und Menüeinträge in der IDE (Atlas.IDE.Tracker.Parts), auf
// Deutsch und Englisch (#1455). Die Sprache bestimmt Base (`TAtlasStrings.Language`); jeder Aufruf liest sie neu.

interface

{$SCOPEDENUMS ON}

type
  TAtlasCommandsTextId = (AttachCommand, BoardCommand, BoardViewMenu, FlowCommand, FlowViewMenu, BlameIssuesCommand,
    IssuePreviewCommand, TrackerLoginCommand, CiLoginCommand, TimeOpenCommand);

  TAtlasCommandsStrings = class
  public
    class function Text(AId: TAtlasCommandsTextId): string; static;
  end;

implementation

uses
  Atlas.UI.Strings;

const
  cTexts: array[TAtlasLanguage, TAtlasCommandsTextId] of string = (
    ('An Issue anhängen …',
     'Board',
     'Board',
     'Ablauf-Karte',
     'Ablauf',
     'Issues zu dieser Methode',
     'Issue anzeigen …',
     'Zugang zum Issue-Tracker hinterlegen …',
     'Zugang zum Build-Server hinterlegen …',
     'Offene Zeitbuchungen …'),
    ('Attach to issue …',
     'Board',
     'Board',
     'Flow map',
     'Flow',
     'Issues for this method',
     'Show issue…',
     'Store issue tracker access …',
     'Store build server access …',
     'Pending time entries …'));

{ TAtlasCommandsStrings }

class function TAtlasCommandsStrings.Text(AId: TAtlasCommandsTextId): string;
begin
  Result := cTexts[TAtlasStrings.Language, AId];
end;

end.
