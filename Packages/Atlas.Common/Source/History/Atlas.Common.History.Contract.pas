unit Atlas.Common.History.Contract;

// Contract des Features Symbolgeschichte (#2641): Geschichte einer Routine oder eines Typs über die Commits, die
// ihre Zeilen geändert haben, und über Umbenennen und Verschieben hinweg.
//
// ISymbolHistoryVcs ist die Sicht des Features auf die Versionsverwaltung; der Host (Shell.Hotspots) setzt sie mit
// git bzw. svn um, das Feature startet selbst keine Prozesse. Pfade sind relativ zur Wurzel der Arbeitskopie mit
// "/", Zeitpunkte in UTC. Mit SVN gibt es nur die Zeilengeschichte im heutigen Stand.

interface

uses
  System.SysUtils,
  Atlas.Common.Hotspots.Contract;

type
  /// <summary>Commit, der einen Zeilenbereich geändert hat, mit seinem Unterschied am Bereich.</summary>
  TSymbolLineCommit = record
    /// <summary>Git: Commit; SVN: Revisionsnummer.</summary>
    Revision: string;
    Author: string;
    /// <summary>UTC.</summary>
    Date: TDateTime;
    /// <summary>Ganze Nachricht.</summary>
    Message: string;
    /// <summary>Zeilen des Unified-Diffs (Git: nur der verfolgte Bereich, SVN: die ganze Datei).</summary>
    Patch: TArray<string>;
  end;

  /// <summary>Versionsverwaltung der Symbolgeschichte. Jede Methode der Umsetzung startet einen Prozess: nur aus
  /// einem Arbeitsthread aufrufen.</summary>
  ISymbolHistoryVcs = interface
    ['{4E2B9C71-8D3A-4F06-B5E1-7A9C2D4F6B83}']
    function Kind: THotspotVcsKind;
    /// <summary>Wurzel der Arbeitskopie ohne abschließenden Trenner.</summary>
    function Root: string;
    /// <summary>Stand der Arbeitskopie (Git HEAD, SVN Revision); '' unbekannt.</summary>
    function Head: string;
    /// <summary>Commits, die die Zeilen AFirstLine..ALastLine (1-basiert) von APath im Stand ARevision ('' =
    /// heutiger Stand) geändert haben, neueste zuerst, höchstens AMaxCount; folgt Dateiumbenennungen. False, wenn git
    /// bzw. svn scheitert oder ARevision nicht unterstützt wird (SVN).</summary>
    function LineLog(const APath, ARevision: string; AFirstLine, ALastLine, AMaxCount: Integer;
      out ACommits: TArray<TSymbolLineCommit>): Boolean;
    /// <summary>Geänderte Dateien des Commits ARevision, Umbenennungen als Renamed mit OldPath. False ohne
    /// Unterstützung (SVN) oder wenn git scheitert.</summary>
    function CommitFiles(const ARevision: string; out AFiles: TArray<THotspotFileChange>): Boolean;
    /// <summary>Inhalt von APath im Stand ARevision bzw. mit ABefore im Stand davor; ARevision '' = übernommener
    /// Stand der Arbeitskopie (Git HEAD, SVN BASE). SVN kennt nur ''.</summary>
    function TextAt(const APath, ARevision: string; ABefore: Boolean; out AText: string): THotspotTextState;
  end;

