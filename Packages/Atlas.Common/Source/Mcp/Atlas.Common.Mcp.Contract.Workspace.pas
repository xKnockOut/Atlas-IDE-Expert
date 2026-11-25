unit Atlas.Common.Mcp.Contract.Workspace;

// Was die MCP-Werkzeuge vom Arbeitsbereich des Servers brauchen: Einstellungen, Projektdateien, Namensräume,
// Index, Nachladen von Units, Symbole je Datei, Code-Abfragen und den Stand des Index. Der Host verbindet es mit der
// Arbeitsbereichsgruppe (Adapters.Mcp.Workspace); die MCP-Werkzeuge kennen nur diese Unit.

interface

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Query.Contract;

type
  IMcpWorkspace = interface
    ['{D6FE62E6-E657-42F7-87E0-3CDE1844D1BF}']
    /// <summary>Wirksame Einstellungen des Hauptprojekts.</summary>
    function Settings: TServerSettings;
    /// <summary>Wirksame Einstellungen des Projekts der Gruppe, zu dem AFileName gehört, sonst des Hauptprojekts.
    /// </summary>
    function SettingsOf(const AFileName: string): TServerSettings;
    /// <summary>atlas.json des Hauptprojekts; '' ohne Datei.</summary>
    function SettingsFile: string;
    /// <summary>Globale Einstellungsdatei (%APPDATA%\Atlas\settings.json); '' ohne APPDATA.</summary>
    function GlobalSettingsFile: string;
    /// <summary>Namensräume des Hauptprojekts (Unit-Präfixe).</summary>
    function Namespaces: TArray<string>;
    /// <summary>Quelldateien des Hauptprojekts.</summary>
    function ProjectFiles: TArray<string>;
    /// <summary>Quelldateien aller Projekte der Gruppe.</summary>
    function AllFiles: TArray<string>;
    /// <summary>Projekte geladen und Index fertig? Sonst der Grund in AReason.</summary>
    function Ready(out AReason: string): Boolean;
    /// <summary>Name des Programms, das den Server gestartet hat (Anmeldung am Index-Cache); '' ohne.</summary>
    function Client: string;
    /// <summary>Symbolindex aller Projekte der Gruppe.</summary>
    function Index: ISymbolIndex;
    /// <summary>Lädt AUnitName über die Suchpfade des ersten Projekts nach, das sie findet.</summary>
    function EnsureUnit(const AUnitName: string): Boolean;
    /// <summary>EnsureUnit als Methodenreferenz für Dienste, die nachladen.</summary>
    function UnitLoader: TEnsureUnitFunc;
    /// <summary>Symbole und Include-Dateien zu AFileName (#860).</summary>
    function CheckSource(const AFileName: string): TPascalSource;
    /// <summary>Code-Abfragen über alle Projekte der Gruppe (#1351).</summary>
    function Queries: ICodeQueries;
  end;

implementation

end.
