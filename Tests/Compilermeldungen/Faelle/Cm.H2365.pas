unit Cm.H2365;

// H2365 Override method should match case of ancestor
// Erwartet: H2365

interface

type
  TBasis = class
  public
    procedure Machen; virtual;
  end;

  TKind = class(TBasis)
  public
    procedure MACHEN; override; // <- H2365
  end;

implementation

procedure TBasis.Machen;
begin
end;

procedure TKind.MACHEN;
begin
end;

end.
