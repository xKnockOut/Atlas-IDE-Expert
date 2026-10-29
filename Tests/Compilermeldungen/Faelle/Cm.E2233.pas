unit Cm.E2233;

// E2233 Property '%s' inaccessible here
// Erwartet: E2147
// Delphi 13 meldet hier E2147 statt E2233.

interface

uses
  Cm.Hilfe.E2233;

type
  TKind = class(TBasis)
  public
    property Wert; // <- E2147
  end;

implementation

end.
