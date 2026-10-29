unit Cm.E2508;

// E2508 type parameters not allowed on this type
// Erwartet: E2508

interface

type
  TZahl<T> = Integer; // <- E2508

implementation

end.
