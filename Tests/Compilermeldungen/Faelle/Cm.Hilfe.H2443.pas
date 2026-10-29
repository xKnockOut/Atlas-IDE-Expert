unit Cm.Hilfe.H2443;

interface

function Doppelt(AWert: Integer): Integer; inline;

implementation

uses
  Cm.Hilfe.H2443Tiefe;

function Doppelt(AWert: Integer): Integer;
begin
  Result := Verdoppeln(AWert);
end;

end.
