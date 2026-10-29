unit Cm.E2539;

// E2539 Missing implementation for abstract method '%s.%s'
// Erwartet: E2539
// Vermutung; .NET.

interface

type
  TAbstrakt = class
  public
    procedure Machen; virtual; abstract;
  end;

  TKind = class(TAbstrakt)
  end;

  TVersiegelt = class sealed(TAbstrakt) // <- E2539
  end;

implementation

end.
