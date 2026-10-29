unit Cm.E2352;

// E2352 Cannot override a final method
// Erwartet: E2352

interface

type
  TBasis = class
  public
    procedure Machen; virtual;
  end;

  TMitte = class(TBasis)
  public
    procedure Machen; override; final;
  end;

  TKind = class(TMitte)
  public
    procedure Machen; override; // <- E2352
  end;

implementation

procedure TBasis.Machen;
begin
end;

procedure TMitte.Machen;
begin
end;

procedure TKind.Machen;
begin
end;

end.
