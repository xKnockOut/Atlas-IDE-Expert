unit Cm.E2211;

// E2211 Declaration of '%s' differs from declaration in interface '%s'
// Erwartet: E2211

interface

type
  IEins = interface
    procedure Machen(AWert: Integer);
  end;

  TKlasse = class(TInterfacedObject, IEins)
  public
    procedure Machen(AWert: string); // <- E2211
  end;

implementation

procedure TKlasse.Machen(AWert: string);
begin
end;

end.
