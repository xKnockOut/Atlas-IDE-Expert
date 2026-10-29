unit Cm.E2025;

// E2025 Procedure cannot have a result type
// Erwartet: E2025

interface

implementation

procedure MitTyp: Integer; // <- E2025
begin
end;

end.
