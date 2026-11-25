unit Atlas.Core.Build.Contract;

// Contract des Plugin-Features Build (#1443): Compilermeldungen, Projekt eines Compiles und
// Bewertung eines Builds, dazu die Schnittstellen, über die Module Builds hören und
// bewerten (#528, #530, #1455). Die Root-Units des Features führen die Typen als Alias
// weiter.

interface

{$SCOPEDENUMS ON}

type
  TAtlasCompilerSeverity = (Info, Hint, Warning, Error, Fatal);

  TAtlasCompilerMessage = record
    FileName: string;
    /// <summary>1-basiert wie in der IDE; 0 ohne.</summary>
    Line: Integer;
    Column: Integer;
    Severity: TAtlasCompilerSeverity;
    Code: string;
    Text: string;
  end;

  TAtlasCompileKind = (Make, Build, Check, MakeUnit, Clean, Link);

  TAtlasCompileProject = record
    FileName: string;
    Kind: TAtlasCompileKind;
    Configuration: string;
    Platform: string;
    OutputFile: string;
    /// <summary>Eigene Hintergrundprüfung von Atlas (#548), kein Build des Benutzers.</summary>
    Background: Boolean;
    /// <summary>Wer den Build angestoßen hat: '' = Benutzer, "mcp" = ein KI-Assistent über build_project (#261).
    /// </summary>
    RequestedBy: string;
    /// <summary>Dauer des Compiles in ms (#758); setzt nur der Leser des Meldungsfensters nach dem Ende, sonst 0.
    /// </summary>
    DurationMs: Int64;
    /// <summary>Dauer des ganzen Laufs (Gruppe) in ms (#758); 0 = unbekannt.</summary>
    GroupDurationMs: Int64;
  end;

  /// <summary>Warum der Build nicht als erfolgreich gilt; None = erfolgreich.</summary>
  TAtlasBuildVerdictReason = (None, CompilerFailed, WarningsAsErrors, ZeroHints);

  TAtlasBuildVerdict = record
    /// <summary>Ergebnis des Compilers.</summary>
    Succeeded: Boolean;
    /// <summary>Gezählte Meldungen (ohne Basislinie).</summary>
    Errors: Integer;
    Warnings: Integer;
    Hints: Integer;
    /// <summary>Warnungen und Hinweise in der Basislinie, nicht gezählt.</summary>
    Baselined: Integer;
    /// <summary>Gezählte Warnungen und Hinweise aus build.warningsAsErrors.</summary>
    Promoted: Integer;
    /// <summary>Erster Code aus build.warningsAsErrors unter den Meldungen; '' ohne.</summary>
    PromotedCode: string;
    /// <summary>Basislinie befragt (Server antwortete)?</summary>
    BaselineChecked: Boolean;
    Reason: TAtlasBuildVerdictReason;
    /// <summary>Position der ersten maßgeblichen Meldung (Fehler, sonst Code aus warningsAsErrors, sonst erste
    /// gezählte Warnung bzw. Hinweis) mit Datei; -1 ohne.</summary>
    First: Integer;
    /// <summary>Gilt der Build als erfolgreich?</summary>
    function Effective: Boolean;
  end;

  /// <summary>Hört auf bewertete Builds des Benutzers (#530); Module stellen ihn über ihren Scope bereit (#1455),
  /// etwa die Tests nach dem Build (#69). Hauptthread, nach Zusammenfassung und Benachrichtigung.</summary>
  IAtlasBuildVerdictListener = interface
    ['{5F6C837F-1473-4EC8-B2F9-1A81BF8A7DAD}']
    procedure BuildEvaluated(const AMessages: TArray<TAtlasCompilerMessage>; const AProject: TAtlasCompileProject;
      const AVerdict: TAtlasBuildVerdict);
  end;

  /// <summary>Gelesene Compilermeldungen eines Builds (#528), Hauptthread.</summary>
  IAtlasCompilerMessagesListener = interface
    ['{28D76957-B5BE-4AB0-8E6C-469673E9C75D}']
    procedure MessagesRead(const AMessages: TArray<TAtlasCompilerMessage>; const AProject: TAtlasCompileProject);
  end;

  /// <summary>Bewertung eines Builds des Benutzers mit lesbaren Meldungen (#530), Hauptthread.</summary>
  IAtlasBuildEvaluator = interface
    ['{7A57B5A5-A39B-4709-9063-BFE893CBA09B}']
    /// <summary>True: übernimmt die Bewertung (Folgen über IAtlasBuildVerdictListener); False: Base trägt den Build
    /// ohne Bewertung ein.</summary>
    function Evaluate(const AMessages: TArray<TAtlasCompilerMessage>; const AProject: TAtlasCompileProject;
      ASucceeded: Boolean): Boolean;
  end;

implementation

{ TAtlasBuildVerdict }

function TAtlasBuildVerdict.Effective: Boolean;
begin
  Result := Reason = TAtlasBuildVerdictReason.None;
end;

end.
