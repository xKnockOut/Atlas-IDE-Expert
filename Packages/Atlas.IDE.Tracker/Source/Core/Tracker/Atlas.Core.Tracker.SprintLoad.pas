unit Atlas.Core.Tracker.SprintLoad;

// Abfrage des Bereichs „Sprint“ (#1277) ohne IDE prüfbar (#1967); die IDE (Atlas.IDE.Tracker.SprintTile) ruft nur
// noch Hintergrundarbeiter, Willkommensseite und Einstellungen:
// - Eine Abfrage im Hintergrund: aktueller Sprint (gewähltes Board, ist es weg: das erste des Projekts),
//   Arbeitstage und mit Vergleich die Vorsprints, abgeschlossene nur einmal (Zwischenspeicher), höchstens so
//   lange, wie Zeit übrig ist.
// - Stand der Kachel je Tracker: aus dem Zwischenspeicher, nach Antwort bzw. Fehler.
// - Wann neu geladen wird.

interface

uses
  System.Diagnostics,
  Atlas.Core.Ci.Contract,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Board,
  Atlas.Core.Tracker.Sprint;

type
  /// <summary>Ergebnis einer Abfrage im Hintergrund.</summary>
  TAtlasSprintResult = record
    Succeeded: Boolean;
    Snapshot: TAtlasBoardSnapshot;
    Calendar: TAtlasSprintCalendar;
    /// <summary>Arbeitstage kamen vom Tracker (sonst bleibt der Kalender des Stands).</summary>
    CalendarKnown: Boolean;
    Previous: TArray<TAtlasSprintSummary>;
    WithPrevious: Boolean;
    Error: TAtlasCiFetchError;
    /// <summary>Abgebrochen mit einer Ausnahme dieser Klasse (für das Protokoll); '' sonst.</summary>
    Aborted: string;
    /// <summary>Fehlschlag mit AError; ACalendar bleibt.</summary>
    class function Failed(const ACalendar: TAtlasSprintCalendar; AError: TAtlasCiFetchError): TAtlasSprintResult;
      static;
  end;

  /// <summary>Stand der Kachel für den Tracker des Projekts (letzte Antwort bzw. Zwischenspeicher).</summary>
  TAtlasSprintState = record
    HasSnapshot: Boolean;
    Snapshot: TAtlasBoardSnapshot;
    Calendar: TAtlasSprintCalendar;
    Previous: TArray<TAtlasSprintSummary>;
    // Die Vorsprints wurden mit dem Vergleich geladen (issues.sprint.compare eingeschaltet: neu laden).
    WithPrevious: Boolean;
    Stale: Boolean;
    Error: TAtlasCiFetchError;
    /// <summary>Neuer Tracker ATarget: Stand und Arbeitstage aus dem Zwischenspeicher in AFolder (ACacheName,
    /// AWorkDaysName), Vorsprints nur von dort; fehlt einer, holt ihn die nächste Abfrage.</summary>
    procedure Restore(const AFolder: string; const ATarget: TAtlasTrackerTarget; const ACacheName,
      AWorkDaysName: string);
    /// <summary>Antwort ohne Erfolg: letzter Stand bleibt mit Grund AError.</summary>
    procedure Fail(AError: TAtlasCiFetchError);
    /// <summary>Antwort AResult übernehmen, abgerufen ANow (UTC); Kalender nur, wenn der Tracker ihn kennt.</summary>
    procedure Take(const AResult: TAtlasSprintResult; ANow: TDateTime);
  end;

  /// <summary>Eine Abfrage: aktueller Sprint, Arbeitstage und mit Vergleich die Vorsprints; läuft im
  /// Hintergrund und schreibt nur in Outcome.</summary>
  TAtlasSprintJob = record
    Target: TAtlasTrackerTarget;
    Boards: IAtlasTrackerBoards;
    WorkDays: IAtlasTrackerWorkDays;
    Transport: IAtlasCiTransport;
    Folder: string;
    /// <summary>Gewähltes Board ('' = das erste des Projekts).</summary>
    BoardId: string;
    /// <summary>issues.sprint.compare: frühere Sprints fragen.</summary>
    Compare: Boolean;
    Watch: TStopwatch;
    Outcome: TAtlasSprintResult;
    procedure Execute;
    function LoadCurrent: Boolean;
    procedure LoadWorkDays;
    procedure LoadPrevious;
  end;

  TAtlasSprintLoad = class
  public const
    /// <summary>Weniger Zeit übrig: keine weiteren Vorsprints fragen.</summary>
    cMinLeftMs = 1000;
    cMsPerMinute = 60000;
  public
    /// <summary>Zusammenfassung des abgeschlossenen Sprints ASprintId aus dem Zwischenspeicher; False ohne
    /// (lesbare) Datei.</summary>
    class function CachedSummary(const AFolder: string; const ATarget: TAtlasTrackerTarget;
      const ABoardId, ASprintId: string; out ASummary: TAtlasSprintSummary): Boolean; static;
    /// <summary>Zusammenfassung eines abgeschlossenen Sprints merken; Fehler beim Schreiben werden übergangen.
    /// </summary>
    class procedure SaveSummary(const AFolder: string; const ATarget: TAtlasTrackerTarget; const ABoardId: string;
      const ASummary: TAtlasSprintSummary); static;
    /// <summary>Neu laden? Noch nie (ALoadedTick 0), nach ADueMinutes oder wenn issues.sprint.compare (ACompare) an
    /// ist, die Vorsprints aber ohne Vergleich geladen wurden.</summary>
    class function Due(ALoadedTick, ANowMs: UInt64; ADueMinutes: Integer; ACompare, AWithPrevious: Boolean): Boolean;
      static;
    class function NowUtc: TDateTime; static;
  end;

