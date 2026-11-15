unit Atlas.Core.Debug.LaunchProcesses;

// Gestartete Programme eines Startverbunds (#867), ohne IDE prüfbar (#1967): Zustand je Programm, Text des
// Statusfelds, Prozess zum Halt, nächster Prozess für den Klick aufs Statusfeld, Wartebedingung mit eigenem Prüfer
// und die Frist, bis die Leiste nach dem Lauf verschwindet. Prozesse und Debugger fragt
// Atlas.IDE.Debug.LaunchGroups.

interface

uses
  Atlas.Core.Debug.LaunchGroups;

{$SCOPEDENUMS ON}

type
  TAtlasLaunchProcessState = (Running, Paused, Ended);

  /// <summary>Gestartetes Programm: Beschriftung, Programmdatei, Prozess (0, solange unbekannt), mit Debugger.
  /// </summary>
  TAtlasLaunchStarted = record
    Caption: string;
    Exe: string;
    Pid: Cardinal;
    Debug: Boolean;
  end;

  TAtlasLaunchStartedList = TArray<TAtlasLaunchStarted>;

  TAtlasLaunchStateTexts = record
    Running: string;
    Paused: string;
    Ended: string;
  end;

  TAtlasLaunchProcesses = class
  public
    /// <summary>Zustand eines Programms: lebt es (AAlive) und steht es im Debugger (APaused)?</summary>
    class function StateOf(AAlive, APaused: Boolean): TAtlasLaunchProcessState; static;
    /// <summary>Text des Statusfelds: je Programm „Beschriftung Zustand“, getrennt mit „ · “; AStates gehört
    /// Eintrag für Eintrag zu AStarted.</summary>
    class function StatusText(const AStarted: TAtlasLaunchStartedList;
      const AStates: TArray<TAtlasLaunchProcessState>; const ATexts: TAtlasLaunchStateTexts): string; static;
    /// <summary>Läuft noch ein Programm (nicht beendet)?</summary>
    class function AnyRunning(const AStates: TArray<TAtlasLaunchProcessState>): Boolean; static;
    /// <summary>Programm mit Debugger zum Prozess APid; False ohne.</summary>
    class function FindDebugged(const AStarted: TAtlasLaunchStartedList; APid: Cardinal;
      out AFound: TAtlasLaunchStarted): Boolean; static;
    /// <summary>Index des nächsten Prozesses nach ACurrent in APids (0 = kein aktueller: der erste); -1 ohne.
    /// </summary>
    class function NextIndex(const APids: TArray<Cardinal>; ACurrent: Cardinal): Integer; static;
    /// <summary>Braucht die Wartebedingung von AItem einen Prüfer (Port, Fenster)? APort ist der Port, sonst 0.
    /// </summary>
    class function NeedsProbe(const AItem: TAtlasLaunchItem; out APort: Integer): Boolean; static;
    /// <summary>Ist der Lauf seit ADoneAt (0 = gerade fertig: setzt ANowMs) mindestens ADelayMs fertig?</summary>
    class function DoneLongEnough(var ADoneAt: UInt64; ANowMs, ADelayMs: UInt64): Boolean; static;
  end;

implementation

uses
  System.SysUtils;

{ TAtlasLaunchProcesses }

class function TAtlasLaunchProcesses.StateOf(AAlive, APaused: Boolean): TAtlasLaunchProcessState;
begin
  if not AAlive then
  begin
    Result := TAtlasLaunchProcessState.Ended;
  end
  else if APaused then
  begin
    Result := TAtlasLaunchProcessState.Paused;
  end
  else
  begin
    Result := TAtlasLaunchProcessState.Running;
  end;
end;

class function TAtlasLaunchProcesses.StatusText(const AStarted: TAtlasLaunchStartedList;
  const AStates: TArray<TAtlasLaunchProcessState>; const ATexts: TAtlasLaunchStateTexts): string;
var
  mParts: TArray<string>;
  mIndex: Integer;
  mState: string;
begin
  SetLength(mParts, Length(AStarted));
  for mIndex := 0 to High(AStarted) do
  begin
    case AStates[mIndex] of
      TAtlasLaunchProcessState.Running:
        mState := ATexts.Running;
      TAtlasLaunchProcessState.Paused:
        mState := ATexts.Paused;
    else
      mState := ATexts.Ended;
    end;
    mParts[mIndex] := AStarted[mIndex].Caption + ' ' + mState;
  end;
  Result := string.Join(' · ', mParts);
end;

class function TAtlasLaunchProcesses.AnyRunning(const AStates: TArray<TAtlasLaunchProcessState>): Boolean;
var
  mState: TAtlasLaunchProcessState;
begin
  Result := False;
  for mState in AStates do
  begin
    if mState <> TAtlasLaunchProcessState.Ended then
    begin
      Exit(True);
    end;
  end;
end;

class function TAtlasLaunchProcesses.FindDebugged(const AStarted: TAtlasLaunchStartedList; APid: Cardinal;
  out AFound: TAtlasLaunchStarted): Boolean;
var
  mStarted: TAtlasLaunchStarted;
begin
  AFound := Default(TAtlasLaunchStarted);
  for mStarted in AStarted do
  begin
    if mStarted.Debug and (mStarted.Pid = APid) then
    begin
      AFound := mStarted;
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TAtlasLaunchProcesses.NextIndex(const APids: TArray<Cardinal>; ACurrent: Cardinal): Integer;
var
  mIndex, mFrom: Integer;
begin
  if Length(APids) = 0 then
  begin
    Exit(-1);
  end;
  mFrom := -1;
  for mIndex := 0 to High(APids) do
  begin
    if (ACurrent <> 0) and (APids[mIndex] = ACurrent) then
    begin
      mFrom := mIndex;
    end;
  end;
  Result := (mFrom + 1) mod Length(APids);
end;

class function TAtlasLaunchProcesses.NeedsProbe(const AItem: TAtlasLaunchItem; out APort: Integer): Boolean;
begin
  APort := 0;
  if AItem.Wait = TAtlasLaunchWaitKind.Port then
  begin
    APort := AItem.Value;
  end;
  Result := AItem.Wait in [TAtlasLaunchWaitKind.Port, TAtlasLaunchWaitKind.Window];
end;

class function TAtlasLaunchProcesses.DoneLongEnough(var ADoneAt: UInt64; ANowMs, ADelayMs: UInt64): Boolean;
begin
  if ADoneAt = 0 then
  begin
    ADoneAt := ANowMs;
  end;
  Result := ANowMs - ADoneAt >= ADelayMs;
end;

end.
