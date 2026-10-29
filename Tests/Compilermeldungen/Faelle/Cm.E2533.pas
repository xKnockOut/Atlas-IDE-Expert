unit Cm.E2533;

// E2533 Virtual, dynamic and message methods cannot have type parameters
// Erwartet: E2533

interface

type
  TKlasse = class
  public
    procedure Machen<T>; virtual; // <- E2533
  end;

implementation

procedure TKlasse.Machen<T>;
begin
end;

end.
