unit Dcc.Einbetten.Gegen;

// #1328, Gegentests zu type-restriction-violated: Hier meldet dcc E2441.
// dcc meldet E2441 nur einmal je Unit (dcc-Lauf vom 29.10.2026, 13:56): Die
// typisierte Konstante (TG4) steht deshalb in Dcc.Einbetten.Konstante.Gegen.

interface

function VariableNutzen: Integer; inline; // TG1: Variable aus dem implementation-Teil

implementation

var
  gZaehler: Integer;

function VariableNutzen: Integer;
begin
  Result := gZaehler; // TG1
end;

end.
