unit Atlas.IDE.Debug.ThreadEvaluator;

// Auswerten und Ändern im angehaltenen Thread der IDE als eigene Auswertung
// der Debug-Sitzung (BeginInternal/EndInternal): Zustandswechsel dabei sind
// kein Fortsetzen.
//   - TAtlasIdeDebugThreadValues: über TAtlasIdeDebugValues
//     (IOTAThread.Evaluate). Bei einem verzögerten Wert (LLDB) endet die eigene
//     Auswertung erst mit ihm oder mit Cancel. Für alle, die beim Halt Werte
//     nachladen (Werte im Editor, Zugriffsverletzung, TAtlasIdeDebugValueRequest).
//   - TAtlasIdeDebugThreadEvaluator: dasselbe als IAtlasDebugEvaluator für die
//     Auswertung in Zeitscheiben (TAtlasEvalSlices, Fenster „Auswerten“ und
//     „Variablen“), in den Tests ersetzt durch eine Fälschung.
// Nur im Hauptthread verwenden.

interface

uses
  Atlas.Core.Hover.DebugValue,
  Atlas.Core.Debug.EvalSlices,
  Atlas.IDE.Hover.DebugValue;

type
  TAtlasIdeDebugThreadValues = class
  private
    FValues: TAtlasIdeDebugValues;
    FInternal: Boolean;
    procedure EndInternal;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>AExpression an AFileName, ALine (1-basiert) auswerten; ein verzögerter Wert kommt über ADone.
    /// </summary>
    function Evaluate(const AExpression, AFileName: string; ALine: Integer; ASideEffects: Boolean;
      const ADone: TAtlasDebugValueEvent): TAtlasDebugValue;
    /// <summary>Laufende Auswertung verwerfen; ihr Rückruf kommt nicht mehr.</summary>
    procedure Cancel;
    /// <summary>AExpression auf ANewValue setzen (IOTAThread.Modify); AResult: neuer Wert bzw. Fehlertext.
    /// </summary>
    class function Modify(const AExpression, AFileName: string; ALine: Integer; const ANewValue: string;
      out AResult: string): Boolean; static;
  end;

  TAtlasIdeDebugThreadEvaluator = class(TInterfacedObject, IAtlasDebugEvaluator)
  private
    FValues: TAtlasIdeDebugThreadValues;
  public
    constructor Create;
    destructor Destroy; override;
    function Evaluate(const AExpression, AFileName: string; ALine: Integer; ASideEffects: Boolean;
      const ADone: TAtlasDebugValueDone): TAtlasDebugValue;
    procedure Cancel;
    function Modify(const AExpression, AFileName: string; ALine: Integer; const ANewValue: string;
      out AResult: string): Boolean;
  end;

implementation

uses
  System.SysUtils,
  Atlas.IDE.Debug.Session;

/// <summary>Verzögerten Wert an ADone, nachdem die eigene Auswertung von AOwner geendet hat; eigene Routine:
/// fängt nur, was sie braucht.</summary>
function Forwarded(AOwner: TAtlasIdeDebugThreadValues; const ADone: TAtlasDebugValueEvent): TAtlasDebugValueEvent;
var
  mDone: TAtlasDebugValueEvent;
begin
  mDone := ADone;
  Result :=
    procedure(const AValue: TAtlasDebugValue)
    begin
      AOwner.EndInternal;
      if Assigned(mDone) then
      begin
        mDone(AValue);
      end;
    end;
end;

/// <summary>ADone als Rückruf von TAtlasIdeDebugValues (eigener Typ des Vertrags).</summary>
function AsEvent(const ADone: TAtlasDebugValueDone): TAtlasDebugValueEvent;
var
  mDone: TAtlasDebugValueDone;
begin
  mDone := ADone;
  Result :=
    procedure(const AValue: TAtlasDebugValue)
    begin
      if Assigned(mDone) then
      begin
        mDone(AValue);
      end;
    end;
end;

{ TAtlasIdeDebugThreadValues }

constructor TAtlasIdeDebugThreadValues.Create;
begin
  inherited Create;
  FValues := TAtlasIdeDebugValues.Create;
end;

destructor TAtlasIdeDebugThreadValues.Destroy;
begin
  // Zuerst verwerfen: Ein verzögerter Wert kommt danach nicht mehr.
  Cancel;
  FreeAndNil(FValues);
  inherited Destroy;
end;

procedure TAtlasIdeDebugThreadValues.EndInternal;
begin
  if FInternal then
  begin
    FInternal := False;
    TAtlasIdeDebugSession.EndInternal;
  end;
end;

function TAtlasIdeDebugThreadValues.Evaluate(const AExpression, AFileName: string; ALine: Integer;
  ASideEffects: Boolean; const ADone: TAtlasDebugValueEvent): TAtlasDebugValue;
begin
  Cancel;
  Result := Default(TAtlasDebugValue);
  TAtlasIdeDebugSession.BeginInternal;
  FInternal := True;
  try
    Result := FValues.Evaluate(AExpression, AFileName, ALine, ASideEffects, Forwarded(Self, ADone));
  finally
    // Verzögerter Wert: Die eigene Auswertung endet erst mit ihm.
    if Result.State <> TAtlasDebugValueState.Pending then
    begin
      EndInternal;
    end;
  end;
end;

procedure TAtlasIdeDebugThreadValues.Cancel;
begin
  if FValues <> nil then
  begin
    FValues.Cancel;
  end;
  EndInternal;
end;

class function TAtlasIdeDebugThreadValues.Modify(const AExpression, AFileName: string; ALine: Integer;
  const ANewValue: string; out AResult: string): Boolean;
begin
  TAtlasIdeDebugSession.BeginInternal;
  try
    Result := TAtlasIdeDebugValues.Modify(AExpression, AFileName, ALine, ANewValue, AResult);
  finally
    TAtlasIdeDebugSession.EndInternal;
  end;
end;

{ TAtlasIdeDebugThreadEvaluator }

constructor TAtlasIdeDebugThreadEvaluator.Create;
begin
  inherited Create;
  FValues := TAtlasIdeDebugThreadValues.Create;
end;

destructor TAtlasIdeDebugThreadEvaluator.Destroy;
begin
  FreeAndNil(FValues);
  inherited Destroy;
end;

function TAtlasIdeDebugThreadEvaluator.Evaluate(const AExpression, AFileName: string; ALine: Integer;
  ASideEffects: Boolean; const ADone: TAtlasDebugValueDone): TAtlasDebugValue;
begin
  Result := FValues.Evaluate(AExpression, AFileName, ALine, ASideEffects, AsEvent(ADone));
end;

procedure TAtlasIdeDebugThreadEvaluator.Cancel;
begin
  FValues.Cancel;
end;

function TAtlasIdeDebugThreadEvaluator.Modify(const AExpression, AFileName: string; ALine: Integer;
  const ANewValue: string; out AResult: string): Boolean;
begin
  Result := TAtlasIdeDebugThreadValues.Modify(AExpression, AFileName, ALine, ANewValue, AResult);
end;

end.