implementation

uses
  System.SysUtils,
  System.DateUtils;

{ TAtlasSprintResult }

class function TAtlasSprintResult.Failed(const ACalendar: TAtlasSprintCalendar;
  AError: TAtlasCiFetchError): TAtlasSprintResult;
begin
  Result := Default(TAtlasSprintResult);
  Result.Calendar := ACalendar;
  Result.Error := AError;
end;

{ TAtlasSprintJob }

procedure TAtlasSprintJob.Execute;
begin
  Watch := TStopwatch.StartNew;
  Outcome.WithPrevious := Compare;
  try
    Outcome.Succeeded := LoadCurrent;
    if Outcome.Succeeded then
    begin
      LoadWorkDays;
    end;
    if Outcome.Succeeded and Compare then
    begin
      LoadPrevious;
    end;
  except
    // Kein Dialog, kein Fehler an die IDE: als Netzfehler werten; die IDE schreibt die Klasse ins Protokoll.
    on E: Exception do
    begin
      Outcome.Succeeded := False;
      Outcome.Error := TAtlasCiFetchError.Network;
      Outcome.Aborted := E.ClassName;
    end;
  end;
  Transport := nil;
end;

function TAtlasSprintJob.LoadCurrent: Boolean;
begin
  Result := Boards.LoadBoard(TAtlasBoardRequest.Create(Target, Transport, BoardId, '', TAtlasTrackerBoard.cTimeoutMs),
    Outcome.Snapshot, Outcome.Error);
  // Board weg (gelöscht, kein Zugriff mehr): das erste des Projekts.
  if not Result and (BoardId <> '') and (Outcome.Error = TAtlasCiFetchError.NotFound) then
  begin
    Result := Boards.LoadBoard(TAtlasBoardRequest.Create(Target, Transport, '', '', TAtlasTrackerBoard.cTimeoutMs),
      Outcome.Snapshot, Outcome.Error);
  end;
end;

procedure TAtlasSprintJob.LoadWorkDays;
var
  mDays: TArray<Integer>;
begin
  if (WorkDays <> nil) and WorkDays.WorkDays(Target, Transport, TAtlasTrackerBoard.cTimeoutMs, mDays) then
  begin
    Outcome.Calendar := TAtlasSprintCalendar.Create(mDays);
    Outcome.CalendarKnown := True;
  end;
end;

procedure TAtlasSprintJob.LoadPrevious;
var
  mSprint: TAtlasBoardSprint;
  mSummary: TAtlasSprintSummary;
  mOld: TAtlasBoardSnapshot;
  mOldError: TAtlasCiFetchError;
  mLeft: Int64;
begin
  for mSprint in TAtlasTrackerSprint.PreviousSprints(Outcome.Snapshot.Sprints, Outcome.Snapshot.Sprint,
    TAtlasTrackerSprint.cVelocitySprints) do
  begin
    // Abgeschlossene Sprints ändern sich nicht: einmal fragen, dann aus dem Zwischenspeicher.
    mLeft := TAtlasTrackerSprint.cTimeoutMs - Watch.ElapsedMilliseconds;
    if TAtlasSprintLoad.CachedSummary(Folder, Target, Outcome.Snapshot.Board.Id, mSprint.Id, mSummary) then
    begin
      Outcome.Previous := Outcome.Previous + [mSummary];
    end
    else if mLeft < TAtlasSprintLoad.cMinLeftMs then
    begin
      Break;
    end
    else if Boards.LoadBoard(TAtlasBoardRequest.Create(Target, Transport, Outcome.Snapshot.Board.Id, mSprint.Id,
      Integer(mLeft)), mOld, mOldError) then
    begin
      mSummary := TAtlasTrackerSprint.Summarize(mOld, Outcome.Calendar, TAtlasSprintLoad.NowUtc);
      TAtlasSprintLoad.SaveSummary(Folder, Target, Outcome.Snapshot.Board.Id, mSummary);
      Outcome.Previous := Outcome.Previous + [mSummary];
    end;
  end;
