unit Atlas.IDE.Debug.ThreadsInSource;

// Threads im Quelltext (#852): Bei jedem Halt liest Atlas die Stapel aller Threads und merkt je Zeile, welche
// anderen Threads dort mit ihrem obersten eigenen Rahmen stehen (Atlas.Core.Debug.ThreadMarks). Die Schicht der
// Rinne (Atlas.IDE.Debug.ThreadsGutter) zeigt daraus das Zeichen mit Anzahl und den Tooltip.
//   - Markieren: Die Markierung gilt für die Sitzung und folgt der Thread-ID; markierte Threads stehen in Tooltip,
//     Auswahllisten und den parallelen Aufrufstapeln (#837) oben und tragen ⚑.
//   - Einfrieren (debug.threadFreeze, experimentell): über TAtlasIdeDebugThreadFreeze; die Statusleiste von Atlas
//     zeigt „2 Threads eingefroren“, solange das gilt. Ende der Sitzung und Abschalten tauen alle auf.
//   - Befehle im Kontextmenü des Editors gelten für die Threads an der Zeile des letzten Rechtsklicks in die Rinne
//     (sonst der Schreibmarke); stehen dort mehrere, wählt man über eine Auswahlliste. Ohne Thread an der Zeile gilt
//     der aktuelle Thread.
//   - Liefert der Win64-Debugger (LLDB) Stapel erst später, fragt Atlas bis zu cRetries mal nach.
// Teil „DebugThreadsInSource“ (debug.threadsInSource); Release meldet den Zuhörer ab, taut alle Threads auf, entfernt
// die Zeile der Statusleiste und gibt Zeitgeber und Menü frei (Regel 3). Nur im Hauptthread verwenden.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.ExtCtrls,
  Vcl.Menus,
  Atlas.Core.Status.Contract,
  Atlas.Core.Status.Registry,
  Atlas.Core.Debug.Threads,
  Atlas.Core.Debug.ThreadMarks,
  Atlas.Core.Debug.ThreadsInSourceFlow,
  Atlas.IDE.Debug.Session,
  Atlas.UI.Debug.Strings;

type
  TAtlasIdeDebugThreadsInSource = class
  public const
    cIntervalMs = 150;
    cRetries = 10;
    /// <summary>Höchstens so viele Threads liest Atlas.</summary>
    cMaxThreads = 512;
    cStatusId = 'atlas.debug.frozenThreads';
    cStatusOrder = 86;
    /// <summary>Tag des Eintrags „Alle Threads dieser Zeile“.</summary>
    cAllTag = TAtlasThreadsInSourceFlow.cAllTag;
  private type
    TListener = class(TAtlasIdeDebugListener)
    public
      procedure DebugStopped(AStop: TAtlasDebugStop); override;
      procedure DebugResumed; override;
      procedure DebugEnded; override;
    end;
    TTicker = class
    public
      procedure Tick(Sender: TObject);
      procedure Pick(Sender: TObject);
    end;
  private class var
    FListener: IAtlasIdeDebugListener;
    FTicker: TTicker;
    FTimer: TTimer;
    FMenu: TPopupMenu;
    FRegistry: IAtlasStatusRegistry;
    FStatusRef: IAtlasStatusItem;
    /// <summary>Dieselbe Zeile wie FStatusRef, zum Aktualisieren.</summary>
    FStatusLine: TAtlasStatusLine;
    FMessage: TProc<string>;
    FRetries: Integer;
    FStacks: TAtlasDebugThreadStacks;
    FMarks: TAtlasDebugThreadMarks;
    FFlagged: TAtlasDebugThreadSet;
    FPickAction: TAtlasThreadAction;
    FPickThreads: TArray<Integer>;
    class function TryRead: Boolean; static;
    class procedure Clear; static;
    class procedure Rebuild; static;
    class procedure UpdateStatus; static;
    class procedure Say(AId: TAtlasDebugTextId; const AThread: TAtlasDebugThreadStack); static;
    /// <summary>Threads für einen Befehl aus dem Kontextmenü (siehe Kopf).</summary>
    class function ContextThreads: TArray<Integer>; static;
    class procedure Choose(AAction: TAtlasThreadAction; const AThreads: TArray<Integer>); static;
    class procedure Apply(AAction: TAtlasThreadAction; AThread: Integer); static;
  public
    class procedure Start(const AMessage: TProc<string>; const ARegistry: IAtlasStatusRegistry); static;
    class procedure Release; static;
    class function Started: Boolean; static;
    { Für die Rinne }
    class function Marks: TAtlasDebugThreadMarks; static;
    class function Stacks: TAtlasDebugThreadStacks; static;
    class function Flagged: TAtlasDebugThreadSet; static;
    /// <summary>Zum Thread AThread (Index in Stacks) wechseln und auf seine Zeile springen.</summary>
    class procedure Switch(AThread: Integer); static;
    /// <summary>Markierung des Threads AStack umschalten (auch aus den parallelen Aufrufstapeln, #837).</summary>
    class procedure ToggleFlag(const AStack: TAtlasDebugThreadStack); static;
    { Befehle }
    class procedure FlagAtLine; static;
    class procedure FreezeAtLine; static;
    class procedure ThawAtLine; static;
    class procedure ThawAll; static;
    /// <summary>Einfrieren erlaubt (debug.threadFreeze) und das Programm steht?</summary>
    class function FreezeAvailable: Boolean; static;
    /// <summary>Ist ein Thread eingefroren?</summary>
    class function AnyFrozen: Boolean; static;
  end;

