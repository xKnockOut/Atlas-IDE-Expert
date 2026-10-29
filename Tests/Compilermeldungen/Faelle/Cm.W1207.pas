unit Cm.W1207;

// W1207 XML comment has a param tag, but there is no parameter by that name
// Erwartet: W1207
// Schalter: --doc
// Nur mit XML-Dokumentation (--doc); dcc prüft nur Kommentare im interface-Teil.

interface

/// <summary>Macht etwas.</summary>
/// <param name="AFalsch">Gibt es nicht.</param>
procedure Machen(AWert: Integer); // <- W1207

implementation

procedure Machen(AWert: Integer);
begin
end;

end.
