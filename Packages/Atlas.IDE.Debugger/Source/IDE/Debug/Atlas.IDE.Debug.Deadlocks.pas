unit Atlas.IDE.Debug.Deadlocks;

// Befehl „Was wartet worauf?“ (#587): liest bei angehaltenem Programm die Aufrufstapel aller Threads
// (IOTAProcess.Threads, IOTAThread wie im Fenster Aufrufstack), markiert eigenen Code (#578) und zeigt im
// Ergebnisfenster die erkannten Muster und je Thread den Wartepunkt. Doppelklick wechselt zum Thread und springt
// auf seine erste eigene Codezeile.
//   - Der Win64-Debugger (LLDB) liefert Stapel erst nach einer Weile (csWait): Atlas fragt bis zu cRetries mal im
//     Abstand von cIntervalMs nach; was dann noch fehlt, steht als „nicht lesbar“ in der Liste.
//   - Wer eine Sperre hält, liefert die IDE nicht (siehe Atlas.Core.Debug.Threads).
// Teil „DebugDeadlocks“ (debug.deadlocks); Release gibt Zeitgeber und die Liste im Ergebnisfenster frei (Regel 3).
// Nur im Hauptthread verwenden.

interface

uses
  System.SysUtils,
  Vcl.ExtCtrls,
  Atlas.Core.Debug.Deadlocks;

type
  TAtlasIdeDebugDeadlocks = class
  public const
    /// <summary>Besitzer der Liste im Ergebnisfenster.</summary>
    cOwner = 'debug.deadlocks';
    cIntervalMs = 150;
    cRetries = 10;
    /// <summary>Höchstens so viele Threads liest Atlas.</summary>
    cMaxThreads = 512;
  private type
    TTicker = class
    public
      procedure Tick(Sender: TObject);
    end;
  private class var
    FTicker: TTicker;
    FTimer: TTimer;
    FMessage: TProc<string>;
    FRetries: Integer;
    FReport: TAtlasDebugWaitReport;
    FStarted: Boolean;
    /// <summary>Stapel lesen; False, solange der Debugger noch Stapel nachliefert und Versuche übrig sind.</summary>
    class function TryRead: Boolean; static;
    class procedure Show; static;
    class procedure Open(const AItemId: string); static;
  public
    class procedure Start(const AMessage: TProc<string>); static;
    class procedure Release; static;
    class function Started: Boolean; static;
    /// <summary>Befehl Atlas.DebugDeadlocks.</summary>
    class procedure Run; static;
  end;

implementation

uses
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Debug.Threads,
  Atlas.UI.Results.Items,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Foundation.ResultsWindow,
  Atlas.IDE.Debug.Session,
  Atlas.IDE.Debug.Threads,
  Atlas.UI.Debug.Deadlocks,
  Atlas.UI.Debug.Strings;

const
  cPatternPrefix = 'p';

{ TAtlasIdeDebugDeadlocks.TTicker }

procedure TAtlasIdeDebugDeadlocks.TTicker.Tick(Sender: TObject);
begin
  TAtlasGuard.Run(TAtlasFeature.Debugger,
    procedure
    begin
      if TAtlasIdeDebugDeadlocks.TryRead then
      begin
        TAtlasIdeDebugDeadlocks.FTimer.Enabled := False;
        TAtlasIdeDebugDeadlocks.Show;
      end;
    end);
end;

{ TAtlasIdeDebugDeadlocks }

class procedure TAtlasIdeDebugDeadlocks.Start(const AMessage: TProc<string>);
begin
  FMessage := AMessage;
  if FTicker = nil then
  begin
    FTicker := TTicker.Create;
  end;
  if FTimer = nil then
  begin
    FTimer := TTimer.Create(nil);
    FTimer.Enabled := False;
    FTimer.Interval := cIntervalMs;
    FTimer.OnTimer := FTicker.Tick;
  end;
  FStarted := True;
end;

class procedure TAtlasIdeDebugDeadlocks.Release;
begin
  FStarted := False;
  FreeAndNil(FTimer);
  FreeAndNil(FTicker);
  FMessage := nil;
  FReport := Default(TAtlasDebugWaitReport);
  TAtlasIdeResultsWindow.ReleaseItems(cOwner);
end;

class function TAtlasIdeDebugDeadlocks.Started: Boolean;
begin
  Result := FStarted;
end;

