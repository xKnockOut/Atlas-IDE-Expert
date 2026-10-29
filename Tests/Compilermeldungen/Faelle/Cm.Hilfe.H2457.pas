unit Cm.Hilfe.H2457;

interface

function Doppelt(AWert: Integer): Integer; inline;

implementation

uses
  Cm.Hilfe.H2457Mitte;

function Doppelt(AWert: Integer): Integer;
begin
  Result := AWert * 2;
end;

end.
