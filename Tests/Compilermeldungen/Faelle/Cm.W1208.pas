unit Cm.W1208;

// W1208 Parameter has no matching param tag in the XML comment
// Erwartet: W1208
// Schalter: --doc
// Nur mit XML-Dokumentation (--doc).

interface

implementation

/// <summary>Macht etwas.</summary>
/// <param name="AErster">Erster.</param>
procedure Machen(AErster, AZweiter: Integer); // <- W1208
begin
end;

end.
