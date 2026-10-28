unit Dcc.Konstanten.Gegen;

// #1328, Gegentest zu typed-constant-modified: Hier soll dcc melden.

interface

procedure OhneJ;

implementation

{$J-}
procedure OhneJ;
const
  cLetzter: Integer = 0;
begin
  cLetzter := 1; // KG1: {$J-}
end;

end.
