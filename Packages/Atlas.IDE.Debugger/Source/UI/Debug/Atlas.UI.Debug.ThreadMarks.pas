unit Atlas.UI.Debug.ThreadMarks;

// Threads im Quelltext (#852), Texte ohne VCL: Tooltip am Zeichen in der Rinne („3 Threads stehen hier“, je Thread
// „⚑ 1234 „Worker“ · wartet in TEvent.WaitFor · eingefroren“), Links zum Wechseln, Zeile der Auswahlliste und der
// Hinweis in der Statusleiste („2 Threads eingefroren“).

interface

uses
  Atlas.Core.Debug.Threads,
  Atlas.Core.Debug.ThreadMarks;

type
  TAtlasThreadMarkTexts = class
  public
    /// <summary>Überschrift des Tooltips für ACount Threads.</summary>
    class function TipTitle(ACount: Integer): string; static;
    /// <summary>„1234“ bzw. „1234 „Worker““, markiert mit ⚑ davor.</summary>
    class function ThreadLabel(const AStack: TAtlasDebugThreadStack; AFlagged: Boolean): string; static;
    /// <summary>Zeile eines Threads im Tooltip: Kennung, Wartepunkt, eingefroren.</summary>
    class function ThreadLine(const AStack: TAtlasDebugThreadStack; AFlagged, AFrozen: Boolean): string; static;
    /// <summary>Text des Tooltips: je Thread der Marke eine Zeile.</summary>
    class function TipText(const AStacks: TAtlasDebugThreadStacks; const AMark: TAtlasDebugThreadMark;
      const AFlagged, AFrozen: TAtlasDebugThreadSet): string; static;
    /// <summary>Link „Zu 1234 „Worker“ wechseln“.</summary>
    class function SwitchLink(const AStack: TAtlasDebugThreadStack): string; static;
    /// <summary>„1 Thread eingefroren“ bzw. „2 Threads eingefroren“.</summary>
    class function FrozenText(ACount: Integer): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Debug.Deadlocks,
  Atlas.UI.Debug.Strings;

const
  /// <summary>Zeichen markierter Threads (⚑); als Zeichencode und nicht in der Texttabelle, weil FPC es dort
  /// nicht hält.</summary>
  cFlag = #$2691;

{ TAtlasThreadMarkTexts }

class function TAtlasThreadMarkTexts.TipTitle(ACount: Integer): string;
begin
  if ACount = 1 then
  begin
    Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.ThreadMarksTitleOne);
  end
  else
  begin
    Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.ThreadMarksTitle, [ACount]);
  end;
end;

class function TAtlasThreadMarkTexts.ThreadLabel(const AStack: TAtlasDebugThreadStack; AFlagged: Boolean): string;
begin
  Result := IntToStr(AStack.ThreadId);
  if AStack.Name <> '' then
  begin
    Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DebugWaitsThreadName, [Result, AStack.Name]);
  end;
  if AFlagged then
  begin
    Result := cFlag + ' ' + Result;
  end;
end;

class function TAtlasThreadMarkTexts.ThreadLine(const AStack: TAtlasDebugThreadStack;
  AFlagged, AFrozen: Boolean): string;
var
  mWait: TAtlasDebugWait;
begin
  Result := ThreadLabel(AStack, False);
  mWait := TAtlasDebugWaits.Find(AStack);
  if mWait.Blocked then
  begin
    Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.ThreadMarksWaiting,
      [Result, TAtlasDebugWaitTexts.ShortRoutine(mWait.Routine)]);
  end;
  if AFrozen then
  begin
    Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.ThreadMarksFrozen, [Result]);
  end;
  // Das Zeichen zuletzt davor: Format reicht es unter FPC nicht unverändert durch.
  if AFlagged then
  begin
    Result := cFlag + ' ' + Result;
  end;
end;

class function TAtlasThreadMarkTexts.TipText(const AStacks: TAtlasDebugThreadStacks;
  const AMark: TAtlasDebugThreadMark; const AFlagged, AFrozen: TAtlasDebugThreadSet): string;
var
  mLines: TArray<string>;
  mIndex, mThread: Integer;
begin
  SetLength(mLines, Length(AMark.Threads));
  for mIndex := 0 to High(AMark.Threads) do
  begin
    mThread := AMark.Threads[mIndex];
    mLines[mIndex] := ThreadLine(AStacks[mThread], AFlagged.Contains(AStacks[mThread].ThreadId),
      AFrozen.Contains(AStacks[mThread].ThreadId));
  end;
  Result := string.Join(sLineBreak, mLines);
end;

class function TAtlasThreadMarkTexts.SwitchLink(const AStack: TAtlasDebugThreadStack): string;
begin
  Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.ThreadMarksSwitch, [ThreadLabel(AStack, False)]);
end;

class function TAtlasThreadMarkTexts.FrozenText(ACount: Integer): string;
begin
  if ACount = 1 then
  begin
    Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.ThreadMarksFrozenOne);
  end
  else
  begin
    Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.ThreadMarksFrozenCount, [ACount]);
  end;
end;

end.
