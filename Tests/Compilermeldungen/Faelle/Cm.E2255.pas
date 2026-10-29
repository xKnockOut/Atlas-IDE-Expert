unit Cm.E2255;

// E2255 New not supported for dynamic arrays - use SetLength
// Erwartet: E2255

interface

implementation

procedure Fall;
var
  mFeld: array of Integer;
begin
  New(mFeld); // <- E2255
end;

end.
