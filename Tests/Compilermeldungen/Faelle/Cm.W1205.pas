unit Cm.W1205;

// W1205 XML comment has badly formed XML - The character was expected
// Erwartet: -
// Delphi 13 meldet hier nichts (Win32 und Win64).
// Schalter: --doc
// Nur mit XML-Dokumentation (--doc); dcc prüft nur Kommentare im interface-Teil.

interface

/// <summary a=>Text</summary>
procedure Machen; // <- ohne Meldung

implementation

procedure Machen;
begin
end;

end.
