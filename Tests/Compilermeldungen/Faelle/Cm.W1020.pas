unit Cm.W1020;

// W1020 Constructing instance containing abstract method
// Erwartet: W1020

interface

implementation

type
  TAbstrakt = class
  public
    procedure Machen; virtual; abstract;
  end;

procedure Erzeugen;
var
  mObjekt: TAbstrakt;
begin
  mObjekt := TAbstrakt.Create; // <- W1020
  mObjekt.Free;
end;

end.
