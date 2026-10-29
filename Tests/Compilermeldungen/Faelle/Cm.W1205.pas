unit Cm.W1205;

// W1205 XML comment has badly formed XML - The character was expected
// Erwartet: W1205
// Schalter: --doc
// Nur mit XML-Dokumentation (--doc); dcc prüft nur Kommentare im interface-Teil.

interface

/// <summary a=>Text</summary>
procedure Machen; // <- W1205

implementation

procedure Machen;
begin
end;

end.
