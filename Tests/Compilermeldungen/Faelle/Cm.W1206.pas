unit Cm.W1206;

// W1206 XML comment has cref attribute that could not be resolved
// Erwartet: W1206
// Schalter: --doc
// Nur mit XML-Dokumentation (--doc).

interface

implementation

/// <summary>Siehe <see cref="TGibtEsNicht"/></summary> // <- W1206
procedure Machen;
begin
end;

end.
