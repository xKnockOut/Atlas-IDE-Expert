unit Atlas.IDE.Debug.ParallelStacks;

// Parallele Aufrufstapel (#837): füllt bei jedem Halt das Fenster „Parallele Aufrufstapel“ mit den Stapeln aller
// Threads als Baum (Atlas.Core.Debug.ParallelStacks).
//   - Gelesen wird nur, solange das Fenster sichtbar ist. Ab debug.parallelStacks.maxThreads Threads liest Atlas
//     je Zeitgeberschritt höchstens so viele Stapel und zeigt den Baum dazwischen, damit die IDE bedienbar bleibt.
//   - Liefert der Win64-Debugger (LLDB) Stapel erst später, fragt Atlas bis zu cRetries mal nach.
//   - Enter bzw. Doppelklick auf einen Knoten wechselt zum Thread (bei mehreren über eine Auswahlliste) und springt
//     auf die Zeile des Rahmens. Den Rahmen im Fenster Aufrufstack der IDE wählt die ToolsAPI nicht.
//   - Kontextmenü „Thread markieren“ (#852, mit debug.threadsInSource): markierte Threads stehen in der
//     Auswahlliste oben und tragen ⚑.
// Teil „DebugParallelStacks“ (debug.parallelStacks); Release meldet den Zuhörer ab und gibt Zeitgeber und Fenster
// frei (Regel 3). Nur im Hauptthread verwenden.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.ExtCtrls,
  Vcl.Menus,
  Atlas.Core.Debug.Threads,
  Atlas.Core.Debug.ParallelStacks,
  Atlas.IDE.Debug.Session,
  Atlas.UI.Debug.ParallelStacksFrame;

type
  TAtlasIdeDebugParallelStacks = class
  public const
    cIntervalMs = 150;
    cRetries = 10;
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
      procedure PickThread(Sender: TObject);
      procedure FlagSelected(Sender: TObject);
      procedure TreePopup(Sender: TObject);
    end;
  private class var
    FListener: IAtlasIdeDebugListener;
    FTicker: TTicker;
    FTimer: TTimer;
    FMenu: TPopupMenu;
    FStacks: TAtlasDebugThreadStacks;
    FTree: TAtlasDebugStackTree;
    FNext: Integer;
    FRetries: Integer;
    FPickNode: Integer;
    /// <summary>Die Auswahlliste markiert statt zu springen.</summary>
    FPickFlag: Boolean;
    class procedure Refresh; static;
    class procedure ReadStep; static;
    class procedure Rebuild(const AStatus: string); static;
    class procedure ShowRunning; static;
    class procedure Open(ANode: Integer); static;
    class procedure Pick(ANode: Integer; AFlag: Boolean); static;
    class procedure AddFlagMenu(AFrame: TAtlasDebugParallelStacksFrame); static;
    class procedure Jump(AThread, ANode: Integer); static;
  public
    class procedure Start; static;
    class procedure Release; static;
    class function Started: Boolean; static;
    /// <summary>Befehl Atlas.DebugParallelStacks: Fenster zeigen und füllen.</summary>
    class procedure ShowWindow; static;
    class procedure ThemeChanged; static;
  end;

implementation

uses
  Vcl.Controls,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Debug.Threads,
  Atlas.IDE.Debug.ParallelStacksWindow,
  Atlas.Core.Debug.ThreadMarks,
  Atlas.IDE.Debug.ThreadsInSource,
  Atlas.UI.Debug.ThreadMarks,
  Atlas.UI.Debug.Strings;

/// <summary>Fenster, falls es sichtbar ist; sonst nil.</summary>
function ShownFrame: TAtlasDebugParallelStacksFrame;
begin
  Result := nil;
  if TAtlasIdeDebugParallelStacksWindow.Visible then
  begin
    Result := TAtlasIdeDebugParallelStacksWindow.ExistingFrame;
  end;
end;

{ TAtlasIdeDebugParallelStacks.TListener }

procedure TAtlasIdeDebugParallelStacks.TListener.DebugStopped(AStop: TAtlasDebugStop);
begin
  TAtlasGuard.Run(TAtlasFeature.Debugger, TAtlasIdeDebugParallelStacks.Refresh);
end;

procedure TAtlasIdeDebugParallelStacks.TListener.DebugResumed;
begin
  TAtlasGuard.Run(TAtlasFeature.Debugger, TAtlasIdeDebugParallelStacks.ShowRunning);
end;

procedure TAtlasIdeDebugParallelStacks.TListener.DebugEnded;
begin
  TAtlasGuard.Run(TAtlasFeature.Debugger, TAtlasIdeDebugParallelStacks.ShowRunning);
end;

{ TAtlasIdeDebugParallelStacks.TTicker }

procedure TAtlasIdeDebugParallelStacks.TTicker.Tick(Sender: TObject);
begin
  TAtlasGuard.Run(TAtlasFeature.Debugger, TAtlasIdeDebugParallelStacks.ReadStep);
end;

