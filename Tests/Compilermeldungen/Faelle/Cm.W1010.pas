unit Cm.W1010;

// W1010 Method hides virtual method of base type
// Erwartet: W1010

interface

type
  TBasis = class
  public
    procedure Machen; virtual;
  end;

  TKind = class(TBasis)
  public
    procedure Machen; // <- W1010
  end;

implementation

procedure TBasis.Machen;
begin
end;

procedure TKind.Machen;
begin
end;

end.
