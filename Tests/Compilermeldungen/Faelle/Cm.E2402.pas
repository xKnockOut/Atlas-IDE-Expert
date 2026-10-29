unit Cm.E2402;

// E2402 Constructing instance of abstract class '%s'
// Erwartet: E2402
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
  mObjekt := TAbstrakt.Create; // <- E2402
  mObjekt.Free;
end;

end.
