unit Cm.E2138;

// E2138 Invalid message parameter list
// Erwartet: E2138

interface

type
  TKlasse = class
  public
    procedure Nachricht(AWert: Integer); message 100; // <- E2138
  end;

implementation

procedure TKlasse.Nachricht(AWert: Integer);
begin
end;

end.
