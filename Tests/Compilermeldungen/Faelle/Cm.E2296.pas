unit Cm.E2296;

// E2296 A constructor introduced in a class helper must call the parameterless constructor of the helped class as the first statement
// Erwartet: E2296
// Laut DccFaelle TR6 übersetzt dcc diese Form; der Fall zeigt, ob eine andere Form E2296
// auslöst.

interface

type
  TBasis = class
  public
    constructor Create;
  end;

  THelfer = class helper for TBasis
  public
    constructor Anlegen(AWert: Integer);
  end;

implementation

constructor TBasis.Create;
begin
end;

constructor THelfer.Anlegen(AWert: Integer);
begin
  if AWert > 0 then
    Create; // <- E2296
end;

end.
