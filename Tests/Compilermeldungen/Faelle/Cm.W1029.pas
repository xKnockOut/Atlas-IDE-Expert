unit Cm.W1029;

// W1029 Duplicate constructor with identical parameters will be inacessible from C++
// Erwartet: W1029
// Schalter: -JPHNE
// Meldet dcc nur, wenn C++-Ausgabe (-JPHN) eingeschaltet ist; ohne sie bleibt der Fall
// still.

interface

type
  TDoppelt = class
  public
    constructor Erzeugen(AWert: Integer);
    constructor Anlegen(AWert: Integer); // <- W1029
  end;

implementation

constructor TDoppelt.Erzeugen(AWert: Integer);
begin
  inherited Create;
end;

constructor TDoppelt.Anlegen(AWert: Integer);
begin
  inherited Create;
end;

end.
