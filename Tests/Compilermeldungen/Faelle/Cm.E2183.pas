unit Cm.E2183;

// E2183 Dispid clause only allowed in OLE automation section
// Erwartet: E2185
// Delphi 13 meldet hier E2185 statt E2183.

interface

type
  TKlasse = class
  public
    procedure Machen; dispid 1; // <- E2185
  end;

implementation

procedure TKlasse.Machen;
begin
end;

end.
