unit Cm.E2075;

// E2075 This form of method call only allowed in methods of derived types
// Erwartet: E2075

interface

type
  TBasis = class
  public
    procedure Machen;
  end;

  TAndere = class
  public
    procedure Rufen;
  end;

implementation

procedure TBasis.Machen;
begin
end;

procedure TAndere.Rufen;
begin
  TBasis.Machen; // <- E2075
end;

end.
