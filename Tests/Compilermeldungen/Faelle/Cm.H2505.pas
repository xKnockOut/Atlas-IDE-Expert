unit Cm.H2505;

// H2505 'Self' is uninitialized. An inherited constructor must be called before entering a try block
// Erwartet: -
// Delphi 13 meldet hier nichts (Win32 und Win64).

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
  try // <- ohne Meldung
    inherited Create;
  finally
  end;
end;

end.
