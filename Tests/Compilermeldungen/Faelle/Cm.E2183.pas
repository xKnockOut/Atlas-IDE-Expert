unit Cm.E2183;

// E2183 Dispid clause only allowed in OLE automation section
// Erwartet: E2183

interface

type
  TKlasse = class
  public
    procedure Machen; dispid 1; // <- E2183
  end;

implementation

procedure TKlasse.Machen;
begin
end;

end.
