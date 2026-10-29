unit Cm.W1206;

// W1206 XML comment has cref attribute that could not be resolved
// Erwartet: W1206
// Schalter: --doc
// Nur mit XML-Dokumentation (--doc); dcc prüft nur Kommentare im interface-Teil.

interface

/// <summary>Siehe <see cref="TGibtEsNicht"/></summary>
procedure Machen; // <- W1206

implementation

procedure Machen;
begin
end;

end.
