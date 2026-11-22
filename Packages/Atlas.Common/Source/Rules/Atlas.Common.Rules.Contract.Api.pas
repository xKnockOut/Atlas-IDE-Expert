unit Atlas.Common.Rules.Contract.Api;

// API des Features Rules: was die Prüfregeln anderen Features anbieten. Sprachserver und MCP erreichen sie nur über
// Host-Adapter (Application/Source/Adapters), die ihre eigenen SPIs auf diese Schnittstellen abbilden; erzeugt
// werden Anbieter und Adapter in Shell.Composition.*. Argumente und Ergebnisse sind reine Werte aus den Contracts
// der Platform-Features.

interface

uses
  Atlas.Common.Index.Contract,
  Atlas.Common.Metrics.Contract;

type
  /// <summary>Vererbungstiefe der Klassen einer Datei wie bei der Regel metric-inheritance-depth (#980).</summary>
  IRuleInheritanceDepths = interface
    ['{7DE19472-351A-436A-B2C6-4E61D0ADEA80}']
    /// <summary>Je Klasse mit eigenen Vorfahren ein Eintrag (Kind InheritanceDepth): Vorfahren aus der Datei und
    /// AIndex (nil = nur die Datei) ohne RTL, VCL und Bibliotheken; AtLeast, wenn die Kette an einem unbekannten
    /// Vorfahren abbricht. Leer für Units der Bibliothek selbst.</summary>
    function Depths(const AFileName, AText: string; const AIndex: ISymbolIndex): TArray<TStructureMetrics>;
  end;

implementation

end.
