unit Cm.E2017b;

// E2017 Pointer type required
// Erwartet: E2017
// Gegenprobe zu type-kind-required (#1370): ^ auf einem Objekt vor einem Punkt.

interface

type
  TKunde = class
  public
    Name: string;
  end;

implementation

procedure Fall(AKunde: TKunde);
begin
  AKunde^.Name := 'A'; // <- E2017
end;

end.
