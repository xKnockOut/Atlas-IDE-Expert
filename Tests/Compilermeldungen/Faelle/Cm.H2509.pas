unit Cm.H2509;

// H2509 Identifier conflicts with type parameters of container type
// Erwartet: H2509

interface

type
  TBehaelter<T> = class
  public
    procedure Machen<T>; // <- H2509
  end;

implementation

procedure TBehaelter<T>.Machen<T>;
begin
end;

end.
