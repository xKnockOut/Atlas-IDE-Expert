unit Cm.E2475;

// E2475 '%s' directive not allowed in record helper type
// Erwartet: E2379
// Delphi 13 meldet hier E2379 statt E2475.

interface

type
  THelfer = record helper for Integer
  public
    procedure Machen; virtual; // <- E2379
  end;

implementation

procedure THelfer.Machen;
begin
end;

end.
