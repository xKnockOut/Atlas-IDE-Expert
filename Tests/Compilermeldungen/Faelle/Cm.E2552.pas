unit Cm.E2552;

// E2552 CLASS or RECORD constraint and class type constraint cannot be specified together
// Erwartet: E2552

interface

uses
  System.Classes;

type
  TBehaelter<T: class, TStream> = class // <- E2552
  end;

implementation

end.
