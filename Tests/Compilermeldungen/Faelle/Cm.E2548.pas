unit Cm.E2548;

// E2548 Cannot take a class reference of parameterized type
// Erwartet: E2029
// Delphi 13 meldet hier E2029 statt E2548.
// Vermutung zum Code.

interface

type
  TBehaelter<T> = class
  end;

  TMeta = class of TBehaelter<T>; // <- E2029

implementation

end.
