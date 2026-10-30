unit Atlas.Common.Hotspots.Contract;

// Contract des Features Hotspots (#1354): Änderungshäufigkeit aus der
// Versionsverwaltung mal Komplexität aus den Metriken (#66), dazu die
// Änderungskopplung (Dateien, die fast immer zusammen geändert werden, ohne
// uses-Kante zwischen ihnen).
//
// IHotspotVcs ist die Sicht des Features auf die Versionsverwaltung. Der Host
// (Shell.Hotspots) setzt sie mit git bzw. svn um; das Feature selbst startet
// keine Prozesse. Pfade in THotspotCommit sind relativ zur Wurzel der
// Arbeitskopie mit "/", Zeitpunkte in UTC.

interface

uses
  System.SysUtils;

type
{$SCOPEDENUMS ON}
  THotspotVcsKind = (None, Git, Svn);

  /// <summary>Art der Änderung einer Datei in einem Commit.</summary>
  THotspotChangeKind = (Modified, Added, Deleted, Renamed);

  /// <summary>Auswertung je Unit oder je Methode (MCP "level").</summary>
  THotspotLevel = (Units, Methods);

  /// <summary>Entwicklung der Komplexität gegenüber dem Stand vor THotspotOptions.TrendMonths Monaten: Unknown =
  /// nicht berechnet, New = gab es damals noch nicht.</summary>
  THotspotTrend = (Unknown, Rising, Steady, Falling, New);

  /// <summary>Ergebnis von IHotspotVcs.TextAt: Found = Inhalt gelesen, Missing = die Datei gab es damals nicht,
  /// Unknown = nicht feststellbar (Verlauf reicht nicht so weit zurück, Fehler von git bzw. svn).</summary>
  THotspotTextState = (Found, Missing, Unknown);
{$SCOPEDENUMS OFF}

  /// <summary>Eine geänderte Datei in einem Commit.</summary>
  THotspotFileChange = record
    /// <summary>Pfad nach dem Commit, relativ zur Wurzel mit "/".</summary>
    Path: string;
    /// <summary>Pfad vor dem Commit bei Renamed, sonst ''.</summary>
    OldPath: string;
    Kind: THotspotChangeKind;
    /// <summary>Hinzugefügte und gelöschte Zeilen; -1 unbekannt (Binärdatei, SVN-Log).</summary>
    Added: Integer;
    Deleted: Integer;
    class function Make(const APath, AOldPath: string; AKind: THotspotChangeKind;
      AAdded, ADeleted: Integer): THotspotFileChange; static;
  end;

  THotspotCommit = record
    /// <summary>Git: Commit; SVN: Revisionsnummer.</summary>
    Revision: string;
    Author: string;
    /// <summary>UTC.</summary>
    Date: TDateTime;
    /// <summary>Erste Zeile der Nachricht.</summary>
    Summary: string;
    Files: TArray<THotspotFileChange>;
  end;

  /// <summary>Commit, der einen Zeilenbereich (Methode) geändert hat.</summary>
  THotspotLineCommit = record
    Revision: string;
    Author: string;
    /// <summary>UTC.</summary>
    Date: TDateTime;
    /// <summary>Erste Zeile der Nachricht.</summary>
    Summary: string;
    /// <summary>Geänderte Zeilen im Bereich; -1 unbekannt.</summary>
    Added: Integer;
    Deleted: Integer;
  end;

  /// <summary>Versionsverwaltung für die Hotspots (#1354). Jede Methode der Umsetzung startet einen Prozess: nur aus
  /// einem Arbeitsthread aufrufen.</summary>
  IHotspotVcs = interface
    ['{6C3E8F21-4B7A-4D95-A2C1-8E0F5B3D9A74}']
    function Kind: THotspotVcsKind;
    /// <summary>Wurzel der Arbeitskopie ohne abschließenden Trenner.</summary>
    function Root: string;
    /// <summary>Stand der Arbeitskopie (Git HEAD, SVN Revision); ändert sich mit jedem Commit. '' unbekannt.</summary>
    function Head: string;
    /// <summary>Commits seit ASince (UTC), neueste zuerst, mit geänderten Dateien; Umbenennungen als Renamed mit
    /// OldPath. False mit AError, wenn git bzw. svn scheitert.</summary>
    function Log(ASince: TDateTime; out ACommits: TArray<THotspotCommit>; out AError: string): Boolean;
    /// <summary>Commits, die die Zeilen AFirstLine..ALastLine (1-basiert, aktueller Stand) von AFileName (voller
    /// Pfad) seit ASince geändert haben, neueste zuerst; folgt Umbenennungen. False, wenn git bzw. svn scheitert.
    /// </summary>
    function LineLog(const AFileName: string; AFirstLine, ALastLine: Integer; ASince: TDateTime;
      out ACommits: TArray<THotspotLineCommit>): Boolean;
    /// <summary>Inhalt von AFileName (Pfad relativ zur Wurzel mit "/", Name in jenem Stand) im letzten Stand vor
    /// ADate (UTC).</summary>
    function TextAt(const AFileName: string; ADate: TDateTime; out AText: string): THotspotTextState;
  end;

  /// <summary>Werte aus den Einstellungen hotspots.* und der Anfrage.</summary>
  THotspotOptions = record
    /// <summary>Ausgewerteter Zeitraum (hotspots.months, 1–60).</summary>
    Months: Integer;
    /// <summary>Mindestzahl gemeinsamer Commits für die Änderungskopplung (hotspots.coupling.minCommits).</summary>
    MinSharedCommits: Integer;
    /// <summary>Mindestanteil gemeinsamer Commits (0–1, Vorgabe 0,7).</summary>
    MinCouplingRatio: Double;
    /// <summary>Commits mit mehr Dateien zählen nicht für die Kopplung (Vorgabe 50).</summary>
    MaxCommitFiles: Integer;
    /// <summary>Methoden, deren Verlauf einzeln gelesen wird (Vorgabe 50).</summary>
    MethodCandidates: Integer;
    /// <summary>Units, deren Trend berechnet wird (Vorgabe 50).</summary>
    TrendCandidates: Integer;
    /// <summary>Abstand für den Trend in Monaten (Vorgabe 3).</summary>
    TrendMonths: Integer;
    class function Default: THotspotOptions; static;
  end;

  THotspots = record
  public
    /// <summary>"git", "svn" oder "".</summary>
    class function KindName(AKind: THotspotVcsKind): string; static;
    /// <summary>"rising", "steady", "falling", "new" oder "unknown".</summary>
    class function TrendKey(ATrend: THotspotTrend): string; static;
    /// <summary>Gegenstück zu TrendKey; unbekannt = Unknown.</summary>
    class function TrendOf(const AKey: string): THotspotTrend; static;
    /// <summary>"unit" oder "method".</summary>
    class function LevelKey(ALevel: THotspotLevel): string; static;
    class function TryLevelOf(const AKey: string; out ALevel: THotspotLevel): Boolean; static;
  end;

