unit Atlas.Tests.DebugEvaluatorFake;

// Fälschung für IAtlasDebugEvaluator: spielt den angehaltenen Thread der IDE
// für die Auswertung in Zeitscheiben. Werte und Fehler legt der Test je
// Ausdruck fest (ohne das angehängte ",r"); Ausdrücke unter Defer antworten
// verzögert wie LLDB, bis der Test Answer ruft. Stop beendet den Halt
// (Ergebnis None). Jede Auswertung wird mitgeschrieben
// („Ausdruck@Datei:Zeile“, mit Nebenwirkungen „!“ dahinter); OnEvaluate
// läuft bei jeder Auswertung, etwa um die Uhr des Tests weiterzustellen.
// Modify setzt den Wert eines bekannten Ausdrucks; Ausdrücke unter Fail
// lassen sich nicht ändern.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Atlas.Core.Hover.DebugValue,
  Atlas.Core.Debug.EvalSlices;

type
  TAtlasDebugEvaluatorFake = class(TInterfacedObject, IAtlasDebugEvaluator)
  private
    FValues: TDictionary<string, string>;
    FFailures: TDictionary<string, string>;
    FDeferred: TList<string>;
    FCalls: TStringList;
    FStopped: Boolean;
    FCancels: Integer;
    FPending: TAtlasDebugValueDone;
    FPendingExpression: string;
    FOnEvaluate: TProc;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>AExpression ergibt AText.</summary>
    procedure Value(const AExpression, AText: string);
    /// <summary>AExpression scheitert mit AText.</summary>
    procedure Fail(const AExpression, AText: string);
    /// <summary>AExpression antwortet verzögert (Pending); der Wert kommt mit Answer.</summary>
    procedure Defer(const AExpression: string);
    /// <summary>Verzögerte Antwort geben; False, wenn keine aussteht (verworfen oder nie angefragt).</summary>
    function Answer(const AText: string; AOk: Boolean): Boolean;
    /// <summary>Halt vorbei: jede Auswertung ergibt None.</summary>
    procedure Stop;
    { IAtlasDebugEvaluator }
    function Evaluate(const AExpression, AFileName: string; ALine: Integer; ASideEffects: Boolean;
      const ADone: TAtlasDebugValueDone): TAtlasDebugValue;
    procedure Cancel;
    function Modify(const AExpression, AFileName: string; ALine: Integer; const ANewValue: string;
      out AResult: string): Boolean;
    /// <summary>Mitgeschriebene Auswertungen in Reihenfolge.</summary>
    property Calls: TStringList read FCalls;
    property Cancels: Integer read FCancels;
    property OnEvaluate: TProc read FOnEvaluate write FOnEvaluate;
  end;

implementation

{ TAtlasDebugEvaluatorFake }

constructor TAtlasDebugEvaluatorFake.Create;
begin
  inherited Create;
  FValues := TDictionary<string, string>.Create;
  FFailures := TDictionary<string, string>.Create;
  FDeferred := TList<string>.Create;
  FCalls := TStringList.Create;
end;

destructor TAtlasDebugEvaluatorFake.Destroy;
begin
  FPending := nil;
  FOnEvaluate := nil;
  FCalls.Free;
  FDeferred.Free;
  FFailures.Free;
  FValues.Free;
  inherited Destroy;
end;

procedure TAtlasDebugEvaluatorFake.Value(const AExpression, AText: string);
begin
  FValues.AddOrSetValue(AExpression, AText);
end;

procedure TAtlasDebugEvaluatorFake.Fail(const AExpression, AText: string);
begin
  FFailures.AddOrSetValue(AExpression, AText);
end;

procedure TAtlasDebugEvaluatorFake.Defer(const AExpression: string);
begin
  FDeferred.Add(AExpression);
end;

function TAtlasDebugEvaluatorFake.Answer(const AText: string; AOk: Boolean): Boolean;
var
  mDone: TAtlasDebugValueDone;
  mValue: TAtlasDebugValue;
begin
  Result := Assigned(FPending);
  if not Result then
  begin
    Exit;
  end;
  mDone := FPending;
  FPending := nil;
  if AOk then
  begin
    mValue := TAtlasDebugValue.Evaluated(FPendingExpression, AText);
  end
  else
  begin
    mValue := TAtlasDebugValue.Failed(FPendingExpression, AText);
  end;
  mDone(mValue);
end;

procedure TAtlasDebugEvaluatorFake.Stop;
begin
  FStopped := True;
end;

function TAtlasDebugEvaluatorFake.Evaluate(const AExpression, AFileName: string; ALine: Integer;
  ASideEffects: Boolean; const ADone: TAtlasDebugValueDone): TAtlasDebugValue;
var
  mName, mCall, mText: string;
begin
  mCall := AExpression + '@' + AFileName + ':' + IntToStr(ALine);
  if ASideEffects then
  begin
    mCall := mCall + '!';
  end;
  FCalls.Add(mCall);
  if Assigned(FOnEvaluate) then
  begin
    FOnEvaluate();
  end;
  mName := AExpression;
  if mName.EndsWith(',r') then
  begin
    mName := mName.Substring(0, mName.Length - 2);
  end;
  Result := Default(TAtlasDebugValue);
  if FStopped then
  begin
    Exit;
  end;
  if FDeferred.Contains(mName) then
  begin
    FPending := ADone;
    FPendingExpression := AExpression;
    Result := TAtlasDebugValue.Pending(AExpression);
  end
  else if FValues.TryGetValue(mName, mText) then
  begin
    Result := TAtlasDebugValue.Evaluated(AExpression, mText);
  end
  else if FFailures.TryGetValue(mName, mText) then
  begin
    Result := TAtlasDebugValue.Failed(AExpression, mText);
  end
  else
  begin
    Result := TAtlasDebugValue.Failed(AExpression, 'E2003 Undeclared identifier: ''' + mName + '''');
  end;
end;

procedure TAtlasDebugEvaluatorFake.Cancel;
begin
  Inc(FCancels);
  FPending := nil;
end;

function TAtlasDebugEvaluatorFake.Modify(const AExpression, AFileName: string; ALine: Integer;
  const ANewValue: string; out AResult: string): Boolean;
begin
  Result := not FStopped and FValues.ContainsKey(AExpression);
  if Result then
  begin
    FValues[AExpression] := ANewValue;
    AResult := ANewValue;
  end
  else
  begin
    AResult := 'cannot modify ' + AExpression;
  end;
end;

end.
