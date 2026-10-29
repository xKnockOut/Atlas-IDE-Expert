unit Cm.E2096;

// E2096 Method identifier expected
// Erwartet: E2096
// Vermutung.

interface

type
  TBasis = class
  public
    procedure Machen;
  end;

implementation

procedure TBasis.; // <- E2096
begin
end;

end.
