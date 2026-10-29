unit Cm.E2565;

// E2565 Cannot use parameterized or instantiated type as custom attribute
// Erwartet: E2565

interface

type
  TMarkeAttribute<T> = class(TCustomAttribute)
  end;

  TKlasse = class
  public
    [TMarke<Integer>] // <- E2565
    procedure Machen;
  end;

implementation

procedure TKlasse.Machen;
begin
end;

end.
