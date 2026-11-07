unit Atlas.IDE.Debug.Evaluator;

// Auswerten mit Zeitlimit für die Visualisierer (#835) und die eigenen
// Wertdarstellungen (#854) über den Debugger der IDE:
// - Die IDE fragt Ersatztexte synchron ab (GetReplacementValue). Antwortet
//   der Debugger verzögert (erDeferred, Win64), verarbeitet Atlas wie die
//   Beispiele von Embarcadero (StdStringVisualizer) die Debugger-Ereignisse
//   (ProcessDebugEvents), bis die Antwort da ist, höchstens aber
//   debug.visualizers.timeoutMs lang. Danach gilt der Wert als nicht
//   auswertbar; eine späte Antwort landet bei einem abgemeldeten Notifier.
// - Nebenwirkungen nach TAtlasVisualizerEvaluation: nur Felder (eseNone),
//   Getter von Eigenschaften (esePropertiesOnly), Aufrufe (eseAll).
// - Ausgewertet wird im aktuellen Rahmen des angehaltenen Threads.
// - Speicher liest IOTAProcess.ReadProcessMemory in Stücken; Fehler (Adresse
//   nicht lesbar) liefern False statt einer Ausnahme.
// Nur im Hauptthread verwenden.

interface

uses
  System.SysUtils,
  ToolsAPI,
  Atlas.Core.Debug.Visualizers,
  Atlas.Core.Settings.VisualizerKinds;

type
  TAtlasIdeDebugEvaluator = class
  private type
    TWaiter = class(TNotifierObject, IOTAThreadNotifier, IOTAThreadNotifier160)
    public
      Done: Boolean;
      ReturnCode: Integer;
      Text: string;
      { IOTAThreadNotifier }
      procedure ThreadNotify(Reason: TOTANotifyReason);
      procedure EvaluateComplete(const ExprStr, ResultStr: string; CanModify: Boolean;
        ResultAddress, ResultSize: LongWord; ReturnCode: Integer); overload;
      procedure ModifyComplete(const ExprStr, ResultStr: string; ReturnCode: Integer);
      { IOTAThreadNotifier160 }
      procedure EvaluateComplete(const ExprStr, ResultStr: string; CanModify: Boolean;
        ResultAddress: TOTAAddress; ResultSize: LongWord; ReturnCode: Integer); overload;
      procedure Destroyed; reintroduce;
    end;
  private
    /// <summary>Verzögerte Auswertung (erDeferred, etwa LLDB): wartet höchstens ATimeoutMs auf das Ergebnis.
    /// </summary>
    class function WaitDeferred(const AThread: IOTAThread; const ADebugger: IOTADebuggerServices;
      ATimeoutMs: Integer; out AText: string): Boolean; static;
  public const
    cChunkSize = 64 * 1024;
  public
    /// <summary>Thread des angehaltenen Prozesses (psStopped, psFault, psException); sonst nil.</summary>
    class function StoppedThread: IOTAThread; static;
    class function SideEffects(AEvaluation: TAtlasVisualizerEvaluation): TOTAEvalSideEffects; static;
    /// <summary>Wertet AExpression im angehaltenen Thread aus; False bei Fehler, ohne angehaltenen Prozess oder nach
    /// ATimeoutMs.</summary>
    class function Evaluate(const AExpression: string; AEvaluation: TAtlasVisualizerEvaluation; ATimeoutMs: Integer;
      out AText: string): Boolean; static;
    /// <summary>ACount Bytes ab AAddress aus dem angehaltenen Prozess.</summary>
    class function ReadMemory(AAddress: UInt64; ACount: Integer; out ABytes: TBytes): Boolean; static;
    /// <summary>Rückrufe für TAtlasVisualizers: Alle Auswertungen zusammen haben ABudgetMs; was danach kommt,
    /// scheitert, und der Kern lässt den Text der IDE stehen.</summary>
    class function Context(ABudgetMs: Integer): TAtlasVisualizerContext; static;
  end;

implementation

uses
  Winapi.Windows;

const
  cBufferSize = 4096;

{ TAtlasIdeDebugEvaluator.TWaiter }

procedure TAtlasIdeDebugEvaluator.TWaiter.ThreadNotify(Reason: TOTANotifyReason);
begin
  // Läuft das Programm weiter oder endet, kommt keine Antwort mehr.
  if Reason in [nrRunning, nrFault, nrException] then
  begin
    Done := True;
    ReturnCode := -1;
  end;
end;

procedure TAtlasIdeDebugEvaluator.TWaiter.EvaluateComplete(const ExprStr, ResultStr: string; CanModify: Boolean;
  ResultAddress, ResultSize: LongWord; ReturnCode: Integer);
begin
  Text := ResultStr;
  Self.ReturnCode := ReturnCode;
  Done := True;
end;

procedure TAtlasIdeDebugEvaluator.TWaiter.EvaluateComplete(const ExprStr, ResultStr: string; CanModify: Boolean;
  ResultAddress: TOTAAddress; ResultSize: LongWord; ReturnCode: Integer);
begin
  Text := ResultStr;
  Self.ReturnCode := ReturnCode;
  Done := True;
end;

procedure TAtlasIdeDebugEvaluator.TWaiter.ModifyComplete(const ExprStr, ResultStr: string; ReturnCode: Integer);
begin
end;

procedure TAtlasIdeDebugEvaluator.TWaiter.Destroyed;
begin
  Done := True;
  ReturnCode := -1;
end;

{ TAtlasIdeDebugEvaluator }

