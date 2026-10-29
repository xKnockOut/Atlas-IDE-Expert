unit Cm.E2382;

// E2382 Cannot call constructors using instance variables
// Erwartet: -
// Delphi 13 meldet hier nichts (Win32 und Win64).
// dcc erlaubt den Aufruf über eine Instanz in Methoden; außerhalb womöglich.

interface

type
  TKlasse = class
  public
    constructor Create;
  end;

implementation

constructor TKlasse.Create;
begin
end;

procedure Fall(AObjekt: TKlasse);
begin
  AObjekt.Create; // <- ohne Meldung
end;

end.