procedure TAtlasIdeDebugParallelStacks.TTicker.PickThread(Sender: TObject);
var
  mThread: Integer;
begin
  mThread := (Sender as TMenuItem).Tag;
  TAtlasGuard.Run(TAtlasFeature.Debugger,
    procedure
    begin
      if TAtlasIdeDebugParallelStacks.FPickFlag then
      begin
        TAtlasIdeDebugThreadsInSource.ToggleFlag(TAtlasIdeDebugParallelStacks.FStacks[mThread]);
      end
      else
      begin
        TAtlasIdeDebugParallelStacks.Jump(mThread, TAtlasIdeDebugParallelStacks.FPickNode);
      end;
    end);
end;

procedure TAtlasIdeDebugParallelStacks.TTicker.FlagSelected(Sender: TObject);
begin
  TAtlasGuard.Run(TAtlasFeature.Debugger,
    procedure
    var
      mFrame: TAtlasDebugParallelStacksFrame;
    begin
      mFrame := ShownFrame;
      if mFrame <> nil then
      begin
        TAtlasIdeDebugParallelStacks.Pick(mFrame.SelectedNode, True);
      end;
    end);
end;

procedure TAtlasIdeDebugParallelStacks.TTicker.TreePopup(Sender: TObject);
var
  mMenu: TPopupMenu;
begin
  // Nur mit „Threads im Quelltext“ (#852): sonst gibt es keine Markierung.
  mMenu := Sender as TPopupMenu;
  if mMenu.Items.Count > 0 then
  begin
    mMenu.Items[0].Visible := TAtlasIdeDebugThreadsInSource.Started;
  end;
end;

{ TAtlasIdeDebugParallelStacks }

class procedure TAtlasIdeDebugParallelStacks.Start;
begin
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
  TAtlasIdeDebugParallelStacksWindow.Prepare;
  TAtlasIdeDebugParallelStacksWindow.OnFrame :=
    procedure(AFrame: TAtlasDebugParallelStacksFrame)
    begin
      AFrame.OnOpen :=
        procedure(ANode: Integer)
        begin
          TAtlasGuard.Run(TAtlasFeature.Debugger,
            procedure
            begin
              Open(ANode);
            end);
        end;
      AFrame.OnFilter :=
        procedure
        begin
          Rebuild('');
        end;
      AddFlagMenu(AFrame);
    end;
  if FListener = nil then
  begin
    FListener := TListener.Create;
    TAtlasIdeDebugSession.AddListener(FListener);
  end;
  TAtlasIdeDebugSession.Start;
end;

class procedure TAtlasIdeDebugParallelStacks.Release;
begin
  if FListener <> nil then
  begin
    TAtlasIdeDebugSession.RemoveListener(FListener);
  end;
  FListener := nil;
  FreeAndNil(FTimer);
  FreeAndNil(FMenu);
  FreeAndNil(FTicker);
  TAtlasIdeDebugParallelStacksWindow.Release;
  FStacks := nil;
  FTree := Default(TAtlasDebugStackTree);
end;

class function TAtlasIdeDebugParallelStacks.Started: Boolean;
begin
  Result := FListener <> nil;
end;

class procedure TAtlasIdeDebugParallelStacks.ShowWindow;
begin
  if not Started then
  begin
    Exit;
  end;
  if TAtlasIdeDebugParallelStacksWindow.Show = nil then
  begin
    Exit;
  end;
  if TAtlasIdeDebugSession.StoppedThread = nil then
  begin
    ShowRunning;
  end
  else
  begin
    Refresh;
  end;
end;

class procedure TAtlasIdeDebugParallelStacks.ThemeChanged;
begin
  TAtlasIdeDebugParallelStacksWindow.ApplyTheme;
end;

class procedure TAtlasIdeDebugParallelStacks.ShowRunning;
var
  mFrame: TAtlasDebugParallelStacksFrame;
begin
  if FTimer <> nil then
  begin
    FTimer.Enabled := False;
  end;
  FStacks := nil;
  FTree := Default(TAtlasDebugStackTree);
  mFrame := ShownFrame;
  if mFrame <> nil then
  begin
    mFrame.ShowStatus(TAtlasDebugStrings.Text(TAtlasDebugTextId.ParallelStacksRunning));
  end;
end;

class procedure TAtlasIdeDebugParallelStacks.Refresh;
begin
  if (FTimer = nil) or (ShownFrame = nil) then
  begin
    Exit;
  end;
  FTimer.Enabled := False;
  FStacks := nil;
  FNext := 0;
  FRetries := 0;
  ReadStep;
end;

class procedure TAtlasIdeDebugParallelStacks.ReadStep;
var
  mProcess: IOTAProcess;
  mChunk: TAtlasDebugThreadStacks;
  mCount: Integer;