class function TAtlasIdeDebugEvaluator.StoppedThread: IOTAThread;
var
  mDebugger: IOTADebuggerServices;
  mProcess: IOTAProcess;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, IOTADebuggerServices, mDebugger) then
  begin
    Exit;
  end;
  mProcess := mDebugger.CurrentProcess;
  if (mProcess = nil) or not (mProcess.ProcessState in [psStopped, psFault, psException]) then
  begin
    Exit;
  end;
  Result := mProcess.CurrentThread;
end;

class function TAtlasIdeDebugEvaluator.SideEffects(AEvaluation: TAtlasVisualizerEvaluation): TOTAEvalSideEffects;
begin
  case AEvaluation of
    TAtlasVisualizerEvaluation.Properties:
      Result := esePropertiesOnly;
    TAtlasVisualizerEvaluation.Calls:
      Result := eseAll;
  else
    Result := eseNone;
  end;
end;

class function TAtlasIdeDebugEvaluator.WaitDeferred(const AThread: IOTAThread;
  const ADebugger: IOTADebuggerServices; ATimeoutMs: Integer; out AText: string): Boolean;
var
  mWaiter: TWaiter;
  mWaiterRef: IOTAThreadNotifier;
  mIndex: Integer;
  mStartedAt: UInt64;
begin
  AText := '';
  mWaiter := TWaiter.Create;
  mWaiterRef := mWaiter;
  mIndex := AThread.AddNotifier(mWaiterRef);
  try
    mStartedAt := GetTickCount64;
    while not mWaiter.Done and (GetTickCount64 - mStartedAt < UInt64(ATimeoutMs)) do
    begin
      ADebugger.ProcessDebugEvents;
    end;
  finally
    try
      AThread.RemoveNotifier(mIndex);
    except
      // Thread schon abgebaut.
    end;
  end;
  Result := mWaiter.Done and (mWaiter.ReturnCode = 0);
  if Result then
  begin
    AText := mWaiter.Text;
  end;
end;

class function TAtlasIdeDebugEvaluator.Evaluate(const AExpression: string; AEvaluation: TAtlasVisualizerEvaluation;
  ATimeoutMs: Integer; out AText: string): Boolean;
var
  mDebugger: IOTADebuggerServices;
  mThread: IOTAThread;
  mBuffer: array[0..cBufferSize - 1] of Char;
  mCanModify: Boolean;
  mResultAddr, mResultSize, mResultVal: LongWord;
  mCode: TOTAEvaluateResult;
begin
  AText := '';
  Result := False;
  mThread := StoppedThread;
  if (mThread = nil) or (AExpression = '') or not Supports(BorlandIDEServices, IOTADebuggerServices, mDebugger) then
  begin
    Exit;
  end;
  FillChar(mBuffer, SizeOf(mBuffer), 0);
  try
    mCode := mThread.Evaluate(AExpression, @mBuffer[0], Length(mBuffer), mCanModify, SideEffects(AEvaluation), '',
      mResultAddr, mResultSize, mResultVal, '', 0);
  except
    on Exception do
      Exit;
  end;
  case mCode of
    erOK:
      begin
        AText := mBuffer;
        Result := True;
      end;
    erDeferred:
      Result := WaitDeferred(mThread, mDebugger, ATimeoutMs, AText);
    erError, erBusy:
      ; // Nichts auszuwerten: Result bleibt False.
  end;
end;

class function TAtlasIdeDebugEvaluator.ReadMemory(AAddress: UInt64; ACount: Integer; out ABytes: TBytes): Boolean;
var
  mDebugger: IOTADebuggerServices;
  mProcess: IOTAProcess;
  mOffset, mCount: Integer;
begin
  ABytes := nil;
  Result := False;
  if (AAddress = 0) or (ACount <= 0) or not Supports(BorlandIDEServices, IOTADebuggerServices, mDebugger) then
  begin
    Exit;
  end;
  mProcess := mDebugger.CurrentProcess;
  if (mProcess = nil) or not (mProcess.ProcessState in [psStopped, psFault, psException]) then
  begin
    Exit;
  end;
  SetLength(ABytes, ACount);
  mOffset := 0;
  try
    while mOffset < ACount do
    begin
      mCount := ACount - mOffset;
      if mCount > cChunkSize then
      begin
        mCount := cChunkSize;
      end;
      if mProcess.ReadProcessMemory(AAddress + UInt64(mOffset), mCount, ABytes[mOffset]) <> mCount then
      begin
        Exit;
      end;
      Inc(mOffset, mCount);
    end;
  except
    on Exception do
      Exit;
  end;
  Result := True;
end;

class function TAtlasIdeDebugEvaluator.Context(ABudgetMs: Integer): TAtlasVisualizerContext;
var
  mDeadline: UInt64;
begin
  if ABudgetMs < 1 then
  begin
    ABudgetMs := 1;
  end;
  mDeadline := GetTickCount64 + UInt64(ABudgetMs);
  Result.Eval :=
    function(const AExpression: string; AEvaluation: TAtlasVisualizerEvaluation; out AText: string): Boolean
    var
      Tick: UInt64;
    begin
      AText := '';
      Tick := GetTickCount64;
      Result := (Tick < mDeadline) and Evaluate(AExpression, AEvaluation, Integer(mDeadline - Tick), AText);
    end;
  Result.Read :=
    function(AAddress: UInt64; ACount: Integer; out ABytes: TBytes): Boolean
    begin
      Result := ReadMemory(AAddress, ACount, ABytes);
    end;
end;

end.
