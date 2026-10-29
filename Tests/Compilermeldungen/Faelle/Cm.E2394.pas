unit Cm.E2394;

// E2394 Parameterless constructors not allowed on record types
// Erwartet: E2394

interface

type
  TRec = record
    constructor Create; // <- E2394
  end;

implementation

constructor TRec.Create;
begin
end;

end.
