unit Cm.W1204;

// W1204 XML comment has badly formed XML - A name contained an invalid character
// Erwartet: W1204
// Schalter: --doc
// Nur mit XML-Dokumentation (--doc); dcc prüft nur Kommentare im interface-Teil.

interface

/// <sum(mary>Text</sum(mary>
procedure Machen; // <- W1204

implementation

procedure Machen;
begin
end;

end.
