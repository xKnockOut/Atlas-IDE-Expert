unit Cm.H2440;

// H2440 Inline method visibility is not lower or same visibility of accessing member
// Erwartet: -
// Delphi 13 meldet hier nichts (Win32 und Win64).
// Vermutung; Delphi meldet es womöglich nur in anderen Konstellationen.

interface

type
  TMitInline = class
  private
    FWert: Integer;
  public
    function Wert: Integer; inline;
  end;

implementation

function TMitInline.Wert: Integer;
begin
  Result := FWert; // <- ohne Meldung
end;

end.
