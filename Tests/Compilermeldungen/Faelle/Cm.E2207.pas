unit Cm.E2207;

// E2207 '%s' clause not allowed in interface type
// Erwartet: E2207

interface

type
  IMitProperty = interface
    function GetWert: Integer;
    property Wert: Integer read GetWert stored False; // <- E2207
  end;

implementation

end.
