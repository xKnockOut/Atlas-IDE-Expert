unit Cm.E2358;

// E2358 Class constructors not allowed in class helpers
// Erwartet: E2358
// Laut DccFaelle TR7 übersetzt dcc das; der Fall zeigt die aktuelle Lage.

interface

type
  THelfer = class helper for TObject
  public
    class constructor Create; // <- E2358
  end;

implementation

class constructor THelfer.Create;
begin
end;

end.
