unit Dcc.Einbetten.Konstante.Gegen;

// #1328, Gegentest zu type-restriction-violated: typisierte Konstante des
// implementation-Teils in einer Inline-Routine des interface-Teils (E2441;
// im ersten dcc-Lauf als TR3 gemeldet). Eigenes Projekt, weil dcc E2441 nur
// einmal je Unit meldet.

interface

function TypKonstanteNutzen: Integer; inline; // TG4 (vorher TR3): typisierte Konstante aus dem implementation-Teil

implementation

const
  cStart: Integer = 2;

function TypKonstanteNutzen: Integer;
begin
  Result := cStart; // TG4
end;

end.
