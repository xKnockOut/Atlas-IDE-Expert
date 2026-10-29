unit Cm.E2459;

// E2459 Class property accessor must not have field selector
// Erwartet: E2459

interface

uses
  System.Types;

type
  TKlasse = class
  private
    class var FPunkt: TPoint;
  public
    class property X: Integer read FPunkt.X; // <- E2459
  end;

implementation

end.
