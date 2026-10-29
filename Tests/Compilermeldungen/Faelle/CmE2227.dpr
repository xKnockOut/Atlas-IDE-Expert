program CmE2227;

// E2227 Imagebase is too high - program exceeds 2 GB limit
// Erwartet: E2227
// Plattform: Win32

{$IMAGEBASE $7FFF0000} // <- E2227

begin
end.
