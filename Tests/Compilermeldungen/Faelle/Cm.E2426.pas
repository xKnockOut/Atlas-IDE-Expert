unit Cm.E2426;

// E2426 Inline function must not have asm block
// Erwartet: E2426
// Plattform: Win32

interface

implementation

function Fall: Integer; inline; // <- E2426
asm
  mov eax, 1
end;

end.
