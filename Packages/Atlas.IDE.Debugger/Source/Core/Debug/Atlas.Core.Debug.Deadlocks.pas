unit Atlas.Core.Debug.Deadlocks;

// „Was wartet worauf?“ (#587), ohne VCL und Open Tools API: Wartepunkte aller Threads und bekannte Muster.
//   - MainWaitsForSynchronize: Der Hauptthread wartet in TThread.WaitFor (etwa im Destruktor eines Threads), ein
//     anderer Thread wartet in TThread.Synchronize auf den Hauptthread. Keiner kommt weiter; die statische Seite ist
//     die Regel synchronize-in-destructor.
//   - SynchronizeBlocked: Ein Thread wartet in Synchronize, der Hauptthread hängt an einer Sperre bzw. einem Ereignis
//     und arbeitet die Warteschlange nicht ab.
//   - SameLock: Mehrere Threads warten an derselben Stelle auf TMonitor.Enter bzw. eine Critical Section. Wer die
//     Sperre hält, liest Atlas nicht (siehe Atlas.Core.Debug.Threads).
//   - AllBlocked: Jeder Thread mit lesbarem Stapel wartet; keiner läuft (Sleep und die Nachrichtenschleife zählen
//     nicht als Warten).

interface

uses
  Atlas.Core.Debug.Threads;

type
  {$SCOPEDENUMS ON}
  TAtlasDebugDeadlockKind = (MainWaitsForSynchronize, SynchronizeBlocked, SameLock, AllBlocked);
  {$SCOPEDENUMS OFF}

  /// <summary>Gefundenes Muster: Art und die beteiligten Threads (Indizes in die Stapelliste).</summary>
  TAtlasDebugDeadlock = record
    Kind: TAtlasDebugDeadlockKind;
    Threads: TArray<Integer>;
    /// <summary>Routine des eigenen Rahmens, an dem die Threads warten (SameLock); sonst ''.</summary>
    Place: string;
  end;

  TAtlasDebugDeadlocks = TArray<TAtlasDebugDeadlock>;

  /// <summary>Wartepunkte und Muster eines Halts.</summary>
  TAtlasDebugWaitReport = record
    Stacks: TAtlasDebugThreadStacks;
    Waits: TArray<TAtlasDebugWait>;
    Main: Integer;
    Patterns: TAtlasDebugDeadlocks;
    class function Analyze(const AStacks: TAtlasDebugThreadStacks): TAtlasDebugWaitReport; static;
    /// <summary>Steht der Hauptthread im Destruktor eines Threads (TThread.Destroy im Stapel)?</summary>
    function MainInThreadDestructor: Boolean;
  end;

implementation

uses
  System.SysUtils;

const
  cMinSameLock = 2;

function Pattern(AKind: TAtlasDebugDeadlockKind; const AThreads: TArray<Integer>;
  const APlace: string): TAtlasDebugDeadlock;
begin
  Result.Kind := AKind;
  Result.Threads := AThreads;
  Result.Place := APlace;
end;

/// <summary>Indizes der Threads außer dem Hauptthread, die in AKind warten.</summary>
function WaitingIn(const AReport: TAtlasDebugWaitReport; AKind: TAtlasDebugWaitKind): TArray<Integer>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to High(AReport.Waits) do
  begin
    if (mIndex <> AReport.Main) and (AReport.Waits[mIndex].Kind = AKind) then
    begin
      Result := Result + [mIndex];
    end;
  end;
end;

procedure AddSynchronize(var AReport: TAtlasDebugWaitReport);
var
  mSync: TArray<Integer>;
  mMain: TAtlasDebugWaitKind;
begin
  if AReport.Main < 0 then
  begin
    Exit;
  end;
  mSync := WaitingIn(AReport, TAtlasDebugWaitKind.Synchronize);
  if mSync = nil then
  begin
    Exit;
  end;
  mMain := AReport.Waits[AReport.Main].Kind;
  if mMain = TAtlasDebugWaitKind.ThreadWaitFor then
  begin
    AReport.Patterns := AReport.Patterns + [Pattern(TAtlasDebugDeadlockKind.MainWaitsForSynchronize,
      TArray<Integer>.Create(AReport.Main) + mSync, '')];
  end
  else if AReport.Waits[AReport.Main].Blocked and (mMain <> TAtlasDebugWaitKind.Sleep) then
  begin
    AReport.Patterns := AReport.Patterns + [Pattern(TAtlasDebugDeadlockKind.SynchronizeBlocked,
      TArray<Integer>.Create(AReport.Main) + mSync, '')];
  end;
