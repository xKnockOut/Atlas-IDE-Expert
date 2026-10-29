unit Cm.W1203;

// W1203 XML comment has badly formed XML - A name was started with an invalid character
// Erwartet: -
// Delphi 13 meldet hier nichts (Win32 und Win64).
// Schalter: --doc
// Nur mit XML-Dokumentation (--doc); dcc prüft nur Kommentare im interface-Teil.

interface

/// <summary>A < B</summary>
procedure Machen; // <- ohne Meldung

implementation

procedure Machen;
begin
end;

end.
