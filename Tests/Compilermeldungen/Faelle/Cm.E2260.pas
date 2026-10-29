unit Cm.E2260;

// E2260 Implements clause not allowed together with index clause
// Erwartet: E2260

interface

type
  IEins = interface
    ['{6A0F0D5E-1C11-4B8E-9A43-3F1D4C2A2260}']
  end;

  TKlasse = class(TInterfacedObject, IEins)
  private
    function GetEins(AIndex: Integer): IEins;
  public
    property Eins: IEins index 1 read GetEins implements IEins; // <- E2260
  end;

implementation

function TKlasse.GetEins(AIndex: Integer): IEins;
begin
  Result := nil;
end;

end.
