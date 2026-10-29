unit Cm.E2263;

// E2263 Implements getter cannot be dynamic or message method
// Erwartet: E2263

interface

type
  IEins = interface
    ['{6A0F0D5E-1C11-4B8E-9A43-3F1D4C2A2263}']
  end;

  TKlasse = class(TInterfacedObject, IEins)
  private
    function GetEins: IEins; dynamic;
  public
    property Eins: IEins read GetEins implements IEins; // <- E2263
  end;

implementation

function TKlasse.GetEins: IEins;
begin
  Result := nil;
end;

end.
