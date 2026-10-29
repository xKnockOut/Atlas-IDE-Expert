unit Cm.E2204;

// E2204 Improper GUID syntax
// Erwartet: E2204

interface

type
  IFalsch = interface
    ['{1234}'] // <- E2204
  end;

implementation

end.
