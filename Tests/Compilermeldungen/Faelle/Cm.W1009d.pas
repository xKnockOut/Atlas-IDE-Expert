unit Cm.W1009d;

// W1009 Redeclaration hides a member in the base class
// Erwartet: W1009
// Vermutung (#1383): statische Methode mit gleicher Signatur verdeckt die des Vorfahren.

interface

type
  TBasis = class
  public
    procedure Machen;
  end;

  TKind = class(TBasis)
  public
    procedure Machen; // <- W1009
  end;

implementation

procedure TBasis.Machen;
begin
end;

procedure TKind.Machen;
begin
end;

end.
