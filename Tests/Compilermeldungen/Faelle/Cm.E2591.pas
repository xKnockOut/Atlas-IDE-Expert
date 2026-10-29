unit Cm.E2591;

// E2591 Only cdecl functions may use varargs
// Erwartet: -
// Delphi 13 meldet hier nichts (Win32 und Win64).

interface

implementation

procedure Fall(AWert: Integer); stdcall; varargs; external 'cm.dll'; // <- ohne Meldung

end.
