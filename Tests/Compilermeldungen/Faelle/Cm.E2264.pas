unit Cm.E2264;

// E2264 Cannot have method resolutions for interface '%s'
// Erwartet: E2264

interface

type
  IEins = interface
    ['{6A0F0D5E-1C11-4B8E-9A43-3F1D4C2A2264}']
    procedure Machen;
  end;

  TKlasse = class(TInterfacedObject, IEins)
  private
    FEins: IEins;
    procedure Tun;
  public
    procedure IEins.Machen = Tun; // <- E2264
    property Eins: IEins read FEins implements IEins;
  end;

implementation

procedure TKlasse.Tun;
begin
end;

end.
