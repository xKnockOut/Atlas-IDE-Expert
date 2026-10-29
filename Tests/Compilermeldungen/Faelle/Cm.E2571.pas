unit Cm.E2571;

// E2571 Type parameter '%s' doesn't have class or interface constraint
// Erwartet: E2571

interface

type
  TBehaelter<T> = class
  public
    procedure Machen(AWert: T);
  end;

implementation

procedure TBehaelter<T>.Machen(AWert: T);
begin
  AWert.Free; // <- E2571
end;

end.
