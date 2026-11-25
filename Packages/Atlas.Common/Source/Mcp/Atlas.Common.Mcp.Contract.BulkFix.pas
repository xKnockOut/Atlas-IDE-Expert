unit Atlas.Common.Mcp.Contract.BulkFix;

// Was fix_findings (#1352) vom Server braucht: die Sammelkorrektur der Prüfregeln über ganze Dateien. Der Host
// verbindet es mit Rules (Adapters.Mcp.BulkFix); die MCP-Werkzeuge kennen nur diese Unit und schreiben selbst.

interface

uses
  Atlas.Common.Configuration.Contract;

type
  /// <summary>Eine Datei für fix_findings.</summary>
  TMcpFixInput = record
    /// <summary>Absoluter Pfad.</summary>
    FileName: string;
    /// <summary>Pfad relativ zum Arbeitsordner (Ausschlüsse, Baseline, Diff).</summary>
    RelativePath: string;
    Text: string;
  end;

  /// <summary>Ergebnis einer Datei.</summary>
  TMcpFixOutput = record
    FileName: string;
    OldText: string;
    /// <summary>Text nach den Korrekturen; gleich OldText, wenn nichts geändert oder verworfen wurde.</summary>
    NewText: string;
    /// <summary>Text geändert und nicht verworfen.</summary>
    Changed: Boolean;
    /// <summary>Vereinigter Diff mit dem relativen Pfad; leer ohne Änderung.</summary>
    Diff: string;
  end;

  TMcpFixRun = record
    Files: TArray<TMcpFixOutput>;
    /// <summary>Zusammenfassung für den Bericht als Vorschau.</summary>
    PreviewSummary: string;
    /// <summary>Zusammenfassung nach dem Schreiben.</summary>
    WrittenSummary: string;
  end;

  IMcpBulkFix = interface
    ['{875659F8-2F67-4F7E-AAE0-935B32C02485}']
    /// <summary>Korrigiert AFiles mit den Regeln AFixRules ("all" = alle) ab AMinConfidence ('' = fix.minConfidence,
    /// sonst nur höher); schreibt nichts. False mit Grund in AError.</summary>
    function Run(const AFiles: TArray<TMcpFixInput>; const AFixRules: TArray<string>; const AMinConfidence: string;
      const ASettings: TServerSettings; out ARun: TMcpFixRun; out AError: string): Boolean;
  end;

implementation

end.
