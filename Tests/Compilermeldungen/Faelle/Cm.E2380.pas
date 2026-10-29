unit Cm.E2380;

// E2380 Instance or class static method expected
// Erwartet: E2380
// Vermutung zum Code.

interface

type
  TRueckruf = procedure of object;

  TKlasse = class
  public
    class procedure Machen; static;
  end;

implementation

class procedure TKlasse.Machen;
begin
end;

procedure Fall;
var
  mRueckruf: TRueckruf;
begin
  mRueckruf := TKlasse.Machen; // <- E2380
  mRueckruf;
end;

end.
