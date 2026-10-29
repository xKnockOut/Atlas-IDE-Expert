unit Cm.E2076;

// E2076 This form of method call only allowed for class methods
// Erwartet: E2076

interface

type
  TBasis = class
  public
    procedure Machen;
  end;

implementation

procedure TBasis.Machen;
begin
end;

procedure Fall;
begin
  TBasis.Machen; // <- E2076
end;

end.
