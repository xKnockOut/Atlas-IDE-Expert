unit Cm.E2553;

// E2553 Class type constraint cannot be specified more than once
// Erwartet: E2553

interface

uses
  System.Classes;

type
  TBehaelter<T: TStream, TComponent> = class // <- E2553
  end;

implementation

end.
