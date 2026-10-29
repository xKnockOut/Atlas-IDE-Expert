unit Cm.E2275;

// E2275 property attribute 'label' cannot be an empty string
// Erwartet: E2275
// Vermutung; aus der .NET-Zeit.

interface

type
  TKlasse = class
  private
    FWert: Integer;
  public
    property Wert: Integer read FWert label ''; // <- E2275
  end;

implementation

end.
