unit Cm.H2505;

// H2505 'Self' is uninitialized. An inherited constructor must be called before entering a try block
// Erwartet: H2505

interface

type
  TRec = record
    FWert: Integer;
    constructor Create(AWert: Integer);
  end;

  TBasis = class
  public
    constructor Create;
  end;

  TKind = class(TBasis)
  public
    constructor Create;
  end;

implementation

constructor TRec.Create(AWert: Integer);
begin
  FWert := AWert;
end;

constructor TBasis.Create;
begin
  inherited Create;
end;

constructor TKind.Create;
begin
  try // <- H2505
    inherited Create;
  finally
  end;
end;

end.
