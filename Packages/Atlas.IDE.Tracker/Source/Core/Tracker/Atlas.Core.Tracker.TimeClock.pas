unit Atlas.Core.Tracker.TimeClock;

// Uhr für die Zeit des aktuellen Issues (#1267), ohne VCL und Open Tools API.
// - Activity meldet aktive Arbeit (Eingabe in der IDE, Debugger-Lauf) zum
//   Zeitpunkt AAt. Zwischen zwei Meldungen mit höchstens IdleMinutes Abstand
//   läuft die Uhr; ein längerer Abstand ist Leerlauf: Die Spanne endet bei der
//   letzten Meldung, der Leerlauf zählt nicht.
// - Tick schließt die offene Spanne, sobald der Leerlauf überschritten ist;
//   Pause schließt sie und hält die Uhr an, bis Resume.
// - Take gibt die Spannen für die Datei (TAtlasTimeLog.Add) ab, die offene
//   bis zur letzten Meldung; die Uhr läuft danach weiter.
// - SetIssue wechselt das Issue (die offene Spanne gehört dem alten).
// Die Zeitquelle kommt von außen (Tests mit fester Uhr). Nur in einem Thread
// benutzen.

interface

uses
  System.SysUtils,
  Atlas.Core.Tracker.TimeLog;

type
  /// <summary>Aktuelle lokale Zeit.</summary>
  TAtlasTimeNow = reference to function: TDateTime;

  TAtlasTimeClock = class
  public const
    DefaultIdleMinutes = 10;
    MinIdleMinutes = 1;
    MaxIdleMinutes = 120;
  private
    FNow: TAtlasTimeNow;
    FIdle: TDateTime;
    FIssue: TAtlasTimeIssue;
    FPaused: Boolean;
    FOpen: Boolean;
    FStart: TDateTime;
    FLast: TDateTime;
    FDone: TArray<TAtlasTimeSpan>;
    procedure Close;
  public
    constructor Create(const ANow: TAtlasTimeNow; AIdleMinutes: Integer);
    /// <summary>issues.idleMinutes (auf MinIdleMinutes..MaxIdleMinutes begrenzt).</summary>
    procedure SetIdleMinutes(AMinutes: Integer);
    /// <summary>Anderes Issue (TAtlasTimeIssue.None = keins); die offene Spanne gehört noch dem alten.</summary>
    procedure SetIssue(const AIssue: TAtlasTimeIssue);
    /// <summary>Aktive Arbeit jetzt.</summary>
    procedure Activity; overload;
    /// <summary>Aktive Arbeit zum Zeitpunkt AAt (z. B. letzte Eingabe); Ältere als die letzte Meldung zählen
    /// nicht.</summary>
    procedure Activity(AAt: TDateTime); overload;
    /// <summary>Offene Spanne nach Leerlauf schließen.</summary>
    procedure Tick;
    procedure Pause;
    procedure Resume;
    /// <summary>Gezählte Spannen seit dem letzten Take; die offene bis zur letzten Meldung.</summary>
    function Take: TArray<TAtlasTimeSpan>;
    /// <summary>Sekunden, die noch nicht abgegeben sind.</summary>
    function Unsaved: Int64;
    /// <summary>Noch nicht abgegebene Zeit verwerfen (Zurücksetzen); die Uhr läuft weiter.</summary>
    procedure Discard;
    /// <summary>Die Uhr zählt gerade: Issue, nicht angehalten, letzte Meldung innerhalb des Leerlaufs.</summary>
    function Running: Boolean;
    property Issue: TAtlasTimeIssue read FIssue;
    property Paused: Boolean read FPaused;
  end;

implementation

uses
  System.Math;

constructor TAtlasTimeClock.Create(const ANow: TAtlasTimeNow; AIdleMinutes: Integer);
begin
  inherited Create;
  FNow := ANow;
  FIssue := TAtlasTimeIssue.None;
  SetIdleMinutes(AIdleMinutes);
end;

procedure TAtlasTimeClock.SetIdleMinutes(AMinutes: Integer);
begin
  FIdle := EnsureRange(AMinutes, MinIdleMinutes, MaxIdleMinutes) / MinsPerDay;
end;

procedure TAtlasTimeClock.Close;
begin
  if FOpen and (FLast > FStart) then
    FDone := FDone + [TAtlasTimeSpan.Create(FIssue, FStart, FLast)];
  FOpen := False;
end;

procedure TAtlasTimeClock.SetIssue(const AIssue: TAtlasTimeIssue);
begin
  if FIssue.Same(AIssue) then
    Exit;
  Close;
  FIssue := AIssue;
end;

procedure TAtlasTimeClock.Activity;
begin
  Activity(FNow());
end;

procedure TAtlasTimeClock.Activity(AAt: TDateTime);
begin
  if FPaused or FIssue.IsEmpty then
    Exit;
  if not FOpen then
  begin
    FOpen := True;
    FStart := AAt;
    FLast := AAt;
    Exit;
  end;
  if AAt <= FLast then
    Exit;
  if AAt - FLast > FIdle then
  begin
    // Leerlauf: Die Spanne endet bei der letzten Meldung, die Pause zählt nicht.
    Close;
    FOpen := True;
    FStart := AAt;
  end;
  FLast := AAt;
end;

procedure TAtlasTimeClock.Tick;
begin
  if FOpen and (FNow() - FLast > FIdle) then
    Close;
end;

procedure TAtlasTimeClock.Pause;
begin
  Close;
  FPaused := True;
end;

procedure TAtlasTimeClock.Resume;
begin
  FPaused := False;
end;

function TAtlasTimeClock.Take: TArray<TAtlasTimeSpan>;
begin
  Result := FDone;
  FDone := nil;
  if FOpen and (FLast > FStart) then
  begin
    Result := Result + [TAtlasTimeSpan.Create(FIssue, FStart, FLast)];
    FStart := FLast;
  end;
end;

function TAtlasTimeClock.Unsaved: Int64;
var
  mSpan: TAtlasTimeSpan;
begin
  Result := 0;
  for mSpan in FDone do
    Inc(Result, mSpan.Seconds);
  if FOpen then
    Inc(Result, TAtlasTimeSpan.Create(FIssue, FStart, FLast).Seconds);
end;

procedure TAtlasTimeClock.Discard;
begin
  FDone := nil;
  if FOpen then
    FStart := FLast;
end;

function TAtlasTimeClock.Running: Boolean;
begin
  Result := FOpen and not FPaused and not FIssue.IsEmpty and (FNow() - FLast <= FIdle);
end;

end.
