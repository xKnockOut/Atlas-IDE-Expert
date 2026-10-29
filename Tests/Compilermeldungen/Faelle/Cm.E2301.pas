unit Cm.E2301;

// E2301 Method '%s' with identical parameters and result type already exists
// Erwartet: E2301

interface

type
  TKlasse = class
  public
    procedure Machen(AWert: Integer); overload;
    procedure Machen(AZahl: Integer); overload; // <- E2301
  end;

implementation

procedure TKlasse.Machen(AWert: Integer);
begin
end;

end.
