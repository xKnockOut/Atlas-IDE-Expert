unit Atlas.Common.Profiling.Contract;

// Stichproben-Profiler (#2057), Vertrag des Probers: Der Server (Atlas.Common.Lsp.Profiler) startet und beendet
// einen Prober; der Prober hält die Threads des Zielprogramms reihum kurz an, liest ihre Aufrufstapel als rohe
// Adressen und fasst gleiche Stapel zusammen (TAtlasRawStacks). Aufgelöst wird erst nach dem Lauf
// (Atlas.Common.Profiling.Sampling). Umsetzung unter Windows: Atlas.Windows.Profiling.Sampler.

interface

type
  /// <summary>Ein geladenes Modul des Zielprogramms: Basisadresse, Größe und voller Dateiname.</summary>
  TAtlasSampleModule = record
    Base: UInt64;
    Size: UInt64;
    FileName: string;
  end;

  /// <summary>Ein Aufrufstapel als rohe Adressen (Index 0 = innerster Rahmen) und wie oft er vorkam.</summary>
  TAtlasRawStack = record
    Addresses: TArray<UInt64>;
    Count: Integer;
  end;

  /// <summary>Ergebnis eines Laufs, wie der Prober es nach Stop liefert.</summary>
  TAtlasSampleRun = record
    Modules: TArray<TAtlasSampleModule>;
    /// <summary>Index des Hauptmoduls (.exe) in Modules; -1 unbekannt.</summary>
    MainModule: Integer;
    Stacks: TArray<TAtlasRawStack>;
    DurationMs: Int64;
  end;

  /// <summary>Nimmt Proben eines laufenden Prozesses in einem eigenen Thread.</summary>
  IAtlasProfileSampler = interface
    ['{6F0B7C6E-2E8A-4B4D-9C55-3A1D2E7F9B41}']
    /// <summary>Öffnet den Prozess und beginnt; False mit Grund in AError, wenn das nicht geht.</summary>
    function Start(AProcessId: Cardinal; AIntervalMs: Integer; out AError: string): Boolean;
    /// <summary>Beendet den Lauf (wartet auf den Thread) und liefert das Ergebnis; danach ist der Prober leer.
    /// </summary>
    function Stop: TAtlasSampleRun;
    /// <summary>False vor Start, nach Stop und sobald der Prozess beendet ist.</summary>
    function Running: Boolean;
    /// <summary>Bisher genommene Proben, in denen ein Thread gerechnet hat.</summary>
    function Samples: Integer;
    /// <summary>Hauptmodul (.exe) des Zielprogramms; '' vor Start.</summary>
    function MainFileName: string;
  end;

  /// <summary>Legt einen Prober an; nil, wo es keinen gibt (außerhalb von Windows).</summary>
  TAtlasProfileSamplerFactory = reference to function: IAtlasProfileSampler;

implementation

end.
