unit Dcc.Einbetten.Gegen;

// #1328, Gegentests zu type-restriction-violated: Hier meldet dcc E2441.

interface

function VariableNutzen: Integer; inline; // TG1: Variable aus dem implementation-Teil
function TypKonstanteNutzen: Integer; inline; // TG4 (vorher TR3): typisierte Konstante aus dem implementation-Teil

implementation

const
  cStart: Integer = 2;

var
  gZaehler: Integer;

function VariableNutzen: Integer;
begin
  Result := gZaehler;
end;

function TypKonstanteNutzen: Integer;
begin
  Result := cStart;
end;

end.
