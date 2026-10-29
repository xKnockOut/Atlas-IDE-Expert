unit Cm.E2210;

// E2210 '%s' directive not allowed in in interface type
// Erwartet: E2210

interface

type
  IMitDirektive = interface
    procedure Machen; virtual; // <- E2210
  end;

implementation

end.
