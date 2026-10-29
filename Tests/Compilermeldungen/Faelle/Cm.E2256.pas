unit Cm.E2256;

// E2256 Dispose not supported (nor necessary) for dynamic arrays
// Erwartet: E2256

interface

implementation

procedure Fall;
var
  mFeld: array of Integer;
begin
  mFeld := nil;
  Dispose(mFeld); // <- E2256
end;

end.
