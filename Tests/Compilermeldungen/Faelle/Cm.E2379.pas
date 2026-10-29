unit Cm.E2379;

// E2379 Virtual methods not allowed in record types
// Erwartet: E2379

interface

type
  TRec = record
    procedure Machen; virtual; // <- E2379
  end;

implementation

procedure TRec.Machen;
begin
end;

end.
