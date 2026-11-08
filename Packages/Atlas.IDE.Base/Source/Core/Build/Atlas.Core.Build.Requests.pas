unit Atlas.Core.Build.Requests;

// Builds auf Auftrag (#261, #1888) ohne Open Tools API: Auftrag, Ergebnis samt Compilermeldungen und Rückruf.
// Gemeinsame Daten des Läufers (Modul Build-Pipeline), des Eingangs der KI-Assistenten und des Vertrags
// Atlas.IDE.Contracts.BuildRequests; ein Typ je Rückruf, sonst E2010 unter Delphi 12.

interface

uses
  Atlas.Core.Build.Events,
  Atlas.Core.Build.Messages;

type
  /// <summary>Ein Build-Auftrag.</summary>
  TAtlasBuildRequest = record
    Id: string;
    /// <summary>Absoluter Pfad der .dproj.</summary>
    Project: string;
    /// <summary>Make, Build oder Check.</summary>
    Kind: TAtlasCompileKind;
    /// <summary>'' = aktive Konfiguration bzw. Plattform der IDE.</summary>
    Configuration: string;
    Platform: string;
  end;

  /// <summary>Ergebnis eines Builds auf Auftrag.</summary>
  TAtlasBuildReport = record
    /// <summary>Projekt, Art, Konfiguration und Plattform des Laufs.</summary>
    Project: TAtlasCompileProject;
    Succeeded: Boolean;
    DurationMs: Int64;
    /// <summary>Ortszeit des Endes.</summary>
    FinishedAt: TDateTime;
    Messages: TArray<TAtlasCompilerMessage>;
  end;

  /// <summary>Ende eines Auftrags; AError &lt;&gt; '' = nicht gebaut (Grund), sonst Ergebnis in AReport.</summary>
  TAtlasBuildDoneProc = reference to procedure(const AReport: TAtlasBuildReport; const AError: string);

implementation

end.
