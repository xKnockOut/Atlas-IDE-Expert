unit Cm.E2018b;

// E2018 Record, object or class type required
// Erwartet: -
// Gegenprobe zu type-kind-required (#1370): Mitglied eines Helpers für Integer bleibt still.

interface

uses
  System.SysUtils;

implementation

function Fall(AZahl: Integer): string;
begin
  Result := AZahl.ToString;
end;

end.
