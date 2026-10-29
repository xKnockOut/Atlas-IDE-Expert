unit Cm.E2056;

// E2056 String literals may have at most 255 elements
// Erwartet: -
// Delphi 13 meldet hier nichts (Win32 und Win64).
// Bis Delphi 11 ein Fehler; Delphi 12 und neuer erlauben längere Literale.

interface

implementation

procedure Fall;
var
  mText: string;
begin
  mText := 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'; // <- ohne Meldung
end;

end.