implementation

uses
  Vcl.Controls,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.GutterMarks,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Debug.Threads,
  Atlas.IDE.Debug.ThreadFreeze,
  Atlas.UI.Debug.ThreadMarks;

{ TAtlasIdeDebugThreadsInSource.TListener }

procedure TAtlasIdeDebugThreadsInSource.TListener.DebugStopped(AStop: TAtlasDebugStop);
begin
  TAtlasGuard.Run(TAtlasFeature.Debugger,
    procedure
    begin
      TAtlasIdeDebugThreadsInSource.FRetries := 0;
      if TAtlasIdeDebugThreadsInSource.TryRead then
      begin
        TAtlasIdeDebugThreadsInSource.Rebuild;
      end
      else
      begin
        TAtlasIdeDebugThreadsInSource.FTimer.Enabled := True;
      end;
    end);
end;

procedure TAtlasIdeDebugThreadsInSource.TListener.DebugResumed;
begin
  TAtlasGuard.Run(TAtlasFeature.Debugger, TAtlasIdeDebugThreadsInSource.Clear);
end;

procedure TAtlasIdeDebugThreadsInSource.TListener.DebugEnded;
begin
  TAtlasGuard.Run(TAtlasFeature.Debugger,
    procedure
    begin
      // Ende der Sitzung: alle auftauen, Markierungen vergessen (die Thread-IDs gelten nicht mehr).
      TAtlasIdeDebugThreadFreeze.ThawAll;
      TAtlasIdeDebugThreadsInSource.FFlagged.Clear;
      TAtlasIdeDebugThreadsInSource.Clear;
      TAtlasIdeDebugThreadsInSource.UpdateStatus;
    end);
end;

{ TAtlasIdeDebugThreadsInSource.TTicker }

procedure TAtlasIdeDebugThreadsInSource.TTicker.Tick(Sender: TObject);
begin
  TAtlasGuard.Run(TAtlasFeature.Debugger,
    procedure
    begin
      if TAtlasIdeDebugThreadsInSource.TryRead then
      begin
        TAtlasIdeDebugThreadsInSource.FTimer.Enabled := False;
        TAtlasIdeDebugThreadsInSource.Rebuild;
      end;
    end);
end;

procedure TAtlasIdeDebugThreadsInSource.TTicker.Pick(Sender: TObject);
var
  mTag: Integer;
begin
  mTag := (Sender as TMenuItem).Tag;
  TAtlasGuard.Run(TAtlasFeature.Debugger,
    procedure
    var
      mThread: Integer;
    begin
      for mThread in TAtlasThreadsInSourceFlow.Targets(mTag, TAtlasIdeDebugThreadsInSource.FPickThreads) do
      begin
        TAtlasIdeDebugThreadsInSource.Apply(TAtlasIdeDebugThreadsInSource.FPickAction, mThread);
      end;
    end);
