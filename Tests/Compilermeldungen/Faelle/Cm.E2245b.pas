unit Cm.E2245b;

// E2245 Recursive include file %s
// Erwartet: -
// Gegenfall zu Cm.E2245 (#1379): Die Include-Datei bindet sich nur hinter einem
// Wächter selbst ein; dcc übersetzt das ohne Meldung.

interface

implementation

{$I Cm.E2245b.inc} // <- ohne Meldung

end.
