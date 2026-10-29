unit Cm.E1019;

// E1019 For loop control variable must be simple local variable
// Erwartet: E1019
// Laufvariable ist eine lokale Variable der umgebenden Routine.

interface

implementation

procedure Aussen;
var
  mIndex: Integer;

  procedure Innen;
  begin
    for mIndex := 0 to 2 do // <- E1019
      ;
  end;

begin
  Innen;
end;

end.
