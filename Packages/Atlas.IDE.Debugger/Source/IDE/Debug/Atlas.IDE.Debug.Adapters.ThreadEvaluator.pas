unit Atlas.IDE.Debug.Adapters.ThreadEvaluator;

// Auswertung im angehaltenen Thread der IDE als IAtlasDebugEvaluator
// (Atlas.Core.Debug.Contract) für die Auswertung in Zeitscheiben: über
// TAtlasIdeDebugThreadValues (Atlas.IDE.Debug.ThreadEvaluator). Erzeugt nur die
// Komposition des Moduls; die Fenster holen neue Auswertungen über
// TAtlasIdeDebugSession.NewEvaluator. Nur im Hauptthread verwenden.

interface

uses
  Atlas.Plugin.Hover.Contract.DebugValue,
  Atlas.Core.Debug.Contract,
  Atlas.IDE.Debug.ThreadEvaluator;

type
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
  Atlas.IDE.Hover.DebugValue;

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
