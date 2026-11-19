unit Atlas.IDE.Contracts.KnownErrors;

// Vertrag zwischen Modulen (#2460, Modulregeln 6 und 9): bekannte Fehler beim
// Exception-Halt. Der Debugger kennt den Halt und zeigt die Exception-Leiste,
// der Tracker kennt die Issues. Der Tracker stellt über seinen Scope
// IAtlasKnownErrors bereit: Er sucht zu einem Halt im Hintergrund passende
// Issues, merkt sich das Ergebnis je Signatur und führt die Knöpfe aus
// (Öffnen, als Kommentar anhängen, wieder öffnen, neues Issue). Der Debugger stellt
// IAtlasKnownErrorsView bereit und erfährt dort, dass ein Ergebnis nachkommt.
// Fehlt eines der Module, fragt das andere ins Leere und tut nichts. Nur
// Interfaces, kein Code; die Records stehen in Atlas.Core.KnownErrors.Contract.
// Alle Aufrufe im Hauptthread der IDE.

interface

uses
  Atlas.Core.KnownErrors.Contract;

type
  /// <summary>Stellt der Tracker bereit: bekannte Fehler zu einem Halt.</summary>
  IAtlasKnownErrors = interface
    ['{70816EF3-C54F-4389-9868-16AFCC8662DC}']
    /// <summary>Treffer zu AReport aus dem Zwischenspeicher der Sitzung; ohne Eintrag beginnt die Suche im
    /// Hintergrund (State = Busy), ihr Ende meldet IAtlasKnownErrorsView.KnownErrorsChanged. Blockiert nie.</summary>
    function Lookup(const AReport: TAtlasDebugExceptionReport): TAtlasKnownErrorsResult;
    /// <summary>Knopf AAction zum Treffer AKey ('' bei NewIssue) des Halts AReport.</summary>
    procedure Run(AAction: TAtlasKnownErrorAction; const AReport: TAtlasDebugExceptionReport; const AKey: string);
  end;

  /// <summary>Stellt der Debugger bereit: Ergebnis der Suche ist da.</summary>
  IAtlasKnownErrorsView = interface
    ['{B39F27BA-FC29-4C53-8939-11BB2B7B6CC9}']
    /// <summary>Eine Suche ist fertig: Lookup für den gezeigten Halt erneut fragen.</summary>
    procedure KnownErrorsChanged;
  end;

implementation

end.
