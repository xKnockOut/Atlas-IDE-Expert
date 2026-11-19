unit Atlas.Core.Tests.Contract;

// Verträge des Features Tests, die andere Teile erfüllen: das Schattenprojekt
// des Mutationslaufs (#1460), wie der Ablauf (Atlas.Core.Tests.MutationFlow)
// es braucht. In der IDE steht dahinter das echte Schattenprojekt
// (Atlas.IDE.Tests.Adapters.MutationShadowProject), in den Tests eine
// Fälschung.

interface

type
  {$SCOPEDENUMS ON}
  /// <summary>Wie die Test-EXE endete: Completed = gelaufen (Exitcode und Bericht zählen), Cancelled = abgebrochen,
  /// TimedOut = Zeitlimit, NotStarted = gar nicht gelaufen (fehlt, gesperrt, nicht startbar).</summary>
  TAtlasMutationRunState = (Completed, Cancelled, TimedOut, NotStarted);
  {$SCOPEDENUMS OFF}

  /// <summary>Ende des Builds: ASucceeded = übersetzt; AExecutable: die Test-EXE ('' = keine gefunden); AError: Build
  /// gar nicht gelaufen.</summary>
  TAtlasMutationBuilt = reference to procedure(ASucceeded: Boolean; const AExecutable, AError: string);
  /// <summary>Ende der Test-EXE: wie sie endete, Exitcode und XML-Bericht ('' = keiner).</summary>
  TAtlasMutationRan = reference to procedure(AState: TAtlasMutationRunState; AExitCode: Integer; const AXml: string);

  /// <summary>Das Schattenprojekt neben dem Testprojekt, wie der Ablauf es braucht.</summary>
  IAtlasMutationShadowProject = interface
    ['{4E5D92B9-A5F1-428C-9F07-B64BC3698A39}']
    /// <summary>Anlegen und öffnen; False mit Meldung AProblem.</summary>
    function Open(out AProblem: string): Boolean;
    /// <summary>Name für Meldungen.</summary>
    function Name: string;
    /// <summary>Kopie der Unit mit den Zeilen ALines schreiben; wirft bei Fehler.</summary>
    procedure Write(const ALines: TArray<string>);
    /// <summary>Vollständig bauen; False mit AReason, wenn nicht gebaut wird, sonst kommt ADone.</summary>
    function Build(const ADone: TAtlasMutationBuilt; out AReason: string): Boolean;
    /// <summary>Test-EXE AExecutable ausführen; ADone kommt im Hauptthread.</summary>
    procedure Run(const AExecutable: string; const ADone: TAtlasMutationRan);
    /// <summary>Schließen; auch nach gescheitertem Open. Wirft bei Fehler, der Ablauf meldet ihn.</summary>
    procedure Close;
  end;

implementation

end.
