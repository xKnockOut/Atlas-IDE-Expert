unit Cm.E2471;

// E2471 Possibly parameterless constructors not allowed on record types
// Erwartet: E2471

interface

type
  TRec = record
    constructor Create(AWert: Integer = 0); // <- E2471
  end;

implementation

constructor TRec.Create(AWert: Integer);
begin
end;

end.