implementation

{ THotspotFileChange }

class function THotspotFileChange.Make(const APath, AOldPath: string; AKind: THotspotChangeKind;
  AAdded, ADeleted: Integer): THotspotFileChange;
begin
  Result.Path := APath;
  Result.OldPath := AOldPath;
  Result.Kind := AKind;
  Result.Added := AAdded;
  Result.Deleted := ADeleted;
end;

{ THotspotOptions }

class function THotspotOptions.Default: THotspotOptions;
begin
  Result.Months := 12;
  Result.MinSharedCommits := 5;
  Result.MinCouplingRatio := 0.7;
  Result.MaxCommitFiles := 50;
  Result.MethodCandidates := 50;
  Result.TrendCandidates := 50;
  Result.TrendMonths := 3;
end;

{ THotspots }

class function THotspots.KindName(AKind: THotspotVcsKind): string;
begin
  case AKind of
    THotspotVcsKind.Git:
      Result := 'git';
    THotspotVcsKind.Svn:
      Result := 'svn';
  else
    Result := '';
  end;
end;

class function THotspots.TrendKey(ATrend: THotspotTrend): string;
begin
  case ATrend of
    THotspotTrend.Rising:
      Result := 'rising';
    THotspotTrend.Steady:
      Result := 'steady';
    THotspotTrend.Falling:
      Result := 'falling';
    THotspotTrend.New:
      Result := 'new';
  else
    Result := 'unknown';
  end;
end;

class function THotspots.TrendOf(const AKey: string): THotspotTrend;
begin
  if SameText(AKey, 'rising') then
    Result := THotspotTrend.Rising
  else if SameText(AKey, 'steady') then
    Result := THotspotTrend.Steady
  else if SameText(AKey, 'falling') then
    Result := THotspotTrend.Falling
  else if SameText(AKey, 'new') then
    Result := THotspotTrend.New
  else
    Result := THotspotTrend.Unknown;
end;

class function THotspots.LevelKey(ALevel: THotspotLevel): string;
begin
  if ALevel = THotspotLevel.Methods then
    Result := 'method'
  else
    Result := 'unit';
end;

class function THotspots.TryLevelOf(const AKey: string; out ALevel: THotspotLevel): Boolean;
begin
  Result := True;
  if (AKey = '') or SameText(AKey, 'unit') then
    ALevel := THotspotLevel.Units
  else if SameText(AKey, 'method') then
    ALevel := THotspotLevel.Methods
  else
  begin
    ALevel := THotspotLevel.Units;
    Result := False;
  end;
end;

end.
