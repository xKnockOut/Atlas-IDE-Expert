unit Cm.E2306;

// E2306 'Self' is initialized more than once
// Erwartet: E2306
// Vermutung; vermutlich nur bei Records mit Konstruktoren.

interface

type
  TBasis = class
  public
    constructor Create;
  end;

  TKind = class(TBasis)
  public
    constructor Create;
  end;

implementation

constructor TBasis.Create;
begin
end;

constructor TKind.Create;
begin
  inherited Create;
  inherited Create; // <- E2306
end;

end.
