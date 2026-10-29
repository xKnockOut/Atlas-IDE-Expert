unit Cm.E2522;

// E2522 Operator '%s' can not convert to/from ancestor type
// Erwartet: E2029
// Delphi 13 meldet hier E2029 statt E2522.
// Klassenoperatoren gibt es nur unter ARC/.NET; womöglich kommt ein anderer Fehler.

interface

type
  TBasis = class
  end;

  TKind = class(TBasis)
  public
    class operator Implicit(A: TKind): TBasis; // <- E2029
  end;

implementation

class operator TKind.Implicit(A: TKind): TBasis;
begin
  Result := A;
end;

end.
