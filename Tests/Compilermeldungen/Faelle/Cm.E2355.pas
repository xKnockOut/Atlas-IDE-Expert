unit Cm.E2355;

// E2355 Class property accessor must be a class field or class static method
// Erwartet: E2355

interface

type
  TKlasse = class
  private
    FWert: Integer;
  public
    class property Wert: Integer read FWert; // <- E2355
  end;

implementation

end.
