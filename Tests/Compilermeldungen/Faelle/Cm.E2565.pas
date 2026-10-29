unit Cm.E2565;

// E2565 Cannot use parameterized or instantiated type as custom attribute
// Erwartet: W1074
// Delphi 13 meldet hier W1074 statt E2565.

interface

type
  TMarkeAttribute<T> = class(TCustomAttribute)
  end;

  TKlasse = class
  public
    [TMarke<Integer>] // <- W1074
    procedure Machen;
  end;

implementation

procedure TKlasse.Machen;
begin
end;

end.
