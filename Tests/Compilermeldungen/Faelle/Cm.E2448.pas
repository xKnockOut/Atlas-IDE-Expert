unit Cm.E2448;

// E2448 An attribute argument must be a constant expression, typeof expression or array constructor
// Erwartet: E2026
// Delphi 13 meldet hier E2026 statt E2448.

interface

var
  GWert: Integer;

type
  TMarkeAttribute = class(TCustomAttribute)
  public
    constructor Create(AWert: Integer);
  end;

  TKlasse = class
  public
    [TMarke(GWert)] // <- E2026
    procedure Machen;
  end;

implementation

constructor TMarkeAttribute.Create(AWert: Integer);
begin
end;

procedure TKlasse.Machen;
begin
end;

end.
