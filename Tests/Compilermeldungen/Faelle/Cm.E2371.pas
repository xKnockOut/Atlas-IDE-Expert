unit Cm.E2371;

// E2371 ABSTRACT and FINAL cannot be used together
// Erwartet: E2371

interface

type
  TKlasse = class
  public
    procedure Machen; virtual; abstract; final; // <- E2371
  end;

implementation

end.