class procedure TAtlasIdeDebugDeadlocks.Run;
begin
  if not FStarted then
  begin
    Exit;
  end;
  FTimer.Enabled := False;
  if TAtlasIdeDebugSession.StoppedThread = nil then
  begin
    FMessage(TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugWaitsNotStopped));
    Exit;
  end;
  FRetries := 0;
  if TryRead then
  begin
    Show;
  end
  else
  begin
    FTimer.Enabled := True;
  end;
end;

class function TAtlasIdeDebugDeadlocks.TryRead: Boolean;
var
  mProcess: IOTAProcess;
  mStacks: TAtlasDebugThreadStacks;
  mPending: Boolean;
begin
  Result := True;
  mProcess := TAtlasIdeDebugSession.Process;
  if (mProcess = nil) or (TAtlasIdeDebugSession.StoppedThread = nil) then
  begin
    // Das Programm läuft wieder: nichts mehr zeigen.
    FReport := Default(TAtlasDebugWaitReport);
    Exit;
  end;
  mStacks := nil;
  mPending := TAtlasIdeDebugThreads.ReadRange(mProcess, 0, cMaxThreads, mStacks);
  Inc(FRetries);
  Result := (not mPending) or (FRetries > cRetries);
  FReport := TAtlasDebugWaitReport.Analyze(mStacks);
end;

class procedure TAtlasIdeDebugDeadlocks.Show;
var
  mList: TAtlasResultsItemList;
  mGroup: TAtlasResultsItemGroup;
  mItem: TAtlasResultsItem;
  mIndex: Integer;
begin
  if FReport.Stacks = nil then
  begin
    FMessage(TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugWaitsNotStopped));
    Exit;
  end;
  mList := Default(TAtlasResultsItemList);
  mList.Owner := cOwner;
  mList.Title := TAtlasDebugWaitTexts.Title(FReport);
  mList.OnOpen := Open;
  mGroup := Default(TAtlasResultsItemGroup);
  mGroup.Caption := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugWaitsPatterns);
  for mIndex := 0 to High(FReport.Patterns) do
  begin
    mItem := Default(TAtlasResultsItem);
    mItem.Id := cPatternPrefix + IntToStr(FReport.Patterns[mIndex].Threads[0]) + '.' + IntToStr(mIndex);
    mItem.Caption := TAtlasDebugWaitTexts.PatternText(FReport, FReport.Patterns[mIndex]);
    mGroup.Items := mGroup.Items + [mItem];
  end;
  if FReport.Patterns = nil then
  begin
    mItem := Default(TAtlasResultsItem);
    mItem.Id := cPatternPrefix;
    mItem.Caption := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugWaitsNoPattern);
    mGroup.Items := [mItem];
  end;
  mList.Groups := [mGroup];
  mGroup := Default(TAtlasResultsItemGroup);
  mGroup.Caption := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugWaitsThreads);
  for mIndex := 0 to High(FReport.Stacks) do
  begin
    mItem := Default(TAtlasResultsItem);
    mItem.Id := IntToStr(mIndex);
    mItem.Caption := TAtlasDebugWaitTexts.ThreadItem(FReport, mIndex);
    mGroup.Items := mGroup.Items + [mItem];
  end;
  mList.Groups := mList.Groups + [mGroup];
  TAtlasIdeResultsWindow.ShowItems(mList);
end;

class procedure TAtlasIdeDebugDeadlocks.Open(const AItemId: string);
var
  mId: string;
  mIndex, mJump: Integer;
begin
  // Muster: „p<Thread>.<Muster>“, Thread: „<Thread>“.
  mId := AItemId;
  if mId.StartsWith(cPatternPrefix) then
  begin
    mId := Copy(mId, Length(cPatternPrefix) + 1, Pos('.', mId) - Length(cPatternPrefix) - 1);
  end;
  mIndex := StrToIntDef(mId, -1);
  if (mIndex < 0) or (mIndex > High(FReport.Stacks)) then
  begin
    Exit;
  end;
  TAtlasIdeDebugThreads.Select(FReport.Stacks[mIndex].ThreadId);
  mJump := FReport.Stacks[mIndex].JumpFrame;
  if mJump >= 0 then
  begin
    TAtlasIdeNavigation.MarkLine(FReport.Stacks[mIndex].Frames[mJump].FileName,
      FReport.Stacks[mIndex].Frames[mJump].Line - 1);
  end;
end;

end.
