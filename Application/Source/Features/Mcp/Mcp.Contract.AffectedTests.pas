unit Mcp.Contract.AffectedTests;

// Was get_affected_tests (#1353) vom Host braucht: den Bericht über die betroffenen Tests einer Änderung. Der Host
// bestimmt sie aus dem Unterschied laut Git oder SVN, dem Index der Gruppe und der Auswirkungsanalyse
// (Adapters.Mcp.AffectedTests); die MCP-Werkzeuge kennen nur diese Unit.

interface

type
  /// <summary>Anfrage aus den Argumenten von get_affected_tests.</summary>
  TMcpAffectedQuery = record
    /// <summary>Arbeitsordner; dort laufen git bzw. svn.</summary>
    Root: string;
    /// <summary>Git-Ref bzw. SVN-Revision; '' = main bzw. BASE.</summary>
    Base: string;
    /// <summary>Index, Arbeitsverzeichnis und neue Dateien mitzählen.</summary>
    IncludeUncommitted: Boolean;
    /// <summary>1–5; 0 = tests.affectedDepth.</summary>
    Depth: Integer;
    /// <summary>text, json oder dunitx; '' = text.</summary>
    Format: string;
  end;

  IMcpAffectedTests = interface
    ['{5A1D8E36-0F4B-4C27-9B83-D2E6A47F1C09}']
    /// <summary>Bericht über die betroffenen Tests im Format von AQuery. False mit dem Grund in AError, wenn
    /// tests.affected aus ist, das Format unbekannt ist oder keine Arbeitskopie gefunden wird.</summary>
    function Report(const AQuery: TMcpAffectedQuery; out AText, AError: string): Boolean;
  end;

implementation

end.
