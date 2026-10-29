unit Cm.W1207;

// W1207 XML comment has a param tag, but there is no parameter by that name
// Erwartet: W1207
// Schalter: --doc
// Nur mit XML-Dokumentation (--doc).

interface

implementation

/// <summary>Macht etwas.</summary>
/// <param name="AFalsch">Gibt es nicht.</param> // <- W1207
procedure Machen(AWert: Integer);
begin
end;

end.
