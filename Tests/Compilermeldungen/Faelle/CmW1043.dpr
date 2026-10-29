program CmW1043;

// W1043 Imagebase is not a multiple of 64k
// Erwartet: -
// Delphi 13 meldet hier nichts (Win32 und Win64).

{$IMAGEBASE $00412345} // <- ohne Meldung

begin
end.
