unit Cm.W1204;

// W1204 XML comment has badly formed XML - A name contained an invalid character
// Erwartet: W1205
// Delphi 13 meldet hier W1205 statt W1204.
// Schalter: --doc
// Nur mit XML-Dokumentation (--doc); dcc prüft nur Kommentare im interface-Teil.

interface

/// <sum(mary>Text</sum(mary>
procedure Machen; // <- W1205

implementation

procedure Machen;
begin
end;

end.
