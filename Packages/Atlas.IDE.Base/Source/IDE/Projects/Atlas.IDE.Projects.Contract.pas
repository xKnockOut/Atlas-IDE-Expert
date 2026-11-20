unit Atlas.IDE.Projects.Contract;

// Contract des Features Projects im IDE-Teil (#1443): Module hören über ihn auf geänderte
// Projekt-Zusammenfassungen, die Atlas.IDE.Projects.Summaries schreibt.

interface

type
  /// <summary>Hört auf geänderte Projekt-Zusammenfassungen (Hauptthread). AProject: Projekt oder Projektgruppe,
  /// '' = mehrere oder unbekannt.</summary>
  IAtlasProjectSummaryListener = interface
    ['{6E0C5B7A-2F1D-4C8E-9A35-7D41B0E2C9F6}']
    procedure SummaryChanged(const AProject: string);
  end;

implementation

end.
