unit Cm.Hilfe.H2456;

interface

function Doppelt(AWert: Integer): Integer; inline;

implementation

uses
  Cm.H2456;

function Doppelt(AWert: Integer): Integer;
begin
  Result := AWert * 2;
end;

end.
