unit Atlas.UI.Tracker.Contract.Sprint;

// Vertrag der Sprint-Kachel zwischen IDE und Oberfläche (#1277, #1443): was die
// Kachel zeigt (TAtlasSprintTile) und was sie auslöst (IAtlasSprintSource). Die
// Quelle setzt Atlas.IDE.Tracker.Adapters.Sprint um, gezeichnet wird in
// Atlas.UI.Tracker.SprintTile.

interface

uses
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Tracker.Contract.Sprint,
  Atlas.Core.Foundation.Contract;

type
{$SCOPEDENUMS ON}
  TAtlasSprintTileStatus = (NoProject, NoTracker, NoBoard, NoSprint, Loading, Failed, Ready);
{$SCOPEDENUMS OFF}

  /// <summary>Was die Kachel zeigt.</summary>
  TAtlasSprintTile = record
    Status: TAtlasSprintTileStatus;
    Sprint: TAtlasSprintView;
    /// <summary>Der Stand ist alt (ohne Netz bzw. Fehler); AError nennt den Grund.</summary>
    Stale: Boolean;
    Error: TAtlasCiFetchError;
    Loading: Boolean;
    /// <summary>issues.sprint.burndown bzw. issues.sprint.compare.</summary>
    Burndown: Boolean;
    Compare: Boolean;
    /// <summary>„zuordnen …“ möglich (#1261).</summary>
    CanAssign: Boolean;
  end;

  IAtlasSprintSource = interface(IAtlasShownSource)
    ['{2F7C9B14-6E3A-4D58-8B1F-0A4C7E2D9561}']
    function View: TAtlasSprintTile;
    // Shown (IAtlasShownSource): Der Bereich wird gezeigt: bei Bedarf den Sprint im Hintergrund laden.
    /// <summary>Fenster „Atlas-Board“ (#1272).</summary>
    procedure OpenBoard;
    procedure BrowseBoard;
    /// <summary>„Meine Issues“ auf die eigenen offenen (ADone = False) bzw. erledigten Issues des Sprints
    /// filtern.</summary>
    procedure FilterIssues(ADone: Boolean);
    procedure AssignProject;
  end;

implementation

end.
