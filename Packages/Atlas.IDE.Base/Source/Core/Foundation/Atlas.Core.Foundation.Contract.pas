unit Atlas.Core.Foundation.Contract;

// Verträge für Base und Module ohne eigenes Feature: Quellen von Bereichen (Willkommensseite, Tracker-Kacheln), die
// erfahren, dass ihr Bereich gezeigt wird. TAtlasCalls.ShowSource ruft sie.

interface

type
  /// <summary>Datenquelle eines Bereichs, die erfährt, dass ihr Bereich gezeigt wird, und dann bei Bedarf im
  /// Hintergrund nachlädt.</summary>
  IAtlasShownSource = interface
    ['{972B5F6C-20FC-440E-A19C-37D65B0FBE72}']
    /// <summary>Der Bereich wird gezeigt.</summary>
    procedure Shown;
  end;

implementation

end.
