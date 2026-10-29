unit Cm.W1203;

// W1203 XML comment has badly formed XML - A name was started with an invalid character
// Erwartet: W1203
// Schalter: --doc
// Nur mit XML-Dokumentation (--doc); dcc prüft nur Kommentare im interface-Teil.

interface

/// <summary>A < B</summary>
procedure Machen; // <- W1203

implementation

procedure Machen;
begin
end;

end.
