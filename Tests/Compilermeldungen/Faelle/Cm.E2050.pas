unit Cm.E2050;

// E2050 Statements not allowed in interface part
// Erwartet: E2050

interface

var
  GZahl: Integer;

begin // <- E2050
  GZahl := 1;
end;

implementation

end.
