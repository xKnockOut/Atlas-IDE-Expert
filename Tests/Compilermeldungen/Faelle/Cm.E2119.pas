unit Cm.E2119;

// E2119 Structure field identifier expected
// Erwartet: E2003
// Delphi 13 meldet hier E2003 statt E2119.
// Plattform: Win32

interface

implementation

type
  TPunkt = record
    X, Y: Integer;
  end;

procedure Fall;
begin
  asm
    mov eax, [ebx].TPunkt.Z // <- E2003
  end;
end;

end.
