unit Atlas.Core.KnownErrors.Contract;

// Daten der bekannten Fehler beim Exception-Halt (#2460) ohne VCL und Open
// Tools API: der Halt, wie ihn der Debugger meldet, die Treffer und die
// Antwort des Trackers. Die Interfaces zwischen den Modulen stehen in
// Atlas.IDE.Contracts.KnownErrors; die Kern- und Oberflächen-Units beider
// Module arbeiten nur mit diesen Records. Nur Typen, kein Code.

interface

type
{$SCOPEDENUMS ON}
  /// <summary>Stand der Suche: aus (kein Tracker, Einstellung aus, keine Klasse), läuft, fertig.</summary>
  TAtlasKnownErrorsState = (Off, Busy, Done);
  /// <summary>Knöpfe: zum Treffer (Öffnen, Kommentar, Wieder öffnen) bzw. ohne Treffer (Neues Issue).</summary>
  TAtlasKnownErrorAction = (Open, Comment, Reopen, NewIssue);
{$SCOPEDENUMS OFF}

  /// <summary>Ein Halt an einer Exception, wie ihn der Debugger meldet.</summary>
  TAtlasDebugExceptionReport = record
    /// <summary>Gestartetes Projekt (.dproj); '' unbekannt.</summary>
    Project: string;
    ExceptionClass: string;
    ExceptionMessage: string;
    /// <summary>Routinen der Rahmen in eigenem Code, oberste zuerst („Unit1.TFoo.Bar“), ohne Parameter.</summary>
    OwnMethods: TArray<string>;
    /// <summary>Dieselben Rahmen als Text für Kommentar und Issue („Unit1.TFoo.Bar (Unit1.pas:42)“).</summary>
    OwnFrames: TArray<string>;
    /// <summary>Gezeigter Ort: Datei und Zeile (1-basiert, 0 = unbekannt).</summary>
    FileName: string;
    Line: Integer;
  end;

  /// <summary>Ein Treffer im Tracker.</summary>
  TAtlasKnownError = record
    /// <summary>Kennung wie im Tracker: "#753" (GitHub), "ATL-123" (YouTrack).</summary>
    Key: string;
    Title: string;
    /// <summary>Zustand wie im Tracker ("open", "In Arbeit", "Fixed"); '' unbekannt.</summary>
    State: string;
    /// <summary>Bearbeiter; '' ohne.</summary>
    Assignee: string;
    /// <summary>Erledigt bzw. geschlossen: „wieder aufgetreten?“.</summary>
    Resolved: Boolean;
  end;

  /// <summary>Antwort auf eine Anfrage nach bekannten Fehlern.</summary>
  TAtlasKnownErrorsResult = record
    State: TAtlasKnownErrorsState;
    /// <summary>Beste zuerst, höchstens vier.</summary>
    Errors: TArray<TAtlasKnownError>;
    /// <summary>Der Tracker schreibt Kommentare (issues.syncState und ein Tracker, der schreiben kann).</summary>
    CanComment: Boolean;
    /// <summary>Der Tracker bietet „Neues Issue …“ an (issues.create).</summary>
    CanCreate: Boolean;
  end;

implementation

end.
