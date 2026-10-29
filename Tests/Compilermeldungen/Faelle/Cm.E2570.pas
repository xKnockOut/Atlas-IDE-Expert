unit Cm.E2570;

// E2570 Local procedure in generic method or method of generic type is not supported
// Erwartet: E2570
// Delphi unterstützt das inzwischen womöglich.

interface

type
  TBehaelter<T> = class
  public
    procedure Machen;
  end;

implementation

procedure TBehaelter<T>.Machen;

  procedure Innen; // <- E2570
  begin
  end;

begin
  Innen;
end;

end.