end;

{ TAtlasIdeDebugThreadsInSource }

class function TAtlasIdeDebugThreadsInSource.TryRead: Boolean;
var
  mProcess: IOTAProcess;
  mStacks: TAtlasDebugThreadStacks;
  mPending: Boolean;
begin
  Result := True;
  mProcess := TAtlasIdeDebugSession.Process;
  if (mProcess = nil) or (TAtlasIdeDebugSession.StoppedThread = nil) then
  begin
    FStacks := nil;
    Exit;
  end;
  mStacks := nil;
  mPending := TAtlasIdeDebugThreads.ReadRange(mProcess, 0, cMaxThreads, mStacks);
  Inc(FRetries);
  Result := TAtlasThreadsInSourceFlow.ReadDone(mPending, FRetries, cRetries);
  FStacks := mStacks;
end;

class procedure TAtlasIdeDebugThreadsInSource.Clear;
begin
  if FTimer <> nil then
  begin
    FTimer.Enabled := False;
  end;
  if FMarks.Marks = nil then
  begin
    FStacks := nil;
    Exit;
  end;
  FStacks := nil;
  FMarks := Default(TAtlasDebugThreadMarks);
  TAtlasIdeGutterMarks.Invalidate;
end;

class procedure TAtlasIdeDebugThreadsInSource.Rebuild;
var
  mProcess: IOTAProcess;
  mCurrent: Integer;
begin
  mCurrent := -1;
  mProcess := TAtlasIdeDebugSession.Process;
  if mProcess <> nil then
  begin
    mCurrent := TAtlasIdeDebugThreads.CurrentIndex(mProcess, FStacks);
  end;
  FMarks := TAtlasDebugThreadMarks.Build(FStacks, mCurrent, FFlagged);
  TAtlasIdeGutterMarks.Invalidate;
end;

class procedure TAtlasIdeDebugThreadsInSource.UpdateStatus;
var
  mLine: TAtlasStatusLine;
  mCount: Integer;
begin
  if FRegistry = nil then
  begin
    Exit;
  end;
  mCount := TAtlasIdeDebugThreadFreeze.Count;
  if mCount = 0 then
  begin
    if FStatusRef <> nil then
    begin
      FRegistry.Remove(cStatusId);
    end;
    FStatusRef := nil;
    FStatusLine := nil;
    Exit;
  end;
  if FStatusRef = nil then
  begin
    // Klick auf die Zeile taut alle auf.
    mLine := TAtlasStatusLine.Create(FRegistry, cStatusId, cStatusOrder,
      procedure
      begin
        TAtlasGuard.Run(TAtlasFeature.Debugger, TAtlasIdeDebugThreadsInSource.ThawAll);
      end);
    FStatusRef := mLine;
    FStatusLine := mLine;
    FRegistry.Add(FStatusRef);
  end;
  // Gelb: Eingefrorene Threads verändern, wie das Programm läuft.
  FStatusLine.Update(TAtlasThreadMarkTexts.FrozenText(mCount), TAtlasStatusState.Yellow);
end;

class procedure TAtlasIdeDebugThreadsInSource.Say(AId: TAtlasDebugTextId; const AThread: TAtlasDebugThreadStack);
begin
  if Assigned(FMessage) then
  begin
    FMessage(TAtlasDebugStrings.Fmt(AId, [TAtlasThreadMarkTexts.ThreadLabel(AThread, False)]));
  end;
end;

class function TAtlasIdeDebugThreadsInSource.ContextThreads: TArray<Integer>;
var
  mView: IOTAEditView;
  mFileName: string;
  mLine: Integer;
  mProcess: IOTAProcess;
