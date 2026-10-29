unit Cm.W1008;

// W1008 Integer and HRESULT interchanged
// Erwartet: W1008

interface

type
  IHr = interface
    ['{6A0F0D5E-1C11-4B8E-9A43-3F1D4C2A1001}']
    function Ausfuehren: HResult; stdcall;
  end;

  THr = class(TInterfacedObject, IHr)
    function Ausfuehren: Integer; stdcall; // <- W1008
  end;

implementation

function THr.Ausfuehren: Integer;
begin
  Result := 0;
end;

end.
