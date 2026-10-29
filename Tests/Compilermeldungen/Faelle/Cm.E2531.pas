unit Cm.E2531;

// E2531 Method '%s' requires explicit type argument(s)
// Erwartet: E2531

interface

type
  TKlasse = class
  public
    class function Neu<T>: T;
  end;

implementation

class function TKlasse.Neu<T>: T;
begin
  Result := Default(T);
end;

procedure Fall;
var
  mZahl: Integer;
begin
  mZahl := TKlasse.Neu; // <- E2531
end;

end.
