unit Atlas.UI.Debug.Deadlocks;

// „Was wartet worauf?“ (#587), Texte für das Ergebnisfenster: Titel, je Thread „Thread 1234 „Worker“: wartet in
// TThread.Synchronize, bei TWorker.Execute (Unit2.pas:30)“ und je Muster ein Satz mit den beteiligten Threads.
// Sprungziel eines Musters ist der erste beteiligte Thread (bei Synchronize-Mustern der Hauptthread).

interface

uses
  Atlas.Core.Debug.Deadlocks;

type
  TAtlasDebugWaitTexts = class
  public
    class function Title(const AReport: TAtlasDebugWaitReport): string; static;
    /// <summary>„1234“, „1234 „Worker““, beim Hauptthread mit „(Hauptthread)“.</summary>
    class function ThreadLabel(const AReport: TAtlasDebugWaitReport; AIndex: Integer): string; static;
    /// <summary>„läuft“, „wartet auf Nachrichten“, „wartet in TMonitor.Enter“, „Aufrufstapel nicht lesbar“.</summary>
    class function WaitText(const AReport: TAtlasDebugWaitReport; AIndex: Integer): string; static;
    /// <summary>Zeile eines Threads mit Wartepunkt und Sprungziel.</summary>
    class function ThreadItem(const AReport: TAtlasDebugWaitReport; AIndex: Integer): string; static;
    /// <summary>Satz zum Muster APattern.</summary>
    class function PatternText(const AReport: TAtlasDebugWaitReport;
      const APattern: TAtlasDebugDeadlock): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Debug.CallStack,
  Atlas.Core.Debug.Threads,
  Atlas.UI.Debug.Strings;

/// <summary>Routine ohne Unit („System.Classes.TThread.WaitFor“ → „TThread.WaitFor“, „ntdll.Sleep“ → „Sleep“).
/// </summary>
function ShortRoutine(const ARoutine: string): string;
var
  mParts: TArray<string>;
  mCount: Integer;
begin
  mParts := ARoutine.Split(['.']);
  mCount := Length(mParts);
  if (mCount >= 2) and (mParts[mCount - 2] <> '') and CharInSet(mParts[mCount - 2][1], ['T', 'I']) then
  begin
    Result := mParts[mCount - 2] + '.' + mParts[mCount - 1];
  end
  else if mCount > 0 then
  begin
    Result := mParts[mCount - 1];
  end
  else
  begin
    Result := ARoutine;
  end;
end;

/// <summary>Threads der Liste AThreads durch Komma getrennt; ASkipMain lässt den Hauptthread weg.</summary>
function ThreadList(const AReport: TAtlasDebugWaitReport; const AThreads: TArray<Integer>;
  ASkipMain: Boolean): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex in AThreads do
  begin
    if ASkipMain and (mIndex = AReport.Main) then
    begin
      Continue;
    end;
    if Result <> '' then
    begin
      Result := Result + ', ';
    end;
    Result := Result + TAtlasDebugWaitTexts.ThreadLabel(AReport, mIndex);
  end;
end;

{ TAtlasDebugWaitTexts }

class function TAtlasDebugWaitTexts.Title(const AReport: TAtlasDebugWaitReport): string;
begin
  Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DebugWaitsTitle, [Length(AReport.Stacks)]);
end;

class function TAtlasDebugWaitTexts.ThreadLabel(const AReport: TAtlasDebugWaitReport; AIndex: Integer): string;
var
  mStack: TAtlasDebugThreadStack;
begin
  mStack := AReport.Stacks[AIndex];
  if mStack.Name <> '' then
  begin
    Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DebugWaitsThreadName, [IntToStr(mStack.ThreadId), mStack.Name]);
  end
  else
  begin
    Result := IntToStr(mStack.ThreadId);
  end;
  if AIndex = AReport.Main then
  begin
    Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DebugWaitsMainThread, [Result]);
  end;
end;

class function TAtlasDebugWaitTexts.WaitText(const AReport: TAtlasDebugWaitReport; AIndex: Integer): string;
begin
  if not AReport.Stacks[AIndex].Readable then
  begin
    Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugWaitsUnreadable);
  end
  else if AReport.Waits[AIndex].Kind = TAtlasDebugWaitKind.None then
  begin
    Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugWaitsRunning);
  end
  else if AReport.Waits[AIndex].Kind = TAtlasDebugWaitKind.Idle then
  begin
    Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugWaitsIdle);
  end
  else
  begin
    Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DebugWaitsIn, [ShortRoutine(AReport.Waits[AIndex].Routine)]);
  end;
end;

class function TAtlasDebugWaitTexts.ThreadItem(const AReport: TAtlasDebugWaitReport; AIndex: Integer): string;
var
  mJump: Integer;
  mFrame: TAtlasDebugFrame;
  mPlace: string;
begin
  mJump := AReport.Stacks[AIndex].JumpFrame;
  if mJump < 0 then
  begin
    Exit(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DebugWaitsThreadItemNoPlace,
      [ThreadLabel(AReport, AIndex), WaitText(AReport, AIndex)]));
  end;
  mFrame := AReport.Stacks[AIndex].Frames[mJump];
  mPlace := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DebugWaitsPlace,
    [ShortRoutine(mFrame.Routine), ExtractFileName(mFrame.FileName), mFrame.Line]);
  Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DebugWaitsThreadItem,
    [ThreadLabel(AReport, AIndex), WaitText(AReport, AIndex), mPlace]);
end;

class function TAtlasDebugWaitTexts.PatternText(const AReport: TAtlasDebugWaitReport;
  const APattern: TAtlasDebugDeadlock): string;
var
  mWhere: string;
begin
  case APattern.Kind of
    TAtlasDebugDeadlockKind.MainWaitsForSynchronize:
      begin
        mWhere := '';
        if AReport.MainInThreadDestructor then
        begin
          mWhere := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugWaitsInDestructor);
        end;
        Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DebugWaitsMainWaitsForSync,
          [mWhere, ThreadList(AReport, APattern.Threads, True)]);
      end;
    TAtlasDebugDeadlockKind.SynchronizeBlocked:
      Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DebugWaitsSyncBlocked,
        [ThreadList(AReport, APattern.Threads, True), ShortRoutine(AReport.Waits[AReport.Main].Routine)]);
    TAtlasDebugDeadlockKind.SameLock:
      Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DebugWaitsSameLock,
        [Length(APattern.Threads), ShortRoutine(APattern.Place),
          ThreadList(AReport, APattern.Threads, False)]);
  else
    Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DebugWaitsAllBlocked, [Length(APattern.Threads)]);
  end;
end;

end.
