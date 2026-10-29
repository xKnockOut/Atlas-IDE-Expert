unit Cm.E2399;

// E2399 Namespace conflicts with unit name '%s'
// Erwartet: -
// Delphi 13 meldet hier nichts (Win32 und Win64).
// Unit CmNs und Namensraum CmNs (Unit CmNs.Teil) gleichzeitig.

interface

implementation

uses
  CmNs, CmNs.Teil; // <- ohne Meldung

end.
