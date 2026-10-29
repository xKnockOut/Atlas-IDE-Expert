unit Cm.E2265;

// E2265 Interface '%s' not mentioned in interface list
// Erwartet: E2003
// Delphi 13 meldet hier E2003 statt E2265.

interface

type
  IEins = interface
    procedure Machen;
  end;

  TKlasse = class(TInterfacedObject)
  private
    procedure Tun;
  public
    procedure IEins.Machen = Tun; // <- E2003
  end;

implementation

procedure TKlasse.Tun;
begin
end;

end.
