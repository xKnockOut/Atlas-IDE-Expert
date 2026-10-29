unit Cm.E2402;

// E2402 Constructing instance of abstract class '%s'
// Erwartet: -
// Delphi 13 meldet hier nichts (Win32 und Win64).
// Delphi meldet hier womöglich nur W1020 oder gar nichts.

interface

type
  TAbstrakt = class abstract
  end;

implementation

procedure Fall;
var
  mObjekt: TAbstrakt;
begin
  mObjekt := TAbstrakt.Create; // <- ohne Meldung
  mObjekt.Free;
end;

end.
