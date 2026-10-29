unit Cm.E2463;

// E2463 '%s' directive not allowed in record type
// Erwartet: E2463

interface

type
  TRec = record
    procedure Machen; dynamic; // <- E2463
  end;

implementation

procedure TRec.Machen;
begin
end;

end.
