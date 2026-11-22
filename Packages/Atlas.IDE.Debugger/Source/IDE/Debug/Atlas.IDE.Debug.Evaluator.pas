unit Atlas.IDE.Debug.Evaluator;

// Auswerten mit Zeitlimit für die Visualisierer (#835) und die eigenen
// Wertdarstellungen (#854) über den Debugger der IDE:
// - Die IDE fragt Ersatztexte synchron ab (GetReplacementValue). Antwortet
//   der Debugger verzögert (erDeferred, Win64), verarbeitet Atlas wie die
//   Beispiele von Embarcadero (StdStringVisualizer) die Debugger-Ereignisse
//   (ProcessDebugEvents), bis die Antwort da ist, höchstens aber
//   debug.visualizers.timeoutMs lang. Danach gilt der Wert als nicht
//   auswertbar; eine späte Antwort landet bei einem abgemeldeten Notifier.
//   Endet der Thread währenddessen (TAtlasIdeThreadNotifier), endet das Warten,
//   und abgemeldet wird nicht mehr.
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
  Atlas.Core.Settings.VisualizerKinds,
  Atlas.IDE.Hover.DebugValue;

type
  /// <summary>Ort für den Debugger beim Auswerten in einem Thread: Datei und Zeile (1-basiert); '' und 0 ohne.
  /// </summary>
  TAtlasIdeEvaluatePlace = record
    FileName: string;
    Line: Integer;
    class function Create(const AFileName: string; ALine: Integer): TAtlasIdeEvaluatePlace; static;
  end;

  TAtlasIdeDebugEvaluator = class
  private type
    TWaiter = class(TAtlasIdeThreadNotifier, IOTAThreadNotifier, IOTAThreadNotifier160)
    protected
      procedure ThreadGone; override;
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
    end;
  private
    /// <summary>Verzögerte Auswertung (erDeferred, etwa LLDB): wartet höchstens ATimeoutMs auf das Ergebnis.
    /// </summary>
    class function WaitDeferred(const AThread: IOTAThread; const ADebugger: IOTADebuggerServices;
      ATimeoutMs: Integer; out AText: string): Boolean; static;
  public const
    cChunkSize = 64 * 1024;
  public
    class function SideEffects(AEvaluation: TAtlasVisualizerEvaluation): TOTAEvalSideEffects; static;
    /// <summary>Wertet AExpression im angehaltenen Thread aus; False bei Fehler, ohne angehaltenen Prozess oder nach
    /// ATimeoutMs.</summary>
    class function Evaluate(const AExpression: string; AEvaluation: TAtlasVisualizerEvaluation; ATimeoutMs: Integer;
      out AText: string): Boolean; static;
    /// <summary>Wertet AExpression im Thread AThread aus, mit APlace als Ort für den Debugger (#866). False bei
    /// Fehler oder nach ATimeoutMs; AText ist dann die Meldung des Debuggers ('' ohne).</summary>
    class function EvaluateIn(const AThread: IOTAThread; const AExpression: string;
      const APlace: TAtlasIdeEvaluatePlace; AEvaluation: TAtlasVisualizerEvaluation; ATimeoutMs: Integer;
      out AText: string): Boolean; static;
    /// <summary>ACount Bytes ab AAddress aus dem angehaltenen Prozess.</summary>
    class function ReadMemory(AAddress: UInt64; ACount: Integer; out ABytes: TBytes): Boolean; static;
    /// <summary>Rückrufe für TAtlasVisualizers: Alle Auswertungen zusammen haben ABudgetMs; was danach kommt,
    /// scheitert, und der Kern lässt den Text der IDE stehen.</summary>
    class function Context(ABudgetMs: Integer): TAtlasVisualizerContext; static;
  end;

implementation

uses
  Winapi.Windows,
  Atlas.Plugin.Diagnostics.Guard;

const
  cBufferSize = 4096;

{ TAtlasIdeEvaluatePlace }

class function TAtlasIdeEvaluatePlace.Create(const AFileName: string; ALine: Integer): TAtlasIdeEvaluatePlace;
begin
  Result.FileName := AFileName;
  Result.Line := ALine;
