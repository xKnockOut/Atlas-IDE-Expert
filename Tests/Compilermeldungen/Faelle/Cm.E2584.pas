unit Cm.E2584;

// E2584 Weak attribute only allowed on fields and variables of type class or interface
// Erwartet: E2584

interface

type
  TKlasse = class
  public
    [Weak] FZahl: Integer; // <- E2584
  end;

implementation

end.
