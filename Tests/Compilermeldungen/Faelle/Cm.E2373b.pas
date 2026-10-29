unit Cm.E2373b;

// E2373 Call to abstract method %s.%s
// Erwartet: E2373
// Vermutung (#1383): inherited ohne Methodennamen (Cm.E2373 mit Namen bleibt still).

interface

type
  TBasis = class
  public
    procedure Machen; virtual; abstract;
  end;

  TKind = class(TBasis)
  public
    procedure Machen; override;
  end;

implementation

procedure TKind.Machen;
begin
  inherited; // <- E2373
end;

end.
