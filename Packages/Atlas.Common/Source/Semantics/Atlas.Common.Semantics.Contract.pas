unit Atlas.Common.Semantics.Contract;

// Contract des Features Semantics: Auswertungen, die mehrere Namensauflöser
// teilen.
//
// - ITreeUnits hält den Unit-Index eines Syntaxbaums für alle Resolver eines
//   Prüflaufs (#1322). Ohne sie wertete jede Typabfrage (NodeType, Resolve)
//   eines nicht gepinnten Resolvers die ganze Unit neu aus, und Regeln mit
//   vielen Abfragen wurden quadratisch in der Unitgröße.

interface

uses
  Atlas.Common.Index.Contract,
  // Genehmigte Ausnahme der Rollenmatrix (Architektur.md, "Genehmigte Ausnahmen"): wie in Rules.Contract ist
  // der Syntaxbaum die Datengrundlage und hängt selbst nur an Contracts.
  Atlas.Common.Pascal.SyntaxTree;

type
  /// <summary>Unit-Index genau eines Syntaxbaums, einmal ausgewertet und von allen Resolvern eines Laufs
  /// geteilt (#1322). Gilt nur in einem Thread und nur, solange der Baum lebt: Der Besitzer ruft Clear,
  /// bevor er den Baum freigibt.</summary>
  ITreeUnits = interface
    ['{64C9DAD4-B538-4A12-93ED-55334C477C28}']
    /// <summary>Gehört die Auswertung zu ATree? Nur dann liefern Extracted und Merged dessen Stand.</summary>
    function Holds(ATree: TSyntaxTree): Boolean;
    /// <summary>Wie TIndexExtractor.Extract(Baum, AFileName), je Dateiname einmal ausgewertet.</summary>
    function Extracted(const AFileName: string): TUnitIndex;
    /// <summary>Extracted samt der Symbole der Include-Dateien aus AIndex und mit Namenstabelle, wie
    /// TNameResolver sie für Prepare braucht; je Dateiname einmal, solange AIndex derselbe bleibt.</summary>
    function Merged(const AIndex: ISymbolIndex; const AFileName: string): TUnitIndex;
    /// <summary>Vergisst Baum und Auswertungen; danach gehört sie zu keinem Baum mehr.</summary>
    procedure Clear;
  end;

implementation

end.
