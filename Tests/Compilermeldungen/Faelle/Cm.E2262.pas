unit Cm.E2262;

// E2262 Implements getter must be %s calling convention
// Erwartet: E2262

interface

type
  IEins = interface
    ['{6A0F0D5E-1C11-4B8E-9A43-3F1D4C2A2262}']
  end;

  TKlasse = class(TInterfacedObject, IEins)
  private
    function GetEins: IEins; stdcall;
  public
    property Eins: IEins read GetEins implements IEins; // <- E2262
  end;

implementation

function TKlasse.GetEins: IEins;
begin
  Result := nil;
end;

end.
