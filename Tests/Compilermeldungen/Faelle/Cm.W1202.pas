unit Cm.W1202;

// W1202 XML comment has badly formed XML - Reference to undefined entity
// Erwartet: -
// Delphi 13 meldet hier nichts (Win32 und Win64).
// Schalter: --doc
// Nur mit XML-Dokumentation (--doc); dcc prüft nur Kommentare im interface-Teil.

interface

/// <summary>A &unbekannt; B</summary>
procedure Machen; // <- ohne Meldung

implementation

procedure Machen;
begin
end;

end.