begin
  FTimer.Enabled := False;
  mProcess := TAtlasIdeDebugSession.Process;
  if (mProcess = nil) or (TAtlasIdeDebugSession.StoppedThread = nil) or (ShownFrame = nil) then
  begin
    Exit;
  end;
  mCount := TAtlasIdeSettings.Current.DebugParallelStacksMaxThreads;
  mChunk := nil;
  if TAtlasIdeDebugThreads.ReadRange(mProcess, FNext, mCount, mChunk) and (FRetries < cRetries) then
  begin
    // Der Debugger liefert noch: denselben Abschnitt gleich noch einmal lesen.
    Inc(FRetries);
    FTimer.Enabled := True;
    Exit;
  end;
  FRetries := 0;
  FStacks := FStacks + mChunk;
  FNext := FNext + Length(mChunk);
  if (mChunk <> nil) and (FNext < mProcess.ThreadCount) then
  begin
    Rebuild(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.ParallelStacksReading, [FNext, mProcess.ThreadCount]));
    FTimer.Enabled := True;
    Exit;
  end;
  Rebuild('');
end;

class procedure TAtlasIdeDebugParallelStacks.Rebuild(const AStatus: string);
var
  mFrame: TAtlasDebugParallelStacksFrame;
  mProcess: IOTAProcess;
  mCurrent: Integer;
begin
  mFrame := ShownFrame;
  if mFrame = nil then
  begin
    Exit;
  end;
  mCurrent := -1;
  mProcess := TAtlasIdeDebugSession.Process;
  if mProcess <> nil then
  begin
    mCurrent := TAtlasIdeDebugThreads.CurrentIndex(mProcess, FStacks);
  end;
  FTree := TAtlasDebugStackTree.Build(FStacks, mCurrent,
    TAtlasDebugStackTree.ParseRoutines(TAtlasIdeSettings.Current.DebugParallelStacksWaitRoutines), mFrame.Filter);
  mFrame.SetTree(FStacks, FTree, AStatus);
end;

class procedure TAtlasIdeDebugParallelStacks.AddFlagMenu(AFrame: TAtlasDebugParallelStacksFrame);
var
  mMenu: TPopupMenu;
  mItem: TMenuItem;
begin
  // Gehört dem Frame und geht mit ihm.
  mMenu := TPopupMenu.Create(AFrame);
  mItem := TMenuItem.Create(mMenu);
  mItem.Caption := TAtlasDebugStrings.Text(TAtlasDebugTextId.ThreadMarksFlagCommand);
  mItem.OnClick := FTicker.FlagSelected;
  mMenu.Items.Add(mItem);
  mMenu.OnPopup := FTicker.TreePopup;
  AFrame.Tree.RightClickSelect := True;
  AFrame.Tree.PopupMenu := mMenu;
end;

class procedure TAtlasIdeDebugParallelStacks.Open(ANode: Integer);
begin
  Pick(ANode, False);
end;

class procedure TAtlasIdeDebugParallelStacks.Pick(ANode: Integer; AFlag: Boolean);
var
  mThread: Integer;
  mThreads: TArray<Integer>;
  mFlagged: TAtlasDebugThreadSet;
  mItem: TMenuItem;
begin
  if (ANode < 0) or (ANode > High(FTree.Nodes)) then
  begin
    Exit;
  end;
  // Markierte Threads (#852) oben und mit ⚑.
  mFlagged := TAtlasIdeDebugThreadsInSource.Flagged;
  mThreads := TAtlasDebugThreadMarks.Ordered(FStacks, FTree.Nodes[ANode].Threads, mFlagged);
  if Length(mThreads) = 1 then
  begin
    if AFlag then
    begin
      TAtlasIdeDebugThreadsInSource.ToggleFlag(FStacks[mThreads[0]]);
    end
    else
    begin
      Jump(mThreads[0], ANode);
    end;
    Exit;
  end;
  // Mehrere Threads: Auswahlliste an der Maus.
  FreeAndNil(FMenu);
  FMenu := TPopupMenu.Create(nil);
  FPickNode := ANode;
  FPickFlag := AFlag;
  for mThread in mThreads do
  begin
    mItem := TMenuItem.Create(FMenu);
    mItem.Caption := TAtlasThreadMarkTexts.ThreadLabel(FStacks[mThread],
      mFlagged.Contains(FStacks[mThread].ThreadId));
    mItem.Tag := mThread;
    mItem.OnClick := FTicker.PickThread;
    FMenu.Items.Add(mItem);
  end;
  FMenu.Popup(Mouse.CursorPos.X, Mouse.CursorPos.Y);
end;

class procedure TAtlasIdeDebugParallelStacks.Jump(AThread, ANode: Integer);
begin
  if (AThread < 0) or (AThread > High(FStacks)) or (ANode < 0) or (ANode > High(FTree.Nodes)) then
  begin
    Exit;
  end;
  TAtlasIdeDebugThreads.Select(FStacks[AThread].ThreadId);
  if FTree.Nodes[ANode].Frame.HasSource then
  begin
    TAtlasIdeNavigation.MarkLine(FTree.Nodes[ANode].Frame.FileName, FTree.Nodes[ANode].Frame.Line - 1);
  end;
end;

end.