end;

{ TAtlasSprintState }

procedure TAtlasSprintState.Restore(const AFolder: string; const ATarget: TAtlasTrackerTarget; const ACacheName,
  AWorkDaysName: string);
var
  mSprint: TAtlasBoardSprint;
  mSummary: TAtlasSprintSummary;
  mFile, mText: string;
begin
  Stale := False;
  Error := TAtlasCiFetchError.None;
  Previous := nil;
  WithPrevious := False;
  Calendar := TAtlasSprintCalendar.WorkWeek;
  HasSnapshot := TAtlasTrackerBoard.Load(AFolder, ATarget, ACacheName, Snapshot);
  if not HasSnapshot then
  begin
    Snapshot := TAtlasBoardSnapshot.Empty;
  end;
  mFile := TAtlasTrackerBoard.CacheFile(AFolder, ATarget, AWorkDaysName);
  if (mFile <> '') and TAtlasTrackerBoard.ReadText(mFile, mText) then
  begin
    Calendar := TAtlasSprintCalendar.FromText(mText);
  end;
  if not HasSnapshot then
  begin
    Exit;
  end;
  for mSprint in TAtlasTrackerSprint.PreviousSprints(Snapshot.Sprints, Snapshot.Sprint,
    TAtlasTrackerSprint.cVelocitySprints) do
  begin
    if TAtlasSprintLoad.CachedSummary(AFolder, ATarget, Snapshot.Board.Id, mSprint.Id, mSummary) then
    begin
      Previous := Previous + [mSummary];
    end;
  end;
end;

procedure TAtlasSprintState.Fail(AError: TAtlasCiFetchError);
begin
  Stale := True;
  Error := AError;
end;

procedure TAtlasSprintState.Take(const AResult: TAtlasSprintResult; ANow: TDateTime);
begin
  Snapshot := AResult.Snapshot;
  Snapshot.Fetched := ANow;
  HasSnapshot := True;
  Stale := False;
  Error := TAtlasCiFetchError.None;
  Previous := AResult.Previous;
  WithPrevious := AResult.WithPrevious;
  if AResult.CalendarKnown then
  begin
    Calendar := AResult.Calendar;
  end;
end;

{ TAtlasSprintLoad }

class function TAtlasSprintLoad.CachedSummary(const AFolder: string; const ATarget: TAtlasTrackerTarget;
  const ABoardId, ASprintId: string; out ASummary: TAtlasSprintSummary): Boolean;
var
  mFile, mText: string;
begin
  ASummary := Default(TAtlasSprintSummary);
  mFile := TAtlasTrackerBoard.CacheFile(AFolder, ATarget, TAtlasTrackerSprint.SummaryName(ABoardId, ASprintId));
  Result := (mFile <> '') and TAtlasTrackerBoard.ReadText(mFile, mText) and
    TAtlasTrackerSprint.SummaryFromJson(mText, ASummary);
end;

class procedure TAtlasSprintLoad.SaveSummary(const AFolder: string; const ATarget: TAtlasTrackerTarget;
  const ABoardId: string; const ASummary: TAtlasSprintSummary);
var
  mFile: string;
begin
  mFile := TAtlasTrackerBoard.CacheFile(AFolder, ATarget, TAtlasTrackerSprint.SummaryName(ABoardId, ASummary.Id));
  if mFile <> '' then
  begin
    TAtlasTrackerBoard.WriteText(mFile, TAtlasTrackerSprint.SummaryToJson(ASummary));
  end;
end;

class function TAtlasSprintLoad.Due(ALoadedTick, ANowMs: UInt64; ADueMinutes: Integer; ACompare,
  AWithPrevious: Boolean): Boolean;
begin
  Result := (ALoadedTick = 0) or (ANowMs - ALoadedTick >= UInt64(ADueMinutes) * cMsPerMinute) or
    (ACompare and not AWithPrevious);
end;

class function TAtlasSprintLoad.NowUtc: TDateTime;
begin
  Result := TTimeZone.Local.ToUniversalTime(Now);
end;

end.
