unit Cm.E2515;

// E2515 Type parameter '%s' is not compatible with type '%s'
// Erwartet: E2515

interface

uses
  System.Classes;

type
  TBehaelter<T: TStream> = class
  end;

implementation

var
  GBehaelter: TBehaelter<TObject>; // <- E2515

end.
