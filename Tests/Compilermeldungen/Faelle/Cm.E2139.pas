unit Cm.E2139;

// E2139 Illegal message method index
// Erwartet: E2139
// Vermutung: negative Nummer.

interface

type
  TKlasse = class
  public
    procedure Nachricht(var AWert); message -1; // <- E2139
  end;

implementation

procedure TKlasse.Nachricht(var AWert);
begin
end;

end.
