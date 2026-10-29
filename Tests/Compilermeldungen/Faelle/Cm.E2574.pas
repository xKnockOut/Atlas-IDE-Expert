unit Cm.E2574;

// E2574 Instantiated type can not be used for TYPE'd type declaration
// Erwartet: E2574

interface

type
  TBehaelter<T> = class
  end;

  TEigen = type TBehaelter<Integer>; // <- E2574

implementation

end.
