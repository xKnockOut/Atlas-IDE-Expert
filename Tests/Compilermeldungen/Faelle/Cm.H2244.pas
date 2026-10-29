unit Cm.H2244;

// H2244 Pointer expression needs no Initialize/Finalize - need ^ operator?
// Erwartet: H2244

interface

implementation

procedure Aufraeumen(AZeiger: PString);
begin
  Finalize(AZeiger); // <- H2244
end;

end.
