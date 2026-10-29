unit Cm.E2265;

// E2265 Interface '%s' not mentioned in interface list
// Erwartet: E2265

interface

type
  IEins = interface
    procedure Machen;
  end;

  TKlasse = class(TInterfacedObject)
  private
    procedure Tun;
  public
    procedure IEins.Machen = Tun; // <- E2265
  end;

implementation

procedure TKlasse.Tun;
begin
end;

end.
