unit Atlas.IDE.Hover.DebugValue;

// Variablenwert im Hover beim Debuggen (#891) über den Debugger der IDE:
//   - Nur bei angehaltenem Prozess (psStopped, psFault, psException).
//   - IOTAThread.Evaluate (Überladung aus IOTAThread90) im Kontext von Datei und
//     Zeile, ohne Nebenwirkungen (eseNone): Die Auswertung ruft nichts im
//     Programm auf.
//   - Antwortet der Debugger verzögert (erDeferred, Win64/LLDB), meldet
//     IOTAThreadNotifier.EvaluateComplete den Wert später. Die IDE wartet nie in
//     einer Schleife darauf; das Ergebnis geht über TAtlasMainThread an den
//     Rückruf, der Notifier wird erst danach im Hauptthread abgemeldet.
//   - Eine neue Auswertung oder Cancel verwirft die laufende.

interface

uses
  System.SysUtils,
  ToolsAPI,
  Atlas.Core.Hover.DebugValue;

type
  /// <summary>Ergebnis einer verzögerten Auswertung; läuft im Hauptthread.</summary>
  TAtlasDebugValueEvent = reference to procedure(const AValue: TAtlasDebugValue);

  TAtlasIdeDebugValues = class
  private type
    TDeferred = class(TNotifierObject, IOTAThreadNotifier, IOTAThreadNotifier160)
    private
      FOwner: TAtlasIdeDebugValues;
      FExpression: string;
      FOnDone: TAtlasDebugValueEvent;
      FDone: Boolean;
      FThreadGone: Boolean;
      procedure Complete(const AResult: string; AReturnCode: Integer);
    public
      constructor Create(AOwner: TAtlasIdeDebugValues; const AExpression: string;
        const AOnDone: TAtlasDebugValueEvent);
      { IOTAThreadNotifier }
      procedure ThreadNotify(Reason: TOTANotifyReason);
      procedure EvaluateComplete(const ExprStr, ResultStr: string; CanModify: Boolean;
        ResultAddress, ResultSize: LongWord; ReturnCode: Integer); overload;
      procedure ModifyComplete(const ExprStr, ResultStr: string; ReturnCode: Integer);
      { IOTAThreadNotifier160 }
      procedure EvaluateComplete(const ExprStr, ResultStr: string; CanModify: Boolean;
        ResultAddress: TOTAAddress; ResultSize: LongWord; ReturnCode: Integer); overload;
      { IOTANotifier: Der Thread wird abgebaut. }
      procedure Destroyed; reintroduce;
    end;
  private
    FDeferred: TDeferred;
    FDeferredRef: IOTAThreadNotifier;
    FThread: IOTAThread;
    FIndex: Integer;
    /// <summary>Notifier abmelden, wenn er zu ADeferred gehört.</summary>
    procedure Release(ADeferred: TDeferred);
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Thread des angehaltenen Prozesses; nil, wenn kein Prozess angehalten ist.</summary>
    class function StoppedThread: IOTAThread; static;
    class function Stopped: Boolean; static;
    /// <summary>Wertet AExpression aus (ALine 1-basiert). Sofort fertig: Wert bzw. Fehler; verzögert:
    /// Pending, AOnDone kommt später im Hauptthread. None ohne angehaltenen Prozess.</summary>
    function Evaluate(const AExpression, AFileName: string; ALine: Integer;
      const AOnDone: TAtlasDebugValueEvent): TAtlasDebugValue;
    /// <summary>Wie Evaluate, wartet aber nicht auf eine verzögerte Antwort (Tooltip der IDE).</summary>
    class function EvaluateNow(const AExpression, AFileName: string; ALine: Integer): TAtlasDebugValue; static;
    /// <summary>Laufende Auswertung verwerfen; ihr Ergebnis kommt nicht mehr.</summary>
    procedure Cancel;
  end;

implementation

uses
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread;

const
  BufferSize = 4096;

type
  TOutcome = record
    Code: TOTAEvaluateResult;
    Text: string;
  end;

function RunEvaluate(const AThread: IOTAThread; const AExpression, AFileName: string;
  ALine: Integer): TOutcome;
var
  Buffer: array[0..BufferSize - 1] of Char;
  CanModify: Boolean;
  ResultAddr, ResultSize, ResultVal: LongWord;
begin
  FillChar(Buffer, SizeOf(Buffer), 0);
  Result.Code := AThread.Evaluate(AExpression, @Buffer[0], Length(Buffer), CanModify, eseNone, '', ResultAddr,
    ResultSize, ResultVal, AFileName, ALine);
  Result.Text := Buffer;
end;

{ TAtlasIdeDebugValues.TDeferred }

constructor TAtlasIdeDebugValues.TDeferred.Create(AOwner: TAtlasIdeDebugValues; const AExpression: string;
  const AOnDone: TAtlasDebugValueEvent);
begin
  inherited Create;
  FOwner := AOwner;
  FExpression := AExpression;
  FOnDone := AOnDone;
end;

procedure TAtlasIdeDebugValues.TDeferred.Complete(const AResult: string; AReturnCode: Integer);
var
  Keep: IOTAThreadNotifier;
  Deferred: TDeferred;
  Value: TAtlasDebugValue;