end;

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

procedure TAtlasIdeDebugEvaluator.TWaiter.ModifyComplete(const ExprStr, ResultStr: string; ReturnCode: Integer);
begin
end;

procedure TAtlasIdeDebugEvaluator.TWaiter.EvaluateComplete(const ExprStr, ResultStr: string; CanModify: Boolean;
  ResultAddress: TOTAAddress; ResultSize: LongWord; ReturnCode: Integer);
begin
  Text := ResultStr;
  Self.ReturnCode := ReturnCode;
  Done := True;
end;

procedure TAtlasIdeDebugEvaluator.TWaiter.ThreadGone;
begin
  // Der Thread ist abgebaut: keine Antwort mehr.
  Done := True;
  ReturnCode := -1;
end;

{ TAtlasIdeDebugEvaluator }

class function TAtlasIdeDebugEvaluator.WaitDeferred(const AThread: IOTAThread;
  const ADebugger: IOTADebuggerServices; ATimeoutMs: Integer; out AText: string): Boolean;
var
  mWaiter: TWaiter;
  mWaiterRef: IOTAThreadNotifier;
  mStartedAt: UInt64;
begin
  AText := '';
  mWaiter := TWaiter.Create;
  mWaiterRef := mWaiter;
  mWaiter.Attach(AThread, mWaiterRef);
  try
    mStartedAt := GetTickCount64;
    while not mWaiter.Done and (GetTickCount64 - mStartedAt < UInt64(ATimeoutMs)) do
    begin
      ADebugger.ProcessDebugEvents;
    end;
  finally
    // Nach dem Ende des Threads (Destroyed) nicht mehr: RemoveNotifier würfe.
    mWaiter.Detach;
  end;
  Result := mWaiter.Done and (mWaiter.ReturnCode = 0);
  if Result then
  begin
    AText := mWaiter.Text;
  end;
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
begin
  Result := EvaluateIn(TAtlasIdeDebugValues.StoppedThread, AExpression, TAtlasIdeEvaluatePlace.Create('', 0),
    AEvaluation, ATimeoutMs, AText);
  if not Result then
  begin
    AText := '';
  end;
end;

class function TAtlasIdeDebugEvaluator.EvaluateIn(const AThread: IOTAThread; const AExpression: string;
  const APlace: TAtlasIdeEvaluatePlace; AEvaluation: TAtlasVisualizerEvaluation; ATimeoutMs: Integer;
  out AText: string): Boolean;
var
  mDebugger: IOTADebuggerServices;
  mBuffer: array[0..cBufferSize - 1] of Char;
  mCanModify: Boolean;
  mResultAddr, mResultSize, mResultVal: LongWord;
  mCode: TOTAEvaluateResult;
begin
  AText := '';
  Result := False;
  if (AThread = nil) or (AExpression = '') or not Supports(BorlandIDEServices, IOTADebuggerServices, mDebugger) then
  begin
    Exit;
  end;
  FillChar(mBuffer, SizeOf(mBuffer), 0);
  try
    mCode := AThread.Evaluate(AExpression, @mBuffer[0], Length(mBuffer), mCanModify, SideEffects(AEvaluation), '',
      mResultAddr, mResultSize, mResultVal, APlace.FileName, APlace.Line);
  except
    on E: Exception do
    begin
      TAtlasGuard.Log('Debugger: Auswerten gescheitert: ' + TAtlasGuard.ErrorText(E)); // german-ok Protokoll
      Exit;
    end;
  end;
  case mCode of
    erOK:
      begin
        AText := mBuffer;
        Result := True;
      end;
    erDeferred:
      Result := WaitDeferred(AThread, mDebugger, ATimeoutMs, AText);
    erError:
      AText := mBuffer; // Meldung des Debuggers („Undeclared identifier …“); Result bleibt False.
    erBusy:
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
    on E: Exception do
    begin
      TAtlasGuard.Log('Debugger: Speicher nicht lesbar: ' + TAtlasGuard.ErrorText(E)); // german-ok Protokoll
      Exit;
    end;
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