begin
  mFileName := '';
  mLine := 0;
  mView := TAtlasEditorBuffer.ActiveView;
  if (mView <> nil) and (mView.Buffer <> nil) then
  begin
    mFileName := mView.Buffer.FileName;
    if (mFileName <> '') and not TAtlasIdeGutterMarks.TakeLine(mFileName, mLine) then
    begin
      mLine := mView.CursorPos.Line - 1;
    end;
  end;
  Result := TAtlasThreadsInSourceFlow.ThreadsAt(FMarks, mFileName, mLine + 1);
  if Result <> nil then
  begin
    Exit;
  end;
  mProcess := TAtlasIdeDebugSession.Process;
  if mProcess <> nil then
  begin
    Result := TAtlasThreadsInSourceFlow.CurrentOnly(TAtlasIdeDebugThreads.CurrentIndex(mProcess, FStacks));
  end;
end;

class procedure TAtlasIdeDebugThreadsInSource.Choose(AAction: TAtlasThreadAction; const AThreads: TArray<Integer>);
var
  mThread: Integer;
  mItem: TMenuItem;
begin
  case TAtlasThreadsInSourceFlow.PickOf(FStacks <> nil, TAtlasIdeDebugSession.StoppedThread <> nil,
    Length(AThreads)) of
    TAtlasThreadPick.NotStopped:
      begin
        if Assigned(FMessage) then
        begin
          FMessage(TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugWaitsNotStopped));
        end;
        Exit;
      end;
    TAtlasThreadPick.Nothing:
      Exit;
    TAtlasThreadPick.Direct:
      begin
        Apply(AAction, AThreads[0]);
        Exit;
      end;
    TAtlasThreadPick.Menu:
      FreeAndNil(FMenu);
  end;
  // Mehrere Threads: Auswahlliste an der Maus, markierte oben (Reihenfolge der Marke).
  FMenu := TPopupMenu.Create(nil);
  FPickAction := AAction;
  FPickThreads := AThreads;
  for mThread in AThreads do
  begin
    mItem := TMenuItem.Create(FMenu);
    mItem.Caption := TAtlasThreadMarkTexts.ThreadLabel(FStacks[mThread],
      FFlagged.Contains(FStacks[mThread].ThreadId));
    mItem.Tag := mThread;
    mItem.OnClick := FTicker.Pick;
    FMenu.Items.Add(mItem);
  end;
  if TAtlasThreadsInSourceFlow.OffersAll(AAction) then
  begin
    mItem := TMenuItem.Create(FMenu);
    mItem.Caption := TAtlasDebugStrings.Text(TAtlasDebugTextId.ThreadMarksAllHere);
    mItem.Tag := cAllTag;
    mItem.OnClick := FTicker.Pick;
    FMenu.Items.Add(mItem);
  end;
  FMenu.Popup(Mouse.CursorPos.X, Mouse.CursorPos.Y);
end;

class procedure TAtlasIdeDebugThreadsInSource.Apply(AAction: TAtlasThreadAction; AThread: Integer);
var
  mStack: TAtlasDebugThreadStack;
begin
  if not TAtlasThreadsInSourceFlow.ValidThread(AThread, Length(FStacks)) then
  begin
    Exit;
  end;
  mStack := FStacks[AThread];
  case AAction of
    TAtlasThreadAction.Switch:
      Switch(AThread);
    TAtlasThreadAction.Flag:
      ToggleFlag(mStack);
    TAtlasThreadAction.Freeze:
      begin
        if TAtlasIdeDebugThreadFreeze.Freeze(mStack.ThreadId) then
        begin
          Say(TAtlasDebugTextId.ThreadMarksFrozenOn, mStack);
        end
        else
        begin
          Say(TAtlasDebugTextId.ThreadMarksFreezeFailed, mStack);
        end;
        UpdateStatus;
        TAtlasIdeGutterMarks.Invalidate;
      end;
    TAtlasThreadAction.Thaw:
      begin
        if TAtlasIdeDebugThreadFreeze.Thaw(mStack.ThreadId) then
        begin
          Say(TAtlasDebugTextId.ThreadMarksThawed, mStack);
        end;
        UpdateStatus;
        TAtlasIdeGutterMarks.Invalidate;
      end;
  end;
end;

class procedure TAtlasIdeDebugThreadsInSource.Start(const AMessage: TProc<string>;
  const ARegistry: IAtlasStatusRegistry);