begin
  if FDone then
    Exit;
  FDone := True;
  if AReturnCode = 0 then
    Value := TAtlasDebugValue.Evaluated(FExpression, AResult)
  else
    Value := TAtlasDebugValue.Failed(FExpression, AResult);
  // Der Debugger ruft aus seiner Benachrichtigung; abmelden und anzeigen erst danach im Hauptthread.
  // Keep hält den Notifier bis dahin am Leben.
  Keep := Self;
  Deferred := Self;
  TAtlasMainThread.ForceQueue(TAtlasFeature.Hover,
    procedure
    begin
      if Keep <> nil then
        TAtlasGuard.Run(TAtlasFeature.Hover,
        procedure
        begin
          if Deferred.FOwner = nil then
            Exit;
          Deferred.FOwner.Release(Deferred);
          if Assigned(Deferred.FOnDone) then
            Deferred.FOnDone(Value);
        end);
    end);
end;

procedure TAtlasIdeDebugValues.TDeferred.ThreadNotify(Reason: TOTANotifyReason);
begin
  // Nichts zu tun: Ob der Debugger zum Auswerten kurz weiterläuft, ist nicht festgelegt. Läuft das Programm
  // wirklich weiter, verwirft der Tooltip die Auswertung beim Schließen (Taste, Klick) über Cancel.
end;

procedure TAtlasIdeDebugValues.TDeferred.EvaluateComplete(const ExprStr, ResultStr: string; CanModify: Boolean;
  ResultAddress, ResultSize: LongWord; ReturnCode: Integer);
begin
  Complete(ResultStr, ReturnCode);
end;

procedure TAtlasIdeDebugValues.TDeferred.EvaluateComplete(const ExprStr, ResultStr: string; CanModify: Boolean;
  ResultAddress: TOTAAddress; ResultSize: LongWord; ReturnCode: Integer);
begin
  Complete(ResultStr, ReturnCode);
end;

procedure TAtlasIdeDebugValues.TDeferred.ModifyComplete(const ExprStr, ResultStr: string; ReturnCode: Integer);
begin
end;

procedure TAtlasIdeDebugValues.TDeferred.Destroyed;
begin
  // Thread beendet: nicht mehr abmelden, kein Wert.
  FThreadGone := True;
  Complete('', -1);
end;

{ TAtlasIdeDebugValues }

constructor TAtlasIdeDebugValues.Create;
begin
  inherited Create;
  FIndex := -1;
end;

destructor TAtlasIdeDebugValues.Destroy;
begin
  Cancel;
  inherited Destroy;
end;

class function TAtlasIdeDebugValues.StoppedThread: IOTAThread;
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

class function TAtlasIdeDebugValues.Stopped: Boolean;
begin
  Result := StoppedThread <> nil;
end;

procedure TAtlasIdeDebugValues.Release(ADeferred: TDeferred);
begin
  if (ADeferred = nil) or (ADeferred <> FDeferred) then
    Exit;
  if (FThread <> nil) and (FIndex >= 0) and not FDeferred.FThreadGone then
    try
      FThread.RemoveNotifier(FIndex);
    except
      // Thread schon abgebaut: nichts mehr abzumelden.
    end;
  FDeferred.FOwner := nil;
  FDeferred := nil;
  FDeferredRef := nil;
  FThread := nil;
  FIndex := -1;
end;

procedure TAtlasIdeDebugValues.Cancel;
begin
  if FDeferred <> nil then
  begin
    FDeferred.FDone := True;
    Release(FDeferred);
  end;
end;

function TAtlasIdeDebugValues.Evaluate(const AExpression, AFileName: string; ALine: Integer;
  const AOnDone: TAtlasDebugValueEvent): TAtlasDebugValue;
var
  Thread: IOTAThread;
  Outcome: TOutcome;
begin
  Cancel;
  Result := Default(TAtlasDebugValue);
  Thread := StoppedThread;
  if (Thread = nil) or (AExpression = '') then
    Exit;
  Outcome := RunEvaluate(Thread, AExpression, AFileName, ALine);
  case Outcome.Code of
    erOK:
      Result := TAtlasDebugValue.Evaluated(AExpression, Outcome.Text);
    erDeferred:
      begin
        // Antwort kommt über den Notifier des Threads.
        FDeferred := TDeferred.Create(Self, AExpression, AOnDone);
        FDeferredRef := FDeferred;
        FThread := Thread;
        FIndex := Thread.AddNotifier(FDeferredRef);
        Result := TAtlasDebugValue.Pending(AExpression);
      end;
  else
    // erError, erBusy: kein Wert.
    Result := TAtlasDebugValue.Failed(AExpression, Outcome.Text);
  end;
end;

class function TAtlasIdeDebugValues.EvaluateNow(const AExpression, AFileName: string;
  ALine: Integer): TAtlasDebugValue;
var
  Thread: IOTAThread;
  Outcome: TOutcome;
begin
  Result := Default(TAtlasDebugValue);
  Thread := StoppedThread;
  if (Thread = nil) or (AExpression = '') then
    Exit;
  Outcome := RunEvaluate(Thread, AExpression, AFileName, ALine);
  if Outcome.Code = erOK then
    Result := TAtlasDebugValue.Evaluated(AExpression, Outcome.Text)
  else
    Result := TAtlasDebugValue.Failed(AExpression, Outcome.Text);
end;

end.
