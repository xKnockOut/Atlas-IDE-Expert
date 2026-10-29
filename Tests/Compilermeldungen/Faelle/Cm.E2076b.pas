unit Cm.E2076b;

// E2076 This form of method call only allowed for class methods
// Erwartet: -
// Gegenprobe zu type-kind-required (#1370): in einer Methode eines Nachfahren ruft TBasis.Machen mit Self.

interface

type
  TBasis = class
  public
    procedure Machen;
  end;

  TKind = class(TBasis)
  public
    procedure Rufen;
  end;

implementation

procedure TBasis.Machen;
begin
end;

procedure TKind.Rufen;
begin
  TBasis.Machen;
end;

end.
