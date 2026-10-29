unit Cm.E2551;

// E2551 There is no type parameterized methods of '%s' that can be used with these number of type parameters
// Erwartet: E2551

interface

type
  TKlasse = class
  public
    class procedure Machen<T>;
  end;

implementation

class procedure TKlasse.Machen<T>;
begin
end;

procedure Fall;
begin
  TKlasse.Machen<Integer, string>; // <- E2551
end;

end.
