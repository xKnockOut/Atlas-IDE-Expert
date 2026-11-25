unit Atlas.Common.Mcp.Contract.Vcs;

// Was die MCP-Werkzeuge von der Versionsverwaltung des Arbeitsordners brauchen: geänderte Dateien samt Zeilen
// (prepare_commit), Verlauf für Hotspots (get_hotspots) und Verlauf einzelner Symbole (get_symbol_history). Git oder
// SVN nach vcs.* in den Einstellungen. Der Host verbindet es mit seinem Zugang zur Versionsverwaltung
// (Adapters.Mcp.Vcs); die MCP-Werkzeuge kennen nur diese Unit.

interface

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.History.Contract,
  Atlas.Common.Hotspots.Contract;

type
  /// <summary>Änderungen einer Arbeitskopie.</summary>
  IMcpVcsChanges = interface
    ['{8E31D6A2-5C47-4B9F-A0D3-17F64B2E9C58}']
    /// <summary>Name der Versionsverwaltung (git, svn).</summary>
    function Name: string;
    /// <summary>Git statt SVN (Commit-Präfix im Git-Verzeichnis).</summary>
    function Git: Boolean;
    /// <summary>Wurzel der Arbeitskopie.</summary>
    function RepoRoot: string;
    /// <summary>Geänderte Dateien mit vollem Pfad.</summary>
    function Files: TArray<string>;
    /// <summary>Ist Zeile ALine (0-basiert) der Datei AFileName (voller Pfad) geändert? False für Dateien ohne
    /// geänderte Zeilen.</summary>
    function LineChanged(const AFileName: string; ALine: Integer): Boolean;
  end;

  IMcpVcs = interface
    ['{4C2F7B1E-93A8-4D65-B0E1-6A9F2C83D714}']
    /// <summary>Änderungen unter ARoot: ohne ABase die nicht eingecheckten gegenüber HEAD (SVN: BASE), mit ABase
    /// die seit der Abzweigung von ABase, jeweils mit neuen Dateien und geänderten Zeilen. False mit dem Grund in
    /// AError ohne Arbeitskopie, bei vcs.provider = off oder fehlendem Programm.</summary>
    function Changes(const ARoot, ABase: string; const ASettings: TServerSettings; out AChanges: IMcpVcsChanges;
      out AError: string): Boolean;
    /// <summary>Verlauf für Hotspots unter AFolder; False mit AError wie Changes.</summary>
    function Hotspots(const AFolder: string; const ASettings: TServerSettings; out AVcs: IHotspotVcs;
      out AError: string): Boolean;
    /// <summary>Verlauf einzelner Symbole unter AFolder; False mit AError wie Changes.</summary>
    function SymbolHistory(const AFolder: string; const ASettings: TServerSettings; out AVcs: ISymbolHistoryVcs;
      out AError: string): Boolean;
  end;

implementation

end.
