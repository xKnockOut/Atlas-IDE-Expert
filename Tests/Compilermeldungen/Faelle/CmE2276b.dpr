library CmE2276b;

// E2276 Identifier '%s' cannot be exported
// Erwartet: E2276
// Vermutung (#1383): Für einen Typ meldet Delphi 13 E2276 (Cm.E2121b), eine Variable exportiert es (CmE2121c);
// eine echte Konstante hat keine Adresse.

const
  cZahl = 3;

exports
  cZahl; // <- E2276

begin
end.