{$SCOPEDENUMS ON}
  /// <summary>Was ein Commit mit dem Symbol gemacht hat.</summary>
  TSymbolEventKind = (Changed, Introduced, Renamed, Moved);

  /// <summary>Warum die Suche vor der Einführung des Symbols endete: None = vollständig.</summary>
  TSymbolHistoryStop = (None, Limit, TimeLimit, Cancelled, Hops, NoHistory, Failed);
{$SCOPEDENUMS OFF}

  /// <summary>Ein Eintrag der Geschichte.</summary>
  TSymbolEvent = record
    Kind: TSymbolEventKind;
    Revision: string;
    Author: string;
    /// <summary>UTC.</summary>
    Date: TDateTime;
    /// <summary>Erste Zeile der Nachricht.</summary>
    Summary: string;
    /// <summary>Geänderte Zeilen im Bereich; -1 unbekannt.</summary>
    Added: Integer;
    Deleted: Integer;
    /// <summary>Kennungen aus der Nachricht (#123, owner/repo#123, ABC-123 am Anfang).</summary>
    Issues: TArray<string>;
    /// <summary>Name des Symbols in diesem Commit (nach der Änderung).</summary>
    Symbol: string;
    /// <summary>Datei in diesem Commit; '' unbekannt (SVN).</summary>
    Path: string;
    /// <summary>Bei Renamed und Moved: Name und Datei davor.</summary>
    FromSymbol: string;
    FromPath: string;
    /// <summary>Bei Renamed und Moved: Ähnlichkeit der Rümpfe (0–1).</summary>
    Similarity: Double;
  end;

  /// <summary>Anfrage: Symbol, sein Bereich im heutigen Stand und die Grenzen.</summary>
  TSymbolHistoryRequest = record
    /// <summary>Name wie in der Datei (TFoo.Bar, Bar oder TFoo).</summary>
    Symbol: string;
    /// <summary>Datei relativ zur Wurzel der Arbeitskopie mit "/".</summary>
    Path: string;
    /// <summary>Bereich 1-basiert im heutigen Stand.</summary>
    FirstLine: Integer;
    LastLine: Integer;
    /// <summary>Routine (Umbenennen und Verschieben folgen nur Routinen).</summary>
    IsRoutine: Boolean;
    /// <summary>Höchstzahl der Einträge (1–200).</summary>
    Limit: Integer;
    FollowMoves: Boolean;
    /// <summary>Zeitlimit in ms; 0 = ohne.</summary>
    TimeoutMs: Integer;
    /// <summary>Abbruch durch den Client; nil = nie.</summary>
    Cancelled: TFunc<Boolean>;
    /// <summary>Schlüssel des Zwischenspeichers ohne Stand.</summary>
    function Key: string;
  end;

  TSymbolHistoryResult = record
    Symbol: string;
    Path: string;
    Kind: THotspotVcsKind;
    Head: string;
    /// <summary>Neueste zuerst.</summary>
    Events: TArray<TSymbolEvent>;
    Stop: TSymbolHistoryStop;
    /// <summary>Umbenennen und Verschieben verfolgt (Git und followMoves).</summary>
    FollowedMoves: Boolean;
    /// <summary>Aus dem Zwischenspeicher.</summary>
    Cached: Boolean;
  end;

  /// <summary>Dienst der Symbolgeschichte; merkt Ergebnisse je Stand. Threadsicher.</summary>
  ISymbolHistoryService = interface
    ['{9B1D4E62-3C7F-4A58-8E20-5F6A7B3C1D94}']
    function Run(const AVcs: ISymbolHistoryVcs; const ARequest: TSymbolHistoryRequest): TSymbolHistoryResult;
    /// <summary>Gemerkte Ergebnisse.</summary>
    function CachedCount: Integer;
  end;

  TSymbolHistory = record
  public
    /// <summary>"changed", "introduced", "renamed", "moved".</summary>
    class function EventKey(AKind: TSymbolEventKind): string; static;
    /// <summary>"", "limit", "timeLimit", "cancelled", "hops", "noHistory", "failed".</summary>
    class function StopKey(AStop: TSymbolHistoryStop): string; static;
  end;

implementation

{ TSymbolHistoryRequest }

function TSymbolHistoryRequest.Key: string;
begin
  Result := LowerCase(Symbol) + #1 + LowerCase(Path) + #1 + IntToStr(FirstLine) + #1 + IntToStr(LastLine) + #1 +
    IntToStr(Limit) + #1 + BoolToStr(FollowMoves, True);
end;

{ TSymbolHistory }

class function TSymbolHistory.EventKey(AKind: TSymbolEventKind): string;
begin
  case AKind of
    TSymbolEventKind.Introduced:
      Result := 'introduced';
    TSymbolEventKind.Renamed:
      Result := 'renamed';
    TSymbolEventKind.Moved:
      Result := 'moved';
  else
    Result := 'changed';
  end;
end;

class function TSymbolHistory.StopKey(AStop: TSymbolHistoryStop): string;
begin
  case AStop of
    TSymbolHistoryStop.Limit:
      Result := 'limit';
    TSymbolHistoryStop.TimeLimit:
      Result := 'timeLimit';
    TSymbolHistoryStop.Cancelled:
      Result := 'cancelled';
    TSymbolHistoryStop.Hops:
      Result := 'hops';
    TSymbolHistoryStop.NoHistory:
      Result := 'noHistory';
    TSymbolHistoryStop.Failed:
      Result := 'failed';
  else
    Result := '';
  end;
end;

end.
