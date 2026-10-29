unit Cm.E2598;

// E2598 Virtual methods not allowed in record helper types
// Erwartet: E2598
// Gleicher Fall wie E2475; dcc entscheidet den Code.

interface

type
  THelfer = record helper for Integer
  public
    procedure Machen; virtual; // <- E2598
  end;

implementation

procedure THelfer.Machen;
begin
end;

end.
