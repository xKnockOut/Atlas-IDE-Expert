unit Cm.E2096;

// E2096 Method identifier expected
// Erwartet: E2029
// Delphi 13 meldet hier E2029 statt E2096.
// Vermutung.

interface

type
  TBasis = class
  public
    procedure Machen;
  end;

implementation

procedure TBasis.; // <- E2029
begin
end;

end.
