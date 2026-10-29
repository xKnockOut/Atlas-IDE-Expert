unit Cm.E2146;

// E2146 Default values must be of ordinal, pointer or small set type
// Erwartet: -
// Delphi 13 meldet hier nichts (Win32 und Win64).

interface

type
  TGrosseMenge = set of 0..100;

implementation

procedure Fall(AMenge: TGrosseMenge = [1]); // <- ohne Meldung
begin
end;

end.
