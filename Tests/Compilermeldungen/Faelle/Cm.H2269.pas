unit Cm.H2269;

// H2269 Overriding virtual method has lower visibility than base class
// Erwartet: H2269

interface

type
  TBasis = class
  public
    procedure Machen; virtual;
  end;

  TKind = class(TBasis)
  protected
    procedure Machen; override; // <- H2269
  end;

implementation

procedure TBasis.Machen;
begin
end;

procedure TKind.Machen;
begin
end;

end.
