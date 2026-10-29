unit Cm.W1201;

// W1201 XML comment has badly formed XML
// Erwartet: W1201
// Schalter: --doc
// Nur mit XML-Dokumentation (--doc); dcc prüft nur Kommentare im interface-Teil.

interface

/// <summary>Offenes Element
procedure Machen; // <- W1201

implementation

procedure Machen;
begin
end;

end.
