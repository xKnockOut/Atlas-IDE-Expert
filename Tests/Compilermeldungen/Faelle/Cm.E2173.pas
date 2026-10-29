unit Cm.E2173;

// E2173 Missing or invalid conditional symbol in '$%s' directive
// Erwartet: E2173

interface

implementation

{$IFDEF} // <- E2173
{$ENDIF}

end.
