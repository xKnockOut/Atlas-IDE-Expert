unit Cm.E2463;

// E2463 '%s' directive not allowed in record type
// Erwartet: E2379
// Delphi 13 meldet hier E2379 statt E2463.

interface

type
  TRec = record
    procedure Machen; dynamic; // <- E2379
  end;

implementation

procedure TRec.Machen;
begin
end;

end.
