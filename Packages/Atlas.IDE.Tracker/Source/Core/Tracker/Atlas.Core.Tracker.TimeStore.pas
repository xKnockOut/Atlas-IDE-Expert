unit Atlas.Core.Tracker.TimeStore;

// Ablage der erfassten Zeit (#1267) ohne VCL und Open Tools API: die Spannen
// der Uhr (TAtlasTimeClock) in time.json (TAtlasTimeFile, mit Sperrdatei).
// - Jede Änderung nimmt die noch nicht geschriebenen Spannen mit. Scheitert
//   das Schreiben (gesperrt, unlesbar), bleiben sie im Speicher und gehen
//   beim nächsten Mal mit; der Aufrufer erfährt nur den ersten Fehlschlag
//   einer Reihe (OnFailed).
// - Die Summe des aktuellen Issues ist der Stand der Datei plus die Zeit, die
//   noch nicht dort steht.
// Nur in einem Thread benutzen.

interface

uses
  System.SysUtils,
  Atlas.Core.Tracker.TimeLog,
  Atlas.Core.Tracker.TimeClock;

type
  TAtlasTimeStore = class
  private
    FPath: string;
    FClock: TAtlasTimeClock;
    FFailed: TProc;
    // Summe des aktuellen Issues in der Datei und Spannen, die noch nicht geschrieben sind.
    FSaved: Int64;
    FPending: TArray<TAtlasTimeSpan>;
    FFileFailed: Boolean;
  public
    /// <summary>APath: time.json; AClock: Uhr, deren Spannen hier landen (gehört dem Aufrufer); AFailed: erster
    /// Fehlschlag beim Schreiben nach einem Erfolg.</summary>
    constructor Create(const APath: string; AClock: TAtlasTimeClock; const AFailed: TProc);
    /// <summary>Spannen der Uhr schreiben und AChange (nil = nichts weiter) anwenden; False, wenn die Datei nicht
    /// geschrieben wurde (die Spannen bleiben dann im Speicher).</summary>
    function Change(const AChange: TAtlasTimeLogChange): Boolean;
    /// <summary>Nur die Spannen der Uhr schreiben.</summary>
    procedure Flush;
    /// <summary>Summe von AIssue in der Datei; 0, wenn sie nicht lesbar ist.</summary>
    function SavedTotal(const AIssue: TAtlasTimeIssue): Int64;
    /// <summary>Summe des Issues der Uhr: Datei plus noch nicht Geschriebenes.</summary>
    function CurrentTotal: Int64;
    /// <summary>Die Uhr zählt jetzt auf AIssue: dessen Summe aus der Datei übernehmen (keins: nichts).</summary>
    procedure Select(const AIssue: TAtlasTimeIssue);
    /// <summary>Gebucht oder verworfen: genau ASeconds von AIssue abziehen.</summary>
    procedure Subtract(const AIssue: TAtlasTimeIssue; ASeconds: Int64);
    /// <summary>Zeit von AIssue von Hand auf ASeconds setzen (heute ist AToday).</summary>
    procedure SetTotal(const AIssue: TAtlasTimeIssue; ASeconds: Int64; AToday: TDateTime);
    /// <summary>Stand der Datei; False, wenn sie nicht lesbar ist.</summary>
    function Read(out ALog: TAtlasTimeLog): Boolean;
    /// <summary>Keine Meldung mehr über OnFailed (beim Abmelden).</summary>
    procedure Detach;
    property Path: string read FPath;
  end;

implementation

uses
  Atlas.Core.Tracker.TimePlan;

{ TAtlasTimeStore }

constructor TAtlasTimeStore.Create(const APath: string; AClock: TAtlasTimeClock; const AFailed: TProc);
begin
  inherited Create;
  FPath := APath;
  FClock := AClock;
  FFailed := AFailed;
end;

function TAtlasTimeStore.Change(const AChange: TAtlasTimeLogChange): Boolean;
var
  mLog: TAtlasTimeLog;
  mSpans: TArray<TAtlasTimeSpan>;
  mIssue: TAtlasTimeIssue;
begin
  // Noch nicht geschriebene Spannen gehen mit jeder Änderung mit.
  mSpans := FPending + FClock.Take;
  mIssue := FClock.Issue;
  Result := TAtlasTimeFile.Update(FPath,
    procedure(var ALog: TAtlasTimeLog)
    var
      mSpan: TAtlasTimeSpan;
    begin
      for mSpan in mSpans do
      begin
        ALog.Add(mSpan);
      end;
      if Assigned(AChange) then
      begin
        AChange(ALog);
      end;
    end, mLog);
  if not Result then
  begin
    FPending := mSpans;
    if not FFileFailed then
    begin
      FFileFailed := True;
      if Assigned(FFailed) then
      begin
        FFailed();
      end;
    end;
    Exit;
  end;
  FPending := nil;
  FFileFailed := False;
  FSaved := mLog.Total(mIssue);
end;

procedure TAtlasTimeStore.Flush;
begin
  Change(nil);
end;

function TAtlasTimeStore.SavedTotal(const AIssue: TAtlasTimeIssue): Int64;
var
  mLog: TAtlasTimeLog;
begin
  Result := 0;
  if TAtlasTimeFile.Read(FPath, mLog) then
  begin
    Result := mLog.Total(AIssue);
  end;
end;

function TAtlasTimeStore.CurrentTotal: Int64;
begin
  Result := TAtlasTimePlan.Total(FSaved, FClock.Unsaved, FPending, FClock.Issue);
end;

procedure TAtlasTimeStore.Select(const AIssue: TAtlasTimeIssue);
begin
  if not AIssue.IsEmpty then
  begin
    FSaved := SavedTotal(AIssue);
  end;
end;

procedure TAtlasTimeStore.Subtract(const AIssue: TAtlasTimeIssue; ASeconds: Int64);
begin
  Change(
    procedure(var ALog: TAtlasTimeLog)
    begin
      ALog.Subtract(AIssue, ASeconds);
    end);
end;

procedure TAtlasTimeStore.SetTotal(const AIssue: TAtlasTimeIssue; ASeconds: Int64; AToday: TDateTime);
begin
  Change(
    procedure(var ALog: TAtlasTimeLog)
    begin
      ALog.SetTotal(AIssue, ASeconds, AToday);
    end);
end;

function TAtlasTimeStore.Read(out ALog: TAtlasTimeLog): Boolean;
begin
  Result := TAtlasTimeFile.Read(FPath, ALog);
end;

procedure TAtlasTimeStore.Detach;
begin
  FFailed := nil;
end;

end.
