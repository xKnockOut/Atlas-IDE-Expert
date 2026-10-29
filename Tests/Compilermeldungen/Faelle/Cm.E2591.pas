unit Cm.E2591;

// E2591 Only cdecl functions may use varargs
// Erwartet: E2591

interface

implementation

procedure Fall(AWert: Integer); stdcall; varargs; external 'cm.dll'; // <- E2591

end.
