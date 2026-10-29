unit Cm.E2233;

// E2233 Property '%s' inaccessible here
// Erwartet: E2233

interface

uses
  Cm.Hilfe.E2233;

type
  TKind = class(TBasis)
  public
    property Wert; // <- E2233
  end;

implementation

end.
