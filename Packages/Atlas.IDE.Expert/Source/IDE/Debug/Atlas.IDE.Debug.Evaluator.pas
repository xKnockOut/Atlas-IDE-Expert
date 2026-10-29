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
  public const
    ChunkSize = 64 * 1024;
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
  BufferSize = 4096;

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
  Debugger: IOTADebuggerServices;
  Process: IOTAProcess;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, IOTADebuggerServices, Debugger) then
    Exit;
  Process := Debugger.CurrentProcess;
  if (Process = nil) or not (Process.ProcessState in [psStopped, psFault, psException]) then
    Exit;
  Result := Process.CurrentThread;
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

class function TAtlasIdeDebugEvaluator.Evaluate(const AExpression: string; AEvaluation: TAtlasVisualizerEvaluation;
  ATimeoutMs: Integer; out AText: string): Boolean;
var
  Debugger: IOTADebuggerServices;
  Thread: IOTAThread;
  Buffer: array[0..BufferSize - 1] of Char;
  CanModify: Boolean;
  ResultAddr, ResultSize, ResultVal: LongWord;
  Code: TOTAEvaluateResult;
  Waiter: TWaiter;
  WaiterRef: IOTAThreadNotifier;
  Index: Integer;
  StartedAt: UInt64;
begin
  AText := '';
  Result := False;
  Thread := StoppedThread;
  if (Thread = nil) or (AExpression = '') or not Supports(BorlandIDEServices, IOTADebuggerServices, Debugger) then
    Exit;
  FillChar(Buffer, SizeOf(Buffer), 0);
  try
    Code := Thread.Evaluate(AExpression, @Buffer[0], Length(Buffer), CanModify, SideEffects(AEvaluation), '',
      ResultAddr, ResultSize, ResultVal, '', 0);
  except
    on Exception do
      Exit;
  end;
  case Code of
    erOK:
      begin
        AText := Buffer;
        Result := True;
      end;
    erDeferred:
      begin
        Waiter := TWaiter.Create;
        WaiterRef := Waiter;
        Index := Thread.AddNotifier(WaiterRef);
        try
          StartedAt := GetTickCount64;
          while not Waiter.Done and (GetTickCount64 - StartedAt < UInt64(ATimeoutMs)) do
            Debugger.ProcessDebugEvents;
        finally
          try
            Thread.RemoveNotifier(Index);
          except
            // Thread schon abgebaut.
          end;
        end;
        Result := Waiter.Done and (Waiter.ReturnCode = 0);
        if Result then
          AText := Waiter.Text;
      end;
  end;
end;

class function TAtlasIdeDebugEvaluator.ReadMemory(AAddress: UInt64; ACount: Integer; out ABytes: TBytes): Boolean;
var
  Debugger: IOTADebuggerServices;
  Process: IOTAProcess;
  Offset, Count: Integer;
begin
  ABytes := nil;
  Result := False;
  if (AAddress = 0) or (ACount <= 0) or not Supports(BorlandIDEServices, IOTADebuggerServices, Debugger) then
    Exit;
  Process := Debugger.CurrentProcess;
  if (Process = nil) or not (Process.ProcessState in [psStopped, psFault, psException]) then
    Exit;
  SetLength(ABytes, ACount);
  Offset := 0;
  try
    while Offset < ACount do
    begin
      Count := ACount - Offset;
      if Count > ChunkSize then
        Count := ChunkSize;
      if Process.ReadProcessMemory(AAddress + UInt64(Offset), Count, ABytes[Offset]) <> Count then
        Exit;
      Inc(Offset, Count);
    end;
  except
    on Exception do
      Exit;
  end;
  Result := True;
end;

class function TAtlasIdeDebugEvaluator.Context(ABudgetMs: Integer): TAtlasVisualizerContext;
var
  Deadline: UInt64;
begin
  if ABudgetMs < 1 then
    ABudgetMs := 1;
  Deadline := GetTickCount64 + UInt64(ABudgetMs);
  Result.Eval :=
    function(const AExpression: string; AEvaluation: TAtlasVisualizerEvaluation; out AText: string): Boolean
    var
      Tick: UInt64;
    begin
      AText := '';
      Tick := GetTickCount64;
      Result := (Tick < Deadline) and Evaluate(AExpression, AEvaluation, Integer(Deadline - Tick), AText);
    end;
  Result.Read :=
    function(AAddress: UInt64; ACount: Integer; out ABytes: TBytes): Boolean
    begin
      Result := ReadMemory(AAddress, ACount, ABytes);
    end;
end;

end.
