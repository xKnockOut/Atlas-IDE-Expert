unit Atlas.Common.Mcp.Contract.DeadCode;

// Was find_unused_code (#64) vom Server braucht: die Regeln für ungenutzten Code über die Dateien eines Laufs. Der
// Host verbindet es mit Rules (Adapters.Mcp.DeadCode) und bindet dabei Regeln, Index, Projekte und Namensräume der
// Gruppe; die MCP-Werkzeuge kennen nur diese Unit.

interface

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Findings.Contract;

type
  IMcpDeadCode = interface
    ['{83976CDD-87D8-4C7D-8A21-75E3B91EE945}']
    /// <summary>Kennungen der Regeln für ungenutzten Code in der Reihenfolge des Berichts.</summary>
    function RuleIds: TArray<string>;
    /// <summary>Gibt es die Regeln für ungenutzten Code?</summary>
    function Available: Boolean;
    /// <summary>Alle Projekte geladen und indiziert? Sonst Grund in AReason; die projektweiten Regeln schweigen.
    /// </summary>
    function Complete(out AReason: string): Boolean;
    /// <summary>Text von AFileName, geöffnete Dokumente zuerst; False, wenn nicht lesbar.</summary>
    function ReadText(const AFileName: string; out AText: string): Boolean;
    /// <summary>Treffer der Regeln für ungenutzten Code in AText, dem Inhalt von AFileName; ARelativePath (relativ
    /// zum Arbeitsordner) für Regeln, Optionen und deadCode.keep* aus ASettings.</summary>
    function Check(const AFileName, ARelativePath, AText: string; const ASettings: TServerSettings):
      TArray<TRuleFinding>;
  end;

  /// <summary>Neuer Lauf von find_unused_code mit dem Stand der Projekte beim Aufruf.</summary>
  TMcpDeadCodeFunc = TFunc<IMcpDeadCode>;

implementation

end.
