unit Cm.E2301;

// E2301 Method '%s' with identical parameters and result type already exists
// Erwartet: E2252
// Delphi 13 meldet hier E2252 statt E2301.

interface

type
  TKlasse = class
  public
    procedure Machen(AWert: Integer); overload;
    procedure Machen(AZahl: Integer); overload; // <- E2252
  end;

implementation

procedure TKlasse.Machen(AWert: Integer);
begin
end;

end.
