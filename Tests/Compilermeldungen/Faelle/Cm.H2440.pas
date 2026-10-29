unit Cm.H2440;

// H2440 Inline method visibility is not lower or same visibility of accessing member
// Erwartet: H2440
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
  Result := FWert; // <- H2440
end;

end.
