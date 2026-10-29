unit Cm.E2366;

// E2366 Global procedure or class static method expected
// Erwartet: E2009
// Delphi 13 meldet hier E2009 statt E2366.
// Vermutung zum Code.

interface

type
  TRueckruf = procedure;

  TKlasse = class
  public
    procedure Machen;
  end;

implementation

procedure TKlasse.Machen;
begin
end;

procedure Fall;
var
  mRueckruf: TRueckruf;
begin
  mRueckruf := TKlasse.Machen; // <- E2009
  mRueckruf;
end;

end.