end;

/// <summary>Ort, an dem AIndex auf eine Sperre wartet: Routine des ersten eigenen Rahmens; '' ohne Sperre.</summary>
function LockPlace(const AReport: TAtlasDebugWaitReport; AIndex: Integer): string;
var
  mOwn: Integer;
begin
  Result := '';
  if (AReport.Waits[AIndex].Kind <> TAtlasDebugWaitKind.MonitorEnter) and
    (AReport.Waits[AIndex].Kind <> TAtlasDebugWaitKind.CriticalSection) then
  begin
    Exit;
  end;
  mOwn := AReport.Stacks[AIndex].FirstOwn;
  if mOwn >= 0 then
  begin
    Result := AReport.Stacks[AIndex].Frames[mOwn].Routine;
  end;
end;

procedure AddSameLock(var AReport: TAtlasDebugWaitReport);
var
  mIndex, mOther: Integer;
  mPlace: string;
  mDone: TArray<Boolean>;
  mThreads: TArray<Integer>;
begin
  SetLength(mDone, Length(AReport.Waits));
  for mIndex := 0 to High(AReport.Waits) do
  begin
    mPlace := LockPlace(AReport, mIndex);
    if mDone[mIndex] or (mPlace = '') then
    begin
      Continue;
    end;
    mThreads := [mIndex];
    for mOther := mIndex + 1 to High(AReport.Waits) do
    begin
      if SameText(LockPlace(AReport, mOther), mPlace) then
      begin
        mThreads := mThreads + [mOther];
        mDone[mOther] := True;
      end;
    end;
    if Length(mThreads) >= cMinSameLock then
    begin
      AReport.Patterns := AReport.Patterns + [Pattern(TAtlasDebugDeadlockKind.SameLock, mThreads, mPlace)];
    end;
  end;
end;

procedure AddAllBlocked(var AReport: TAtlasDebugWaitReport);
var
  mIndex: Integer;
  mThreads: TArray<Integer>;
begin
  mThreads := nil;
  for mIndex := 0 to High(AReport.Waits) do
  begin
    if not AReport.Stacks[mIndex].Readable then
    begin
      Continue;
    end;
    if (not AReport.Waits[mIndex].Blocked) or (AReport.Waits[mIndex].Kind = TAtlasDebugWaitKind.Sleep) then
    begin
      Exit;
    end;
    mThreads := mThreads + [mIndex];
  end;
  if Length(mThreads) >= cMinSameLock then
  begin
    AReport.Patterns := AReport.Patterns + [Pattern(TAtlasDebugDeadlockKind.AllBlocked, mThreads, '')];
  end;
end;

{ TAtlasDebugWaitReport }

class function TAtlasDebugWaitReport.Analyze(const AStacks: TAtlasDebugThreadStacks): TAtlasDebugWaitReport;
var
  mIndex: Integer;
begin
  Result := Default(TAtlasDebugWaitReport);
  Result.Stacks := AStacks;
  SetLength(Result.Waits, Length(AStacks));
  for mIndex := 0 to High(AStacks) do
  begin
    Result.Waits[mIndex] := TAtlasDebugWaits.Find(AStacks[mIndex]);
  end;
  Result.Main := TAtlasDebugWaits.MainIndex(AStacks);
  AddSynchronize(Result);
  AddSameLock(Result);
  AddAllBlocked(Result);
end;

function TAtlasDebugWaitReport.MainInThreadDestructor: Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  if Main < 0 then
  begin
    Exit;
  end;
  for mIndex := 0 to High(Stacks[Main].Frames) do
  begin
    if TAtlasDebugWaits.Matches(Stacks[Main].Frames[mIndex].Routine, 'TThread.Destroy') then
    begin
      Exit(True);
    end;
  end;
end;

end.
