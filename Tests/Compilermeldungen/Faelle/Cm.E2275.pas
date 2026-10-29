unit Cm.E2275;

// E2275 property attribute 'label' cannot be an empty string
// Erwartet: E2029
// Delphi 13 meldet hier E2029 statt E2275.
// Vermutung; aus der .NET-Zeit.

interface

type
  TKlasse = class
  private
    FWert: Integer;
  public
    property Wert: Integer read FWert label ''; // <- E2029
  end;

implementation

end.
