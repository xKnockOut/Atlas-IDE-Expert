unit Cm.E2211;

// E2211 Declaration of '%s' differs from declaration in interface '%s'
// Erwartet: E2291
// Delphi 13 meldet hier E2291 statt E2211.

interface

type
  IEins = interface
    procedure Machen(AWert: Integer);
  end;

  TKlasse = class(TInterfacedObject, IEins)
  public
    procedure Machen(AWert: string); // <- E2291
  end;

implementation

procedure TKlasse.Machen(AWert: string);
begin
end;

end.
