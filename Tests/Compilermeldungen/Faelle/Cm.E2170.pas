unit Cm.E2170;

// E2170 Cannot override a non-virtual method
// Erwartet: E2170

interface

type
  TBasis = class
  public
    procedure Machen;
  end;

  TKind = class(TBasis)
  public
    procedure Machen; override; // <- E2170
  end;

implementation

procedure TBasis.Machen;
begin
end;

procedure TKind.Machen;
begin
end;

end.
