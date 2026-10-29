{$WARN UNKNOWN_CUSTOM_ATTRIBUTE ERROR}
unit Cm.E2289;

// E2289 Unresolved custom attribute %s
// Erwartet: E1074
// Delphi 13 meldet hier E1074 statt E2289.
// Unbekannte Attribute sind sonst nur W1074; E2289 vermutlich nur mit {$WARN
// UNKNOWN_CUSTOM_ATTRIBUTE ERROR}.

interface

type
  TMitAttribut = class
  public
    [GibtEsNichtAttribute] // <- E1074
    procedure Machen;
  end;

implementation

procedure TMitAttribut.Machen;
begin
end;

end.
