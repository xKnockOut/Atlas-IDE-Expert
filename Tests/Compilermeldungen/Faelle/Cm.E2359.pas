unit Cm.E2359;

// E2359 Multiple class constructors in class %s: %s and %s
// Erwartet: E2359

interface

type
  TKlasse = class
  public
    class constructor Erster;
    class constructor Zweiter; // <- E2359
  end;

implementation

class constructor TKlasse.Erster;
begin
end;

class constructor TKlasse.Zweiter;
begin
end;

end.
