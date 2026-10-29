unit Cm.E2075;

// E2075 This form of method call only allowed in methods of derived types
// Erwartet: E2076
// Delphi 13 meldet hier E2076 statt E2075.

interface

type
  TBasis = class
  public
    procedure Machen;
  end;

  TAndere = class
  public
    procedure Rufen;
  end;

implementation

procedure TBasis.Machen;
begin
end;

procedure TAndere.Rufen;
begin
  TBasis.Machen; // <- E2076
end;

end.
