unit Cm.W1201;

// W1201 XML comment has badly formed XML
// Erwartet: -
// Delphi 13 meldet hier nichts (Win32 und Win64).
// Schalter: --doc
// Nur mit XML-Dokumentation (--doc); dcc prüft nur Kommentare im interface-Teil.

interface

/// <summary>Offenes Element
procedure Machen; // <- ohne Meldung

implementation

procedure Machen;
begin
end;

end.
