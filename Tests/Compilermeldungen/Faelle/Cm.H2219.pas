unit Cm.H2219;

// H2219 Private symbol '%s' declared but never used
// Erwartet: H2219

interface

type
  TMitPrivat = class
  private
    FVergessen: Integer; // <- H2219
  end;

implementation

end.
