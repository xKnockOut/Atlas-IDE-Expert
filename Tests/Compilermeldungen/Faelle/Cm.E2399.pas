unit Cm.E2399;

// E2399 Namespace conflicts with unit name '%s'
// Erwartet: E2399
// Unit CmNs und Namensraum CmNs (Unit CmNs.Teil) gleichzeitig.

interface

implementation

uses
  CmNs, CmNs.Teil; // <- E2399

end.