begin
  FMessage := AMessage;
  FRegistry := ARegistry;
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
  if FListener = nil then
  begin
    FListener := TListener.Create;
    TAtlasIdeDebugSession.AddListener(FListener);
  end;
  TAtlasIdeDebugSession.Start;
end;

class procedure TAtlasIdeDebugThreadsInSource.Release;
begin
  if FListener <> nil then
  begin
    TAtlasIdeDebugSession.RemoveListener(FListener);
  end;
  FListener := nil;
  TAtlasIdeDebugThreadFreeze.Release;
  FFlagged.Clear;
  if (FRegistry <> nil) and (FStatusRef <> nil) then
  begin
    FRegistry.Remove(cStatusId);
  end;
  FStatusRef := nil;
  FStatusLine := nil;
  FRegistry := nil;
  FreeAndNil(FTimer);
  FreeAndNil(FMenu);
  FreeAndNil(FTicker);
  FMessage := nil;
  FStacks := nil;
  FMarks := Default(TAtlasDebugThreadMarks);
  FPickThreads := nil;
end;

class function TAtlasIdeDebugThreadsInSource.Started: Boolean;
begin
  Result := FListener <> nil;
end;

class function TAtlasIdeDebugThreadsInSource.Marks: TAtlasDebugThreadMarks;
begin
  Result := FMarks;
end;

class function TAtlasIdeDebugThreadsInSource.Stacks: TAtlasDebugThreadStacks;
begin
  Result := FStacks;
end;

class function TAtlasIdeDebugThreadsInSource.Flagged: TAtlasDebugThreadSet;
begin
  Result := FFlagged;
end;

class procedure TAtlasIdeDebugThreadsInSource.Switch(AThread: Integer);
var
  mJump: Integer;
begin
  if not TAtlasThreadsInSourceFlow.ValidThread(AThread, Length(FStacks)) then
  begin
    Exit;
  end;
  TAtlasIdeDebugThreads.Select(FStacks[AThread].ThreadId);
  mJump := FStacks[AThread].JumpFrame;
  if mJump >= 0 then
  begin
    TAtlasIdeNavigation.MarkLine(FStacks[AThread].Frames[mJump].FileName, FStacks[AThread].Frames[mJump].Line - 1);
  end;
end;

class procedure TAtlasIdeDebugThreadsInSource.ToggleFlag(const AStack: TAtlasDebugThreadStack);
begin
  if FFlagged.Toggle(AStack.ThreadId) then
  begin
    Say(TAtlasDebugTextId.ThreadMarksFlaggedOn, AStack);
  end
  else
  begin
    Say(TAtlasDebugTextId.ThreadMarksFlaggedOff, AStack);
  end;
  Rebuild;
end;

class procedure TAtlasIdeDebugThreadsInSource.FlagAtLine;
begin
  Choose(TAtlasThreadAction.Flag, ContextThreads);
end;

class procedure TAtlasIdeDebugThreadsInSource.FreezeAtLine;
begin
  if not TAtlasIdeSettings.Current.DebugThreadFreeze then
  begin
    Exit;
  end;
  Choose(TAtlasThreadAction.Freeze, ContextThreads);
end;

class procedure TAtlasIdeDebugThreadsInSource.ThawAtLine;
begin
  Choose(TAtlasThreadAction.Thaw, ContextThreads);
end;

class procedure TAtlasIdeDebugThreadsInSource.ThawAll;
begin
  if TAtlasIdeDebugThreadFreeze.Count = 0 then
  begin
    Exit;
  end;
  TAtlasIdeDebugThreadFreeze.ThawAll;
  if Assigned(FMessage) then
  begin
    FMessage(TAtlasDebugStrings.Text(TAtlasDebugTextId.ThreadMarksThawedAll));
  end;
  UpdateStatus;
  TAtlasIdeGutterMarks.Invalidate;
end;

class function TAtlasIdeDebugThreadsInSource.FreezeAvailable: Boolean;
begin
  Result := Started and TAtlasIdeSettings.Current.DebugThreadFreeze;
end;

class function TAtlasIdeDebugThreadsInSource.AnyFrozen: Boolean;
begin
  Result := TAtlasIdeDebugThreadFreeze.Count > 0;
end;

end.
