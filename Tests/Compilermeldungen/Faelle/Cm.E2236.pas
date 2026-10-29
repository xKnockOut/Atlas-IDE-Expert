unit Cm.E2236;

// E2236 Constructors and destructors must have %s calling convention
// Erwartet: E2236

interface

type
  TKlasse = class
  public
    constructor Create; stdcall; // <- E2236
  end;

implementation

constructor TKlasse.Create;
begin
end;

end.
