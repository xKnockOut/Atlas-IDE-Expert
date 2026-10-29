unit Cm.E2589;

// E2589 Helper type can not be declared in parameterized type context
// Erwartet: E2589

interface

type
  TBehaelter<T> = class
  public
    type
      THelfer = class helper for TObject // <- E2589
      end;
  end;

implementation

end.
