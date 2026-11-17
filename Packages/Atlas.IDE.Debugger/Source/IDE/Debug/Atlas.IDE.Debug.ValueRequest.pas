unit Atlas.IDE.Debug.ValueRequest;

// Eine Auswertung nach der anderen für Funktionen, die beim Halt Werte
// nachladen („Warum bin ich hier?“ #1878, angeheftete Werte #526):
//   - Evaluate über TAtlasIdeDebugThreadValues im Kontext von Datei und
//     Zeile, als eigene Auswertung der Debug-Sitzung geklammert: Zustandswechsel
//     dabei sind kein Fortsetzen.
//   - Antwortet der Debugger verzögert (erDeferred, LLDB), meldet Busy das
//     Warten, höchstens ATimeoutMs lang; danach gilt der Wert als nicht
//     auswertbar und der Rückruf kommt mit AOk = False.
//   - Cancel verwirft die laufende Auswertung; ihr Rückruf kommt nicht mehr.
// Nur im Hauptthread verwenden.

interface

uses
  Atlas.Core.Hover.DebugValue,
  Atlas.IDE.Debug.ThreadEvaluator;

type
  /// <summary>Ergebnis einer Auswertung; AOk = False: nicht auswertbar.</summary>
  TAtlasDebugValueResult = reference to procedure(const AText: string; AOk: Boolean);

  {$SCOPEDENUMS ON}
  /// <summary>Done: Rückruf ist schon gekommen; Waiting: verzögert, Rückruf folgt; NoProcess: kein Halt mehr.
  /// </summary>
  TAtlasDebugRequestState = (Done, Waiting, NoProcess);
  {$SCOPEDENUMS OFF}

  TAtlasIdeDebugValueRequest = class
  private
    FEvaluator: TAtlasIdeDebugThreadValues;
    FTimeoutMs: Cardinal;
    FWaiting: Boolean;
    FSince: UInt64;
    FDone: TAtlasDebugValueResult;
    procedure Deferred(const AValue: TAtlasDebugValue);
    procedure Finish(const AText: string; AOk: Boolean);
  public
    constructor Create(ATimeoutMs: Cardinal);
    destructor Destroy; override;
    /// <summary>AExpression an AFileName, ALine (1-basiert) auswerten; ASideEffects erlaubt Aufrufe.</summary>
    function Evaluate(const AExpression, AFileName: string; ALine: Integer; ASideEffects: Boolean;
      const ADone: TAtlasDebugValueResult): TAtlasDebugRequestState;
    /// <summary>Wartet eine verzögerte Antwort noch? Nach dem Zeitlimit: verwerfen, Rückruf mit AOk = False,
    /// Ergebnis False.</summary>
    function Busy: Boolean;
    procedure Cancel;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Diagnostics.Deadline;

{ TAtlasIdeDebugValueRequest }

constructor TAtlasIdeDebugValueRequest.Create(ATimeoutMs: Cardinal);
begin
  inherited Create;
  FTimeoutMs := ATimeoutMs;
  FEvaluator := TAtlasIdeDebugThreadValues.Create;
end;

destructor TAtlasIdeDebugValueRequest.Destroy;
begin
  Cancel;
  FreeAndNil(FEvaluator);
  inherited Destroy;
end;

procedure TAtlasIdeDebugValueRequest.Deferred(const AValue: TAtlasDebugValue);
begin
  if FWaiting then
  begin
    Finish(AValue.Text, AValue.State = TAtlasDebugValueState.Value);
  end;
end;

procedure TAtlasIdeDebugValueRequest.Finish(const AText: string; AOk: Boolean);
var
  mDone: TAtlasDebugValueResult;
begin
  FWaiting := False;
  mDone := FDone;
  FDone := nil;
  if Assigned(mDone) then
  begin
    mDone(AText, AOk);
  end;
end;

function TAtlasIdeDebugValueRequest.Evaluate(const AExpression, AFileName: string; ALine: Integer;
  ASideEffects: Boolean; const ADone: TAtlasDebugValueResult): TAtlasDebugRequestState;
var
  mValue: TAtlasDebugValue;
begin
  Cancel;
  FDone := ADone;
  mValue := FEvaluator.Evaluate(AExpression, AFileName, ALine, ASideEffects, Deferred);
  case mValue.State of
    TAtlasDebugValueState.Pending:
      begin
        FWaiting := True;
        FSince := TAtlasTicks.Now;
        Result := TAtlasDebugRequestState.Waiting;
      end;
    TAtlasDebugValueState.Value, TAtlasDebugValueState.Failed:
      begin
        Finish(mValue.Text, mValue.State = TAtlasDebugValueState.Value);
        Result := TAtlasDebugRequestState.Done;
      end;
  else
    FDone := nil;
    Result := TAtlasDebugRequestState.NoProcess;
  end;
end;

function TAtlasIdeDebugValueRequest.Busy: Boolean;
begin
  Result := FWaiting and (TAtlasTicks.Since(FSince) < FTimeoutMs);
  if FWaiting and not Result then
  begin
    FEvaluator.Cancel;
    Finish('', False);
  end;
end;

procedure TAtlasIdeDebugValueRequest.Cancel;
begin
  if FEvaluator <> nil then
  begin
    FEvaluator.Cancel;
  end;
  FWaiting := False;
  FDone := nil;
end;

end.
