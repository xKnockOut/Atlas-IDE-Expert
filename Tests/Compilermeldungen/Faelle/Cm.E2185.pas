unit Cm.E2185;

// E2185 Overriding automated virtual method '%s' cannot specify a dispid
// Erwartet: E2185

interface

type
  TBasis = class
  automated
    procedure Machen; virtual; dispid 1;
  end;

  TKind = class(TBasis)
  automated
    procedure Machen; override; dispid 2; // <- E2185
  end;

implementation

procedure TBasis.Machen;
begin
end;

procedure TKind.Machen;
begin
end;

end.
