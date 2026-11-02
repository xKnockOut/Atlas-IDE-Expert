unit Atlas.Core.Updates.Contract;

// Prüfung auf neue Versionen (#495): Quelle der Versionsdatei als
// Schnittstelle, damit die Prüfung ohne Netzwerk testbar ist. Die einzige
// echte Quelle ist TAtlasHttpVersionSource (Adapters.HttpSource).

interface

type
  IAtlasVersionSource = interface
    ['{6B1F4D2E-8C3A-4E57-9B0D-2A7E5C1F3B94}']
    /// <summary>Versionsdatei unter AUrl lesen, höchstens ATimeoutMs; False mit AError (ohne Adresse) bei
    /// Fehler, Zeitüberschreitung oder Abbruch.</summary>
    function Fetch(const AUrl: string; ATimeoutMs: Integer; out AText, AError: string): Boolean;
  end;

implementation

end.
