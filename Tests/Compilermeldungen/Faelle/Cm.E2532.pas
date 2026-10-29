unit Cm.E2532;

// E2532 Couldn't infer generic type argument from different argument types for method '%s'
// Erwartet: E2532

interface

type
  TKlasse = class
  public
    class procedure Paar<T>(A, B: T);
  end;

implementation

class procedure TKlasse.Paar<T>(A, B: T);
begin
end;

procedure Fall;
begin
  TKlasse.Paar(1, 'a'); // <- E2532
end;

end.
